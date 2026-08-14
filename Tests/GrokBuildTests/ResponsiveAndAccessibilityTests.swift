import XCTest
@testable import GrokBuild

/// Codex parity Slice 7 — responsive thresholds and accessibility repairs.
final class ResponsiveAndAccessibilityTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testInspectorHidesFirstAndReturnsWhenWide() {
        XCTAssertFalse(ResponsiveLayoutPolicy.inspectorFits(chatAreaWidth: 856),
                       "at the 1100-pt window minimum with the sidebar visible, the overlay hides first")
        XCTAssertTrue(ResponsiveLayoutPolicy.inspectorFits(chatAreaWidth: 1100),
                      "collapsing the sidebar reclaims room for the inspector")
        XCTAssertTrue(ResponsiveLayoutPolicy.inspectorFits(chatAreaWidth: .infinity),
                      "the unmeasured initial state never suppresses the panel")
    }

    /// Workbench W-6 / audit Slice 4 — three regimes: collapsed strip below
    /// 900, a top-trailing overlay through 1,099, a docked third column from
    /// 1,100 up. Docking never changes when the inspector collapses.
    func testInspectorDocksOnlyAtFullThirdColumnWidth() {
        XCTAssertFalse(ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: 899),
                       "collapsed regime: the inspector does not dock")
        XCTAssertFalse(ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: 1099),
                       "overlay regime: below the dock threshold the panel overlays")
        XCTAssertTrue(ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: 1100),
                      "dock regime: a real third column once both surfaces fit at full width")
        XCTAssertTrue(ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: 1200),
                      "default 1440×900 chat area (1440 − 240 sidebar) docks")
        XCTAssertEqual(ResponsiveLayoutPolicy.inspectorDockMinimumChatWidth, 1100)
        // Docking must leave the transcript above its readable minimum.
        XCTAssertGreaterThanOrEqual(
            ResponsiveLayoutPolicy.inspectorDockMinimumChatWidth - 284,
            ResponsiveLayoutPolicy.conversationReadableMinimum,
            "1,100 − (260-pt panel + padding) keeps the reading column readable"
        )
    }

    func testSidebarCollapsesBeforeTheTranscriptCompresses() {
        // Current minimums keep the sidebar user-controlled…
        XCTAssertTrue(ResponsiveLayoutPolicy.sidebarFits(contentWidth: 1100, sidebarWidth: 280))
        // …but a smaller window must sacrifice the sidebar, never the transcript.
        XCTAssertFalse(ResponsiveLayoutPolicy.sidebarFits(contentWidth: 1000, sidebarWidth: 244))
        XCTAssertEqual(ResponsiveLayoutPolicy.conversationReadableMinimum, 812,
                       "760-pt reading column plus 26-pt padding per side")
    }

    func testInspectorRenderIsGatedByThePolicyWithStatePreserved() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        XCTAssertTrue(chatView.contains("ResponsiveLayoutPolicy.inspectorFits(chatAreaWidth: chatAreaWidth)"),
                      "the overlay render is gated by the responsive policy")
        XCTAssertTrue(chatView.contains("if showActivitySidebar,\n               ResponsiveLayoutPolicy.inspectorFits"),
                      "the user's open state is preserved so widening restores the panel")
        XCTAssertTrue(chatView.contains(".onGeometryChange(for: Double.self)"),
                      "width comes from geometry observation, not polling")
        // Workbench W-6: exactly one mount at a time — the overlay branch
        // excludes the dock regime, and the docked column requires it.
        XCTAssertTrue(chatView.contains("!ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: chatAreaWidth)"),
                      "the overlay stands down when the panel docks")
        XCTAssertTrue(chatView.contains("ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: chatAreaWidth) {\n            activityInspector(docked: true)"),
                      "the docked column is gated by the same policy and preserved open state")
        XCTAssertTrue(chatView.contains("activityInspector(docked: false)"),
                      "both mounts share the one inspector instance")
        XCTAssertTrue(chatView.contains("activityInspectorCollapsedStrip()"),
                      "below 900 the open inspector collapses instead of hiding")
        XCTAssertTrue(chatView.contains("Text(\"Run inspector\")"),
                      "header toggle speaks Run inspector")
    }

    /// Slice 4 acceptance found `.menuStyle(.button)` menus ignored AXPress and
    /// synthesized clicks; the borderlessButton style (proven by the add menu)
    /// opens from a plain press. No composer menu may regress to `.button`.
    func testComposerMenusUseThePressableMenuStyle() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        XCTAssertFalse(chatView.contains(".menuStyle(.button)"),
                       "the .button menu style swallowed AXPress during Slice 4 acceptance")
        for id in ["grok-mode-selector", "grok-model-effort-selector", "grok-composer-add-menu"] {
            XCTAssertTrue(chatView.contains(id), "composer menu `\(id)` must remain")
        }
    }

    func testSidebarSessionRowsAreIdentifiableForAssistiveTech() throws {
        let sidebar = try source("GrokBuild/Views/SidebarView.swift")
        XCTAssertTrue(sidebar.contains("grok-sidebar-session-row"),
                      "nested session rows carry a stable accessibility identifier")
        XCTAssertTrue(sidebar.contains("SessionSidebarMetadata.accessibilityLabel(for: session)"),
                      "session rows keep their spoken title/model/state label")
        XCTAssertTrue(sidebar.contains(".accessibilityAction(named: \"Rename session\")"),
                      "VoiceOver exposes rename without requiring a pointer-only context menu")
        XCTAssertTrue(sidebar.contains(".accessibilityAction(named: \"Close session\")"),
                      "VoiceOver exposes exact session close without requiring hover")
    }

    func testTaskContractControlsExposeDistinctNamedSemantics() throws {
        let contract = try source("GrokBuild/Views/LivePlanSpine.swift")
        for identifier in [
            "grok-task-contract-toggle",
            "grok-task-contract-details",
            "Cancel pending",
            "Stop turn",
            "Pause goal",
            "Resume goal",
            "Resume saved task",
            "Continue as New",
        ] {
            XCTAssertTrue(contract.contains(identifier), "missing task-contract semantic: \(identifier)")
        }
        XCTAssertTrue(contract.contains("An active model turn can be stopped, not paused."),
                      "the UI must not invent pause semantics the CLI does not expose")
        XCTAssertTrue(contract.contains(".popover(isPresented: $isExpanded"),
                      "task details must not resize the selectable transcript during live ACP updates")
    }

    func testFocusOrderSectionsRemainDeclared() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        XCTAssertTrue(chatView.contains("accessibilitySortPriority(3)"))
        XCTAssertTrue(chatView.contains(".accessibilitySortPriority(2)"))
        XCTAssertTrue(chatView.contains(".accessibilitySortPriority(1)"))
        XCTAssertEqual(chatView.components(separatedBy: ".focusSection()").count - 1, 3,
                       "workbench controls, transcript, and composer each own one focus section")
    }

    /// Slice 7 close-out: the sidebar step of the responsive order is wired into
    /// the actual visibility decision, not just declared as a pure policy.
    func testSidebarVisibilityWiresTheResponsiveThreshold() {
        // Preference and Settings behavior are unchanged.
        XCTAssertTrue(SidebarVisibility.shouldShow(preference: true, settingsPresented: false))
        XCTAssertFalse(SidebarVisibility.shouldShow(preference: true, settingsPresented: true))
        XCTAssertFalse(SidebarVisibility.shouldShow(preference: false, settingsPresented: false))
        // At the 1100-pt window minimum the collapse is unreachable by construction.
        XCTAssertTrue(SidebarVisibility.shouldShow(
            preference: true, settingsPresented: false, availableContentWidth: 1100
        ))
        // A hypothetical smaller window sacrifices the sidebar before the transcript.
        XCTAssertFalse(SidebarVisibility.shouldShow(
            preference: true, settingsPresented: false, availableContentWidth: 1000
        ))
        XCTAssertEqual(ResponsiveLayoutPolicy.sidebarMinimumWidth, 200,
                       "Workbench W-1: the rail is navigation, not a pane")
    }

    /// M-1 closure (2026-08-08): reduce motion is code-enforced, not a manual
    /// sweep. Every view file that animates must consult the system setting —
    /// a file-level tripwire so a new `withAnimation` cannot ship ungated.
    func testEveryAnimatingViewConsultsReduceMotion() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GrokBuild")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ))
        var animatingFiles = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("withAnimation(") else { continue }
            animatingFiles += 1
            XCTAssertTrue(
                source.contains("accessibilityReduceMotion"),
                "\(url.lastPathComponent) animates without consulting Reduce Motion"
            )
        }
        XCTAssertGreaterThan(animatingFiles, 0, "the tripwire must actually scan animating files")
    }

    /// Slice 7 icon-only audit: every audited icon-only control carries an explicit
    /// accessibility label (SF Symbol fallback names are not the contract).
    func testAuditedIconOnlyControlsCarryExplicitLabels() throws {
        let expectations: [(file: String, labels: [String])] = [
            ("GrokBuild/Views/SidebarView.swift",
             ["Filter projects", "Session dashboard", "New project"]),
            ("GrokBuild/Views/PreviewPane.swift", ["Close review pane"]),
            ("GrokBuild/Views/SessionsBrowserPanel.swift", ["Delete session"]),
            ("GrokBuild/Views/MemoryBrowserPanel.swift", ["Reveal in Finder"]),
            ("GrokBuild/Views/Settings/AgentsSettingsPane.swift",
             ["Edit subagent", "Remove subagent"]),
            ("GrokBuild/Views/Settings/MCPSettingsPane.swift",
             ["Move argument up", "Move argument down", "Remove argument"]),
            ("GrokBuild/Views/Settings/MarketplaceSettingsPane.swift",
             ["Remove source", "Plugin actions"]),
            ("GrokBuild/Views/Settings/PluginsSettingsPane.swift",
             ["Plugin actions", "Refresh plugins"])
        ]
        for expectation in expectations {
            let contents = try source(expectation.file)
            for label in expectation.labels {
                XCTAssertTrue(
                    contents.contains(".accessibilityLabel(\"\(label)\")"),
                    "\(expectation.file) lost the explicit \"\(label)\" label"
                )
            }
        }
        let customModels = try source("GrokBuild/Views/Settings/CustomModelsSettingsPane.swift")
        XCTAssertEqual(
            customModels.components(separatedBy: "accessibilityLabel(revealProviderKey").count
                + customModels.components(separatedBy: "accessibilityLabel(revealKey").count - 2,
            2,
            "both reveal-key toggles speak their current action"
        )
    }
}
