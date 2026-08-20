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
        XCTAssertTrue(runScript.contains("load_ledger_v2(args.ledger)"))
    }

    func testSlice4B5LifecyclePythonContracts() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "unittest", "scripts.acceptance.tests.test_v3_lifecycle"]
        process.currentDirectoryURL = Self.repoRoot
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("OK"), text)

        let driver = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/candidate_process_driver.py"),
            encoding: .utf8
        )
        XCTAssertTrue(driver.contains("OFFICIAL_CLI_SHA256"))
        XCTAssertTrue(driver.contains("STAGED_PAGER_SHA256"))
        XCTAssertTrue(driver.contains("never replaces"))
        XCTAssertFalse(driver.contains("grok update"))
        let provider = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/loopback_provider.py"),
            encoding: .utf8
        )
        XCTAssertTrue(provider.contains("127.0.0.1"))
        XCTAssertTrue(provider.contains("simulated"))
        XCTAssertFalse(provider.contains("openrouter.ai"))
        XCTAssertFalse(driver.contains("loopback-placeholder-not-live"))
        XCTAssertTrue(provider.contains("worker"))
        XCTAssertTrue(provider.contains("recovery"))
        XCTAssertTrue(provider.contains("missing_usage"))
        XCTAssertTrue(provider.contains("stream_fail"))
        XCTAssertTrue(provider.contains("hold_after_body"))
    }

    func testSlice4B6InstallPythonContracts() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "unittest", "scripts.acceptance.tests.test_v3_install"]
        process.currentDirectoryURL = Self.repoRoot
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("OK"), text)

        let installer = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/candidate_install.py"),
            encoding: .utf8
        )
        XCTAssertTrue(installer.contains("Never replaces"))
        XCTAssertTrue(installer.contains("candidate-runtime"))
        XCTAssertFalse(installer.contains("grok update"))
        XCTAssertTrue(installer.contains("O_EXCL"))
        XCTAssertTrue(installer.contains("distinct timestamps"))
        let runScript = try String(contentsOf: Self.runScript, encoding: .utf8)
        let billableRange = try XCTUnwrap(runScript.range(of: "def _billable_v3"))
        let mainRange = try XCTUnwrap(runScript.range(of: "if __name__"))
        let billable = String(runScript[billableRange.lowerBound..<mainRange.lowerBound])
        XCTAssertFalse(billable.contains("resume_saved_task()"))
        XCTAssertFalse(billable.contains("later unlock path"))
        XCTAssertTrue(billable.contains("4B.4 continuation"))
        XCTAssertFalse(billable.contains("runtime_selection_file="))
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

    func testSlice4V2DryRunReservesOneMillionAndPlansExactlyThreeMillion() throws {
        let manifest = Self.repoRoot
            .appendingPathComponent("scripts/acceptance/manifests/official-provider-slice4-v2.json")
        let result = try runHarness(["--manifest", manifest.path, "--run-id", "20260817T170000Z"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.stdout.contains("\"campaignTokenCeiling\": 4000000"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"plannedAllocation\": 3000000"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"emergencyReserveTokens\": 1000000"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"maxAttempts\": 1"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"appFallbackEnabled\": false"), result.stdout)
    }

    func testSlice4V2AbsoluteCeilingGateExecutesBeforeRuntimeDiscovery() throws {
        let source = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/preflight_v2.py"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("require_runtime_floor"))
        XCTAssertTrue(source.contains("require_absolute_ceiling_support"))
        XCTAssertTrue(source.contains("reactive and cannot prove the absolute 4,000,000-token ceiling"))

        let manifest = Self.repoRoot
            .appendingPathComponent("scripts/acceptance/manifests/official-provider-slice4-v2.json")
        let result = try runHarness([
            "--manifest", manifest.path,
            "--run-id", "20260817T170001Z",
            "--billable",
        ])
        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.stderr.contains("cannot prove the absolute 4,000,000-token ceiling"),
            "The hard ceiling refusal must win before the installed 1.0.4 runtime floor or any catalog discovery: \(result.output)"
        )
    }

    func testLegacyV1BillableAlsoStopsBeforeLaunchOnUnsupportedRuntime() throws {
        let result = try runHarness([
            "--run-id", "20260817T170002Z",
            "--billable",
        ])
        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.stderr.contains("legacy v1 billable execution is retired"), result.stderr)
    }

    func testSlice4V2HostileReceiptAndManifestFixtures() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "unittest", "scripts.acceptance.tests.test_v2"]
        process.currentDirectoryURL = Self.repoRoot
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("OK"), text)
    }

    func testSlice4B4FreshProcessContinuationRejectsLegacyResume() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "unittest", "scripts.acceptance.tests.test_v3_continuation"]
        process.currentDirectoryURL = Self.repoRoot
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("OK"), text)

        let driver = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/driver.py"),
            encoding: .utf8
        )
        XCTAssertTrue(driver.contains("def governed_fresh_process_load"))
        let governed = driver[
            driver.range(of: "def governed_fresh_process_load")!.lowerBound
            ..< driver.range(of: "def resume_saved_task")!.lowerBound
        ]
        XCTAssertFalse(governed.contains("resume_saved_task()"))
        XCTAssertFalse(governed.contains("Resume current task"))
        XCTAssertFalse(governed.contains("not live-wired yet"))
        XCTAssertTrue(governed.contains("session/load"))
        XCTAssertTrue(governed.contains("_select_retained_tab"))
    }

    func testSlice4B4Schema3DryRunPlansGovernedLoad() throws {
        let manifest = Self.repoRoot
            .appendingPathComponent("scripts/acceptance/manifests/fresh-process-continuation-v3.json")
        let result = try runHarness(["--manifest", manifest.path, "--run-id", "20260819T101400Z"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.stdout.contains("\"schemaVersion\": 3"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"billable\": false"), result.stdout)
        XCTAssertTrue(result.stdout.contains("governed_fresh_process_load"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"cleanupAfter\": \"T3\""), result.stdout)
        XCTAssertTrue(result.stdout.contains("S4B4-CONT-T1"), result.stdout)
    }

    func testSlice4B4Schema3BillableStillRefusesAbsoluteCeiling() throws {
        let manifest = Self.repoRoot
            .appendingPathComponent("scripts/acceptance/manifests/fresh-process-continuation-v3.json")
        let result = try runHarness([
            "--manifest", manifest.path,
            "--run-id", "20260819T101401Z",
            "--billable",
        ])
        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.stderr.contains("cannot prove the absolute 4,000,000-token ceiling"),
            "Schema-3 --billable must refuse at the absolute ceiling before runtime discovery or Send: \(result.output)"
        )
        XCTAssertFalse(result.stderr.contains("legacy v1 billable execution is retired"), result.stderr)
    }

    func testSlice4CPaidLockPythonContracts() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "unittest", "scripts.acceptance.tests.test_4c_paid_lock"]
        process.currentDirectoryURL = Self.repoRoot
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("OK"), text)

        let runScript = try String(contentsOf: Self.runScript, encoding: .utf8)
        let fourCRange = try XCTUnwrap(runScript.range(of: "def _billable_4c"))
        let v2Range = try XCTUnwrap(runScript.range(of: "def _billable_v2"))
        let fourC = String(runScript[fourCRange.lowerBound..<v2Range.lowerBound])
        XCTAssertTrue(fourC.contains("runtime_selection_file="))
        XCTAssertTrue(fourC.contains("require_4c_send_ready"))
        XCTAssertFalse(fourC.contains("resume_saved_task()"))
        XCTAssertFalse(fourC.contains("launch_installed()"))
        let preflight = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/preflight_v2.py"),
            encoding: .utf8
        )
        XCTAssertTrue(preflight.contains("require_4c_unlock_predicate"))
        XCTAssertTrue(preflight.contains("reactive and cannot prove the absolute 4,000,000-token ceiling"))
        let billableRange = try XCTUnwrap(runScript.range(of: "def _billable_v3"))
        let mainRange = try XCTUnwrap(runScript.range(of: "if __name__"))
        let billable = String(runScript[billableRange.lowerBound..<mainRange.lowerBound])
        XCTAssertFalse(billable.contains("runtime_selection_file="))
        XCTAssertFalse(billable.contains("resume_saved_task()"))
    }

    func testSlice4CDryRunPlansLockedPaidMatrix() throws {
        let manifest = Self.repoRoot
            .appendingPathComponent("scripts/acceptance/manifests/official-provider-slice4c-paid.json")
        let result = try runHarness(["--manifest", manifest.path, "--run-id", "20260819T210000Z"])
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.stdout.contains("\"schemaVersion\": 4"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"billable\": false"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"campaignId\": \"slice4c-bounded-paid\""), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"campaignTokenCeiling\": 20000000"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"plannedTokenMaximum\": 19000000"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"emergencyReserveTokens\": 1000000"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\"pricingConfirmed\": false"), result.stdout)
        XCTAssertTrue(result.stdout.contains("S4C-NAT-CTRL"), result.stdout)
        XCTAssertTrue(result.stdout.contains("S4C-OAI-H-NO"), result.stdout)
        XCTAssertTrue(result.stdout.contains("S4C-OR-OW-NO"), result.stdout)
        XCTAssertTrue(result.stdout.contains("four-arg armed launch_installed"), result.stdout)
        XCTAssertFalse(result.stdout.contains("governed_fresh_process_load"), result.stdout)
    }

    func testSlice4CBillableStillRefusesAbsoluteCeiling() throws {
        let manifest = Self.repoRoot
            .appendingPathComponent("scripts/acceptance/manifests/official-provider-slice4c-paid.json")
        let result = try runHarness([
            "--manifest", manifest.path,
            "--run-id", "20260819T210001Z",
            "--billable",
        ])
        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(
            result.stderr.contains("cannot prove the absolute 4,000,000-token ceiling"),
            "Schema-4 --billable must refuse at the absolute ceiling before runtime discovery or Send: \(result.output)"
        )
        XCTAssertFalse(result.stderr.contains("catalog prices are not campaign-confirmed"), result.stderr)
        XCTAssertFalse(result.stderr.contains("legacy v1 billable execution is retired"), result.stderr)
    }

    func testSlice4HarnessUsesOnlyAppOwnedEvidenceAndAllowlistedV2Rows() throws {
        let preflight = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/preflight.py"),
            encoding: .utf8
        )
        let driver = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/driver.py"),
            encoding: .utf8
        )
        let v2 = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/receipts_v2.py"),
            encoding: .utf8
        )
        XCTAssertFalse(preflight.contains(".grok/sessions"))
        XCTAssertFalse(driver.contains("grok sessions search"))
        XCTAssertTrue(driver.contains("Perform exactly one billable Send actuator"))
        XCTAssertTrue(v2.contains("START_ONLY"))
        XCTAssertTrue(v2.contains("TERMINAL_ONLY"))
        XCTAssertTrue(v2.contains("packet token allocation exceeded"))
        XCTAssertFalse(v2.contains("evidencePath"))
    }

    private func runHarness(_ arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", Self.runScript.path] + arguments
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
