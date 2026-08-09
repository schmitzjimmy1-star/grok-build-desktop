import AppKit
import ApplicationServices
import Foundation
import GrokBuildComputerUseCore
import Security

struct ComputerUseBackendStatus: Sendable, Equatable {
    var isInstalled: Bool
    var isReady: Bool
    var executablePath: String?
    var version: String?
    var diagnostic: String

    static let unavailable = ComputerUseBackendStatus(
        isInstalled: false,
        isReady: false,
        executablePath: nil,
        version: nil,
        diagnostic: "agent-desktop is not installed."
    )
}

struct ComputerUsePermissionStatus: Sendable, Equatable {
    var accessibility: String
    var screenRecording: String
    var diagnostic: String
    var guidance: String?

    static let unavailable = ComputerUsePermissionStatus(
        accessibility: "unknown",
        screenRecording: "unknown",
        diagnostic: "Permission status is unavailable until agent-desktop is installed.",
        guidance: nil
    )

    /// Ready to act. Accessibility must be granted; when screenshots are
    /// enabled, a *known* Screen Recording denial also blocks readiness
    /// (unknown/not-reported does not, to avoid hard-blocking older
    /// agent-desktop versions that cannot report it).
    func isReady(includeScreenshots: Bool) -> Bool {
        guard accessibility == "granted" else { return false }
        if includeScreenshots && screenRecording == "denied" { return false }
        return true
    }
}

struct AccessibilityTrustProbe: Sendable, Equatable {
    var helperGranted: Bool
    var agentDesktopGranted: Bool
    var helperExecutablePath: String
    var agentDesktopOutput: String
    var probeError: String?
}

enum ComputerUseService {
    struct CommandResult: Sendable {
        var output: String
        var exitCode: Int32
    }

    static func bundledAgentDesktopURL() -> URL? {
        guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let candidate = directory.appendingPathComponent("agent-desktop")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    static func usesBundledAgentDesktop(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> Bool {
        guard let bundled = bundledAgentDesktopURL(),
              let resolved = executableURL(settings: settings) else {
            return false
        }
        return resolved.path == bundled.path
    }

    static func executableURL(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> URL? {
        if let bundled = bundledAgentDesktopURL() {
            return bundled
        }

        if let path = ProcessInfo.processInfo.environment["AGENT_DESKTOP_PATH"], !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }

        for candidate in [
            "/opt/homebrew/bin/agent-desktop",
            "/usr/local/bin/agent-desktop",
            "\(NSHomeDirectory())/.local/bin/agent-desktop",
            "\(NSHomeDirectory())/bin/agent-desktop"
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent("agent-desktop")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    static func helperURL() -> URL? {
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = executableDirectory.appendingPathComponent("GrokBuildComputerUseMCP")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        for configuration in ["release", "debug"] {
            var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            for _ in 0..<4 {
                let candidate = directory
                    .appendingPathComponent(".build")
                    .appendingPathComponent(configuration)
                    .appendingPathComponent("GrokBuildComputerUseMCP")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
                directory.deleteLastPathComponent()
            }
        }

        return nil
    }

    static func computerUseMCPConfig(
        settings: ComputerUseSettings = ComputerUseSettingsStore.load(),
        helperOverride: URL? = nil,
        agentDesktopOverride: URL? = nil
    ) -> MCPServerConfig? {
        guard settings.enabled,
              settings.backend == .agentDesktop,
              let helper = helperOverride ?? helperURL() else {
            return nil
        }

        // Exactly the set the helper reads, via the shared contract constants;
        // an env-parity test keeps app and helper in sync.
        var env: [String: String] = [
            ComputerUseHelperEnvironment.policy: settings.permissionPolicy.rawValue,
            ComputerUseHelperEnvironment.timeout: String(settings.commandTimeoutSeconds),
            ComputerUseHelperEnvironment.screenshots: settings.includeScreenshots ? "true" : "false"
        ]

        if let executable = agentDesktopOverride ?? executableURL(settings: settings) {
            env[ComputerUseHelperEnvironment.agentDesktopPath] = executable.path
        }

        return MCPServerConfig(
            name: "grokbuild-computer-use",
            transport: .stdio,
            command: helper.path,
            args: [],
            env: env
        )
    }

    enum ApplyEnabledResult: Sendable, Equatable {
        case applied
        case needsSetup
        case unchanged
    }

    @MainActor
    static func applyEnabled(
        _ enabled: Bool,
        settings baseSettings: ComputerUseSettings? = nil,
        reloadConfiguration: () async -> Void = {}
    ) async -> ApplyEnabledResult {
        var settings = baseSettings ?? ComputerUseSettingsStore.load()
        guard settings.enabled != enabled else { return .unchanged }

        if enabled {
            if configurationIssue(settings: settings) != nil {
                return .needsSetup
            }
            let permissions = await permissionStatus(settings: settings)
            guard permissions.isReady(includeScreenshots: settings.includeScreenshots) else {
                return .needsSetup
            }
        }

        settings.enabled = enabled
        ComputerUseSettingsStore.save(settings)
        ComputerUseSettingsStore.saveApplied(settings)
        await reloadConfiguration()
        return .applied
    }

    static func syncCursorIntegrationIfInstalled(
        settings: ComputerUseSettings = ComputerUseSettingsStore.load()
    ) throws -> String? {
        let status = ComputerUseCursorInstaller.status()
        guard status.isInstalled else { return nil }
        let message = try ComputerUseCursorInstaller.updateConfiguration(settings: settings)
        ComputerUseSettingsStore.saveAppliedCursorEnvironment(from: settings)
        return message
    }

    static func configurationIssue(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> String? {
        guard settings.backend == .agentDesktop else {
            return "Computer Use backend is not configured."
        }
        guard helperURL() != nil else {
            return "Computer Use MCP helper is missing. Rebuild the app."
        }
        guard executableURL(settings: settings) != nil else {
            return "Install agent-desktop first."
        }
        return nil
    }

    static func status(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async -> ComputerUseBackendStatus {
        guard let executable = executableURL(settings: settings) else { return .unavailable }
        let versionResult = try? await run([executable.path, "version"], timeout: 8)
        let permissionResult = try? await runResult([executable.path, "permissions"], timeout: 8)
        let version = versionResult.flatMap(parseVersion)
        let diagnostic = permissionResult?.output.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "agent-desktop found at \(executable.path)."

        return ComputerUseBackendStatus(
            isInstalled: true,
            isReady: permissionResult?.exitCode == 0,
            executablePath: executable.path,
            version: version?.isEmpty == false ? version : nil,
            diagnostic: diagnostic
        )
    }

    /// The resolved status plus the raw per-process signals it was derived
    /// from, so the UI can show a truthful per-binary breakdown instead of a
    /// single merged verdict.
    struct PermissionOverview: Sendable {
        var resolved: ComputerUsePermissionStatus
        var probe: AccessibilityTrustProbe?
        var grokBuildAccessibilityGranted: Bool
        var grokBuildScreenRecordingGranted: Bool
    }

    static func permissionOverview(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async -> PermissionOverview {
        let grokBuildGranted = localAccessibilityGranted()
        let screenGranted = localScreenRecordingGranted()

        guard executableURL(settings: settings) != nil else {
            return PermissionOverview(
                resolved: .unavailable,
                probe: nil,
                grokBuildAccessibilityGranted: grokBuildGranted,
                grokBuildScreenRecordingGranted: screenGranted
            )
        }

        let probe = await helperAccessibilityProbe(settings: settings)
        var cliStatus: ComputerUsePermissionStatus

        if let probe, !probe.agentDesktopOutput.isEmpty {
            cliStatus = parsePermissions(probe.agentDesktopOutput)
        } else if let executable = executableURL(settings: settings) {
            do {
                let output = try await run([executable.path, "permissions"], timeout: 8)
                cliStatus = parsePermissions(output)
            } catch {
                cliStatus = ComputerUsePermissionStatus(
                    accessibility: "unknown",
                    screenRecording: "unknown",
                    diagnostic: error.localizedDescription,
                    guidance: nil
                )
            }
        } else {
            cliStatus = .unavailable
        }

        let resolved = resolvePermissionStatus(
            cliStatus: cliStatus,
            grokBuildGranted: grokBuildGranted,
            probe: probe,
            settings: settings,
            grokBuildScreenRecordingGranted: screenGranted
        )
        return PermissionOverview(
            resolved: resolved,
            probe: probe,
            grokBuildAccessibilityGranted: grokBuildGranted,
            grokBuildScreenRecordingGranted: screenGranted
        )
    }

    static func permissionStatus(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async -> ComputerUsePermissionStatus {
        await permissionOverview(settings: settings).resolved
    }

    static func localAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Screen Recording preflight for this process. Meaningful for the
    /// bundled agent-desktop (same signing identity); an external copy has
    /// its own TCC identity and must report for itself.
    static func localScreenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Ask macOS for Screen Recording. Until an app *requests* capture it
    /// never appears in Privacy & Security → Screen & System Audio
    /// Recording at all, so there is no row for the user to enable — this
    /// call is what creates it.
    ///
    /// macOS shows the prompt only once per app; afterwards this is a no-op
    /// and the user must toggle the (now existing) row themselves.
    @discardableResult
    static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Requesting is worth doing only when screenshots are enabled and the
    /// permission is not already granted.
    static func shouldRequestScreenRecording(includeScreenshots: Bool, granted: Bool) -> Bool {
        includeScreenshots && !granted
    }

    static var runningExecutablePath: String {
        Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments[0]
    }

    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var bundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    static func helperAccessibilityProbe(
        settings: ComputerUseSettings = ComputerUseSettingsStore.load()
    ) async -> AccessibilityTrustProbe? {
        guard let helper = helperURL(),
              let agentDesktop = executableURL(settings: settings) else {
            return nil
        }

        var environment = ProcessInfo.processInfo.environment
        environment["AGENT_DESKTOP_PATH"] = agentDesktop.path

        do {
            let output = try await run(
                [helper.path, "--check-permissions"],
                timeout: 12,
                environment: environment
            )
            return parseAccessibilityTrustProbe(output)
        } catch {
            return AccessibilityTrustProbe(
                helperGranted: false,
                agentDesktopGranted: false,
                helperExecutablePath: helper.path,
                agentDesktopOutput: "",
                probeError: error.localizedDescription
            )
        }
    }

    static func parseAccessibilityTrustProbe(_ output: String) -> AccessibilityTrustProbe? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return AccessibilityTrustProbe(
            helperGranted: json["helper_accessibility_granted"] as? Bool ?? false,
            agentDesktopGranted: json["agent_desktop_granted"] as? Bool ?? false,
            helperExecutablePath: json["helper_executable"] as? String ?? "",
            agentDesktopOutput: json["agent_desktop_output"] as? String ?? "",
            probeError: nil
        )
    }

    static func resolvePermissionStatus(
        cliStatus: ComputerUsePermissionStatus,
        grokBuildGranted: Bool,
        probe: AccessibilityTrustProbe?,
        settings: ComputerUseSettings = ComputerUseSettingsStore.load(),
        grokBuildScreenRecordingGranted: Bool = localScreenRecordingGranted()
    ) -> ComputerUsePermissionStatus {
        let helperGranted = probe?.helperGranted ?? false
        let agentDesktopGranted = probe?.agentDesktopGranted ?? false
        let cliGranted = cliStatus.accessibility == "granted"
        let bundled = usesBundledAgentDesktop(settings: settings)

        let granted: Bool
        if bundled {
            // All three binaries are signed with the app's bundle id, so any
            // grant proves the shared TCC identity is trusted.
            granted = grokBuildGranted || helperGranted || agentDesktopGranted || cliGranted
        } else {
            // An external agent-desktop has its own TCC identity. Only its
            // own grant (probe or direct report) counts — GrokBuild's or the
            // helper's trust must not mask a denied actuator.
            granted = agentDesktopGranted || cliGranted
        }

        var resolved = cliStatus
        if granted {
            resolved.accessibility = "granted"
            resolved.guidance = nil
        } else {
            resolved.guidance = accessibilityGuidance(probe: probe, settings: settings)
        }
        // Screen Recording: for the bundled copy this process's preflight is
        // authoritative (same identity); an external copy keeps its own report.
        if bundled && grokBuildScreenRecordingGranted {
            resolved.screenRecording = "granted"
        }
        resolved.diagnostic = permissionDiagnosticText(
            cliStatus: cliStatus,
            grokBuildGranted: grokBuildGranted,
            probe: probe,
            settings: settings
        )
        return resolved
    }

    static func accessibilityGuidance(
        probe: AccessibilityTrustProbe?,
        settings: ComputerUseSettings = ComputerUseSettingsStore.load()
    ) -> String {
        if usesBundledAgentDesktop(settings: settings) {
            var lines = [
                "Enable \(hostAppName) in System Settings → Privacy & Security → Accessibility.",
                "agent-desktop is bundled inside this app and shares the same permission.",
                "Add this app with the + button:",
                appBundlePath
            ]
            if let cdHash = codeSignatureCDHash() {
                lines.append("If GrokBuild is already listed but still denied, remove it and add again (signature CDHash: \(cdHash.prefix(12))…).")
            } else {
                lines.append("If GrokBuild is already listed but still denied, remove it and add again after `make app`.")
            }
            return lines.joined(separator: "\n")
        }

        let agentDesktopPath = executableURL(settings: settings)?.path ?? "agent-desktop"
        var lines = [
            "Computer Use runs through agent-desktop. In System Settings → Privacy & Security → Accessibility, enable both:",
            "1. \(hostAppName) (this app)",
            "2. agent-desktop at \(agentDesktopPath)"
        ]

        if isBundledApp {
            lines.append(
                "If \(hostAppName) is already listed, remove it and add it again after `make app` — macOS ties permission to the app signature."
            )
        } else {
            lines.append(
                "Running executable: \(runningExecutablePath)"
            )
        }

        if let probe, !probe.helperGranted {
            lines.append("If problems persist, also allow GrokBuildComputerUseMCP.")
        }

        return lines.joined(separator: "\n")
    }

    static func permissionDiagnosticText(
        cliStatus: ComputerUsePermissionStatus,
        grokBuildGranted: Bool,
        probe: AccessibilityTrustProbe?,
        settings: ComputerUseSettings = ComputerUseSettingsStore.load()
    ) -> String {
        let agentDesktopPath = executableURL(settings: settings)?.path ?? "unknown"
        let bundled = usesBundledAgentDesktop(settings: settings)
        var lines = [
            "App bundle: \(appBundlePath)",
            "Running executable: \(runningExecutablePath)",
            "Bundle identifier: \(bundleIdentifier ?? "none")",
            "Bundled app: \(isBundledApp ? "yes" : "no")",
            "agent-desktop path: \(agentDesktopPath)",
            "agent-desktop bundled: \(bundled ? "yes" : "no")",
            "GrokBuild Accessibility: \(grokBuildGranted ? "granted" : "denied")"
        ]

        if let cdHash = codeSignatureCDHash() {
            lines.append("App signature CDHash: \(cdHash)")
        }

        if let probe {
            lines.append("Helper executable: \(probe.helperExecutablePath)")
            lines.append("Helper Accessibility: \(probe.helperGranted ? "granted" : "denied")")
            lines.append("agent-desktop (via helper): \(probe.agentDesktopGranted ? "granted" : "denied")")
            if let probeError = probe.probeError, !probeError.isEmpty {
                lines.append("Helper probe error: \(probeError)")
            }
        }

        if grokBuildGranted || probe?.helperGranted == true || probe?.agentDesktopGranted == true {
            lines.append("Required Accessibility clients are trusted by macOS.")
        }

        let cliText = cliStatus.diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cliText.isEmpty {
            lines.append("")
            lines.append("agent-desktop output:")
            lines.append(cliText)
        }

        return lines.joined(separator: "\n")
    }

    static func requestPermissions(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async throws -> String {
        guard executableURL(settings: settings) != nil else {
            throw NSError(
                domain: "ComputerUseService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "agent-desktop is not installed."]
            )
        }

        let grokBuildGranted = await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            return promptForLocalAccessibility()
        }

        var lines = [
            "GrokBuild accessibility: \(grokBuildGranted ? "granted" : "not granted yet")"
        ]

        if shouldRequestScreenRecording(
            includeScreenshots: settings.includeScreenshots,
            granted: localScreenRecordingGranted()
        ) {
            let granted = await MainActor.run { requestScreenRecordingAccess() }
            lines.append(
                granted
                    ? "Screen Recording: granted."
                    : "Screen Recording: requested — approve the macOS prompt, then enable GrokBuild in Privacy & Security → Screen & System Audio Recording (the entry exists now) and relaunch."
            )
        }

        if usesBundledAgentDesktop(settings: settings) {
            if !grokBuildGranted {
                await MainActor.run { openAccessibilitySettings() }
                lines.append("Opened Accessibility settings.")
                lines.append("Remove any existing GrokBuild entry, click +, and choose:")
                lines.append(appBundlePath)
                if let cdHash = codeSignatureCDHash() {
                    lines.append("Current app signature CDHash: \(cdHash)")
                    lines.append("macOS ties Accessibility to this signature; re-adding is required after each rebuild.")
                }
            }
            return lines.joined(separator: "\n")
        }

        if !grokBuildGranted {
            await MainActor.run { openAccessibilitySettings() }
        }

        if let helper = helperURL(), let agentDesktop = executableURL(settings: settings) {
            var environment = ProcessInfo.processInfo.environment
            environment["AGENT_DESKTOP_PATH"] = agentDesktop.path
            let helperOutput = try await run(
                [helper.path, "--request-permissions"],
                timeout: 30,
                environment: environment
            )
            lines.append(helperOutput)
        } else if let executable = executableURL(settings: settings) {
            let output = try await run([executable.path, "permissions", "--request"], timeout: 30)
            lines.append(output)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - End-to-end self test

    enum EndToEndTestFailure: String, Sendable, Equatable {
        case helperMissing
        case agentDesktopMissing
        case malformedJSON
        case jsonRPCError
        case wrongFinalRequestID
        case timeout
        case emptyContent
        case helperExitFailure
        case commandMismatch
    }

    struct EndToEndTestResult: Sendable, Equatable {
        var success: Bool
        var summary: String
        var failure: EndToEndTestFailure?
        var protocolVersion: String?
        var helperVersion: String?
        var command: String
        var appCount: Int?
        var durationMilliseconds: Int
        var accessibilityRequired: Bool
        var accessibilityProven: Bool
        var screenshotsRequired: Bool
        var screenshotsProven: Bool
        var diagnostic: String

        var compactDetail: String {
            guard success else { return diagnostic }
            let protocolText = protocolVersion ?? "unknown"
            let helperText = helperVersion ?? "unknown"
            let countText = appCount.map { "\($0) apps" } ?? "unknown app count"
            return "Protocol \(protocolText) · Helper \(helperText)\n\(command) · \(countText) · \(durationMilliseconds) ms\nAccessibility: \(accessibilityProven ? "proven" : "not proven") · Screenshots: \(screenshotsRequired ? (screenshotsProven ? "proven" : "not proven") : "not required")"
        }

        static func failure(
            _ failure: EndToEndTestFailure,
            summary: String,
            diagnostic: String,
            command: String = "computer_list_apps",
            durationMilliseconds: Int = 0
        ) -> EndToEndTestResult {
            EndToEndTestResult(
                success: false,
                summary: summary,
                failure: failure,
                protocolVersion: nil,
                helperVersion: nil,
                command: command,
                appCount: nil,
                durationMilliseconds: boundedDuration(durationMilliseconds),
                accessibilityRequired: true,
                accessibilityProven: false,
                screenshotsRequired: false,
                screenshotsProven: false,
                diagnostic: diagnostic
            )
        }
    }

    enum HelperRPCError: Error, Sendable, Equatable, LocalizedError {
        case timedOut(seconds: Int)
        case nonzeroExit(code: Int32)
        case wrongFinalRequestID(expected: Int, observed: [Int])
        case malformedResponse
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case let .timedOut(seconds):
                return "Computer Use test timed out after \(seconds)s."
            case let .nonzeroExit(code):
                return "Computer Use helper exited with status \(code)."
            case let .wrongFinalRequestID(expected, observed):
                let ids = observed.sorted().map(String.init).joined(separator: ", ")
                return "Computer Use helper returned request ID(s) [\(ids)] instead of final ID \(expected)."
            case .malformedResponse:
                return "Computer Use helper returned malformed JSON-RPC output."
            case .emptyResponse:
                return "Computer Use helper exited without a JSON-RPC response."
            }
        }
    }

    private struct AgentDesktopListAppsResponse: Decodable {
        struct Payload: Decodable {
            struct App: Decodable {}
            var apps: [App]
        }

        var version: String
        var ok: Bool
        var command: String
        var data: Payload
    }

    /// Proves the whole chain the way grok uses it: spawn the helper over
    /// stdio JSON-RPC with the exported env, `initialize`, then call
    /// `computer_list_apps` through agent-desktop. Every green light in the
    /// pane is inference; this is evidence.
    static func runEndToEndTest(settings: ComputerUseSettings = ComputerUseSettingsStore.load()) async -> EndToEndTestResult {
        guard let helper = helperURL() else {
            return .failure(
                .helperMissing,
                summary: "Helper missing",
                diagnostic: "GrokBuildComputerUseMCP was not found next to the app executable. Rebuild the app (make run)."
            )
        }
        guard let agentDesktop = executableURL(settings: settings) else {
            return .failure(
                .agentDesktopMissing,
                summary: "agent-desktop missing",
                diagnostic: "Install it with `npm install -g agent-desktop`, then rebuild so packaging bundles it."
            )
        }

        var env = ProcessInfo.processInfo.environment
        env[ComputerUseHelperEnvironment.agentDesktopPath] = agentDesktop.path
        env[ComputerUseHelperEnvironment.policy] = settings.permissionPolicy.rawValue
        env[ComputerUseHelperEnvironment.timeout] = String(settings.commandTimeoutSeconds)
        env[ComputerUseHelperEnvironment.screenshots] = settings.includeScreenshots ? "true" : "false"

        let startedAt = Date()
        do {
            let responses = try await runHelperRPC(
                helper: helper,
                environment: env,
                requests: [
                    #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
                    #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"computer_list_apps","arguments":{}}}"#,
                ],
                finalID: 2,
                timeout: 20
            )
            return parseEndToEndResponses(
                responses,
                finalID: 2,
                durationMilliseconds: elapsedMilliseconds(since: startedAt)
            )
        } catch let error as HelperRPCError {
            let duration = elapsedMilliseconds(since: startedAt)
            switch error {
            case .timedOut:
                return .failure(.timeout, summary: "Test timed out", diagnostic: error.localizedDescription, durationMilliseconds: duration)
            case .nonzeroExit:
                return .failure(.helperExitFailure, summary: "Helper exited", diagnostic: error.localizedDescription, durationMilliseconds: duration)
            case .wrongFinalRequestID:
                return .failure(.wrongFinalRequestID, summary: "Wrong response ID", diagnostic: error.localizedDescription, durationMilliseconds: duration)
            case .malformedResponse:
                return .failure(.malformedJSON, summary: "Malformed helper response", diagnostic: error.localizedDescription, durationMilliseconds: duration)
            case .emptyResponse:
                return .failure(.emptyContent, summary: "No response", diagnostic: error.localizedDescription, durationMilliseconds: duration)
            }
        } catch {
            return .failure(
                .helperExitFailure,
                summary: "Test failed",
                diagnostic: error.localizedDescription,
                durationMilliseconds: elapsedMilliseconds(since: startedAt)
            )
        }
    }

    static func parseEndToEndResponses(
        _ responses: [Int: [String: Any]],
        finalID: Int,
        durationMilliseconds: Int
    ) -> EndToEndTestResult {
        guard let initialize = responses[1],
              let initializeResult = initialize["result"] as? [String: Any],
              let protocolVersion = initializeResult["protocolVersion"] as? String,
              let serverInfo = initializeResult["serverInfo"] as? [String: Any],
              let helperVersion = serverInfo["version"] as? String else {
            return .failure(
                .malformedJSON,
                summary: "Malformed initialize response",
                diagnostic: "The helper initialize receipt did not contain protocol and helper versions.",
                durationMilliseconds: durationMilliseconds
            )
        }

        guard let final = responses[finalID] else {
            return .failure(
                .wrongFinalRequestID,
                summary: "Wrong response ID",
                diagnostic: "The helper did not return final request ID \(finalID).",
                durationMilliseconds: durationMilliseconds
            )
        }
        if let error = final["error"] as? [String: Any] {
            return .failure(
                .jsonRPCError,
                summary: "Tool call failed",
                diagnostic: boundedDiagnostic(error["message"] as? String ?? "Unknown JSON-RPC error."),
                durationMilliseconds: durationMilliseconds
            )
        }
        guard let result = final["result"] as? [String: Any] else {
            return .failure(
                .malformedJSON,
                summary: "Malformed tool response",
                diagnostic: "The final JSON-RPC response did not contain a result object.",
                durationMilliseconds: durationMilliseconds
            )
        }
        if result["isError"] as? Bool == true {
            return .failure(
                .jsonRPCError,
                summary: "Tool call failed",
                diagnostic: "The helper marked computer_list_apps as failed; raw tool output was withheld.",
                durationMilliseconds: durationMilliseconds
            )
        }
        guard let content = result["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(
                .emptyContent,
                summary: "Empty tool response",
                diagnostic: "computer_list_apps returned no usable text content.",
                durationMilliseconds: durationMilliseconds
            )
        }

        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AgentDesktopListAppsResponse.self, from: data) else {
            return .failure(
                .malformedJSON,
                summary: "Malformed list-apps response",
                diagnostic: "agent-desktop returned malformed list-apps JSON (\(text.utf8.count) bytes).",
                durationMilliseconds: durationMilliseconds
            )
        }
        guard payload.ok, payload.command == "list-apps" else {
            return .failure(
                .commandMismatch,
                summary: "Unexpected command response",
                diagnostic: "Expected successful list-apps output; received command \(boundedDiagnostic(payload.command)).",
                durationMilliseconds: durationMilliseconds
            )
        }

        return EndToEndTestResult(
            success: true,
            summary: "Computer Use passed end to end",
            failure: nil,
            protocolVersion: protocolVersion,
            helperVersion: helperVersion,
            command: "computer_list_apps",
            appCount: payload.data.apps.count,
            durationMilliseconds: boundedDuration(durationMilliseconds),
            accessibilityRequired: true,
            accessibilityProven: true,
            screenshotsRequired: false,
            screenshotsProven: false,
            diagnostic: redactedListAppsDiagnostic(text)
        )
    }

    static func redactedListAppsDiagnostic(_ text: String, limit: Int = 1_200) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Malformed list-apps JSON (\(text.utf8.count) bytes); raw output withheld."
        }
        var redacted = object
        if let payload = object["data"] as? [String: Any],
           let apps = payload["apps"] as? [Any] {
            var safePayload = payload
            safePayload["apps"] = ["<redacted \(apps.count) app records>"]
            redacted["data"] = safePayload
        }
        guard let safeData = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
              let safeText = String(data: safeData, encoding: .utf8) else {
            return "Valid list-apps response; redacted diagnostics unavailable."
        }
        return boundedDiagnostic(safeText, limit: limit)
    }

    static func boundedDiagnostic(_ text: String, limit: Int = 1_200) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "…"
    }

    private static func elapsedMilliseconds(since date: Date) -> Int {
        boundedDuration(Int(Date().timeIntervalSince(date) * 1_000))
    }

    private static func boundedDuration(_ milliseconds: Int) -> Int {
        min(max(milliseconds, 0), 99_999)
    }

    /// Internal (not private) so the RPC plumbing stays under test against a
    /// scripted fake helper.
    static func runHelperRPC(
        helper: URL,
        environment: [String: String],
        requests: [String],
        finalID: Int,
        timeout: TimeInterval
    ) async throws -> [Int: [String: Any]] {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = helper
            process.environment = environment

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            final class RPCBox: @unchecked Sendable {
                let lock = NSLock()
                var buffer = Data()
                var responses: [Int: [String: Any]] = [:]
                var sawMalformedLine = false
                var didResume = false
            }
            let box = RPCBox()

            @Sendable
            func finish(_ result: Result<[Int: [String: Any]], Error>) {
                box.lock.lock()
                guard !box.didResume else {
                    box.lock.unlock()
                    return
                }
                box.didResume = true
                box.lock.unlock()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                try? stdinPipe.fileHandleForWriting.close()
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(with: result)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    return
                }
                box.lock.lock()
                let lines = AcpLineBuffer.drainLines(buffer: &box.buffer, appending: chunk)
                for line in lines {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = json["id"] as? Int else {
                        box.sawMalformedLine = true
                        continue
                    }
                    box.responses[id] = json
                }
                let snapshot = box.responses
                box.lock.unlock()
                if snapshot[finalID] != nil {
                    finish(.success(snapshot))
                }
            }

            process.terminationHandler = { terminated in
                box.lock.lock()
                let responses = box.responses
                let malformed = box.sawMalformedLine
                box.lock.unlock()
                if responses[finalID] != nil {
                    finish(.success(responses))
                } else if terminated.terminationStatus != 0 {
                    finish(.failure(HelperRPCError.nonzeroExit(code: terminated.terminationStatus)))
                } else if malformed {
                    finish(.failure(HelperRPCError.malformedResponse))
                } else if !responses.isEmpty {
                    finish(.failure(HelperRPCError.wrongFinalRequestID(
                        expected: finalID,
                        observed: Array(responses.keys)
                    )))
                } else {
                    finish(.failure(HelperRPCError.emptyResponse))
                }
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            let payload = requests.map { $0 + "\n" }.joined()
            stdinPipe.fileHandleForWriting.write(Data(payload.utf8))
            try? stdinPipe.fileHandleForWriting.close()

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                finish(.failure(HelperRPCError.timedOut(seconds: max(1, Int(ceil(timeout))))))
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    static var appBundlePath: String {
        Bundle.main.bundleURL.path
    }

    static func codeSignatureCDHash() -> String? {
        let bundleURL = Bundle.main.bundleURL as CFURL
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: 0), &information) == errSecSuccess,
              let info = information as? [String: Any] else {
            return nil
        }

        if let cdHashes = info["cdhashes"] as? [Data], let first = cdHashes.first {
            return first.map { String(format: "%02x", $0) }.joined()
        }

        if let unique = info[kSecCodeInfoUnique as String] as? Data {
            return unique.map { String(format: "%02x", $0) }.joined()
        }

        return nil
    }

    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @MainActor
    static func promptForLocalAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openAccessibilitySettings() {
        NSApp.activate(ignoringOtherApps: true)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            ?? URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    static var hostAppName: String {
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !name.isEmpty {
            return name
        }
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return "GrokBuild"
    }

    static func commandPreview(_ args: [String], settings: ComputerUseSettings = ComputerUseSettingsStore.load()) -> [String] {
        [executableURL(settings: settings)?.path ?? "agent-desktop"] + args
    }

    static func parseVersion(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return trimmed.isEmpty ? nil : trimmed
        }

        if let data = json["data"] as? [String: Any],
           let version = data["version"] as? String,
           !version.isEmpty {
            return version
        }
        if let version = json["version"] as? String, !version.isEmpty {
            return version
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parsePermissions(_ output: String) -> ComputerUsePermissionStatus {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ComputerUsePermissionStatus(
                accessibility: "unknown",
                screenRecording: "unknown",
                diagnostic: output.isEmpty ? "No permission diagnostics returned." : output,
                guidance: nil
            )
        }

        let payload = (json["data"] as? [String: Any]) ?? json

        func normalizedState(from value: Any?) -> String? {
            switch value {
            case let string as String where !string.isEmpty:
                return string.lowercased()
            case let granted as Bool:
                return granted ? "granted" : "denied"
            default:
                return nil
            }
        }

        func permissionState(for key: String) -> String? {
            if let dict = payload[key] as? [String: Any] {
                return normalizedState(from: dict["state"]) ?? normalizedState(from: dict["granted"])
            }
            return normalizedState(from: payload[key])
        }

        let legacyGranted = normalizedState(from: payload["granted"])
        let hasStructuredScreenRecording = payload["screen_recording"] != nil || payload["screenRecording"] != nil

        let accessibility = permissionState(for: "accessibility")
            ?? legacyGranted
            ?? "unknown"

        let screenRecording: String
        if hasStructuredScreenRecording {
            screenRecording = permissionState(for: "screen_recording")
                ?? permissionState(for: "screenRecording")
                ?? "unknown"
        } else if legacyGranted != nil {
            // agent-desktop v1.0 only reports a combined granted flag.
            screenRecording = "not reported"
        } else {
            screenRecording = "unknown"
        }

        return ComputerUsePermissionStatus(
            accessibility: accessibility,
            screenRecording: screenRecording,
            diagnostic: output,
            guidance: permissionGuidance(accessibility: accessibility, payload: payload)
        )
    }

    static func permissionGuidance(accessibility: String, payload: [String: Any], appName: String = hostAppName) -> String? {
        guard accessibility != "granted" else { return nil }
        if let rewritten = rewritePermissionSuggestion(payload["suggestion"] as? String, appName: appName) {
            return rewritten
        }
        return "Open System Settings → Privacy & Security → Accessibility and enable \(appName)."
    }

    static func rewritePermissionSuggestion(_ suggestion: String?, appName: String) -> String? {
        guard let suggestion else { return nil }
        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.localizedCaseInsensitiveContains("terminal") {
            return "Open System Settings → Privacy & Security → Accessibility and enable \(appName)."
        }

        return trimmed.replacingOccurrences(
            of: "your terminal application",
            with: appName,
            options: [.caseInsensitive]
        )
    }

    private static func run(_ command: [String], timeout: TimeInterval, environment: [String: String]? = nil) async throws -> String {
        let result = try await runResult(command, timeout: timeout, environment: environment)
        if result.exitCode != 0 {
            throw NSError(
                domain: "ComputerUseService",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.output.isEmpty ? "Command failed." : result.output]
            )
        }
        return result.output
    }

    /// Internal (not private) so the pipe-drain behavior stays under test.
    static func runResult(
        _ command: [String],
        timeout: TimeInterval,
        environment: [String: String]? = nil
    ) async throws -> CommandResult {
        guard let executable = command.first else {
            throw NSError(domain: "ComputerUseService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing command."])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst())
            if let environment {
                process.environment = environment
            }
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            final class ResumeBox: @unchecked Sendable {
                let lock = NSLock()
                var didResume = false
                var stdoutData = Data()
                var stderrData = Data()
            }
            let box = ResumeBox()

            // Drain while the child runs — output beyond the ~64 KiB pipe
            // buffer would otherwise block the child in write(2) until the
            // timeout (same bug as the helper's runAgentDesktop had).
            let drainGroup = DispatchGroup()
            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                box.lock.lock()
                box.stdoutData = data
                box.lock.unlock()
                drainGroup.leave()
            }
            drainGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                box.lock.lock()
                box.stderrData = data
                box.lock.unlock()
                drainGroup.leave()
            }

            @Sendable
            func finish(_ result: Result<CommandResult, Error>) {
                box.lock.lock()
                guard !box.didResume else {
                    box.lock.unlock()
                    return
                }
                box.didResume = true
                box.lock.unlock()
                continuation.resume(with: result)
            }

            process.terminationHandler = { process in
                _ = drainGroup.wait(timeout: .now() + 5)
                box.lock.lock()
                let out = String(decoding: box.stdoutData, as: UTF8.self)
                let err = String(decoding: box.stderrData, as: UTF8.self)
                box.lock.unlock()
                finish(.success(CommandResult(output: out.isEmpty ? err : out, exitCode: process.terminationStatus)))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard process.isRunning else { return }
                // Resume the caller with the timeout right away; the
                // dedupe box makes the (later) terminationHandler a no-op.
                // Publish the timeout before sending SIGTERM so a fast
                // termination handler cannot win the race with a success.
                finish(.failure(NSError(
                    domain: "ComputerUseService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "agent-desktop command timed out."]
                )))
                process.terminate()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }
}
