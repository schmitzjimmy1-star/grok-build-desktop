import XCTest
@testable import GrokBuild

final class ChatTranscriptLayoutTests: XCTestCase {
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
}
