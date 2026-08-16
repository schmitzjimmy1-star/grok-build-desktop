import XCTest
@testable import GrokBuild

final class ActivitySidebarTests: XCTestCase {
    func testLiveWorkerCardDoesNotMountSelectableFixedReceiptText() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Views/ActivitySidebar.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "private func workerActivityCard("))
        let end = try XCTUnwrap(source.range(of: "private func subagentsSection(", range: start.upperBound..<source.endIndex))
        let card = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertFalse(card.contains(".textSelection(.enabled)"),
                       "streaming receipt text must not create a SelectionOverlay in the worker rail")
        XCTAssertFalse(card.contains(".fixedSize(horizontal: false, vertical: true)"),
                       "live receipt growth must not force unbounded vertical remeasurement")
        XCTAssertTrue(card.contains(".lineLimit(isLive ? 6 : 10)"),
                      "expanded technical receipts stay readable but layout-bounded")
    }

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

    func testDiscoveryMetadataNeverClaimsBrowserExecution() {
        let metadata = ActivitySidebarPresentation.liveToolMetadata(
            kind: "discovery",
            status: "Succeeded",
            mcpServerName: nil
        )

        XCTAssertEqual(metadata, "discovery • Succeeded")
        XCTAssertFalse(metadata.localizedCaseInsensitiveContains("using"))
        XCTAssertFalse(metadata.localizedCaseInsensitiveContains("browser"))
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
        let failed = makeSnapshot(
            outcome: .failed,
            unresolvedErrors: ["Provider rejected non-portable history"],
            nextAction: "Review the provider or CLI error before retrying."
        )

        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(missing),
            "The reply arrived, but the backend never confirmed the turn finished."
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(stopped),
            "You stopped this run before it finished."
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(failed),
            "The backend confirmed that this turn ended with an error."
        )
        XCTAssertFalse(missing.binding.isSettled)
        XCTAssertFalse(stopped.binding.isSettled)
        XCTAssertTrue(failed.binding.isSettled)
    }

    func testBackendCancellationNeverRendersAsCompletionOrUserStop() {
        let cancelled = makeSnapshot(outcome: .cancelled)

        XCTAssertEqual(cancelled.outcome.displayName, "Turn cancelled")
        XCTAssertEqual(
            ActivitySidebarPresentation.summaryDetail(cancelled),
            "The backend confirmed that this turn was cancelled before completion."
        )
        XCTAssertNotEqual(cancelled.outcome, .completed)
        XCTAssertNotEqual(cancelled.outcome, .userStopped)
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
        XCTAssertTrue(ActivitySidebarPresentation.workerNeedsReview(worker))
        XCTAssertEqual(ActivitySidebarPresentation.workerDisplayStatus(worker), "Needs Review")
        XCTAssertEqual(ActivitySidebarPresentation.workerStatusSummary([worker]), "1 needs review")
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

    func testWorkerStatusSummarySeparatesLiveCleanAndReviewStates() {
        let live = makeWorker(status: "running")
        let clean = RunEvidenceSnapshot.Worker(
            id: "clean",
            title: "Clean",
            status: "completed",
            childID: "child-clean",
            durationMilliseconds: 100,
            toolCallCount: 0,
            redactedError: nil,
            childToolReceipts: [],
            childLedgerReadOutcome: .empty
        )
        let failedReceipt = ChildToolReceipt(
            id: "child-tool-failed",
            title: "Read layout",
            status: .failed,
            mcpReceiptRole: nil,
            qualifiedToolName: nil,
            discoveredQualifiedToolNames: []
        )
        let review = RunEvidenceSnapshot.Worker(
            id: "review",
            title: "Review",
            status: "completed",
            childID: "child-review",
            durationMilliseconds: 100,
            toolCallCount: 1,
            redactedError: nil,
            childToolReceipts: [failedReceipt],
            childLedgerReadOutcome: .receipts
        )

        XCTAssertEqual(
            ActivitySidebarPresentation.workerStatusSummary([live, clean, review]),
            "1 live · 1 finished · 1 needs review"
        )
        XCTAssertEqual(ActivitySidebarPresentation.workerDisplayStatus(clean), "Completed")
        XCTAssertEqual(ActivitySidebarPresentation.workerDisplayStatus(review), "Needs Review")
    }

    func testChildLedgerPresentationDistinguishesUnreadableFromEmpty() {
        let unreadable = ActivitySidebarPresentation.workerReceiptDetail(
            status: "completed",
            durationMilliseconds: 100,
            toolCallCount: 0,
            redactedError: nil,
            childToolReceipts: nil,
            childLedgerReadOutcome: .unreadable
        )
        XCTAssertTrue(unreadable.contains("Child ledger unreadable"))
        XCTAssertFalse(unreadable.contains("not reported"))

        let empty = ActivitySidebarPresentation.workerReceiptDetail(
            status: "completed",
            durationMilliseconds: 100,
            toolCallCount: 0,
            redactedError: nil,
            childToolReceipts: [],
            childLedgerReadOutcome: .empty
        )
        XCTAssertTrue(empty.contains("Child ledger confirmed zero tools"))
        XCTAssertFalse(empty.contains("not reported"))
        XCTAssertFalse(empty.contains("unreadable"))
    }

    func testReconciledChildBrowserReceiptStaysAttributedInsideWorker() {
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
            title: "Inspect proof page",
            status: "completed",
            childID: "child",
            durationMilliseconds: 100,
            toolCallCount: 2,
            redactedError: nil,
            childToolReceipts: receipts
        )
        let snapshot = makeSnapshot(workers: [worker])
        let detail = ActivitySidebarPresentation.workerReceiptDetail(
            status: worker.status,
            durationMilliseconds: worker.durationMilliseconds,
            toolCallCount: worker.toolCallCount,
            redactedError: worker.redactedError,
            childToolReceipts: worker.childToolReceipts
        )

        XCTAssertEqual(snapshot.tools.total, 0, "child receipts must not become parent tools")
        XCTAssertEqual(snapshot.unresolvedWorkerCount, 0)
        XCTAssertTrue(detail.contains("Child receipts: 2/2 succeeded"))
        XCTAssertTrue(detail.contains("grokbuild-browser__browser_open_url succeeded via grokbuild-browser"))
        XCTAssertFalse(detail.contains("not reported"))
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
        XCTAssertTrue(sidebar.contains("Current turn · live receipts"))
        XCTAssertTrue(sidebar.contains("grok-live-worker-activity"))
        XCTAssertTrue(sidebar.contains("grok-settled-worker-activity"))
        XCTAssertTrue(sidebar.contains("grok-worker-activity-\\(worker.id)"))
        XCTAssertTrue(sidebar.contains("Parent request"))
        XCTAssertTrue(sidebar.contains("Current parent action:"))
        XCTAssertTrue(sidebar.contains("showsCurrentAction"))
        XCTAssertTrue(sidebar.contains("Label(\"Details\""))
        XCTAssertTrue(sidebar.contains("accessibilityLabel(\"Worker receipt\")"))
        XCTAssertFalse(sidebar.contains("Text(\"Assignment\")"))
        XCTAssertTrue(sidebar.contains("Live generation receipt; outcome and usage are not settled."))
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
        XCTAssertTrue(sidebar.contains("workerDelegationRow"))
        XCTAssertTrue(sidebar.contains("grok-run-inspector-worker-\\(worker.id)"))
        XCTAssertTrue(sidebar.contains("MCP evidence"))
        XCTAssertTrue(sidebar.contains("Unavailable for this turn") == false,
                      "the unavailable copy is owned by the typed projection, not hard-coded outcome prose")
        XCTAssertTrue(sidebar.contains(".accessibilityElement(children: .contain)"))
        XCTAssertFalse(sidebar.contains(".regularMaterial"))
        XCTAssertTrue(chat.contains("accessibilityLabel(\"Run inspector\")"))
        XCTAssertTrue(chat.contains("RunInspectorQuickLook"))
        XCTAssertTrue(chat.contains("grok-live-progress"))
        XCTAssertTrue(chat.contains("LiveProgressPresentation.make"))
        XCTAssertTrue(chat.contains("outcome == .completionReceiptMissing"))
        XCTAssertTrue(chat.contains(".userStopped"))
        XCTAssertTrue(chat.contains("local stop outcome and next action"))
        XCTAssertTrue(chat.contains("Run inspector opened with the preserved run evidence"))
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
                isSettled: outcome == .completed || outcome == .failed || outcome == .cancelled
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

    func testCoordinationMetricsRenderOnlyAuthoritativeReportedFields() {
        let metrics = RunEvidenceSnapshot.CoordinationMetrics(
            requestedChildCount: 2,
            spawnedChildCount: 2,
            finishedChildCount: 1,
            maximumUsefulConcurrency: 2,
            childToolCallCount: 3,
            unresolvedIdentityCount: 1,
            stopToSettleMilliseconds: 275,
            parentTotalTokens: 20_000,
            childTotalTokens: 8_000
        )

        XCTAssertEqual(
            ActivitySidebarPresentation.coordinationSummary(metrics),
            "2 requested • 2 spawned • 1 finished • max 2 concurrent"
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.coordinationUsage(metrics),
            "20,000 parent tokens • 8,000 child tokens • 3 child tool calls"
        )
    }

    func testWorkerReceiptDetailIncludesTokensTurnsAndSpawnCorrelation() {
        let detail = ActivitySidebarPresentation.workerReceiptDetail(
            status: "completed",
            durationMilliseconds: 1_500,
            toolCallCount: 2,
            redactedError: nil,
            tokenCount: 8_796,
            turns: 1,
            spawnToolCallID: "spawn-tokens",
            childID: "child-tokens"
        )
        XCTAssertTrue(detail.contains("Spawn tool spawn-tokens → child child-tokens"))
        XCTAssertTrue(detail.contains("8,796 tokens"))
        XCTAssertTrue(detail.contains("1 turn"))
        XCTAssertTrue(detail.contains("1.5 sec"))
        XCTAssertTrue(detail.contains("2 tools"))
    }

    func testWorkerReceiptDetailOmitsNilTokensTurnsAndSpawnWithoutChild() {
        let detail = ActivitySidebarPresentation.workerReceiptDetail(
            status: "running",
            durationMilliseconds: nil,
            toolCallCount: nil,
            redactedError: nil,
            tokenCount: nil,
            turns: nil,
            spawnToolCallID: "spawn-only",
            childID: nil
        )
        XCTAssertFalse(detail.contains("tokens"))
        XCTAssertFalse(detail.contains("turn"))
        XCTAssertFalse(detail.contains("Spawn tool"))
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
        let composer = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatComposer.swift"),
            encoding: .utf8
        )
        let chrome = chat + "\n" + composer
        XCTAssertTrue(chat.contains("addCursorRect(bounds, cursor: .iBeam)"))
        XCTAssertTrue(composer.contains(".overlay(ComposerCursorRegion())"))
        XCTAssertTrue(chrome.contains("window?.invalidateCursorRects(for: self)"))
        XCTAssertTrue(chrome.contains(".cursorUpdate"))
        XCTAssertTrue(chrome.contains("NSCursor.iBeam.set()"))
        XCTAssertTrue(chrome.contains("NSCursor.arrow.set()"))
        XCTAssertFalse(chrome.contains("NSCursor.iBeam.push()"))
        XCTAssertFalse(chrome.contains("NSCursor.pop()"))
    }
}
