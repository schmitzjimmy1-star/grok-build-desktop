import XCTest
@testable import GrokBuild

final class AppMenuTests: XCTestCase {
    func testUpdateMenuUsesStandardApplicationMenuCopy() {
        XCTAssertEqual(
            AppMenuCopy.updateMenuTitle(hasActionableUpdate: false),
            "Check for Updates…"
        )
        XCTAssertEqual(
            AppMenuCopy.updateMenuTitle(hasActionableUpdate: true),
            "Updates Available…"
        )
    }

    func testSidebarMenuTitleFlipsWithVisibility() {
        XCTAssertEqual(AppMenuCopy.sidebarMenuTitle(isVisible: true), "Hide Sidebar")
        XCTAssertEqual(AppMenuCopy.sidebarMenuTitle(isVisible: false), "Show Sidebar")
    }

    /// Rehomed from the removed status-bar menu; the usage page must keep an
    /// entry point in the standard application menu.
    func testViewUsageMenuCopy() {
        XCTAssertEqual(AppMenuCopy.viewUsageTitle, "View Usage on grok.com…")
    }
}
