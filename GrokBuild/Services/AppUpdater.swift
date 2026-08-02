import AppKit
import Foundation

@MainActor @Observable
final class AppUpdater {
    static let shared = AppUpdater()

    enum Phase: Equatable {
        case idle
        case downloading(progress: Double)
        case verifying
        case readyToInstall(extractedAppURL: URL, version: String)
        case installing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var activeRelease: UpdateChecker.AppRelease?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadObservation: NSKeyValueObservation?

    private init() {}

    var isBusy: Bool {
        switch phase {
        case .idle, .failed, .readyToInstall:
            return false
        case .downloading, .verifying, .installing:
            return true
        }
    }

    func reset() {
        cancelDownload()
        phase = .idle
        activeRelease = nil
    }

    func downloadAndVerify(release: UpdateChecker.AppRelease) async {
        // A second tap while a download/verify/install is already in flight must not
        // stack a concurrent attempt on the same state machine.
        guard !isBusy else { return }
#if DEBUG
        if UpdateDebugSimulator.isAppSimulationActive
            || UpdateDebugSimulator.isSimulatedAppRelease(release) {
            await performSimulatedDownloadAndVerify(release: release)
            return
        }
#endif

        guard release.canInstallInApp, let downloadURL = release.downloadURL else {
            phase = .failed("No installable release asset was found.")
            notifyPhaseChanged()
            return
        }

        activeRelease = release
        phase = .downloading(progress: 0)
        notifyPhaseChanged()

        let updatesRoot = Self.updatesDirectory()
        do {
            try FileManager.default.createDirectory(at: updatesRoot, withIntermediateDirectories: true)
            try Self.cleanupOldDownloads(in: updatesRoot, keepingVersion: release.latestVersion)

            let zipURL = updatesRoot.appendingPathComponent("\(UpdateChecker.appName)-\(release.tagName).app.zip")
            if FileManager.default.fileExists(atPath: zipURL.path) {
                try FileManager.default.removeItem(at: zipURL)
            }

            try await downloadFile(from: downloadURL, to: zipURL)

            phase = .verifying
            notifyPhaseChanged()

            let extractedApp = try await verifyAndExtract(zipURL: zipURL, version: release.latestVersion)
            phase = .readyToInstall(extractedAppURL: extractedApp, version: release.latestVersion)
            notifyPhaseChanged()
        } catch {
            // reset() cancels the download; keep the phase it chose instead of
            // overwriting .idle with a failure for our own cancellation.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            phase = .failed(error.localizedDescription)
            notifyPhaseChanged()
        }
    }

    func installAndRestart(extractedAppURL: URL) {
#if DEBUG
        if UpdateDebugSimulator.isAppSimulationActive
            || (activeRelease.map(UpdateDebugSimulator.isSimulatedAppRelease) == true) {
            performSimulatedInstall()
            return
        }
#endif

        let targetURL = Bundle.main.bundleURL

        guard Self.isInstallTargetWritable(targetURL) else {
            phase = .failed("Cannot update GrokBuild at its current location. Move the app to /Applications and try again.")
            notifyPhaseChanged()
            return
        }

        guard let helper = Self.installHelperURL() else {
            phase = .failed("Install helper script is missing from the app bundle.")
            notifyPhaseChanged()
            return
        }

        // Run a temp copy of the helper: the bundled script lives inside the very
        // bundle being replaced, and overwriting a script mid-execution is only
        // accidentally safe (bash holds the old inode).
        let stagedHelper: URL
        do {
            stagedHelper = try Self.stageHelperCopy(of: helper)
        } catch {
            phase = .failed("Could not stage the install helper: \(error.localizedDescription)")
            notifyPhaseChanged()
            return
        }

        phase = .installing
        notifyPhaseChanged()

        NotificationCenter.default.post(name: .grokBuildPrepareForShutdown, object: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            stagedHelper.path,
            "--target", targetURL.path,
            "--new-app", extractedAppURL.path,
            "--pid", String(getpid()),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            phase = .failed("Could not launch install helper: \(error.localizedDescription)")
            notifyPhaseChanged()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    func cancelDownload() {
        downloadObservation?.invalidate()
        downloadObservation = nil
        downloadTask?.cancel()
        downloadTask = nil
    }

    private func downloadFile(from url: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = URLSession(configuration: .ephemeral)
            let task = session.downloadTask(with: url) { [weak self] tempURL, _, error in
                // One-shot session — invalidate so each download attempt doesn't leak one.
                session.finishTasksAndInvalidate()
                Task { @MainActor in
                    self?.downloadObservation?.invalidate()
                    self?.downloadObservation = nil
                    self?.downloadTask = nil
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tempURL else {
                    continuation.resume(throwing: NSError(
                        domain: "GrokBuildUpdater",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Download failed."]
                    ))
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            downloadTask = task
            downloadObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if case .downloading = self.phase {
                        self.phase = .downloading(progress: progress.fractionCompleted)
                        self.notifyPhaseChanged()
                    }
                }
            }
            task.resume()
        }
    }

    private func verifyAndExtract(zipURL: URL, version: String) async throws -> URL {
        let extractRoot = Self.updatesDirectory()
            .appendingPathComponent("extract-\(version)", isDirectory: true)

        if FileManager.default.fileExists(atPath: extractRoot.path) {
            try FileManager.default.removeItem(at: extractRoot)
        }
        try FileManager.default.createDirectory(at: extractRoot, withIntermediateDirectories: true)

        let extract = try await Self.runCommand("/usr/bin/ditto", ["-xk", zipURL.path, extractRoot.path])
        if extract.exitCode != 0 {
            throw Self.updaterError("Could not extract update archive.\n\(extract.output)")
        }

        guard let appURL = Self.findAppBundle(in: extractRoot) else {
            throw Self.updaterError("Downloaded archive did not contain GrokBuild.app.")
        }

        try await Self.verifySignature(for: appURL)
        return appURL
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        if directory.pathExtension == "app" {
            return directory
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        if let direct = entries.first(where: { $0.lastPathComponent == "\(UpdateChecker.appName).app" }) {
            return direct
        }
        return entries.first(where: { $0.pathExtension == "app" })
    }

    private static func verifySignature(for appURL: URL) async throws {
        let codesign = try await runCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", appURL.path])
        if codesign.exitCode != 0 {
            throw updaterError("Update failed code signature verification.\n\(codesign.output)")
        }

        let spctl = try await runCommand("/usr/sbin/spctl", ["-a", "-t", "exec", "-vv", appURL.path])
        if spctl.exitCode != 0 {
            throw updaterError("Update failed Gatekeeper assessment.\n\(spctl.output)")
        }

        let installedTeam = await teamIdentifier(for: Bundle.main.bundleURL)
        let updateTeam = await teamIdentifier(for: appURL)
        if let issue = teamPolicyIssue(installedTeam: installedTeam, updateTeam: updateTeam) {
            throw updaterError(issue)
        }
    }

    /// Fail-closed publisher continuity. nil = acceptable; otherwise the reason to block.
    /// Previously the team check was silently skipped when either side lacked a TeamID,
    /// so a dev/ad-hoc-signed install would accept a validly notarized update from any
    /// developer.
    nonisolated static func teamPolicyIssue(installedTeam: String?, updateTeam: String?) -> String? {
        guard let updateTeam, !updateTeam.isEmpty else {
            return "The update does not declare a signing team, so its publisher cannot be verified. Update manually from the releases page."
        }
        guard let installedTeam, !installedTeam.isEmpty else {
            return "The installed copy of GrokBuild has no signing team (development build), so publisher continuity cannot be verified against the update (signed by team \(updateTeam)). Download the release from GitHub and replace the app manually, or install a signed build first."
        }
        if installedTeam != updateTeam {
            return "Update was signed by a different developer (\(updateTeam)) than the installed app (\(installedTeam))."
        }
        return nil
    }

    static func teamIdentifier(for appURL: URL) async -> String? {
        guard let result = try? await runCommand("/usr/bin/codesign", ["-dv", "--verbose=4", appURL.path]) else {
            return nil
        }
        for line in result.output.components(separatedBy: .newlines) {
            if line.hasPrefix("TeamIdentifier=") {
                let value = line.replacingOccurrences(of: "TeamIdentifier=", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value == "not set" ? nil : value
            }
        }
        return nil
    }

    static func installHelperURL() -> URL? {
        if let resource = Bundle.main.url(forResource: "grokbuild-install-update", withExtension: nil) {
            return resource
        }

        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            let candidate = directory
                .appendingPathComponent("..")
                .appendingPathComponent("scripts")
                .appendingPathComponent("grokbuild-install-update.sh")
                .standardized
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        return nil
    }

    static func stageHelperCopy(of helper: URL) throws -> URL {
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-install-update-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: staged)
        try FileManager.default.copyItem(at: helper, to: staged)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        return staged
    }

    static func updatesDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GrokBuild", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
    }

    static func isInstallTargetWritable(_ targetURL: URL) -> Bool {
        if let values = try? targetURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]),
           values.volumeIsReadOnly == true {
            return false
        }

        let parent = targetURL.deletingLastPathComponent()
        return FileManager.default.isWritableFile(atPath: parent.path)
    }

    private static func cleanupOldDownloads(in directory: URL, keepingVersion: String) throws {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        for entry in entries {
            let name = entry.lastPathComponent
            if name.contains(keepingVersion) { continue }
            if name.hasSuffix(".app.zip") || name.hasPrefix("extract-") {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    // Async (via BoundedProcess) so ditto/codesign/spctl no longer block the main actor
    // mid-"Verifying…" (the spinner could not even animate); merged stdout+stderr through
    // one pipe with incremental drain.
    private static func runCommand(_ launchPath: String, _ arguments: [String]) async throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let outcome = try await BoundedProcess.run(process, stdout: pipe, stderr: nil, timeout: nil)
        return (outcome.status, String(decoding: outcome.stdout, as: UTF8.self))
    }

    private static func updaterError(_ message: String) -> NSError {
        NSError(domain: "GrokBuildUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func notifyPhaseChanged() {
        NotificationCenter.default.post(name: .grokBuildUpdaterPhaseChanged, object: self)
    }

#if DEBUG
    private func performSimulatedDownloadAndVerify(release: UpdateChecker.AppRelease) async {
        activeRelease = release
        phase = .downloading(progress: 0)
        notifyPhaseChanged()

        for step in 1...10 {
            try? await Task.sleep(for: .milliseconds(120))
            phase = .downloading(progress: Double(step) / 10.0)
            notifyPhaseChanged()
        }

        phase = .verifying
        notifyPhaseChanged()
        try? await Task.sleep(for: .milliseconds(700))

        phase = .readyToInstall(extractedAppURL: Bundle.main.bundleURL, version: release.latestVersion)
        notifyPhaseChanged()
    }

    private func performSimulatedInstall() {
        let targetURL = Bundle.main.bundleURL

        guard let helper = Self.installHelperURL() else {
            phase = .failed("Install helper script is missing from the app bundle.")
            notifyPhaseChanged()
            return
        }

        phase = .installing
        notifyPhaseChanged()

        NotificationCenter.default.post(name: .grokBuildPrepareForShutdown, object: nil)

        UpdateSettingsStore.skipVersion(UpdateDebugSimulator.simulatedAppVersion)
        UpdateDebugSimulator.clearSimulationFlags()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            helper.path,
            "--relaunch-only",
            "--target", targetURL.path,
            "--pid", String(getpid()),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            phase = .failed("Could not launch install helper: \(error.localizedDescription)")
            notifyPhaseChanged()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
#endif
}
