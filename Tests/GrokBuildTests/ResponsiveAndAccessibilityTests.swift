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
    }

    func testFocusOrderSectionsRemainDeclared() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        XCTAssertTrue(chatView.contains("accessibilitySortPriority(3)"))
        XCTAssertTrue(chatView.contains(".accessibilitySortPriority(2)"))
        XCTAssertTrue(chatView.contains(".accessibilitySortPriority(1)"))
        XCTAssertEqual(chatView.components(separatedBy: ".focusSection()").count - 1, 3,
                       "workbench controls, transcript, and composer each own one focus section")
    }
}
