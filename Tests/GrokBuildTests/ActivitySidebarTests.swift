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
        XCTAssertEqual(presentation.compactText, "Using chrome-devtools · 0 active workers · List pages")
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
            "1.2 sec • 7 tools"
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
        XCTAssertTrue(sidebar.contains("Technical details"))
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
        XCTAssertTrue(chat.contains("Build agent finished. \\(outcome)."))
        XCTAssertEqual(chat.components(separatedBy: "Build agent finished").count - 1, 1)
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
