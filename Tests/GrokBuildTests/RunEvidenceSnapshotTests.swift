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

    @MainActor
    func testHasActiveBackgroundTasksTracksNonScheduledWork() {
        let store = ChatStore()
        XCTAssertFalse(store.hasActiveBackgroundTasks, "a fresh session has no background work")

        // A running background shell must count as active long-horizon work.
        store.ingestBackgroundActivityForTests([
            "toolCallId": "bg-1",
            "_meta": ["x.ai/tool": ["name": "run_terminal_command"]],
            "rawInput": ["command": "tail -f build.log", "background": true],
        ])
        XCTAssertTrue(store.hasActiveBackgroundTasks, "a running background shell must be protected")

        // Its terminal receipt releases the protection.
        store.ingestBackgroundActivityForTests([
            "toolCallId": "bg-1",
            "_meta": ["x.ai/tool": ["name": "run_terminal_command"]],
            "rawInput": ["command": "tail -f build.log", "background": true],
            "rawOutput": ["id": "bg-1", "status": "completed", "output": "done"],
            "status": "completed",
        ])
        XCTAssertFalse(store.hasActiveBackgroundTasks, "a completed background shell no longer pins the session")
    }

    @MainActor
    func testUnboundSubagentSpawnSetsHasActiveBackgroundTasks() {
        let store = ChatStore()
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
            description: "Still running"
        ))
        XCTAssertTrue(
            store.hasActiveBackgroundTasks,
            "a spawned subagent with no terminal receipt keeps the session protected"
        )
    }

    @MainActor
    func testScheduledActivityAloneDoesNotSetHasActiveBackgroundTasks() {
        let store = ChatStore()
        // Scheduled tasks are covered by the runtime lease, not the background flag,
        // so a scheduler mirror alone must not double-report as background work.
        store.ingestBackgroundActivityForTests([
            "toolCallId": "sched-1",
            "_meta": ["x.ai/tool": ["name": "scheduler_create"]],
            "rawInput": ["interval": "60s", "prompt": "check inbox"],
            "rawOutput": ["type": "SchedulerCreate", "id": "schedule-xyz"],
        ])
        XCTAssertTrue(store.backgroundActivities.contains { $0.kind == .scheduled })
        XCTAssertFalse(store.hasActiveBackgroundTasks)
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

    func testCheckpointRestoresWorkerTokenAndTurnReceipts() {
        let worker = RunEvidenceSnapshot.Worker(
            id: "spawn-restore",
            title: "Restore lane",
            status: "completed",
            childID: "child-restore",
            durationMilliseconds: 400,
            toolCallCount: 2,
            redactedError: nil,
            tokenCount: 1_234,
            turns: 3
        )
        let snapshot = RunEvidenceSnapshot(
            binding: .init(
                localTabID: UUID(),
                workspaceID: nil,
                backendSessionID: "backend-restore",
                processGeneration: 1,
                requestID: nil,
                isSettled: true
            ),
            goalSummary: nil,
            plan: [],
            workers: [worker],
            tools: .init(succeeded: 0, failed: 0, cancelled: 0, unknown: 0),
            artifacts: [],
            gitReviewFiles: [],
            process: .init(state: "ready", model: nil, mcps: []),
            continuity: .init(
                status: "bound",
                reason: "fresh",
                provenance: "test",
                requiresRecoveryAction: false
            ),
            usage: .init(totalTokens: nil, modelCalls: nil, turnCount: nil),
            outcome: .completed,
            unresolvedErrors: [],
            nextAction: ""
        )
        let checkpoint = AssistantTurnCheckpoint(snapshot: snapshot, requestedToolFamilies: [])
        let restored = checkpoint.restoredRunEvidenceSnapshot(settledTools: [])
        XCTAssertEqual(restored.workers.first?.tokenCount, 1_234)
        XCTAssertEqual(restored.workers.first?.turns, 3)
        XCTAssertEqual(restored.workers.first?.spawnToolCallID, "spawn-restore")
        XCTAssertEqual(restored.workers.first?.childID, "child-restore")
    }
}
