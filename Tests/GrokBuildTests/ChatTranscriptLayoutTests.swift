import XCTest
@testable import GrokBuild

final class ChatTranscriptLayoutTests: XCTestCase {
    func testComposerStartsAtOneAccessibleLineAndGrowsForLongWork() {
        XCTAssertEqual(ComposerDensityPolicy.minimumLineCount, 1)
        XCTAssertEqual(ComposerDensityPolicy.maximumLineCount, 8)
        XCTAssertEqual(
            ComposerDensityPolicy.editorMinimumHeight,
            ComposerControlMetrics.minimumHitTarget
        )
        XCTAssertGreaterThanOrEqual(ComposerDensityPolicy.editorMinimumHeight, 36)
    }

    func testAutoScrollRetriesThroughLateRichTextLayout() {
        let gaps = ChatAutoScrollPolicy.layoutSettleGapsMilliseconds
        XCTAssertEqual(gaps.first, 0)
        XCTAssertGreaterThanOrEqual(gaps.count, 6)
        XCTAssertGreaterThanOrEqual(gaps.reduce(0, +), 3_000)
        XCTAssertTrue(gaps.allSatisfy { $0 >= 0 })
    }

    func testMessageBlockIdentityIncludesOwningMessage() {
        let firstMessageID = UUID()
        let secondMessageID = UUID()
        let blocks: [ChatTranscriptLayout.MessageBlock] = [.agentHeader, .toolActivity, .answer]
        let first = ChatTranscriptLayout.identifiedMessageBlocks(
            messageID: firstMessageID,
            blocks: blocks
        )
        let second = ChatTranscriptLayout.identifiedMessageBlocks(
            messageID: secondMessageID,
            blocks: blocks
        )

        XCTAssertEqual(first.map(\.block), blocks)
        XCTAssertEqual(Set(first).count, blocks.count)
        XCTAssertTrue(first.allSatisfy { $0.messageID == firstMessageID })
        XCTAssertTrue(Set(first).isDisjoint(with: Set(second)))
    }

    func testRestoreSettlementCoalescesAndFreezesSelectableTranscript() throws {
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
        let richSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/RichMessageView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(chatSource.contains("guard autoScrollTask == nil else"))
        XCTAssertTrue(chatSource.contains("autoScrollTrailingPassRequested = true"))
        XCTAssertTrue(chatSource.contains("guard !transcriptSessionTransitionInProgress else"))
        XCTAssertTrue(chatSource.contains("await Task.yield()\n        let result = await operation()"))
        XCTAssertGreaterThanOrEqual(
            chatSource.components(separatedBy: "performTranscriptSessionTransition {").count - 1,
            2,
            "launch and inspector Resume/Continue actions share one transaction boundary after the task bar removal"
        )
        XCTAssertTrue(chatSource.contains("private func sendWithTranscriptSessionTransition("))
        XCTAssertTrue(chatSource.contains("if store.continuityRequiresRecovery"))
        XCTAssertGreaterThanOrEqual(
            chatSource.components(separatedBy: "sendWithTranscriptSessionTransition {").count - 1,
            7,
            "composer, slash, goal, workflow, research, create-skill, and imagine sends share the recovery boundary"
        )
        XCTAssertTrue(chatSource.contains("isLayoutFrozen: transcriptSessionTransitionInProgress"))
        XCTAssertTrue(chatSource.contains("allowsTextSelection: allowsTranscriptTextSelection"))
        XCTAssertTrue(chatSource.contains("ChatTranscriptSelectionPolicy.shouldSuspendSelection("))
        XCTAssertTrue(
            chatSource.contains("ChatTranscriptScrollPolicy.shouldPerformImmediateFollowScroll("),
            "attached stream revisions must skip per-chunk scrollTo and keep the coalesced settlement window"
        )
        XCTAssertTrue(bubbleSource.contains("if isLayoutFrozen"))
        XCTAssertTrue(bubbleSource.contains("isLayoutFrozen: Bool = false"))
        XCTAssertTrue(bubbleSource.contains("allowsTextSelection: Bool = true"))
        XCTAssertTrue(bubbleSource.contains(".transcriptTextSelection()"))
        XCTAssertTrue(bubbleSource.contains(".environment(\\.allowsTranscriptTextSelection, allowsTextSelection)"))
        XCTAssertFalse(
            bubbleSource.contains(".textSelection(.enabled)"),
            "MessageBubble must honor the follow/settle selection suspend instead of mounting SelectionOverlay unconditionally"
        )
        XCTAssertTrue(richSource.contains("func transcriptTextSelection()"))
        XCTAssertGreaterThanOrEqual(
            richSource.components(separatedBy: ".transcriptTextSelection()").count - 1,
            8,
            "settled Markdown blocks must honor the same selection suspend as MessageBubble"
        )
        XCTAssertEqual(
            richSource.components(separatedBy: ".textSelection(.enabled)").count - 1,
            1,
            "the only enabled SelectionOverlay in RichMessageView is the environment-gated modifier"
        )
    }

    func testTranscriptSelectionSuspendsOnlyWhileFollowingLiveOrSettlingTurns() {
        XCTAssertFalse(
            ChatTranscriptSelectionPolicy.shouldSuspendSelection(
                isFollowingBottom: true,
                isStreaming: false,
                isSettlingAutoScroll: false
            )
        )
        XCTAssertTrue(
            ChatTranscriptSelectionPolicy.shouldSuspendSelection(
                isFollowingBottom: true,
                isStreaming: true,
                isSettlingAutoScroll: false
            )
        )
        XCTAssertTrue(
            ChatTranscriptSelectionPolicy.shouldSuspendSelection(
                isFollowingBottom: true,
                isStreaming: false,
                isSettlingAutoScroll: true
            )
        )
        XCTAssertFalse(
            ChatTranscriptSelectionPolicy.shouldSuspendSelection(
                isFollowingBottom: false,
                isStreaming: true,
                isSettlingAutoScroll: true
            ),
            "a detached reader keeps copy while a live turn continues below"
        )
    }

    func testImmediateFollowScrollSkipsWhenAlreadyAttached() {
        XCTAssertFalse(ChatTranscriptScrollPolicy.shouldPerformImmediateFollowScroll(isAttached: true))
        XCTAssertTrue(ChatTranscriptScrollPolicy.shouldPerformImmediateFollowScroll(isAttached: false))
    }

    func testDetachedTranscriptStopsFollowingAndCountsNewContent() {
        XCTAssertTrue(
            ChatTranscriptScrollPolicy.isAttached(
                distanceFromBottom: ChatTranscriptScrollPolicy.attachmentThreshold
            )
        )
        XCTAssertFalse(
            ChatTranscriptScrollPolicy.isAttached(
                distanceFromBottom: ChatTranscriptScrollPolicy.attachmentThreshold + 1
            )
        )
        XCTAssertEqual(
            ChatTranscriptScrollPolicy.unreadCount(
                current: 2,
                messageCountDelta: 0,
                contentChanged: true,
                isAttached: false
            ),
            3
        )
        XCTAssertEqual(
            ChatTranscriptScrollPolicy.unreadCount(
                current: 2,
                messageCountDelta: 4,
                contentChanged: true,
                isAttached: false
            ),
            6
        )
        XCTAssertEqual(
            ChatTranscriptScrollPolicy.unreadCount(
                current: 2,
                messageCountDelta: 4,
                contentChanged: true,
                isAttached: true
            ),
            0
        )
        XCTAssertEqual(
            ChatTranscriptScrollPolicy.jumpLabel(unreadCount: 3),
            "Jump to latest (3 new)"
        )
    }

    func testActiveAssistantAnchorKeepsToolActivityAboveStreamingAnswer() {
        let prompt = Message(role: .user, content: "Search")
        let answer = Message(role: .assistant, content: "Streaming")

        XCTAssertEqual(
            ChatTranscriptLayout.activeAssistantMessageID(
                messages: [prompt, answer],
                streamingMessageID: answer.id
            ),
            answer.id
        )
        XCTAssertEqual(
            ChatTranscriptLayout.activeAssistantMessageID(
                messages: [prompt, answer],
                streamingMessageID: nil
            ),
            answer.id
        )
    }

    func testStreamingTextBufferSmoothsBurstsWithoutChangingContent() {
        let text = String(repeating: "Grok stream 🚀 ", count: 240)
        var buffer = StreamingTextBuffer()
        buffer.append(text)

        var batches: [String] = []
        while !buffer.isEmpty {
            batches.append(buffer.popNextBatch())
        }

        XCTAssertGreaterThanOrEqual(batches.count, 12)
        XCTAssertLessThanOrEqual(batches.count, StreamingTextBuffer.targetRevealFrames)
        XCTAssertEqual(batches.joined(), text)
        XCTAssertTrue(batches.allSatisfy { !$0.isEmpty })
        XCTAssertGreaterThanOrEqual(
            batches.count * StreamingTextBuffer.displayCadenceMilliseconds,
            350
        )
    }

    func testThinkingAndToolActivityAlwaysPrecedeTheirAnswer() {
        XCTAssertEqual(
            ChatTranscriptLayout.messageBlockOrder(
                containsAgentHeader: true,
                traceExpanded: true,
                containsThinking: true,
                containsToolActivity: true,
                containsLiveProgress: true,
                containsPlanSpine: true
            ),
            [.agentHeader, .thinking, .toolActivity, .planSpine, .liveProgress, .answer]
        )
        // Workbench W-5: the plan spine is independent of the trace disclosure —
        // collapsing thinking/tools never hides the plan during a live run.
        XCTAssertEqual(
            ChatTranscriptLayout.messageBlockOrder(
                containsAgentHeader: true,
                traceExpanded: false,
                containsThinking: true,
                containsToolActivity: true,
                containsLiveProgress: true,
                containsPlanSpine: true
            ),
            [.agentHeader, .planSpine, .liveProgress, .answer]
        )
        XCTAssertEqual(
            ChatTranscriptLayout.messageBlockOrder(
                containsAgentHeader: true,
                traceExpanded: false,
                containsThinking: true,
                containsToolActivity: true,
                containsLiveProgress: true
            ),
            [.agentHeader, .liveProgress, .answer]
        )
        XCTAssertEqual(
            ChatTranscriptLayout.messageBlockOrder(
                containsAgentHeader: false,
                traceExpanded: false,
                containsThinking: false,
                containsToolActivity: false
            ),
            [.answer]
        )
    }

    func testTurnsWithToolsDefaultExpandedIncludingRestoredIDs() throws {
        let restored = UUID()
        let live = UUID()
        let thinkingOnly = UUID()
        let collapsed = UUID()
        XCTAssertTrue(
            ChatTranscriptLayout.isTraceExpanded(
                messageID: restored,
                hasTools: true,
                explicitlyExpanded: [],
                explicitlyCollapsed: []
            ),
            "restored tool receipts must not wait for a live stream insert"
        )
        XCTAssertTrue(
            ChatTranscriptLayout.isTraceExpanded(
                messageID: live,
                hasTools: false,
                explicitlyExpanded: [live],
                explicitlyCollapsed: []
            ),
            "a live streaming turn still opens even before the first tool receipt"
        )
        XCTAssertFalse(
            ChatTranscriptLayout.isTraceExpanded(
                messageID: thinkingOnly,
                hasTools: false,
                explicitlyExpanded: [],
                explicitlyCollapsed: []
            ),
            "thinking-only turns stay collapsed until opened"
        )
        XCTAssertFalse(
            ChatTranscriptLayout.isTraceExpanded(
                messageID: collapsed,
                hasTools: true,
                explicitlyExpanded: [collapsed],
                explicitlyCollapsed: [collapsed]
            ),
            "an explicit collapse wins over tools and a live insert"
        )

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatSource.contains("ChatTranscriptLayout.isTraceExpanded("))
        XCTAssertTrue(chatSource.contains("collapsedAssistantTraceIDs"))
        XCTAssertFalse(
            chatSource.contains("let traceExpanded = expandedAssistantTraceIDs.contains(msg.id)"),
            "the transcript must not treat an empty expand set as collapsed tools"
        )
    }

    /// Workbench W-5 — the plan spine formats existing generation-bound steps;
    /// it never invents progress or decides lifecycle state.
    func testPlanSpinePresentationCountsOnlySettledStepStatuses() {
        XCTAssertTrue(PlanSpinePresentation.isCompleted(" Completed "))
        XCTAssertTrue(PlanSpinePresentation.isCompleted("done"))
        XCTAssertFalse(PlanSpinePresentation.isCompleted("in_progress"))
        XCTAssertFalse(PlanSpinePresentation.isCompleted("pending"))

        let plan = [
            RunEvidenceSnapshot.PlanStep(id: "1", title: "Read the failing test", status: "completed"),
            RunEvidenceSnapshot.PlanStep(id: "2", title: "Patch the parser", status: "in_progress"),
            RunEvidenceSnapshot.PlanStep(id: "3", title: "Re-run the suite", status: "pending")
        ]
        XCTAssertEqual(PlanSpinePresentation.completedCount(plan), 1)
        XCTAssertEqual(PlanSpinePresentation.progressLabel(plan), "1 of 3 done")
        XCTAssertEqual(
            PlanSpinePresentation.stepAccessibilityLabel(plan[0]),
            "Read the failing test, completed"
        )
        XCTAssertEqual(
            PlanSpinePresentation.stepAccessibilityLabel(plan[1]),
            "Patch the parser, in progress"
        )
        XCTAssertEqual(
            PlanSpinePresentation.stepAccessibilityLabel(plan[2]),
            "Re-run the suite, pending"
        )
    }

    /// P3D — live phase/plan/worker truth moves to the right activity canvas.
    /// The transcript keeps its compact tool trace, but never mounts either the
    /// old task-contract bar or the redundant full-width Run card.
    func testLiveRunCardLeavesTranscriptForWorkerActivityCanvas() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatSource.contains("containsPlanSpine: false"))
        XCTAssertFalse(chatSource.contains("ThreadRunSpineView("),
                       "the duplicate Run card must not mount in the transcript")
        XCTAssertFalse(chatSource.contains("grok-task-context-strip"),
                       "the task-contract bar must not mount above the transcript")
        XCTAssertTrue(chatSource.contains("activityInspector(docked:"),
                      "live worker evidence remains reachable in the right canvas")
        XCTAssertFalse(
            chatSource.contains("containsSettledRunSpine"),
            "the settled GitHub-style Run checklist must not return under the answer"
        )
        XCTAssertFalse(
            chatSource.contains("case .settledRunSpine"),
            "settled run spine is not a transcript block"
        )
        let spineSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/LivePlanSpine.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(spineSource.contains("grok-plan-spine"),
                      "the spine carries a stable accessibility identifier")
        XCTAssertTrue(spineSource.contains("accessibilityLabel(\"Run plan\")"))
        XCTAssertTrue(spineSource.contains("grok-run-spine-live"),
                      "the dormant renderer stays available without a structural deletion in P3D")
    }

    func testPromptMCPAttachmentIsTruthfulSanitizedAndDeterministic() throws {
        let prompt = try XCTUnwrap(
            PromptMCPAttachmentPromptBuilder.build(
                from: [" zeta ", "alpha\nconnection", "zeta", "  "]
            )
        )

        XCTAssertTrue(prompt.contains("- alpha connection\n- zeta"))
        XCTAssertTrue(prompt.contains("If no attached MCP tool is actually called"))
        XCTAssertFalse(prompt.contains("alpha\nconnection"))
        XCTAssertNil(PromptMCPAttachmentPromptBuilder.build(from: [" ", "\n"]))
    }

    func testPromptMCPInventoryCatalogRoundTripsOnlyPresentationMetadata() throws {
        let suite = "grokbuild-mcp-catalog-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let options = [
            PromptMCPOption(
                name: "chrome-devtools",
                detail: "User connection · STDIO",
                isReady: true
            )
        ]

        PromptMCPInventoryCatalog.record(options, defaults: defaults)

        let restored = PromptMCPInventoryCatalog.cached(defaults: defaults)
        XCTAssertEqual(restored.map(\.name), options.map(\.name))
        XCTAssertTrue(restored.allSatisfy { !$0.isReady },
                      "cached configuration must never survive as process readiness")
        let raw = try XCTUnwrap(defaults.data(forKey: "grokbuild.promptMCPInventory.v1"))
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("environment"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("command"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("secret"))
        XCTAssertTrue(text.contains(#""isReady":false"#))
    }

    func testRestoredTraceRetainsActualUseWithoutInventingCurrentReadiness() throws {
        let trace = AssistantTurnTrace(
            reasoningSummaryChunks: [],
            thinkingDuration: nil,
            tools: [.init(
                id: "use-1",
                title: "chrome-devtools__list_pages",
                status: "Succeeded",
                mcpServerName: "chrome-devtools",
                mcpReceiptRole: .invocation,
                qualifiedToolName: "chrome-devtools__list_pages"
            )]
        )
        let restored = try JSONDecoder().decode(
            AssistantTurnTrace.self,
            from: JSONEncoder().encode(trace)
        )

        XCTAssertEqual(restored.tools.first?.mcpReceiptRole, .invocation)
        XCTAssertEqual(restored.tools.first?.qualifiedToolName, "chrome-devtools__list_pages")
        let capabilities = try XCTUnwrap(ContextInspectorProjection.capabilitiesSection(
            configuredMCPNames: [],
            processStatuses: [],
            requestedMCPNames: [],
            requestedQualifiedToolNames: [],
            receipts: restored.tools.map {
                .init(
                    id: $0.id,
                    role: $0.mcpReceiptRole,
                    qualifiedToolName: $0.qualifiedToolName,
                    serverName: $0.mcpServerName,
                    discoveredQualifiedToolNames: $0.discoveredQualifiedToolNames,
                    statusLabel: $0.status,
                    isSettled: true
                )
            }
        ))
        XCTAssertEqual(capabilities.exercisedTools.map(\.label), ["chrome-devtools__list_pages"])
        XCTAssertTrue(capabilities.processStates.isEmpty)
    }

    func testMCPIdentityRequiresExplicitOrProviderQualifiedReceipt() {
        XCTAssertEqual(
            MCPToolReceiptIdentity.serverName(
                explicitName: " chrome-devtools ",
                qualifiedToolName: nil,
                knownServerNames: []
            ),
            "chrome-devtools"
        )
        XCTAssertEqual(
            MCPToolReceiptIdentity.serverName(
                explicitName: nil,
                qualifiedToolName: "chrome-devtools__list_pages",
                knownServerNames: ["chrome", "chrome-devtools"]
            ),
            "chrome-devtools"
        )
        XCTAssertEqual(
            MCPToolReceiptIdentity.serverName(
                explicitName: nil,
                qualifiedToolName: "chrome-devtools__list_pages",
                knownServerNames: ["unrelated"]
            ),
            "chrome-devtools"
        )
        XCTAssertNil(
            MCPToolReceiptIdentity.serverName(
                explicitName: nil,
                qualifiedToolName: "list_pages",
                knownServerNames: ["chrome-devtools"]
            )
        )
        XCTAssertNil(
            MCPToolReceiptIdentity.serverName(
                explicitName: nil,
                qualifiedToolName: "not a safe server__tool",
                knownServerNames: []
            )
        )
    }

    func testRestoredToolDisclosureDerivesMCPNameFromQualifiedReceiptTitle() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let composerViews = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ComposerViews.swift"),
            encoding: .utf8
        )
        let toolViewStart = try XCTUnwrap(composerViews.range(of: "struct AssistantToolTraceView"))
        let toolViewEnd = try XCTUnwrap(
            composerViews.range(of: "// MARK: - Workflow chips", range: toolViewStart.upperBound..<composerViews.endIndex)
        )
        let toolView = String(composerViews[toolViewStart.lowerBound..<toolViewEnd.lowerBound])

        XCTAssertTrue(toolView.contains("qualifiedToolName: tool.qualifiedToolName ?? tool.title"))
        XCTAssertTrue(toolView.contains("tool.mcpReceiptRole == .discovery"))
        XCTAssertTrue(toolView.contains("Capability discovery"))
        XCTAssertTrue(toolView.contains("if let server = displayedMCPServer"))
        XCTAssertTrue(toolView.contains("Text(\"Using \\(server)\")"))
        XCTAssertTrue(toolView.contains("settledOutput"))
        XCTAssertFalse(
            toolView.contains("textSelection(.enabled)"),
            "settled tool output must not mount AppKit SelectionOverlay inside the transcript LazyVStack"
        )
        XCTAssertTrue(toolView.contains("grok-assistant-tool-\\(sanitizedToolID)"))
        XCTAssertTrue(toolView.contains("accessibilityLabel(server: displayedMCPServer)"))
        XCTAssertTrue(toolView.contains("if let output = settledOutput"))
        XCTAssertFalse(toolView.contains("grok-assistant-tool-details"))
        XCTAssertTrue(toolView.contains("grok-assistant-tool-list"))
    }

    func testComposerOrdersAddModeThenModelMicSend() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        // Codex parity Slice 4: leading cluster is add/context then run mode.
        let start = try XCTUnwrap(source.range(of: "private var composerPrimaryControls"))
        let end = try XCTUnwrap(
            source.range(of: "private var composerAddMenu", range: start.upperBound..<source.endIndex)
        )
        let controls = String(source[start.lowerBound..<end.lowerBound])
        let add = try XCTUnwrap(controls.range(of: "composerAddMenu"))
        let mode = try XCTUnwrap(controls.range(of: "modeSelector"))
        XCTAssertLessThan(add.lowerBound, mode.lowerBound)
        XCTAssertFalse(controls.contains("composerDetailsToggle"))

        // Trailing cluster is model, voice, then send/stop.
        let actionStart = try XCTUnwrap(source.range(of: "private var composerActionControls"))
        let actionSlice = String(source[actionStart.lowerBound..<source.index(actionStart.upperBound, offsetBy: 400)])
        let model = try XCTUnwrap(actionSlice.range(of: "modelSelector"))
        let mic = try XCTUnwrap(actionSlice.range(of: "MicButton"))
        let send = try XCTUnwrap(actionSlice.range(of: "sessionActionButton"))
        XCTAssertLessThan(model.lowerBound, mic.lowerBound)
        XCTAssertLessThan(mic.lowerBound, send.lowerBound)
        XCTAssertTrue(source.contains(".task(id: promptMCPRefreshIdentity)"))
        XCTAssertTrue(source.contains("store.currentWorkspace?.id.uuidString"))
        XCTAssertTrue(source.contains("store.tabSessionID?.uuidString"))
        XCTAssertTrue(source.contains("await store.refreshPromptMCPOptions()"))

        let storeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(storeSource.contains("?? toolCall.title"))
        XCTAssertTrue(storeSource.contains("toolCall.rawInput?[\"name\"] as? String"))
        XCTAssertTrue(storeSource.contains("ToolResultPresentation.transcriptOutput"))
        XCTAssertTrue(source.contains("store.isStreaming || store.isGrokking"))

        let composerViews = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ComposerViews.swift"),
            encoding: .utf8
        )
        let reasoningStart = try XCTUnwrap(composerViews.range(of: "struct AssistantReasoningTraceView"))
        let reasoningEnd = try XCTUnwrap(
            composerViews.range(of: "struct AssistantToolTraceView", range: reasoningStart.upperBound..<composerViews.endIndex)
        )
        let reasoningView = String(composerViews[reasoningStart.lowerBound..<reasoningEnd.lowerBound])
        XCTAssertFalse(reasoningView.contains("Text(summary)"))
        XCTAssertFalse(reasoningView.contains("presentationOnlyText"))
        XCTAssertTrue(reasoningView.contains("Label(durationLabel"))
    }

    func testThinkingUsesStreamingAssistantWhenAvailable() {
        let completed = Message(role: .assistant, content: "Earlier")
        let streaming = Message(role: .assistant, content: "")

        XCTAssertEqual(
            ChatTranscriptLayout.thinkingMessageID(
                messages: [completed, streaming],
                streamingMessageID: streaming.id
            ),
            streaming.id
        )
    }

    func testThinkingUsesMostRecentAssistantAfterCompletion() {
        let first = Message(role: .assistant, content: "Earlier")
        let user = Message(role: .user, content: "Next")
        let latest = Message(role: .assistant, content: "Answer")

        XCTAssertEqual(
            ChatTranscriptLayout.thinkingMessageID(
                messages: [first, user, latest],
                streamingMessageID: nil
            ),
            latest.id
        )
    }

    /// nil means "no anchor" — ChatView then renders the thinking block at the
    /// transcript tail rather than dropping it (first-turn failure case).
    func testThinkingHasNoAttachmentWithoutAssistantMessage() {
        XCTAssertNil(
            ChatTranscriptLayout.thinkingMessageID(
                messages: [Message(role: .user, content: "Question")],
                streamingMessageID: nil
            )
        )
    }

    /// A failed turn removes its empty assistant reply, so the transcript ends
    /// with the user prompt. The trace must NOT attach to the previous turn's
    /// answer — nil sends it to the tail, below the prompt that produced it.
    func testThinkingDetachesFromOlderAnswerWhenLatestTurnFailed() {
        let olderAnswer = Message(role: .assistant, content: "Earlier answer")
        let failedPrompt = Message(role: .user, content: "Prompt that failed")

        XCTAssertNil(
            ChatTranscriptLayout.thinkingMessageID(
                messages: [olderAnswer, failedPrompt],
                streamingMessageID: nil
            )
        )
    }

    /// System notes after the answer (e.g. "Reloaded Grok configuration.") must
    /// not break attachment to the latest assistant message.
    func testThinkingAttachmentIgnoresTrailingSystemNotes() {
        let user = Message(role: .user, content: "Prompt")
        let answer = Message(role: .assistant, content: "Answer")
        let note = Message(role: .system, content: "Reloaded Grok configuration.")

        XCTAssertEqual(
            ChatTranscriptLayout.thinkingMessageID(
                messages: [user, answer, note],
                streamingMessageID: nil
            ),
            answer.id
        )
    }

    func testAssistantDiffLanguagesArePresentedAsExamples() {
        XCTAssertTrue(AssistantDiffPresentation.isExample(language: "diff"))
        XCTAssertTrue(AssistantDiffPresentation.isExample(language: " PATCH "))
        XCTAssertFalse(AssistantDiffPresentation.isExample(language: "swift"))
        XCTAssertFalse(AssistantDiffPresentation.isExample(language: nil))
    }

    func testCompactModelMenuUsesHumanReadableEffortNames() {
        XCTAssertEqual(
            ComposerModelMenuLayout.effortDisplayName(storedValue: ""),
            "Default"
        )
        XCTAssertEqual(
            ComposerModelMenuLayout.effortDisplayName(storedValue: "xhigh"),
            "XHigh"
        )
        XCTAssertEqual(
            ComposerModelMenuLayout.effortDisplayName(storedValue: "unknown"),
            "Default"
        )
    }

    func testFailedOrRacingSubmissionPreservesComposerDraft() {
        XCTAssertEqual(
            ComposerSubmissionPolicy.draftAfterSubmission(
                currentDraft: "build it",
                submittedDraft: "build it",
                accepted: false
            ),
            "build it"
        )
        XCTAssertEqual(
            ComposerSubmissionPolicy.draftAfterSubmission(
                currentDraft: "build it, plus tests",
                submittedDraft: "build it",
                accepted: true
            ),
            "build it, plus tests"
        )
        XCTAssertEqual(
            ComposerSubmissionPolicy.draftAfterSubmission(
                currentDraft: "build it",
                submittedDraft: "build it",
                accepted: true
            ),
            ""
        )
    }

    @MainActor
    func testPendingSubmitCancelPreservesExactDraftAndSpendsNothing() {
        let store = ChatStore()
        store.composerDraft = "  exact first task  "
        let intent = PendingSubmitIntent(id: UUID(), draft: "exact first task")

        XCTAssertEqual(intent.draft, "exact first task")
        XCTAssertFalse(store.isPreparingSubmit)
        store.cancelPendingSubmit()
        XCTAssertEqual(store.composerDraft, "  exact first task  ")
        XCTAssertFalse(store.isPreparingSubmit)
    }

    func testPendingSubmitIntentHasStableIdentityForExactlyOnceDispatch() {
        let id = UUID()
        let first = PendingSubmitIntent(id: id, draft: "run one command")
        let duplicate = PendingSubmitIntent(id: id, draft: "run one command")
        let different = PendingSubmitIntent(id: UUID(), draft: "run one command")

        XCTAssertEqual(first, duplicate)
        XCTAssertNotEqual(first, different)
        XCTAssertEqual(
            PendingSubmitIntentPolicy.latchDecision(existing: nil, draft: first.draft),
            .latch
        )
        XCTAssertEqual(
            PendingSubmitIntentPolicy.latchDecision(existing: first, draft: first.draft),
            .duplicate
        )
        XCTAssertEqual(
            PendingSubmitIntentPolicy.latchDecision(existing: first, draft: "mutated"),
            .conflictingDraft
        )
    }

    func testPendingSubmitIntentFreezesEveryDispatchInputAndRejectsMutation() {
        let workspace = URL(fileURLWithPath: "/tmp/grokbuild-pending-freeze")
        let attachment = FileAttachment(
            path: "/tmp/grokbuild-pending-freeze/proof.txt",
            workspaceRoot: workspace
        )
        let intent = PendingSubmitIntent(
            id: UUID(),
            draft: "prove route",
            modelID: "grok-4.5-build",
            modeID: "agent",
            reasoningEffort: "high",
            fileAttachments: [attachment],
            requestedMCPNames: ["zotero"]
        )
        XCTAssertEqual(intent.modelID, "grok-4.5-build")
        XCTAssertEqual(intent.modeID, "agent")
        XCTAssertEqual(intent.reasoningEffort, "high")
        XCTAssertEqual(intent.fileAttachments, [attachment])
        XCTAssertEqual(intent.requestedMCPNames, ["zotero"])
        XCTAssertTrue(PendingSubmitIntentPolicy.routeStillMatches(
            intent,
            modelID: "grok-4.5-build",
            modeID: "agent",
            reasoningEffort: "high",
            fileAttachments: [attachment],
            requestedMCPNames: ["zotero"]
        ))
        XCTAssertFalse(PendingSubmitIntentPolicy.routeStillMatches(
            intent,
            modelID: "grok-4.5-build",
            modeID: "agent",
            reasoningEffort: "low",
            fileAttachments: [attachment],
            requestedMCPNames: ["zotero"]
        ))
        XCTAssertFalse(PendingSubmitIntentPolicy.routeStillMatches(
            intent,
            modelID: "grok-4.5-build",
            modeID: "agent",
            reasoningEffort: "high",
            fileAttachments: [],
            requestedMCPNames: ["zotero"]
        ))
        XCTAssertNotEqual(
            intent,
            PendingSubmitIntent(
                id: intent.id,
                draft: intent.draft,
                modelID: intent.modelID,
                modeID: intent.modeID,
                reasoningEffort: intent.reasoningEffort,
                fileAttachments: intent.fileAttachments,
                requestedMCPNames: ["github"]
            )
        )
    }

    func testPendingSubmitRequiresExactModelReadbackAndModeBeforeDispatch() {
        let intent = PendingSubmitIntent(
            id: UUID(),
            draft: "prove custom route",
            modelID: "custom-terra",
            modeID: "agent"
        )
        let confirmedProviderReadback = ModelExecutionState(
            status: .confirmed,
            requestedModelID: "custom-terra",
            effectiveModelID: "openai/gpt-5.6-terra",
            identity: nil,
            failure: nil,
            updatedAt: nil
        )
        XCTAssertTrue(PendingSubmitIntentPolicy.backendRouteIsConfirmed(
            intent,
            modelExecutionState: confirmedProviderReadback,
            expectedEffectiveModelID: "openai/gpt-5.6-terra",
            currentModeID: "agent"
        ))

        var missingReadback = confirmedProviderReadback
        missingReadback.status = .requested
        missingReadback.effectiveModelID = nil
        XCTAssertFalse(PendingSubmitIntentPolicy.backendRouteIsConfirmed(
            intent,
            modelExecutionState: missingReadback,
            expectedEffectiveModelID: "openai/gpt-5.6-terra",
            currentModeID: "agent"
        ))

        var wrongReadback = confirmedProviderReadback
        wrongReadback.effectiveModelID = "grok-4.5"
        XCTAssertFalse(PendingSubmitIntentPolicy.backendRouteIsConfirmed(
            intent,
            modelExecutionState: wrongReadback,
            expectedEffectiveModelID: "openai/gpt-5.6-terra",
            currentModeID: "agent"
        ))
        XCTAssertFalse(PendingSubmitIntentPolicy.backendRouteIsConfirmed(
            intent,
            modelExecutionState: confirmedProviderReadback,
            expectedEffectiveModelID: "openai/gpt-5.6-terra",
            currentModeID: "plan"
        ))
    }

    func testPreparingSubmitLocksEveryRouteControl() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatSource.contains(".disabled(store.isStreaming || store.isPreparingSubmit)"))
        XCTAssertTrue(storeSource.contains("guard !isPreparingSubmit else { return }"))
        XCTAssertTrue(storeSource.contains("pendingSubmitRouteStillMatches(intent)"))
    }

    func testNativeSubmitLatchesBeforeLaunchingAsyncDelivery() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        let composer = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatComposer.swift"),
            encoding: .utf8
        )

        let preparation = try XCTUnwrap(source.range(of: "let preparation = store.prepareSubmit(text)"))
        let delivery = try XCTUnwrap(
            source.range(of: "let accepted = await sendWithTranscriptSessionTransition",
                         range: preparation.upperBound..<source.endIndex)
        )
        let send = try XCTUnwrap(
            source.range(of: "await store.send(text, preparedIntentID: preparation.intentID)",
                         range: delivery.upperBound..<source.endIndex)
        )
        XCTAssertLessThan(preparation.lowerBound, delivery.lowerBound)
        XCTAssertLessThan(delivery.lowerBound, send.lowerBound)
        XCTAssertTrue(source.contains("onSubmit: submit"))
        XCTAssertTrue(composer.contains("onSubmit()"))
    }

    func testConnectionStatusNamesLazyResumeExplicitly() {
        XCTAssertEqual(
            ConnectionStatusPresentation.subtitle(
                state: .starting,
                isResumedSession: true,
                hasWorkspace: true
            ),
            "Resuming session…"
        )
        XCTAssertEqual(
            ConnectionStatusPresentation.subtitle(
                state: .starting,
                isResumedSession: false,
                hasWorkspace: true
            ),
            "Starting agent…"
        )
    }

    func testConnectedIdleDraftDoesNotReadAsALiveSidebarTask() {
        XCTAssertFalse(SidebarSessionActivity.isWorking(connectionState: .ready, isStreaming: false))
        XCTAssertEqual(
            ThreadTaskContractPresentation.phase(
                live: nil,
                snapshot: nil,
                checkpoint: nil,
                connectionState: .ready,
                isPreparingSubmit: false,
                canResumeSavedTask: false,
                continuityRequiresRecovery: false,
                isResumedSession: false
            ),
            "Connected — idle"
        )
        XCTAssertEqual(
            SessionSidebarMetadata.accessibilityLabel(
                for: SidebarSession(
                    id: UUID(),
                    workspaceID: UUID(),
                    title: "Draft",
                    modelName: "Grok 4.6",
                    lastAccessed: nil,
                    isRunning: false
                )
            ),
            "Session: Draft, Grok 4.6, idle, new session"
        )
    }
}

extension ChatTranscriptLayoutTests {
    /// Repeated settings applies produced a wall of identical system notes.
    func testDuplicateTrailingSystemNoteIsCollapsed() {
        let note = "Reloaded Grok configuration."
        XCTAssertFalse(ChatStore.isDuplicateTrailingNote(note, in: []))

        let afterNote = [Message(role: .system, content: note)]
        XCTAssertTrue(ChatStore.isDuplicateTrailingNote(note, in: afterNote))
        XCTAssertFalse(ChatStore.isDuplicateTrailingNote("A different note.", in: afterNote))

        // A note that repeats an EARLIER one still appears when something
        // happened in between — only consecutive repeats collapse.
        let interrupted = afterNote + [Message(role: .assistant, content: "Answer")]
        XCTAssertFalse(ChatStore.isDuplicateTrailingNote(note, in: interrupted))
    }

    /// Transcripts recorded before the per-turn model stamp existed must decode
    /// with `nil` identity — the header then falls back to "Build agent" rather
    /// than guessing a model name without a receipt.
    func testAssistantTraceDecodesLegacyJSONWithoutModelStamp() throws {
        let legacy = """
        {"reasoningSummaryChunks":["thought"],"thinkingDuration":2.5,
         "tools":[{"id":"t1","title":"Execute","status":"Done","mcpServerName":null}]}
        """.data(using: .utf8)!
        let trace = try JSONDecoder().decode(AssistantTurnTrace.self, from: legacy)
        XCTAssertNil(trace.modelDisplayName)
        XCTAssertNil(trace.agentName)
        XCTAssertEqual(trace.tools.count, 1)
    }

    /// The turn header names the model that ran the turn when (and only when)
    /// the trace carries the confirmed receipt; the neutral label is the fallback.
    func testAssistantTurnHeaderUsesStampedModelIdentity() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatSource.contains("Text(assistantTurnTitle(trace: trace))"),
                      "the header renders the dynamic per-turn identity")
        XCTAssertTrue(chatSource.contains("return \"Build agent\""),
                      "unstamped turns keep the neutral fallback, never a guessed model")
        let storeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(storeSource.contains("modelExecutionState.status == .confirmed"),
                      "the stamp comes only from the confirmed execution receipt")
    }
}
