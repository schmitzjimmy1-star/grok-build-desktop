import XCTest
@testable import GrokBuild

final class ACPClientContractTests: XCTestCase {
    private enum TurnFixtureEvent {
        case chunk(String)
        case tool(String)
        case promptResponse(Bool)
        case completion
    }

    private func settlementDecisions(for events: [TurnFixtureEvent]) -> [TurnSettlementCoordinator.Decision] {
        var coordinator = TurnSettlementCoordinator()
        let generation = coordinator.begin(assistantID: UUID())
        var decisions: [TurnSettlementCoordinator.Decision] = []
        for event in events {
            let decision: TurnSettlementCoordinator.Decision?
            switch event {
            case .chunk, .tool:
                decision = nil
            case .promptResponse(let ok):
                decision = coordinator.recordPromptResult(generation: generation, ok: ok)
            case .completion:
                decision = coordinator.recordCompletionConsumed()
            }
            if let decision { decisions.append(decision) }
        }
        return decisions
    }

    func testTurnSettlementFixturesFinalizeExactlyOnceAcrossWireOrders() {
        let fixtures: [[TurnFixtureEvent]] = [
            [.chunk("final"), .promptResponse(true), .completion],
            [.promptResponse(true), .chunk("final"), .completion],
            [.completion, .chunk("late final"), .promptResponse(true)],
            [.tool("browser"), .completion, .chunk("synthesis"), .promptResponse(true)],
            [.tool("explore"), .tool("general-purpose"), .chunk("parent"), .promptResponse(true), .completion],
        ]

        for fixture in fixtures {
            let decisions = settlementDecisions(for: fixture)
            XCTAssertEqual(decisions.count, 1)
            XCTAssertTrue(decisions[0].ok)
        }
    }

    func testTurnSettlementFailureAndStopGenerationCannotFinishANewerTurn() {
        var coordinator = TurnSettlementCoordinator()
        let oldAssistant = UUID()
        let oldGeneration = coordinator.begin(assistantID: oldAssistant)
        coordinator.invalidate()
        let newAssistant = UUID()
        let newGeneration = coordinator.begin(assistantID: newAssistant)

        XCTAssertNil(coordinator.recordPromptResult(generation: oldGeneration, ok: true))
        XCTAssertNil(coordinator.recordPromptResult(generation: newGeneration, ok: true))
        XCTAssertEqual(
            coordinator.recordCompletionConsumed(),
            .init(assistantID: newAssistant, ok: true)
        )

        var failed = TurnSettlementCoordinator()
        let failedID = UUID()
        let failedGeneration = failed.begin(assistantID: failedID)
        XCTAssertEqual(
            failed.recordPromptResult(generation: failedGeneration, ok: false),
            .init(assistantID: failedID, ok: false)
        )
    }

    func testModelReducerRequiresExactTabBackendGenerationAndRequestIdentity() {
        let tab = UUID()
        let identity = ModelRequestIdentity(
            localTabID: tab,
            backendSessionID: "backend-a",
            processGeneration: 7,
            requestID: UUID()
        )
        var state = ModelExecutionReducer.beginRequest(
            modelID: "grok-4.5",
            identity: identity,
            preserving: .unknown,
            at: Date(timeIntervalSince1970: 1)
        )
        let original = state
        let staleIdentities = [
            ModelRequestIdentity(
                localTabID: UUID(), backendSessionID: identity.backendSessionID,
                processGeneration: identity.processGeneration, requestID: identity.requestID
            ),
            ModelRequestIdentity(
                localTabID: identity.localTabID, backendSessionID: "backend-b",
                processGeneration: identity.processGeneration, requestID: identity.requestID
            ),
            ModelRequestIdentity(
                localTabID: identity.localTabID, backendSessionID: identity.backendSessionID,
                processGeneration: 8, requestID: identity.requestID
            ),
            ModelRequestIdentity(
                localTabID: identity.localTabID, backendSessionID: identity.backendSessionID,
                processGeneration: identity.processGeneration, requestID: UUID()
            ),
        ]

        for stale in staleIdentities {
            XCTAssertFalse(ModelExecutionReducer.confirm(
                effectiveModelID: "wrong",
                identity: stale,
                state: &state
            ))
            XCTAssertFalse(ModelExecutionReducer.reject(
                failure: .rejected,
                identity: stale,
                state: &state
            ))
            XCTAssertEqual(state, original)
        }
    }

    func testModelReducerDoesNotConfirmAnAcceptedRequestWithoutEffectiveModel() {
        let identity = ModelRequestIdentity(
            localTabID: UUID(), backendSessionID: "backend",
            processGeneration: 3, requestID: UUID()
        )
        var state = ModelExecutionReducer.beginRequest(
            modelID: "gpt-5.6-terra",
            identity: identity,
            preserving: .unknown
        )

        XCTAssertTrue(ModelExecutionReducer.acceptWithoutEffectiveModel(
            identity: identity,
            state: &state
        ))
        XCTAssertEqual(state.status, .requested)
        XCTAssertEqual(state.requestedModelID, "gpt-5.6-terra")
        XCTAssertNil(state.effectiveModelID)
    }

    func testModelReducerConfirmsExplicitReadbackAndPreservesItOnRejection() {
        let identity = ModelRequestIdentity(
            localTabID: UUID(), backendSessionID: "backend",
            processGeneration: 11, requestID: UUID()
        )
        var state = ModelExecutionReducer.launch(
            requestedModelID: "grok-4.5",
            identity: identity
        )
        XCTAssertTrue(ModelExecutionReducer.confirm(
            effectiveModelID: "grok-4.5",
            identity: identity,
            state: &state
        ))
        XCTAssertEqual(state.status, .confirmed)

        let next = ModelRequestIdentity(
            localTabID: identity.localTabID,
            backendSessionID: identity.backendSessionID,
            processGeneration: identity.processGeneration,
            requestID: UUID()
        )
        state = ModelExecutionReducer.beginRequest(
            modelID: "gpt-5.6-terra",
            identity: next,
            preserving: state
        )
        XCTAssertTrue(ModelExecutionReducer.reject(
            failure: .rejected,
            identity: next,
            state: &state
        ))
        XCTAssertEqual(state.status, .rejected)
        XCTAssertEqual(state.requestedModelID, "gpt-5.6-terra")
        XCTAssertEqual(state.effectiveModelID, "grok-4.5")
    }

    func testEffectiveModelParsingRequiresAnExplicitReadback() {
        XCTAssertNil(GrokProcess.effectiveModelID(from: [:]))
        XCTAssertEqual(GrokProcess.effectiveModelID(from: [
            "_meta": ["model": ["Ok": "grok-4.5"]]
        ]), "grok-4.5")
        XCTAssertEqual(GrokProcess.effectiveModelID(from: [
            "modelState": ["currentModelId": "gpt-5.6-terra"]
        ]), "gpt-5.6-terra")
    }

    @MainActor
    func testUnstartedTabModelSelectionIsSavedRatherThanLive() async {
        let store = ChatStore()
        store.prepare(workspace: Workspace(
            name: "fixture",
            path: FileManager.default.temporaryDirectory
        ))
        store.bindTabSession(UUID(), modelIntent: .inheritProjectDefault)
        store.setModel("grok-4.5")

        XCTAssertEqual(store.modelExecutionState.status, .requested)
        XCTAssertEqual(store.modelSelectorStatusLabel, "Saved")
        XCTAssertTrue(store.modelAccessibilityValue.contains("no active process"))
        XCTAssertEqual(store.persistedModelIntent, .explicit("grok-4.5"))
        await store.shutdownPermanently()
    }

    func testLiveProcessLaunchAndRestartReceiptsTrackEffectivePermissionAndResume() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-acp-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let logURL = fixtureRoot.appendingPathComponent("argv.log")
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(logURL.path)'
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/load"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"fixture-new"}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        let workspace = Workspace(name: "fixture", path: fixtureRoot)
        let tabID = UUID()

        await process.start(workspace: workspace, options: GrokLaunchOptions(
            localTabID: tabID,
            permissionMode: "alwaysApprove",
            model: "grok-4.5",
            sandboxProfile: "default",
            resumeSessionID: "fixture-resume"
        ))
        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.sessionId, "fixture-resume")
        XCTAssertEqual(process.launchReceipt?.permissionMode, .alwaysApprove)
        XCTAssertEqual(process.launchReceipt?.permissionArguments, ["--always-approve"])
        XCTAssertEqual(process.launchReceipt?.localTabID, tabID)
        XCTAssertEqual(process.launchReceipt?.workspaceID, workspace.id)
        XCTAssertEqual(process.launchReceipt?.backendSessionID, "fixture-resume")
        XCTAssertEqual(process.launchReceipt?.outcome, .loaded)
        XCTAssertEqual(process.modelExecutionState.status, .requested)
        XCTAssertEqual(process.modelExecutionState.requestedModelID, "grok-4.5")
        XCTAssertNil(process.modelExecutionState.effectiveModelID)
        let firstGeneration = process.processGeneration

        await process.start(workspace: workspace, options: GrokLaunchOptions(
            localTabID: tabID,
            permissionMode: "default",
            model: "grok-4.5",
            sandboxProfile: "default",
            resumeSessionID: "fixture-resume"
        ))
        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.sessionId, "fixture-resume")
        XCTAssertEqual(process.launchReceipt?.permissionMode, .ask)
        XCTAssertEqual(process.launchReceipt?.permissionArguments, [])
        XCTAssertEqual(process.processGeneration, firstGeneration + 1)
        XCTAssertEqual(process.activeProcessGeneration, process.processGeneration)

        let launches = try String(contentsOf: logURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(launches.count, 2)
        XCTAssertTrue(launches[0].contains("--always-approve"))
        XCTAssertFalse(launches[1].contains("--always-approve"))
        await process.stop()
    }

    func testProcessKeepsAcceptedModelRequestUnconfirmedWithoutEffectiveReadback() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-model-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"model-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )
        XCTAssertEqual(process.modelExecutionState.status, .confirmed)
        XCTAssertEqual(process.currentModelId, "grok-4.5")

        let handle = try XCTUnwrap(process.setModel("gpt-5.6-terra"))
        let result = await handle.result.value
        XCTAssertEqual(result.status, .requested)
        XCTAssertEqual(result.requestedModelID, "gpt-5.6-terra")
        XCTAssertEqual(result.effectiveModelID, "grok-4.5")
        XCTAssertEqual(process.currentModelId, "grok-4.5")
        await process.stop()
    }

    func testFailedProcessLaunchCannotLeaveAnActiveOrRequestedReceipt() async {
        let missingCLI = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-grok-\(UUID().uuidString)")
        GrokProcess.cliOverrideForTests = missingCLI
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()

        await process.start(
            workspace: Workspace(
                name: "fixture",
                path: FileManager.default.temporaryDirectory
            ),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )

        XCTAssertNil(process.activeProcessGeneration)
        XCTAssertEqual(process.launchReceipt?.outcome, .failed)
        XCTAssertEqual(process.modelExecutionState.status, .rejected)
        XCTAssertEqual(process.modelExecutionState.failure, .unknown)
    }

    func testAdvertisedTerminalCapabilityHasWorkingLifecycle() async throws {
        XCTAssertEqual(GrokProcess.clientCapabilities["terminal"] as? Bool, true)

        let manager = ACPClientTerminalManager()
        let terminalID = try manager.create(
            command: "/usr/bin/printf",
            arguments: ["terminal-contract-ok"],
            environment: [:],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            outputByteLimit: 1_024
        )

        let exit = try await manager.waitForExit(terminalID: terminalID)
        XCTAssertEqual(exit, .init(exitCode: 0, signal: nil))
        let snapshot = try manager.snapshot(terminalID: terminalID)
        XCTAssertEqual(snapshot.output, "terminal-contract-ok")
        XCTAssertFalse(snapshot.truncated)
        XCTAssertEqual(snapshot.exitStatus, exit)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: snapshot.jsonObject))

        try manager.release(terminalID: terminalID)
        XCTAssertThrowsError(try manager.snapshot(terminalID: terminalID))
    }

    func testTerminalOutputRetainsBoundedValidUTF8Suffix() async throws {
        let manager = ACPClientTerminalManager()
        let terminalID = try manager.create(
            command: "/usr/bin/printf",
            arguments: ["éééé"],
            environment: [:],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            outputByteLimit: 5
        )
        _ = try await manager.waitForExit(terminalID: terminalID)
        let snapshot = try manager.snapshot(terminalID: terminalID)
        XCTAssertTrue(snapshot.truncated)
        XCTAssertLessThanOrEqual(snapshot.output.utf8.count, 5)
        XCTAssertFalse(snapshot.output.contains("�"))
        try manager.release(terminalID: terminalID)
    }

    func testGrokCombinedShellCommandCompatibility() async throws {
        let manager = ACPClientTerminalManager()
        let terminalID = try manager.create(
            command: "/bin/bash -lc \"printf combined-command-ok\"",
            arguments: [],
            environment: [:],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            outputByteLimit: 1_024
        )
        let exit = try await manager.waitForExit(terminalID: terminalID)
        XCTAssertEqual(exit.exitCode, 0)
        XCTAssertEqual(try manager.snapshot(terminalID: terminalID).output, "combined-command-ok")
        try manager.release(terminalID: terminalID)
    }

    func testToolCallFailureStatusAndMessageSurviveACPParsing() {
        let process = GrokProcess()
        let parsed = process.parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-1",
            "kind": "execute",
            "title": "Run command",
            "status": "failed",
            "content": [[
                "type": "content",
                "content": ["type": "text", "text": "Tool failed"]
            ]],
            "rawOutput": [
                "error": "tool_execution_failed",
                "message": "Terminal exited with status 2"
            ]
        ])

        XCTAssertEqual(parsed?.id, "call-1")
        XCTAssertEqual(parsed?.status, "failed")
        XCTAssertEqual(parsed?.detail, "Terminal exited with status 2")
    }

    func testFreshModelCatalogFallbackIsCurrentGrok() {
        let suiteName = "grokbuild.tests.models.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let models = GrokModelCatalog.cachedOrFallback(defaults: defaults)
        XCTAssertEqual(models.map(\.id), ["grok-4.5"])
        XCTAssertEqual(models.first?.name, "Grok 4.5")
        XCTAssertEqual(models.first?.isDefault, true)
    }

    func testComposerControlsMeetMinimumPointerTarget() {
        XCTAssertGreaterThanOrEqual(ComposerControlMetrics.minimumHitTarget, 36)
    }

    func testSettingsCredentialLoadingLeavesMainThread() async {
        let ranOnMainThread = await SettingsBackgroundLoader.run { Thread.isMainThread }
        XCTAssertFalse(ranOnMainThread)
    }

    func testTranscriptWorkingIndicatorHasNoPeriodicInvalidationLoop() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("GrokBuild/Views/GrokChatChrome.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("TimelineView("))
        XCTAssertTrue(source.contains("Text(\"Agent working…\")"))
    }

    func testRestoredTranscriptSchedulesSettledAutoScrollOnAppearance() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("GrokBuild/Views/ChatView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Settings navigation and tab restoration recreate ChatView"))
        XCTAssertTrue(
            source.contains(
                """
                .onAppear {
                                    // Settings navigation and tab restoration recreate ChatView, so
                                    // populated transcripts must reopen at the latest answer.
                                    scheduleSettledAutoScroll(proxy: proxy)
                                }
                """
            )
        )
    }

    func testLazyRestoredTabResumesSavedSessionBeforeSending() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("GrokBuild/Services/ChatStore.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("starting without its id"))
        XCTAssertTrue(source.contains("await restartProcess(resumeSessionID: savedGrokSessionID)"))
    }

    func testSavedBackendCannotStartOrSendBeforeContinuityGateAllowsIt() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("GrokBuild/Services/ChatStore.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let restartStart = try XCTUnwrap(source.range(of: "private func restartProcess"))
        let processStart = try XCTUnwrap(
            source.range(of: "await process.start", range: restartStart.upperBound..<source.endIndex)
        )
        let preStart = String(source[restartStart.lowerBound..<processStart.lowerBound])
        XCTAssertTrue(preStart.contains("await verifyContinuityBeforeResume"))
        XCTAssertTrue(preStart.contains("SessionSendGate.decision(for: status) != .block"))

        let deliveryStart = try XCTUnwrap(source.range(of: "private func deliverPrompt"))
        let deliveryEnd = try XCTUnwrap(
            source.range(of: "// MARK:", range: deliveryStart.upperBound..<source.endIndex)
        )
        let delivery = String(source[deliveryStart.lowerBound..<deliveryEnd.lowerBound])
        XCTAssertTrue(delivery.contains("guard SessionSendGate.decision(for: continuityStatus) != .block"))
        XCTAssertTrue(source.contains("else if !isSameContinuityBinding"))

        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        let selectionStart = try XCTUnwrap(contentSource.range(of: "private func selectSession("))
        let selectionEnd = try XCTUnwrap(
            contentSource.range(of: "private func noteSessionUsed", range: selectionStart.upperBound..<contentSource.endIndex)
        )
        let selection = String(contentSource[selectionStart.lowerBound..<selectionEnd.lowerBound])
        XCTAssertTrue(selection.contains("SessionMessageStore.messages(for: id)"))
        XCTAssertTrue(selection.contains("continuityPermitsAuthoritativeReconciliation"))
    }

    func testRecoveryCandidatesRemainExplicitAndRecoveryActionsDoNotStartAProcess() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        let chatStoreSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )

        let restoreStart = try XCTUnwrap(contentSource.range(of: "private func restorePersistedSessions"))
        let restoreEnd = try XCTUnwrap(
            contentSource.range(of: "private func restoredTitle", range: restoreStart.upperBound..<contentSource.endIndex)
        )
        let restore = String(contentSource[restoreStart.lowerBound..<restoreEnd.lowerBound])
        XCTAssertFalse(restore.contains("recoveryCandidates"))
        XCTAssertFalse(restore.contains("recoveryHistoryURLs"))

        let persistenceStart = try XCTUnwrap(contentSource.range(of: "private func persistSessionLayout"))
        let persistenceEnd = try XCTUnwrap(
            contentSource.range(of: "// MARK: - Logic", range: persistenceStart.upperBound..<contentSource.endIndex)
        )
        let persistence = String(contentSource[persistenceStart.lowerBound..<persistenceEnd.lowerBound])
        XCTAssertTrue(persistence.contains("session.store.persistedPendingRecoveryIntent == nil"))
        XCTAssertTrue(persistence.contains("pendingRecoveryIntent: session.store.persistedPendingRecoveryIntent"))

        let continueStart = try XCTUnwrap(chatStoreSource.range(of: "func continueAsNew"))
        let relinkStart = try XCTUnwrap(
            chatStoreSource.range(of: "func relink", range: continueStart.upperBound..<chatStoreSource.endIndex)
        )
        let continueAction = String(chatStoreSource[continueStart.lowerBound..<relinkStart.lowerBound])
        XCTAssertFalse(continueAction.contains("restartProcess"))
        XCTAssertFalse(continueAction.contains("process.start"))

        let relinkEnd = try XCTUnwrap(
            chatStoreSource.range(of: "private enum SessionRecoveryReviewError", range: relinkStart.upperBound..<chatStoreSource.endIndex)
        )
        let relinkAction = String(chatStoreSource[relinkStart.lowerBound..<relinkEnd.lowerBound])
        XCTAssertTrue(relinkAction.contains("verifyContinuity"))
        XCTAssertFalse(relinkAction.contains("restartProcess"))
        XCTAssertFalse(relinkAction.contains("process.start"))
    }

    func testAppUpdatePaneObservesFreshUpdateReceipts() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("GrokBuild/Views/SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private struct AppUpdatesSettingsPane"))
        XCTAssertTrue(source.contains("publisher(for: .grokBuildUpdateStateChanged)"))
        XCTAssertTrue(source.contains("updateRevision &+= 1"))
    }

    func testWorkbenchStatusIsVisibleAndAgentIsNotPresentedAsAChatbot() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        let bubbleSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/MessageBubble.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(chatSource.contains("@State private var showSessionControls = true"))
        XCTAssertTrue(chatSource.contains("Build Workspace"))
        XCTAssertTrue(chatSource.contains("Text(connectionSubtitle)"))
        XCTAssertTrue(bubbleSource.contains("Text(\"Build agent\")"))
        XCTAssertFalse(bubbleSource.contains("Text(\"Grok\")"))
    }
}
