import XCTest

/// Codex parity Slice 0 — red-baseline inventory (2026-08-07).
///
/// These tests prove the known pre-parity residue STILL EXISTS in the merged
/// source. They are deliberately not desired-state assertions: each one pins a
/// structure that a later authorized slice must remove or relocate, so that the
/// slice which deletes it is forced to replace this inventory with a real
/// presentation contract instead of silently dropping coverage.
///
/// Replacement map (from docs/CLAUDE_FABLE_CODEX_PARITY_SLICES_2026-08-07.md):
/// - sidebar lanes residue      → replaced in Slice 1
/// - composer Details residue   → replaced in Slice 4 (`ComposerPresentationContract`)
/// - Activity dashboard residue → replaced in Slice 5 (`ContextInspectorProjection`)
/// - empty-state pills          → judged against the photographs in Slice 1/7
final class CodexShellParityTests: XCTestCase {
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    /// Slice 4 presentation contract (replaced the Slice 0 red-baseline
    /// inventory): the composer is Codex-shaped. No Details shelf, no center
    /// hint prose, no project status row, no duplicate Review/Activity controls
    /// under the composer; one add/context menu carries files, MCPs, skills,
    /// and project tools; telemetry lives in the model popover.
    func testComposerIsCodexShaped() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")

        for removed in [
            "showComposerDetails",
            "composerDetailsToggle",
            "composerDetailsDisclosure",
            "composerDetailsAccessibilityValue",
            "composerCenterHint",
            "private var projectStatusRow",
            "private var reviewControls",
            "⏎ send",
        ] {
            XCTAssertFalse(
                chatView.contains(removed),
                "Slice 4 contract: `\(removed)` must not return to ChatView.swift"
            )
        }

        for retained in [
            "TextField(\"Describe a task\"",
            "private var composerAddMenu",
            "grok-composer-add-menu",
            "Attach Files…",
            "togglePromptMCPAttachment",
            "Section(\"Skills and workflows\")",
            "browserStatusIndicator",
            "computerUseStatusIndicator",
            "grok-mode-selector",
            "grok-model-effort-selector",
            "MicButton(",
            "sessionActionButton",
            "Section(\"Session telemetry\")",
            "grok-model-route-contract",
        ] {
            XCTAssertTrue(
                chatView.contains(retained),
                "Slice 4 contract: authoring/telemetry surface `\(retained)` must remain reachable"
            )
        }
    }

    /// Slice 1 presentation contract (replaced the Slice 0 red-baseline
    /// inventory): the left sidebar is navigation-only. No operational lanes,
    /// no permanent Agents/Connections sections, no primary Activity/Workflows
    /// rows; the header bell owns activity, and navigation/session hierarchy
    /// (projects, nested sessions, search, add project, footer) remains.
    func testSidebarIsNavigationOnly() throws {
        let sidebar = try source("GrokBuild/Views/SidebarView.swift")

        for removed in [
            "activityLane",
            "agentEntries",
            "PromptMCPOption",
            "SidebarActivityRow",
            "AgentHubRow",
            "ConnectionSidebarRow",
            "Label(\"Agents\"",
            "Label(\"Connections\"",
            "Label(\"Activity\"",
            "CodexRailButton(title: \"Activity\"",
            "CodexRailButton(title: \"Workflows\"",
        ] {
            XCTAssertFalse(
                sidebar.contains(removed),
                "Slice 1 contract: `\(removed)` must not return to SidebarView.swift"
            )
        }

        for retained in [
            "CodexRailButton(title: \"New chat\"",
            "CodexRailButton(title: \"Sessions\"",
            "CodexRailButton(title: \"Plugins\"",
            "CodexRailButton(title: \"Security\"",
            "Button(action: onOpenActivity) {",   // header bell
            "Text(\"Projects\")",
            "sessionRow(",
            "TextField(\"Filter projects\"",
            "projectContextMenu(",
        ] {
            XCTAssertTrue(
                sidebar.contains(retained),
                "Slice 1 contract: navigation surface `\(retained)` must remain in SidebarView.swift"
            )
        }

        let contentView = try source("GrokBuild/ContentView.swift")
        for wiring in [
            "activityLane:",
            "agentEntries:",
            "connections: activeStore.promptMCPOptions",
        ] {
            XCTAssertFalse(
                contentView.contains(wiring),
                "Slice 1 contract: ContentView must not feed operational lanes into the sidebar via `\(wiring)`"
            )
        }
    }

    /// Slice 5 presentation contract (replaced the Slice 0 red-baseline
    /// inventory): the right panel is a compact contextual inspector — short
    /// optional sections, content height, deep receipts one disclosure away —
    /// and never a dashboard again.
    func testInspectorIsCompactAndContextual() throws {
        let activitySidebar = try source("GrokBuild/Views/ActivitySidebar.swift")

        for removed in [
            "maxHeight: 620",
            "Label(\"Ready to work\"",
            "idleWorkspacePanel",
            "idleChangedFiles",
        ] {
            XCTAssertFalse(activitySidebar.contains(removed),
                           "Slice 5 contract: dashboard residue `\(removed)` must not return")
        }

        // "grok-inspector-computer-use" left this list 2026-08-08: the owner
        // removed the Computer Use readiness note from the inspector. The
        // projection keeps the receipt; Settings owns the control surface.
        for retained in [
            "ContextInspectorProjection",
            "grok-inspector-subagents",
            "grok-inspector-sources",
            "grok-inspector-run-details",
            "grok-inspector-unresolved",
            "snapshot.continuity.requiresRecoveryAction",
            ".keyboardShortcut(.cancelAction)",
        ] {
            XCTAssertTrue(activitySidebar.contains(retained),
                          "Slice 5 contract: inspector surface `\(retained)` must remain")
        }

        // Recovery outranks parity: the continuity card renders before any
        // compact section in the panel body.
        let recovery = try XCTUnwrap(activitySidebar.range(of: "continuityCard(snapshot)"))
        let subagents = try XCTUnwrap(activitySidebar.range(of: "subagentsSection(subagents)"))
        XCTAssertLessThan(recovery.lowerBound, subagents.lowerBound,
                          "the recovery card must stay above the compact sections")
    }

    /// Slice 6 contract: one presentation owner per visible fact. Projections
    /// and chrome whose last truthful consumer was deleted may not return.
    func testDeletedProjectionsAndChromeStayDeleted() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("GrokBuild/Models/SidebarActivity.swift").path),
                       "SidebarActivityProjection had zero consumers after Slice 1")
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("GrokBuild/Models/AgentHub.swift").path),
                       "AgentHubProjection had zero consumers after Slice 1")

        let chatView = try source("GrokBuild/Views/ChatView.swift")
        for dead in ["agentStatusPill", "memoryStatusPill", "ContextUsageIndicator", "rememberPromptSheet", "showMemoryBrowser"] {
            XCTAssertFalse(chatView.contains(dead),
                           "dead chrome `\(dead)` must not return to ChatView")
        }
        // Live owners survive: inspector projection, evidence models, tool pills.
        XCTAssertTrue(chatView.contains("ContextInspectorProjection"))
        XCTAssertTrue(chatView.contains("toolPillStatus"))
        XCTAssertTrue(chatView.contains("ChangedFilesSummaryProjection"))
    }

    /// Slice 1/7 judgment call recorded as inventory: the Ask/Build/Review
    /// empty-state pills are a GrokBuild invention that the photographs do not
    /// show; they stay only if a side-by-side installed comparison proves they
    /// do not disturb the Codex hierarchy.
    func testEmptyStateIntentPillsStillExist() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        XCTAssertTrue(chatView.contains("welcomeState"),
                      "Red-baseline inventory: the welcome state still exists")
        XCTAssertTrue(chatView.contains("WorkbenchIntent.defaults"),
                      "Red-baseline inventory: the Ask/Build/Review intent pills still render")
    }

    /// Slice 4 contract (supersedes the Slice 0/2 residue inventory): Review has
    /// exactly two truthful homes — the contextual header control and the inline
    /// changed-files card. The Details-shelf duplicate is gone for good.
    func testReviewLivesOnlyInHeaderAndInlineCard() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        XCTAssertTrue(chatView.contains("grok-header-review-toggle"),
                      "the contextual header Review control remains")
        XCTAssertTrue(chatView.contains("ChangedFilesSummaryCard("),
                      "the inline changed-files card remains the in-conversation Review entry")
        XCTAssertFalse(chatView.contains("private var reviewControls"),
                       "the Details-shelf Review duplicate must not return")

        let sidebar = try source("GrokBuild/Views/SidebarView.swift")
        XCTAssertFalse(sidebar.contains("CodexRailButton(title: \"Review\""),
                       "Inventory fact: the sidebar has no primary Review row yet (Codex's rail does)")
        XCTAssertFalse(sidebar.contains("Pull requests"),
                       "Inventory fact: the sidebar has no pull-request entry yet (Codex's rail does)")
    }

    /// Slice 2 presentation contract: one route owner per surface and a compact
    /// contextual task header.
    func testHeaderAndRouteOwnership() throws {
        let contentView = try source("GrokBuild/ContentView.swift")

        // One mutually exclusive owner for the transient session sheets.
        XCTAssertTrue(contentView.contains("private enum SessionModal: Equatable"),
                      "the browser/dashboard sheets share one SessionModal owner")
        XCTAssertTrue(contentView.contains("@State private var sessionModal: SessionModal = .none"))
        XCTAssertFalse(contentView.contains("@State private var showSessions"),
                       "the old independent sessions-sheet Boolean must not return")
        XCTAssertFalse(contentView.contains("@State private var showSessionDashboard"),
                       "the old independent dashboard Boolean must not return")
        XCTAssertTrue(contentView.contains(".sheet(isPresented: sessionModalBinding(.sessionBrowser))"))
        XCTAssertTrue(contentView.contains(".sheet(isPresented: sessionModalBinding(.activityDashboard))"))
        XCTAssertTrue(contentView.contains("onOpenActivity: { sessionModal = .activityDashboard }"),
                      "the sidebar bell routes through the single modal owner")
        XCTAssertTrue(contentView.contains("onClose: { showPreview = false }"),
                      "the review split still targets the real PreviewPane with one owner")

        let chatView = try source("GrokBuild/Views/ChatView.swift")

        // The inspector overlays; it is not a conversation-crushing third column.
        XCTAssertTrue(chatView.contains("ZStack(alignment: .topTrailing) {"),
                      "the Activity inspector overlays the top-trailing corner")
        XCTAssertFalse(chatView.contains("HStack(spacing: 0) {\n            VStack(spacing: 0) {\n            topBar"),
                       "the old third-column body layout must not return")

        // Compact contextual header: Review state, inspector toggle, Settings.
        XCTAssertTrue(chatView.contains("grok-header-review-toggle"),
                      "the header carries the contextual Review control")
        let trailingCluster = try XCTUnwrap(chatView.range(of: "headerReviewToggle\n\n            activitySidebarToggle"),
                                            "header trailing order is Review, then inspector toggle, then Settings")
        XCTAssertTrue(
            chatView[trailingCluster.upperBound...]
                .prefix(300)
                .contains("Image(systemName: \"gearshape\")"),
            "Settings stays the last trailing header control"
        )
    }
}
