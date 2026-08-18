import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import GrokBuild

final class CandidateRuntimeAuthorityTests: XCTestCase {
    private let sourceSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let requirement = "identifier \"com.grokbuild.fixture\" and anchor apple generic"

    override func tearDown() {
        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = nil
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = nil
        GrokCredentialTransportV1.outboundFrameFaultForTests = .none
        GrokCredentialTransportV1.socketPairCreatedObserverForTests = nil
        super.tearDown()
    }

    func testAppOwnedSpawnGateClosesSocketpairRaceBeforeConcurrentProcessLaunch() throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        let socketCreated = DispatchSemaphore(value: 0)
        let allowDescriptorPolicy = DispatchSemaphore(value: 0)
        let candidateFinished = DispatchSemaphore(value: 0)
        let competingFinished = DispatchSemaphore(value: 0)
        final class ResultBox: @unchecked Sendable {
            var candidateSucceeded = false
            var competingSucceeded = false
        }
        let result = ResultBox()
        GrokCredentialTransportV1.socketPairCreatedObserverForTests = {
            socketCreated.signal()
            _ = allowDescriptorPolicy.wait(timeout: .now() + 2)
        }
        let payload = try XCTUnwrap(GrokCredentialTransportPayload(Array("spawn-gate-fake".utf8)))
        DispatchQueue.global().async {
            defer { candidateFinished.signal() }
            guard let launched = try? GrokCandidateProcessLauncher.spawn(
                lease: lease,
                arguments: [],
                environment: ["HOME": fixture.container.path, "PATH": "/usr/bin:/bin"],
                currentDirectory: fixture.container,
                credentialTransport: payload
            ) else { return }
            try? launched.standardInput.close()
            while launched.process.isRunning { usleep(10_000) }
            result.candidateSucceeded = true
        }
        XCTAssertEqual(socketCreated.wait(timeout: .now() + 2), .success)

        DispatchQueue.global().async {
            defer { competingFinished.signal() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            guard (try? GrokChildProcessSpawnGate.run(process)) != nil else { return }
            process.waitUntilExit()
            result.competingSucceeded = process.terminationStatus == 0
        }
        XCTAssertEqual(competingFinished.wait(timeout: .now() + 0.1), .timedOut)
        allowDescriptorPolicy.signal()
        XCTAssertEqual(candidateFinished.wait(timeout: .now() + 4), .success)
        XCTAssertEqual(competingFinished.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(result.candidateSucceeded)
        XCTAssertTrue(result.competingSucceeded)
    }

    func testFakeCredentialTransportUsesRealCandidateSpawnAndLeaksNowhere() throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))

        var sentinel = Array("S4B2-FAKE-\(UUID().uuidString)-END".utf8)
        defer { _ = sentinel.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        let payload = try XCTUnwrap(GrokCredentialTransportPayload(sentinel))
        let decoySource = Darwin.open("/dev/null", O_RDONLY)
        XCTAssertGreaterThanOrEqual(decoySource, 0)
        let decoy = fcntl(decoySource, F_DUPFD, 512)
        Darwin.close(decoySource)
        XCTAssertGreaterThanOrEqual(decoy, 512)
        defer { if decoy >= 0 { Darwin.close(decoy) } }
        XCTAssertEqual(fcntl(decoy, F_SETFD, 0), 0)

        let launched = try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: [],
            environment: [
                "HOME": fixture.container.path,
                "PATH": "/usr/bin:/bin",
                "XAI_API_KEY": "must-not-cross",
                "OPENAI_API_KEY": "must-not-cross",
                "DYLD_INSERT_LIBRARIES": "must-not-cross",
                "GROK_HARD_TOKEN_BUDGET_ALLOCATION": "fixture-allocation",
            ],
            currentDirectory: fixture.container,
            credentialTransport: payload
        )
        try launched.standardInput.close()
        let output = try XCTUnwrap(try launched.standardOutput.fileHandleForReading.readToEnd())
        let error = try launched.standardError.fileHandleForReading.readToEnd() ?? Data()
        waitForExit(launched.process)
        XCTAssertEqual(output, Data("transport=fd-v1,result=ok\n".utf8))
        XCTAssertTrue(error.isEmpty)
        XCTAssertNil(output.range(of: Data(sentinel)))
        XCTAssertNil(error.range(of: Data(sentinel)))

        let files = try FileManager.default.subpathsOfDirectory(atPath: fixture.container.path)
        for relative in files {
            let path = fixture.container.appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  let data = try? Data(contentsOf: path) else { continue }
            XCTAssertNil(data.range(of: Data(sentinel)), "Fake transport bytes persisted in fixture artifact")
        }
        XCTAssertEqual(kill(launched.process.processIdentifier, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testFakeCredentialTransportRejectsBoundsBadPeerAndTimeoutWithoutZombie() throws {
        XCTAssertNil(GrokCredentialTransportPayload([]))
        XCTAssertNil(GrokCredentialTransportPayload(
            [UInt8](repeating: 7, count: GrokCredentialTransportPayload.maximumByteCount + 1)
        ))

        for behavior in [
            CandidateRuntimeTestFixture.CredentialReceiverBehavior.malformedAcknowledgement,
            .timeout,
            .trailingReadyByte,
            .slowDripAcknowledgement,
        ] {
            let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable(behavior: behavior)
            defer { try? FileManager.default.removeItem(at: fixture.container) }
            CandidateRuntimeTestFixture.installSignatureOverride()
            let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
                selectionPath: fixture.selection.path,
                expectedCLIBuild: fixture.cliBuild
            ))
            final class PIDBox: @unchecked Sendable { var value: pid_t = 0 }
            let observed = PIDBox()
            GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }
            let payload = try XCTUnwrap(GrokCredentialTransportPayload(Array("bounded-fake".utf8)))
            XCTAssertThrowsError(try GrokCandidateProcessLauncher.spawn(
                lease: lease,
                arguments: [],
                environment: ["HOME": fixture.container.path, "PATH": "/usr/bin:/bin"],
                currentDirectory: fixture.container,
                credentialTransport: payload
            )) { error in
                XCTAssertFalse(error.localizedDescription.contains("bounded-fake"))
                guard case GrokCandidateProcessLauncher.LaunchError.credentialTransportFailed = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertGreaterThan(observed.value, 0)
            XCTAssertEqual(kill(observed.value, 0), -1)
            XCTAssertEqual(errno, ESRCH)
            GrokCandidateProcessLauncher.spawnedProcessObserverForTests = nil
        }
    }

    func testFakeCredentialTransportRejectsPayloadInArgumentsOrEnvironmentBeforeSpawn() throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        let text = "pre-spawn-fake-sentinel"
        let payload = try XCTUnwrap(GrokCredentialTransportPayload(Array(text.utf8)))
        final class PIDBox: @unchecked Sendable { var value: pid_t = 0 }
        let observed = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }

        XCTAssertThrowsError(try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: ["prefix-\(text)-suffix"],
            environment: ["HOME": fixture.container.path, "PATH": "/usr/bin:/bin"],
            currentDirectory: fixture.container,
            credentialTransport: payload
        )) { XCTAssertFalse($0.localizedDescription.contains(text)) }
        XCTAssertEqual(observed.value, 0)
        XCTAssertThrowsError(try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: [],
            environment: ["HOME": "prefix-\(text)-suffix", "PATH": "/usr/bin:/bin"],
            currentDirectory: fixture.container,
            credentialTransport: payload
        )) { XCTAssertFalse($0.localizedDescription.contains(text)) }
        XCTAssertEqual(observed.value, 0)
        XCTAssertThrowsError(try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: [],
            environment: ["XAI_API_KEY": text, "PATH": "/usr/bin:/bin"],
            currentDirectory: fixture.container,
            credentialTransport: payload
        )) { XCTAssertFalse($0.localizedDescription.contains(text)) }
        XCTAssertEqual(observed.value, 0)
    }

    func testFakeCredentialTransportAcceptsExactMaximumFrame() throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        var bytes = [UInt8](repeating: 0x5a, count: GrokCredentialTransportPayload.maximumByteCount)
        defer { _ = bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        let payload = try XCTUnwrap(GrokCredentialTransportPayload(bytes))
        let launched = try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: [],
            environment: ["HOME": fixture.container.path, "PATH": "/usr/bin:/bin"],
            currentDirectory: fixture.container,
            credentialTransport: payload
        )
        try launched.standardInput.close()
        let output = try launched.standardOutput.fileHandleForReading.readToEnd() ?? Data()
        waitForExit(launched.process)
        XCTAssertEqual(output, Data("transport=fd-v1,result=ok\n".utf8))
    }

    func testFakeCredentialTransportRejectsMalformedTruncatedTrailingAndDuplicateFrames() throws {
        for fault in [
            GrokCredentialTransportV1.OutboundFrameFaultForTests.badMagic,
            .oversizedClaim,
            .truncated,
            .trailingByte,
            .duplicatedFrame,
        ] {
            let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
            defer { try? FileManager.default.removeItem(at: fixture.container) }
            CandidateRuntimeTestFixture.installSignatureOverride()
            let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
                selectionPath: fixture.selection.path,
                expectedCLIBuild: fixture.cliBuild
            ))
            final class PIDBox: @unchecked Sendable { var value: pid_t = 0 }
            let observed = PIDBox()
            GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }
            GrokCredentialTransportV1.outboundFrameFaultForTests = fault
            let payload = try XCTUnwrap(GrokCredentialTransportPayload(Array("malformed-fake".utf8)))
            XCTAssertThrowsError(try GrokCandidateProcessLauncher.spawn(
                lease: lease,
                arguments: [],
                environment: ["HOME": fixture.container.path, "PATH": "/usr/bin:/bin"],
                currentDirectory: fixture.container,
                credentialTransport: payload
            )) { error in
                XCTAssertFalse(error.localizedDescription.contains("malformed-fake"))
                guard case GrokCandidateProcessLauncher.LaunchError.credentialTransportFailed = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertGreaterThan(observed.value, 0)
            XCTAssertEqual(kill(observed.value, 0), -1)
            XCTAssertEqual(errno, ESRCH)
            GrokCandidateProcessLauncher.spawnedProcessObserverForTests = nil
            GrokCredentialTransportV1.outboundFrameFaultForTests = .none
        }
    }

    func testFakeCredentialTransportKillsPreReturnSameGroupDescriptorHoldingDescendant() throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable(behavior: .forkBeforeClose)
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        let descendantReceipt = fixture.container.appendingPathComponent("descendant.pid")
        final class PIDBox: @unchecked Sendable { var value: pid_t = 0 }
        let observedRoot = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observedRoot.value = $0 }
        defer { GrokCandidateProcessLauncher.spawnedProcessObserverForTests = nil }
        let payload = try XCTUnwrap(GrokCredentialTransportPayload(Array("group-cleanup-fake".utf8)))
        XCTAssertThrowsError(try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: [descendantReceipt.path],
            environment: ["HOME": fixture.container.path, "PATH": "/usr/bin:/bin"],
            currentDirectory: fixture.container,
            credentialTransport: payload
        )) { error in
            guard case GrokCandidateProcessLauncher.LaunchError.credentialTransportFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let rootPID = observedRoot.value
        XCTAssertGreaterThan(rootPID, 0)
        let descendantText = try String(contentsOf: descendantReceipt, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let descendantPID = try XCTUnwrap(pid_t(descendantText))
        for _ in 0..<100 {
            errno = 0
            let rootGone = kill(rootPID, 0) == -1 && errno == ESRCH
            errno = 0
            let descendantGone = kill(descendantPID, 0) == -1 && errno == ESRCH
            errno = 0
            let groupGone = kill(-rootPID, 0) == -1 && errno == ESRCH
            if rootGone && descendantGone && groupGone { break }
            usleep(10_000)
        }
        errno = 0
        XCTAssertEqual(kill(rootPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        errno = 0
        XCTAssertEqual(kill(descendantPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        errno = 0
        XCTAssertEqual(kill(-rootPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testSuspendedChildExecutesPinnedInspectedBytesAfterOriginalPathSwap() throws {
        let fixture = try makeFixture(sourceExecutable: "/bin/echo")
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        var signatureObserved = false
        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = { _ in
            signatureObserved = true
            return GrokCandidateSignatureReceipt(
                teamIdentifier: GrokCandidateRuntimeAuthority.expectedTeamIdentifier,
                designatedRequirement: self.requirement
            )
        }
        let candidateLease = GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        )
        XCTAssertTrue(signatureObserved)
        let lease = try XCTUnwrap(candidateLease)

        let replacement = fixture.digestDirectory.appendingPathComponent("replacement")
        try thinARM64(source: "/usr/bin/touch", destination: replacement)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: replacement.path)
        let heldOriginal = fixture.digestDirectory.appendingPathComponent("held-original")
        try FileManager.default.moveItem(at: fixture.candidate, to: heldOriginal)
        try FileManager.default.moveItem(at: replacement, to: fixture.candidate)

        let forbiddenMarker = fixture.container.appendingPathComponent("replacement-must-not-run")
        let launched = try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: [forbiddenMarker.path],
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectory: fixture.container
        )
        try launched.standardInput.close()
        let output = try XCTUnwrap(try launched.standardOutput.fileHandleForReading.readToEnd())
        waitForExit(launched.process)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "\(forbiddenMarker.path)\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: forbiddenMarker.path))
    }

    func testCandidateLeaseIsSingleUseAndPathOverridesCannotSubstituteIt() throws {
        let fixture = try makeFixture(sourceExecutable: "/bin/echo")
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = { _ in
            GrokCandidateSignatureReceipt(
                teamIdentifier: GrokCandidateRuntimeAuthority.expectedTeamIdentifier,
                designatedRequirement: self.requirement
            )
        }
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        let campaignManifest = fixture.container.appendingPathComponent("hard-budget-manifest.json")
        let campaignLedger = fixture.container.appendingPathComponent("hard-budget-ledger.json")
        let campaignData = Data("{\"campaign\":\"fixture\"}".utf8)
        try campaignData.write(to: campaignManifest)
        try Data("{}".utf8).write(to: campaignLedger)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: campaignManifest.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: campaignLedger.path)
        let contract = try XCTUnwrap(HardBudgetLaunchContract(
            manifestPath: campaignManifest.path,
            ledgerPath: campaignLedger.path,
            allocationID: "packet-one",
            expectedManifestSHA256: sha256(campaignData),
            candidateExecutionLease: lease
        ))
        let armedEnvironment = GrokProcessLaunchEnvironment.resolved(
            base: ["GROK_CLI_PATH": "/usr/bin/false"],
            hardBudget: contract
        )
        XCTAssertEqual(armedEnvironment["GROK_HARD_TOKEN_BUDGET_ALLOCATION"], "packet-one")
        XCTAssertTrue(contract.filesRemainValid)
        let first = try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: ["FIRST"],
            environment: [
                "PATH": fixture.digestDirectory.path,
                "GROK_CLI_PATH": "/usr/bin/false",
            ],
            currentDirectory: fixture.container
        )
        try first.standardInput.close()
        let output = try XCTUnwrap(try first.standardOutput.fileHandleForReading.readToEnd())
        waitForExit(first.process)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "FIRST\n")
        XCTAssertThrowsError(try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: ["SECOND"],
            environment: [:],
            currentDirectory: fixture.container
        )) { error in
            guard case GrokCandidateProcessLauncher.LaunchError.leaseAlreadyConsumed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLocalTeamSignedFixturePassesWithoutSignatureOverride() throws {
        let fixture = try CandidateRuntimeTestFixture.makeTeamSigned()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = nil
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        XCTAssertEqual(lease.identity.signature.teamIdentifier,
                       GrokCandidateRuntimeAuthority.expectedTeamIdentifier)
        XCTAssertEqual(lease.identity.signature.designatedRequirement,
                       fixture.observedDesignatedRequirement)
        XCTAssertFalse(lease.identity.signature.codeDirectoryHash.isEmpty)
    }

    func testAdHocFixtureIsNotArmableWithoutTestSignatureOverride() throws {
        let fixture = try CandidateRuntimeTestFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = nil
        XCTAssertNil(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
    }

    func testForcedCandidateTerminationReapsTermIgnoringDirectChild() throws {
        let fixture = try CandidateRuntimeTestFixture.makeTermIgnoringExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        let launched = try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: [],
            environment: ["PATH": "/usr/bin:/bin"],
            currentDirectory: fixture.container
        )
        let ready = try launched.standardOutput.fileHandleForReading.read(upToCount: 1)
        XCTAssertEqual(ready, Data("R".utf8))
        launched.process.terminate()
        usleep(100_000)
        XCTAssertTrue(launched.process.isRunning)
        launched.process.forceKillAndReap()
        XCTAssertFalse(launched.process.isRunning)
        var status: Int32 = 0
        XCTAssertEqual(waitpid(launched.process.processIdentifier, &status, WNOHANG), -1)
        XCTAssertEqual(errno, ECHILD)
    }

    func testCandidateSelectionRejectsSignatureBuildAndBinaryDrift() throws {
        let fixture = try makeFixture(sourceExecutable: "/bin/echo")
        defer { try? FileManager.default.removeItem(at: fixture.container) }

        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = { _ in
            GrokCandidateSignatureReceipt(
                teamIdentifier: "WRONGTEAM",
                designatedRequirement: self.requirement
            )
        }
        XCTAssertNil(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))

        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = { _ in
            GrokCandidateSignatureReceipt(
                teamIdentifier: GrokCandidateRuntimeAuthority.expectedTeamIdentifier,
                designatedRequirement: self.requirement
            )
        }
        XCTAssertNil(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: "1.0.5 (fffffff)"
        ))

        let replacement = fixture.digestDirectory.appendingPathComponent("replacement")
        try thinARM64(source: "/usr/bin/false", destination: replacement)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: replacement.path)
        try FileManager.default.removeItem(at: fixture.candidate)
        try FileManager.default.moveItem(at: replacement, to: fixture.candidate)
        XCTAssertNil(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
    }

    func testCandidateSelectionRejectsPartialUnknownAndUnsafeAuthority() throws {
        let fixture = try makeFixture(sourceExecutable: "/bin/echo")
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = { _ in
            GrokCandidateSignatureReceipt(
                teamIdentifier: GrokCandidateRuntimeAuthority.expectedTeamIdentifier,
                designatedRequirement: self.requirement
            )
        }

        var selection = try jsonObject(fixture.selection)
        selection["unexpected"] = true
        try writeJSON(selection, to: fixture.selection, permissions: 0o600)
        XCTAssertNil(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))

        selection.removeValue(forKey: "unexpected")
        try writeJSON(selection, to: fixture.selection, permissions: 0o644)
        XCTAssertNil(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
    }

    func testAcceptanceGuardRequiresOneCompleteRuntimeSelectionAndBindsItsLease() throws {
        let fixture = try CandidateRuntimeTestFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()

        let prompt = "Return EXACT-RUNTIME"
        let promptSHA = CandidateRuntimeTestFixture.sha256(Data(prompt.utf8))
        let cliManifest = fixture.container.appendingPathComponent("hard-budget-manifest.json")
        let cliManifestData = Data("{\"campaignId\":\"runtime-selection\"}".utf8)
        try cliManifestData.write(to: cliManifest)
        let ledger = fixture.container.appendingPathComponent("hard-budget-ledger.json")
        try Data("{}".utf8).write(to: ledger)
        for path in [cliManifest.path, ledger.path] {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
        let authorization = fixture.container.appendingPathComponent("authorization.json")
        let manifest = AcceptanceBudgetManifest(
            schemaVersion: 2,
            runID: "runtime-selection",
            campaignTokenCeiling: 4_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: CandidateRuntimeTestFixture.sha256(cliManifestData),
            expectedCLIBuild: fixture.cliBuild,
            packets: [AcceptanceTurnBudget(
                packetID: "packet",
                allocationID: "allocation",
                marker: "EXACT-RUNTIME",
                promptHash: promptSHA,
                tokenAllocation: 100,
                maxModelCalls: 1,
                route: AcceptanceHardBudgetRoute(
                    model: "grok-4.6",
                    endpointSHA256: String(repeating: "a", count: 64),
                    apiBackend: "responses",
                    requestBoundTokens: 100,
                    maxPayloadBytes: 80,
                    maxOutputTokens: 20,
                    boundProvenanceSHA256: String(repeating: "b", count: 64)
                )
            )]
        )
        try JSONEncoder().encode(manifest).write(to: authorization)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authorization.path)

        let baseArguments = [
            "app",
            "\(AcceptanceBudgetGuard.argumentPrefix)\(authorization.path)",
            "\(AcceptanceBudgetGuard.cliManifestArgumentPrefix)\(cliManifest.path)",
            "\(AcceptanceBudgetGuard.ledgerArgumentPrefix)\(ledger.path)",
        ]
        let selectionArgument = "\(GrokCandidateRuntimeAuthority.selectionArgumentPrefix)\(fixture.selection.path)"
        let completeArguments = baseArguments + [selectionArgument]
        XCTAssertEqual(AcceptanceBudgetGuard.resolve(prompt: prompt, arguments: baseArguments), .blocked)
        XCTAssertEqual(
            AcceptanceBudgetGuard.resolve(
                prompt: prompt,
                arguments: ["app", "\(GrokCandidateRuntimeAuthority.selectionArgumentPrefix)\(fixture.selection.path)"]
            ),
            .blocked
        )
        XCTAssertTrue(AcceptanceBudgetGuard.isConfigured(arguments: [
            "app", "\(GrokCandidateRuntimeAuthority.selectionArgumentPrefix)"
        ]))
        XCTAssertNil(GrokCLIRuntimeResolver.locateOfficial(
            testOverride: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["app", selectionArgument]
        ))
        XCTAssertEqual(
            GrokCLIRuntimeResolver.locateOfficial(
                testOverride: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["app"]
            )?.path,
            "/bin/echo"
        )
        for authorityPath in [authorization, cliManifest, ledger] {
            let hardlink = fixture.container.appendingPathComponent("hardlink-\(UUID().uuidString)")
            try FileManager.default.linkItem(at: authorityPath, to: hardlink)
            XCTAssertEqual(
                AcceptanceBudgetGuard.resolve(prompt: prompt, arguments: completeArguments),
                .blocked
            )
            try FileManager.default.removeItem(at: hardlink)
        }
        let resolution = AcceptanceBudgetGuard.resolve(
            prompt: prompt,
            arguments: completeArguments
        )
        guard case .budget(let authorized) = resolution else {
            return XCTFail("Complete exact runtime authority was not accepted: \(resolution)")
        }
        XCTAssertEqual(authorized.expectedCLIBuild, fixture.cliBuild)
        XCTAssertEqual(authorized.candidateExecutionLease?.identity.binarySHA256,
                       CandidateRuntimeTestFixture.sha256(try Data(contentsOf: fixture.candidate)))
        for index in completeArguments.indices.dropFirst() {
            var missing = completeArguments
            missing.remove(at: index)
            XCTAssertEqual(AcceptanceBudgetGuard.resolve(prompt: prompt, arguments: missing), .blocked)
            var duplicate = completeArguments
            duplicate.append(completeArguments[index])
            XCTAssertEqual(AcceptanceBudgetGuard.resolve(prompt: prompt, arguments: duplicate), .blocked)
        }
    }

    private struct Fixture {
        let container: URL
        let digestDirectory: URL
        let candidate: URL
        let provenance: URL
        let selection: URL
        let cliBuild: String
    }

    private func makeFixture(sourceExecutable: String) throws -> Fixture {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-candidate-fixture-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: container.path)

        let staged = container.appendingPathComponent("staged")
        try thinARM64(source: sourceExecutable, destination: staged)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)
        let binaryData = try Data(contentsOf: staged)
        let binarySHA = sha256(binaryData)
        let digestDirectory = container.appendingPathComponent(binarySHA, isDirectory: true)
        try FileManager.default.createDirectory(at: digestDirectory, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: digestDirectory.path)
        let candidate = digestDirectory.appendingPathComponent("grok")
        try FileManager.default.moveItem(at: staged, to: candidate)
        let cliBuild = "1.0.5 (\(sourceSHA.prefix(7)))"
        let provenance = digestDirectory.appendingPathComponent("candidate-provenance.json")
        let zeros = String(repeating: "0", count: 64)
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "source": [
                "officialBaseSHA": String(repeating: "1", count: 40),
                "upstreamReplayBaseSHA": String(repeating: "2", count: 40),
                "forkSourceSHA": sourceSHA,
                "sourceRev": String(repeating: "3", count: 40),
                "cargoLockSHA256": zeros,
            ],
            "toolchain": [
                "rustVersion": "rustc 1.94.0 (fixture)",
                "cargoVersion": "cargo 1.94.0 (fixture)",
                "dotslashVersion": "DotSlash 0.5.7",
                "rustcSHA256": zeros,
                "cargoSHA256": zeros,
                "dotslashSHA256": zeros,
                "targetTriple": "aarch64-apple-darwin",
                "architecture": "arm64",
            ],
            "build": [
                "preBuildCommand": [
                    "cargo", "clean", "--target-dir", "<candidate-target>", "--profile", "release-dist",
                    "-p", "xai-grok-pager-bin",
                ],
                "command": [
                    "cargo", "build", "--locked", "--profile", "release-dist", "-p",
                    "xai-grok-pager-bin", "--features", "release-dist",
                ],
                "environment": [
                    "clearEnvironment": true,
                    "home": "<account-home>",
                    "path": ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "<dotslash-directory>"],
                    "cargoHome": "<account-home>/.cargo",
                    "rustupHome": "<account-home>/.rustup",
                    "rustc": "<pinned-rustc>",
                    "cargoTargetDir": "<candidate-target>",
                    "cargoIncremental": false,
                    "locale": "C",
                    "temporaryDirectory": "/private/tmp",
                ],
                "profile": "release-dist",
                "package": "xai-grok-pager-bin",
                "features": ["release-dist"],
            ],
            "binary": [
                "artifactName": "xai-grok-pager",
                "sha256": binarySHA,
                "sizeBytes": binaryData.count,
                "architecture": "arm64",
                "expectedVersionWithCommit": cliBuild,
                "expectedACPCLIBuild": cliBuild,
                "observedVersionWithCommit": cliBuild,
            ],
            "signing": [
                "state": "signed",
                "strictVerification": true,
                "teamIdentifier": GrokCandidateRuntimeAuthority.expectedTeamIdentifier,
                "designatedRequirement": requirement,
            ],
        ]
        try writeJSON(manifest, to: provenance, permissions: 0o600)
        let selection = container.appendingPathComponent("runtime-selection.json")
        try writeJSON([
            "schemaVersion": 1,
            "runtimeRoot": container.path,
            "candidatePath": candidate.path,
            "provenancePath": provenance.path,
            "provenanceSHA256": sha256(try Data(contentsOf: provenance)),
        ], to: selection, permissions: 0o600)
        return Fixture(
            container: container,
            digestDirectory: digestDirectory,
            candidate: candidate,
            provenance: provenance,
            selection: selection,
            cliBuild: cliBuild
        )
    }

    private func thinARM64(source: String, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        process.arguments = [source, "-thin", "arm64e", "-output", destination.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", destination.path]
        try signer.run()
        signer.waitUntilExit()
        XCTAssertEqual(signer.terminationStatus, 0)
    }

    private func waitForExit(_ process: GrokManagedProcess) {
        for _ in 0..<200 where process.isRunning {
            usleep(10_000)
        }
        XCTAssertFalse(process.isRunning)
    }

    private func writeJSON(_ value: [String: Any], to url: URL, permissions: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private func jsonObject(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
