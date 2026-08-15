import Foundation
import XCTest

/// Slice 5 first-class agentic acceptance harness: fixture-mode contracts at zero provider cost.
final class AcceptanceHarnessTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static var runScript: URL {
        repoRoot.appendingPathComponent("scripts/acceptance/run.py")
    }

    private static var fixturesRoot: URL {
        repoRoot.appendingPathComponent("scripts/acceptance/fixtures")
    }

    func testDryRunIsTheDefaultAndPrintsNoCredentials() throws {
        let result = try runHarness([])
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.stdout.contains("\"mode\": \"dry-run\""), result.stdout)
        XCTAssertFalse(result.stdout.lowercased().contains("sk-"))
        XCTAssertFalse(result.stdout.lowercased().contains("bearer "))
        XCTAssertFalse(result.stdout.contains("responseBody"))
    }

    func testBillableWithoutRunIdFailsClosed() throws {
        let result = try runHarness(["--billable"])
        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.stderr.contains("billable mode requires --run-id"), result.stderr)
    }

    func testCleanupWithoutLedgerRefusesGuessedIDs() throws {
        let result = try runHarness(["--cleanup"])
        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.stderr.contains("incorrect cleanup"), result.stderr)
    }

    func testEveryFixtureDirectoryMatchesItsExpectedOutcome() throws {
        let root = Self.fixturesRoot
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            var isDirectory: ObjCBool = false
            let dir = root.appendingPathComponent(name)
            FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory)
            guard isDirectory.boolValue else { continue }
            let result = try runHarness(["--fixture", dir.path])
            XCTAssertEqual(result.exitCode, 0, "\(name): \(result.output)")
        }
    }

    func testInstalledDriverUsesResumeThenSendAndRefusesBuildCopies() throws {
        let driver = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/driver.py"),
            encoding: .utf8
        )
        XCTAssertTrue(driver.contains("Send and resume session"))
        XCTAssertTrue(driver.contains("def resume_saved_task()"))
        XCTAssertTrue(driver.contains("Resume current task"))
        XCTAssertTrue(driver.contains("refusing to drive a non-installed GrokBuild"))
        XCTAssertTrue(driver.contains("INSTALLED_EXEC = APP_PATH / \"Contents/MacOS/GrokBuild\""))

        let runScript = try String(contentsOf: Self.runScript, encoding: .utf8)
        XCTAssertTrue(runScript.contains("resume_saved_task()"))
        XCTAssertTrue(runScript.contains("resumeAfterQuit"))
        XCTAssertTrue(driver.contains("def stop_turn()"))
        XCTAssertTrue(driver.contains("Stop turn"))
        XCTAssertTrue(runScript.contains("deliberateStop"))
        XCTAssertTrue(runScript.contains("250000"))
    }

    func testSlice6ManifestDryRunUsesQuarterMillionCeiling() throws {
        let manifest = Self.repoRoot
            .appendingPathComponent("scripts/acceptance/manifests/installed-slice6-packet-v1.json")
        let result = try runHarness(["--manifest", manifest.path, "--run-id", "20260814T000000Z"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.stdout.contains("\"anomalyCeilingActualTokens\": 250000"), result.stdout)
        XCTAssertTrue(result.stdout.contains("S6-PKT-T1"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"deliberateStop\": true"), result.stdout)
        XCTAssertTrue(result.stdout.contains("GB-S6-PKT-T1-20260814T000000Z"), result.stdout)
    }

    private func runHarness(_ arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [Self.runScript.path] + arguments
        process.currentDirectoryURL = Self.repoRoot
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, out, err, out + err)
    }
}
