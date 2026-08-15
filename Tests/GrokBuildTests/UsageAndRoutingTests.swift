import Foundation
import XCTest
@testable import GrokBuild

/// Agentic roadmap Slices 5+6: configured role→model routing display and the
/// session usage ledger / pricing capture. Everything here is display-side truth:
/// routing labels come only from exact config matches, and dollar figures exist
/// only where catalog pricing is known.
final class UsageAndRoutingTests: XCTestCase {
    // MARK: - Slice 5: routing

    func testRolesByNameKeepsOnlyNamedRoutedRoles() {
        let roles = [
            SubagentRole(name: "Researcher", model: "deepseek-deepseek-v4-flash-0731", instruction: "dig"),
            SubagentRole(name: "writer", model: "   ", instruction: "write"),
            SubagentRole(name: "  ", model: "grok-build", instruction: "x"),
        ]
        let map = SubagentRouting.rolesByName(roles)
        XCTAssertEqual(map, ["researcher": "deepseek-deepseek-v4-flash-0731"],
                       "inheriting and unnamed roles must make no routing claim")
    }

    func testRoutedModelMatchesWorkerTitleExactlyCaseInsensitive() {
        let map = ["researcher": "deepseek-deepseek-v4-flash-0731"]
        XCTAssertEqual(SubagentRouting.routedModel(forWorkerTitle: "Researcher", rolesByName: map),
                       "deepseek-deepseek-v4-flash-0731")
        XCTAssertEqual(SubagentRouting.routedModel(forWorkerTitle: "  researcher  ", rolesByName: map),
                       "deepseek-deepseek-v4-flash-0731")
        XCTAssertNil(SubagentRouting.routedModel(forWorkerTitle: "researcher subagent", rolesByName: map),
                     "a prompt-derived title must not fuzzy-match a role")
        XCTAssertNil(SubagentRouting.routedModel(forWorkerTitle: "", rolesByName: map))
    }

    func testWorkerReceiptDetailLeadsWithConfiguredRoute() {
        let detail = ActivitySidebarPresentation.workerReceiptDetail(
            status: "completed",
            durationMilliseconds: 3_200,
            toolCallCount: 4,
            redactedError: nil,
            routedModel: "deepseek-deepseek-v4-flash-0731"
        )
        XCTAssertTrue(detail.hasPrefix("Routes to deepseek-deepseek-v4-flash-0731 (configured)"),
                      "routing is declared config truth and labeled as such: \(detail)")
        XCTAssertTrue(detail.contains("3.2 sec"))
        XCTAssertTrue(detail.contains("4 tools"))
        // No route → no claim, and the receipt is unchanged from the legacy shape.
        let unrouted = ActivitySidebarPresentation.workerReceiptDetail(
            status: "completed", durationMilliseconds: 3_200, toolCallCount: 4, redactedError: nil
        )
        XCTAssertFalse(unrouted.contains("Routes to"))
    }

    func testWorkerReceiptPrefersRuntimeModelWithoutErasingConfiguredRoute() {
        let detail = ActivitySidebarPresentation.workerReceiptDetail(
            status: "completed",
            durationMilliseconds: nil,
            toolCallCount: 1,
            redactedError: nil,
            runtimeModelID: "grok-4.5-build",
            routedModel: "gpt-5.6-terra"
        )
        XCTAssertTrue(detail.hasPrefix("Ran on grok-4.5-build (Grok ACP)"))
        XCTAssertTrue(detail.contains("Routes to gpt-5.6-terra (configured)"))
    }

    // MARK: - Slice 6: pricing capture

    func testParseCapturesOpenRouterPricingAndToleratesShapes() throws {
        let payload = """
        {"data": [
          {"id": "deepseek/deepseek-v4-flash-0731", "pricing": {"prompt": "0.00000014", "completion": "0.00000028"}},
          {"id": "free/model", "pricing": {"prompt": "0", "completion": "0"}},
          {"id": "numeric/model", "pricing": {"prompt": 0.000001, "completion": 0.000002}},
          {"id": "no-pricing/model"}
        ]}
        """
        let models = try XCTUnwrap(ProviderModelFetcher.parse(Data(payload.utf8)))
        let byID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        XCTAssertEqual(byID["deepseek/deepseek-v4-flash-0731"]?.promptPricePerToken, 0.00000014)
        XCTAssertEqual(byID["deepseek/deepseek-v4-flash-0731"]?.completionPricePerToken, 0.00000028)
        XCTAssertNil(byID["free/model"]?.promptPricePerToken, "zero rates are absent, not free-forever claims")
        XCTAssertEqual(byID["numeric/model"]?.promptPricePerToken, 0.000001)
        XCTAssertNil(byID["no-pricing/model"]?.promptPricePerToken)
    }

    func testPricingStoreRoundTripAndCacheInvalidation() throws {
        let suite = "grokbuild.tests.pricing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            ModelPricingStore.resetCacheForTests()
        }
        ModelPricingStore.resetCacheForTests()

        XCTAssertNil(ModelPricingStore.pricing(for: "x/y", defaults: defaults))
        ModelPricingStore.record([
            FetchedModel(id: "x/y", ownedBy: nil, promptPricePerToken: 1e-7, completionPricePerToken: 2e-7),
            FetchedModel(id: "unpriced", ownedBy: nil),
        ], defaults: defaults)
        XCTAssertEqual(ModelPricingStore.pricing(for: "x/y", defaults: defaults),
                       ModelPricing(promptPerToken: 1e-7, completionPerToken: 2e-7))
        XCTAssertNil(ModelPricingStore.pricing(for: "unpriced", defaults: defaults),
                     "models without pricing are never recorded as $0")
        // A later fetch merges without erasing earlier entries.
        ModelPricingStore.record([
            FetchedModel(id: "a/b", ownedBy: nil, promptPricePerToken: 3e-7, completionPricePerToken: 3e-7)
        ], defaults: defaults)
        XCTAssertNotNil(ModelPricingStore.pricing(for: "x/y", defaults: defaults))
        XCTAssertNotNil(ModelPricingStore.pricing(for: "a/b", defaults: defaults))
    }

    // MARK: - Slice 6: ledger

    func testLedgerAccumulatesOnlySettledTurnsWithTokens() {
        var ledger = SessionUsageLedger()
        XCTAssertNil(ledger.summaryText(pricing: [:]))
        ledger.recordTurn(modelID: "grok-4.5", totalTokens: 10_000, modelCalls: 2)
        ledger.recordTurn(modelID: "grok-4.5", totalTokens: nil, modelCalls: 1)   // no receipt → no entry
        ledger.recordTurn(modelID: "grok-4.5", totalTokens: 0, modelCalls: 1)     // zero → no entry
        ledger.recordTurn(modelID: "deepseek/deepseek-v4-flash-0731", totalTokens: 5_000, modelCalls: 1)
        XCTAssertEqual(ledger.turnCount, 2)
        XCTAssertEqual(ledger.totalTokens, 15_000)
        XCTAssertEqual(ledger.totalModelCalls, 3)

        ledger.reset()
        XCTAssertTrue(ledger.isEmpty)
    }

    func testEstimateBracketsPromptAndCompletionRatesAndFlagsPartialCoverage() {
        var ledger = SessionUsageLedger()
        ledger.recordTurn(modelID: "unpriced-model", totalTokens: 10_000, modelCalls: 1)
        let pricing = ["deepseek/deepseek-v4-flash-0731": ModelPricing(promptPerToken: 1e-7, completionPerToken: 4e-7)]
        XCTAssertNil(ledger.estimate(pricing: pricing), "no priced tokens → no dollar claim at all")

        ledger.recordTurn(modelID: "deepseek/deepseek-v4-flash-0731", totalTokens: 10_000, modelCalls: 1)
        let estimate = try! XCTUnwrap(ledger.estimate(pricing: pricing))
        XCTAssertEqual(estimate.low, 10_000 * 1e-7, accuracy: 1e-12)
        XCTAssertEqual(estimate.high, 10_000 * 4e-7, accuracy: 1e-12)
        XCTAssertEqual(estimate.pricedTokens, 10_000)
        XCTAssertFalse(estimate.coversAllTokens)

        let summary = try! XCTUnwrap(ledger.summaryText(pricing: pricing))
        XCTAssertTrue(summary.contains("20.0k tokens"))
        XCTAssertTrue(summary.contains("2 turns"))
        XCTAssertTrue(summary.contains("est. (priced portion)"),
                      "partially priced sessions must disclose partial coverage: \(summary)")

        let unpricedSummary = try! XCTUnwrap(ledger.summaryText(pricing: [:]))
        XCTAssertFalse(unpricedSummary.contains("$"), "tokens only when no pricing is known")
    }

    func testAuthoritativePerModelUsageAndProviderCostOverrideMainRouteGuess() {
        var ledger = SessionUsageLedger()
        ledger.recordTurn(
            modelID: "main-model",
            totalTokens: 3_000,
            modelCalls: 2,
            costUsdTicks: 125_000_000,
            modelUsage: [
                .init(
                    modelID: "worker-model",
                    inputTokens: 2_000,
                    outputTokens: 1_000,
                    totalTokens: 3_000,
                    cachedReadTokens: 500,
                    reasoningTokens: 250,
                    modelCalls: 2,
                    apiDurationMilliseconds: 4_500,
                    costUsdTicks: 125_000_000
                )
            ]
        )
        let pricing = ["worker-model": ModelPricing(promptPerToken: 1e-6, completionPerToken: 2e-6)]
        let estimate = try! XCTUnwrap(ledger.estimate(pricing: pricing))
        XCTAssertEqual(estimate.pricedTokens, 3_000)
        XCTAssertEqual(estimate.low, 0.004, accuracy: 1e-12)
        XCTAssertEqual(estimate.high, 0.004, accuracy: 1e-12)
        let summary = try! XCTUnwrap(ledger.summaryText(pricing: [:]))
        XCTAssertTrue(summary.contains("$0.12 provider-reported"), summary)
        XCTAssertFalse(summary.contains("est."), summary)
    }

    func testModelUsageParserKeepsEveryAuthoritativeSplit() {
        let receipts = GrokProcess.modelUsageReceipts(from: [
            "grok-4.5-build": [
                "inputTokens": 11,
                "outputTokens": 7,
                "totalTokens": 18,
                "cachedReadTokens": 5,
                "reasoningTokens": 3,
                "modelCalls": 2,
                "apiDurationMs": 900,
                "costUsdTicks": 42_000_000,
            ],
        ])
        XCTAssertEqual(receipts, [
            .init(
                modelID: "grok-4.5-build",
                inputTokens: 11,
                outputTokens: 7,
                totalTokens: 18,
                cachedReadTokens: 5,
                reasoningTokens: 3,
                modelCalls: 2,
                apiDurationMilliseconds: 900,
                costUsdTicks: 42_000_000
            )
        ])
    }

    func testCompactTokenAndDollarFormatting() {
        XCTAssertEqual(SessionUsageLedger.compactTokens(999), "999")
        XCTAssertEqual(SessionUsageLedger.compactTokens(41_300), "41.3k")
        XCTAssertEqual(SessionUsageLedger.compactTokens(2_450_000), "2.45M")
        XCTAssertEqual(SessionUsageLedger.dollars(0.1234), "$0.12")
        XCTAssertEqual(SessionUsageLedger.dollars(0.00042), "$0.00042")
    }

    // MARK: - LLM diversity + workbench polish

    func testGroupedModelsSplitNativeFromCustomAndDropEmptyGroups() {
        let grouped = ChatStore.groupedModels(
            available: ["grok-4.5", "deepseek-deepseek-v4-flash-0731", "gpt-5.6-terra"],
            customIDs: ["deepseek-deepseek-v4-flash-0731", "gpt-5.6-terra"]
        )
        XCTAssertEqual(grouped.map(\.label), ["Grok", "Your models"])
        XCTAssertEqual(grouped[0].ids, ["grok-4.5"])
        XCTAssertEqual(grouped[1].ids, ["deepseek-deepseek-v4-flash-0731", "gpt-5.6-terra"])

        let customOnly = ChatStore.groupedModels(
            available: ["deepseek-deepseek-v4-flash-0731"],
            customIDs: ["deepseek-deepseek-v4-flash-0731"]
        )
        XCTAssertEqual(customOnly.map(\.label), ["Your models"],
                       "empty groups render nothing — no dead Grok header for custom-only setups")
    }

    func testWorkbenchPolishWiring() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let chatViewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatViewSource.contains("store.groupedAvailableModels"),
                      "model menus must present provider-grouped choices")
        XCTAssertTrue(chatViewSource.contains("store.setCurrentModelAsProjectDefault()"),
                      "the menu offers making the current model the project default for new sessions")
        // Codex parity Slice 4: agent mode is a compact composer control beside the
        // add/context menu, and session telemetry lives in the model popover.
        let primaryStart = try XCTUnwrap(chatViewSource.range(of: "private var composerPrimaryControls"))
        let primaryEnd = try XCTUnwrap(
            chatViewSource.range(of: "private var composerAddMenu", range: primaryStart.upperBound..<chatViewSource.endIndex)
        )
        let primary = String(chatViewSource[primaryStart.lowerBound..<primaryEnd.lowerBound])
        XCTAssertTrue(primary.contains("modeSelector"), "run mode stays an immediate composer control")
        XCTAssertTrue(chatViewSource.contains("Section(\"Session telemetry\")"),
                      "context and usage telemetry relocated to the model popover")

        let activitySource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ActivitySidebar.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(activitySource.contains("if !snapshot.workers.isEmpty { workers(snapshot) }"),
                      "empty settled sections must not repeat the summary grid's zeros")
        XCTAssertTrue(activitySource.contains("if !liveProjection.tools.isEmpty { liveTools(liveProjection) }"))

        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        let createStart = try XCTUnwrap(contentSource.range(of: "private func createLiveSession"))
        let createEnd = try XCTUnwrap(
            contentSource.range(of: "private func switchBranch", range: createStart.upperBound..<contentSource.endIndex)
        )
        let create = String(contentSource[createStart.lowerBound..<createEnd.lowerBound])
        // Creating a tab must spawn nothing. Send, not the first keystroke, owns launch.
        XCTAssertFalse(create.contains("await store.startNewSession()"),
                       "tab creation must not spawn a grok process; Send owns the first launch")
        let storeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(storeSource.contains("warmStartOnFirstIntentIfNeeded"),
                       "the keystroke warm-start hook is gone; Send remains the launch gate")
        XCTAssertFalse(storeSource.contains("didSet { warmStart"),
                       "composerDraft must not spawn grok on first keystroke")
        let draftRange = try XCTUnwrap(storeSource.range(of: "var composerDraft: String = \"\""))
        let draftWindow = String(storeSource[draftRange.lowerBound..<storeSource.index(draftRange.lowerBound, offsetBy: min(400, storeSource.distance(from: draftRange.lowerBound, to: storeSource.endIndex)))])
        XCTAssertFalse(draftWindow.contains("didSet"),
                       "composerDraft has no didSet; typing must not launch grok")
        XCTAssertTrue(storeSource.contains("cancelLeftoverWarmStart()"),
                      "Stop, shutdown, and Close Session must cancel a leftover synthetic warm-start task")
        XCTAssertTrue(storeSource.contains("isPermanentlyShutdown"),
                      "a closed tab must refuse restartProcess after shutdownPermanently")
        XCTAssertTrue(storeSource.contains("var sendOwnedStartupStageText: String?"),
                      "Send-owned spawn must expose starting copy, not only a silent sidebar working dot")
        XCTAssertTrue(storeSource.contains("composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"),
                      "welcome pills hide once the composer draft owns the task")
    }

    // MARK: - Source contracts

    func testRoutingAndUsageWiring() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatStoreSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        let trackerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/BackgroundTaskStore.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(
            trackerSource.components(separatedBy: "routedModel: SubagentRouting.routedModel(").count - 1,
            1,
            "worker construction carries routing through BackgroundTaskTracker.evidenceWorkers()"
        )
        XCTAssertFalse(
            chatStoreSource.contains("routedModel: SubagentRouting.routedModel("),
            "ChatStore no longer maps BackgroundActivity onto run-evidence workers"
        )
        XCTAssertTrue(
            trackerSource.contains("func evidenceWorkers("),
            "the tracker owns turn-scoped evidence-worker mapping"
        )
        XCTAssertTrue(
            chatStoreSource.contains("backgroundTaskTracker.evidenceWorkers("),
            "live projection and settled snapshot share the tracker evidence builder"
        )
        XCTAssertTrue(
            chatStoreSource.contains("func currentTurnEvidenceWorkers()"),
            "ChatStore keeps one thin delegate so live and settled snapshots share one call"
        )
        let settleAnchor = try XCTUnwrap(chatStoreSource.range(of: "let turnSucceeded = completion.isSuccessful"))
        let afterSettle = String(chatStoreSource[settleAnchor.upperBound...].prefix(600))
        XCTAssertTrue(afterSettle.contains("sessionUsage.recordTurn("),
                      "the ledger records only at the authoritative completion barrier")
        XCTAssertFalse(chatStoreSource.contains("sessionUsage.recordTurn(\n                modelID: nil"),
                      "ledger entries carry the effective model for pricing correlation")

        let chatViewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatViewSource.contains("store.sessionUsageSummary"),
                      "the model popover surfaces the session usage HUD (Slice 4 home)")
        XCTAssertTrue(
            chatViewSource.contains("rolesByName: store.subagentRoleModelsByName"),
            "Tasks-pill unbound workers use the same role→model table as the inspector"
        )

        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/Settings/CustomModelsSettingsPane.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(settingsSource.contains("ModelPricingStore.record(result.models)"),
                      "Test connection captures catalog pricing with no extra requests")
    }
}
