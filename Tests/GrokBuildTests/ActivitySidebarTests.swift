import XCTest
@testable import GrokBuild

final class ActivitySidebarTests: XCTestCase {
    func testLiveProgressProjectsExistingReceiptsWithoutUsageOrBudgetCopy() {
        let projection = RunEvidenceLiveProjection(
            binding: .init(
                localTabID: UUID(),
                workspaceID: UUID(),
                backendSessionID: "backend-1",
                processGeneration: 4
            ),
            goalSummary: "Build it",
            plan: [],
            workers: [
                .init(
                    id: "worker-1",
                    title: "UI lane",
                    status: "running",
                    childID: nil,
                    durationMilliseconds: nil,
                    toolCallCount: nil,
                    redactedError: nil
                )
            ],
            tools: [
                .init(
                    id: "tool-1",
                    title: "Read workspace",
                    kind: "read",
                    status: "Running",
                    detail: nil,
                    isActive: true
                )
            ],
            artifacts: [],
            process: .init(state: "In progress — not settled", model: "grok-4.5", mcps: [])
        )
        let start = Date(timeIntervalSince1970: 1_000)
        let presentation = LiveProgressPresentation.make(
            projection: projection,
            startedAt: start,
            now: start.addingTimeInterval(12.8),
            hasAssistantText: false
        )

        XCTAssertEqual(presentation.phase, "Using tools")
        XCTAssertEqual(presentation.activeWorkers, 1)
        XCTAssertEqual(presentation.activeTool, "Read workspace")
        XCTAssertEqual(presentation.elapsedSeconds, 12)
        XCTAssertEqual(
            presentation.compactText,
            "Using tools · 1 active worker · Read workspace · 12s elapsed"
        )
        XCTAssertFalse(presentation.compactText.localizedCaseInsensitiveContains("budget"))
        XCTAssertFalse(presentation.compactText.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(presentation.compactText.localizedCaseInsensitiveContains("usage"))
    }

    func testLiveProgressNamesMCPOnlyFromItsToolReceipt() {
        let projection = RunEvidenceLiveProjection(
            binding: .init(
                localTabID: UUID(),
                workspaceID: UUID(),
                backendSessionID: "backend-mcp",
                processGeneration: 7
            ),
            goalSummary: nil,
            plan: [],
            workers: [],
            tools: [
                .init(
                    id: "mcp-tool",
                    title: "List pages",
                    kind: "read",
                    status: "Running",
                    detail: nil,
                    mcpServerName: "chrome-devtools",
                    isActive: true
                )
            ],
            artifacts: [],
            process: .init(state: "In progress — not settled", model: "gpt-5.6-terra", mcps: [])
        )
        let presentation = LiveProgressPresentation.make(
            projection: projection,
            startedAt: nil,
            now: Date(),
            hasAssistantText: false
        )

        XCTAssertEqual(presentation.phase, "Using chrome-devtools")
        XCTAssertEqual(presentation.activeMCP, "chrome-devtools")
        XCTAssertEqual(presentation.activeTool, "List pages")
        XCTAssertEqual(presentation.compactText, "Using chrome-devtools · List pages")
    }

    func testLiveProgressPhaseTracksWritingAndWorkerCoordination() {
        let binding = RunEvidenceLiveProjection.Binding(
            localTabID: UUID(),
            workspaceID: nil,
            backendSessionID: "backend-2",
            processGeneration: 5
        )
        let process = RunEvidenceSnapshot.ProcessReceipt(
            state: "In progress — not settled",
            model: nil,
            mcps: []
        )
        let writing = RunEvidenceLiveProjection(
            binding: binding,
            goalSummary: nil,
            plan: [],
            workers: [],
            tools: [],
            artifacts: [],
            process: process
        )
        XCTAssertEqual(
            LiveProgressPresentation.make(
                projection: writing,
                startedAt: nil,
                now: Date(),
                hasAssistantText: true
            ).phase,
            "Writing answer"
        )

        let workers = RunEvidenceLiveProjection(
            binding: binding,
            goalSummary: nil,
            plan: [],
            workers: [
                .init(
                    id: "worker-2",
                    title: "Research lane",
                    status: "in_progress",
                    childID: nil,
                    durationMilliseconds: nil,
                    toolCallCount: nil,
                    redactedError: nil
                )
            ],
            tools: [],
            artifacts: [],
            process: process
        )
        XCTAssertEqual(
            LiveProgressPresentation.make(
                projection: workers,
                startedAt: nil,
                now: Date(),
                hasAssistantText: false
            ).phase,
            "Coordinating workers"
        )
    }

    func testTranscriptNormalizationPreservesMarkdownLinesButRemovesTransportNoise() {
        XCTAssertEqual(
            TranscriptTextPresentation.normalize("one\r\ntwo\u{00A0}three\u{200B}"),
            "one\ntwo three"
        )
        XCTAssertEqual(
            TranscriptTextPresentation.singleLine("one\n\t two", maxLength: 40),
            "one two"
        )
    }

    func testSubagentActivityLabelsUseReadableLaneNames() {
        let education = BackgroundActivity(
            id: "education",
            kind: .subagent,
            title: "Research this question: PUBLIC EDUCATION",
            detail: "Research this question thoroughly using web_search"
        )
        XCTAssertEqual(ActivitySidebarPresentation.activityTitle(education), "Public education lane")
        XCTAssertEqual(ActivitySidebarPresentation.activityDetail(education), "Research lane: public education")
        XCTAssertEqual(ActivitySidebarPresentation.activityStatus("in_progress"), "In Progress")
    }

    func testUniqueFilePathsPreservesFirstOccurrenceAndDropsBlankEntries() {
        XCTAssertEqual(
            ActivitySidebarPresentation.uniqueFilePaths([
                "Sources/App.swift",
                " ",
                "Sources/App.swift",
                "Tests/AppTests.swift"
            ]),
            ["Sources/App.swift", "Tests/AppTests.swift"]
        )
    }

    func testDisplayPathShortensAbsoluteWorkspacePaths() {
        let workspace = URL(fileURLWithPath: "/tmp/grok-build")
        XCTAssertEqual(
            ActivitySidebarPresentation.displayPath(
                "/tmp/grok-build/Sources/App.swift",
                relativeTo: workspace
            ),
            "Sources/App.swift"
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.displayPath("/tmp/other.swift", relativeTo: workspace),
            "/tmp/other.swift"
        )
    }

    func testArtifactPresentationKeepsWorkspaceAndExternalEvidenceExplicit() {
        let workspaceArtifact = ChatStore.RunArtifact(
            toolCallID: "write-1",
            path: "/tmp/grok-build/evidence.md",
            status: "Completed",
            location: .workspace
        )
        let externalArtifact = ChatStore.RunArtifact(
            toolCallID: "write-2",
            path: "/tmp/outside/evidence.md",
            status: "Completed",
            location: .external
        )

        XCTAssertEqual(
            ActivitySidebarPresentation.artifactLocationLabel(workspaceArtifact),
            "Workspace artifact"
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.artifactLocationLabel(externalArtifact),
            "External artifact"
        )
    }

    func testActiveStatusKeepsRunningAndUnknownWorkersVisible() {
        XCTAssertTrue(ActivitySidebarPresentation.isActiveStatus("running"))
        XCTAssertTrue(ActivitySidebarPresentation.isActiveStatus(""))
        XCTAssertFalse(ActivitySidebarPresentation.isActiveStatus("done"))
        XCTAssertFalse(ActivitySidebarPresentation.isActiveStatus("completed successfully"))
        XCTAssertFalse(ActivitySidebarPresentation.isActiveStatus("failed: timeout"))
        XCTAssertFalse(ActivitySidebarPresentation.isActiveStatus("unknown"))
        XCTAssertFalse(ActivitySidebarPresentation.isActiveStatus("orphaned"))
    }

    func testWorkerReceiptPresentationKeepsUnknownAndOrphanedTruthful() {
        let completed = BackgroundActivity(
            id: "worker-1",
            kind: .subagent,
            title: "Education lane",
            status: "completed",
            durationMilliseconds: 1_234,
            toolCallCount: 7
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.workerReceiptDetail(completed),
            "1.2 sec • 7 tools • Child tool outcomes were not reported to the parent receipt"
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.activityStatus("unknown"),
            "No final report"
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.activityStatus("orphaned"),
            "No final report (orphaned)"
        )
    }

    func testCompletedDiscoveryWithAdmittedUnmetRequestUsesLifecycleOnlyCopy() {
        let snapshot = makeSnapshot(
            goalSummary: "Use a browser capability that is unavailable",
            tools: .init(succeeded: 1, failed: 0, cancelled: 0, unknown: 0)
        )

        let summary = ActivitySidebarPresentation.summaryDetail(snapshot)

        XCTAssertEqual(summary, "Turn completed; no tool or worker failures were reported.")
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("checked out"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("request succeeded"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("goal"))
    }

    func testTerminalFailureStaysUnresolvedAfterParentCompletion() {
        let snapshot = makeSnapshot(
            tools: .init(succeeded: 0, failed: 1, cancelled: 0, unknown: 0),
            unresolvedErrors: ["Terminal exited with status 1"],
            nextAction: "Review unresolved tool or worker errors."
        )

        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(snapshot),
            "Turn completed with 1 unresolved error."
        )
        XCTAssertEqual(snapshot.tools.failed, 1)
        XCTAssertEqual(snapshot.unresolvedErrors, ["Terminal exited with status 1"])
        XCTAssertEqual(snapshot.nextAction, "Review unresolved tool or worker errors.")
    }

    func testMissingReceiptAndUserStopRemainDistinctFromCompletion() {
        let missing = makeSnapshot(outcome: .completionReceiptMissing)
        let stopped = makeSnapshot(outcome: .userStopped)

        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(missing),
            "The reply arrived, but the backend never confirmed the turn finished."
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(stopped),
            "You stopped this run before it finished."
        )
        XCTAssertFalse(missing.binding.isSettled)
        XCTAssertFalse(stopped.binding.isSettled)
    }

    func testActiveUnknownAndOrphanedWorkersCannotRenderCleanCompletion() {
        let active = makeSnapshot(workers: [makeWorker(status: "running")])
        let unknown = makeSnapshot(
            workers: [makeWorker(status: "unknown")],
            nextAction: "Review unresolved worker receipts."
        )
        let orphaned = makeSnapshot(
            workers: [makeWorker(status: "orphaned")],
            nextAction: "Review unresolved worker receipts."
        )

        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(active),
            "Turn completed; 1 worker is still active."
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(unknown),
            "Turn completed; 1 worker receipt remains unresolved."
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(orphaned),
            "Turn completed; 1 worker receipt remains unresolved."
        )
        XCTAssertEqual(unknown.unresolvedWorkerCount, 1)
        XCTAssertEqual(orphaned.unresolvedWorkerCount, 1)
    }

    func testCompletedWorkerWithChildToolsKeepsOutcomeUnresolved() {
        let worker = RunEvidenceSnapshot.Worker(
            id: "worker-1",
            title: "Run false",
            status: "completed",
            childID: "child-1",
            durationMilliseconds: 100,
            toolCallCount: 1,
            redactedError: nil
        )
        let snapshot = makeSnapshot(workers: [worker])

        XCTAssertTrue(worker.isCompleted)
        XCTAssertTrue(worker.hasUnresolvedChildToolOutcome)
        XCTAssertTrue(worker.isUnresolved)
        XCTAssertEqual(snapshot.unresolvedWorkerCount, 1)
        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(snapshot),
            "Turn completed; 1 worker receipt remains unresolved."
        )
        XCTAssertTrue(
            ActivitySidebarPresentation.workerReceiptDetail(
                status: worker.status,
                durationMilliseconds: worker.durationMilliseconds,
                toolCallCount: worker.toolCallCount,
                redactedError: worker.redactedError
            ).contains("Child tool outcomes were not reported to the parent receipt")
        )
    }

    func testActivityWorkbenchUsesOutcomeFirstNativeEvidenceChrome() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebar = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ActivitySidebar.swift"),
            encoding: .utf8
        )
        let chat = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sidebar.contains("What the agent did"))
        XCTAssertTrue(sidebar.contains("Happening now — not final"))
        XCTAssertTrue(sidebar.contains("evidencePhaseBadge(\"Live\""))
        XCTAssertTrue(sidebar.contains("evidencePhaseBadge(\"Finished\""))
        XCTAssertTrue(sidebar.contains("Outcomes and usage are not settled"))
        XCTAssertLessThan(
            try XCTUnwrap(sidebar.range(of: "if let snapshot")).lowerBound,
            try XCTUnwrap(sidebar.range(of: "else if let liveProjection")).lowerBound
        )
        XCTAssertTrue(sidebar.contains("snapshot.outcome.displayName"))
        // Codex parity Slice 5: the deep receipts live behind one Run details
        // disclosure in the compact inspector.
        XCTAssertTrue(sidebar.contains("Label(\"Run details\", systemImage: \"list.bullet.rectangle\")"))
        XCTAssertTrue(sidebar.contains("workerAccessibilityLabel"))
        XCTAssertTrue(sidebar.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertFalse(sidebar.contains(".regularMaterial"))
        XCTAssertTrue(chat.contains("Text(\"Activity\")"))
        XCTAssertTrue(chat.contains("grok-live-progress"))
        XCTAssertTrue(chat.contains("LiveProgressPresentation.make"))
        XCTAssertTrue(chat.contains("outcome == .completionReceiptMissing"))
        XCTAssertTrue(chat.contains(".userStopped"))
        XCTAssertTrue(chat.contains("local stop outcome and next action"))
        XCTAssertTrue(chat.contains("Activity opened with the preserved run evidence"))
        XCTAssertTrue(chat.contains("Turn finished. \\(outcome)."))
        XCTAssertEqual(chat.components(separatedBy: "Turn finished").count - 1, 1)
    }

    private func makeSnapshot(
        outcome: ChatStore.TurnOutcome = .completed,
        goalSummary: String? = nil,
        workers: [RunEvidenceSnapshot.Worker] = [],
        tools: RunEvidenceSnapshot.ToolSummary = .init(
            succeeded: 0,
            failed: 0,
            cancelled: 0,
            unknown: 0
        ),
        unresolvedErrors: [String] = [],
        nextAction: String = "The agent reported no next action."
    ) -> RunEvidenceSnapshot {
        RunEvidenceSnapshot(
            binding: .init(
                localTabID: UUID(),
                workspaceID: UUID(),
                backendSessionID: "backend",
                processGeneration: 1,
                requestID: "prompt",
                isSettled: outcome == .completed
            ),
            goalSummary: goalSummary,
            plan: [],
            workers: workers,
            tools: tools,
            artifacts: [],
            gitReviewFiles: [],
            process: .init(state: "Settled", model: "grok-4.5", mcps: []),
            continuity: .init(
                status: "backendBound",
                reason: "freshBackendBound",
                provenance: "Fresh backend bound",
                requiresRecoveryAction: false
            ),
            usage: .init(totalTokens: 100, modelCalls: 1, turnCount: 1),
            outcome: outcome,
            unresolvedErrors: unresolvedErrors,
            nextAction: nextAction
        )
    }

    private func makeWorker(status: String) -> RunEvidenceSnapshot.Worker {
        .init(
            id: "worker-\(status)",
            title: "Worker",
            status: status,
            childID: status == "orphaned" ? "child-1" : nil,
            durationMilliseconds: nil,
            toolCallCount: nil,
            redactedError: nil
        )
    }

    @MainActor
    func testComposerCursorRegionOwnsOnlyTheEditorWithoutInterceptingClicks() throws {
        let cursorView = ComposerCursorRectView(frame: NSRect(x: 0, y: 0, width: 320, height: 44))
        cursorView.resetCursorRects()
        XCTAssertNil(cursorView.hitTest(NSPoint(x: 12, y: 12)))

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chat = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chat.contains("addCursorRect(bounds, cursor: .iBeam)"))
        XCTAssertTrue(chat.contains(".overlay(ComposerCursorRegion())"))
        XCTAssertTrue(chat.contains("window?.invalidateCursorRects(for: self)"))
        XCTAssertTrue(chat.contains(".cursorUpdate"))
        XCTAssertTrue(chat.contains("NSCursor.iBeam.set()"))
        XCTAssertTrue(chat.contains("NSCursor.arrow.set()"))
        XCTAssertFalse(chat.contains("NSCursor.iBeam.push()"))
        XCTAssertFalse(chat.contains("NSCursor.pop()"))
    }
}
