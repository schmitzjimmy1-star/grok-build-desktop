import Foundation
import XCTest
@testable import GrokBuild

/// Slice-6 contracts: fail-closed publisher continuity and the stage-then-swap
/// install helper (no ditto-merge leftovers, no unverified content, rollback intact).
final class UpdaterHardeningTests: XCTestCase {
    // MARK: - Team policy

    func testTeamPolicyBlocksWhenUpdateHasNoTeam() {
        XCTAssertNotNil(AppUpdater.teamPolicyIssue(installedTeam: "DD2GCQJVB4", updateTeam: nil))
        XCTAssertNotNil(AppUpdater.teamPolicyIssue(installedTeam: "DD2GCQJVB4", updateTeam: ""))
    }

    func testTeamPolicyFailsClosedForUnsignedInstalledCopy() {
        let issue = AppUpdater.teamPolicyIssue(installedTeam: nil, updateTeam: "OTHERTEAM1")
        XCTAssertNotNil(issue, "an unsigned install must not silently accept any notarized update")
        XCTAssertTrue(issue?.contains("OTHERTEAM1") ?? false, "the message must name the update's team")
        XCTAssertNotNil(AppUpdater.teamPolicyIssue(installedTeam: "", updateTeam: "OTHERTEAM1"))
    }

    func testTeamPolicyBlocksDifferentTeamAndAllowsMatching() {
        XCTAssertNotNil(AppUpdater.teamPolicyIssue(installedTeam: "TEAMAAAAAA", updateTeam: "TEAMBBBBBB"))
        XCTAssertNil(AppUpdater.teamPolicyIssue(installedTeam: "DD2GCQJVB4", updateTeam: "DD2GCQJVB4"))
    }

    // MARK: - Personal-use app-release feed gate

    func testAppReleaseFeedDisabledByDefaultReturnsUpToDateWithoutNetwork() async throws {
        let key = "grokbuild.updates.appReleaseFeedEnabled"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        XCTAssertFalse(UpdateChecker.appReleaseFeedEnabled)
        let started = ContinuousClock.now
        let release = try await UpdateChecker.checkAppRelease()
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1), "gated check must not touch the network")
        XCTAssertFalse(release.updateAvailable)
        XCTAssertEqual(release.latestVersion, release.installedVersion)
        XCTAssertNil(release.downloadURL, "a gated release stub must never be installable")
    }

    // MARK: - Install helper script

    private static let installScriptURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("scripts/grokbuild-install-update.sh")

    private func makeAppBundle(at url: URL, executableName: String, marker: String) throws {
        let macos = url.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.grokbuild.tests.dummy",
            "CFBundleExecutable": executableName,
            "CFBundleName": executableName,
            "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/usr/bin/true"),
            to: macos.appendingPathComponent(executableName)
        )
        try marker.write(
            to: resources.appendingPathComponent("\(marker).txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func adHocSign(_ bundle: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", bundle.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "ad-hoc signing the fixture bundle failed")
    }

    private func exitedPID() throws -> Int32 {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try probe.run()
        probe.waitUntilExit()
        return probe.processIdentifier
    }

    private func runInstallScript(target: URL, newApp: URL) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.installScriptURL.path,
            "--target", target.path,
            "--new-app", newApp.path,
            "--pid", String(try exitedPID()),
            "--no-relaunch",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("updater-hardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testInstallScriptSwapsWholeBundleAndDropsStaleFiles() throws {
        let root = try makeRoot()
        let target = root.appendingPathComponent("Target.app")
        let fresh = root.appendingPathComponent("Fresh.app")
        try makeAppBundle(at: target, executableName: "OldExec", marker: "stale")
        try makeAppBundle(at: fresh, executableName: "NewExec", marker: "fresh")
        try adHocSign(fresh)

        let result = try runInstallScript(target: target, newApp: fresh)
        XCTAssertEqual(result.exitCode, 0, "script failed: \(result.output)")

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("Contents/Resources/fresh.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("Contents/MacOS/NewExec").path))
        XCTAssertFalse(
            fm.fileExists(atPath: target.appendingPathComponent("Contents/Resources/stale.txt").path),
            "files deleted upstream must not survive inside the installed bundle (old ditto-merge bug)"
        )
        XCTAssertFalse(fm.fileExists(atPath: target.appendingPathComponent("Contents/MacOS/OldExec").path))

        let leftovers = try fm.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains(".update-") || $0.contains(".previous-") }
        XCTAssertEqual(leftovers, [], "staging/backup directories must not be left behind")
    }

    func testInstallScriptRefusesUnsignedUpdateAndLeavesTargetUntouched() throws {
        let root = try makeRoot()
        let target = root.appendingPathComponent("Target.app")
        let fresh = root.appendingPathComponent("Fresh.app")
        try makeAppBundle(at: target, executableName: "OldExec", marker: "stale")
        try makeAppBundle(at: fresh, executableName: "NewExec", marker: "fresh")
        // Deliberately unsigned: the staged copy must fail verification.

        let result = try runInstallScript(target: target, newApp: fresh)
        XCTAssertNotEqual(result.exitCode, 0, "an unverifiable staged update must be refused")

        let fm = FileManager.default
        XCTAssertTrue(
            fm.fileExists(atPath: target.appendingPathComponent("Contents/Resources/stale.txt").path),
            "the installed app must be untouched after a refused update"
        )
        XCTAssertTrue(fm.fileExists(atPath: target.appendingPathComponent("Contents/MacOS/OldExec").path))
        XCTAssertFalse(fm.fileExists(atPath: target.appendingPathComponent("Contents/Resources/fresh.txt").path))

        let leftovers = try fm.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains(".update-") || $0.contains(".previous-") }
        XCTAssertEqual(leftovers, [], "refused updates must clean their staging directories")
    }

    // MARK: - Helper staging

    @MainActor
    func testStageHelperCopyProducesExecutableTempCopy() throws {
        guard let helper = AppUpdater.installHelperURL() else {
            return XCTFail("install helper script not found")
        }
        let staged = try AppUpdater.stageHelperCopy(of: helper)
        addTeardownBlock { try? FileManager.default.removeItem(at: staged) }

        XCTAssertNotEqual(staged.path, helper.path, "the helper must run from outside the bundle being replaced")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: staged.path))
        XCTAssertEqual(
            try Data(contentsOf: staged),
            try Data(contentsOf: helper),
            "the staged copy must be byte-identical to the bundled helper"
        )
    }
}
