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
        super.tearDown()
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
