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

    /// Displays smaller than the window floor get a minimum-size frame with the
    /// top edge pinned to the visible area, keeping the title bar reachable.
    func testScreenFillingFrameClampsToMinimumOnSmallDisplays() {
        let small = CGRect(x: 0, y: 38, width: 1024, height: 640)
        let frame = MainWindowLayout.screenFillingFrame(visibleFrame: small)
        XCTAssertEqual(frame.width, MainWindowLayout.minimumSize.width)
        XCTAssertEqual(frame.height, MainWindowLayout.minimumSize.height)
        XCTAssertEqual(frame.maxY, small.maxY)
        XCTAssertEqual(frame.minX, small.minX)
    }

    func testSidebarVisibilityRespectsPreferenceDuringChat() {
        XCTAssertTrue(SidebarVisibility.shouldShow(preference: true, settingsPresented: false))
        XCTAssertFalse(SidebarVisibility.shouldShow(preference: false, settingsPresented: false))
    }

    func testSettingsUsesOnlyItsInternalNavigation() {
        XCTAssertFalse(SidebarVisibility.shouldShow(preference: false, settingsPresented: true))
        XCTAssertFalse(SidebarVisibility.shouldShow(preference: true, settingsPresented: true))
    }

    /// The View menu reads the preference outside SwiftUI: a missing key must
    /// mean the default (visible), not UserDefaults' bool fallback of false.
    func testSidebarCurrentPreferenceMatchesAppStorageSemantics() {
        let suite = "grokbuild.tests.sidebar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(SidebarVisibility.currentPreference(defaults: defaults), SidebarVisibility.defaultVisible)
        defaults.set(false, forKey: SidebarVisibility.storageKey)
        XCTAssertFalse(SidebarVisibility.currentPreference(defaults: defaults))
        defaults.set(true, forKey: SidebarVisibility.storageKey)
        XCTAssertTrue(SidebarVisibility.currentPreference(defaults: defaults))
    }
}
