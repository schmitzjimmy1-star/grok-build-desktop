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
                containsLiveProgress: true
            ),
            [.agentHeader, .thinking, .toolActivity, .liveProgress, .answer]
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

        XCTAssertEqual(PromptMCPInventoryCatalog.cached(defaults: defaults), options)
        let raw = try XCTUnwrap(defaults.data(forKey: "grokbuild.promptMCPInventory.v1"))
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("environment"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("command"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("secret"))
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

        XCTAssertTrue(toolView.contains("qualifiedToolName: tool.title"))
        XCTAssertTrue(toolView.contains("if let server = displayedMCPServer"))
        XCTAssertTrue(toolView.contains("Text(\"Using \\(server)\")"))
    }

    func testComposerOrdersMCPHammerDetailsThenModel() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "private var composerPrimaryControls"))
        let end = try XCTUnwrap(
            source.range(of: "private var composerMCPMenu", range: start.upperBound..<source.endIndex)
        )
        let controls = String(source[start.lowerBound..<end.lowerBound])

        let mcp = try XCTUnwrap(controls.range(of: "composerMCPMenu"))
        let hammer = try XCTUnwrap(controls.range(of: "composerCommandMenu"))
        let details = try XCTUnwrap(controls.range(of: "composerDetailsToggle"))
        let model = try XCTUnwrap(controls.range(of: "modelSelector"))
        XCTAssertLessThan(mcp.lowerBound, hammer.lowerBound)
        XCTAssertLessThan(hammer.lowerBound, details.lowerBound)
        XCTAssertLessThan(details.lowerBound, model.lowerBound)
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
}
