import XCTest
@testable import GrokBuild

final class BrowserIntegrationTests: XCTestCase {
    private var savedEnabled: Any?
    private var savedRuntimeMode: Any?
    private var savedCDPURL: Any?
    private var savedProfileName: Any?
    private var savedShowBrowserWindow: Any?
    private var savedExternalBrowserAppID: Any?
    private var savedExternalBrowserAppPath: Any?
    private var savedAutoStartExternalBrowser: Any?
    private var savedAppliedEnabled: Any?
    private var savedAppliedRuntimeMode: Any?
    private var savedAppliedCDPURL: Any?
    private var savedAppliedProfileName: Any?
    private var savedAppliedShowBrowserWindow: Any?
    private var savedAppliedExternalBrowserAppID: Any?
    private var savedAppliedExternalBrowserAppPath: Any?
    private var savedAppliedAutoStartExternalBrowser: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedEnabled = defaults.object(forKey: BrowserSettingsKeys.enabled)
        savedRuntimeMode = defaults.object(forKey: BrowserSettingsKeys.runtimeMode)
        savedCDPURL = defaults.object(forKey: BrowserSettingsKeys.cdpURL)
        savedProfileName = defaults.object(forKey: BrowserSettingsKeys.profileName)
        savedShowBrowserWindow = defaults.object(forKey: BrowserSettingsKeys.showBrowserWindow)
        savedExternalBrowserAppID = defaults.object(forKey: BrowserSettingsKeys.externalBrowserAppID)
        savedExternalBrowserAppPath = defaults.object(forKey: BrowserSettingsKeys.externalBrowserAppPath)
        savedAutoStartExternalBrowser = defaults.object(forKey: BrowserSettingsKeys.autoStartExternalBrowser)
        savedAppliedEnabled = defaults.object(forKey: BrowserSettingsKeys.appliedEnabled)
        savedAppliedRuntimeMode = defaults.object(forKey: BrowserSettingsKeys.appliedRuntimeMode)
        savedAppliedCDPURL = defaults.object(forKey: BrowserSettingsKeys.appliedCDPURL)
        savedAppliedProfileName = defaults.object(forKey: BrowserSettingsKeys.appliedProfileName)
        savedAppliedShowBrowserWindow = defaults.object(forKey: BrowserSettingsKeys.appliedShowBrowserWindow)
        savedAppliedExternalBrowserAppID = defaults.object(forKey: BrowserSettingsKeys.appliedExternalBrowserAppID)
        savedAppliedExternalBrowserAppPath = defaults.object(forKey: BrowserSettingsKeys.appliedExternalBrowserAppPath)
        savedAppliedAutoStartExternalBrowser = defaults.object(forKey: BrowserSettingsKeys.appliedAutoStartExternalBrowser)
    }

    override func tearDown() {
        restore(savedEnabled, forKey: BrowserSettingsKeys.enabled)
        restore(savedRuntimeMode, forKey: BrowserSettingsKeys.runtimeMode)
        restore(savedCDPURL, forKey: BrowserSettingsKeys.cdpURL)
        restore(savedProfileName, forKey: BrowserSettingsKeys.profileName)
        restore(savedShowBrowserWindow, forKey: BrowserSettingsKeys.showBrowserWindow)
        restore(savedExternalBrowserAppID, forKey: BrowserSettingsKeys.externalBrowserAppID)
        restore(savedExternalBrowserAppPath, forKey: BrowserSettingsKeys.externalBrowserAppPath)
        restore(savedAutoStartExternalBrowser, forKey: BrowserSettingsKeys.autoStartExternalBrowser)
        restore(savedAppliedEnabled, forKey: BrowserSettingsKeys.appliedEnabled)
        restore(savedAppliedRuntimeMode, forKey: BrowserSettingsKeys.appliedRuntimeMode)
        restore(savedAppliedCDPURL, forKey: BrowserSettingsKeys.appliedCDPURL)
        restore(savedAppliedProfileName, forKey: BrowserSettingsKeys.appliedProfileName)
        restore(savedAppliedShowBrowserWindow, forKey: BrowserSettingsKeys.appliedShowBrowserWindow)
        restore(savedAppliedExternalBrowserAppID, forKey: BrowserSettingsKeys.appliedExternalBrowserAppID)
        restore(savedAppliedExternalBrowserAppPath, forKey: BrowserSettingsKeys.appliedExternalBrowserAppPath)
        restore(savedAppliedAutoStartExternalBrowser, forKey: BrowserSettingsKeys.appliedAutoStartExternalBrowser)
        super.tearDown()
    }

    func testBrowserSettingsRoundTrip() {
        let settings = BrowserSettings(
            enabled: true,
            runtimeMode: .external,
            cdpURL: "http://127.0.0.1:9222",
            profileName: "project-a",
            showBrowserWindow: true,
            externalBrowserAppID: .brave,
            externalBrowserAppPath: "/Applications/Brave Browser.app",
            autoStartExternalBrowser: false
        )

        BrowserSettingsStore.save(settings)
        XCTAssertEqual(BrowserSettingsStore.load(), settings)
    }

    func testAppliedBrowserSettingsRoundTripSeparately() {
        let current = BrowserSettings(
            enabled: true,
            runtimeMode: .external,
            cdpURL: "http://127.0.0.1:9222",
            profileName: "current",
            showBrowserWindow: true,
            externalBrowserAppID: .edge,
            externalBrowserAppPath: "/Applications/Microsoft Edge.app",
            autoStartExternalBrowser: true
        )
        let applied = BrowserSettings(
            enabled: false,
            runtimeMode: .managed,
            cdpURL: "",
            profileName: "applied",
            showBrowserWindow: false,
            externalBrowserAppID: .arc,
            externalBrowserAppPath: "/Applications/Arc.app",
            autoStartExternalBrowser: false
        )

        BrowserSettingsStore.save(current)
        BrowserSettingsStore.saveApplied(applied)

        XCTAssertEqual(BrowserSettingsStore.load(), current)
        XCTAssertEqual(BrowserSettingsStore.loadApplied(), applied)
    }

    func testMCPServerConfigSerializesForACP() {
        let config = MCPServerConfig(
            name: "grokbuild-browser",
            command: "/tmp/grokbuild-browser-mcp",
            args: ["--stdio"],
            env: ["AGENT_BROWSER_PATH": "/opt/homebrew/bin/agent-browser"]
        )

        let json = config.jsonObject

        XCTAssertEqual(json["name"] as? String, "grokbuild-browser")
        XCTAssertNil(json["type"])
        XCTAssertNil(json["transport"])
        XCTAssertEqual(json["command"] as? String, "/tmp/grokbuild-browser-mcp")
        XCTAssertEqual(json["args"] as? [String], ["--stdio"])

        let env = json["env"] as? [[String: String]]
        XCTAssertEqual(env?.first?["name"], "AGENT_BROWSER_PATH")
        XCTAssertEqual(env?.first?["value"], "/opt/homebrew/bin/agent-browser")
    }

    func testBrowserMCPConfigIncludesHeadedEnvironmentWhenEnabled() throws {
        let settings = BrowserSettings(
            enabled: true,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: true
        )

        let config = try XCTUnwrap(AgentBrowserService.browserMCPConfig(settings: settings))
        let env = try XCTUnwrap(config.jsonObject["env"] as? [[String: String]])

        XCTAssertTrue(env.contains { entry in
            entry["name"] == "AGENT_BROWSER_HEADED" && entry["value"] == "true"
        })
    }

    func testBrowserMCPConfigUsesDefaultCDPURLInExternalMode() throws {
        let settings = BrowserSettings(
            enabled: true,
            runtimeMode: .external,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        let config = try XCTUnwrap(AgentBrowserService.browserMCPConfig(settings: settings))
        let env = try XCTUnwrap(config.jsonObject["env"] as? [[String: String]])

        XCTAssertTrue(env.contains { entry in
            entry["name"] == "GROKBUILD_BROWSER_CDP_URL" && entry["value"] == "http://127.0.0.1:9222"
        })
    }

    func testAgentBrowserCommandPreviewKeepsArguments() {
        let command = AgentBrowserService.commandPreview(["open", "https://example.com"])

        XCTAssertGreaterThanOrEqual(command.count, 3)
        XCTAssertEqual(Array(command.suffix(2)), ["open", "https://example.com"])
    }

    func testExternalBrowserLaunchArgumentsUseCDPPortAndSeparateProfile() {
        let settings = BrowserSettings(
            enabled: true,
            cdpURL: "http://127.0.0.1:9333",
            profileName: "",
            showBrowserWindow: false,
            externalBrowserAppID: .chrome,
            externalBrowserAppPath: "",
            autoStartExternalBrowser: true
        )

        let args = AgentBrowserService.externalBrowserLaunchArguments(settings: settings)

        XCTAssertTrue(args.contains("--remote-debugging-port=9333"))
        XCTAssertTrue(args.contains { $0.hasPrefix("--user-data-dir=") && $0.contains("GrokBuild/BrowserProfiles/chrome") })
        XCTAssertTrue(args.contains("--no-first-run"))
    }

    func testExternalBrowserInstalledChoicesAlwaysIncludeCustom() {
        XCTAssertTrue(ExternalBrowserAppID.installedChoices.contains(.custom))
        XCTAssertFalse(ExternalBrowserAppID.installedChoices.contains { app in
            app != .custom && app.defaultAppURL == nil
        })
    }

    func testBrowserSkillInstallerCopiesBundledSkillWhenEnabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let settings = BrowserSettings(
            enabled: true,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        try BrowserSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        let installedSkill = BrowserSkillInstaller.skillURL(inSkillsRoot: skillsRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedSkill.path))
        let contents = try String(contentsOf: installedSkill, encoding: .utf8)
        XCTAssertTrue(contents.contains("GrokBuild Browser Control"))
    }

    func testBrowserSkillInstallerDoesNothingWhenDisabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let settings = BrowserSettings(
            enabled: false,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        try BrowserSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: BrowserSkillInstaller.skillURL(inSkillsRoot: skillsRoot).path))
    }

    func testBrowserSkillInstallerAlsoInstallsGrokWebSkillWhenEnabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        let settings = BrowserSettings(
            enabled: true,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        try BrowserSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        let grokWebSkill = BrowserSkillInstaller.skillURL(named: "grokbuild-grok-web", inSkillsRoot: skillsRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: grokWebSkill.path))
        let contents = try String(contentsOf: grokWebSkill, encoding: .utf8)
        XCTAssertTrue(contents.contains("grok.com Web"))
    }

    func testGrokComBrowserPresetConfiguresExternalChromeWithDedicatedSessionName() {
        let preset = BrowserPreset.grokCom
        let settings = BrowserSettings(
            enabled: true,
            runtimeMode: .managed,
            cdpURL: "",
            profileName: "",
            showBrowserWindow: false
        )

        let applied = preset.applied(to: settings)

        XCTAssertEqual(applied.runtimeMode, .external)
        XCTAssertEqual(applied.externalBrowserAppID, .chrome)
        XCTAssertEqual(applied.cdpURL, "http://127.0.0.1:9222")
        XCTAssertEqual(applied.profileName, "grok-com")
        XCTAssertTrue(applied.showBrowserWindow)
        XCTAssertTrue(applied.autoStartExternalBrowser)
        // Preset must not flip the user's enable toggle.
        XCTAssertEqual(applied.enabled, settings.enabled)
    }

    func testBrowserProbeStartsUnresolvedWithoutSetupControls() {
        let state = BrowserBackendProbeState()

        XCTAssertTrue(state.isUnresolved)
        XCTAssertFalse(state.isChecking)
        XCTAssertNil(state.settledStatus)
        XCTAssertFalse(state.canShowSetupControls)
        XCTAssertNil(state.errorMessage)
    }

    func testBrowserProbeResolvesReadyExactlyOnce() {
        var state = BrowserBackendProbeState()
        let request = state.begin(configurationGeneration: 4)
        let ready = browserStatus(installed: true, ready: true)

        XCTAssertTrue(state.resolve(ready, request: request, currentConfigurationGeneration: 4))
        XCTAssertEqual(state.settledStatus, ready)
        XCTAssertFalse(state.isChecking)
        XCTAssertTrue(state.canShowSetupControls)
        XCTAssertFalse(state.resolve(.unavailable, request: request, currentConfigurationGeneration: 4))
        XCTAssertEqual(state.settledStatus, ready)
    }

    func testBrowserProbeResolvesMissingRuntimeToUnavailable() {
        var state = BrowserBackendProbeState()
        let request = state.begin(configurationGeneration: 0)

        XCTAssertTrue(state.resolve(.unavailable, request: request, currentConfigurationGeneration: 0))
        XCTAssertEqual(state.settledStatus, .unavailable)
        XCTAssertTrue(state.canShowSetupControls)
    }

    func testStaleBrowserProbeCannotOverwriteNewerResult() {
        var state = BrowserBackendProbeState()
        let stale = state.begin(configurationGeneration: 7)
        let current = state.begin(configurationGeneration: 7)
        let ready = browserStatus(installed: true, ready: true)

        XCTAssertTrue(state.resolve(ready, request: current, currentConfigurationGeneration: 7))
        XCTAssertFalse(state.resolve(.unavailable, request: stale, currentConfigurationGeneration: 7))
        XCTAssertEqual(state.settledStatus, ready)
    }

    func testBrowserManualRefreshPreservesSettledStatusWhileCheckingAndOnFailure() {
        struct ProbeError: LocalizedError {
            var errorDescription: String? { String(repeating: "diagnostic failure ", count: 30) }
        }

        var state = BrowserBackendProbeState()
        let initial = state.begin(configurationGeneration: 2)
        let ready = browserStatus(installed: true, ready: true)
        XCTAssertTrue(state.resolve(ready, request: initial, currentConfigurationGeneration: 2))

        let refresh = state.begin(configurationGeneration: 2)
        XCTAssertTrue(state.isChecking)
        XCTAssertEqual(state.settledStatus, ready)
        XCTAssertTrue(state.canShowSetupControls)

        XCTAssertTrue(state.fail(ProbeError(), request: refresh, currentConfigurationGeneration: 2))
        XCTAssertEqual(state.settledStatus, ready)
        XCTAssertFalse(state.isChecking)
        XCTAssertEqual(state.errorMessage?.count, 240)
    }

    func testBrowserProbeCancellationAndGenerationChangeRejectLateResults() {
        var state = BrowserBackendProbeState()
        let hiddenPaneRequest = state.begin(configurationGeneration: 10)
        state.cancel()
        XCTAssertFalse(state.isChecking)
        XCTAssertFalse(
            state.resolve(.unavailable, request: hiddenPaneRequest, currentConfigurationGeneration: 10)
        )

        let oldGeneration = state.begin(configurationGeneration: 10)
        XCTAssertFalse(
            state.resolve(.unavailable, request: oldGeneration, currentConfigurationGeneration: 11)
        )
        XCTAssertNil(state.settledStatus)
    }

    private func browserStatus(installed: Bool, ready: Bool) -> BrowserBackendStatus {
        BrowserBackendStatus(
            isInstalled: installed,
            isReady: ready,
            executablePath: installed ? "/usr/local/bin/agent-browser" : nil,
            version: installed ? "1.2.3" : nil,
            diagnostic: ready ? "Ready" : "Not ready"
        )
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func temporarySkillsRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokBuildTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(".grok")
            .appendingPathComponent("skills")
    }
}
