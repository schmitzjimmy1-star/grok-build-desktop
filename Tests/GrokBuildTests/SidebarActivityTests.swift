import Foundation
import XCTest
@testable import GrokBuild

/// Activity presentation helpers plus the sidebar/inspector source contracts.
/// (The former sidebar Activity lane projection was deleted in Codex parity Slice 6.)
final class SidebarActivityTests: XCTestCase {
    // The pure SidebarActivityProjection lane cases were removed with the
    // projection itself in Codex parity Slice 6 (zero remaining consumers).

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

    /// Agentic roadmap Slice 3 + Codex parity Slice 1 source contracts: the live tool
    /// inspector still expands the full redacted receipt and live workers still surface
    /// mid-turn receipts, while the sidebar no longer renders a Connections lane — MCP
    /// attachment stays reachable from the composer without any configuration writes.
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
        XCTAssertTrue(liveWorkers.contains("workerDelegationRow"),
                      "live workers share the expandable delegation row, including mid-turn receipts")
        XCTAssertTrue(activitySource.contains("func workerDelegationRow"),
                      "delegation rows own spawn/child/token receipts for live and settled workers")
        XCTAssertTrue(activitySource.contains("grok-run-inspector-worker-\\(worker.id)"))

        let sidebarSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SidebarView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(sidebarSource.contains("ConnectionSidebarRow"),
                       "Codex parity Slice 1: the sidebar renders no Connections lane")
        XCTAssertFalse(sidebarSource.contains("Label(\"Connections\""),
                       "Codex parity Slice 1: the sidebar renders no Connections section header")

        // The capability the lane exposed remains reachable from the composer.
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatSource.contains("grok-composer-add-menu"),
                      "the composer add/context menu remains the visible MCP attachment surface (Slice 4 home)")
        XCTAssertTrue(chatSource.contains("togglePromptMCPAttachment"),
                      "attachment toggling stays wired from the composer")
        let storeSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(storeSource.contains("func togglePromptMCPAttachment(named name: String)"),
                      "per-tab attachment machinery survives the sidebar removal — no config writes")
    }

    /// Codex parity Slice 1 source contract: the sidebar is navigation-only. The
    /// Activity lane, Agents hub, and primary Activity/Workflows rows are gone; the
    /// header bell remains the activity entry point, and the lane projection models
    /// stay for their remaining consumers until Slice 6 decides ownership.
    func testSidebarAndContentViewWiring() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sidebarSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SidebarView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(sidebarSource.contains("SidebarActivityRow"),
                       "Codex parity Slice 1: the sidebar renders no Activity lane rows")
        XCTAssertFalse(sidebarSource.contains("Label(\"Activity\""),
                       "Codex parity Slice 1: the sidebar renders no Activity section header")
        XCTAssertFalse(sidebarSource.contains("CodexRailButton(title: \"Activity\""),
                       "Activity is not a large primary rail row; the bell owns it")
        XCTAssertFalse(sidebarSource.contains("CodexRailButton(title: \"Workflows\""),
                       "Workflows is not a primary rail row; Settings and the composer command menu own it")
        let topBar = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatTopBar.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(topBar.contains("TitlebarGlyph(systemName: \"bell\")"),
                       "F2 moves activity out of the conversation header")
        XCTAssertTrue(sidebarSource.contains("Image(systemName: \"bell\")"),
                      "the persistent rail owns the one dashboard bell")
        XCTAssertTrue(sidebarSource.contains("accessibilityRemoveTraits"),
                      "action rail and inactive persistent rows must remove false selection")
        XCTAssertTrue(sidebarSource.contains("accessibilityAddTraits(isSelected ? .isSelected : [])"),
                      "the real selected session row must expose its visual selection in AX")
        XCTAssertTrue(sidebarSource.contains("List(selection: persistentSelection)"),
                      "native sidebar rows must receive the route-aware persistent selection")

        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(contentSource.contains("activityLane:"),
                       "ContentView no longer feeds an operational lane into the sidebar")
        XCTAssertFalse(contentSource.contains("agentEntries:"),
                       "ContentView no longer feeds agent hub entries into the sidebar")
        XCTAssertFalse(contentSource.contains("connections: activeStore.promptMCPOptions"),
                       "ContentView no longer feeds MCP connections into the sidebar")
        XCTAssertTrue(contentSource.contains("isConversationRouteActive: route == .session"),
                      "sidebar selection must follow the actual session/settings route")
    }
}
