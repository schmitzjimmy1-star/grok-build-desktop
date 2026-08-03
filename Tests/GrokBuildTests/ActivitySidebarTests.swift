import XCTest
@testable import GrokBuild

final class ActivitySidebarTests: XCTestCase {
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
            "Unknown — status not reported"
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.activityStatus("orphaned"),
            "Orphaned — terminal status not reported"
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

        XCTAssertTrue(sidebar.contains("Authoritative run evidence"))
        XCTAssertTrue(sidebar.contains("Current receipts — not settled"))
        XCTAssertTrue(sidebar.contains("evidencePhaseBadge(\"Live\""))
        XCTAssertTrue(sidebar.contains("evidencePhaseBadge(\"Settled\""))
        XCTAssertTrue(sidebar.contains("Outcomes and usage are not settled"))
        XCTAssertLessThan(
            try XCTUnwrap(sidebar.range(of: "if let snapshot")).lowerBound,
            try XCTUnwrap(sidebar.range(of: "else if let liveProjection")).lowerBound
        )
        XCTAssertTrue(sidebar.contains("snapshot.outcome.displayName"))
        XCTAssertTrue(sidebar.contains("Execution receipts"))
        XCTAssertTrue(sidebar.contains("workerAccessibilityLabel"))
        XCTAssertTrue(sidebar.contains(".accessibilityElement(children: .ignore)"))
        XCTAssertFalse(sidebar.contains(".regularMaterial"))
        XCTAssertTrue(chat.contains("Text(\"Activity\")"))
        XCTAssertTrue(chat.contains("outcome == .completionReceiptMissing"))
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
