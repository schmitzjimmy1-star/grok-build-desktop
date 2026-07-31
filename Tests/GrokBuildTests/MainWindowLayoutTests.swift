import XCTest
@testable import GrokBuild

final class MainWindowLayoutTests: XCTestCase {
    func testMinimumFitsSidebarPlusComposerAndStatusPills() {
        // Sidebar (~260) + composer/status chrome (~840) → 1100×720.
        XCTAssertGreaterThanOrEqual(MainWindowLayout.minimumSize.width, 1000)
        XCTAssertEqual(MainWindowLayout.minimumSize.width, 1100)
        XCTAssertEqual(MainWindowLayout.minimumSize.height, 720)
    }

    func testDefaultIsAtLeastMinimum() {
        XCTAssertGreaterThanOrEqual(MainWindowLayout.defaultSize.width, MainWindowLayout.minimumSize.width)
        XCTAssertGreaterThanOrEqual(MainWindowLayout.defaultSize.height, MainWindowLayout.minimumSize.height)
        XCTAssertEqual(MainWindowLayout.defaultSize.width, 1440)
        XCTAssertEqual(MainWindowLayout.defaultSize.height, 900)
    }

    func testComposerUsesFullChatColumnWidth() {
        XCTAssertEqual(MainWindowLayout.composerMaxWidth, .infinity)
    }

    func testScreenFillingFrameUsesTheAvailableDisplayFrame() {
        let visibleFrame = CGRect(x: 0, y: 48, width: 1440, height: 812)
        XCTAssertEqual(MainWindowLayout.screenFillingFrame(visibleFrame: visibleFrame), visibleFrame)
    }

    func testSidebarVisibilityRespectsPreferenceDuringChat() {
        XCTAssertTrue(SidebarVisibility.shouldShow(preference: true, settingsPresented: false))
        XCTAssertFalse(SidebarVisibility.shouldShow(preference: false, settingsPresented: false))
    }

    func testSettingsUsesOnlyItsInternalNavigation() {
        XCTAssertFalse(SidebarVisibility.shouldShow(preference: false, settingsPresented: true))
        XCTAssertFalse(SidebarVisibility.shouldShow(preference: true, settingsPresented: true))
    }
}
