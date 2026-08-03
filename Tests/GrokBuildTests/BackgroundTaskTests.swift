import XCTest
@testable import GrokBuild

final class BackgroundTaskTests: XCTestCase {
    func testBackgroundToolParsingDetectsScheduler() {
        let update: [String: Any] = [
            "_meta": ["x.ai/tool": ["name": "scheduler_list"]],
            "rawOutput": ["type": "SchedulerList", "tasks": []]
        ]
        XCTAssertEqual(BackgroundToolParsing.backgroundToolName(inUpdate: update), "scheduler_list")
    }

    func testBackgroundToolParsingDetectsBackgroundTerminal() {
        let update: [String: Any] = [
            "_meta": ["x.ai/tool": ["name": "run_terminal_command"]],
            "rawInput": ["command": "sleep 60", "background": true]
        ]
        XCTAssertEqual(BackgroundToolParsing.backgroundToolName(inUpdate: update), "run_terminal_command")
        XCTAssertEqual(
            BackgroundToolParsing.activityKind(for: "run_terminal_command", input: update["rawInput"] as! [String: Any]),
            .backgroundCommand
        )
    }

    func testBackgroundToolParsingIgnoresForegroundTerminal() {
        let input: [String: Any] = ["command": "ls", "background": false]
        XCTAssertNil(BackgroundToolParsing.activityKind(for: "run_terminal_command", input: input))
    }

    func testOnlyExplicitSpawnCreatesSubagentActivity() {
        XCTAssertEqual(
            BackgroundToolParsing.activityKind(for: "spawn_subagent", input: [:]),
            .subagent
        )
        XCTAssertNil(
            BackgroundToolParsing.activityKind(
                for: "get_command_or_subagent_output",
                input: ["task_ids": ["child-1"]]
            )
        )
        XCTAssertNil(
            BackgroundToolParsing.activityKind(for: "some_other_subagent_helper", input: [:])
        )
    }

    func testBackgroundTaskTrackerAccumulatesSubagent() {
        var tracker = BackgroundTaskTracker()
        let callID = "call-1"
        tracker.apply(update: [
            "toolCallId": callID,
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "reviewer", "prompt": "Review the diff"]
        ])
        tracker.apply(update: [
            "toolCallId": callID,
            "rawOutput": ["id": "sub-1", "status": "running"]
        ])
        XCTAssertEqual(tracker.activities.count, 1)
        XCTAssertEqual(tracker.activities.first?.kind, .subagent)
        XCTAssertEqual(tracker.activities.first?.title, "reviewer")
    }

    func testBackgroundTaskTrackerCorrelatesSpawnWaitAndFinishedWithoutGhosts() {
        var tracker = BackgroundTaskTracker()
        let callID = "spawn-call"
        let childID = "child-1"
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-1",
            processGeneration: 3,
            backendEventID: "event-1"
        )

        tracker.apply(update: [
            "toolCallId": callID,
            "title": "Education lane",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["prompt": "Research education"]
        ])
        tracker.apply(update: [
            "toolCallId": callID,
            "title": "Education lane",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["task_id": childID, "description": "Education lane"]
        ])
        tracker.apply(update: [
            "toolCallId": callID,
            "status": "completed",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawOutput": ["type": "SubagentSpawned", "task_id": childID]
        ])

        tracker.apply(update: [
            "toolCallId": "wait-call",
            "_meta": ["x.ai/tool": ["name": "get_command_or_subagent_output"]],
            "rawInput": ["task_ids": [childID]]
        ])
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: childID,
            parentPromptID: nil,
            subagentType: "general-purpose",
            modelID: "grok-4.5",
            description: nil
        ))
        tracker.apply(finished: SubagentFinishedEvent(
            identity: identity,
            childID: childID,
            status: "completed",
            durationMilliseconds: 1_234,
            turns: 1,
            toolCallCount: 7,
            tokenCount: 99,
            redactedError: nil
        ))

        XCTAssertEqual(tracker.activities.filter { $0.kind == .subagent }.count, 1)
        let worker = tracker.activities.first(where: { $0.kind == .subagent })
        XCTAssertEqual(worker?.id, callID)
        XCTAssertEqual(worker?.toolCallID, callID)
        XCTAssertEqual(worker?.childID, childID)
        XCTAssertEqual(worker?.status, "completed")
        XCTAssertEqual(worker?.durationMilliseconds, 1_234)
        XCTAssertEqual(worker?.toolCallCount, 7)
        XCTAssertEqual(worker?.collectionReceiptCount, 1)
    }

    func testLifecycleDescriptionBindsAnExistingSpawnWhenToolChildIDIsNull() {
        var tracker = BackgroundTaskTracker()
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-1",
            processGeneration: 3,
            backendEventID: "event-1"
        )
        tracker.apply(update: [
            "toolCallId": "spawn-map",
            "title": "Map Swift package tests",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            // Grok currently emits `task_id: null` at this stage.
            "rawInput": ["task_id": NSNull(), "description": "Map Swift package tests"]
        ])
        tracker.apply(update: [
            "toolCallId": "spawn-review",
            "title": "Review discount stock logic",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["task_id": NSNull(), "description": "Review discount stock logic"]
        ])

        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: "child-map",
            parentPromptID: "prompt-1",
            subagentType: "explore",
            modelID: "grok-4.5",
            description: "Map Swift package tests"
        ))
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: "child-review",
            parentPromptID: "prompt-1",
            subagentType: "explore",
            modelID: "grok-4.5",
            description: "Review discount stock logic"
        ))
        tracker.apply(finished: SubagentFinishedEvent(
            identity: identity,
            childID: "child-map",
            status: "completed",
            durationMilliseconds: 100,
            turns: 1,
            toolCallCount: 7,
            tokenCount: 8_796,
            redactedError: nil
        ))
        tracker.apply(finished: SubagentFinishedEvent(
            identity: identity,
            childID: "child-review",
            status: "completed",
            durationMilliseconds: 110,
            turns: 1,
            toolCallCount: 7,
            tokenCount: 9_729,
            redactedError: nil
        ))

        XCTAssertEqual(tracker.activities.filter { $0.kind == .subagent }.count, 2)
        XCTAssertEqual(Set(tracker.activities.compactMap(\.childID)), Set(["child-map", "child-review"]))
        XCTAssertTrue(tracker.activities.filter { $0.kind == .subagent }.allSatisfy { $0.status == "completed" })
    }

    func testMissingTerminalEvidenceIsExplicitlyUnknownOrOrphaned() {
        var unknownTracker = BackgroundTaskTracker()
        unknownTracker.apply(update: [
            "toolCallId": "unknown-spawn",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["prompt": "No child receipt"]
        ])
        unknownTracker.markUnsettledSubagents()
        XCTAssertEqual(unknownTracker.activities.first?.status, "unknown")

        var orphanedTracker = BackgroundTaskTracker()
        orphanedTracker.apply(update: [
            "toolCallId": "orphan-spawn",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["task_id": "orphan-child", "prompt": "No finish receipt"]
        ])
        orphanedTracker.markUnsettledSubagents()
        XCTAssertEqual(orphanedTracker.activities.first?.status, "orphaned")

        orphanedTracker.apply(finished: SubagentFinishedEvent(
            identity: ACPEventIdentity(
                localTabID: UUID(),
                backendSessionID: "backend-1",
                processGeneration: 1,
                backendEventID: "late-finish"
            ),
            childID: "orphan-child",
            status: "failed",
            durationMilliseconds: nil,
            turns: nil,
            toolCallCount: nil,
            tokenCount: nil,
            redactedError: "timeout"
        ))
        XCTAssertEqual(orphanedTracker.activities.first?.status, "failed")
        XCTAssertEqual(orphanedTracker.activities.count, 1)
    }

    func testTurnBarrierMarksOnlyWorkersOwnedByThatTurn() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "prior-worker",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["prompt": "Prior turn"]
        ])
        tracker.apply(update: [
            "toolCallId": "current-worker",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["prompt": "Current turn"]
        ])

        tracker.markUnsettledSubagents(only: ["current-worker"])

        XCTAssertEqual(tracker.activities.first { $0.id == "prior-worker" }?.status, "running")
        XCTAssertEqual(tracker.activities.first { $0.id == "current-worker" }?.status, "unknown")
    }

    func testKillReceiptUpdatesTargetedWorkerWithoutCreatingAnother() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "spawn-call",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["task_id": "child-1", "prompt": "Cancelable work"]
        ])
        tracker.apply(update: [
            "toolCallId": "kill-call",
            "status": "completed",
            "_meta": ["x.ai/tool": ["name": "kill_command_or_subagent"]],
            "rawInput": ["task_id": "child-1"]
        ])

        XCTAssertEqual(tracker.activities.count, 1)
        XCTAssertEqual(tracker.activities.first?.status, "cancelled")
    }

    func testBackgroundTaskTrackerSyncsScheduledTasks() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "rawOutput": [
                "type": "SchedulerList",
                "tasks": [[
                    "id": "t1",
                    "prompt": "ping",
                    "intervalHuman": "5m",
                    "recurring": true
                ]]
            ]
        ])
        XCTAssertEqual(tracker.activities.count, 1)
        XCTAssertEqual(tracker.activities.first?.kind, .scheduled)
        XCTAssertEqual(tracker.activities.first?.scheduledTask?.prompt, "ping")
    }

    func testBackgroundTaskTrackerMarksWorkersStoppedWithoutHidingEvidence() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "call-1",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "reviewer", "prompt": "Review the diff"]
        ])
        tracker.apply(update: [
            "toolCallId": "call-1",
            "rawOutput": ["id": "sub-1", "status": "running"]
        ])

        tracker.markActiveActivitiesStopped()

        XCTAssertEqual(tracker.activities.count, 1)
        XCTAssertEqual(tracker.activities.first?.status, "stopped")
    }
}
