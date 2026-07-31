import XCTest
@testable import GrokBuild

final class ComputerUseIntegrationTests: XCTestCase {
    private var savedValues: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for key in allKeys {
            savedValues[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    override func tearDown() {
        for key in allKeys {
            restore(savedValues[key] ?? nil, forKey: key)
        }
        super.tearDown()
    }

    func testComputerUseSettingsRoundTrip() {
        let settings = ComputerUseSettings(
            enabled: true,
            backend: .agentDesktop,
            permissionPolicy: .auto,
            commandTimeoutSeconds: 90,
            includeScreenshots: true
        )

        ComputerUseSettingsStore.save(settings)

        XCTAssertEqual(ComputerUseSettingsStore.load(), settings)
    }

    /// The removed "ask" policy (never enforced by the helper) must decode as
    /// auto so upgrading users keep working settings.
    func testLegacyAskPolicyFallsBackToAuto() {
        UserDefaults.standard.set("ask", forKey: ComputerUseSettingsKeys.permissionPolicy)
        XCTAssertEqual(ComputerUseSettingsStore.load().permissionPolicy, .auto)
    }

    func testAppliedComputerUseSettingsRoundTripSeparately() {
        let current = ComputerUseSettings(
            enabled: true,
            backend: .agentDesktop,
            permissionPolicy: .auto,
            commandTimeoutSeconds: 30,
            includeScreenshots: false
        )
        let applied = ComputerUseSettings(
            enabled: false,
            backend: .agentDesktop,
            permissionPolicy: .deny,
            commandTimeoutSeconds: 15,
            includeScreenshots: true
        )

        ComputerUseSettingsStore.save(current)
        ComputerUseSettingsStore.saveApplied(applied)

        XCTAssertEqual(ComputerUseSettingsStore.load(), current)
        XCTAssertEqual(ComputerUseSettingsStore.loadApplied(), applied)
    }

    func testComputerUseMCPConfigSerializesForACP() throws {
        let helper = URL(fileURLWithPath: "/tmp/GrokBuildComputerUseMCP")
        let agentDesktop = URL(fileURLWithPath: "/opt/homebrew/bin/agent-desktop")
        let settings = ComputerUseSettings(
            enabled: true,
            backend: .agentDesktop,
            permissionPolicy: .auto,
            commandTimeoutSeconds: 25,
            includeScreenshots: true
        )

        let config = try XCTUnwrap(ComputerUseService.computerUseMCPConfig(
            settings: settings,
            helperOverride: helper,
            agentDesktopOverride: agentDesktop
        ))
        let json = config.jsonObject

        XCTAssertEqual(json["name"] as? String, "grokbuild-computer-use")
        XCTAssertNil(json["type"])
        XCTAssertNil(json["transport"])
        XCTAssertEqual(json["command"] as? String, helper.path)
        XCTAssertEqual(json["args"] as? [String], [])

        let env = try XCTUnwrap(json["env"] as? [[String: String]])
        XCTAssertTrue(env.contains { $0["name"] == "AGENT_DESKTOP_PATH" && $0["value"] == agentDesktop.path })
        XCTAssertTrue(env.contains { $0["name"] == "GROKBUILD_COMPUTER_USE_POLICY" && $0["value"] == "auto" })
        XCTAssertTrue(env.contains { $0["name"] == "GROKBUILD_COMPUTER_USE_SCREENSHOTS" && $0["value"] == "true" })
    }

    /// The app must send exactly the env the helper reads (main.swift):
    /// AGENT_DESKTOP_PATH + POLICY + TIMEOUT + SCREENSHOTS. A key on either
    /// side that the other does not know is a dead control or a dead read.
    func testMCPConfigEnvMatchesHelperReadSet() throws {
        let settings = ComputerUseSettings(
            enabled: true,
            backend: .agentDesktop,
            permissionPolicy: .deny,
            commandTimeoutSeconds: 45,
            includeScreenshots: false
        )
        let config = try XCTUnwrap(ComputerUseService.computerUseMCPConfig(
            settings: settings,
            helperOverride: URL(fileURLWithPath: "/tmp/GrokBuildComputerUseMCP"),
            agentDesktopOverride: URL(fileURLWithPath: "/tmp/agent-desktop")
        ))
        let env = try XCTUnwrap(config.jsonObject["env"] as? [[String: String]])
        let keys = Set(env.compactMap { $0["name"] })
        XCTAssertEqual(keys, [
            "AGENT_DESKTOP_PATH",
            "GROKBUILD_COMPUTER_USE_POLICY",
            "GROKBUILD_COMPUTER_USE_TIMEOUT",
            "GROKBUILD_COMPUTER_USE_SCREENSHOTS",
        ])
    }

    func testComputerUseMCPConfigDisabledReturnsNil() {
        let settings = ComputerUseSettings.defaults

        XCTAssertNil(ComputerUseService.computerUseMCPConfig(
            settings: settings,
            helperOverride: URL(fileURLWithPath: "/tmp/GrokBuildComputerUseMCP")
        ))
    }

    func testPermissionDiagnosticsParseStructuredJSON() {
        let status = ComputerUseService.parsePermissions("""
        {"accessibility":{"state":"granted"},"screen_recording":{"state":"denied"}}
        """)

        XCTAssertEqual(status.accessibility, "granted")
        XCTAssertEqual(status.screenRecording, "denied")
        XCTAssertTrue(status.isReady(includeScreenshots: false))
        XCTAssertFalse(status.isReady(includeScreenshots: true))
    }

    func testPermissionDiagnosticsParseAgentDesktopEnvelope() {
        let status = ComputerUseService.parsePermissions("""
        {"command":"permissions","data":{"accessibility":{"state":"granted"},"screen_recording":{"state":"denied"}},"ok":true,"version":"2.0"}
        """)

        XCTAssertEqual(status.accessibility, "granted")
        XCTAssertEqual(status.screenRecording, "denied")
        XCTAssertTrue(status.isReady(includeScreenshots: false))
        XCTAssertFalse(status.isReady(includeScreenshots: true))
    }

    func testPermissionDiagnosticsParseAgentDesktopV1GrantedFlag() {
        let status = ComputerUseService.parsePermissions("""
        {"command":"permissions","data":{"granted":true},"ok":true,"version":"1.0"}
        """)

        XCTAssertEqual(status.accessibility, "granted")
        XCTAssertEqual(status.screenRecording, "not reported")
        XCTAssertTrue(status.isReady(includeScreenshots: false))
    }

    func testPermissionDiagnosticsParseAgentDesktopV1DeniedFlag() {
        let status = ComputerUseService.parsePermissions("""
        {"command":"permissions","data":{"granted":false,"suggestion":"Open System Settings > Privacy & Security > Accessibility and add your terminal application"},"ok":true,"version":"1.0"}
        """)

        XCTAssertEqual(status.accessibility, "denied")
        XCTAssertEqual(status.screenRecording, "not reported")
        XCTAssertFalse(status.isReady(includeScreenshots: false))
        XCTAssertEqual(
            status.guidance,
            "Open System Settings → Privacy & Security → Accessibility and enable \(ComputerUseService.hostAppName)."
        )
        XCTAssertFalse(status.guidance?.localizedCaseInsensitiveContains("terminal") ?? true)
    }

    func testRewritePermissionSuggestionReplacesTerminalWording() {
        let guidance = ComputerUseService.rewritePermissionSuggestion(
            "Open System Settings > Privacy & Security > Accessibility and add your terminal application",
            appName: "GrokBuild"
        )

        XCTAssertEqual(
            guidance,
            "Open System Settings → Privacy & Security → Accessibility and enable GrokBuild."
        )
    }

    /// With an EXTERNAL agent-desktop (no bundled copy in the test bundle),
    /// GrokBuild's own Accessibility grant must NOT mask the actuator's
    /// denial — the old OR-chain reported "Ready" here and the first real
    /// click failed.
    func testExternalAgentDesktopDenialIsNotMaskedByGrokBuildGrant() {
        let cliStatus = ComputerUsePermissionStatus(
            accessibility: "denied",
            screenRecording: "not reported",
            diagnostic: #"{"granted":false}"#,
            guidance: "Enable GrokBuild."
        )

        let resolved = ComputerUseService.resolvePermissionStatus(
            cliStatus: cliStatus,
            grokBuildGranted: true,
            probe: nil,
            grokBuildScreenRecordingGranted: false
        )

        XCTAssertEqual(resolved.accessibility, "denied")
        XCTAssertFalse(resolved.isReady(includeScreenshots: false))
        XCTAssertNotNil(resolved.guidance)
        XCTAssertTrue(resolved.diagnostic.contains("GrokBuild Accessibility: granted"))
    }

    /// Helper trust is diagnostic only: the helper never touches AX APIs
    /// itself, so its grant cannot make an external agent-desktop ready.
    func testExternalAgentDesktopDenialIsNotMaskedByHelperGrant() {
        let cliStatus = ComputerUsePermissionStatus(
            accessibility: "denied",
            screenRecording: "not reported",
            diagnostic: #"{"granted":false}"#,
            guidance: "Enable GrokBuild."
        )
        let probe = AccessibilityTrustProbe(
            helperGranted: true,
            agentDesktopGranted: false,
            helperExecutablePath: "/tmp/GrokBuildComputerUseMCP",
            agentDesktopOutput: #"{"granted":false}"#,
            probeError: nil
        )

        let resolved = ComputerUseService.resolvePermissionStatus(
            cliStatus: cliStatus,
            grokBuildGranted: false,
            probe: probe,
            grokBuildScreenRecordingGranted: false
        )

        XCTAssertEqual(resolved.accessibility, "denied")
        XCTAssertFalse(resolved.isReady(includeScreenshots: false))
        XCTAssertTrue(resolved.diagnostic.contains("Helper Accessibility: granted"))
    }

    /// Screenshots enabled + known Screen Recording denial blocks readiness
    /// even when Accessibility is granted; unknown state does not block.
    func testReadinessAccountsForScreenRecordingWhenScreenshotsEnabled() {
        let denied = ComputerUsePermissionStatus(
            accessibility: "granted",
            screenRecording: "denied",
            diagnostic: "",
            guidance: nil
        )
        XCTAssertTrue(denied.isReady(includeScreenshots: false))
        XCTAssertFalse(denied.isReady(includeScreenshots: true))

        let unknown = ComputerUsePermissionStatus(
            accessibility: "granted",
            screenRecording: "not reported",
            diagnostic: "",
            guidance: nil
        )
        XCTAssertTrue(unknown.isReady(includeScreenshots: true))
    }

    func testResolvePermissionStatusUsesAgentDesktopAccessibility() {
        let cliStatus = ComputerUsePermissionStatus(
            accessibility: "denied",
            screenRecording: "not reported",
            diagnostic: #"{"granted":false}"#,
            guidance: nil
        )
        let probe = AccessibilityTrustProbe(
            helperGranted: false,
            agentDesktopGranted: true,
            helperExecutablePath: "/tmp/GrokBuildComputerUseMCP",
            agentDesktopOutput: #"{"granted":true}"#,
            probeError: nil
        )

        let resolved = ComputerUseService.resolvePermissionStatus(
            cliStatus: cliStatus,
            grokBuildGranted: false,
            probe: probe,
            grokBuildScreenRecordingGranted: false
        )

        XCTAssertEqual(resolved.accessibility, "granted")
        XCTAssertTrue(resolved.isReady(includeScreenshots: false))
    }

    func testParseAccessibilityTrustProbeReadsHelperJSON() {
        let probe = ComputerUseService.parseAccessibilityTrustProbe("""
        {"ok":true,"helper_accessibility_granted":true,"helper_executable":"/tmp/helper","agent_desktop_granted":false,"agent_desktop_output":"{\\"granted\\":false}"}
        """)

        XCTAssertEqual(probe?.helperGranted, true)
        XCTAssertEqual(probe?.agentDesktopGranted, false)
        XCTAssertEqual(probe?.helperExecutablePath, "/tmp/helper")
    }

    func testResolvedStatusKeepsCLIDenialWhenNothingIsGranted() {
        let cliStatus = ComputerUsePermissionStatus(
            accessibility: "denied",
            screenRecording: "not reported",
            diagnostic: #"{"granted":false}"#,
            guidance: "Enable GrokBuild."
        )

        let resolved = ComputerUseService.resolvePermissionStatus(
            cliStatus: cliStatus,
            grokBuildGranted: false,
            probe: nil,
            grokBuildScreenRecordingGranted: false
        )

        XCTAssertEqual(resolved.accessibility, "denied")
        XCTAssertFalse(resolved.isReady(includeScreenshots: false))
        XCTAssertNotNil(resolved.guidance)
        XCTAssertTrue(resolved.guidance?.localizedCaseInsensitiveContains("accessibility") ?? false)
    }

    func testVersionParserUsesAgentDesktopDataVersion() {
        let version = ComputerUseService.parseVersion("""
        {"command":"version","data":{"os":"macos","target":"aarch64","version":"0.3.1"},"ok":true,"version":"2.0"}
        """)

        XCTAssertEqual(version, "0.3.1")
    }

    func testComputerUseSkillInstallerCopiesBundledSkillWhenEnabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        var settings = ComputerUseSettings.defaults
        settings.enabled = true

        try ComputerUseSkillInstaller.installIfNeeded(settings: settings, skillsRoot: skillsRoot)

        let installedSkill = ComputerUseSkillInstaller.skillURL(inSkillsRoot: skillsRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedSkill.path))
        let contents = try String(contentsOf: installedSkill, encoding: .utf8)
        XCTAssertTrue(contents.contains("GrokBuild Computer Use"))
    }

    func testComputerUseSkillInstallerDoesNothingWhenDisabled() throws {
        let skillsRoot = temporarySkillsRootURL()
        defer { try? FileManager.default.removeItem(at: skillsRoot) }

        try ComputerUseSkillInstaller.installIfNeeded(settings: .defaults, skillsRoot: skillsRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: ComputerUseSkillInstaller.skillURL(inSkillsRoot: skillsRoot).path))
    }

    func testCursorInstallerCopiesBinariesAndUpdatesMCPConfig() throws {
        let root = temporaryInstallRootURL()
        let mcpURL = root.appendingPathComponent("mcp.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let helper = try makeTemporaryExecutable(named: "GrokBuildComputerUseMCP")
        let agentDesktop = try makeTemporaryExecutable(named: "agent-desktop")
        defer {
            try? FileManager.default.removeItem(at: helper.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: agentDesktop.deletingLastPathComponent())
        }

        var settings = ComputerUseSettings.defaults
        settings.permissionPolicy = .auto
        settings.includeScreenshots = true

        let output = try ComputerUseCursorInstaller.install(
            settings: settings,
            installRoot: root.appendingPathComponent("computer-use"),
            cursorMCPConfigURL: mcpURL,
            helperOverride: helper,
            agentDesktopOverride: agentDesktop
        )

        XCTAssertTrue(output.contains("Installed Computer Use for Cursor."))
        let status = ComputerUseCursorInstaller.status(
            installRoot: root.appendingPathComponent("computer-use"),
            cursorMCPConfigURL: mcpURL
        )
        XCTAssertTrue(status.isInstalled)
        XCTAssertTrue(status.helperInstalled)
        XCTAssertTrue(status.agentDesktopInstalled)
        XCTAssertTrue(status.mcpEntryConfigured)

        let entry = try XCTUnwrap(ComputerUseCursorInstaller.mcpEntry(in: mcpURL))
        XCTAssertEqual(entry["command"] as? String, status.helperPath)
        let env = try XCTUnwrap(entry["env"] as? [String: String])
        XCTAssertEqual(env["AGENT_DESKTOP_PATH"], status.agentDesktopPath)
        XCTAssertEqual(env["GROKBUILD_COMPUTER_USE_POLICY"], "auto")
        XCTAssertEqual(env["GROKBUILD_COMPUTER_USE_SCREENSHOTS"], "true")
        XCTAssertNil(env["GROKBUILD_COMPUTER_USE_SESSION"], "removed control must not be exported")
    }

    func testCursorInstallerMergePreservesExistingMCPServers() throws {
        let root = temporaryInstallRootURL()
        let mcpURL = root.appendingPathComponent("mcp.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let existing: [String: Any] = [
            "mcpServers": [
                "context7": [
                    "type": "http",
                    "url": "https://example.com/mcp"
                ]
            ],
            "inputs": [
                ["id": "example", "type": "promptString"]
            ]
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted])
        try existingData.write(to: mcpURL)

        let helperDirectory = temporaryInstallRootURL()
        let agentDesktopDirectory = temporaryInstallRootURL()
        defer {
            try? FileManager.default.removeItem(at: helperDirectory)
            try? FileManager.default.removeItem(at: agentDesktopDirectory)
        }

        try FileManager.default.createDirectory(at: helperDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agentDesktopDirectory, withIntermediateDirectories: true)

        let helper = helperDirectory.appendingPathComponent("GrokBuildComputerUseMCP")
        let agentDesktop = agentDesktopDirectory.appendingPathComponent("agent-desktop")
        FileManager.default.createFile(atPath: helper.path, contents: Data("#!/bin/sh\n".utf8))
        FileManager.default.createFile(atPath: agentDesktop.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: agentDesktop.path)

        _ = try ComputerUseCursorInstaller.install(
            installRoot: root.appendingPathComponent("computer-use"),
            cursorMCPConfigURL: mcpURL,
            helperOverride: helper,
            agentDesktopOverride: agentDesktop
        )

        let data = try Data(contentsOf: mcpURL)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(parsed["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["context7"])
        XCTAssertNotNil(servers[ComputerUseCursorInstaller.mcpServerName])
        XCTAssertNotNil(parsed["inputs"])
    }

    func testCursorInstallerUninstallRemovesEntryAndFiles() throws {
        let root = temporaryInstallRootURL()
        let mcpURL = root.appendingPathComponent("mcp.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let helper = try makeTemporaryExecutable(named: "GrokBuildComputerUseMCP")
        let agentDesktop = try makeTemporaryExecutable(named: "agent-desktop")
        defer {
            try? FileManager.default.removeItem(at: helper.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: agentDesktop.deletingLastPathComponent())
        }

        let installRoot = root.appendingPathComponent("computer-use")
        _ = try ComputerUseCursorInstaller.install(
            installRoot: installRoot,
            cursorMCPConfigURL: mcpURL,
            helperOverride: helper,
            agentDesktopOverride: agentDesktop
        )

        let output = try ComputerUseCursorInstaller.uninstall(
            installRoot: installRoot,
            cursorMCPConfigURL: mcpURL
        )

        XCTAssertTrue(output.contains("Removed `\(ComputerUseCursorInstaller.mcpServerName)`"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installRoot.path))
        XCTAssertNil(ComputerUseCursorInstaller.mcpEntry(in: mcpURL))
    }

    func testSaveAppliedCursorEnvironmentUpdatesAppliedPrefixOnly() {
        var current = ComputerUseSettings.defaults
        current.includeScreenshots = true
        current.commandTimeoutSeconds = 45
        ComputerUseSettingsStore.save(current)
        ComputerUseSettingsStore.saveApplied(.defaults)

        ComputerUseSettingsStore.saveAppliedCursorEnvironment(from: current)

        XCTAssertEqual(ComputerUseSettingsStore.load().includeScreenshots, true)
        XCTAssertEqual(ComputerUseSettingsStore.loadApplied().includeScreenshots, true)
        XCTAssertEqual(ComputerUseSettingsStore.loadApplied().commandTimeoutSeconds, 45)
        XCTAssertEqual(ComputerUseSettingsStore.loadApplied().enabled, false)
    }

    func testCursorInstallerUpdateConfigurationChangesEnvWithoutReinstallingBinaries() throws {
        let root = temporaryInstallRootURL()
        let mcpURL = root.appendingPathComponent("mcp.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let helper = try makeTemporaryExecutable(named: "GrokBuildComputerUseMCP")
        let agentDesktop = try makeTemporaryExecutable(named: "agent-desktop")
        defer {
            try? FileManager.default.removeItem(at: helper.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: agentDesktop.deletingLastPathComponent())
        }

        let installRoot = root.appendingPathComponent("computer-use")
        var settings = ComputerUseSettings.defaults
        settings.includeScreenshots = false
        _ = try ComputerUseCursorInstaller.install(
            settings: settings,
            installRoot: installRoot,
            cursorMCPConfigURL: mcpURL,
            helperOverride: helper,
            agentDesktopOverride: agentDesktop
        )

        let helperBefore = try Data(contentsOf: installRoot.appendingPathComponent("GrokBuildComputerUseMCP"))
        settings.includeScreenshots = true
        settings.permissionPolicy = .auto
        let output = try ComputerUseCursorInstaller.updateConfiguration(
            settings: settings,
            installRoot: installRoot,
            cursorMCPConfigURL: mcpURL
        )

        XCTAssertTrue(output.contains("Updated Cursor MCP configuration"))
        let helperAfter = try Data(contentsOf: installRoot.appendingPathComponent("GrokBuildComputerUseMCP"))
        XCTAssertEqual(helperBefore, helperAfter)

        let entry = try XCTUnwrap(ComputerUseCursorInstaller.mcpEntry(in: mcpURL))
        let env = try XCTUnwrap(entry["env"] as? [String: String])
        XCTAssertEqual(env["GROKBUILD_COMPUTER_USE_SCREENSHOTS"], "true")
        XCTAssertEqual(env["GROKBUILD_COMPUTER_USE_POLICY"], "auto")
    }

    private var allKeys: [String] {
        [
            ComputerUseSettingsKeys.enabled,
            ComputerUseSettingsKeys.backend,
            ComputerUseSettingsKeys.permissionPolicy,
            ComputerUseSettingsKeys.commandTimeoutSeconds,
            ComputerUseSettingsKeys.includeScreenshots,
            ComputerUseSettingsKeys.appliedEnabled,
            ComputerUseSettingsKeys.appliedBackend,
            ComputerUseSettingsKeys.appliedPermissionPolicy,
            ComputerUseSettingsKeys.appliedCommandTimeoutSeconds,
            ComputerUseSettingsKeys.appliedIncludeScreenshots
        ]
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func temporaryExecutableURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokBuildTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("agent-desktop")
    }

    // MARK: - Process runner (pipe drain + timeout)

    /// 256 KiB of child output deadlocked the old runner: nothing read the
    /// pipe until exit, so the child blocked in write(2) at ~64 KiB and the
    /// call surfaced as a bogus timeout. The runner must drain while running.
    func testRunResultDrainsOutputLargerThanPipeBuffer() async throws {
        let result = try await ComputerUseService.runResult(
            ["/bin/sh", "-c", "/usr/bin/head -c 262144 /dev/zero | /usr/bin/tr '\\0' 'a'"],
            timeout: 10
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.count, 262_144)
    }

    func testRunResultTimesOutAndTerminatesTheChild() async {
        let started = Date()
        do {
            _ = try await ComputerUseService.runResult(["/bin/sleep", "30"], timeout: 1)
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 8)
    }

    private func temporarySkillsRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokBuildTests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(".grok")
            .appendingPathComponent("skills")
    }

    private func temporaryInstallRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokBuildTests")
            .appendingPathComponent(UUID().uuidString)
    }

    @discardableResult
    private func makeTemporaryExecutable(named name: String) throws -> URL {
        let directory = temporaryInstallRootURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}
