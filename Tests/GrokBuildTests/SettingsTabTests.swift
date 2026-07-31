import XCTest
import AppKit
@testable import GrokBuild

final class SettingsTabTests: XCTestCase {
    func testAllTabsHaveUniqueNonEmptyTitles() {
        let titles = SettingsTab.allCases.map(\.title)
        XCTAssertEqual(titles.count, Set(titles).count)
        for title in titles {
            XCTAssertFalse(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(title.contains("…"))
            XCTAssertFalse(title.hasSuffix("..."))
        }
    }

    func testTabOrderMatchesSettingsSurface() {
        XCTAssertEqual(
            SettingsTab.allCases.map(\.title),
            [
                "Agents",
                "Models",
                "Memory",
                "Workflows",
                "Browser",
                "Computer Use",
                "MCP Servers",
                "Skills",
                "Plugins",
                "Marketplace",
                "Hooks",
                "Compatibility",
                "Permissions",
                "App",
            ]
        )
    }

    func testAllTabsHaveSystemImages() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.systemImage.isEmpty, "\(tab) missing systemImage")
            XCTAssertNotNil(
                NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: nil),
                "\(tab) uses unavailable SF Symbol \(tab.systemImage)"
            )
        }
    }

    func testSettingsSidebarGroupsEveryTabExactlyOnce() {
        let groupedTabs = SettingsSection.allCases.flatMap(\.tabs)
        XCTAssertEqual(groupedTabs.count, SettingsTab.allCases.count)
        XCTAssertEqual(Set(groupedTabs), Set(SettingsTab.allCases))
        XCTAssertEqual(groupedTabs, SettingsTab.allCases)
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["Grok", "Tools", "Extensions", "Controls", "Application"]
        )

        for section in SettingsSection.allCases {
            XCTAssertFalse(section.title.isEmpty)
            XCTAssertFalse(section.tabs.isEmpty, "\(section) should contain at least one tab")
        }
    }

    func testKeepAliveMountsSelectedAndPreviouslyVisitedTabsOnly() {
        var loaded: Set<SettingsTab> = []
        XCTAssertTrue(SettingsTabKeepAlive.shouldMount(.agents, selected: .agents, loaded: loaded))
        XCTAssertFalse(SettingsTabKeepAlive.shouldMount(.browser, selected: .agents, loaded: loaded))

        SettingsTabKeepAlive.recordVisit(.agents, loaded: &loaded)
        SettingsTabKeepAlive.recordVisit(.browser, loaded: &loaded)

        XCTAssertEqual(loaded, [.agents, .browser])
        XCTAssertTrue(SettingsTabKeepAlive.shouldMount(.agents, selected: .models, loaded: loaded))
        XCTAssertTrue(SettingsTabKeepAlive.shouldMount(.browser, selected: .models, loaded: loaded))
        XCTAssertTrue(SettingsTabKeepAlive.shouldMount(.models, selected: .models, loaded: loaded))
        XCTAssertFalse(SettingsTabKeepAlive.shouldMount(.hooks, selected: .models, loaded: loaded))
    }

    func testSettingsProportionsStayCompactAtFullScreenWidths() {
        XCTAssertLessThanOrEqual(AppTheme.Layout.settingsContentMaxWidth, 760)
        XCTAssertLessThanOrEqual(AppTheme.Layout.settingsControlWidth, 180)
        XCTAssertLessThan(AppTheme.Layout.settingsRuleEditorHeight, 120)
    }
}
