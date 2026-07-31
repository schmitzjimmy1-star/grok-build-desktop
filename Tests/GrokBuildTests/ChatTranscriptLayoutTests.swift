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

    func testThinkingHasNoAttachmentWithoutAssistantMessage() {
        XCTAssertNil(
            ChatTranscriptLayout.thinkingMessageID(
                messages: [Message(role: .user, content: "Question")],
                streamingMessageID: nil
            )
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
