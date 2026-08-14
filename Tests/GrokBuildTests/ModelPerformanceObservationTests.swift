import Foundation
import XCTest
@testable import GrokBuild

final class ModelPerformanceObservationTests: XCTestCase {
    func testWorkloadClassifierKeepsComparableClassesSeparate() throws {
        XCTAssertEqual(
            ModelPerformanceObservation.workloadClass(
                snapshot: snapshot(tools: .init(succeeded: 0, failed: 0, cancelled: 0, unknown: 0)),
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                conversationTurnOrdinal: 1
            ),
            .noTool
        )
        XCTAssertEqual(
            ModelPerformanceObservation.workloadClass(
                snapshot: snapshot(tools: .init(succeeded: 3, failed: 0, cancelled: 0, unknown: 0)),
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                conversationTurnOrdinal: 1
            ),
            .orderedMultiTool
        )
        XCTAssertEqual(
            ModelPerformanceObservation.workloadClass(
                snapshot: snapshot(tools: .init(succeeded: 3, failed: 0, cancelled: 0, unknown: 0)),
                observedParallelToolExecution: true,
                recoveryOpportunityObserved: false,
                conversationTurnOrdinal: 1
            ),
            .parallelMultiTool
        )
        XCTAssertEqual(
            ModelPerformanceObservation.workloadClass(
                snapshot: snapshot(
                    workers: [worker("a"), worker("b")],
                    coordination: .init(
                        requestedChildCount: 2,
                        spawnedChildCount: 2,
                        finishedChildCount: 2,
                        maximumUsefulConcurrency: 2,
                        childToolCallCount: 2,
                        unresolvedIdentityCount: 0,
                        stopToSettleMilliseconds: nil,
                        parentTotalTokens: 10,
                        childTotalTokens: 4
                    )
                ),
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                conversationTurnOrdinal: 1
            ),
            .twoChildCoordination
        )
        XCTAssertEqual(
            ModelPerformanceObservation.workloadClass(
                snapshot: snapshot(turnCount: 2),
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                conversationTurnOrdinal: 2
            ),
            .longHorizonContinuation
        )
        XCTAssertEqual(
            ModelPerformanceObservation.workloadClass(
                snapshot: snapshot(tools: .init(succeeded: 1, failed: 1, cancelled: 0, unknown: 0)),
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: true,
                conversationTurnOrdinal: 2
            ),
            .recovery,
            "recovery remains its own class instead of being averaged into continuation"
        )
        XCTAssertNil(
            ModelPerformanceObservation.workloadClass(
                snapshot: snapshot(tools: .init(succeeded: 1, failed: 0, cancelled: 0, unknown: 0)),
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                conversationTurnOrdinal: 1
            ),
            "unsupported one-tool turns are ignored rather than assigned a fake comparable class"
        )
        XCTAssertNil(
            ModelPerformanceObservation.workloadClass(
                snapshot: snapshot(workers: [worker("a"), worker("b"), worker("c")]),
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                conversationTurnOrdinal: 1
            ),
            "three-child runs stay out of the frozen two-child cohort"
        )
    }

    func testRecordRequiresSettledAuthoritativeIdentityAndPersistsContinuation() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let route = nativeRoute()

        XCTAssertNil(ModelPerformanceObservationStore.record(
            snapshot: snapshot(isSettled: false),
            route: route,
            firstChunkLatencyMilliseconds: 800,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            defaults: defaults
        ))
        XCTAssertTrue(ModelPerformanceObservationStore.load(defaults: defaults).isEmpty)

        let first = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(backend: "same-backend"),
            route: route,
            firstChunkLatencyMilliseconds: 800,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            observedAt: Date(timeIntervalSince1970: 10),
            defaults: defaults
        ))
        XCTAssertEqual(first.workloadClass, .noTool)
        XCTAssertEqual(first.firstChunkLatencyMilliseconds, 800)

        let second = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(backend: "same-backend", turnCount: 2),
            route: route,
            firstChunkLatencyMilliseconds: nil,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            conversationTurnOrdinal: 2,
            observedAt: Date(timeIntervalSince1970: 20),
            defaults: defaults
        ))
        XCTAssertEqual(second.workloadClass, .longHorizonContinuation)
        XCTAssertNil(second.firstChunkLatencyMilliseconds, "missing local measurement stays missing")
        XCTAssertEqual(ModelPerformanceObservationStore.load(defaults: defaults).count, 2)
    }

    func testProviderInternalTurnCountDoesNotInventConversationContinuation() throws {
        XCTAssertEqual(
            ModelPerformanceObservation.workloadClass(
                snapshot: snapshot(turnCount: 7),
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                conversationTurnOrdinal: 1
            ),
            .noTool
        )
    }

    func testConversationOrdinalUsesCompletedCheckpointsAndExactBackendPromptIndex() {
        let completed = AssistantTurnCheckpoint(snapshot: snapshot(backend: "same-backend"), requestedToolFamilies: [])
        let completedAfterRelaunch = AssistantTurnCheckpoint(
            snapshot: snapshot(backend: "same-backend", processGeneration: 2),
            requestedToolFamilies: []
        )
        let stopped = AssistantTurnCheckpoint(
            snapshot: snapshot(backend: "same-backend", outcome: .userStopped),
            requestedToolFamilies: []
        )
        let otherBackend = AssistantTurnCheckpoint(snapshot: snapshot(backend: "other-backend"), requestedToolFamilies: [])

        XCTAssertEqual(
            ModelPerformanceConversationOrdinal.value(
                priorCheckpoints: [completed],
                backendSessionID: "same-backend"
            ),
            2,
            "a restored completion for the exact backend advances the user-conversation ordinal"
        )
        XCTAssertEqual(
            ModelPerformanceConversationOrdinal.value(
                priorCheckpoints: [otherBackend],
                backendSessionID: "same-backend"
            ),
            1,
            "a fork or different backend starts its own ordinal"
        )
        XCTAssertEqual(
            ModelPerformanceConversationOrdinal.value(
                priorCheckpoints: [stopped],
                backendSessionID: "same-backend"
            ),
            1,
            "a user-stopped attempt is not an authoritative completed conversation turn"
        )
        XCTAssertEqual(
            ModelPerformanceConversationOrdinal.value(
                priorCheckpoints: [stopped],
                backendSessionID: "same-backend",
                backendPromptIndex: 1
            ),
            2,
            "the backend prompt index truthfully identifies a later same-backend prompt even after a stopped attempt"
        )
        XCTAssertEqual(
            ModelPerformanceConversationOrdinal.value(
                priorCheckpoints: [completed, completed],
                backendSessionID: "same-backend"
            ),
            2,
            "duplicate persistence of one request in one generation does not invent an extra turn"
        )
        XCTAssertEqual(
            ModelPerformanceConversationOrdinal.value(
                priorCheckpoints: [completed, completedAfterRelaunch],
                backendSessionID: "same-backend"
            ),
            3,
            "a reused request ID in a later process generation remains a distinct completion"
        )
        XCTAssertEqual(
            ModelPerformanceConversationOrdinal.value(
                priorCheckpoints: [],
                backendSessionID: "same-backend",
                backendPromptIndex: 4
            ),
            5,
            "an authoritative restored-backend prompt index preserves same-backend context in a new local tab without trusting provider model-cycle counts"
        )
        XCTAssertEqual(
            ModelPerformanceConversationOrdinal.value(
                priorCheckpoints: [completed, completedAfterRelaunch],
                backendSessionID: "same-backend",
                backendPromptIndex: 0
            ),
            3,
            "a stale or reset backend prompt index cannot lower durable checkpoint truth"
        )
    }

    func testRouteBucketsKeepOpenRouterPinnedAndAutoUnproven() {
        XCTAssertEqual(ModelPerformanceObservation.RouteKind.from(nativeRoute()), .nativeXAI)
        XCTAssertEqual(ModelPerformanceObservation.RouteKind.from(route(.directProvider)), .directProvider)
        XCTAssertEqual(ModelPerformanceObservation.RouteKind.from(route(.localEndpoint)), .localEndpoint)
        let pinned = route(.brokeredOpenRouter, modelID: "openai/gpt-4.1-mini", pinned: true)
        let automatic = route(.brokeredOpenRouter, modelID: "openrouter/auto", pinned: false)
        XCTAssertEqual(ModelPerformanceObservation.RouteKind.from(pinned), .pinnedOpenRouter)
        XCTAssertEqual(ModelPerformanceObservation.RouteKind.from(automatic), .openRouterAuto)
        XCTAssertFalse(pinned.servingProviderIsProven)
        XCTAssertFalse(automatic.servingProviderIsProven)
    }

    func testExactRoutesDoNotCollapseInsideOneRouteKind() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        for (index, endpoint) in ["http://localhost:11434/v1", "http://localhost:1234/v1"].enumerated() {
            _ = ModelPerformanceObservationStore.record(
                snapshot: snapshot(backend: "route-\(index)"),
                route: route(
                    .directProvider,
                    providerName: "same-provider",
                    endpointHost: "localhost",
                    endpointRouteIdentity: endpoint,
                    modelID: "same-model"
                ),
                firstChunkLatencyMilliseconds: 100 + index,
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                recoverySucceeded: false,
                defaults: defaults
            )
        }
        let summaries = ModelPerformanceObservationStore.summaries(defaults: defaults)
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(Set(summaries.compactMap(\.routeIdentity.endpointIdentity)), [
            "http://localhost:11434/v1",
            "http://localhost:1234/v1",
        ])
    }

    func testCustomRouteUsesProviderModelAsStableCohortIdentity() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let brokeredRoute = route(
            .brokeredOpenRouter,
            providerName: "OpenRouter",
            endpointHost: "openrouter.ai",
            endpointRouteIdentity: "https://openrouter.ai/api/v1",
            modelID: "openai/gpt-4.1-mini"
        )
        let configuredKeyReceipt = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(
                backend: "configured-key",
                processModel: "openai-gpt-4.1-mini",
                modelUsage: [
                    .init(
                        modelID: "openai-gpt-4.1-mini",
                        inputTokens: 100,
                        outputTokens: 20,
                        totalTokens: 120,
                        cachedReadTokens: 50,
                        reasoningTokens: 0,
                        modelCalls: 1,
                        apiDurationMilliseconds: 300,
                        costUsdTicks: nil
                    ),
                ]
            ),
            route: brokeredRoute,
            firstChunkLatencyMilliseconds: 100,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            defaults: defaults
        ))
        let providerModelReceipt = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(backend: "provider-model", processModel: "openai/gpt-4.1-mini"),
            route: brokeredRoute,
            firstChunkLatencyMilliseconds: 110,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            defaults: defaults
        ))

        XCTAssertEqual(configuredKeyReceipt.modelID, "openai/gpt-4.1-mini")
        XCTAssertEqual(configuredKeyReceipt.usageAttribution, .matchedPerModelReceipt)
        XCTAssertEqual(configuredKeyReceipt.totalTokens, 120)
        XCTAssertEqual(providerModelReceipt.modelID, "openai/gpt-4.1-mini")
        let summary = try XCTUnwrap(ModelPerformanceObservationStore.summaries(defaults: defaults).first)
        XCTAssertEqual(summary.modelID, "openai/gpt-4.1-mini")
        XCTAssertEqual(summary.sampleCount, 2)

        let nativeReceipt = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(backend: "native-build", processModel: "grok-4.6-build"),
            route: nativeRoute(),
            firstChunkLatencyMilliseconds: 120,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            defaults: defaults
        ))
        XCTAssertEqual(nativeReceipt.modelID, "grok-4.6-build")

        let fallbackReceipt = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(backend: "custom-fallback", processModel: "custom-selector"),
            route: route(.directProvider, modelID: ""),
            firstChunkLatencyMilliseconds: 130,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            defaults: defaults
        ))
        XCTAssertEqual(fallbackReceipt.modelID, "custom-selector")
    }

    func testLegacyCustomSelectorRowsCanonicalizeInsideTheRetentionBoundary() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let brokeredRoute = route(
            .brokeredOpenRouter,
            providerName: "OpenRouter",
            endpointHost: "openrouter.ai",
            endpointRouteIdentity: "https://openrouter.ai/api/v1",
            modelID: "openai/gpt-4.1-mini"
        )
        let legacyRows = (0..<41).map { index in
            customObservation(
                modelID: index.isMultiple(of: 2)
                    ? "openai-gpt-4.1-mini"
                    : "openai/gpt-4.1-mini",
                route: brokeredRoute,
                timestamp: TimeInterval(index)
            )
        }
        defaults.set(
            try JSONEncoder().encode(legacyRows),
            forKey: ModelPerformanceObservationStore.storageKey
        )

        _ = ModelPerformanceObservationStore.record(
            snapshot: snapshot(backend: "new-canonical", processModel: "openai-gpt-4.1-mini"),
            route: brokeredRoute,
            firstChunkLatencyMilliseconds: 100,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            observedAt: Date(timeIntervalSince1970: 42),
            defaults: defaults
        )

        XCTAssertEqual(ModelPerformanceObservationStore.load(defaults: defaults).count, 40)
        let summary = try XCTUnwrap(ModelPerformanceObservationStore.summaries(defaults: defaults).first)
        XCTAssertEqual(summary.modelID, "openai/gpt-4.1-mini")
        XCTAssertEqual(summary.sampleCount, 40)
    }

    func testExactRouteIdentityPreservesCaseSensitivePath() {
        let uppercasePath = ModelPerformanceObservation.RouteIdentity(route: route(
            .directProvider,
            endpointHost: "example.test",
            endpointRouteIdentity: "https://example.test/Proxy/v1",
            modelID: "same-model"
        ))
        let lowercasePath = ModelPerformanceObservation.RouteIdentity(route: route(
            .directProvider,
            endpointHost: "example.test",
            endpointRouteIdentity: "https://example.test/proxy/v1",
            modelID: "same-model"
        ))

        XCTAssertNotEqual(uppercasePath.stableKey, lowercasePath.stableKey)
        XCTAssertEqual(uppercasePath.endpointIdentity, "https://example.test/Proxy/v1")
        XCTAssertEqual(lowercasePath.endpointIdentity, "https://example.test/proxy/v1")
    }

    func testMixedModelUsageUsesOnlyTheMatchedReceipt() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let receipt = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(
                workers: [worker("a"), worker("b")],
                modelUsage: [
                    .init(modelID: "grok-4.6", inputTokens: 100, outputTokens: 20, totalTokens: 120, cachedReadTokens: 5, reasoningTokens: 7, modelCalls: 1, apiDurationMilliseconds: 300, costUsdTicks: 90),
                    .init(modelID: "worker-model", inputTokens: 500, outputTokens: 50, totalTokens: 550, cachedReadTokens: nil, reasoningTokens: nil, modelCalls: 2, apiDurationMilliseconds: 900, costUsdTicks: 400),
                ]
            ),
            route: nativeRoute(),
            firstChunkLatencyMilliseconds: 50,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            defaults: defaults
        ))
        XCTAssertEqual(receipt.usageAttribution, .matchedPerModelReceipt)
        XCTAssertEqual(receipt.totalTokens, 120)
        XCTAssertEqual(receipt.costUsdTicks, 90)
    }

    func testNativeBuildAliasMatchesParentWithoutWorkers() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let receipt = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(modelUsage: [
                .init(modelID: "grok-4.6-build", inputTokens: 10, outputTokens: 2, totalTokens: 12, cachedReadTokens: 0, reasoningTokens: 1, modelCalls: 1, apiDurationMilliseconds: 100, costUsdTicks: 20),
            ]),
            route: nativeRoute(),
            firstChunkLatencyMilliseconds: 50,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            defaults: defaults
        ))
        XCTAssertEqual(receipt.usageAttribution, .matchedPerModelReceipt)
        XCTAssertEqual(receipt.totalTokens, 12)
        XCTAssertEqual(receipt.costUsdTicks, 20)
    }

    func testNativeBuildAliasMatchesParentInsideWorkerUsageMap() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let receipt = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(
                workers: [worker("a"), worker("b")],
                modelUsage: [
                    .init(modelID: "grok-4.6-build", inputTokens: 10, outputTokens: 2, totalTokens: 12, cachedReadTokens: 0, reasoningTokens: 1, modelCalls: 1, apiDurationMilliseconds: 100, costUsdTicks: 20),
                    .init(modelID: "worker-model", inputTokens: 50, outputTokens: 5, totalTokens: 55, cachedReadTokens: nil, reasoningTokens: nil, modelCalls: 2, apiDurationMilliseconds: 300, costUsdTicks: 80),
                ]
            ),
            route: nativeRoute(),
            firstChunkLatencyMilliseconds: 50,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            defaults: defaults
        ))
        XCTAssertEqual(receipt.usageAttribution, .matchedPerModelReceipt)
        XCTAssertEqual(receipt.totalTokens, 12)
    }

    func testMixedModelUsageWithoutParentMatchStaysMissing() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let receipt = try XCTUnwrap(ModelPerformanceObservationStore.record(
            snapshot: snapshot(
                workers: [worker("a"), worker("b")],
                modelUsage: [.init(modelID: "worker-model", inputTokens: 500, outputTokens: 50, totalTokens: 550, cachedReadTokens: nil, reasoningTokens: nil, modelCalls: 2, apiDurationMilliseconds: 900, costUsdTicks: 400)]
            ),
            route: nativeRoute(),
            firstChunkLatencyMilliseconds: 50,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            defaults: defaults
        ))
        XCTAssertEqual(receipt.usageAttribution, .unavailableForMixedModelTurn)
        XCTAssertNil(receipt.totalTokens)
        XCTAssertNil(receipt.costUsdTicks)
    }

    func testCompletedTurnDoesNotInventRecoverySuccess() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = ModelPerformanceObservationStore.record(
            snapshot: snapshot(tools: .init(succeeded: 1, failed: 1, cancelled: 0, unknown: 0)),
            route: nativeRoute(),
            firstChunkLatencyMilliseconds: 50,
            observedParallelToolExecution: false,
            recoveryOpportunityObserved: true,
            recoverySucceeded: false,
            defaults: defaults
        )
        XCTAssertEqual(try XCTUnwrap(ModelPerformanceObservationStore.summaries(defaults: defaults).first?.recoveryRate), 0)
    }

    func testRecoveryEvidenceRequiresTypedRetryAndKeepsChildRecoveryUnproven() {
        let failed = liveTool(id: "failed", status: .failed)
        let retry = liveTool(id: "retry", status: .succeeded, retryOf: "failed")
        let settledFailure = failed.settled(against: [failed, retry])
        XCTAssertEqual(
            ModelPerformanceRecoveryEvidence.make(parentTools: [settledFailure, retry], workers: []),
            .init(opportunityObserved: true, succeeded: true)
        )
        XCTAssertEqual(
            ModelPerformanceRecoveryEvidence.make(parentTools: [failed], workers: []),
            .init(opportunityObserved: true, succeeded: false),
            "an abandoned failure is an unrecovered opportunity, not an attempted retry"
        )
        let failedChild = ChildToolReceipt(
            id: "child-failed",
            title: "Child tool",
            status: .failed,
            mcpReceiptRole: nil,
            qualifiedToolName: nil,
            discoveredQualifiedToolNames: []
        )
        XCTAssertEqual(
            ModelPerformanceRecoveryEvidence.make(
                parentTools: [],
                workers: [worker("child", receipts: [failedChild])]
            ),
            .init(opportunityObserved: true, succeeded: false),
            "child retry success stays unproven until ACP exposes child retry correlation"
        )
    }

    func testSummaryUsesMeasuredSamplesOnlyAndKeepsRatesTruthful() throws {
        let values = [
            observation(
                timestamp: 1,
                firstChunk: 100,
                apiDuration: 900,
                totalTokens: 1_000,
                costTicks: nil,
                outcome: .completed,
                unresolvedWorkers: 0,
                recoveryOpportunityObserved: true,
                recoverySucceeded: true
            ),
            observation(
                timestamp: 2,
                firstChunk: nil,
                apiDuration: 1_100,
                totalTokens: 3_000,
                costTicks: 25_000_000,
                outcome: .failed,
                unresolvedWorkers: 1,
                recoveryOpportunityObserved: true,
                recoverySucceeded: false
            ),
            observation(
                timestamp: 3,
                firstChunk: 300,
                apiDuration: nil,
                totalTokens: 2_000,
                costTicks: nil,
                outcome: .completed,
                unresolvedWorkers: 0,
                recoveryOpportunityObserved: false,
                recoverySucceeded: false
            ),
        ]
        let summary = try XCTUnwrap(ModelPerformanceObservationSummary.make(from: values))
        XCTAssertEqual(summary.sampleCount, 3)
        XCTAssertEqual(summary.firstChunkLatency, .init(sampleCount: 2, median: 200, minimum: 100, maximum: 300))
        XCTAssertEqual(summary.providerAPIDuration, .init(sampleCount: 2, median: 1_000, minimum: 900, maximum: 1_100))
        XCTAssertEqual(summary.totalTokens, .init(sampleCount: 3, median: 2_000, minimum: 1_000, maximum: 3_000))
        XCTAssertEqual(summary.costUsdTicks, .init(sampleCount: 1, median: 25_000_000, minimum: 25_000_000, maximum: 25_000_000))
        XCTAssertEqual(summary.completionRate, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(summary.recoveryRate), 0.5, accuracy: 0.0001)
        XCTAssertEqual(summary.unresolvedWorkerRate, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testStoreBoundsEachCohortAndClearIsIsolated() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("credential-kept", forKey: "providerCredentialSentinel")
        defaults.set("transcript-kept", forKey: "transcriptSentinel")
        for index in 0..<(ModelPerformanceObservationStore.maximumObservationsPerCohort + 5) {
            _ = ModelPerformanceObservationStore.record(
                snapshot: snapshot(backend: "backend-\(index)"),
                route: nativeRoute(),
                firstChunkLatencyMilliseconds: index,
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                recoverySucceeded: false,
                observedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                defaults: defaults
            )
        }
        let retained = ModelPerformanceObservationStore.load(defaults: defaults)
        XCTAssertEqual(retained.count, ModelPerformanceObservationStore.maximumObservationsPerCohort)
        XCTAssertEqual(retained.first?.firstChunkLatencyMilliseconds, 5)

        ModelPerformanceObservationStore.clear(defaults: defaults)
        XCTAssertTrue(ModelPerformanceObservationStore.load(defaults: defaults).isEmpty)
        XCTAssertEqual(defaults.string(forKey: "providerCredentialSentinel"), "credential-kept")
        XCTAssertEqual(defaults.string(forKey: "transcriptSentinel"), "transcript-kept")
    }

    func testConcurrentSessionSettlementDoesNotLoseObservations() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            _ = ModelPerformanceObservationStore.record(
                snapshot: snapshot(backend: "concurrent-backend-\(index)"),
                route: nativeRoute(),
                firstChunkLatencyMilliseconds: index,
                observedParallelToolExecution: false,
                recoveryOpportunityObserved: false,
                recoverySucceeded: false,
                observedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                defaults: defaults
            )
        }
        XCTAssertEqual(ModelPerformanceObservationStore.load(defaults: defaults).count, 20)
    }

    func testCorruptLocalDataFailsClosedWithoutAQualityClaim() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: ModelPerformanceObservationStore.storageKey)
        XCTAssertTrue(ModelPerformanceObservationStore.load(defaults: defaults).isEmpty)
        XCTAssertTrue(ModelPerformanceObservationStore.summaries(defaults: defaults).isEmpty)
    }

    func testSettlementAndModelsPaneWiringStayBounded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let storeSource = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        let settledAnchor = try XCTUnwrap(storeSource.range(of: "let settledSnapshot = makeRunEvidenceSnapshot(completion: completion)"))
        let settledWindow = String(storeSource[settledAnchor.lowerBound...].prefix(5_000))
        XCTAssertTrue(settledWindow.contains("ModelPerformanceObservationStore.record("))
        XCTAssertTrue(settledWindow.contains("routeContractsByProcessGeneration"))
        XCTAssertTrue(storeSource.contains("currentTurnFirstChunkLatencyMilliseconds"))
        XCTAssertTrue(storeSource.contains("currentTurnObservedParallelToolExecution"))
        XCTAssertTrue(settledWindow.contains("ModelPerformanceRecoveryEvidence.make("))
        XCTAssertTrue(settledWindow.contains("ModelPerformanceConversationOrdinal.value("))
        XCTAssertTrue(settledWindow.contains("conversationTurnOrdinal: conversationTurnOrdinal"))

        let paneSource = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Views/Settings/CustomModelsSettingsPane.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(paneSource.contains("Observed on this Mac"))
        XCTAssertTrue(paneSource.contains("Clear local observations"))
        XCTAssertTrue(paneSource.contains("Provider credentials, model configuration, Grok history, and transcripts are unchanged"))
        XCTAssertFalse(paneSource.contains("Button(\"Use best model"))
        XCTAssertFalse(paneSource.contains("ModelPerformanceObservationStore.autoSelect"))
    }

    private func snapshot(
        backend: String = "backend",
        processGeneration: UInt64 = 1,
        isSettled: Bool = true,
        processModel: String = "grok-4.6",
        workers: [RunEvidenceSnapshot.Worker] = [],
        coordination: RunEvidenceSnapshot.CoordinationMetrics? = nil,
        tools: RunEvidenceSnapshot.ToolSummary = .init(succeeded: 0, failed: 0, cancelled: 0, unknown: 0),
        turnCount: Int? = 1,
        modelUsage: [ModelUsageReceipt] = [],
        outcome: ChatStore.TurnOutcome = .completed
    ) -> RunEvidenceSnapshot {
        RunEvidenceSnapshot(
            binding: .init(
                localTabID: UUID(),
                workspaceID: UUID(),
                backendSessionID: backend,
                processGeneration: processGeneration,
                requestID: "request",
                isSettled: isSettled
            ),
            goalSummary: nil,
            plan: [],
            workers: workers,
            coordination: coordination,
            tools: tools,
            artifacts: [],
            gitReviewFiles: [],
            process: .init(state: "Settled", model: processModel, mcps: []),
            continuity: .init(status: "verified", reason: "test", provenance: "test", requiresRecoveryAction: false),
            usage: .init(
                totalTokens: 1_234,
                modelCalls: 2,
                turnCount: turnCount,
                inputTokens: 1_000,
                outputTokens: 234,
                cachedReadTokens: 100,
                reasoningTokens: 50,
                apiDurationMilliseconds: 1_500,
                costUsdTicks: 10_000_000,
                modelUsage: modelUsage
            ),
            outcome: outcome,
            unresolvedErrors: [],
            nextAction: "none"
        )
    }

    private func worker(
        _ id: String,
        receipts: [ChildToolReceipt] = []
    ) -> RunEvidenceSnapshot.Worker {
        .init(
            id: id,
            title: id,
            status: "completed",
            childID: "child-\(id)",
            durationMilliseconds: 100,
            toolCallCount: 1,
            redactedError: nil,
            childToolReceipts: receipts,
            childLedgerReadOutcome: .receipts
        )
    }

    private func nativeRoute() -> ModelRouteContract {
        route(.nativeXAI, modelID: "grok-4.6", pinned: true, providerProven: true)
    }

    private func route(
        _ kind: ModelRouteContract.Kind,
        providerName: String? = nil,
        endpointHost: String? = nil,
        endpointRouteIdentity: String? = nil,
        modelID: String = "model",
        pinned: Bool = true,
        providerProven: Bool = false
    ) -> ModelRouteContract {
        .init(
            kind: kind,
            providerName: providerName ?? (kind == .brokeredOpenRouter ? "OpenRouter" : "Provider"),
            endpointHost: endpointHost,
            endpointRouteIdentity: endpointRouteIdentity,
            providerModelID: modelID,
            modelIsPinned: pinned,
            servingProviderIsProven: providerProven
        )
    }

    private func liveTool(
        id: String,
        status: ToolCallTerminalStatus,
        retryOf: String? = nil
    ) -> ChatStore.LiveToolCall {
        .init(
            id: id,
            title: id,
            kind: "test",
            status: status.rawValue,
            terminalStatus: status,
            detail: nil,
            diagnosticDetail: nil,
            target: nil,
            retryOfToolCallID: retryOf,
            recoveredByToolCallID: nil
        )
    }

    private func observation(
        timestamp: TimeInterval,
        firstChunk: Int?,
        apiDuration: Int?,
        totalTokens: Int?,
        costTicks: Int?,
        outcome: ChatStore.TurnOutcome,
        unresolvedWorkers: Int,
        recoveryOpportunityObserved: Bool,
        recoverySucceeded: Bool
    ) -> ModelPerformanceObservation {
        .init(
            id: UUID(),
            observedAt: Date(timeIntervalSince1970: timestamp),
            modelID: "grok-4.6",
            routeKind: .nativeXAI,
            routeIdentity: .init(route: nativeRoute()),
            routeLabel: "Direct xAI",
            servingProviderIsProven: true,
            workloadClass: .recovery,
            parentBackendSessionID: "backend-\(timestamp)",
            firstChunkLatencyMilliseconds: firstChunk,
            providerAPIDurationMilliseconds: apiDuration,
            totalTokens: totalTokens,
            inputTokens: totalTokens.map { $0 - 100 },
            outputTokens: totalTokens.map { min(100, $0) },
            cachedReadTokens: nil,
            reasoningTokens: nil,
            modelCalls: 2,
            costUsdTicks: costTicks,
            outcome: outcome.rawValue,
            observedToolPresence: true,
            observedWorkerPresence: false,
            unresolvedWorkerCount: unresolvedWorkers,
            recoveryOpportunityObserved: recoveryOpportunityObserved,
            recoverySucceeded: recoverySucceeded,
            usageAttribution: .parentTurnReceipt
        )
    }

    private func customObservation(
        modelID: String,
        route: ModelRouteContract,
        timestamp: TimeInterval
    ) -> ModelPerformanceObservation {
        .init(
            id: UUID(),
            observedAt: Date(timeIntervalSince1970: timestamp),
            modelID: modelID,
            routeKind: .from(route),
            routeIdentity: .init(route: route),
            routeLabel: route.compactLabel,
            servingProviderIsProven: route.servingProviderIsProven,
            workloadClass: .noTool,
            parentBackendSessionID: "legacy-\(timestamp)",
            firstChunkLatencyMilliseconds: 100,
            providerAPIDurationMilliseconds: 200,
            totalTokens: 300,
            inputTokens: 250,
            outputTokens: 50,
            cachedReadTokens: 0,
            reasoningTokens: 0,
            modelCalls: 1,
            costUsdTicks: nil,
            outcome: ChatStore.TurnOutcome.completed.rawValue,
            observedToolPresence: false,
            observedWorkerPresence: false,
            unresolvedWorkerCount: 0,
            recoveryOpportunityObserved: false,
            recoverySucceeded: false,
            usageAttribution: .parentTurnReceipt
        )
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "grokbuild.tests.performance.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }
}
