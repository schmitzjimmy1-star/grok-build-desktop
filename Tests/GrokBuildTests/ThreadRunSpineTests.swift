import XCTest
@testable import GrokBuild

final class ThreadRunSpineTests: XCTestCase {
    private let binding = RunEvidenceLiveProjection.Binding(
        localTabID: UUID(),
        workspaceID: UUID(),
        backendSessionID: "backend",
        processGeneration: 9
    )

    func testNoToolRunKeepsAQuietTruthfulPhase() {
        let projection = live(plan: [], workers: [], tools: [])

        XCTAssertEqual(ThreadRunSpinePresentation.livePhase(projection), "Working")
        XCTAssertTrue(ThreadRunSpinePresentation.liveTools(projection, workspace: nil).isEmpty)
    }

    func testOneToolReceiptNamesFamilyOperationStatusAndUnknownBoundaries() {
        let projection = live(tools: [.init(
            id: "terminal-1",
            title: "Run tests",
            kind: "terminal",
            status: "Running",
            detail: "streaming output",
            qualifiedToolName: "terminal__run",
            isActive: true
        )])

        let row = ThreadRunSpinePresentation.liveTools(projection, workspace: nil)[0]
        XCTAssertEqual(row.family, "terminal")
        XCTAssertEqual(row.operation, "terminal__run")
        XCTAssertEqual(row.status, "Running")
        XCTAssertEqual(row.duration, "Duration not reported")
        XCTAssertEqual(row.worker, "Parent agent")
        XCTAssertEqual(row.outputBoundary, "No file artifact reported")
        XCTAssertNil(row.resultDetail, "Changing tool output must wait for the settled spine")
        XCTAssertEqual(ThreadRunSpinePresentation.livePhase(projection), "Using terminal")
    }

    func testToolDurationUsesOnlyAuthoritativeMilliseconds() {
        let projection = live(tools: [.init(
            id: "terminal-duration",
            title: "Run tests",
            kind: "terminal",
            status: "Succeeded",
            detail: nil,
            durationMilliseconds: 1_250,
            isActive: false
        )])
        XCTAssertEqual(
            ThreadRunSpinePresentation.liveTools(projection, workspace: nil)[0].duration,
            "1.2 s"
        )
        XCTAssertEqual(ThreadRunSpinePresentation.durationLabel(nil), "Duration not reported")
    }

    func testSequentialMultiToolReceiptsKeepOrderAndArtifactBoundary() {
        let workspace = URL(fileURLWithPath: "/tmp/project")
        let projection = live(
            tools: [
                .init(id: "read", title: "Read file", kind: "read", status: "Succeeded", detail: nil, isActive: false),
                .init(id: "write", title: "Write file", kind: "edit", status: "Succeeded", detail: nil, isActive: false),
            ],
            artifacts: [.init(
                toolCallID: "write",
                path: "/tmp/project/Sources/App.swift",
                status: "Completed",
                location: .workspace
            )]
        )

        let rows = ThreadRunSpinePresentation.liveTools(projection, workspace: workspace)
        XCTAssertEqual(rows.map(\.operation), ["Read file", "Write file"])
        XCTAssertEqual(rows[0].outputBoundary, "No file artifact reported")
        XCTAssertEqual(rows[1].outputBoundary, "Sources/App.swift")
    }

    func testTwoParallelWorkersGroupUnderOwningPlanStep() {
        let step = RunEvidenceSnapshot.PlanStep(id: "build", title: "Build both lanes", status: "in_progress")
        let workers = [
            worker(id: "one", stepID: step.id, status: "running"),
            worker(id: "two", stepID: step.id, status: "running"),
            worker(id: "unowned", stepID: nil, status: "running"),
        ]

        XCTAssertEqual(ThreadRunSpinePresentation.workers(workers, ownedBy: step).map(\.id), ["one", "two"])
        XCTAssertEqual(ThreadRunSpinePresentation.unownedWorkers(workers, plan: [step]).map(\.id), ["unowned"])
        XCTAssertEqual(ThreadRunSpinePresentation.progressLabel([step]), "0 completed · 1 remaining")
    }

    func testSettledCommandsAndArtifactsGroupUnderProducingPlanStep() {
        let step = RunEvidenceSnapshot.PlanStep(id: "verify", title: "Verify result", status: "completed")
        let tools = ThreadRunSpinePresentation.settledTools(
            [.init(
                id: "terminal-verify",
                title: "Run tests",
                kind: "terminal",
                status: "Succeeded",
                mcpServerName: nil,
                resultDetail: "5 tests passed",
                owningPlanStepID: step.id
            )],
            artifacts: [],
            workspace: nil
        )
        let artifacts = [ChatStore.RunArtifact(
            toolCallID: "terminal-verify",
            path: "/tmp/report.txt",
            status: "Completed",
            location: .external,
            owningPlanStepID: step.id,
            workerID: nil
        )]

        XCTAssertEqual(ThreadRunSpinePresentation.tools(tools, ownedBy: step).map(\.resultDetail), ["5 tests passed"])
        XCTAssertEqual(ThreadRunSpinePresentation.artifacts(artifacts, ownedBy: step).map(\.toolCallID), ["terminal-verify"])
        XCTAssertTrue(ThreadRunSpinePresentation.unownedTools(tools, plan: [step]).isEmpty)
        XCTAssertTrue(ThreadRunSpinePresentation.unownedArtifacts(artifacts, plan: [step]).isEmpty)
    }

    func testCommandOutputDecodesWithoutProjectingProtocolJSON() {
        let detail = #"{"command":"./check.sh","exit_code":0,"output":[71,66,45,83,49,49,45,84,69,83,84,83,45,80,65,83,83,69,68,10]}"#

        XCTAssertEqual(
            ToolResultPresentation.commandOutput(detail: detail, kind: "execute"),
            "GB-S11-TESTS-PASSED"
        )
        XCTAssertNil(ToolResultPresentation.commandOutput(detail: detail, kind: "edit"))
        XCTAssertNil(ToolResultPresentation.commandOutput(
            detail: #"{"EditsApplied":{"absolute_path":"/tmp/result.txt"}}"#,
            kind: "edit"
        ))
        XCTAssertEqual(
            ToolResultPresentation.commandOutput(detail: "GB-S11-TESTS-PASSED", kind: "execute"),
            "GB-S11-TESTS-PASSED"
        )
    }

    func testFailureReceiptStaysFailedAfterSettlement() {
        let rows = ThreadRunSpinePresentation.settledTools(
            [.init(id: "bad", title: "Run command", kind: "terminal", status: "Failed", mcpServerName: nil)],
            artifacts: [],
            workspace: nil
        )

        XCTAssertEqual(rows.map(\.status), ["Failed"])
        XCTAssertEqual(rows.map(\.duration), ["Duration not reported"])
    }

    func testCancellationAndRecoveryRequiredRemainDistinctCheckpoints() {
        let stopped = snapshot(outcome: .userStopped, recovery: false, settled: true)
        let cancelled = snapshot(outcome: .cancelled, recovery: false, settled: true)
        let recovery = snapshot(outcome: .completed, recovery: true, settled: true)

        XCTAssertEqual(ThreadRunSpinePresentation.checkpointLabel(stopped), "Stopped checkpoint")
        XCTAssertEqual(ThreadRunSpinePresentation.checkpointLabel(cancelled), "Cancelled checkpoint")
        XCTAssertEqual(ThreadRunSpinePresentation.checkpointLabel(recovery), "Recovery required")
        XCTAssertEqual(ThreadRunSpinePresentation.settledPhase(stopped), "Stopped by you")
        XCTAssertEqual(ThreadRunSpinePresentation.settledPhase(cancelled), "Turn cancelled")
    }

    func testTraceKindRoundTripsWithoutBreakingLegacyRows() throws {
        let current = AssistantTurnTrace.Tool(
            id: "tool",
            title: "Run",
            kind: "terminal",
            status: "Succeeded",
            mcpServerName: nil,
            resultDetail: "tests passed",
            owningPlanStepID: "verify"
        )
        let restored = try JSONDecoder().decode(
            AssistantTurnTrace.Tool.self,
            from: JSONEncoder().encode(current)
        )
        let legacy = try JSONDecoder().decode(
            AssistantTurnTrace.Tool.self,
            from: Data(#"{"id":"old","title":"Read","status":"Succeeded","mcpServerName":null,"discoveredQualifiedToolNames":[]}"#.utf8)
        )

        XCTAssertEqual(restored.kind, "terminal")
        XCTAssertEqual(restored.resultDetail, "tests passed")
        XCTAssertEqual(restored.owningPlanStepID, "verify")
        XCTAssertNil(legacy.kind)
        XCTAssertNil(legacy.resultDetail)
        XCTAssertNil(legacy.owningPlanStepID)
    }

    func testTypedTodoPlanCreatesStableStepsAndMergesStatusOnlyUpdates() {
        let initial: [String: Any] = [
            "rawInput": [
                "merge": false,
                "todos": [
                    ["id": "Spawn", "content": "Spawn sibling workers", "status": "in_progress"],
                    ["id": "Collect", "content": "Collect both", "status": "pending"],
                    ["id": "Report", "content": "Report", "status": "pending"],
                ],
            ],
        ]
        let partial: [String: Any] = [
            "rawInput": [
                "merge": true,
                "todos": [
                    ["id": "Spawn", "status": "completed"],
                    ["id": "Collect", "status": "in_progress"],
                ],
            ],
        ]

        let created = ChatStore.applyingPlanUpdate(initial, to: [])
        let merged = ChatStore.applyingPlanUpdate(partial, to: created)

        XCTAssertEqual(created.map(\.id), ["Spawn", "Collect", "Report"])
        XCTAssertEqual(merged.map(\.title), ["Spawn sibling workers", "Collect both", "Report"])
        XCTAssertEqual(merged.map(\.status), ["completed", "in_progress", "pending"])
    }

    func testOnlyTypedTodoWriteReceiptsEnterThePlanProjection() {
        XCTAssertTrue(GrokProcess.isPlanToolUpdate([
            "_meta": ["x.ai/tool": ["name": "todo_write"]],
            "rawInput": ["todos": []],
        ]))
        XCTAssertTrue(GrokProcess.isPlanToolUpdate([
            "rawInput": ["variant": "TodoWrite", "todos": []],
        ]))
        XCTAssertFalse(GrokProcess.isPlanToolUpdate([
            "_meta": ["x.ai/tool": ["name": "execute"]],
            "rawInput": ["command": "true"],
        ]))
    }

    func testTaskContractNeverClaimsExitedWorkIsStillRunning() {
        let checkpoint = AssistantTurnCheckpoint(
            snapshot: snapshot(outcome: .completed, recovery: false, settled: true),
            requestedToolFamilies: []
        )

        XCTAssertEqual(
            ThreadTaskContractPresentation.phase(
                live: nil,
                snapshot: nil,
                checkpoint: checkpoint,
                connectionState: .idle,
                isPreparingSubmit: false,
                canResumeSavedTask: true,
                continuityRequiresRecovery: false
            ),
            "Paused locally — ready to resume"
        )
        XCTAssertEqual(
            ThreadTaskContractPresentation.phase(
                live: nil,
                snapshot: nil,
                checkpoint: checkpoint,
                connectionState: .idle,
                isPreparingSubmit: false,
                canResumeSavedTask: false,
                continuityRequiresRecovery: false
            ),
            "Saved checkpoint — no process running"
        )
    }

    func testTaskContractKeepsRecoveryAndPreDispatchSemanticsDistinct() {
        XCTAssertEqual(
            ThreadTaskContractPresentation.phase(
                live: nil,
                snapshot: nil,
                checkpoint: nil,
                connectionState: .starting,
                isPreparingSubmit: true,
                canResumeSavedTask: false,
                continuityRequiresRecovery: false
            ),
            "Preparing task — not dispatched"
        )
        XCTAssertEqual(
            ThreadTaskContractPresentation.phase(
                live: nil,
                snapshot: nil,
                checkpoint: nil,
                connectionState: .idle,
                isPreparingSubmit: false,
                canResumeSavedTask: false,
                continuityRequiresRecovery: true
            ),
            "Fresh thread required"
        )
    }

    func testTaskContractNamesOnlyExplicitRequestedToolFamilies() {
        let checkpoint = AssistantTurnCheckpoint(
            snapshot: snapshot(outcome: .completed, recovery: false, settled: true),
            requestedToolFamilies: ["grokbuild-browser", "zotero", "grokbuild-browser"]
        )

        XCTAssertEqual(
            ThreadTaskContractPresentation.requestedToolFamilies(current: [], checkpoint: checkpoint),
            ["Browser", "zotero"]
        )
        XCTAssertEqual(
            ThreadTaskContractPresentation.requestedToolFamilies(
                current: ["grokbuild-computer-use"],
                checkpoint: checkpoint
            ),
            ["Computer Use"]
        )
    }

    func testTaskContractRetainsExactParentChildHandoffIdentity() {
        let child = RunEvidenceSnapshot.Worker(
            id: "worker-row",
            title: "Verifier",
            status: "completed",
            childID: "child-backend-exact",
            durationMilliseconds: 40,
            toolCallCount: 0,
            redactedError: nil
        )
        let projection = live(workers: [child])
        let handoff = ThreadTaskContractPresentation.workerHandoffs(
            live: projection,
            snapshot: nil,
            checkpoint: nil
        ).first

        XCTAssertEqual(handoff?.parentBackendSessionID, "backend")
        XCTAssertEqual(handoff?.childBackendSessionID, "child-backend-exact")
        XCTAssertEqual(
            handoff?.displayText,
            "Parent backend → Child child-backend-exact · Completed"
        )
    }

    func testTaskCheckpointRoundTripsInsideAssistantTrace() throws {
        let checkpoint = AssistantTurnCheckpoint(
            snapshot: snapshot(outcome: .completed, recovery: false, settled: true),
            requestedToolFamilies: ["zotero"]
        )
        let trace = AssistantTurnTrace(
            reasoningSummaryChunks: [],
            thinkingDuration: nil,
            tools: [],
            checkpoint: checkpoint
        )
        let restored = try JSONDecoder().decode(
            AssistantTurnTrace.self,
            from: JSONEncoder().encode(trace)
        )

        XCTAssertEqual(restored.checkpoint, checkpoint)
        XCTAssertTrue(restored.hasContent)
        XCTAssertEqual(ThreadRunSpinePresentation.persistedPlan(restored.checkpoint).count, 1)
        XCTAssertEqual(ThreadRunSpinePresentation.persistedWorkers(restored.checkpoint).first?.runtimeModelID, "grok-4.5-build")
        XCTAssertEqual(ThreadRunSpinePresentation.persistedArtifacts(restored.checkpoint).first?.path, "/tmp/report.txt")
    }

    func testTaskHeaderUsesPersistedModelOnlyWhenNoProcessIsRunning() {
        let checkpoint = AssistantTurnCheckpoint(
            snapshot: snapshot(outcome: .completed, recovery: false, settled: true),
            requestedToolFamilies: []
        )
        XCTAssertEqual(
            ThreadTaskContractPresentation.modelReceipt(
                current: "No confirmed model",
                checkpoint: checkpoint,
                connectionState: .idle
            ),
            "grok-4.5 · saved checkpoint"
        )
        XCTAssertEqual(
            ThreadTaskContractPresentation.modelReceipt(
                current: "grok-4.5 · generation 3",
                checkpoint: checkpoint,
                connectionState: .ready
            ),
            "grok-4.5 · generation 3"
        )
    }

    private func live(
        plan: [RunEvidenceSnapshot.PlanStep] = [],
        workers: [RunEvidenceSnapshot.Worker] = [],
        tools: [RunEvidenceLiveProjection.Tool] = [],
        artifacts: [ChatStore.RunArtifact] = []
    ) -> RunEvidenceLiveProjection {
        RunEvidenceLiveProjection(
            binding: binding,
            goalSummary: "Acceptance",
            plan: plan,
            workers: workers,
            tools: tools,
            artifacts: artifacts,
            process: .init(state: "In progress — not settled", model: "grok-4.5", mcps: [])
        )
    }

    private func worker(id: String, stepID: String?, status: String) -> RunEvidenceSnapshot.Worker {
        .init(
            id: id,
            title: "Worker \(id)",
            status: status,
            owningPlanStepID: stepID,
            childID: id,
            durationMilliseconds: nil,
            toolCallCount: nil,
            redactedError: nil
        )
    }

    private func snapshot(
        outcome: ChatStore.TurnOutcome,
        recovery: Bool,
        settled: Bool
    ) -> RunEvidenceSnapshot {
        RunEvidenceSnapshot(
            binding: .init(
                localTabID: UUID(),
                workspaceID: UUID(),
                backendSessionID: "backend",
                processGeneration: 9,
                requestID: "prompt",
                isSettled: settled
            ),
            goalSummary: "Acceptance",
            plan: [.init(id: "verify", title: "Verify", status: "completed")],
            workers: [.init(
                id: "worker",
                title: "Verifier",
                status: "completed",
                owningPlanStepID: "verify",
                childID: "child",
                durationMilliseconds: 120,
                toolCallCount: 1,
                redactedError: nil,
                runtimeModelID: "grok-4.5-build",
                routedModel: "gpt-5.6-terra"
            )],
            tools: .init(succeeded: 0, failed: 0, cancelled: 0, unknown: 0),
            artifacts: [.init(
                toolCallID: "tool",
                path: "/tmp/report.txt",
                status: "Completed",
                location: .external,
                owningPlanStepID: "verify",
                workerID: nil
            )],
            gitReviewFiles: ["report.txt"],
            process: .init(state: "Settled", model: "grok-4.5", mcps: []),
            continuity: .init(
                status: recovery ? "diverged" : "verified",
                reason: recovery ? "review" : "matched",
                provenance: recovery ? "Continuity needs review" : "Verified continuity",
                requiresRecoveryAction: recovery
            ),
            usage: .init(totalTokens: 1, modelCalls: 1, turnCount: 1),
            outcome: outcome,
            unresolvedErrors: [],
            nextAction: recovery ? "Review recovery." : "No action."
        )
    }
}
