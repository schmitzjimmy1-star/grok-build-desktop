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

    func testOnlySelectedPaneMountsSoHiddenTasksCancel() {
        for selected in SettingsTab.allCases {
            for tab in SettingsTab.allCases {
                XCTAssertEqual(
                    SettingsPaneLifecycle.shouldMount(tab, selected: selected),
                    tab == selected
                )
            }
        }
    }

    func testSharedValueStateMovesDraftSavedRestartRequiredLive() throws {
        var state = SettingsValueState<Bool>.unloaded(default: false)
        state.load(persisted: false, applied: false, live: false)
        XCTAssertEqual(state.status, .live)

        state.updateDraft(true)
        XCTAssertEqual(state.status, .draft)
        XCTAssertTrue(state.canApply)

        let tabID = UUID()
        let request = SettingsApplyRequest(
            configurationGeneration: 1,
            capability: .memory,
            persistenceOwner: .userDefaults,
            applyScope: .activeTabRestart,
            requiresProcessRestart: true,
            redactedSummary: "Memory launch setting saved.",
            target: SettingsApplyTarget(
                localTabID: tabID,
                backendSessionID: "backend-a",
                processGeneration: 4
            )
        )
        state.recordSaved(
            applied: true,
            requiresRestart: true,
            receipt: request.receipt
        )
        XCTAssertEqual(state.status, .restartRequired)
        XCTAssertEqual(state.configurationGeneration, 1)

        let live = EffectiveSessionReceipt(
            localTabID: tabID,
            workspaceID: UUID(),
            processIdentifier: 42,
            processGeneration: 5,
            backendSessionID: "backend-a",
            launchOutcome: .loaded,
            requestedModelID: "grok-4.5",
            requestedAgentID: nil,
            requestedReasoningEffort: nil,
            permissionMode: .ask,
            sandboxProfile: "default",
            memoryEnabled: true,
            browserEnabled: false,
            computerUseEnabled: false,
            mcpServerNames: [],
            startedAt: Date(),
            freshness: .live
        )
        let receipt = SettingsApplyReceiptResolver.resolve(
            request: request,
            connectionIsReady: true,
            liveReceipt: live
        )
        XCTAssertEqual(receipt.status, .success)
        state.complete(receipt: receipt, live: live.memoryEnabled)
        XCTAssertEqual(state.status, .live)
        XCTAssertFalse(state.requiresRestart)
    }

    func testAdaptiveSettingsFormRowsStackForNarrowOrAccessibilityLayout() {
        XCTAssertEqual(
            SettingsFormRowLayoutPolicy.layout(availableWidth: 760, usesAccessibilityText: false),
            .horizontal
        )
        XCTAssertEqual(
            SettingsFormRowLayoutPolicy.layout(availableWidth: 480, usesAccessibilityText: false),
            .vertical
        )
        XCTAssertEqual(
            SettingsFormRowLayoutPolicy.layout(availableWidth: 760, usesAccessibilityText: true),
            .vertical
        )
    }

    func testSettingsLoadStatesAndStatusAccessibilityAreDistinct() {
        let states: [SettingsLoadState] = [
            .checking,
            .content,
            .empty("No values"),
            .stale("Showing cached values"),
            .error("Could not load"),
        ]
        XCTAssertEqual(Set(states.map(String.init(describing:))).count, states.count)
        XCTAssertEqual(
            Set(SettingsValueStatus.allTestCases.map(\.accessibilityValue)).count,
            SettingsValueStatus.allTestCases.count
        )
    }

    func testSettingsProportionsStayCompactAtFullScreenWidths() {
        XCTAssertLessThanOrEqual(AppTheme.Layout.settingsContentMaxWidth, 760)
        XCTAssertLessThanOrEqual(AppTheme.Layout.settingsControlWidth, 180)
        XCTAssertLessThan(AppTheme.Layout.settingsRuleEditorHeight, 120)
    }

    func testMemoryFixtureUsesParentOwnedDraftAndExplicitPersistenceBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SettingsView.swift"),
            encoding: .utf8
        )
        let memoryStart = try XCTUnwrap(source.range(of: "private struct MemorySettingsPane"))
        let workflowStart = try XCTUnwrap(
            source.range(
                of: "private struct WorkflowsSettingsPane",
                range: memoryStart.upperBound..<source.endIndex
            )
        )
        let memory = String(source[memoryStart.lowerBound..<workflowStart.lowerBound])

        XCTAssertFalse(memory.contains("@AppStorage"))
        XCTAssertTrue(memory.contains("@Binding var valueState: SettingsValueState<Bool>"))
        XCTAssertTrue(memory.contains("UserDefaults.standard.set(newValue"))
        XCTAssertTrue(memory.contains("valueState.canApply"))
        XCTAssertTrue(memory.contains("SettingsReceiptDisclosure"))
    }
}

private extension SettingsValueStatus {
    static let allTestCases: [SettingsValueStatus] = [
        .draft, .saved, .restartRequired, .live, .unknown,
    ]
}
