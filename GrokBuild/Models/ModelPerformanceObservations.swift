import Foundation

/// Derives a user-conversation prompt ordinal from durable parent completion
/// checkpoints and the backend's authoritative prompt index. The latter truthfully
/// preserves same-backend context after a stopped or failed prior attempt; provider
/// `turnCount` still counts unrelated internal model cycles and is never used here.
enum ModelPerformanceConversationOrdinal {
    static func value(
        priorCheckpoints: [AssistantTurnCheckpoint],
        backendSessionID: String,
        backendPromptIndex: Int? = nil
    ) -> Int {
        var seenCompletionReceipts = Set<String>()
        let completedTurnCount = priorCheckpoints.reduce(into: 0) { count, checkpoint in
            guard checkpoint.isSettled,
                  checkpoint.parentBackendSessionID == backendSessionID,
                  isCompleted(checkpoint)
            else { return }

            if let requestID = checkpoint.requestID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !requestID.isEmpty {
                let generation = checkpoint.processGeneration.map(String.init) ?? "legacy-generation"
                let receiptIdentity = "\(generation):\(requestID)"
                guard seenCompletionReceipts.insert(receiptIdentity).inserted else { return }
            }
            count += 1
        }
        let durableCheckpointOrdinal = completedTurnCount + 1
        let backendPromptOrdinal = backendPromptIndex.map { $0 + 1 } ?? 1
        return max(durableCheckpointOrdinal, backendPromptOrdinal)
    }

    private static func isCompleted(_ checkpoint: AssistantTurnCheckpoint) -> Bool {
        if let outcomeCode = checkpoint.outcomeCode {
            return outcomeCode == ChatStore.TurnOutcome.completed.rawValue
        }
        return checkpoint.outcome == ChatStore.TurnOutcome.completed.displayName
    }
}

/// One bounded, local-only observation recorded after an authoritative
/// `turn_completed` receipt settles. It contains typed performance receipts and
/// classifications only—never prompts, response bodies, tool payloads, credentials,
/// file paths, or private reasoning.
struct ModelPerformanceObservation: Codable, Hashable, Identifiable, Sendable {
    enum RouteKind: String, Codable, CaseIterable, Sendable {
        case nativeXAI
        case directProvider
        case localEndpoint
        case pinnedOpenRouter
        case openRouterAuto
        case unavailable

        var displayName: String {
            switch self {
            case .nativeXAI: "Native xAI"
            case .directProvider: "Direct provider"
            case .localEndpoint: "Local endpoint"
            case .pinnedOpenRouter: "Pinned OpenRouter"
            case .openRouterAuto: "OpenRouter auto"
            case .unavailable: "Provider unavailable"
            }
        }

        static func from(_ route: ModelRouteContract) -> RouteKind {
            switch route.kind {
            case .nativeXAI: .nativeXAI
            case .directProvider: .directProvider
            case .localEndpoint: .localEndpoint
            case .brokeredOpenRouter:
                route.modelIsPinned ? .pinnedOpenRouter : .openRouterAuto
            case .unavailable: .unavailable
            }
        }
    }

    enum WorkloadClass: String, Codable, CaseIterable, Sendable {
        case noTool
        case orderedMultiTool
        case parallelMultiTool
        case twoChildCoordination
        case longHorizonContinuation
        case recovery

        var displayName: String {
            switch self {
            case .noTool: "No-tool control"
            case .orderedMultiTool: "Ordered multi-tool"
            case .parallelMultiTool: "Parallel multi-tool"
            case .twoChildCoordination: "Two-child coordination"
            case .longHorizonContinuation: "Long-horizon continuation"
            case .recovery: "Recovery"
            }
        }
    }

    struct RouteIdentity: Codable, Hashable, Sendable {
        let kind: RouteKind
        let providerName: String
        let endpointIdentity: String?
        let providerModelID: String
        let modelIsPinned: Bool

        init(route: ModelRouteContract) {
            kind = .from(route)
            providerName = route.providerName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let exactEndpoint = route.endpointRouteIdentity {
                endpointIdentity = exactEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                endpointIdentity = route.endpointHost?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            providerModelID = route.providerModelID
                .trimmingCharacters(in: .whitespacesAndNewlines)
            modelIsPinned = route.modelIsPinned
        }

        var displayName: String {
            let endpoint = endpointIdentity.map { " · \($0)" } ?? ""
            let model = providerModelID.isEmpty ? "model unconfigured" : providerModelID
            let pinning = modelIsPinned ? "pinned" : "automatic"
            return "\(kind.displayName) · \(providerName)\(endpoint) · \(model) · \(pinning)"
        }

        var stableKey: String {
            [
                kind.rawValue,
                providerName,
                endpointIdentity ?? "",
                providerModelID,
                modelIsPinned ? "pinned" : "automatic",
            ].map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        }
    }

    enum UsageAttribution: String, Codable, Sendable {
        case parentTurnReceipt
        case matchedPerModelReceipt
        case unavailableForMixedModelTurn
    }

    let id: UUID
    let observedAt: Date
    let modelID: String
    let routeKind: RouteKind
    let routeIdentity: RouteIdentity
    let routeLabel: String
    let servingProviderIsProven: Bool
    let workloadClass: WorkloadClass
    let parentBackendSessionID: String
    let firstChunkLatencyMilliseconds: Int?
    let providerAPIDurationMilliseconds: Int?
    let totalTokens: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let cachedReadTokens: Int?
    let reasoningTokens: Int?
    let modelCalls: Int?
    let costUsdTicks: Int?
    let outcome: String
    let observedToolPresence: Bool
    let observedWorkerPresence: Bool
    let unresolvedWorkerCount: Int
    let recoveryOpportunityObserved: Bool
    let recoverySucceeded: Bool
    let usageAttribution: UsageAttribution

    var completed: Bool { outcome == ChatStore.TurnOutcome.completed.rawValue }
    var cohortModelID: String {
        guard routeKind != .nativeXAI else { return modelID }
        let providerModelID = routeIdentity.providerModelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return providerModelID.isEmpty ? modelID : providerModelID
    }

    static func workloadClass(
        snapshot: RunEvidenceSnapshot,
        observedParallelToolExecution: Bool,
        recoveryOpportunityObserved: Bool,
        conversationTurnOrdinal: Int
    ) -> WorkloadClass? {
        if recoveryOpportunityObserved {
            return .recovery
        }
        let requestedChildren = snapshot.coordination?.requestedChildCount ?? 0
        let spawnedChildren = snapshot.coordination?.spawnedChildCount ?? snapshot.workers.count
        let childCount = max(requestedChildren, spawnedChildren, snapshot.workers.count)
        if childCount == 2 {
            return .twoChildCoordination
        }
        guard childCount == 0 else { return nil }
        if snapshot.tools.total >= 2 {
            return observedParallelToolExecution ? .parallelMultiTool : .orderedMultiTool
        }
        if conversationTurnOrdinal > 1 {
            return .longHorizonContinuation
        }
        if snapshot.tools.total == 0, snapshot.workers.isEmpty {
            return .noTool
        }
        // A one-tool or one-child turn is not one of the frozen comparable classes.
        // Ignore it instead of quietly inventing an "other" benchmark bucket.
        return nil
    }
}

/// A recovery opportunity is an authoritative failed parent or child tool receipt.
/// Success is narrower: every failed parent tool must have an explicit successful
/// retry correlation, and child recovery remains unproven until ACP exposes the same
/// correlation in `ChildToolReceipt`.
struct ModelPerformanceRecoveryEvidence: Equatable, Sendable {
    let opportunityObserved: Bool
    let succeeded: Bool

    static func make(
        parentTools: [ChatStore.LiveToolCall],
        workers: [RunEvidenceSnapshot.Worker]
    ) -> Self {
        let failedParentTools = parentTools.filter(\.isFailed)
        let hasFailedChildTool = workers.contains { worker in
            (worker.childToolReceipts ?? []).contains { $0.status == .failed }
        }
        let opportunityObserved = !failedParentTools.isEmpty || hasFailedChildTool
        return Self(
            opportunityObserved: opportunityObserved,
            succeeded: opportunityObserved
                && !hasFailedChildTool
                && !failedParentTools.isEmpty
                && failedParentTools.allSatisfy(\.isRecovered)
        )
    }
}

struct ModelPerformanceObservationSummary: Identifiable, Equatable, Sendable {
    struct IntegerMetric: Equatable, Sendable {
        let sampleCount: Int
        let median: Int
        let minimum: Int
        let maximum: Int
    }

    let modelID: String
    let routeKind: ModelPerformanceObservation.RouteKind
    let routeIdentity: ModelPerformanceObservation.RouteIdentity
    let workloadClass: ModelPerformanceObservation.WorkloadClass
    let sampleCount: Int
    let firstChunkLatency: IntegerMetric?
    let providerAPIDuration: IntegerMetric?
    let totalTokens: IntegerMetric?
    let inputTokens: IntegerMetric?
    let outputTokens: IntegerMetric?
    let cachedReadTokens: IntegerMetric?
    let reasoningTokens: IntegerMetric?
    let modelCalls: IntegerMetric?
    let costUsdTicks: IntegerMetric?
    let completionRate: Double
    let recoveryRate: Double?
    let unresolvedWorkerRate: Double
    let lastObservedRoute: String
    let servingProviderIsProven: Bool
    let lastObservedAt: Date

    var id: String { "\(modelID)|\(routeIdentity.stableKey)|\(workloadClass.rawValue)" }

    static func make(from observations: [ModelPerformanceObservation]) -> Self? {
        guard let latest = observations.max(by: { $0.observedAt < $1.observedAt }) else { return nil }
        let completionCount = observations.filter(\.completed).count
        let recovery = observations.filter(\.recoveryOpportunityObserved)
        let unresolved = observations.filter { $0.unresolvedWorkerCount > 0 }.count
        return Self(
            modelID: latest.cohortModelID,
            routeKind: latest.routeKind,
            routeIdentity: latest.routeIdentity,
            workloadClass: latest.workloadClass,
            sampleCount: observations.count,
            firstChunkLatency: metric(observations.compactMap(\.firstChunkLatencyMilliseconds)),
            providerAPIDuration: metric(observations.compactMap(\.providerAPIDurationMilliseconds)),
            totalTokens: metric(observations.compactMap(\.totalTokens)),
            inputTokens: metric(observations.compactMap(\.inputTokens)),
            outputTokens: metric(observations.compactMap(\.outputTokens)),
            cachedReadTokens: metric(observations.compactMap(\.cachedReadTokens)),
            reasoningTokens: metric(observations.compactMap(\.reasoningTokens)),
            modelCalls: metric(observations.compactMap(\.modelCalls)),
            costUsdTicks: metric(observations.compactMap(\.costUsdTicks)),
            completionRate: Double(completionCount) / Double(observations.count),
            recoveryRate: recovery.isEmpty
                ? nil
                : Double(recovery.filter(\.recoverySucceeded).count) / Double(recovery.count),
            unresolvedWorkerRate: Double(unresolved) / Double(observations.count),
            lastObservedRoute: latest.routeIdentity.displayName,
            servingProviderIsProven: latest.servingProviderIsProven,
            lastObservedAt: latest.observedAt
        )
    }

    private static func metric(_ values: [Int]) -> IntegerMetric? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        let median = if sorted.count.isMultiple(of: 2) {
            (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            sorted[middle]
        }
        return IntegerMetric(
            sampleCount: sorted.count,
            median: median,
            minimum: sorted[0],
            maximum: sorted[sorted.count - 1]
        )
    }
}

enum ModelPerformanceObservationStore {
    static let storageKey = "grokbuild.modelPerformanceObservations.v1"
    static let maximumObservationCount = 240
    static let maximumObservationsPerCohort = 40
    private static let lock = NSLock()

    private struct CohortKey: Hashable {
        let modelID: String
        let routeIdentity: ModelPerformanceObservation.RouteIdentity
        let workloadClass: ModelPerformanceObservation.WorkloadClass
    }

    private struct UsageProjection {
        let attribution: ModelPerformanceObservation.UsageAttribution
        let providerAPIDurationMilliseconds: Int?
        let totalTokens: Int?
        let inputTokens: Int?
        let outputTokens: Int?
        let cachedReadTokens: Int?
        let reasoningTokens: Int?
        let modelCalls: Int?
        let costUsdTicks: Int?
    }

    static func load(defaults: UserDefaults = .standard) -> [ModelPerformanceObservation] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked(defaults: defaults)
    }

    private static func loadUnlocked(defaults: UserDefaults) -> [ModelPerformanceObservation] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ModelPerformanceObservation].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.observedAt < $1.observedAt }
    }

    @discardableResult
    static func record(
        snapshot: RunEvidenceSnapshot,
        route: ModelRouteContract,
        firstChunkLatencyMilliseconds: Int?,
        observedParallelToolExecution: Bool,
        recoveryOpportunityObserved: Bool,
        recoverySucceeded: Bool,
        conversationTurnOrdinal: Int = 1,
        observedAt: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> ModelPerformanceObservation? {
        guard snapshot.binding.isSettled,
              let backendID = snapshot.binding.backendSessionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !backendID.isEmpty,
              let processModelID = snapshot.process.model?.trimmingCharacters(in: .whitespacesAndNewlines),
              !processModelID.isEmpty else {
            return nil
        }
        lock.lock()
        var observations = loadUnlocked(defaults: defaults)
        guard let workloadClass = ModelPerformanceObservation.workloadClass(
            snapshot: snapshot,
            observedParallelToolExecution: observedParallelToolExecution,
            recoveryOpportunityObserved: recoveryOpportunityObserved,
            conversationTurnOrdinal: conversationTurnOrdinal
        ) else {
            lock.unlock()
            return nil
        }
        let routeIdentity = ModelPerformanceObservation.RouteIdentity(route: route)
        let modelID = routeIdentity.kind == .nativeXAI || routeIdentity.providerModelID.isEmpty
            ? processModelID
            : routeIdentity.providerModelID
        let usage = usageProjection(snapshot: snapshot, route: route, modelID: processModelID)
        let observation = ModelPerformanceObservation(
            id: UUID(),
            observedAt: observedAt,
            modelID: modelID,
            routeKind: .from(route),
            routeIdentity: routeIdentity,
            routeLabel: route.compactLabel,
            servingProviderIsProven: route.servingProviderIsProven,
            workloadClass: workloadClass,
            parentBackendSessionID: backendID,
            firstChunkLatencyMilliseconds: firstChunkLatencyMilliseconds,
            providerAPIDurationMilliseconds: usage.providerAPIDurationMilliseconds,
            totalTokens: usage.totalTokens,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cachedReadTokens: usage.cachedReadTokens,
            reasoningTokens: usage.reasoningTokens,
            modelCalls: usage.modelCalls,
            costUsdTicks: usage.costUsdTicks,
            outcome: snapshot.outcome.rawValue,
            observedToolPresence: snapshot.tools.total > 0,
            observedWorkerPresence: !snapshot.workers.isEmpty,
            unresolvedWorkerCount: snapshot.unresolvedWorkerCount,
            recoveryOpportunityObserved: recoveryOpportunityObserved,
            recoverySucceeded: recoveryOpportunityObserved && recoverySucceeded,
            usageAttribution: usage.attribution
        )
        observations.append(observation)
        observations = bounded(observations)
        guard let data = try? JSONEncoder().encode(observations) else {
            lock.unlock()
            return nil
        }
        defaults.set(data, forKey: storageKey)
        lock.unlock()
        NotificationCenter.default.post(name: .modelPerformanceObservationsChanged, object: nil)
        return observation
    }

    static func summaries(
        defaults: UserDefaults = .standard
    ) -> [ModelPerformanceObservationSummary] {
        let grouped = Dictionary(grouping: load(defaults: defaults)) {
            CohortKey(
                modelID: $0.cohortModelID,
                routeIdentity: $0.routeIdentity,
                workloadClass: $0.workloadClass
            )
        }
        return grouped.values.compactMap(ModelPerformanceObservationSummary.make)
            .sorted {
                if $0.modelID != $1.modelID {
                    return $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending
                }
                if $0.routeKind.rawValue != $1.routeKind.rawValue {
                    return $0.routeKind.rawValue < $1.routeKind.rawValue
                }
                if $0.routeIdentity.displayName != $1.routeIdentity.displayName {
                    return $0.routeIdentity.displayName < $1.routeIdentity.displayName
                }
                return $0.workloadClass.rawValue < $1.workloadClass.rawValue
            }
    }

    static func clear(defaults: UserDefaults = .standard) {
        lock.lock()
        defaults.removeObject(forKey: storageKey)
        lock.unlock()
        NotificationCenter.default.post(name: .modelPerformanceObservationsChanged, object: nil)
    }

    private static func bounded(
        _ observations: [ModelPerformanceObservation]
    ) -> [ModelPerformanceObservation] {
        let sorted = observations.sorted { $0.observedAt < $1.observedAt }
        var counts: [CohortKey: Int] = [:]
        var retainedNewestFirst: [ModelPerformanceObservation] = []
        for observation in sorted.reversed() {
            let cohort = CohortKey(
                modelID: observation.cohortModelID,
                routeIdentity: observation.routeIdentity,
                workloadClass: observation.workloadClass
            )
            guard counts[cohort, default: 0] < maximumObservationsPerCohort else { continue }
            counts[cohort, default: 0] += 1
            retainedNewestFirst.append(observation)
            if retainedNewestFirst.count == maximumObservationCount { break }
        }
        return retainedNewestFirst.reversed()
    }

    private static func usageProjection(
        snapshot: RunEvidenceSnapshot,
        route: ModelRouteContract,
        modelID: String
    ) -> UsageProjection {
        let perModel = snapshot.usage.modelUsage
        if perModel.isEmpty, snapshot.workers.isEmpty {
            return UsageProjection(
                attribution: .parentTurnReceipt,
                providerAPIDurationMilliseconds: snapshot.usage.apiDurationMilliseconds,
                totalTokens: snapshot.usage.totalTokens,
                inputTokens: snapshot.usage.inputTokens,
                outputTokens: snapshot.usage.outputTokens,
                cachedReadTokens: snapshot.usage.cachedReadTokens,
                reasoningTokens: snapshot.usage.reasoningTokens,
                modelCalls: snapshot.usage.modelCalls,
                costUsdTicks: snapshot.usage.costUsdTicks
            )
        }
        let candidates = Set([modelID, route.providerModelID].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })
        let matches = perModel.filter {
            let receiptModel = $0.modelID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return candidates.contains(receiptModel)
                || (route.kind == .nativeXAI && candidates.contains {
                    receiptModel == "\($0)-build"
                })
        }
        guard matches.count == 1, let match = matches.first else {
            return UsageProjection(
                attribution: .unavailableForMixedModelTurn,
                providerAPIDurationMilliseconds: nil,
                totalTokens: nil,
                inputTokens: nil,
                outputTokens: nil,
                cachedReadTokens: nil,
                reasoningTokens: nil,
                modelCalls: nil,
                costUsdTicks: nil
            )
        }
        return usageProjection(receipt: match, attribution: .matchedPerModelReceipt)
    }

    private static func usageProjection(
        receipt: ModelUsageReceipt,
        attribution: ModelPerformanceObservation.UsageAttribution
    ) -> UsageProjection {
        UsageProjection(
            attribution: attribution,
            providerAPIDurationMilliseconds: receipt.apiDurationMilliseconds,
            totalTokens: receipt.totalTokens,
            inputTokens: receipt.inputTokens,
            outputTokens: receipt.outputTokens,
            cachedReadTokens: receipt.cachedReadTokens,
            reasoningTokens: receipt.reasoningTokens,
            modelCalls: receipt.modelCalls,
            costUsdTicks: receipt.costUsdTicks
        )
    }
}

extension Notification.Name {
    static let modelPerformanceObservationsChanged = Notification.Name(
        "com.grokbuild.model-performance-observations-changed"
    )
}
