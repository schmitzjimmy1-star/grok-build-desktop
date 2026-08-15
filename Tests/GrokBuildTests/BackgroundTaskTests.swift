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
        XCTAssertEqual(worker?.runtimeModelID, "grok-4.5")
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

    func testSubagentCorrelationIsStableAcrossAllToolSpawnFinishPermutations() throws {
        enum Event: CaseIterable {
            case tool
            case spawned
            case finished
        }
        let permutations: [[Event]] = [
            [.tool, .spawned, .finished],
            [.tool, .finished, .spawned],
            [.spawned, .tool, .finished],
            [.spawned, .finished, .tool],
            [.finished, .tool, .spawned],
            [.finished, .spawned, .tool],
        ]
        let tabID = UUID()
        let identity = ACPEventIdentity(
            localTabID: tabID,
            backendSessionID: "backend-permutation",
            processGeneration: 4,
            backendEventID: "event-permutation"
        )

        for ordering in permutations {
            var tracker = BackgroundTaskTracker()
            for event in ordering {
                switch event {
                case .tool:
                    tracker.apply(update: [
                        "toolCallId": "spawn-permutation",
                        "title": "Inspect worker correlation",
                        "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
                        "rawInput": [
                            "task_id": NSNull(),
                            "description": "Inspect worker correlation",
                        ],
                    ])
                case .spawned:
                    tracker.apply(spawned: SubagentSpawnedEvent(
                        identity: identity,
                        childID: "child-permutation",
                        parentPromptID: "prompt-permutation",
                        subagentType: "explore",
                        modelID: "grok-4.6",
                        description: "Inspect worker correlation"
                    ))
                case .finished:
                    tracker.apply(finished: SubagentFinishedEvent(
                        identity: identity,
                        childID: "child-permutation",
                        status: "completed",
                        durationMilliseconds: 420,
                        turns: 1,
                        toolCallCount: 2,
                        tokenCount: 900,
                        redactedError: nil,
                        childToolReceipts: [
                            ChildToolReceipt(
                                id: "read-1",
                                title: "Read package",
                                status: .succeeded,
                                mcpReceiptRole: nil,
                                qualifiedToolName: nil,
                                discoveredQualifiedToolNames: []
                            ),
                            ChildToolReceipt(
                                id: "read-2",
                                title: "Read tests",
                                status: .succeeded,
                                mcpReceiptRole: nil,
                                qualifiedToolName: nil,
                                discoveredQualifiedToolNames: []
                            ),
                        ]
                    ))
                }
            }

            let workers = tracker.activities.filter { $0.kind == .subagent }
            let worker = try XCTUnwrap(workers.first, "ordering \(ordering) did not bind")
            XCTAssertEqual(workers.count, 1, "ordering \(ordering)")
            XCTAssertEqual(worker.id, "spawn-permutation", "ordering \(ordering)")
            XCTAssertEqual(worker.childID, "child-permutation", "ordering \(ordering)")
            XCTAssertEqual(worker.status, "completed", "ordering \(ordering)")
            XCTAssertEqual(worker.runtimeModelID, "grok-4.6", "ordering \(ordering)")
            XCTAssertEqual(worker.toolCallCount, 2, "ordering \(ordering)")
            XCTAssertTrue(tracker.unboundSpawnedEvents.isEmpty, "ordering \(ordering)")

            let metrics = tracker.coordinationMetrics(parentTotalTokens: 1_200)
            XCTAssertEqual(metrics.requestedChildCount, 1, "ordering \(ordering)")
            XCTAssertEqual(metrics.spawnedChildCount, 1, "ordering \(ordering)")
            XCTAssertEqual(metrics.finishedChildCount, 1, "ordering \(ordering)")
            XCTAssertEqual(metrics.maximumUsefulConcurrency, 1, "ordering \(ordering)")
            XCTAssertEqual(metrics.childToolCallCount, 2, "ordering \(ordering)")
            XCTAssertEqual(metrics.unresolvedIdentityCount, 0, "ordering \(ordering)")
            XCTAssertEqual(metrics.parentTotalTokens, 1_200, "ordering \(ordering)")
            XCTAssertEqual(metrics.childTotalTokens, 900, "ordering \(ordering)")
        }
    }

    func testDuplicateLifecycleEventsKeepOneWorkerAndOneMetricReceipt() {
        var tracker = BackgroundTaskTracker()
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-duplicate",
            processGeneration: 2,
            backendEventID: "event-duplicate"
        )
        let spawned = SubagentSpawnedEvent(
            identity: identity,
            childID: "child-duplicate",
            parentPromptID: nil,
            subagentType: "explore",
            modelID: "grok-4.6",
            description: "Duplicate lane"
        )
        let finished = SubagentFinishedEvent(
            identity: identity,
            childID: "child-duplicate",
            status: "completed",
            durationMilliseconds: 100,
            turns: 1,
            toolCallCount: 1,
            tokenCount: 50,
            redactedError: nil
        )
        tracker.apply(update: [
            "toolCallId": "spawn-duplicate",
            "title": "Duplicate lane",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["description": "Duplicate lane"],
        ])
        tracker.apply(spawned: spawned)
        tracker.apply(spawned: spawned)
        tracker.apply(finished: finished)
        tracker.apply(finished: SubagentFinishedEvent(
            identity: identity,
            childID: "child-duplicate",
            status: "unknown",
            durationMilliseconds: nil,
            turns: nil,
            toolCallCount: nil,
            tokenCount: nil,
            redactedError: nil
        ))

        let workers = tracker.activities.filter { $0.kind == .subagent }
        XCTAssertEqual(workers.count, 1)
        XCTAssertEqual(workers.first?.status, "completed")
        XCTAssertEqual(workers.first?.durationMilliseconds, 100)
        XCTAssertEqual(workers.first?.toolCallCount, 1)
        XCTAssertEqual(workers.first?.tokenCount, 50)
        let metrics = tracker.coordinationMetrics(parentTotalTokens: nil)
        XCTAssertEqual(metrics.spawnedChildCount, 1)
        XCTAssertEqual(metrics.finishedChildCount, 1)
        XCTAssertEqual(metrics.childToolCallCount, 1)
        XCTAssertEqual(metrics.childTotalTokens, 50)
    }

    func testAmbiguousDescriptionsRemainExplicitlyUnbound() {
        var tracker = BackgroundTaskTracker()
        for callID in ["spawn-a", "spawn-b"] {
            tracker.apply(update: [
                "toolCallId": callID,
                "title": "Same lane",
                "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
                "rawInput": ["description": "Same lane"],
            ])
        }
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: ACPEventIdentity(
                localTabID: UUID(),
                backendSessionID: "backend-ambiguous",
                processGeneration: 1,
                backendEventID: "spawn-ambiguous"
            ),
            childID: "child-ambiguous",
            parentPromptID: nil,
            subagentType: "explore",
            modelID: "grok-4.6",
            description: "Same lane"
        ))

        XCTAssertEqual(tracker.activities.filter { $0.kind == .subagent }.count, 2)
        XCTAssertTrue(tracker.activities.compactMap(\.childID).isEmpty)
        XCTAssertEqual(tracker.unboundSpawnedEvents.map(\.childID), ["child-ambiguous"])
        XCTAssertEqual(tracker.coordinationMetrics(parentTotalTokens: nil).unresolvedIdentityCount, 3)
    }

    func testCoordinationMetricsTrackConcurrencyStopAndTurnReset() {
        var tracker = BackgroundTaskTracker()
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-metrics",
            processGeneration: 1,
            backendEventID: "spawn-metrics"
        )
        for index in 1...2 {
            tracker.apply(update: [
                "toolCallId": "spawn-\(index)",
                "title": "Lane \(index)",
                "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
                "rawInput": ["task_id": "child-\(index)", "description": "Lane \(index)"],
            ])
            tracker.apply(spawned: SubagentSpawnedEvent(
                identity: identity,
                childID: "child-\(index)",
                parentPromptID: nil,
                subagentType: "explore",
                modelID: "grok-4.6",
                description: "Lane \(index)"
            ))
        }
        tracker.recordStopToSettle(milliseconds: 275)

        let observed = tracker.coordinationMetrics(parentTotalTokens: nil)
        XCTAssertEqual(observed.maximumUsefulConcurrency, 2)
        XCTAssertEqual(observed.stopToSettleMilliseconds, 275)
        XCTAssertNil(observed.childToolCallCount)
        XCTAssertNil(observed.childTotalTokens)

        tracker.beginUserTurn()
        let reset = tracker.coordinationMetrics(parentTotalTokens: nil)
        XCTAssertEqual(reset.requestedChildCount, 0)
        XCTAssertEqual(reset.spawnedChildCount, 0)
        XCTAssertEqual(reset.finishedChildCount, 0)
        XCTAssertEqual(reset.maximumUsefulConcurrency, 0)
        XCTAssertNil(reset.stopToSettleMilliseconds)
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

    func testBackgroundTaskTrackerMarksNonSubagentActivitiesStopped() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "shell-1",
            "_meta": ["x.ai/tool": ["name": "run_terminal_command"]],
            "rawInput": ["command": "sleep 60", "is_background": true]
        ])

        tracker.markActiveActivitiesStopped()

        XCTAssertEqual(tracker.activities.count, 1)
        XCTAssertEqual(tracker.activities.first?.status, "stopped")
    }

    func testStopMidChildMarksBoundSubagentOrphanedNotStopped() throws {
        var tracker = BackgroundTaskTracker()
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-1",
            processGeneration: 1,
            backendEventID: "spawn-1"
        )
        tracker.apply(update: [
            "toolCallId": "spawn-call",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["task_id": "child-1", "description": "Mid-child work"]
        ])
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: "child-1",
            parentPromptID: nil,
            subagentType: "explore",
            modelID: "grok-4.5",
            description: "Mid-child work"
        ))

        tracker.markActiveSubagentsStoppedByUser()

        let worker = try XCTUnwrap(tracker.activities.first(where: { $0.kind == .subagent }))
        XCTAssertEqual(worker.status, "orphaned")
        XCTAssertEqual(worker.childID, "child-1")
        XCTAssertNotEqual(worker.status, "stopped")
        XCTAssertNotEqual(worker.status, "completed")
    }

    func testStopMidChildWithoutChildIDMarksCancelled() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "spawn-call",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["prompt": "No child yet"]
        ])

        tracker.markActiveSubagentsStoppedByUser()

        XCTAssertEqual(tracker.activities.first?.status, "cancelled")
    }

    func testUnboundSpawnedEventSurfacesWithoutInventingActivityRow() {
        var tracker = BackgroundTaskTracker()
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-1",
            processGeneration: 1,
            backendEventID: "spawn-orphan"
        )
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: "orphan-child",
            parentPromptID: nil,
            subagentType: "general-purpose",
            modelID: "grok-4.5",
            description: "No spawn row"
        ))

        XCTAssertTrue(tracker.activities.filter { $0.kind == .subagent }.isEmpty)
        XCTAssertEqual(tracker.unboundSpawnedEvents.count, 1)
        XCTAssertEqual(tracker.unboundSpawnedEvents.first?.childID, "orphan-child")
    }

    func testChildLedgerReadOutcomeDistinguishesUnreadableFromEmpty() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "spawn-call",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["task_id": "child-1", "prompt": "Ledger test"]
        ])
        tracker.reconcileChildToolReceipts(childID: "child-1", receipts: nil)
        XCTAssertEqual(
            tracker.activities.first?.childLedgerReadOutcome,
            .unreadable
        )

        tracker.reconcileChildToolReceipts(childID: "child-1", receipts: [])
        XCTAssertEqual(
            tracker.activities.first?.childLedgerReadOutcome,
            .empty
        )
        XCTAssertEqual(tracker.activities.first?.childToolReceipts, [])

        let receipt = ChildToolReceipt(
            id: "tool-1",
            title: "search",
            status: .succeeded,
            mcpReceiptRole: nil,
            qualifiedToolName: nil,
            discoveredQualifiedToolNames: []
        )
        tracker.reconcileChildToolReceipts(childID: "child-1", receipts: [receipt])
        XCTAssertEqual(
            tracker.activities.first?.childLedgerReadOutcome,
            .receipts
        )
    }

    func testBackgroundTaskTrackerMarksActiveSubagentsOrphanedWithoutHidingEvidence() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "call-1",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "reviewer", "prompt": "Review the diff", "task_id": "sub-1"]
        ])
        tracker.apply(update: [
            "toolCallId": "call-1",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawOutput": ["task_id": "sub-1", "status": "running"]
        ])

        tracker.markActiveSubagentsStoppedByUser()

        XCTAssertEqual(tracker.activities.count, 1)
        XCTAssertEqual(tracker.activities.first?.status, "orphaned")
    }

    func testUserStopLeavesAlreadyFinishedWorkersCompleted() {
        var tracker = BackgroundTaskTracker()
        let childID = "child-finished-during-stop"
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-1",
            processGeneration: 3,
            backendEventID: "event-1"
        )
        tracker.apply(update: [
            "toolCallId": "spawn-call",
            "title": "Education lane",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["task_id": childID, "description": "Education lane"]
        ])
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: childID,
            parentPromptID: nil,
            subagentType: "general-purpose",
            modelID: "grok-4.6",
            description: "Education lane"
        ))
        tracker.apply(finished: SubagentFinishedEvent(
            identity: identity,
            childID: childID,
            status: "completed",
            durationMilliseconds: 800,
            turns: 1,
            toolCallCount: 2,
            tokenCount: 40,
            redactedError: nil
        ))

        tracker.markActiveSubagentsStoppedByUser()

        XCTAssertEqual(tracker.activities.first?.status, "completed",
                       "a subagent_finished drained during Stop is ACP truth, not an orphan")
        XCTAssertEqual(tracker.activities.count, 1)
    }

    func testBeginUserTurnDropsPriorWorkersButKeepsScheduled() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "prior-worker",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "reviewer", "prompt": "Prior turn work"]
        ])
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

        tracker.beginUserTurn()

        XCTAssertEqual(tracker.activities.count, 1)
        XCTAssertEqual(tracker.activities.first?.kind, .scheduled)
        XCTAssertEqual(tracker.activities.first?.scheduledTask?.prompt, "ping")

        tracker.apply(update: [
            "toolCallId": "current-worker",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "mapper", "prompt": "Current turn only"]
        ])

        XCTAssertEqual(tracker.activities.count, 2)
        XCTAssertEqual(tracker.activities.filter { $0.kind == .subagent }.count, 1)
        XCTAssertEqual(tracker.activities.first(where: { $0.kind == .subagent })?.id, "current-worker")
    }

    func testBeginUserTurnDropsUnboundSpawnedEventsEvenWithoutActivities() {
        var tracker = BackgroundTaskTracker()
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-1",
            processGeneration: 1,
            backendEventID: "spawn-orphan"
        )
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: "orphan-child",
            parentPromptID: nil,
            subagentType: "general-purpose",
            modelID: "grok-4.5",
            description: "No spawn row"
        ))
        XCTAssertEqual(tracker.unboundSpawnedEvents.count, 1)

        tracker.beginUserTurn()

        XCTAssertTrue(tracker.unboundSpawnedEvents.isEmpty)
        XCTAssertTrue(tracker.activities.isEmpty)
    }

    func testBeginUserTurnDropsUnboundSpawnedEventsAlongsidePriorWorkers() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "prior-worker",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "reviewer", "prompt": "Prior turn work"]
        ])
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: ACPEventIdentity(
                localTabID: UUID(),
                backendSessionID: "backend-1",
                processGeneration: 1,
                backendEventID: "unbound"
            ),
            childID: "unbound-child",
            parentPromptID: nil,
            subagentType: "explore",
            modelID: "grok-4.5",
            description: "Never bound"
        ))
        XCTAssertEqual(tracker.unboundSpawnedEvents.count, 1)

        tracker.beginUserTurn()

        XCTAssertTrue(tracker.unboundSpawnedEvents.isEmpty)
        XCTAssertTrue(tracker.activities.filter { $0.kind == .subagent }.isEmpty)
    }

    func testEvidenceWorkersIncludeOnlyCurrentTurnSubagentsAndUnboundSpawns() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "prior-worker",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "prior", "prompt": "Last turn"]
        ])
        tracker.apply(update: [
            "toolCallId": "current-worker",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "reviewer", "prompt": "Review the diff"]
        ])
        tracker.apply(update: [
            "toolCallId": "shell-1",
            "_meta": ["x.ai/tool": ["name": "run_terminal_command"]],
            "rawInput": ["command": "sleep 60", "background": true]
        ])
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: ACPEventIdentity(
                localTabID: UUID(),
                backendSessionID: "backend-1",
                processGeneration: 1,
                backendEventID: "spawn-reviewer"
            ),
            childID: "child-reviewer",
            parentPromptID: nil,
            subagentType: "reviewer",
            modelID: "grok-4.5",
            description: "reviewer"
        ))
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: ACPEventIdentity(
                localTabID: UUID(),
                backendSessionID: "backend-1",
                processGeneration: 1,
                backendEventID: "spawn-orphan"
            ),
            childID: "orphan-child",
            parentPromptID: nil,
            subagentType: "explore",
            modelID: "grok-4.6",
            description: "Never bound"
        ))

        let workers = tracker.evidenceWorkers(
            currentTurnActivityIDs: ["current-worker", "shell-1"],
            planStepIDs: ["current-worker": "step-3"],
            rolesByName: ["reviewer": "deepseek-deepseek-v4-flash-0731"]
        )

        XCTAssertEqual(workers.map(\.id), ["current-worker", "unbound|orphan-child"])
        XCTAssertEqual(workers[0].title, "reviewer")
        XCTAssertEqual(workers[0].childID, "child-reviewer")
        XCTAssertEqual(workers[0].owningPlanStepID, "step-3")
        XCTAssertEqual(workers[0].runtimeModelID, "grok-4.5")
        XCTAssertEqual(workers[0].routedModel, "deepseek-deepseek-v4-flash-0731")
        XCTAssertEqual(workers[1].status, "unknown")
        XCTAssertEqual(workers[1].childID, "orphan-child")
        XCTAssertEqual(workers[1].runtimeModelID, "grok-4.6")
        XCTAssertNil(workers[1].owningPlanStepID)
    }

    func testEvidenceWorkersOmitPriorTurnWhenActivityIDsAreEmpty() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(update: [
            "toolCallId": "current-worker",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["name": "reviewer", "prompt": "Review the diff"]
        ])
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: ACPEventIdentity(
                localTabID: UUID(),
                backendSessionID: "backend-1",
                processGeneration: 1,
                backendEventID: "spawn-orphan"
            ),
            childID: "orphan-child",
            parentPromptID: nil,
            subagentType: "general-purpose",
            modelID: "grok-4.5",
            description: "No spawn row"
        ))

        let workers = tracker.evidenceWorkers(
            currentTurnActivityIDs: [],
            planStepIDs: [:],
            rolesByName: [:]
        )

        XCTAssertEqual(workers.map(\.id), ["unbound|orphan-child"])
    }

    func testEvidenceWorkersCarryTokenAndTurnReceiptsFromFinishedEvent() {
        var tracker = BackgroundTaskTracker()
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-tokens",
            processGeneration: 1,
            backendEventID: "event-tokens"
        )
        tracker.apply(update: [
            "toolCallId": "spawn-tokens",
            "title": "Token lane",
            "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
            "rawInput": ["task_id": "child-tokens", "description": "Token lane"],
        ])
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: "child-tokens",
            parentPromptID: nil,
            subagentType: "explore",
            modelID: "grok-4.6",
            description: "Token lane"
        ))
        tracker.apply(finished: SubagentFinishedEvent(
            identity: identity,
            childID: "child-tokens",
            status: "completed",
            durationMilliseconds: 1_250,
            turns: 2,
            toolCallCount: 3,
            tokenCount: 8_796,
            redactedError: nil
        ))

        let workers = tracker.evidenceWorkers(
            currentTurnActivityIDs: ["spawn-tokens"],
            planStepIDs: [:],
            rolesByName: [:]
        )
        XCTAssertEqual(workers.count, 1)
        XCTAssertEqual(workers[0].tokenCount, 8_796)
        XCTAssertEqual(workers[0].turns, 2)
        XCTAssertEqual(workers[0].spawnToolCallID, "spawn-tokens")
        XCTAssertEqual(workers[0].childID, "child-tokens")
    }

    func testFinishOnlyWithoutSpawnSurfacesUnboundFinishedWorker() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(finished: SubagentFinishedEvent(
            identity: ACPEventIdentity(
                localTabID: UUID(),
                backendSessionID: "backend-finish-only",
                processGeneration: 1,
                backendEventID: "finish-only"
            ),
            childID: "child-finish-only",
            status: "completed",
            durationMilliseconds: 400,
            turns: 1,
            toolCallCount: 2,
            tokenCount: 500,
            redactedError: nil
        ))

        XCTAssertTrue(tracker.activities.isEmpty)
        XCTAssertEqual(tracker.unboundFinishedEvents.map(\.childID), ["child-finish-only"])
        let workers = tracker.evidenceWorkers(
            currentTurnActivityIDs: [],
            planStepIDs: [:],
            rolesByName: [:]
        )
        XCTAssertEqual(workers.map(\.id), ["unbound-finish|child-finish-only"])
        XCTAssertEqual(workers[0].status, "completed")
        XCTAssertEqual(workers[0].tokenCount, 500)
        XCTAssertEqual(workers[0].turns, 1)
        XCTAssertNil(workers[0].spawnToolCallID)
        let metrics = tracker.coordinationMetrics(parentTotalTokens: nil)
        XCTAssertEqual(metrics.finishedChildCount, 1)
        XCTAssertEqual(metrics.childTotalTokens, 500)
    }

    func testUnboundSpawnThenFinishKeepsTerminalMetricsOnOneWorker() {
        var tracker = BackgroundTaskTracker()
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-unbound-merge",
            processGeneration: 1,
            backendEventID: "unbound-merge"
        )
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: "child-unbound-merge",
            parentPromptID: nil,
            subagentType: "explore",
            modelID: "grok-4.6",
            description: "No spawn row"
        ))
        tracker.apply(finished: SubagentFinishedEvent(
            identity: identity,
            childID: "child-unbound-merge",
            status: "completed",
            durationMilliseconds: 800,
            turns: 2,
            toolCallCount: 1,
            tokenCount: 640,
            redactedError: nil
        ))

        let workers = tracker.evidenceWorkers(
            currentTurnActivityIDs: [],
            planStepIDs: [:],
            rolesByName: [:]
        )
        XCTAssertEqual(workers.count, 1)
        XCTAssertEqual(workers[0].id, "unbound|child-unbound-merge")
        XCTAssertEqual(workers[0].status, "completed")
        XCTAssertEqual(workers[0].tokenCount, 640)
        XCTAssertEqual(workers[0].turns, 2)
        XCTAssertEqual(workers[0].durationMilliseconds, 800)
        XCTAssertNil(workers[0].spawnToolCallID)
        XCTAssertEqual(tracker.coordinationMetrics(parentTotalTokens: nil).childTotalTokens, 640)
    }

    func testFinishThenUnboundSpawnDoesNotRegressTerminalMetrics() {
        var tracker = BackgroundTaskTracker()
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-finish-first",
            processGeneration: 1,
            backendEventID: "finish-first"
        )
        tracker.apply(finished: SubagentFinishedEvent(
            identity: identity,
            childID: "child-finish-first",
            status: "completed",
            durationMilliseconds: 500,
            turns: 1,
            toolCallCount: 2,
            tokenCount: 500,
            redactedError: nil
        ))
        XCTAssertEqual(
            tracker.evidenceWorkers(currentTurnActivityIDs: [], planStepIDs: [:], rolesByName: [:]).map(\.id),
            ["unbound-finish|child-finish-first"]
        )
        tracker.apply(spawned: SubagentSpawnedEvent(
            identity: identity,
            childID: "child-finish-first",
            parentPromptID: nil,
            subagentType: "explore",
            modelID: "grok-4.6",
            description: "Late spawn"
        ))

        let workers = tracker.evidenceWorkers(
            currentTurnActivityIDs: [],
            planStepIDs: [:],
            rolesByName: [:]
        )
        XCTAssertEqual(workers.count, 1)
        XCTAssertEqual(workers[0].id, "unbound|child-finish-first")
        XCTAssertEqual(workers[0].status, "completed")
        XCTAssertEqual(workers[0].tokenCount, 500)
        XCTAssertEqual(workers[0].turns, 1)
        XCTAssertTrue(workers[0].title.contains("Late spawn"))
    }

    func testBeginUserTurnDropsUnboundFinishedEvents() {
        var tracker = BackgroundTaskTracker()
        tracker.apply(finished: SubagentFinishedEvent(
            identity: ACPEventIdentity(
                localTabID: UUID(),
                backendSessionID: "backend-finish-drop",
                processGeneration: 1,
                backendEventID: "finish-drop"
            ),
            childID: "child-finish-drop",
            status: "completed",
            durationMilliseconds: 100,
            turns: 1,
            toolCallCount: 0,
            tokenCount: 42,
            redactedError: nil
        ))
        XCTAssertEqual(tracker.unboundFinishedEvents.count, 1)

        tracker.beginUserTurn()

        XCTAssertTrue(tracker.unboundFinishedEvents.isEmpty)
        XCTAssertTrue(
            tracker.evidenceWorkers(currentTurnActivityIDs: [], planStepIDs: [:], rolesByName: [:]).isEmpty
        )
    }

    func testTwoChildInterleavedPermutationsStayIsolated() {
        enum Event: CaseIterable {
            case toolA, spawnA, finishA, toolB, spawnB, finishB
        }
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend-two-child",
            processGeneration: 3,
            backendEventID: "event-two-child"
        )
        let orderings: [[Event]] = [
            [.toolA, .toolB, .spawnA, .spawnB, .finishA, .finishB],
            [.finishB, .finishA, .spawnB, .spawnA, .toolB, .toolA],
            [.spawnA, .toolB, .finishA, .toolA, .spawnB, .finishB],
            [.finishA, .toolA, .spawnA, .finishB, .toolB, .spawnB],
        ]

        for ordering in orderings {
            var tracker = BackgroundTaskTracker()
            for event in ordering {
                switch event {
                case .toolA:
                    tracker.apply(update: [
                        "toolCallId": "spawn-a",
                        "title": "Lane A",
                        "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
                        "rawInput": ["task_id": "child-a", "description": "Lane A"],
                    ])
                case .toolB:
                    tracker.apply(update: [
                        "toolCallId": "spawn-b",
                        "title": "Lane B",
                        "_meta": ["x.ai/tool": ["name": "spawn_subagent"]],
                        "rawInput": ["task_id": "child-b", "description": "Lane B"],
                    ])
                case .spawnA:
                    tracker.apply(spawned: SubagentSpawnedEvent(
                        identity: identity,
                        childID: "child-a",
                        parentPromptID: nil,
                        subagentType: "explore",
                        modelID: "grok-4.6",
                        description: "Lane A"
                    ))
                case .spawnB:
                    tracker.apply(spawned: SubagentSpawnedEvent(
                        identity: identity,
                        childID: "child-b",
                        parentPromptID: nil,
                        subagentType: "reviewer",
                        modelID: "grok-4.5",
                        description: "Lane B"
                    ))
                case .finishA:
                    tracker.apply(finished: SubagentFinishedEvent(
                        identity: identity,
                        childID: "child-a",
                        status: "completed",
                        durationMilliseconds: 100,
                        turns: 1,
                        toolCallCount: 2,
                        tokenCount: 111,
                        redactedError: nil
                    ))
                case .finishB:
                    tracker.apply(finished: SubagentFinishedEvent(
                        identity: identity,
                        childID: "child-b",
                        status: "failed",
                        durationMilliseconds: 200,
                        turns: 3,
                        toolCallCount: 4,
                        tokenCount: 222,
                        redactedError: "redacted"
                    ))
                }
            }

            let workers = tracker.activities.filter { $0.kind == .subagent }
            XCTAssertEqual(workers.count, 2, "ordering \(ordering)")
            let byChild = Dictionary(uniqueKeysWithValues: workers.compactMap { worker in
                worker.childID.map { ($0, worker) }
            })
            XCTAssertEqual(byChild["child-a"]?.id, "spawn-a", "ordering \(ordering)")
            XCTAssertEqual(byChild["child-a"]?.status, "completed", "ordering \(ordering)")
            XCTAssertEqual(byChild["child-a"]?.tokenCount, 111, "ordering \(ordering)")
            XCTAssertEqual(byChild["child-a"]?.turns, 1, "ordering \(ordering)")
            XCTAssertEqual(byChild["child-b"]?.id, "spawn-b", "ordering \(ordering)")
            XCTAssertEqual(byChild["child-b"]?.status, "failed", "ordering \(ordering)")
            XCTAssertEqual(byChild["child-b"]?.tokenCount, 222, "ordering \(ordering)")
            XCTAssertEqual(byChild["child-b"]?.turns, 3, "ordering \(ordering)")
            XCTAssertTrue(tracker.unboundSpawnedEvents.isEmpty, "ordering \(ordering)")
            XCTAssertTrue(tracker.unboundFinishedEvents.isEmpty, "ordering \(ordering)")
            let evidence = tracker.evidenceWorkers(
                currentTurnActivityIDs: ["spawn-a", "spawn-b"],
                planStepIDs: [:],
                rolesByName: [:]
            )
            XCTAssertEqual(evidence.count, 2, "ordering \(ordering)")
            let evidenceByChild = Dictionary(uniqueKeysWithValues: evidence.compactMap { worker in
                worker.childID.map { ($0, worker) }
            })
            XCTAssertEqual(evidenceByChild["child-a"]?.tokenCount, 111, "ordering \(ordering)")
            XCTAssertEqual(evidenceByChild["child-a"]?.turns, 1, "ordering \(ordering)")
            XCTAssertEqual(evidenceByChild["child-a"]?.spawnToolCallID, "spawn-a", "ordering \(ordering)")
            XCTAssertEqual(evidenceByChild["child-b"]?.tokenCount, 222, "ordering \(ordering)")
            XCTAssertEqual(evidenceByChild["child-b"]?.turns, 3, "ordering \(ordering)")
            XCTAssertEqual(evidenceByChild["child-b"]?.spawnToolCallID, "spawn-b", "ordering \(ordering)")
            let metrics = tracker.coordinationMetrics(parentTotalTokens: 900)
            XCTAssertEqual(metrics.requestedChildCount, 2, "ordering \(ordering)")
            XCTAssertEqual(metrics.spawnedChildCount, 2, "ordering \(ordering)")
            XCTAssertEqual(metrics.finishedChildCount, 2, "ordering \(ordering)")
            XCTAssertEqual(metrics.childTotalTokens, 333, "ordering \(ordering)")
            XCTAssertEqual(metrics.unresolvedIdentityCount, 0, "ordering \(ordering)")
        }
    }
}
