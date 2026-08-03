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
        XCTAssertGreaterThanOrEqual(gaps.count, 4)
        XCTAssertGreaterThanOrEqual(gaps.reduce(0, +), 800)
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

        XCTAssertGreaterThan(batches.count, 1)
        XCTAssertLessThan(batches.count, 24)
        XCTAssertEqual(batches.joined(), text)
        XCTAssertTrue(batches.allSatisfy { !$0.isEmpty })
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
