import XCTest
@testable import GrokBuild

final class ConversationWorkbenchTests: XCTestCase {
    func testTurnStatusUsesLiveAndCheckpointTruth() {
        XCTAssertEqual(
            ConversationTurnStatusPresentation.make(isLive: true, checkpoint: nil)?.kind,
            .working
        )
        XCTAssertNil(
            ConversationTurnStatusPresentation.make(isLive: false, checkpoint: nil),
            "legacy prose without a checkpoint must not be promoted to success"
        )
        XCTAssertEqual(
            ConversationTurnStatusPresentation.make(
                isLive: false,
                checkpoint: checkpoint(outcome: .completed)
            )?.kind,
            .completed
        )
        XCTAssertEqual(
            ConversationTurnStatusPresentation.make(
                isLive: false,
                checkpoint: checkpoint(outcome: .failed)
            )?.kind,
            .failed
        )
        XCTAssertEqual(
            ConversationTurnStatusPresentation.make(
                isLive: false,
                checkpoint: checkpoint(outcome: .completed, failedTools: 1)
            )?.kind,
            .needsReview,
            "a completed parent must not paint a failed child receipt green"
        )
        XCTAssertEqual(
            ConversationTurnStatusPresentation.make(
                isLive: false,
                checkpoint: checkpoint(outcome: .completionReceiptMissing)
            )?.kind,
            .needsReview
        )
    }

    func testToolActionsAreReadableWithoutChangingReceiptStatus() {
        XCTAssertEqual(
            ToolActionPresentation.title(
                rawTitle: "Sources/App.swift",
                kind: "read_file",
                status: "succeeded"
            ),
            "Read Sources/App.swift"
        )
        XCTAssertEqual(
            ToolActionPresentation.title(
                rawTitle: "package tests",
                kind: "execute",
                status: "running"
            ),
            "Running package tests"
        )
        XCTAssertEqual(
            ToolActionPresentation.title(
                rawTitle: "Edited README.md",
                kind: "write",
                status: "succeeded"
            ),
            "Edited README.md"
        )
    }

    func testConversationWorkbenchWiresOneTurnTimelineAndOneClosedReviewEntry() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chat = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        let bubble = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Views/MessageBubble.swift"),
            encoding: .utf8
        )
        let tools = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Views/ComposerViews.swift"),
            encoding: .utf8
        )
        let changedFiles = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Views/ChangedFilesSummaryCard.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(chat.contains("ConversationTurnSurface(messageID: msg.id"))
        XCTAssertTrue(chat.contains("checkpoint: persistedTrace?.checkpoint"))
        XCTAssertTrue(chat.contains("msg.id == inlineChangedFilesMessageID"))
        XCTAssertTrue(chat.contains("inlineChangedFilesSummary != nil && !isReviewVisible"))
        XCTAssertTrue(bubble.contains(".frame(maxWidth: 640, alignment: .leading)"))
        XCTAssertFalse(bubble.contains(".frame(width: 3)"))
        XCTAssertTrue(tools.contains("ReasoningSummaryPresentation.make("))
        XCTAssertTrue(tools.contains("ToolActionPresentation.title("))
        XCTAssertTrue(tools.contains("details collapsed"))
        XCTAssertFalse(changedFiles.contains(".grokGlassSurface("))
        XCTAssertTrue(changedFiles.contains("Label(\"Review changes\""))
        XCTAssertTrue(changedFiles.contains("GrokProminentButtonStyle"))
    }

    private func checkpoint(
        outcome: ChatStore.TurnOutcome,
        failedTools: Int = 0
    ) -> AssistantTurnCheckpoint {
        let snapshot = RunEvidenceSnapshot(
            binding: .init(
                localTabID: UUID(),
                workspaceID: UUID(),
                backendSessionID: "backend",
                processGeneration: 1,
                requestID: "request",
                isSettled: true
            ),
            goalSummary: nil,
            plan: [],
            workers: [],
            tools: .init(succeeded: failedTools == 0 ? 1 : 0, failed: failedTools, cancelled: 0, unknown: 0),
            artifacts: [],
            gitReviewFiles: [],
            process: .init(state: "ready", model: "grok-4.6", mcps: []),
            continuity: .init(
                status: "bound",
                reason: "fresh",
                provenance: "test",
                requiresRecoveryAction: outcome == .completionReceiptMissing
            ),
            usage: .init(totalTokens: nil, modelCalls: nil, turnCount: nil),
            outcome: outcome,
            unresolvedErrors: outcome == .completionReceiptMissing ? ["missing receipt"] : [],
            nextAction: ""
        )
        return AssistantTurnCheckpoint(snapshot: snapshot, requestedToolFamilies: [])
    }
}
