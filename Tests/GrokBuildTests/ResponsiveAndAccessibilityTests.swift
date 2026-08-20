import XCTest
@testable import GrokBuild

/// Codex parity Slice 7 — responsive thresholds and accessibility repairs.
final class ResponsiveAndAccessibilityTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testInspectorYieldsToCollapsedStripWhenNarrow() {
        XCTAssertFalse(ResponsiveLayoutPolicy.inspectorFits(chatAreaWidth: 856),
                       "at the 1100-pt window minimum with the sidebar visible, the overlay yields to the collapsed strip")
        XCTAssertTrue(ResponsiveLayoutPolicy.inspectorFits(chatAreaWidth: 1100),
                      "collapsing the sidebar reclaims room for the inspector")
        XCTAssertTrue(ResponsiveLayoutPolicy.inspectorFits(chatAreaWidth: .infinity),
                      "the unmeasured initial state never suppresses the panel")
    }

    /// P3D — three regimes: collapsed strip below 900, a bounded overlay through
    /// 1,179, and the wider 340-pt worker canvas docked from 1,180 up.
    func testInspectorDocksOnlyAtFullThirdColumnWidth() {
        XCTAssertFalse(ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: 899),
                       "collapsed regime: the inspector does not dock")
        XCTAssertFalse(ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: 1179),
                       "overlay regime: below the dock threshold the panel overlays")
        XCTAssertTrue(ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: 1180),
                      "dock regime: a real third column once both surfaces fit at full width")
        XCTAssertTrue(ResponsiveLayoutPolicy.inspectorDocks(chatAreaWidth: 1200),
                      "default 1440×900 chat area (1440 − 240 sidebar) docks")
        XCTAssertEqual(ResponsiveLayoutPolicy.inspectorDockMinimumChatWidth, 1180)
        XCTAssertEqual(ResponsiveLayoutPolicy.activityCanvasWidth, 340)
        // Docking must leave the transcript above its readable minimum.
        XCTAssertGreaterThanOrEqual(
            ResponsiveLayoutPolicy.inspectorDockMinimumChatWidth
                - Double(ResponsiveLayoutPolicy.activityCanvasWidth) - 24,
            ResponsiveLayoutPolicy.conversationReadableMinimum,
            "1,180 − (340-pt canvas + padding) keeps the reading column readable"
        )
    }

    func testMeasuredWidthIgnoresSubPointJitter() {
        XCTAssertTrue(
            ResponsiveLayoutPolicy.shouldCommitMeasuredWidth(current: .infinity, next: 1200),
            "the first real measurement must replace the unmeasured sentinel"
        )
        XCTAssertFalse(
            ResponsiveLayoutPolicy.shouldCommitMeasuredWidth(current: 1200, next: 1200.4),
            "sub-point jitter must not rewrite chat-area state"
        )
        XCTAssertTrue(
            ResponsiveLayoutPolicy.shouldCommitMeasuredWidth(current: 1200, next: 1201),
            "a full point of resize still commits"
        )
        XCTAssertFalse(
            ResponsiveLayoutPolicy.shouldCommitMeasuredWidth(current: 1200, next: 1200),
            "identical widths are a no-op"
        )
    }

    func testMarkdownTableWidthUsesTheSharedGeometryEpsilon() throws {
        let richMessage = try source("GrokBuild/Views/RichMessageView.swift")
        let tableStart = try XCTUnwrap(richMessage.range(of: "private struct MarkdownTableView"))
        let tableSource = String(richMessage[tableStart.lowerBound...])

        XCTAssertTrue(tableSource.contains("commitAvailableWidth(proxy.size.width)"))
        XCTAssertTrue(tableSource.contains("width.isFinite, width > 0"))
        XCTAssertTrue(tableSource.contains("ResponsiveLayoutPolicy.shouldCommitMeasuredWidth("))
        XCTAssertFalse(
            tableSource.contains("onChange(of: proxy.size.width) { _, width in availableWidth = width }"),
            "sub-point table width jitter must not rewrite state during LazyVStack placement"
        )
    }

    func testInspectorPlacementHysteresisAvoidsThresholdOscillation() {
        let docked = ResponsiveLayoutPolicy.InspectorPlacement.dockedColumn
        let overlay = ResponsiveLayoutPolicy.InspectorPlacement.overlay
        let strip = ResponsiveLayoutPolicy.InspectorPlacement.collapsedStrip
        XCTAssertEqual(
            ResponsiveLayoutPolicy.inspectorPlacement(chatAreaWidth: .infinity, current: overlay),
            docked,
            "unmeasured initial state docks, matching the default window"
        )
        XCTAssertEqual(
            ResponsiveLayoutPolicy.inspectorPlacement(chatAreaWidth: 1179, current: docked),
            docked,
            "once docked, a 1-pt dip below 1,180 must not undock"
        )
        XCTAssertEqual(
            ResponsiveLayoutPolicy.inspectorPlacement(chatAreaWidth: 1163, current: docked),
            overlay,
            "docking yields only after the 16-pt hysteresis band"
        )
        XCTAssertEqual(
            ResponsiveLayoutPolicy.inspectorPlacement(chatAreaWidth: 899, current: overlay),
            overlay,
            "once overlaying, a 1-pt dip below 900 must not collapse"
        )
        XCTAssertEqual(
            ResponsiveLayoutPolicy.inspectorPlacement(chatAreaWidth: 883, current: overlay),
            strip
        )
        XCTAssertEqual(
            ResponsiveLayoutPolicy.inspectorPlacement(chatAreaWidth: 900, current: strip),
            overlay,
            "widening from the strip still uses the raw 900-pt enter threshold"
        )
        XCTAssertEqual(
            ResponsiveLayoutPolicy.inspectorPlacement(chatAreaWidth: 1180, current: overlay),
            docked,
            "widening from overlay still uses the raw 1,180-pt enter threshold"
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
        XCTAssertTrue(chatView.contains("inspectorPlacement == .overlay"),
                      "the overlay render is gated by hysteresis-backed placement")
        XCTAssertTrue(chatView.contains("if showActivitySidebar, inspectorPlacement == .overlay"),
                      "the user's open state is preserved so widening restores the panel")
        XCTAssertTrue(chatView.contains(".onGeometryChange(for: Double.self)"),
                      "width comes from geometry observation, not polling")
        XCTAssertTrue(chatView.contains("shouldCommitMeasuredWidth"),
                      "geometry commits ignore sub-point jitter")
        XCTAssertTrue(chatView.contains("inspectorPlacement == .dockedColumn"),
                      "the overlay stands down when the panel docks")
        XCTAssertTrue(chatView.contains("inspectorPlacement == .dockedColumn {\n            activityInspector(docked: true)"),
                      "the docked column is gated by the same policy and preserved open state")
        XCTAssertTrue(chatView.contains("activityInspector(docked: false)"),
                      "both mounts share the one inspector instance")
        XCTAssertTrue(chatView.contains("activityInspectorCollapsedStrip()"),
                      "below 900 the open inspector collapses instead of hiding")
        XCTAssertTrue(chatView.contains("grok-worker-activity-collapsed"),
                      "the narrow control is named as worker activity")
        XCTAssertTrue(chatView.contains("Workers \\(count)"),
                      "the narrow control exposes the exact worker count")
        XCTAssertTrue(chatView.contains("accessibilityLabel(\"Run inspector\")"),
                      "header menu speaks Run inspector")
        XCTAssertTrue(chatView.contains(".menuIndicator(.hidden)"),
                      "the inspector menu is one tiny hit target")
        XCTAssertTrue(chatView.contains(".onScrollGeometryChange(for: Bool.self)"),
                      "scroll attachment projects a Bool so sub-point distance jitter cannot rebuild the transcript")
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
        XCTAssertTrue(sidebar.contains(".accessibilityValue(session.id.uuidString)"),
                      "session rows expose the exact tab UUID so continuation can select one row")
        XCTAssertTrue(sidebar.contains("SessionSidebarMetadata.accessibilityLabel(for: session)"),
                      "session rows keep their spoken title/model/state label")
        XCTAssertTrue(sidebar.contains(".accessibilityAction(named: \"Rename session\")"),
                      "VoiceOver exposes rename without requiring a pointer-only context menu")
        XCTAssertTrue(sidebar.contains(".accessibilityAction(named: \"Close local tab\")"),
                      "VoiceOver exposes non-destructive local close without requiring hover")
        XCTAssertTrue(sidebar.contains(".accessibilityAction(named: \"Delete session\")"),
                      "VoiceOver names destructive backend deletion honestly")
    }

    func testTaskContractBarIsGoneWhileRunControlsRemainReachable() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let contract = try source("GrokBuild/Views/LivePlanSpine.swift")
        XCTAssertFalse(chatView.contains("grok-task-context-strip"))
        XCTAssertFalse(contract.contains("struct ThreadTaskContractView"))
        XCTAssertTrue(chatView.contains(".accessibilityLabel(\"Stop turn\")"),
                      "Stop remains directly reachable in the composer")
        XCTAssertTrue(chatView.contains("RunInspectorQuickLook"),
                      "run receipts remain reachable from the header")
        XCTAssertTrue(chatView.contains("activityInspector(docked:"),
                      "worker receipts remain visible in the right-side canvas")
    }

    func testFocusOrderSectionsRemainDeclared() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let topBar = try source("GrokBuild/Views/ChatTopBar.swift")
        let chrome = chatView + "\n" + topBar
        XCTAssertTrue(chatView.contains("accessibilitySortPriority(3)"))
        XCTAssertTrue(chatView.contains(".accessibilitySortPriority(2)"))
        XCTAssertTrue(chatView.contains(".accessibilitySortPriority(1)"))
        XCTAssertEqual(chrome.components(separatedBy: ".focusSection()").count - 1, 3,
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
        XCTAssertEqual(ResponsiveLayoutPolicy.sidebarMinimumWidth, 248,
                       "F2: the persistent rail matches the shell width")
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
             ["New project", "Filter projects", "Session dashboard"]),
            ("GrokBuild/Views/ChatTopBar.swift",
             []),
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
