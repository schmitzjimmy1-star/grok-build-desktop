import CryptoKit
import Darwin
import Foundation
import Security
import XCTest
@testable import GrokBuild

/// Slice 4B.5: nonbillable staged-pager lifecycle against a test-only loopback
/// provider. Skips in CI. Never replaces `~/.grok/bin/grok`.
final class Slice4B5LifecycleTests: XCTestCase {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    static let expectedSHA = "f434fa4f17160c8771d3b57bfc62499e252413c4d1fc5ab22bee1a18f2bc933b"
    static let expectedCLIBuild = "1.0.5 (8226242)"
    static let expectedSourceSHA = "822624291de2b544605f439ad1349ae6bdc3cf10"
    static let officialSHA = "39366f7756a090b735cc1df8c93a8c0c3c7871555cf6cbb28f9351ca82936485"
    static let modelID = "s4b5-direct"
    static let providerFacing = "loopback-model"
    static let prompt = "Reply with exactly the word pong."
    static let payloadCeiling: UInt64 = 65_536
    static let maxOutput: UInt64 = 256
    static let tokenCeiling = 2_000_000
    private static var installedSelectionPath: String?
    private static var installError: String?

    override class func setUp() {
        super.setUp()
        let source = ProcessInfo.processInfo.environment["GROKBUILD_SLICE4B3_RUNTIME_SELECTION"] ?? ""
        let inCI = ProcessInfo.processInfo.environment["CI"] != nil
            || ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
        guard !source.isEmpty, !inCI else { return }
        do {
            let installed = try installOwnerPrivateCopy(from: source)
            installedSelectionPath = installed
            _ = setenv("GROKBUILD_SLICE4B6_INSTALLED_SELECTION", installed, 1)
        } catch {
            installError = String(describing: error)
        }
    }

    override func tearDown() {
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = nil
        GrokProcess.cliOverrideForTests = nil
        GrokProcess.armedKeychainClientForTests = nil
        super.tearDown()
    }

    @MainActor
    func testNormalDirectCallSendsOneShotSentinelAndZeroForeignListeners() async throws {
        let result = try await runCase(mode: "normal", maxModelCalls: 1)
        XCTAssertEqual(result.primaryConnections, 1)
        XCTAssertEqual(result.redirectConnections, 0)
        XCTAssertEqual(result.retryConnections, 0)
        XCTAssertEqual(result.authorizations.count, 1)
        let authorization = result.authorizations.first ?? ""
        XCTAssertTrue(authorization.hasPrefix("Bearer "))
        XCTAssertFalse(authorization.contains("sk-"))
        XCTAssertEqual(result.stateAfterSend, .ready)
        XCTAssertTrue(result.assistantText.contains("pong"))
        XCTAssertEqual(result.officialAfter, Self.officialSHA)
        XCTAssertEqual(result.spawnedSHA, Self.expectedSHA)
        XCTAssertFalse(result.reservations.isEmpty, "normal call must leave ledger evidence")
        XCTAssertTrue(
            result.reservations.contains(where: { row in
                (row["actualTokens"] as? Int).map { $0 > 0 } == true
                    || (row["chargedTokens"] as? Int).map { $0 > 0 } == true
            }),
            "normal call must settle or conservatively charge a reservation"
        )
        XCTAssertTrue(result.primaryHosts.allSatisfy { $0.contains("127.0.0.1") })
    }

    @MainActor
    func testRedirectModeLeavesRedirectAndRetryListenersAtZero() async throws {
        let result = try await runCase(mode: "redirect", maxModelCalls: 1, expectReadySend: false)
        XCTAssertEqual(result.redirectConnections, 0)
        XCTAssertEqual(result.retryConnections, 0)
        XCTAssertEqual(result.officialAfter, Self.officialSHA)
    }

    @MainActor
    func testKillAfterReserveChargesAmbiguousFullReservation() async throws {
        try skipUnlessOwnerLocal()
        let harness = try await Slice4B5Harness.start(mode: "hold", maxModelCalls: 1)
        defer { harness.close() }
        let sendTask = Task { await harness.process.send(Self.prompt) }
        let sawConnection = await harness.waitForPrimaryConnection(timeout: 20)
        XCTAssertTrue(sawConnection, "loopback never observed the reserved request")
        let pid = Int32(harness.observedPID)
        XCTAssertNotEqual(pid, 0)
        signal(SIGPIPE, SIG_IGN)
        Darwin.kill(pid, SIGKILL)
        await harness.process.stop()
        _ = await sendTask.value
        let ledger = try harness.readLedger()
        let reservations = ledger["reservations"] as? [[String: Any]] ?? []
        XCTAssertFalse(reservations.isEmpty, "kill-after-reserve must leave ledger evidence")
        for row in reservations {
            XCTAssertTrue(row["actualTokens"] == nil || row["actualTokens"] is NSNull)
            XCTAssertGreaterThan((row["reservedTokens"] as? Int) ?? 0, 0)
        }
        XCTAssertEqual(try harness.officialSHA(), Self.officialSHA)
    }

    @MainActor
    func testMissingUsageKeepsConservativeReservation() async throws {
        let result = try await runCase(mode: "missing_usage", maxModelCalls: 1)
        XCTAssertEqual(result.primaryConnections, 1)
        XCTAssertEqual(result.redirectConnections, 0)
        XCTAssertEqual(result.retryConnections, 0)
        XCTAssertTrue(result.assistantText.contains("pong"))
        XCTAssertFalse(result.reservations.isEmpty)
        XCTAssertEqual(result.officialAfter, Self.officialSHA)
    }

    @MainActor
    func testStreamFailureChargesAmbiguousReservation() async throws {
        let result = try await runCase(mode: "stream_fail", maxModelCalls: 1, expectReadySend: false)
        XCTAssertGreaterThanOrEqual(result.primaryConnections, 1)
        XCTAssertEqual(result.redirectConnections, 0)
        XCTAssertEqual(result.retryConnections, 0)
        XCTAssertFalse(result.reservations.isEmpty)
        for row in result.reservations {
            XCTAssertTrue(row["actualTokens"] == nil || row["actualTokens"] is NSNull)
            XCTAssertGreaterThan((row["reservedTokens"] as? Int) ?? 0, 0)
        }
        XCTAssertEqual(result.officialAfter, Self.officialSHA)
    }

    @MainActor
    func testCallCeilingRefusesASecondModelCall() async throws {
        let result = try await runCase(
            mode: "ordered_reads",
            maxModelCalls: 1,
            expectReadySend: false,
            copyNativeFixtures: true
        )
        XCTAssertEqual(result.primaryConnections, 1)
        XCTAssertEqual(result.redirectConnections, 0)
        XCTAssertEqual(result.retryConnections, 0)
        XCTAssertFalse(result.assistantText.contains("pong"))
        XCTAssertFalse(result.reservations.isEmpty)
        XCTAssertEqual(result.officialAfter, Self.officialSHA)
    }

    @MainActor
    func testKillAfterResponseBeforeSettlementChargesAmbiguousReservation() async throws {
        try skipUnlessOwnerLocal()
        let harness = try await Slice4B5Harness.start(mode: "hold_after_body", maxModelCalls: 1)
        defer { harness.close() }
        let sendTask = Task { await harness.process.send(Self.prompt) }
        let assistant = await harness.waitForAssistantText("pong", timeout: 20)
        XCTAssertTrue(assistant.contains("pong"), "kill-after-response needs streamed content before SIGKILL")
        let pid = Int32(harness.observedPID)
        XCTAssertNotEqual(pid, 0)
        signal(SIGPIPE, SIG_IGN)
        Darwin.kill(pid, SIGKILL)
        await harness.process.stop()
        _ = await sendTask.value
        let ledger = try harness.readLedger()
        let reservations = ledger["reservations"] as? [[String: Any]] ?? []
        XCTAssertFalse(reservations.isEmpty, "kill-after-response must leave ledger evidence")
        for row in reservations {
            XCTAssertTrue(row["actualTokens"] == nil || row["actualTokens"] is NSNull)
            XCTAssertGreaterThan((row["reservedTokens"] as? Int) ?? 0, 0)
        }
        XCTAssertEqual(try harness.officialSHA(), Self.officialSHA)
    }

    @MainActor
    func testKillDuringRestartChargesAmbiguousReservation() async throws {
        try skipUnlessOwnerLocal()
        let harness = try await Slice4B5Harness.start(
            mode: "hold",
            maxModelCalls: 1,
            allocations: [
                ("s4b5-restart-1", "S4B5-RESTART-1"),
                ("s4b5-restart-2", "S4B5-RESTART-2"),
            ],
            activeAllocation: "s4b5-restart-1"
        )
        defer { harness.close() }
        await harness.process.stop()
        try await harness.rearm(allocationID: "s4b5-restart-2", resumeSessionID: nil)
        try await killAfterPrimaryConnection(harness: harness)
        let ledger = try harness.readLedger()
        let reservations = ledger["reservations"] as? [[String: Any]] ?? []
        XCTAssertFalse(reservations.isEmpty)
        XCTAssertEqual(try harness.officialSHA(), Self.officialSHA)
    }

    @MainActor
    func testStopCancelBeforeTeardownKeepsReservationEvidence() async throws {
        try skipUnlessOwnerLocal()
        let harness = try await Slice4B5Harness.start(mode: "hold", maxModelCalls: 1)
        defer { harness.close() }
        let sendTask = Task { await harness.process.send(Self.prompt) }
        let sawCancelConnection = await harness.waitForPrimaryConnection(timeout: 20)
        XCTAssertTrue(sawCancelConnection, "loopback never observed the reserved request")
        harness.process.interrupt()
        _ = await sendTask.value
        await harness.process.stop()
        let ledger = try harness.readLedger()
        let reservations = ledger["reservations"] as? [[String: Any]] ?? []
        XCTAssertFalse(reservations.isEmpty)
        XCTAssertEqual(try harness.officialSHA(), Self.officialSHA)
    }

    @MainActor
    func testOrderedNativeReadsUseAllowlistedToolsOnly() async throws {
        let result = try await runCase(mode: "ordered_reads", maxModelCalls: 4, copyNativeFixtures: true)
        XCTAssertGreaterThanOrEqual(result.primaryConnections, 1)
        XCTAssertEqual(result.redirectConnections, 0)
        XCTAssertEqual(result.retryConnections, 0)
        XCTAssertEqual(result.officialAfter, Self.officialSHA)
    }

    @MainActor
    func testWorkerCoordinationUsesTaskAndWaitOnly() async throws {
        let result = try await runCase(mode: "worker", maxModelCalls: 8, copyNativeFixtures: true)
        XCTAssertGreaterThanOrEqual(result.primaryConnections, 1)
        XCTAssertEqual(result.redirectConnections, 0)
        XCTAssertEqual(result.retryConnections, 0)
        XCTAssertEqual(result.officialAfter, Self.officialSHA)
    }

    @MainActor
    func testRecoveryMissingThenRecoveredRead() async throws {
        let result = try await runCase(mode: "recovery", maxModelCalls: 3, copyNativeFixtures: true)
        XCTAssertGreaterThanOrEqual(result.primaryConnections, 1)
        XCTAssertEqual(result.redirectConnections, 0)
        XCTAssertEqual(result.retryConnections, 0)
        XCTAssertEqual(result.officialAfter, Self.officialSHA)
    }

    @MainActor
    func testContinuationUsesThreeAllocationsAndSessionLoad() async throws {
        try skipUnlessOwnerLocal()
        let harness = try await Slice4B5Harness.start(
            mode: "normal",
            maxModelCalls: 1,
            allocations: [
                ("s4b5-cont-1", "S4B5-CONT-T1"),
                ("s4b5-cont-2", "S4B5-CONT-T2"),
                ("s4b5-cont-3", "S4B5-CONT-T3"),
            ],
            activeAllocation: "s4b5-cont-1"
        )
        defer { harness.close() }
        XCTAssertEqual(harness.process.state, .ready, String(describing: harness.process.state))
        let firstSent = await sendPrompt(harness.process)
        XCTAssertTrue(firstSent)
        let backend = try XCTUnwrap(harness.process.sessionId)
        await harness.process.stop()

        for allocation in ["s4b5-cont-2", "s4b5-cont-3"] {
            try await harness.rearm(allocationID: allocation, resumeSessionID: backend)
            XCTAssertEqual(harness.process.state, .ready, String(describing: harness.process.state))
            XCTAssertEqual(harness.process.sessionId, backend)
            let continued = await sendPrompt(harness.process)
            XCTAssertTrue(continued)
            await harness.process.stop()
        }
        XCTAssertEqual(try harness.officialSHA(), Self.officialSHA)
        let snapshot = try harness.finishSnapshot()
        XCTAssertEqual(snapshot.redirectConnections, 0)
        XCTAssertEqual(snapshot.retryConnections, 0)
    }

    @MainActor
    private func runCase(
        mode: String,
        maxModelCalls: Int,
        expectReadySend: Bool = true,
        copyNativeFixtures: Bool = false
    ) async throws -> Slice4B5Result {
        try skipUnlessOwnerLocal()
        let harness = try await Slice4B5Harness.start(
            mode: mode,
            maxModelCalls: maxModelCalls,
            copyNativeFixtures: copyNativeFixtures
        )
        defer { harness.close() }
        var assistant = ""
        var stateAfterSend = harness.process.state
        if harness.process.state == .ready {
            let sent = await sendPrompt(harness.process)
            stateAfterSend = harness.process.state
            if expectReadySend {
                if !sent {
                    try? dumpFailure(harness: harness)
                }
                XCTAssertTrue(sent, String(describing: harness.process.state))
                assistant = await harness.waitForAssistantText("pong", timeout: 2)
                if !assistant.contains("pong") {
                    try? dumpFailure(harness: harness)
                }
                XCTAssertTrue(
                    assistant.contains("pong"),
                    "assistant text must come from the streamed turn, got \(assistant)"
                )
            }
        } else if expectReadySend {
            try? dumpFailure(harness: harness)
            XCTFail("expected ready pager, got \(String(describing: harness.process.state))")
        }
        await harness.process.stop()
        let snapshot = try harness.finishSnapshot()
        return Slice4B5Result(
            primaryConnections: snapshot.primaryConnections,
            redirectConnections: snapshot.redirectConnections,
            retryConnections: snapshot.retryConnections,
            authorizations: snapshot.authorizations,
            assistantText: assistant,
            stateAfterSend: stateAfterSend,
            officialAfter: try harness.officialSHA(),
            spawnedSHA: harness.process.launchReceipt?.candidateBinarySHA256,
            reservations: (try? harness.readLedger())?["reservations"] as? [[String: Any]] ?? [],
            primaryHosts: snapshot.primaryHosts
        )
    }

    @MainActor
    private func killAfterPrimaryConnection(harness: Slice4B5Harness) async throws {
        let sendTask = Task { await harness.process.send(Self.prompt) }
        let sawConnection = await harness.waitForPrimaryConnection(timeout: 20)
        XCTAssertTrue(sawConnection, "loopback never observed the reserved request")
        let pid = Int32(harness.observedPID)
        XCTAssertNotEqual(pid, 0)
        signal(SIGPIPE, SIG_IGN)
        Darwin.kill(pid, SIGKILL)
        await harness.process.stop()
        _ = await sendTask.value
    }

    private func skipUnlessOwnerLocal() throws {
        let selectionPath = ProcessInfo.processInfo.environment["GROKBUILD_SLICE4B3_RUNTIME_SELECTION"] ?? ""
        try XCTSkipIf(selectionPath.isEmpty, "Set GROKBUILD_SLICE4B3_RUNTIME_SELECTION to the signed digest-staged pager selection file")
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["CI"] != nil
                || ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
            "Signed pager lifecycle is owner-local and must not run in CI"
        )
        if let installError = Self.installError {
            XCTFail("4B.6 owner-private install failed: \(installError)")
        }
    }

    func testSlice4B6InstalledSelectionIsLeasableAndDistinctFromOfficialCLI() throws {
        try skipUnlessOwnerLocal()
        let path = try XCTUnwrap(Self.installedSelectionPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let lease = try XCTUnwrap(
            GrokCandidateRuntimeAuthority.acquireLease(
                selectionPath: path,
                expectedCLIBuild: Self.expectedCLIBuild
            )
        )
        XCTAssertEqual(lease.identity.binarySHA256, Self.expectedSHA)
        XCTAssertEqual(lease.identity.cliBuild, Self.expectedCLIBuild)
        XCTAssertNotEqual(
            URL(fileURLWithPath: lease.identity.binaryPath).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/bin/grok").path
        )
        XCTAssertEqual(
            try sha256File(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/bin/grok")),
            Self.officialSHA
        )
    }

    func testSlice4B6OrdinaryResolverNeverScansCandidateRuntime() throws {
        let url = Self.repoRoot.appendingPathComponent("GrokBuild/Services/GrokCLIRuntimeAuthority.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let lookupStart = try XCTUnwrap(source.range(of: "enum GrokCLIRuntimeResolver"))
        let lookupEnd = try XCTUnwrap(source.range(of: "enum GrokCandidateRuntimeAuthority"))
        let lookup = String(source[lookupStart.lowerBound..<lookupEnd.lowerBound])
        XCTAssertFalse(lookup.contains("candidate-runtime"))
        XCTAssertFalse(lookup.contains("Application Support/GrokBuild/candidate"))
        XCTAssertTrue(lookup.contains(".grok/bin/grok"))
        XCTAssertTrue(source.contains("never scans"))
        let located = GrokCLIRuntimeResolver.locateOfficial(
            testOverride: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: ["app"]
        )
        XCTAssertEqual(located?.path, "/usr/bin/true")
        XCTAssertFalse(located?.path.contains("candidate-runtime") == true)
    }

    func testSlice4B6PaidUnlockStaysLockedInHarnessSource() throws {
        let runScript = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/run.py"),
            encoding: .utf8
        )
        let preflight = try String(
            contentsOf: Self.repoRoot.appendingPathComponent("scripts/acceptance/harness/preflight_v2.py"),
            encoding: .utf8
        )
        XCTAssertTrue(preflight.contains("cannot prove the absolute 4,000,000-token ceiling"))
        let billableRange = try XCTUnwrap(runScript.range(of: "def _billable_v3"))
        let mainRange = try XCTUnwrap(runScript.range(of: "if __name__"))
        let billable = String(runScript[billableRange.lowerBound..<mainRange.lowerBound])
        XCTAssertFalse(billable.contains("resume_saved_task()"))
        XCTAssertFalse(billable.contains("later unlock path"))
        XCTAssertTrue(billable.contains("4B.4 continuation"))
        XCTAssertTrue(billable.contains("governed_fresh_process_load"))
        XCTAssertTrue(billable.contains("launch_installed()"))
        XCTAssertFalse(billable.contains("runtime_selection_file="))
        XCTAssertTrue(runScript.contains("require_absolute_ceiling_support()"))
    }

    private static func installOwnerPrivateCopy(from source: String) throws -> String {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-s4b6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dest.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = repoRoot
        process.arguments = [
            "python3", "-m", "scripts.acceptance.harness.candidate_install",
            "install",
            "--source", source,
            "--dest", dest.path,
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0, !out.isEmpty else {
            throw Slice4B5Error.failed("4B.6 install failed: \(err)\(out)")
        }
        return out
    }

    @MainActor
    private func sendPrompt(_ process: GrokProcess) async -> Bool {
        await process.send(Self.prompt)
    }

    func testArmedSessionPromptTimeoutIsBounded() {
        XCTAssertEqual(GrokProcess.armedSessionPromptTimeout, .seconds(90))
        XCTAssertEqual(
            GrokProcess.jsonRPCTimeoutSeconds(method: "initialize", isArmed: true, requestedSeconds: 15),
            GrokProcess.armedACPHandshakeTimeoutSeconds
        )
    }

    private func dumpFailure(harness: Slice4B5Harness) throws {
        let snapshot = try harness.finishSnapshot()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("s4b5-last-fail", isDirectory: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: harness.home, to: destination)
        XCTContext.runActivity(named: "s4b5-failure") { _ in
            XCTFail(
                "loopback primary=\(snapshot.primaryConnections) redirect=\(snapshot.redirectConnections) retry=\(snapshot.retryConnections) auth=\(snapshot.authorizations) assistant=\(harness.assistantChunks) home=\(destination.path)"
            )
        }
    }
}

private enum Slice4B5Error: Error {
    case failed(String)
}

private struct Slice4B5Result {
    let primaryConnections: Int
    let redirectConnections: Int
    let retryConnections: Int
    let authorizations: [String]
    let assistantText: String
    let stateAfterSend: GrokProcessState
    let officialAfter: String
    let spawnedSHA: String?
    let reservations: [[String: Any]]
    let primaryHosts: [String]
}

private struct Slice4B5Snapshot {
    let primaryConnections: Int
    let redirectConnections: Int
    let retryConnections: Int
    let authorizations: [String]
    let primaryHosts: [String]
}

private final class Slice4B5Loopback {
    let process: Process
    let identity: [String: Any]
    let statusFile: URL
    private let stdin: FileHandle

    init(process: Process, identity: [String: Any], statusFile: URL, stdin: FileHandle) {
        self.process = process
        self.identity = identity
        self.statusFile = statusFile
        self.stdin = stdin
    }

    static func start(mode: String, workDirectory: URL) throws -> Slice4B5Loopback {
        let statusFile = workDirectory.appendingPathComponent("loopback-status.json")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = Slice4B5LifecycleTests.repoRoot
        process.arguments = [
            "python3", "-m", "scripts.acceptance.harness.loopback_provider",
            "--mode", mode,
            "--status-file", statusFile.path,
        ]
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()
        guard let line = readJSONLine(from: output.fileHandleForReading) else {
            let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw Slice4B5Error.failed("loopback provider failed to start: \(stderr)")
        }
        return Slice4B5Loopback(
            process: process,
            identity: line,
            statusFile: statusFile,
            stdin: input.fileHandleForWriting
        )
    }

    func close() {
        try? stdin.close()
        process.terminate()
        process.waitUntilExit()
    }

    func snapshot() throws -> Slice4B5Snapshot {
        let data = try Data(contentsOf: statusFile)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let object else { throw Slice4B5Error.failed("loopback status was not an object") }
        let primary = object["primary"] as? [String: Any] ?? [:]
        let redirect = object["redirect"] as? [String: Any] ?? [:]
        let retry = object["retry"] as? [String: Any] ?? [:]
        return Slice4B5Snapshot(
            primaryConnections: primary["connections"] as? Int ?? 0,
            redirectConnections: redirect["connections"] as? Int ?? 0,
            retryConnections: retry["connections"] as? Int ?? 0,
            authorizations: primary["authorization"] as? [String] ?? [],
            primaryHosts: primary["hosts"] as? [String] ?? []
        )
    }
}

private final class Slice4B5StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = ""
    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        stored += text
    }
    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

private final class Slice4B5PIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: pid_t = 0
    var value: pid_t {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}

private final class Slice4B5Harness {
    let home: URL
    let workspace: URL
    let authority: URL
    let loopback: Slice4B5Loopback
    let officialBefore: String
    private(set) var process: GrokProcess
    private let observedPIDBox = Slice4B5PIDBox()
    var observedPID: pid_t { observedPIDBox.value }
    private let previousHome: String?
    private let selectionPath: String
    private let sentinel: [UInt8]
    private let allocations: [(String, String)]
    private var lease: GrokCandidateExecutionLease?
    private var eventPump: Task<Void, Never>?
    private let assistantBox = Slice4B5StringBox()
    var assistantChunks: String { assistantBox.value }

    func collectedAssistantText() -> String {
        assistantChunks
    }

    func waitForAssistantText(_ needle: String, timeout: TimeInterval) async -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let text = assistantChunks
            if text.contains(needle) {
                return text
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return assistantChunks
    }

    init(
        home: URL,
        workspace: URL,
        authority: URL,
        loopback: Slice4B5Loopback,
        officialBefore: String,
        process: GrokProcess,
        previousHome: String?,
        selectionPath: String,
        sentinel: [UInt8],
        allocations: [(String, String)]
    ) {
        self.home = home
        self.workspace = workspace
        self.authority = authority
        self.loopback = loopback
        self.officialBefore = officialBefore
        self.process = process
        self.previousHome = previousHome
        self.selectionPath = selectionPath
        self.sentinel = sentinel
        self.allocations = allocations
    }

    static func start(
        mode: String,
        maxModelCalls: Int,
        copyNativeFixtures: Bool = false,
        allocations: [(String, String)] = [("s4b5-normal", "S4B5-NORMAL")],
        activeAllocation: String = "s4b5-normal"
    ) async throws -> Slice4B5Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-s4b5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let authority = root.appendingPathComponent("authority", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: authority, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workspace.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: authority.path)
        if copyNativeFixtures {
            let source = Slice4B5LifecycleTests.repoRoot
                .appendingPathComponent("scripts/acceptance/fixtures/.slice4-native-tools")
            let destination = workspace
                .appendingPathComponent("scripts/acceptance/fixtures/.slice4-native-tools")
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: source, to: destination)
        }

        let loopback = try Slice4B5Loopback.start(mode: mode, workDirectory: root)
        guard let baseURL = loopback.identity["baseUrl"] as? String else {
            throw Slice4B5Error.failed("loopback identity omitted baseUrl")
        }
        try writeIsolatedConfig(home: home, baseURL: baseURL)
        try writeManifest(
            directory: authority,
            baseURL: baseURL,
            allocations: allocations,
            maxModelCalls: maxModelCalls
        )

        let previousHome = getenv("HOME").map { String(cString: $0) }
        XCTAssertEqual(setenv("HOME", home.path, 1), 0)
        let officialURL = (previousHome.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent(".grok/bin/grok")
        let harness = Slice4B5Harness(
            home: home,
            workspace: workspace,
            authority: authority,
            loopback: loopback,
            officialBefore: try sha256File(officialURL),
            process: GrokProcess(),
            previousHome: previousHome,
            selectionPath: ProcessInfo.processInfo.environment["GROKBUILD_SLICE4B6_INSTALLED_SELECTION"]
                ?? ProcessInfo.processInfo.environment["GROKBUILD_SLICE4B3_RUNTIME_SELECTION"]
                ?? "",
            sentinel: Array("S4B5-\(UUID().uuidString)-END".utf8),
            allocations: allocations
        )
        try await harness.armProcess(
            allocationID: activeAllocation,
            resumeSessionID: Optional<String>.none,
            maxModelCalls: maxModelCalls
        )
        return harness
    }

    func rearm(allocationID: String, resumeSessionID: String?) async throws {
        process = GrokProcess()
        try await armProcess(allocationID: allocationID, resumeSessionID: resumeSessionID, maxModelCalls: 1)
    }

    func close() {
        eventPump?.cancel()
        loopback.close()
        if let previousHome {
            setenv("HOME", previousHome, 1)
        } else {
            unsetenv("HOME")
        }
        try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
        GrokProcess.armedKeychainClientForTests = nil
        GrokProcess.cliOverrideForTests = nil
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = nil
    }

    func finishSnapshot() throws -> Slice4B5Snapshot {
        try loopback.snapshot()
    }

    func waitForPrimaryConnection(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let snapshot = try? loopback.snapshot(), snapshot.primaryConnections > 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    func readLedger() throws -> [String: Any] {
        let data = try Data(contentsOf: authority.appendingPathComponent("ledger.json"))
        if data.isEmpty { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    func officialSHA() throws -> String {
        let home = previousHome.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory())
        return try sha256File(home.appendingPathComponent(".grok/bin/grok"))
    }

    private func armProcess(allocationID: String, resumeSessionID: String?, maxModelCalls: Int) async throws {
        let lease = GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: selectionPath,
            expectedCLIBuild: Slice4B5LifecycleTests.expectedCLIBuild
        )
        guard let lease else { throw Slice4B5Error.failed("failed to lease the staged pager") }
        self.lease = lease
        XCTAssertEqual(lease.identity.binarySHA256, Slice4B5LifecycleTests.expectedSHA)
        let contract = try makeContract(lease: lease, allocationID: allocationID, maxModelCalls: maxModelCalls)
        GrokProcess.armedKeychainClientForTests = GrokArmedCredentialKeychainClient { _, item in
            item?.pointee = [Data(self.sentinel)] as NSArray
            return errSecSuccess
        }
        GrokProcess.cliOverrideForTests = URL(fileURLWithPath: "/usr/bin/true")
        let pidBox = observedPIDBox
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { pid in
            pidBox.value = pid
        }
        eventPump?.cancel()
        let process = process
        let chunks = assistantBox
        eventPump = Task.detached { [weak process] in
            guard let process else { return }
            for await event in process.acpEventStream {
                switch event {
                case .messageChunk(let text):
                    chunks.append(text)
                case .permissionRequest(let request):
                    let option = request.options.first(where: { $0.kind.contains("allow") })
                        ?? request.options.first
                    if let option {
                        process.respondToPermission(request, with: option.id)
                    } else {
                        process.rejectPermission(request, reason: "no allow option")
                    }
                case .turnCompleted:
                    process.acknowledgeTurnCompletionBridge(authoritative: true)
                case .turnCompletionReceiptMissing:
                    process.acknowledgeTurnCompletionBridge(authoritative: false)
                default:
                    break
                }
            }
        }
        await process.start(
            workspace: Workspace(name: "s4b5", path: workspace),
            options: GrokLaunchOptions(
                noMemory: true,
                model: Slice4B5LifecycleTests.modelID,
                expectedEffectiveModelID: Slice4B5LifecycleTests.providerFacing,
                disableWebSearch: true,
                noSubagents: false,
                resumeSessionID: resumeSessionID,
                hardBudgetLaunchContract: contract
            )
        )
    }

    private func makeContract(
        lease: GrokCandidateExecutionLease,
        allocationID: String,
        maxModelCalls: Int
    ) throws -> HardBudgetLaunchContract {
        guard let baseURL = loopback.identity["baseUrl"] as? String else {
            throw Slice4B5Error.failed("loopback identity omitted baseUrl")
        }
        let manifest = authority.appendingPathComponent("manifest-v3.json")
        let ledger = authority.appendingPathComponent("ledger.json")
        let manifestSHA = try sha256File(manifest)
        let endpointSHA = sha256Hex("\(baseURL)/chat/completions")
        let bound = Int(Slice4B5LifecycleTests.payloadCeiling + Slice4B5LifecycleTests.maxOutput)
        let route = AcceptanceHardBudgetRoute(
            model: Slice4B5LifecycleTests.providerFacing,
            endpointSHA256: endpointSHA,
            apiBackend: "chat_completions",
            requestBoundTokens: bound,
            maxPayloadBytes: Int(Slice4B5LifecycleTests.payloadCeiling),
            maxOutputTokens: Int(Slice4B5LifecycleTests.maxOutput),
            boundProvenanceSHA256: String(repeating: "a", count: 64),
            managedProviderID: "openrouter",
            authScheme: "bearer"
        )
        let packet = AcceptanceTurnBudget(
            packetID: allocations.first(where: { $0.0 == allocationID })?.1 ?? allocationID,
            allocationID: allocationID,
            marker: "EXACT-V3",
            promptHash: sha256Hex(Slice4B5LifecycleTests.prompt),
            tokenAllocation: Slice4B5LifecycleTests.tokenCeiling,
            maxModelCalls: maxModelCalls,
            route: route
        )
        let authorization = AcceptanceBudgetAuthorization(
            runID: "s4b5-lifecycle",
            campaignTokenCeiling: 20_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: manifestSHA,
            expectedCLIBuild: Slice4B5LifecycleTests.expectedCLIBuild,
            budget: packet,
            authorizationManifestPath: "/tmp/authorization.json",
            hardBudgetCLIManifestPath: manifest.path,
            hardBudgetLedgerPath: ledger.path,
            candidateExecutionLease: lease,
            credentialAuthorizationV3: route.credentialAuthorizationV3
        )
        guard let expectation = ArmedV3DispatchExpectation.tryMake(
            authorization: authorization,
            selectedModelID: Slice4B5LifecycleTests.modelID,
            customModel: CustomModel(
                id: Slice4B5LifecycleTests.modelID,
                model: Slice4B5LifecycleTests.providerFacing,
                baseURL: baseURL,
                apiBackend: .chatCompletions,
                providerID: "openrouter"
            ),
            provider: Provider(
                id: "openrouter",
                name: "OpenRouter",
                baseURL: baseURL,
                authScheme: .bearer
            ),
            candidate: lease.identity
        ) else {
            throw Slice4B5Error.failed("loopback OpenRouter dispatch did not bind")
        }
        guard let contract = HardBudgetLaunchContract(
            manifestPath: manifest.path,
            ledgerPath: ledger.path,
            allocationID: allocationID,
            expectedManifestSHA256: manifestSHA,
            candidateExecutionLease: lease,
            credentialAuthorizationV3: expectation.credentialAuthorizationV3,
            dispatchExpectation: expectation
        ) else {
            throw Slice4B5Error.failed("hard-budget contract refused the loopback latch")
        }
        return contract
    }
}

private func writeIsolatedConfig(home: URL, baseURL: String) throws {
    let grok = home.appendingPathComponent(".grok", isDirectory: true)
    try FileManager.default.createDirectory(at: grok, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: grok.path)
    let body = """
    [endpoints]
    models_list_url = "\(baseURL)/models"

    [model_providers.openrouter]
    name = "OpenRouter"
    base_url = "\(baseURL)"

    [model.s4b5-direct]
    model = "loopback-model"
    model_provider = "openrouter"
    api_backend = "chat_completions"
    max_completion_tokens = 256

    [models]
    default = "s4b5-direct"
    """
    let config = grok.appendingPathComponent("config.toml")
    try Data(body.utf8).write(to: config)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
}

private func writeManifest(
    directory: URL,
    baseURL: String,
    allocations: [(String, String)],
    maxModelCalls: Int
) throws {
    let endpointSHA = sha256Hex("\(baseURL)/chat/completions")
    let bound = Slice4B5LifecycleTests.payloadCeiling + Slice4B5LifecycleTests.maxOutput
    let tools = [
        "GrokBuild:get_task_output",
        "GrokBuild:kill_task",
        "GrokBuild:read_file",
        "GrokBuild:task",
        "GrokBuild:wait_tasks",
    ]
    let route: [String: Any] = [
        "routeId": "v3." + sha256Hex(
            ["openrouter", "loopback-model", endpointSHA, "chat_completions", "bearer"].joined(separator: "\u{0}")
        ),
        "providerId": "openrouter",
        "providerFacingModel": "loopback-model",
        "endpointSha256": endpointSHA,
        "apiBackend": "chat_completions",
        "credentialTransport": "fd_v1",
        "authScheme": "bearer",
        "maxFinalSerializedPayloadBytes": Int(Slice4B5LifecycleTests.payloadCeiling),
        "maxOutputTokens": Int(Slice4B5LifecycleTests.maxOutput),
        "conservativeRequestBoundTokens": Int(bound),
        "allocationTokenCeiling": Slice4B5LifecycleTests.tokenCeiling,
        "maxModelCalls": maxModelCalls,
        "textOnly": true,
        "remoteContextForbidden": true,
        "multimodalForbidden": true,
        "redirectDisabled": true,
        "retryDisabled": true,
        "toolIsolation": [
            "authProviderHelpersDisabled": true,
            "terminalDisabled": true,
            "externalMcpDisabled": true,
            "hooksDisabled": true,
            "pluginsDisabled": true,
            "lspDisabled": true,
            "workflowsDisabled": true,
            "schedulerDisabled": true,
            "protectedAuthorityFs": true,
            "workspaceFsConfined": true,
            "samplerTransportRetriesDisabled": true,
            "allowedToolIds": tools,
        ] as [String: Any],
    ]
    let projection = Data("""
    [{"catalogKey":"s4b5-direct","model":"loopback-model","modelProvider":"openrouter","apiBackend":"chat_completions","authScheme":"bearer","baseUrl":"\(baseURL)"}]
    """.utf8)
    let rows: [[String: Any]] = allocations.map { allocation in
        [
            "id": allocation.0,
            "packetId": allocation.1,
            "promptSha256": sha256Hex(Slice4B5LifecycleTests.prompt),
            "tokenCeiling": Slice4B5LifecycleTests.tokenCeiling,
            "maxModelCalls": maxModelCalls,
            "routeExpectation": route,
        ]
    }
    let manifest: [String: Any] = [
        "schemaVersion": 3,
        "campaignId": "s4b5-lifecycle",
        "campaignPolicy": [
            "schemaVersion": 3,
            "absoluteTokenCeiling": 20_000_000,
            "allocatableTokenCeiling": 19_000_000,
            "unreachableReserveTokens": 1_000_000,
        ],
        "candidateExpectation": [
            "cliBuild": Slice4B5LifecycleTests.expectedCLIBuild,
            "binarySha256": Slice4B5LifecycleTests.expectedSHA,
            "sourceCommitSha": Slice4B5LifecycleTests.expectedSourceSHA,
        ],
        "configExpectation": [
            "sourceKind": "resolved-managed-provider",
            "generation": 1,
            "managedProviderId": "openrouter",
            "configProjectionSha256": sha256Hex(projection),
        ],
        "allocations": rows,
    ]
    let data = try JSONSerialization.data(withJSONObject: manifest)
    try data.write(to: directory.appendingPathComponent("manifest-v3.json"))
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: directory.appendingPathComponent("manifest-v3.json").path
    )
    let ledger = directory.appendingPathComponent("ledger.json")
    try Data().write(to: ledger)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledger.path)
}

private func sha256File(_ url: URL) throws -> String {
    sha256Hex(try Data(contentsOf: url))
}

private func sha256Hex(_ value: String) -> String {
    sha256Hex(Data(value.utf8))
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func readJSONLine(from handle: FileHandle) -> [String: Any]? {
    var buffer = Data()
    while buffer.count < 8_192 {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        buffer.append(chunk)
        if let range = buffer.firstIndex(of: 0x0a) {
            let line = buffer.subdata(in: buffer.startIndex..<range)
            return (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        }
    }
    return (try? JSONSerialization.jsonObject(with: buffer)) as? [String: Any]
}
