import XCTest
@testable import GrokBuild

final class ACPClientContractTests: XCTestCase {
    func testChildSessionLedgerImportsTypedTerminalReceiptsWithoutTrustingChildProse() throws {
        let process = GrokProcess()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-child-receipts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = URL(fileURLWithPath: "/tmp/grok child receipt workspace % ready")
        let childID = "child-123"
        let childDirectory = root
            .appendingPathComponent(GrokSessionTranscriptImporter.encodeWorkspacePath(workspace), isDirectory: true)
            .appendingPathComponent(childID, isDirectory: true)
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        let rows = [
            #"{"method":"session/update","params":{"sessionId":"child-123","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"I used invented__browser_tool successfully"}}}}"#,
            #"{"method":"session/update","params":{"sessionId":"child-123","update":{"sessionUpdate":"tool_call_update","toolCallId":"search-1","status":"completed","rawInput":{"variant":"SearchTool","query":"grokbuild-browser__browser_open_url"},"rawOutput":{"type":"SearchTool","content":"{\"results\":[{\"server\":\"grokbuild-browser\",\"tools\":[{\"tool_name\":\"grokbuild-browser__browser_open_url\"}]}]}"}}}}"#,
            #"{"method":"session/update","params":{"sessionId":"child-123","update":{"sessionUpdate":"tool_call_update","toolCallId":"use-1","status":"completed","rawInput":{"variant":"UseTool","tool_name":"grokbuild-browser__browser_open_url"},"rawOutput":{"type":"MCP","server_name":"grokbuild-browser","tool_name":"browser_open_url","output":{"OkayOutput":"marker"}}}}}"#,
            #"{"method":"session/update","params":{"sessionId":"other-child","update":{"sessionUpdate":"tool_call_update","toolCallId":"foreign","status":"completed","rawInput":{"variant":"UseTool","tool_name":"foreign__tool"}}}}"#,
        ]
        try rows.joined(separator: "\n").write(
            to: childDirectory.appendingPathComponent("updates.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let receipts = try XCTUnwrap(process.loadChildToolReceipts(
            childID: childID,
            workspacePath: workspace,
            sessionsRoot: root
        ))

        XCTAssertEqual(receipts.count, 2)
        XCTAssertEqual(receipts.map(\.mcpReceiptRole), [.discovery, .invocation])
        XCTAssertEqual(receipts[0].discoveredQualifiedToolNames, ["grokbuild-browser__browser_open_url"])
        XCTAssertEqual(receipts[1].qualifiedToolName, "grokbuild-browser__browser_open_url")
        XCTAssertEqual(receipts[1].status, .succeeded)
        XCTAssertFalse(receipts.contains { $0.qualifiedToolName == "invented__browser_tool" })
        XCTAssertFalse(receipts.contains { $0.qualifiedToolName == "foreign__tool" })
    }

    func testChildSessionLedgerRejectsTraversalIdentity() {
        let process = GrokProcess()
        XCTAssertNil(process.loadChildToolReceipts(
            childID: "../other",
            workspacePath: URL(fileURLWithPath: "/tmp/workspace"),
            sessionsRoot: FileManager.default.temporaryDirectory
        ))
    }

    func testMirroredChildToolReceiptsNeverBecomeParentTools() {
        let childReceipts = [
            ChildToolReceipt(
                id: "child-search",
                title: "search_tool",
                status: .succeeded,
                mcpReceiptRole: .discovery,
                qualifiedToolName: nil,
                discoveredQualifiedToolNames: ["grokbuild-browser__browser_open_url"]
            ),
            ChildToolReceipt(
                id: "child-use",
                title: "grokbuild-browser__browser_open_url",
                status: .succeeded,
                mcpReceiptRole: .invocation,
                qualifiedToolName: "grokbuild-browser__browser_open_url",
                discoveredQualifiedToolNames: []
            ),
        ]

        XCTAssertEqual(
            ChatStore.parentToolCallIDs(
                observedIDs: ["parent-spawn", "child-search", "child-use", "parent-collect"],
                childReceipts: childReceipts
            ),
            ["parent-spawn", "parent-collect"]
        )
    }

    func testQuestionReducerCoalescesOnlyTheSameAuthoritativeRequestIdentity() {
        let question = QuestionItem(
            id: "audience",
            text: "Which audience should this target?",
            options: [QuestionOption(label: "Consumer", description: nil)],
            multiSelect: false
        )
        let original = QuestionRequest(
            id: AnyHashable(42),
            sessionId: "session",
            questions: [question],
            isResolved: false,
            answerSummary: nil
        )
        let replay = QuestionRequest(
            id: AnyHashable(42),
            sessionId: "session",
            questions: [question],
            isResolved: false,
            answerSummary: "updated"
        )

        var pending = QuestionRequest.merging(original, into: [])
        pending = QuestionRequest.merging(replay, into: pending)

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].id, replay.id)
        XCTAssertEqual(pending[0].answerSummary, "updated")
    }

    func testIdenticalQuestionContentWithDifferentRPCIDsRemainsTwoRequests() {
        let question = QuestionItem(
            id: "audience",
            text: "Which audience should this target?",
            options: [],
            multiSelect: false
        )
        let first = QuestionRequest(
            id: AnyHashable(42),
            sessionId: "session",
            questions: [question],
            isResolved: false,
            answerSummary: nil
        )
        let second = QuestionRequest(
            id: AnyHashable(43),
            sessionId: "session",
            questions: [question],
            isResolved: false,
            answerSummary: nil
        )

        var pending = QuestionRequest.merging(first, into: [])
        pending = QuestionRequest.merging(second, into: pending)

        XCTAssertEqual(pending.map(\.id), [first.id, second.id])
    }

    func testDifferentQuestionsRemainIndependent() {
        let first = QuestionRequest(
            id: AnyHashable(1),
            sessionId: "session",
            questions: [QuestionItem(id: "one", text: "First?", options: [], multiSelect: false)],
            isResolved: false,
            answerSummary: nil
        )
        let second = QuestionRequest(
            id: AnyHashable(2),
            sessionId: "session",
            questions: [QuestionItem(id: "two", text: "Second?", options: [], multiSelect: false)],
            isResolved: false,
            answerSummary: nil
        )

        var pending = QuestionRequest.merging(first, into: [])
        pending = QuestionRequest.merging(second, into: pending)

        XCTAssertEqual(pending.map(\.id), [first.id, second.id])
    }

    func testInteractionIdentityIncludesBackendSession() {
        XCTAssertTrue(ACPInteractionRequestIdentity.matches(
            lhsID: AnyHashable(7),
            lhsSessionID: "backend-a",
            rhsID: AnyHashable(7),
            rhsSessionID: "backend-a"
        ))
        XCTAssertFalse(ACPInteractionRequestIdentity.matches(
            lhsID: AnyHashable(7),
            lhsSessionID: "backend-a",
            rhsID: AnyHashable(7),
            rhsSessionID: "backend-b"
        ))
        XCTAssertFalse(ACPInteractionRequestIdentity.ownsActiveSession(
            "backend-a",
            activeSessionID: "backend-b"
        ))
    }

    func testPlanReplayPreservesPreviouslyObservedPlanText() {
        let current = ExitPlanRequest(
            id: AnyHashable(9),
            sessionId: "backend",
            planText: "# Native plan",
            isResolved: false,
            verdict: nil
        )
        let replay = ExitPlanRequest(
            id: AnyHashable(9),
            sessionId: "backend",
            planText: "",
            isResolved: false,
            verdict: nil
        )

        XCTAssertEqual(ExitPlanRequest.merging(replay, into: current).planText, "# Native plan")
    }

    @MainActor
    func testPlanApprovalAnswersOneACPRequestWithoutCreatingASecondPrompt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-plan-interaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rpcLogURL = root.appendingPathComponent("rpc.log")
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        prompt_rpc_id=''
        while IFS= read -r line; do
          printf '%s\n' "$line" >> '\(rpcLogURL.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"plan-backend","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id" ;;
            *'"method":"session/prompt"'*)
              prompt_rpc_id="$id"
              printf '{"jsonrpc":"2.0","id":77,"method":"_x.ai/exit_plan_mode","params":{"sessionId":"plan-backend","toolCallId":"plan-tool","planContent":"# One native plan"}}\n'
              ;;
            *'"outcome":"approved"'*)
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"plan-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn"}}}\n'
              printf '{"jsonrpc":"2.0","id":%s,"result":{"stopReason":"end_turn"}}\n' "$prompt_rpc_id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "plan-interaction", path: root))

        let sendTask = Task { @MainActor in await store.sendAndWait("Show one native plan") }
        for _ in 0..<200 where store.pendingExitPlan == nil {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        guard let request = store.pendingExitPlan else {
            let rpc = (try? String(contentsOf: rpcLogURL, encoding: .utf8)) ?? "missing log"
            let failure = store.lastError ?? "none"
            XCTFail("Missing plan request; process=\(store.process.state), connection=\(store.connectionState), error=\(failure), rpc=\(rpc)")
            await store.shutdownPermanently()
            _ = await sendTask.value
            return
        }
        XCTAssertEqual(request.id, AnyHashable(77))
        XCTAssertEqual(request.sessionId, "plan-backend")
        store.respondToExitPlan(request, verdict: .approved)

        let sent = await sendTask.value
        XCTAssertTrue(sent)
        XCTAssertNil(store.pendingExitPlan)
        XCTAssertEqual(store.messages.filter { $0.role == .user }.map(\.content), ["Show one native plan"])

        let rpcLines = try String(contentsOf: rpcLogURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(rpcLines.filter { $0.contains("\"method\":\"session/prompt\"") }.count, 1)
        XCTAssertEqual(rpcLines.filter {
            $0.contains("\"id\":77") && $0.contains("\"outcome\":\"approved\"")
        }.count, 1)
        XCTAssertFalse(rpcLines.contains { $0.contains("[Plan approved]") })
        await store.shutdownPermanently()
    }

    func testSubagentTerminalDeduplicationUsesWorkerLifecycleIdentity() {
        let tabID = UUID()
        let first = SubagentFinishedEvent(
            identity: ACPEventIdentity(
                localTabID: tabID,
                backendSessionID: "parent",
                processGeneration: 4,
                backendEventID: "event-a"
            ),
            childID: "child",
            status: "completed",
            durationMilliseconds: 100,
            turns: 1,
            toolCallCount: 2,
            tokenCount: 3,
            redactedError: nil
        )
        let replay = SubagentFinishedEvent(
            identity: ACPEventIdentity(
                localTabID: tabID,
                backendSessionID: "parent",
                processGeneration: 4,
                backendEventID: "event-b"
            ),
            childID: "child",
            status: "completed",
            durationMilliseconds: 100,
            turns: 1,
            toolCallCount: 2,
            tokenCount: 3,
            redactedError: nil
        )

        XCTAssertEqual(first.deduplicationKey, replay.deduplicationKey)
        XCTAssertFalse(first.deduplicationKey.contains("event-a"))
    }

    func testSubagentLifecycleErrorsAreRedactedAndBounded() throws {
        let secret = "super-secret-worker-token"
        let raw = "token=\(secret) " + String(repeating: "failure ", count: 80)
        let redacted = try XCTUnwrap(GrokProcess.redactedLifecycleText(raw))

        XCTAssertFalse(redacted.contains(secret))
        XCTAssertTrue(redacted.contains("<redacted>"))
        XCTAssertLessThanOrEqual(redacted.count, 280)
    }

    func testACPEventsStayOnTheParentSessionWhenWorkerSessionsStream() {
        let params: [String: Any] = [
            "sessionId": "worker-session",
            "update": ["sessionUpdate": "agent_message_chunk"]
        ]
        let update = params["update"] as? [String: Any]

        XCTAssertEqual(
            GrokProcess.eventSessionID(from: params, update: update),
            "worker-session"
        )
        XCTAssertFalse(
            GrokProcess.eventBelongsToSession("worker-session", currentSessionID: "parent-session")
        )
        XCTAssertTrue(
            GrokProcess.eventBelongsToSession(nil, currentSessionID: "parent-session")
        )
        XCTAssertTrue(
            GrokProcess.eventBelongsToSession("parent-session", currentSessionID: "parent-session")
        )
    }

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

        var backendFailure = TurnSettlementCoordinator()
        let backendFailureID = UUID()
        let backendFailureGeneration = backendFailure.begin(assistantID: backendFailureID)
        XCTAssertNil(backendFailure.recordPromptResult(generation: backendFailureGeneration, ok: true))
        XCTAssertEqual(
            backendFailure.recordCompletionConsumed(ok: false),
            .init(assistantID: backendFailureID, ok: false),
            "an authoritative ACP error completion must not be promoted to success"
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

    func testFreshSessionRecoveryPreservesTheRequestedModelOnlyWhileItIsAvailable() {
        XCTAssertEqual(
            ChatStore.recoverableModelForNewSession(
                "deepseek-deepseek-v4-flash-0731",
                availableModels: ["grok-4.5", "deepseek-deepseek-v4-flash-0731"]
            ),
            "deepseek-deepseek-v4-flash-0731"
        )
        XCTAssertNil(ChatStore.recoverableModelForNewSession(
            "deepseek-deepseek-v4-flash-0731",
            availableModels: ["grok-4.5"]
        ))
        XCTAssertNil(ChatStore.recoverableModelForNewSession(
            nil,
            availableModels: ["grok-4.5"]
        ))
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
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
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
        XCTAssertEqual(process.modelExecutionState.status, .confirmed)
        XCTAssertEqual(process.modelExecutionState.requestedModelID, "grok-4.5")
        XCTAssertEqual(process.modelExecutionState.effectiveModelID, "grok-4.5")
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

    func testLaunchReassertsCustomModelAfterACPNewSessionDefaultsToGrok() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-launch-model-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rpcLogURL = fixtureRoot.appendingPathComponent("rpc.log")
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\n' "$line" >> '\(rpcLogURL.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"custom-model-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"gpt-5.6-terra"}}}}\n' "$id"
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
            options: GrokLaunchOptions(localTabID: UUID(), model: "gpt-5.6-terra")
        )

        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.currentModelId, "gpt-5.6-terra")
        XCTAssertEqual(process.modelExecutionState.status, .confirmed)
        XCTAssertEqual(process.modelExecutionState.requestedModelID, "gpt-5.6-terra")
        XCTAssertEqual(process.modelExecutionState.effectiveModelID, "gpt-5.6-terra")
        let rpcLog = try String(contentsOf: rpcLogURL, encoding: .utf8)
        XCTAssertTrue(rpcLog.contains("\"method\":\"session/set_model\""))
        XCTAssertTrue(rpcLog.contains("\"modelId\":\"gpt-5.6-terra\""))
        await process.stop()
    }

    func testLaunchFailsClosedWhenACPConfirmsTheWrongModel() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-wrong-model-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"wrong-model-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id"
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
            options: GrokLaunchOptions(localTabID: UUID(), model: "gpt-5.6-terra")
        )

        guard case .failed(let message) = process.state else {
            return XCTFail("Expected startup to fail closed, got \(process.state)")
        }
        XCTAssertTrue(message.contains("confirmed grok-4.5 instead of the requested model gpt-5.6-terra"))
        XCTAssertEqual(process.modelExecutionState.status, .rejected)
        XCTAssertNil(process.activeProcessGeneration)
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

    func testLiveModelSwitchRejectsAnUnexpectedEffectiveReadback() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-model-mismatch-fixture-\(UUID().uuidString)", isDirectory: true)
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
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"model-mismatch-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"unrelated-provider/model"}}}}\\n' "$id"
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
        XCTAssertEqual(process.state, .ready)

        let handle = try XCTUnwrap(process.setModel("gpt-5.6-terra"))
        let result = await handle.result.value
        XCTAssertEqual(result.status, .rejected)
        XCTAssertTrue(process.modelSwitchNeedsNewSession)
        XCTAssertTrue(process.modelSwitchError?.contains("unrelated-provider/model") == true)
        guard case .failed = process.state else {
            return XCTFail("An unexpected effective model must make the process unsendable")
        }
        await process.stop()
    }

    @MainActor
    func testUnavailableExplicitModelRemainsTheFailClosedTabSelection() async {
        let store = ChatStore()
        store.prepare(workspace: Workspace(
            name: "fixture",
            path: FileManager.default.temporaryDirectory
        ))
        store.bindTabSession(
            UUID(),
            modelIntent: .explicit("removed-custom-model")
        )

        XCTAssertEqual(store.persistedModelIntent, .explicit("removed-custom-model"))
        XCTAssertTrue(store.modelSelectorDisplayLabel.hasPrefix("removed-custom-model"))
        await store.shutdownPermanently()
    }

    func testModelChoiceIsBlockedWhileATurnIsStreaming() {
        XCTAssertEqual(
            ChatStore.modelSwitchSafetyBlock(
                isStreaming: true,
                hasProviderSpecificHistory: false
            ),
            .activeTurn
        )
    }

    func testAnyAssistantHistoryRequiresANewSessionBeforeChangingModel() {
        let messages = [
            Message(role: .user, content: "Inspect it"),
            Message(
                role: .assistant,
                content: "Done",
                assistantTrace: AssistantTurnTrace(
                    reasoningSummaryChunks: [],
                    thinkingDuration: nil,
                    tools: [
                        .init(
                            id: "tool-1",
                            title: "Web search",
                            status: "Succeeded",
                            mcpServerName: nil
                        )
                    ]
                )
            ),
        ]
        XCTAssertTrue(ChatStore.hasProviderSpecificHistory(in: messages))
        XCTAssertEqual(
            ChatStore.modelSwitchSafetyBlock(
                isStreaming: false,
                hasProviderSpecificHistory: true
            ),
            .providerHistory
        )
    }

    func testPlainAssistantHistoryIsProviderSpecificEvenWithoutTools() {
        let messages = [
            Message(role: .user, content: "Say hello"),
            Message(role: .assistant, content: "Hello"),
        ]
        XCTAssertTrue(ChatStore.hasProviderSpecificHistory(in: messages))
        XCTAssertEqual(
            ChatStore.modelSwitchSafetyBlock(
                isStreaming: false,
                hasProviderSpecificHistory: true
            ),
            .providerHistory
        )
    }

    func testMCPGatewayPolicyDefaultsOffAndRequiresExplicitSelection() {
        XCTAssertFalse(ChatStore.mcpGatewayEnabled(
            selectedPromptMCPNames: [],
            enabledBuiltInToolNames: []
        ))
        XCTAssertTrue(ChatStore.mcpGatewayEnabled(
            selectedPromptMCPNames: ["chrome-devtools"],
            enabledBuiltInToolNames: []
        ))
        XCTAssertTrue(ChatStore.mcpGatewayEnabled(
            selectedPromptMCPNames: [],
            enabledBuiltInToolNames: [BuiltInToolConnection.browser.rawValue]
        ))
    }

    func testCLIConfiguredMCPNotificationNamesAreCredentialFreeAndSorted() {
        XCTAssertEqual(
            GrokProcess.mcpServerNames(from: [
                "mcpServers": [
                    ["name": "chrome-devtools", "url": "http://secret.invalid"],
                    ["server_name": "alpha"],
                    ["name": "chrome-devtools"],
                ]
            ]),
            ["alpha", "chrome-devtools"]
        )
    }

    func testACPErrorCompletionIsAnAuthoritativeFailure() {
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend",
            processGeneration: 9,
            backendEventID: "event"
        )
        let receipt = TurnCompletionReceipt(
            identity: identity,
            promptID: "prompt",
            stopReason: "error",
            redactedError: GrokProcess.redactedLifecycleText("API error: encrypted reasoning could not be verified"),
            totalTokens: nil,
            modelCalls: nil,
            turnCount: nil
        )
        XCTAssertTrue(receipt.isFailure)
        XCTAssertEqual(receipt.redactedError, "API error: encrypted reasoning could not be verified")

        let success = TurnCompletionReceipt(
            identity: identity,
            promptID: "prompt",
            stopReason: "end_turn",
            redactedError: nil,
            totalTokens: 12,
            modelCalls: 1,
            turnCount: 1
        )
        XCTAssertFalse(success.isFailure)
        XCTAssertTrue(success.isSuccessful)

        let cancelled = TurnCompletionReceipt(
            identity: identity,
            promptID: "prompt",
            stopReason: "cancelled",
            redactedError: nil,
            totalTokens: 12,
            modelCalls: 1,
            turnCount: 1
        )
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertFalse(cancelled.isSuccessful)
        XCTAssertFalse(cancelled.isFailure)
    }

    func testCustomLaunchAcceptsOnlyItsDeclaredProviderModelReadback() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-custom-alias-fixture-\(UUID().uuidString)", isDirectory: true)
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
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"custom-alias-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"deepseek/deepseek-v4-flash-0731"}}}}\\n' "$id"
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
            options: GrokLaunchOptions(
                localTabID: UUID(),
                model: "deepseek-deepseek-v4-flash-0731",
                expectedEffectiveModelID: "deepseek/deepseek-v4-flash-0731"
            )
        )

        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.modelExecutionState.requestedModelID, "deepseek-deepseek-v4-flash-0731")
        XCTAssertEqual(process.modelExecutionState.effectiveModelID, "deepseek/deepseek-v4-flash-0731")
        await process.stop()
    }

    func testLiveCustomModelSwitchAcceptsOnlyItsDeclaredProviderAlias() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-live-custom-alias-fixture-\(UUID().uuidString)", isDirectory: true)
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
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"live-custom-alias-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"deepseek/deepseek-v4-flash-0731"}}}}\\n' "$id"
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

        let handle = try XCTUnwrap(process.setModel(
            "deepseek-deepseek-v4-flash-0731",
            expectedEffectiveModelID: "deepseek/deepseek-v4-flash-0731"
        ))
        let result = await handle.result.value
        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.requestedModelID, "deepseek-deepseek-v4-flash-0731")
        XCTAssertEqual(result.effectiveModelID, "deepseek/deepseek-v4-flash-0731")
        XCTAssertEqual(process.state, .ready)
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
            "kind": "unknown",
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
        XCTAssertEqual(parsed?.terminalStatus, .failed)
        XCTAssertEqual(parsed?.diagnosticDetail, #"{"error":"tool_execution_failed","message":"Terminal exited with status 2"}"#)
    }

    func testSuccessfulTerminalReceiptProjectsOutputInsteadOfProtocolJSON() {
        let rawOutput: [String: Any] = [
            "command": "./check.sh",
            "exit_code": 0,
            "output": [71, 66, 45, 84, 69, 83, 84, 83, 45, 80, 65, 83, 83, 69, 68, 10],
            "output_file": "/private/backend/path",
        ]
        let rawOutputData = try! JSONSerialization.data(withJSONObject: rawOutput)
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-output",
            "kind": "execute",
            "title": "Run checks",
            "status": "completed",
            "rawOutput": String(decoding: rawOutputData, as: UTF8.self),
        ])

        XCTAssertEqual(parsed?.detail, "GB-TESTS-PASSED")
        XCTAssertFalse(parsed?.detail?.contains("output_file") == true)
    }

    func testToolCallPreservesAuthoritativeMCPServerName() {
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "mcp-call-1",
            "toolName": "list_pages",
            "serverName": "chrome-devtools",
            "title": "List pages",
            "status": "in_progress",
        ])

        XCTAssertEqual(parsed?.rawInput?["serverName"] as? String, "chrome-devtools")
        XCTAssertEqual(parsed?.rawInput?["toolName"] as? String, "list_pages")
    }

    func testSearchToolParsesAsDiscoveryWithBoundedQualifiedCatalog() {
        let content = #"{"results":[{"server":"chrome-devtools","tools":[{"tool_name":"chrome-devtools__list_pages"},{"tool_name":"not safe"}]}]}"#
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "search-1",
            "status": "completed",
            "rawOutput": [
                "type": "SearchTool",
                "result_count": 2,
                "content": content,
            ],
        ])

        XCTAssertEqual(parsed?.mcpReceiptRole, .discovery)
        XCTAssertNil(parsed?.qualifiedToolName)
        XCTAssertEqual(parsed?.discoveredQualifiedToolNames, ["chrome-devtools__list_pages"])
        XCTAssertNil(parsed?.rawInput?["serverName"],
                     "catalog discovery is not a server-use receipt")
    }

    func testLiveSearchToolContentEnvelopeParsesAsDiscovery() {
        let content = #"{"results":[{"server":"chrome-devtools","tools":[{"tool_name":"chrome-devtools__list_pages","input_schema":{"type":"object"}}]}]}"#
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "live-search-1",
            "status": "completed",
            "content": [[
                "type": "content",
                "content": ["type": "text", "text": content],
                "rawOutput": [
                    "type": "SearchTool",
                    "result_count": 1,
                    "content": content,
                ],
            ]],
        ])

        XCTAssertEqual(parsed?.mcpReceiptRole, .discovery)
        XCTAssertEqual(parsed?.discoveredQualifiedToolNames, ["chrome-devtools__list_pages"])
        XCTAssertNil(parsed?.qualifiedToolName)
        XCTAssertNil(parsed?.rawInput?["serverName"],
                     "nested discovery output is still not an invocation receipt")
    }

    func testUseToolParsesQualifiedInvocationAndAuthoritativeServer() {
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "use-1",
            "title": "chrome-devtools__list_pages",
            "status": "completed",
            "rawInput": [
                "variant": "UseTool",
                "tool_name": "chrome-devtools__list_pages",
                "tool_input": [:],
            ],
            "rawOutput": [
                "type": "MCP",
                "server_name": "chrome-devtools",
                "tool_name": "list_pages",
                "output": ["OkayOutput": "## Pages"],
            ],
        ])

        XCTAssertEqual(parsed?.mcpReceiptRole, .invocation)
        XCTAssertEqual(parsed?.qualifiedToolName, "chrome-devtools__list_pages")
        XCTAssertEqual(parsed?.rawInput?["serverName"] as? String, "chrome-devtools")
        XCTAssertTrue(parsed?.discoveredQualifiedToolNames.isEmpty == true)
    }

    func testTerminalExitReceiptOverridesTransportCompletedStatus() {
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-nonzero",
            "kind": "execute",
            "title": "Run command",
            "status": "completed",
            "rawOutput": [
                "type": "Bash",
                "exit_code": 127,
                "timed_out": false,
            ],
        ])

        XCTAssertEqual(parsed?.status, "failed")
        XCTAssertEqual(parsed?.terminalStatus, .failed)
        XCTAssertEqual(parsed?.detail, "Command exited with status 127.")
    }

    func testTerminalArtifactReceiptRequiresAnExplicitSafeRedirection() {
        let artifact = ToolCall(
            id: "artifact",
            kind: "execute",
            title: "Write marker",
            rawInput: [
                "command": "printf '%s\\n' marker > /tmp/grokbuild-artifact.txt && cat /tmp/grokbuild-artifact.txt"
            ]
        )
        let stdoutOnly = ToolCall(
            id: "stdout",
            kind: "execute",
            title: "Print marker",
            rawInput: ["command": "printf '%s\\n' marker"]
        )
        let discarded = ToolCall(
            id: "discarded",
            kind: "execute",
            title: "Discard marker",
            rawInput: ["command": "printf marker > /dev/null"]
        )

        XCTAssertEqual(artifact.writtenFilePath, "/tmp/grokbuild-artifact.txt")
        XCTAssertNil(stdoutOnly.writtenFilePath)
        XCTAssertNil(discarded.writtenFilePath)
    }

    func testToolCallParserKeepsTargetAndExplicitRetryCorrelationWithoutInventingIt() {
        let process = GrokProcess()
        let correlated = process.parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-retry",
            "status": "completed",
            "retryOfToolCallId": "call-failed",
            "rawInput": ["url": "https://example.com/source"],
        ])
        let uncorrelated = process.parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-unrelated",
            "status": "completed",
            "rawInput": ["url": "https://example.com/source"],
        ])

        XCTAssertEqual(correlated?.target, "https://example.com/source")
        XCTAssertEqual(correlated?.retryOfToolCallID, "call-failed")
        XCTAssertNil(uncorrelated?.retryOfToolCallID)
    }

    func testToolTerminalStatusNormalizationKeepsOnlyKnownTerminalStates() {
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "completed"), .succeeded)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "rejected"), .failed)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "canceled"), .cancelled)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "superseded"), .stale)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "backend_mystery"), .unknown)
        XCTAssertNil(ToolCallTerminalStatus.from(rawStatus: "running"))
        XCTAssertNil(ToolCallTerminalStatus.from(rawStatus: nil))
    }

    func testToolSettlementChromeKeepsFailureSeparateFromParentCompletion() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chrome = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/GrokChatChrome.swift"),
            encoding: .utf8
        )
        let store = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(chrome.contains("Diagnostic payload"))
        XCTAssertTrue(chrome.contains("Failed · Recovered"))
        XCTAssertTrue(chrome.contains("tool calls failed"))
        XCTAssertTrue(chrome.contains("Run summary"))
        XCTAssertTrue(chrome.contains("explicit backend retry correlation"))
        XCTAssertTrue(chrome.contains("turnOutcome.displayName"))
        XCTAssertTrue(store.contains("settleToolCallsAtTurnBarrier()"))
        XCTAssertTrue(store.contains("else if completion.isCancelled"))
        XCTAssertTrue(store.contains(".cancelled"))
        XCTAssertTrue(store.contains("The agent reported no next action."))
        XCTAssertTrue(store.contains("Review unresolved worker receipts."))
        XCTAssertFalse(store.contains("No further action reported."))
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

    func testAuthoritativeCompletionDoesNotBypassPacedAnswerReveal() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let store = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        let completionStart = try XCTUnwrap(
            store.range(of: "case .turnCompleted(let completion):")
        )
        let completionEnd = try XCTUnwrap(
            store.range(
                of: "case .turnCompletionReceiptMissing",
                range: completionStart.upperBound..<store.endIndex
            )
        )
        let completionBlock = String(
            store[completionStart.lowerBound..<completionEnd.lowerBound]
        )

        XCTAssertTrue(completionBlock.contains("pendingCompletionReconciliation = true"))
        XCTAssertTrue(
            completionBlock.contains("reconcileCompletedTurnIfDisplayBufferIsSettled()")
        )
        XCTAssertFalse(completionBlock.contains("flushAllPendingAssistantText()"))
        XCTAssertFalse(completionBlock.contains("reconcileActiveTurnFromBackend()"))
    }

    @MainActor
    func testSingleFinalACPChunkRevealsInBatchesBeforeSettling() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-paced-reveal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let answer = String(repeating: "Smooth final answer segment. ", count: 80)
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"paced-backend","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id" ;;
            *'"method":"session/prompt"'*)
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"paced-backend","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"Checked the answer shape."}}}}\n'
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"paced-backend","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"\(answer)"}}}}\n'
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"paced-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn"}}}\n'
              printf '{"jsonrpc":"2.0","id":%s,"result":{"stopReason":"end_turn"}}\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "paced-reveal", path: root))

        let sendTask = Task { @MainActor in
            await store.sendAndWait("Reveal one final chunk smoothly")
        }
        var firstVisibleCount = 0
        for _ in 0..<200 {
            firstVisibleCount = store.messages.last(where: { $0.role == .assistant })?.content.count ?? 0
            if firstVisibleCount > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertGreaterThan(firstVisibleCount, 0)
        XCTAssertLessThan(firstVisibleCount, answer.count)
        XCTAssertTrue(store.isStreaming)
        XCTAssertEqual(store.thinkingText, "Checked the answer shape.")
        XCTAssertEqual(
            ChatTranscriptLayout.messageBlockOrder(
                containsAgentHeader: true,
                traceExpanded: true,
                containsThinking: true,
                containsToolActivity: false
            ),
            [.agentHeader, .thinking, .answer]
        )

        let sendSucceeded = await sendTask.value
        XCTAssertTrue(sendSucceeded)
        for _ in 0..<200 where store.isStreaming {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(
            store.messages.last(where: { $0.role == .assistant })?.content,
            answer
        )
        XCTAssertFalse(store.isStreaming)
        await store.shutdownPermanently()
    }

    @MainActor
    func testCancelledCompletionReleasesMissingPromptRPCResponse() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-cancelled-prompt-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"cancelled-backend","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id" ;;
            *'"method":"session/prompt"'*)
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"cancelled-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"cancelled","usage":{"totalTokens":42,"modelCalls":1,"numTurns":1}}}}\n'
              # Grok CLI 1.0 omits the matching JSON-RPC response on this path.
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "cancelled-prompt", path: root))

        let sendSucceeded = await store.sendAndWait("Exercise cancelled completion")

        XCTAssertTrue(sendSucceeded, "the authoritative ACP receipt releases the transport wait")
        XCTAssertEqual(store.latestTurnOutcome, .cancelled)
        XCTAssertFalse(store.isStreaming)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.runEvidenceSnapshot?.process.state, "Cancelled")
        XCTAssertEqual(store.runEvidenceSnapshot?.usage.totalTokens, 42)
        await store.shutdownPermanently()
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

        XCTAssertTrue(source.contains("silently resuming a mismatched backend"))
        XCTAssertTrue(source.contains("let forceFreshStart = forcedFreshStartAfterUserStop"))
        XCTAssertTrue(source.contains("resumeSessionID: savedGrokSessionID"))
        XCTAssertTrue(source.contains("forceFreshStart: forceFreshStart"))
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
            .appendingPathComponent("GrokBuild/Views/Settings/AppUpdatesSettingsPane.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("struct AppUpdatesSettingsPane"))
        XCTAssertTrue(source.contains("publisher(for: .grokBuildUpdateStateChanged)"))
        XCTAssertTrue(source.contains("updateRevision &+= 1"))
    }

    func testWorkbenchChromeKeepsBackendReceiptsInTheActivityDrawer() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        let bubbleSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/MessageBubble.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(chatSource.contains("@State private var showActivitySidebar = false"))
        XCTAssertTrue(chatSource.contains("private var activitySidebarToggle"))
        XCTAssertTrue(chatSource.contains("snapshot: store.runEvidenceSnapshot"))
        XCTAssertTrue(contentSource.contains("activeStore.recordGitReviewFiles"))
        XCTAssertTrue(contentSource.contains("refreshGitReviewFromTranscriptBoundary"))
        XCTAssertFalse(contentSource.contains("detectedDiffs(in:"))
        XCTAssertFalse(contentSource.contains("applyDiffs(from:"))
        let previewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/PreviewPane.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(previewSource.contains("Repository changes from Git"))
        XCTAssertTrue(previewSource.contains("Diffs come only\n    /// from Git") || previewSource.contains("This panel reflects a fresh Git working-tree snapshot."),
                      "the pane stays a Git-truth surface")
        XCTAssertFalse(previewSource.contains("Apply All"))
        XCTAssertFalse(chatSource.contains("SessionContinuityBanner("))
        XCTAssertTrue(chatSource.contains("What do you want to work on?"))
        XCTAssertTrue(chatSource.contains("private struct CodexPromptPill"))
        XCTAssertTrue(chatSource.contains("private var browserStatusIndicator"))
        XCTAssertTrue(chatSource.contains("private var computerUseStatusIndicator"))
        XCTAssertTrue(chatSource.contains("TextField(\"Describe a task\""))
        XCTAssertTrue(chatSource.contains("ComposerDensityPolicy.minimumLineCount...ComposerDensityPolicy.maximumLineCount"))
        // Codex parity Slice 4: the composer Details shelf and project status row
        // were deleted; no telemetry shelf may return below the composer.
        XCTAssertFalse(chatSource.contains("showComposerDetails"))
        XCTAssertFalse(chatSource.contains("composerDetailsDisclosure"))
        XCTAssertFalse(chatSource.contains("private var projectStatusRow"))

        let sidebarSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ActivitySidebar.swift"),
            encoding: .utf8
        )
        let artifactSection = try XCTUnwrap(sidebarSource.range(of: "section(\"Artifacts\""))
        let reviewSection = try XCTUnwrap(sidebarSource.range(of: "section(\"Files in review\""))
        XCTAssertLessThan(artifactSection.lowerBound, reviewSection.lowerBound)
        XCTAssertTrue(sidebarSource.contains("External artifact"))
        XCTAssertTrue(sidebarSource.contains("Files in review"))
        XCTAssertTrue(sidebarSource.contains("section(\"Workers\""))
        XCTAssertTrue(sidebarSource.contains("grok-activity-sidebar"))
        XCTAssertTrue(sidebarSource.contains("let snapshot: RunEvidenceSnapshot?"))
        XCTAssertFalse(sidebarSource.contains("store."))
        XCTAssertTrue(contentSource.contains(".onChange(of: activeStore.gitRefreshRevision)"))
        XCTAssertTrue(contentSource.contains("Task.sleep(for: .milliseconds(250))"))
        XCTAssertTrue(contentSource.contains("boundedGitRefreshTask?.cancel()"))
        XCTAssertFalse(bubbleSource.contains("Text(\"Build agent\")"),
                       "the dead bubble header branch stays deleted; turn identity lives in the ChatView header")
        XCTAssertFalse(bubbleSource.contains("Text(\"Grok\")"))
    }
}
