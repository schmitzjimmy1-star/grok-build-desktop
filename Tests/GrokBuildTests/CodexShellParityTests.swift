import XCTest
@testable import GrokBuild

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

    private func chromeSource() throws -> String {
        try [
            "GrokBuild/Views/ChatView.swift",
            "GrokBuild/Views/ChatTopBar.swift",
            "GrokBuild/Views/ChatComposer.swift",
            "GrokBuild/Views/ChatHeaderReviewToggle.swift",
        ].map(source).joined(separator: "\n")
    }

    /// Slice 4 presentation contract (replaced the Slice 0 red-baseline
    /// inventory): the composer is Codex-shaped. No Details shelf, no center
    /// hint prose, no project status row, no duplicate Review/Activity controls
    /// under the composer; one add/context menu carries files, MCPs, skills,
    /// and project tools; telemetry lives in the model popover.
    func testComposerIsCodexShaped() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let chrome = try chromeSource()

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
            "grok-send-startup-status",
            "grok-model-effort-selector",
            "MicButton(",
            "sessionActionButton",
            "Section(\"Session telemetry\")",
            "grok-model-route-contract",
        ] {
            XCTAssertTrue(
                chrome.contains(retained),
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

        XCTAssertTrue(sidebar.contains("SidebarSelectionSemantics.railActionIsSelected"),
                      "rail actions must explicitly reject persistent selection")
        XCTAssertTrue(sidebar.contains(".accessibilityRemoveTraits("),
                      "unselected rail/workspace/session controls must remove stale selected traits")
        XCTAssertTrue(sidebar.contains("SidebarSelectionSemantics.workspaceIsSelected"),
                      "workspace highlight and AX state must derive from one route-aware selection")
        XCTAssertTrue(sidebar.contains("SidebarSelectionSemantics.sessionIsSelected"),
                      "session highlight and AX state must derive from one route-aware selection")
        XCTAssertTrue(sidebar.contains("List(selection: persistentSelection)"),
                      "native List selection must expose the one real persistent destination")
        XCTAssertTrue(sidebar.contains("visibleSelectedSessionID"),
                      "a hidden or unavailable session row must fall back to project selection")
        XCTAssertFalse(sidebar.contains("Help and settings"),
                       "the old footer Help-and-settings copy must not return")
        XCTAssertTrue(sidebar.contains("grok-sidebar-account-settings"),
                      "the account row opens Settings; Command-comma still works")
        XCTAssertTrue(sidebar.contains("Section(\"Recents\")"),
                      "the selected project's session rows live in one Codex-style Recents section")
        XCTAssertTrue(sidebar.contains("filtered.contains(where: { $0.id == selectedWorkspaceID })"),
                      "a filtered-out project cannot leave orphaned Recents rows")
        XCTAssertFalse(sidebar.contains("Text(workspace.path.path)"),
                       "project rows keep the path as a tooltip, not a second line of chrome")

        let appDelegate = try source("GrokBuild/AppDelegate.swift")
        XCTAssertTrue(appDelegate.contains("AppTheme.Palette.canvasNSColor"),
                      "the AppKit window fill must match the SwiftUI canvas token")

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
        XCTAssertTrue(contentView.contains("isConversationRouteActive: route == .session"),
                      "ContentView must bind sidebar selection to the real AppRoute")
        XCTAssertTrue(contentView.contains("selectedSessionID = nil"),
                      "project switches must clear a hidden stale session selection")
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
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("GrokBuild/Models/Agent.swift").path),
                       "empty Agent Team placeholder must stay deleted")

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
        let welcomeState = try source("GrokBuild/Views/WelcomeStateView.swift")
        XCTAssertTrue(chatView.contains("WelcomeStateView("),
                      "ChatView still mounts the extracted welcome state")
        XCTAssertFalse(chatView.contains("private var welcomeState"),
                       "Phase 6 keeps the welcome implementation out of ChatView")
        XCTAssertTrue(welcomeState.contains("WorkbenchIntent.defaults"),
                      "Red-baseline inventory: the Ask/Build/Review intent chips still render")
        XCTAssertFalse(welcomeState.contains("Text(\"Grok agent runs in this folder.\")"),
                       "Visual Quiet Path A dropped the redundant folder-as-cwd line")
        XCTAssertFalse(welcomeState.contains("Text(item.detail)"),
                       "Ask/Build/Review chips keep outcome copy in accessibility, not card paragraphs")
        XCTAssertTrue(welcomeState.contains("accessibilityLabel(\"\\(item.title). \\(item.detail)\")"),
                      "VoiceOver still hears the Ask/Build/Review outcome copy")
        XCTAssertFalse(welcomeState.contains("Text(\"Recent tasks\")"),
                       "W-3 recent-task dashboard must not return to the empty canvas")
        XCTAssertFalse(chatView.contains("grok-task-context-strip"),
                       "the running task-contract bar must not return")
    }

    /// Slice 4 contract (supersedes the Slice 0/2 residue inventory): Review has
    /// exactly two truthful homes — the contextual header control and the inline
    /// changed-files card. The Details-shelf duplicate is gone for good.
    func testReviewLivesOnlyInHeaderAndInlineCard() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let reviewToggle = try source("GrokBuild/Views/ChatHeaderReviewToggle.swift")
        XCTAssertTrue(reviewToggle.contains("grok-header-review-toggle"),
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
        XCTAssertTrue(contentView.contains("onOpenActivity: { openActivityDashboard() }"),
                      "the sidebar bell snapshots historical receipts before routing through the single modal owner")
        XCTAssertTrue(contentView.contains("sessionModal = .activityDashboard"),
                      "the dashboard helper still uses the single modal owner")
        XCTAssertTrue(contentView.contains("onClose: { showPreview = false }"),
                      "the review split still targets the real PreviewPane with one owner")
        XCTAssertTrue(contentView.contains("workspaces: workspaceStore.orderedWorkspaces"),
                      "Browse Sessions lists every GrokBuild sidebar project, not only the current cwd")
        XCTAssertFalse(contentView.contains("workspaces: currentWorkspace.map { [$0] } ?? []"),
                       "the current-project-only Browse Sessions wiring must not return")
        XCTAssertFalse(contentView.contains("workspaces: workspaceStore.workspaces,"),
                       "Browse Sessions follows sidebar order, not the unsorted storage array")

        XCTAssertEqual(
            SessionsBrowserPanel.emptyDescription(workspaceCount: 0, searchQuery: ""),
            "Add a project to browse Grok sessions."
        )
        XCTAssertEqual(
            SessionsBrowserPanel.emptyDescription(workspaceCount: 2, searchQuery: ""),
            "No sessions in these projects."
        )
        XCTAssertEqual(
            SessionsBrowserPanel.headerSubtitle(workspaces: [
                Workspace(name: "A", path: URL(fileURLWithPath: "/tmp/a")),
                Workspace(name: "B", path: URL(fileURLWithPath: "/tmp/b")),
            ]),
            "All GrokBuild projects"
        )

        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let topBar = try source("GrokBuild/Views/ChatTopBar.swift")
        let reviewToggle = try source("GrokBuild/Views/ChatHeaderReviewToggle.swift")

        // The inspector docks at the default window width; overlay is mid-band only.
        XCTAssertTrue(chatView.contains("ZStack(alignment: .topTrailing) {"),
                      "the Run inspector still overlays in the mid band")
        XCTAssertTrue(chatView.contains("activityInspector(docked: true)"),
                      "at default width the inspector docks as a third column")
        XCTAssertTrue(chatView.contains("inspectorPlacement == .dockedColumn"),
                      "docking is gated by hysteresis-backed placement")
        XCTAssertFalse(chatView.contains("HStack(spacing: 0) {\n            VStack(spacing: 0) {\n            topBar"),
                       "the old third-column body layout must not return")

        // Compact contextual header: Review and inspector. Settings is the
        // sidebar account row, not a trailing gear.
        XCTAssertTrue(reviewToggle.contains("grok-header-review-toggle"),
                      "the header carries the contextual Review control")
        XCTAssertTrue(chatView.contains("headerReviewToggle"),
                      "ChatView still hosts the Review toggle in the extracted top bar")
        XCTAssertTrue(topBar.contains("reviewToggle\n\n            inspectorToggle"),
                      "header trailing order is Review, then inspector toggle")
        XCTAssertFalse(topBar.contains("Image(systemName: \"gearshape\")"),
                       "Settings is the sidebar account row, not a header gear")
        XCTAssertTrue(topBar.contains("TitlebarMetrics.trafficLightLeading"),
                      "the header sits beside the traffic lights")
        XCTAssertTrue(topBar.contains("TitlebarMetrics.height"),
                      "the header is one control row")
        XCTAssertTrue(topBar.contains("TitlebarMetrics.contentTopInset"),
                      "the header sits just under the traffic lights, not inside the vibrant titlebar")
        XCTAssertTrue(topBar.contains("TitlebarMetrics.headerIconGap"),
                      "the session title keeps calm spacing before contextual controls")
        XCTAssertFalse(topBar.contains("TitlebarGlyph(systemName: \"magnifyingglass\")"),
                       "Filter projects belongs to the persistent rail header")
        XCTAssertFalse(topBar.contains("TitlebarGlyph(systemName: \"bell\")"),
                       "Session dashboard belongs to the persistent rail header")
        XCTAssertTrue(topBar.contains("? TitlebarMetrics.headerIconGap"),
                      "the persistent rail means the main header needs only a local inset")
        XCTAssertFalse(topBar.contains(".offset(y: -TitlebarMetrics.height)"),
                       "the header no longer lifts into the traffic-light row")
        XCTAssertTrue(topBar.contains(".menuIndicator(.hidden)"),
                      "More actions is one tiny ellipsis, not ellipsis plus a chevron")
        XCTAssertTrue(topBar.contains("TitlebarGlyph(systemName: \"sidebar.left\")"),
                      "titlebar icons are non-template glyphs so Dark vibrancy cannot hide them")
        XCTAssertTrue(topBar.contains("TitlebarGlyph(systemName: \"ellipsis\")"),
                      "More actions uses the same baked titlebar glyph")
        XCTAssertTrue(topBar.contains("AppTheme.Palette.titlebarControl"),
                      "titlebar icons use the readable titlebar token, not system secondary")
        XCTAssertTrue(reviewToggle.contains("TitlebarGlyph(systemName: \"doc.on.doc\")"),
                      "Review uses a baked titlebar glyph")
        XCTAssertTrue(reviewToggle.contains("AppTheme.Palette.titlebarControl"),
                      "Review stays visible in the transparent titlebar")
        XCTAssertTrue(chatView.contains("TitlebarGlyph(systemName: \"sidebar.right\")"),
                      "the inspector menu uses a baked titlebar glyph")
        XCTAssertTrue(chatView.contains("AppTheme.Palette.titlebarControl"),
                      "the inspector menu uses the same readable titlebar token")
        XCTAssertFalse(topBar.contains(".overlay(alignment: .bottom) { Divider() }"),
                       "the titlebar has no hairline under the characters")
        XCTAssertTrue(chatView.contains("RunInspectorQuickLook"),
                      "run facts live in the header dropdown")
        XCTAssertTrue(chatView.contains("Show subagents"),
                      "the dropdown can open the right-side subagent tracker")
        XCTAssertTrue(chatView.contains("hasLiveSubagents"),
                      "live workers auto-open the right-side tracker")
        XCTAssertFalse(chatView.contains("Color.primary.opacity(0.035), in: RoundedRectangle"),
                       "launch choices are not a tinted banner")
        XCTAssertTrue(chatView.contains("LaunchSessionChoices("),
                      "saved-task choices remain")
        XCTAssertTrue(chatView.contains(".frame(maxWidth: AppTheme.Layout.composerMaxWidth, alignment: .leading)"),
                      "launch choices sit in the composer column, not a full-width bar")
        XCTAssertFalse(chatView.contains("showsTaskContextStrip"),
                       "the task-contract bar is removed, not merely hidden while idle")

        let sidebar = try source("GrokBuild/Views/SidebarView.swift")
        XCTAssertTrue(sidebar.contains("Image(systemName: \"magnifyingglass\")"),
                      "Filter projects lives in the persistent rail header")
        XCTAssertTrue(sidebar.contains("Image(systemName: \"bell\")"),
                      "Session dashboard lives in the persistent rail header")
        XCTAssertTrue(sidebar.contains("Section(\"Pinned\")"))
        XCTAssertTrue(sidebar.contains("Section(\"Recents\")"))

        XCTAssertTrue(contentView.contains("private var workspaceShell: some View"),
                      "F2 owns one explicit persistent shell")
        XCTAssertTrue(contentView.contains("HStack(spacing: 0)"),
                      "the project rail and canvas are structural siblings")
        XCTAssertTrue(contentView.contains(".move(edge: .leading)"),
                      "the sidebar slides in from the leading edge")
        XCTAssertTrue(contentView.contains("TitlebarMetrics.sidebarWidth"),
                      "the persistent rail uses the one shell width token")
        XCTAssertFalse(contentView.contains("projectSidebarOverlay"),
                       "F2 removes the old dimming slide-over")
        XCTAssertFalse(contentView.contains("Color.black.opacity(0.18)"),
                       "the main canvas is never dimmed merely because navigation is visible")
        XCTAssertTrue(contentView.contains("onOpenSettings: { openSettings(tab: selectedSettingsTab) }"),
                      "the account row routes through the existing Settings owner")
        XCTAssertFalse(contentView.contains("HSplitView {\n            if SidebarVisibility.shouldShow"),
                       "the rail remains a fixed shell sibling, never a user-resizable split pane")

        let appDelegate = try source("GrokBuild/AppDelegate.swift")
        XCTAssertTrue(appDelegate.contains(".fullSizeContentView"),
                      "the main window draws content under the traffic lights")
        XCTAssertTrue(appDelegate.contains("hosting.safeAreaRegions = []"),
                      "the hosting controller must not keep a titlebar-only safe area")
    }
}
