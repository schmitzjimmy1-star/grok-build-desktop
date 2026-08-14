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

    func testEmptyLedgerWithZeroToolsIsNotUnresolved() {
        let worker = RunEvidenceSnapshot.Worker(
            id: "worker",
            title: "No tools",
            status: "completed",
            childID: "child",
            durationMilliseconds: 10,
            toolCallCount: 0,
            redactedError: nil,
            childToolReceipts: [],
            childLedgerReadOutcome: .empty
        )

        XCTAssertTrue(worker.isCompleted)
        XCTAssertFalse(worker.isUnresolved)
        XCTAssertTrue(worker.hasReconciledChildToolReceipts)
    }

    func testUnreadableLedgerRemainsUnresolvedEvenWithZeroToolCount() {
        let worker = RunEvidenceSnapshot.Worker(
            id: "worker",
            title: "Unreadable ledger",
            status: "completed",
            childID: "child",
            durationMilliseconds: 10,
            toolCallCount: 0,
            redactedError: nil,
            childLedgerReadOutcome: .unreadable
        )

        XCTAssertTrue(worker.isUnresolved)
    }

    func testOrphanedWorkerFromStopCountsAsUnresolved() {
        let worker = RunEvidenceSnapshot.Worker(
            id: "worker",
            title: "Stopped child",
            status: "orphaned",
            childID: "child",
            durationMilliseconds: nil,
            toolCallCount: nil,
            redactedError: nil
        )
        let snapshot = RunEvidenceSnapshot(
            binding: .init(
                localTabID: UUID(), workspaceID: UUID(), backendSessionID: "b",
                processGeneration: 1, requestID: nil, isSettled: true
            ),
            goalSummary: nil,
            plan: [],
            workers: [worker],
            tools: .init(succeeded: 0, failed: 0, cancelled: 0, unknown: 0),
            artifacts: [],
            gitReviewFiles: [],
            process: .init(state: "Stopped by you", model: nil, mcps: []),
            continuity: .init(
                status: "backendBound", reason: "fresh", provenance: "p", requiresRecoveryAction: false
            ),
            usage: .init(totalTokens: nil, modelCalls: nil, turnCount: nil),
            outcome: .userStopped,
            unresolvedErrors: [],
            nextAction: "Reconnect"
        )

        XCTAssertEqual(snapshot.unresolvedWorkerCount, 1)
        XCTAssertEqual(snapshot.completedWorkerCount, 0)
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

    @MainActor
    func testClearTurnStatePrunesBackgroundActivitiesAndUnboundSpawns() {
        let store = ChatStore()
        store.ingestBackgroundActivityForTests([
            "toolCallId": "prior-worker",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "reviewer", "prompt": "Prior turn work", "task_id": "child-prior"]
        ])
        store.ingestSubagentSpawnedForTests(SubagentSpawnedEvent(
            identity: ACPEventIdentity(
                localTabID: UUID(),
                backendSessionID: "backend",
                processGeneration: 1,
                backendEventID: "unbound"
            ),
            childID: "unbound-child",
            parentPromptID: nil,
            subagentType: "explore",
            modelID: "grok-4.5",
            description: "Never bound"
        ))
        XCTAssertEqual(store.backgroundActivities.filter { $0.kind == .subagent }.count, 1)
        XCTAssertEqual(store.unboundSubagentSpawnedEvents.count, 1)

        store.clearTurnState()

        XCTAssertTrue(store.backgroundActivities.filter { $0.kind == .subagent }.isEmpty)
        XCTAssertTrue(store.unboundSubagentSpawnedEvents.isEmpty)
        XCTAssertNil(store.runEvidenceSnapshot)
    }

    func testCancelledWorkerFromStopCountsAsUnresolvedNotDone() {
        let worker = RunEvidenceSnapshot.Worker(
            id: "worker",
            title: "Stopped before child id",
            status: "cancelled",
            childID: nil,
            durationMilliseconds: nil,
            toolCallCount: nil,
            redactedError: nil
        )
        XCTAssertTrue(worker.isUnresolved)
        XCTAssertFalse(worker.isCompleted)
        let summary = ContextInspectorProjection.subagentSummary([worker])
        XCTAssertEqual(summary.doneCount, 0)
        XCTAssertEqual(summary.failedCount, 1)
    }
}
