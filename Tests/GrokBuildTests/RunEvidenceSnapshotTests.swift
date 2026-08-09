import XCTest
@testable import GrokBuild

final class RunEvidenceSnapshotTests: XCTestCase {
    func testCompletedWorkerResolvesOnlyWhenTypedChildReceiptsReconcile() {
        let receipts = [
            ChildToolReceipt(
                id: "search",
                title: "search_tool",
                status: .succeeded,
                mcpReceiptRole: .discovery,
                qualifiedToolName: nil,
                discoveredQualifiedToolNames: ["grokbuild-browser__browser_open_url"]
            ),
            ChildToolReceipt(
                id: "use",
                title: "grokbuild-browser__browser_open_url",
                status: .succeeded,
                mcpReceiptRole: .invocation,
                qualifiedToolName: "grokbuild-browser__browser_open_url",
                discoveredQualifiedToolNames: []
            ),
        ]
        let worker = RunEvidenceSnapshot.Worker(
            id: "worker",
            title: "Inspect page",
            status: "completed",
            childID: "child",
            durationMilliseconds: 10,
            toolCallCount: 2,
            redactedError: nil,
            childToolReceipts: receipts
        )

        XCTAssertTrue(worker.hasReconciledChildToolReceipts)
        XCTAssertFalse(worker.hasUnresolvedChildToolOutcome)
        XCTAssertFalse(worker.isUnresolved)
    }

    func testFailedTypedChildReceiptRemainsUnresolved() {
        let worker = RunEvidenceSnapshot.Worker(
            id: "worker",
            title: "Inspect page",
            status: "completed",
            childID: "child",
            durationMilliseconds: 10,
            toolCallCount: 1,
            redactedError: nil,
            childToolReceipts: [ChildToolReceipt(
                id: "use",
                title: "browser",
                status: .failed,
                mcpReceiptRole: .invocation,
                qualifiedToolName: "server__browser",
                discoveredQualifiedToolNames: []
            )]
        )

        XCTAssertTrue(worker.hasReconciledChildToolReceipts)
        XCTAssertTrue(worker.hasUnresolvedChildToolOutcome)
        XCTAssertTrue(worker.isUnresolved)
    }

    func testCompletedWorkerLifecycleDoesNotProveChildToolSuccess() {
        let worker = RunEvidenceSnapshot.Worker(
            id: "worker",
            title: "Child command",
            status: "completed",
            childID: "child",
            durationMilliseconds: 10,
            toolCallCount: 1,
            redactedError: nil
        )

        XCTAssertTrue(worker.isCompleted)
        XCTAssertTrue(worker.isUnresolved)
        XCTAssertFalse(worker.isActive)
    }

    func testSnapshotUpdatesOnlyGitReviewFilesWithoutChangingItsRunBinding() {
        let binding = RunEvidenceSnapshot.Binding(
            localTabID: UUID(),
            workspaceID: UUID(),
            backendSessionID: "backend",
            processGeneration: 7,
            requestID: "prompt",
            isSettled: true
        )
        let snapshot = RunEvidenceSnapshot(
            binding: binding,
            goalSummary: nil,
            plan: [],
            workers: [],
            tools: .init(succeeded: 0, failed: 0, cancelled: 0, unknown: 0),
            artifacts: [],
            gitReviewFiles: [],
            process: .init(state: "Ready", model: "grok-4.5", mcps: []),
            continuity: .init(
                status: "backendBound",
                reason: "freshBackendBound",
                provenance: "Fresh backend bound",
                requiresRecoveryAction: false
            ),
            usage: .init(totalTokens: 1_276_441, modelCalls: 15, turnCount: 8),
            outcome: .completed,
            unresolvedErrors: [],
            nextAction: "The agent reported no next action."
        )

        let updated = snapshot.replacingGitReviewFiles(["Sources/App.swift"])

        XCTAssertEqual(updated.binding, binding)
        XCTAssertEqual(updated.usage.totalTokens, 1_276_441)
        XCTAssertEqual(updated.gitReviewFiles, ["Sources/App.swift"])
        XCTAssertEqual(updated.nextAction, "The agent reported no next action.")
    }

    @MainActor
    func testBeginningANewTurnClearsThePriorEphemeralSnapshot() async throws {
        let store = ChatStore()
        store.clearTurnState()
        XCTAssertNil(store.runEvidenceSnapshot)
    }
}
