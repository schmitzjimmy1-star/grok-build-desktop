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

    func testAppSettingsDraftRoundTripsAppearanceAndUpdatePreference() {
        let suite = "grokbuild.tests.appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = AppSettingsDraft.load(defaults: defaults)
        XCTAssertEqual(initial, .defaults)

        defaults.set(false, forKey: UpdateSettingsKeys.autoCheckEnabled)
        defaults.set(GrokBuildAppearance.light.rawValue, forKey: GrokSettingsKeys.appearance)
        let loaded = AppSettingsDraft.load(defaults: defaults)
        XCTAssertFalse(loaded.autoCheckEnabled)
        XCTAssertEqual(loaded.appearance, .light)

        let saved = AppSettingsDraft(autoCheckEnabled: true, appearance: .dark)
        saved.save(to: defaults)
        XCTAssertEqual(AppSettingsDraft.load(defaults: defaults), saved)
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

    func testSliceSixPanesUseSharedDraftStateAndUnmountCancellation() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SettingsView.swift"),
            encoding: .utf8
        )
        let paneNames = [
            "AgentsSettingsPane",
            "CustomModelsSettingsPane",
            "PermissionsSettingsPane",
            "MemorySettingsPane",
            "BrowserSettingsPane",
            "ComputerUseSettingsPane",
        ]
        for pane in paneNames {
            let start = try XCTUnwrap(source.range(of: "private struct \(pane)"))
            let remainder = source[start.lowerBound...]
            let next = remainder.dropFirst().range(of: "\nprivate struct ")?.lowerBound
                ?? remainder.endIndex
            let body = String(remainder[..<next])
            XCTAssertTrue(body.contains("@Binding var valueState"), "\(pane) must receive parent-owned state")
            XCTAssertFalse(body.contains("@AppStorage"), "\(pane) must not persist while a control is edited")
        }

        XCTAssertTrue(source.contains("Hidden panes unmount and"))
        XCTAssertTrue(source.contains("guard !Task.isCancelled else { return }"))
    }

    func testPermissionDraftPersistsOnlyAtExplicitBoundary() {
        let suite = "SettingsTabTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("Could not create isolated defaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        var draft = PermissionSettingsDraft.defaults
        draft.permissionMode = GrokPermissionMode.alwaysApprove.rawValue
        draft.allowRules = "Bash(git *)"
        XCTAssertNil(defaults.object(forKey: GrokSettingsKeys.permissionMode))
        XCTAssertNil(defaults.object(forKey: GrokSettingsKeys.allowRules))

        draft.save(to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: GrokSettingsKeys.permissionMode),
            GrokPermissionMode.alwaysApprove.rawValue
        )
        XCTAssertEqual(defaults.string(forKey: GrokSettingsKeys.allowRules), "Bash(git *)")
    }

    func testComputerUsePaneStateKeepsExternalIntegrationInTheSameDraft() {
        let original = ComputerUsePaneSettings.defaults
        var state = SettingsValueState<ComputerUsePaneSettings>.unloaded(default: original)
        state.load(persisted: original, applied: original, live: nil)

        var changed = original
        changed.settings.includeScreenshots = true
        changed.cursorIntegrationEnabled = true
        state.updateDraft(changed)

        XCTAssertTrue(state.isDirty)
        XCTAssertTrue(state.canApply)
        XCTAssertEqual(state.status, .draft)
        XCTAssertFalse(state.persisted.settings.includeScreenshots)
        XCTAssertFalse(state.persisted.cursorIntegrationEnabled)
    }

    func testSliceSevenPanesUseSharedStateExplicitScopesAndRowReceipts() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SettingsView.swift"),
            encoding: .utf8
        )

        for pane in ["WorkflowsSettingsPane", "CompatibilitySettingsPane", "AppUpdatesSettingsPane"] {
            let body = try paneBody(named: pane, source: source)
            XCTAssertTrue(body.contains("@Binding var valueState"), "\(pane) needs a parent-owned draft")
            XCTAssertTrue(body.contains("SettingsApplyRequest"), "\(pane) needs an explicit Apply request")
            XCTAssertFalse(body.contains("@AppStorage"), "\(pane) cannot mutate persistence from a control")
        }

        for pane in ["MCPSettingsPane", "SkillsSettingsPane", "PluginsSettingsPane", "MarketplaceSettingsPane", "HooksSettingsPane"] {
            let body = try paneBody(named: pane, source: source)
            XCTAssertTrue(body.contains("SettingsInventoryState"), "\(pane) needs retained load/stale/error state")
        }

        for pane in ["MCPSettingsPane", "PluginsSettingsPane", "MarketplaceSettingsPane"] {
            let body = try paneBody(named: pane, source: source)
            XCTAssertTrue(body.contains("SettingsRowOperationReceipt"), "\(pane) needs row-local operation receipts")
            XCTAssertTrue(body.contains("operationTask?.cancel()"), "\(pane) must cancel hidden-pane work")
            XCTAssertTrue(body.contains("activeTabRestart"), "\(pane) must declare current-tab restart scope")
        }

        let marketplace = try paneBody(named: "MarketplaceSettingsPane", source: source)
        XCTAssertTrue(marketplace.contains("trustedPluginIDs.contains"))
        XCTAssertTrue(marketplace.contains("I reviewed and trust"))

        let mcp = try paneBody(named: "MCPSettingsPane", source: source)
        XCTAssertTrue(mcp.contains("@Binding var draft: GrokMCPServerDraft"))
        XCTAssertTrue(mcp.contains("Structured server draft"))
        XCTAssertTrue(mcp.contains("SecureField"))
        XCTAssertTrue(mcp.contains("Literal secret storage"))
        XCTAssertFalse(mcp.contains("split(separator: \" \""))

        let compatibility = try paneBody(named: "CompatibilitySettingsPane", source: source)
        XCTAssertFalse(compatibility.contains("try? await service.listExternalCompat"))
        XCTAssertTrue(compatibility.contains("Codex currently exposes sessions only"))
    }

    private func paneBody(named pane: String, source: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: "private struct \(pane)"))
        let remainder = source[start.lowerBound...]
        let next = remainder.dropFirst().range(of: "\nprivate struct ")?.lowerBound
            ?? remainder.endIndex
        return String(remainder[..<next])
    }
}

private extension SettingsValueStatus {
    static let allTestCases: [SettingsValueStatus] = [
        .draft, .saved, .restartRequired, .live, .unknown,
    ]
}
