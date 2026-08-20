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

    func testSettingsTabsExposeStableAccessibilityIdentifiers() {
        let identifiers = SettingsTab.allCases.map(\.accessibilityIdentifier)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
        XCTAssertEqual(SettingsTab.app.accessibilityIdentifier, "grok-settings-tab-app")
        XCTAssertEqual(
            SettingsTab.computerUse.accessibilityIdentifier,
            "grok-settings-tab-computerUse"
        )
        for tab in SettingsTab.allCases {
            XCTAssertEqual(tab.accessibilityIdentifier, "grok-settings-tab-\(tab.rawValue)")
        }
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
            mcpGatewayEnabled: false,
            observedCLIConfiguredMCPServerNames: [],
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

    func testFrontendRebuildDefaultsNewInstallsToDarkWithoutOverridingExplicitState() {
        let freshSuite = "grokbuild.tests.appearance.fresh.\(UUID().uuidString)"
        let freshDefaults = UserDefaults(suiteName: freshSuite)!
        defer { freshDefaults.removePersistentDomain(forName: freshSuite) }

        XCTAssertEqual(GrokBuildAppearance.load(defaults: freshDefaults), .dark)
        AppAppearanceMigration.run(defaults: freshDefaults)
        XCTAssertEqual(GrokBuildAppearance.load(defaults: freshDefaults), .dark)

        let existingSuite = "grokbuild.tests.appearance.existing.\(UUID().uuidString)"
        let existingDefaults = UserDefaults(suiteName: existingSuite)!
        defer { existingDefaults.removePersistentDomain(forName: existingSuite) }
        existingDefaults.set(GrokBuildAppearance.light.rawValue, forKey: GrokSettingsKeys.appearance)

        AppAppearanceMigration.run(defaults: existingDefaults)
        XCTAssertEqual(GrokBuildAppearance.load(defaults: existingDefaults), .light)
    }

    func testAppearanceChoicesUseIndependentAccessibleButtons() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try paneSource(named: "AppUpdatesSettingsPane")
        let appearanceStart = try XCTUnwrap(source.range(of: "updatesCard(title: \"Appearance\""))
        let applyStart = try XCTUnwrap(
            source.range(
                of: "SettingsApplyBar(",
                range: appearanceStart.upperBound..<source.endIndex
            )
        )
        let appearance = String(source[appearanceStart.lowerBound..<applyStart.lowerBound])

        XCTAssertFalse(appearance.contains("pickerStyle(.segmented)"))
        XCTAssertTrue(source.contains("ForEach(GrokBuildAppearance.allCases)"))
        XCTAssertTrue(source.contains("grok-appearance-\" + option.rawValue"))
        XCTAssertTrue(source.contains("accessibilityAddTraits"))
        XCTAssertTrue(source.contains("Image(systemName: \"checkmark\")"))
    }

    func testAppThemeDarkShellAndOriginalLightCanvasStayDistinct() {
        let light = NSAppearance(named: .aqua)!
        let dark = NSAppearance(named: .darkAqua)!
        let canvasLight = sRGBComponents(of: AppTheme.Palette.canvasNSColor, appearance: light)
        let sidebarLight = sRGBComponents(of: AppTheme.Palette.sidebarNSColor, appearance: light)
        let canvasDark = sRGBComponents(of: AppTheme.Palette.canvasNSColor, appearance: dark)
        let sidebarDark = sRGBComponents(of: AppTheme.Palette.sidebarNSColor, appearance: dark)
        let accentLight = sRGBComponents(of: AppTheme.Palette.accentNSColor, appearance: light)
        let linkLight = sRGBComponents(of: AppTheme.Palette.linkNSColor, appearance: light)

        XCTAssertGreaterThan(canvasLight.r, 0.97, "Light canvas is the near-white design authority")
        XCTAssertLessThan(sidebarLight.r, canvasLight.r, "Project rail must separate from the canvas")
        XCTAssertGreaterThanOrEqual(canvasLight.b, canvasLight.r - 0.001,
                                    "Light canvas must not keep a warm/cream blue deficit")
        XCTAssertGreaterThanOrEqual(sidebarLight.b, sidebarLight.r - 0.001,
                                    "Light sidebar must not keep a warm/cream blue deficit")
        XCTAssertGreaterThan(canvasDark.b, canvasDark.r,
                             "Dark canvas keeps a cool bias so charcoal does not read brown")
        XCTAssertGreaterThan(sidebarDark.r, canvasDark.r + 0.05,
                             "Dark rail is the lighter cool charcoal beside the black canvas")
        XCTAssertGreaterThan(sidebarDark.b, sidebarDark.r,
                             "Dark rail keeps a cool gray bias")
        XCTAssertNotEqual(AppTheme.Palette.warningNSColor, AppTheme.Palette.linkNSColor)
        XCTAssertGreaterThan(accentLight.b, accentLight.r + 0.35,
                             "Primary actions use the restrained blue rebuild accent")
        XCTAssertGreaterThan(linkLight.b, linkLight.r + 0.35,
                             "Links remain blue rather than inheriting neutral chrome")
        XCTAssertGreaterThanOrEqual(
            contrastRatio(accentLight, (r: 1, g: 1, b: 1)),
            4.5,
            "White primary-action labels must keep WCAG AA contrast on the rebuild blue"
        )
        _ = AppTheme.Palette.warning
        _ = AppTheme.Palette.link

        let titlebarDark = sRGBComponents(of: AppTheme.Palette.titlebarControlNSColor, appearance: dark)
        let titlebarLight = sRGBComponents(of: AppTheme.Palette.titlebarControlNSColor, appearance: light)
        XCTAssertGreaterThan(titlebarDark.r, canvasDark.r + 0.5,
                             "Dark titlebar icons must stay well above the charcoal canvas")
        XCTAssertLessThan(titlebarLight.r, canvasLight.r - 0.5,
                          "Light titlebar icons must stay well below the stone canvas")
    }

    func testAppThemeWarningAndLinkTokensExistInSource() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/AppTheme.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("static let warning"))
        XCTAssertTrue(source.contains("static let link"))
        XCTAssertTrue(source.contains("static let warningNSColor"))
        XCTAssertTrue(source.contains("static let linkNSColor"))
        XCTAssertTrue(source.contains("static let titlebarControl"))
        XCTAssertTrue(source.contains("static let titlebarControlNSColor"))
        XCTAssertTrue(source.contains("struct TitlebarGlyph"))
        XCTAssertTrue(source.contains("enum TitlebarGlyphRaster"))
        XCTAssertTrue(source.contains("rect.fill(using: .sourceIn)"))
        XCTAssertTrue(source.contains("tiffRepresentation"))
        XCTAssertTrue(source.contains("image.isTemplate = false"))

        let dark = NSAppearance(named: .darkAqua)!
        let glyph = TitlebarGlyphRaster.image(
            systemName: "ellipsis",
            pointSize: 13,
            color: AppTheme.Palette.titlebarControlNSColor,
            appearance: dark
        )
        XCTAssertFalse(glyph.isTemplate, "titlebar glyphs must not be AppKit templates")
        XCTAssertGreaterThan(
            brightestOpaqueLuma(in: glyph),
            0.7,
            "Dark titlebar glyphs must stay visibly lighter than the charcoal canvas"
        )
    }

    private func brightestOpaqueLuma(in image: NSImage) -> CGFloat {
        let width = max(Int(image.size.width * 2), 1)
        let height = max(Int(image.size.height * 2), 1)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return 0
        }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return 0 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        var brightest: CGFloat = 0
        for y in 0..<height {
            for x in 0..<width {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.25 else { continue }
                let luma = (0.2126 * color.redComponent)
                    + (0.7152 * color.greenComponent)
                    + (0.0722 * color.blueComponent)
                brightest = max(brightest, luma)
            }
        }
        return brightest
    }

    private func sRGBComponents(of color: NSColor, appearance: NSAppearance) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            color.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        return (r, g, b)
    }

    private func contrastRatio(
        _ lhs: (r: CGFloat, g: CGFloat, b: CGFloat),
        _ rhs: (r: CGFloat, g: CGFloat, b: CGFloat)
    ) -> CGFloat {
        let brighter = max(relativeLuminance(lhs), relativeLuminance(rhs))
        let darker = min(relativeLuminance(lhs), relativeLuminance(rhs))
        return (brighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: (r: CGFloat, g: CGFloat, b: CGFloat)) -> CGFloat {
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * linear(color.r))
            + (0.7152 * linear(color.g))
            + (0.0722 * linear(color.b))
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
        // The Memory pane's own file is the exact contract scope now.
        let memory = try paneSource(named: "MemorySettingsPane")

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
        let paneNames = [
            "AgentsSettingsPane",
            "CustomModelsSettingsPane",
            "PermissionsSettingsPane",
            "MemorySettingsPane",
            "BrowserSettingsPane",
            "ComputerUseSettingsPane",
        ]
        for pane in paneNames {
            let body = try paneSource(named: pane)
            XCTAssertTrue(body.contains("struct \(pane)"))
            XCTAssertTrue(body.contains("@Binding var valueState"), "\(pane) must receive parent-owned state")
            XCTAssertFalse(body.contains("@AppStorage"), "\(pane) must not persist while a control is edited")
        }

        let shell = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SettingsView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(shell.contains("Hidden panes unmount and"))
        XCTAssertTrue(try paneSource(named: "AppUpdatesSettingsPane")
            .contains("guard !Task.isCancelled else { return }"))
    }

    func testBrowserPaneUsesUnresolvedGenerationBoundProbePresentation() throws {
        let browser = try paneSource(named: "BrowserSettingsPane")

        XCTAssertTrue(browser.contains("@State private var probeState = BrowserBackendProbeState()"))
        XCTAssertFalse(browser.contains("@State private var status = BrowserBackendStatus.unavailable"))
        XCTAssertTrue(browser.contains("Checking browser support…"))
        XCTAssertTrue(browser.contains("probeState.canShowSetupControls"))
        XCTAssertTrue(browser.contains("statusProbeTask?.cancel()"))
        XCTAssertTrue(browser.contains(".onChange(of: valueState.configurationGeneration)"))
        XCTAssertTrue(browser.contains("currentConfigurationGeneration: valueState.configurationGeneration"))
    }

    func testComputerUseSelfTestKeepsRawReceiptBehindDiagnostics() throws {
        let pane = try paneSource(named: "ComputerUseSettingsPane")

        XCTAssertTrue(pane.contains("Text(endToEndResult.compactDetail)"))
        XCTAssertFalse(pane.contains("Text(endToEndResult.detail)"))
        XCTAssertTrue(pane.contains("Text(endToEndResult.diagnostic)"))
        XCTAssertTrue(pane.contains("Show diagnostics"))
        XCTAssertTrue(pane.contains("if let endToEndResult, !endToEndResult.diagnostic.isEmpty"))
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

    func testPersistenceReconciliationCanPreserveADifferentDraft() {
        var state = SettingsValueState<String>.unloaded(default: "removed-model")
        state.load(persisted: "removed-model", applied: "removed-model", live: nil)
        state.updateDraft("replacement-model")

        state.reconcilePersisted("", preservingDraft: "replacement-model")

        XCTAssertEqual(state.persisted, "")
        XCTAssertEqual(state.applied, "")
        XCTAssertEqual(state.draft, "replacement-model")
        XCTAssertTrue(state.isDirty)
        XCTAssertEqual(state.configurationGeneration, 1)
    }

    func testSliceSevenPanesUseSharedStateExplicitScopesAndRowReceipts() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = ""

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

    /// Slice 10: each pane lives in its own file under Views/Settings, so a pane's
    /// "body" for contract scanning is that whole file — a stricter scope than the old
    /// next-struct slicing inside the monolithic SettingsView.swift.
    private func paneSource(named pane: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/Settings/\(pane).swift"),
            encoding: .utf8
        )
    }

    private func paneBody(named pane: String, source: String) throws -> String {
        try paneSource(named: pane)
    }
}

private extension SettingsValueStatus {
    static let allTestCases: [SettingsValueStatus] = [
        .draft, .saved, .restartRequired, .live, .unknown,
    ]
}
