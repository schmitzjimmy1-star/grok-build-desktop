import Foundation
import XCTest
@testable import GrokBuild

/// Slice 1 (agentic roadmap): the sidebar Activity lane is a pure, bounded projection over
/// per-session mirrors — running work first, plain-language statuses, stable per-session ids.
final class SidebarActivityTests: XCTestCase {
    private let sessionA = UUID()
    private let sessionB = UUID()

    private func input(
        _ id: UUID,
        title: String,
        background: [BackgroundActivity] = [],
        scheduled: [ScheduledTask] = [],
        workflows: [WorkflowRun] = []
    ) -> SidebarActivityProjection.SessionInput {
        SidebarActivityProjection.SessionInput(
            sessionID: id,
            sessionTitle: title,
            backgroundActivities: background,
            scheduledTasks: scheduled,
            workflowRuns: workflows
        )
    }

    func testRunningSortsBeforeScheduledBeforeFinishedAndCapsWithOverflow() {
        let background: [BackgroundActivity] = [
            BackgroundActivity(id: "done-1", kind: .backgroundCommand, title: "old build", status: "done"),
            BackgroundActivity(id: "live-1", kind: .subagent, title: "researcher", status: "running"),
            BackgroundActivity(id: "fail-1", kind: .monitor, title: "watcher", status: "failed: boom"),
        ]
        let scheduled = [
            ScheduledTask(id: "s1", prompt: "check CI", intervalHuman: "5m", nextFireAt: nil, recurring: true)
        ]
        let workflows = [
            WorkflowRun(id: "w1", name: "audit", phase: "Verify", status: "running", progress: "3/5"),
        ]
        let lane = SidebarActivityProjection.lane(
            from: [input(sessionA, title: "Alpha", background: background, scheduled: scheduled, workflows: workflows)],
            limit: 3
        )

        XCTAssertEqual(lane.entries.count, 3)
        XCTAssertEqual(lane.overflowCount, 2)
        // Running rows survive the cap; finished rows are what overflow drops.
        XCTAssertTrue(lane.entries[0].isRunning)
        XCTAssertTrue(lane.entries[1].isRunning)
        XCTAssertEqual(lane.entries[2].kind, .scheduled)
        XCTAssertFalse(lane.entries.contains { $0.id.contains("done-1") || $0.id.contains("fail-1") })
    }

    func testPlainLanguageStatusLabels() {
        let background: [BackgroundActivity] = [
            BackgroundActivity(id: "a", kind: .subagent, title: "worker", status: "completed"),
            BackgroundActivity(id: "b", kind: .subagent, title: "worker", status: "failed: exit 1"),
            BackgroundActivity(id: "c", kind: .subagent, title: "worker", status: "cancelled"),
            BackgroundActivity(id: "d", kind: .subagent, title: "worker", status: "orphaned"),
            BackgroundActivity(id: "e", kind: .backgroundCommand, title: "npm test", status: "running"),
        ]
        let lane = SidebarActivityProjection.lane(
            from: [input(sessionA, title: "Alpha", background: background)],
            limit: 10
        )
        let byID = Dictionary(uniqueKeysWithValues: lane.entries.map { ($0.id, $0.statusLabel) })
        XCTAssertEqual(byID["\(sessionA.uuidString)/background/a"], "Done")
        XCTAssertEqual(byID["\(sessionA.uuidString)/background/b"], "Failed")
        XCTAssertEqual(byID["\(sessionA.uuidString)/background/c"], "Stopped")
        XCTAssertEqual(byID["\(sessionA.uuidString)/background/d"], "No final report")
        XCTAssertEqual(byID["\(sessionA.uuidString)/background/e"], "Running")
    }

    func testWorkflowPausedIsNotRunningAndPhaseNamesRunningStatus() {
        let workflows = [
            WorkflowRun(id: "p", name: "sweep", phase: "Find", status: "paused", progress: ""),
            WorkflowRun(id: "r", name: "sweep2", phase: "Verify", status: "running", progress: ""),
        ]
        let lane = SidebarActivityProjection.lane(
            from: [input(sessionA, title: "Alpha", workflows: workflows)],
            limit: 10
        )
        let paused = lane.entries.first { $0.id.hasSuffix("/workflow/p") }
        let running = lane.entries.first { $0.id.hasSuffix("/workflow/r") }
        XCTAssertEqual(paused?.statusLabel, "Paused")
        XCTAssertEqual(paused?.isRunning, false)
        XCTAssertEqual(running?.statusLabel, "Verify")
        XCTAssertEqual(running?.isRunning, true)
    }

    func testScheduledTaskDedupAcrossSchedulerMirrorAndBackgroundRow() {
        let task = ScheduledTask(id: "t1", prompt: "loop", intervalHuman: "10m", nextFireAt: nil, recurring: true)
        let background = [
            BackgroundActivity(id: "bg-t1", kind: .scheduled, title: "loop", scheduledTask: task)
        ]
        let lane = SidebarActivityProjection.lane(
            from: [input(sessionA, title: "Alpha", background: background, scheduled: [task])],
            limit: 10
        )
        XCTAssertEqual(lane.entries.filter { $0.kind == .scheduled }.count, 1)
        XCTAssertEqual(lane.entries.first?.statusLabel, "Every 10m")
    }

    func testSameActivityIDInTwoSessionsCannotCollide() {
        let activity = BackgroundActivity(id: "shared", kind: .subagent, title: "worker", status: "running")
        let lane = SidebarActivityProjection.lane(
            from: [
                input(sessionA, title: "Alpha", background: [activity]),
                input(sessionB, title: "Beta", background: [activity]),
            ],
            limit: 10
        )
        XCTAssertEqual(lane.entries.count, 2)
        XCTAssertEqual(Set(lane.entries.map(\.id)).count, 2)
        XCTAssertEqual(Set(lane.entries.map(\.sessionID)), [sessionA, sessionB])
    }

    func testEmptySessionsProduceAnEmptyLaneSoTheSectionStaysHidden() {
        let lane = SidebarActivityProjection.lane(from: [input(sessionA, title: "Alpha")])
        XCTAssertTrue(lane.isEmpty)
        XCTAssertEqual(lane.overflowCount, 0)
    }

    /// Agentic roadmap Slice 3: live tool metadata carries kind, status, and authoritative
    /// MCP attribution — and never invents a "via" segment without a server receipt.
    func testLiveToolMetadataFormatsKindStatusAndMCPAttribution() {
        XCTAssertEqual(
            ActivitySidebarPresentation.liveToolMetadata(kind: "execute", status: "Running", mcpServerName: "chrome-devtools"),
            "execute • Running • via chrome-devtools"
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.liveToolMetadata(kind: "other", status: "Done", mcpServerName: nil),
            "Done"
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.liveToolMetadata(kind: "", status: "Failed", mcpServerName: "  "),
            "Failed",
            "a blank server name must not fabricate attribution"
        )
        XCTAssertEqual(
            ActivitySidebarPresentation.liveToolMetadata(kind: "read", status: "Done", mcpServerName: nil),
            "read • Done"
        )
    }

    /// Agentic roadmap Slices 3+4 source contracts: the live tool inspector expands the
    /// full redacted receipt, live workers surface mid-turn receipts, and the sidebar
    /// Connections lane toggles prompt attachments without writing any configuration.
    func testDelegationInspectorAndConnectionsWiring() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let activitySource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ActivitySidebar.swift"),
            encoding: .utf8
        )
        let liveToolsStart = try XCTUnwrap(activitySource.range(of: "private func liveTools"))
        let liveToolsEnd = try XCTUnwrap(
            activitySource.range(of: "private func liveRunDetails", range: liveToolsStart.upperBound..<activitySource.endIndex)
        )
        let liveTools = String(activitySource[liveToolsStart.lowerBound..<liveToolsEnd.lowerBound])
        XCTAssertTrue(liveTools.contains("DisclosureGroup"),
                      "tool rows must expand to a full receipt, not truncate at 180 characters")
        XCTAssertTrue(liveTools.contains("MCP server: \\(server)"),
                      "the expanded receipt must show authoritative MCP attribution")

        let liveWorkersStart = try XCTUnwrap(activitySource.range(of: "private func liveWorkers"))
        let liveWorkersEnd = try XCTUnwrap(
            activitySource.range(of: "private func liveTools", range: liveWorkersStart.upperBound..<activitySource.endIndex)
        )
        let liveWorkers = String(activitySource[liveWorkersStart.lowerBound..<liveWorkersEnd.lowerBound])
        XCTAssertTrue(liveWorkers.contains("workerReceiptDetail"),
                      "a worker that finished mid-turn must show its receipt live")

        let sidebarSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SidebarView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(sidebarSource.contains("ConnectionSidebarRow("),
                      "Connections lane rows render through the dedicated component")
        XCTAssertTrue(sidebarSource.contains("Label(\"Connections\", systemImage: \"network\")"))
        XCTAssertTrue(sidebarSource.contains("if !connections.isEmpty {"),
                      "an empty inventory must hide the Connections section")

        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(contentSource.contains("activeStore.togglePromptMCPAttachment(named: name)"),
                      "toggling reuses the existing per-tab attachment machinery — no config writes")
        XCTAssertTrue(contentSource.contains("connections: activeStore.promptMCPOptions"))
        XCTAssertTrue(contentSource.contains("onManageConnections: { openSettings(tab: .mcpServers) }"))
    }

    /// Source contract: the lane renders in the sidebar, navigates to the owning session,
    /// and ContentView builds it from the live stores' observed mirrors only.
    func testSidebarAndContentViewWiring() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebarSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SidebarView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(sidebarSource.contains("if !activityLane.isEmpty {"),
                      "empty lane must hide the section entirely")
        XCTAssertTrue(sidebarSource.contains("SidebarActivityRow(entry: entry)"),
                      "lane rows render through the dedicated row component")

        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(contentSource.contains("activityLane: sidebarActivityLane"),
                      "ContentView must pass the projected lane to the sidebar")
        XCTAssertTrue(contentSource.contains("selectSession(entry.sessionID)"),
                      "activating a lane row navigates to the owning session")
    }
}
