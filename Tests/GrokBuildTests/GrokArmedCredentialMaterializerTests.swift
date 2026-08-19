import CryptoKit
import Darwin
import Foundation
import Security
import XCTest
@testable import GrokBuild

final class GrokArmedCredentialMaterializerTests: XCTestCase {
    private let account = "openrouter"

    override func tearDown() {
        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = nil
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = nil
        GrokProcess.cliOverrideForTests = nil
        GrokProcess.armedKeychainClientForTests = nil
        GrokCredentialTransportV1.handshakeInterphaseDelayMillisecondsForTests = 0
        super.tearDown()
    }

    func testUsesExactGenericPasswordServiceAccountAndOneResult() throws {
        final class QueryBox {
            var query: [String: Any]?
        }
        let box = QueryBox()
        let materializer = GrokArmedCredentialMaterializer(keychain: client { query, item in
            box.query = query as NSDictionary as? [String: Any]
            item?.pointee = [Data([0x00, 0xff, 0x7f])] as NSArray
            return errSecSuccess
        })

        let transfer = try materializer.materialize(authorization: authorization())
        XCTAssertEqual(transfer.byteCount, 3)
        let query = try XCTUnwrap(box.query)
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, GrokArmedCredentialMaterializer.keychainService)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, account)
        XCTAssertEqual(
            query[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitAll as String)
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(authorization().keychainAccount, account)
        XCTAssertEqual(authorization().authHeaderNames, ["authorization"])
    }

    func testAuthorizationDerivesAccountAndHeadersFromScheme() throws {
        XCTAssertNil(GrokArmedCredentialAuthorizationV3(
            managedProviderID: account,
            authScheme: "oauth",
            expectedProvenanceSHA256: String(repeating: "a", count: 64)
        ))
        XCTAssertNil(GrokArmedCredentialAuthorizationV3(
            managedProviderID: account,
            authScheme: "bearer",
            expectedProvenanceSHA256: "not-a-digest"
        ))
        let both = try XCTUnwrap(GrokArmedCredentialAuthorizationV3(
            managedProviderID: account,
            authScheme: "bearer_and_x_api_key",
            expectedProvenanceSHA256: String(repeating: "a", count: 64)
        ))
        XCTAssertEqual(both.keychainAccount, account)
        XCTAssertEqual(both.authHeaderNames, ["authorization", "x-api-key"])
        XCTAssertEqual(
            try XCTUnwrap(GrokArmedCredentialAuthorizationV3(
                managedProviderID: account,
                authScheme: "x_api_key",
                expectedProvenanceSHA256: String(repeating: "a", count: 64)
            )).authHeaderNames,
            ["x-api-key"]
        )
    }

    func testRejectsMissingErrorMultipleEmptyInvalidAndOversizeResponses() throws {
        let failures: [(OSStatus, AnyObject?, GrokArmedCredentialMaterializer.MaterializationError)] = [
            (errSecItemNotFound, nil, .itemNotFound),
            (errSecAuthFailed, nil, .keychainReadFailed),
            (errSecSuccess, [Data([1]), Data([2])] as NSArray, .multipleCredentials),
            (errSecSuccess, [Data()] as NSArray, .invalidCredential),
            (errSecSuccess, ["not-data"] as NSArray, .invalidCredential),
            (
                errSecSuccess,
                [Data(repeating: 1, count: GrokArmedCredentialMaterializer.maximumByteCount + 1)] as NSArray,
                .credentialTooLarge
            ),
        ]
        for (status, item, expected) in failures {
            let materializer = GrokArmedCredentialMaterializer(keychain: client { _, result in
                result?.pointee = item as CFTypeRef?
                return status
            })
            XCTAssertThrowsError(try materializer.materialize(authorization: authorization())) { error in
                XCTAssertEqual(error as? GrokArmedCredentialMaterializer.MaterializationError, expected)
            }
        }
    }

    func testTransferConsumesOnlyOnceWithoutReturningCredentialBytes() throws {
        let original = [UInt8]([0xff, 0xfe, 0x80, 0x00, 0x7f])
        let materializer = GrokArmedCredentialMaterializer(keychain: client { _, item in
            item?.pointee = [Data(original)] as NSArray
            return errSecSuccess
        })
        let transfer = try materializer.materialize(authorization: authorization())
        var channel = try GrokCredentialTransportV1.prepare(transfer: transfer)
        channel.closeParent()
        channel.closeChild()
        channel.bestEffortWipe()
        XCTAssertEqual(transfer.byteCount, 0)
        XCTAssertThrowsError(try GrokCredentialTransportV1.prepare(transfer: transfer)) { error in
            XCTAssertEqual(error as? GrokArmedCredentialTransfer.TransferError, .alreadyConsumed)
        }
    }

    func testMaterializationFailureCannotCreateCandidateProcess() throws {
        final class PIDBox { var value: pid_t = 0 }
        let observed = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }
        let materializer = GrokArmedCredentialMaterializer(keychain: client { _, _ in errSecItemNotFound })

        XCTAssertThrowsError(try materializer.materialize(authorization: authorization())) { error in
            XCTAssertEqual(error as? GrokArmedCredentialMaterializer.MaterializationError, .itemNotFound)
        }
        XCTAssertEqual(observed.value, 0)
    }

    @MainActor
    func testProductionStartRefusesArmedV3WithoutInjectedKeychainAndDoesNotSpawn() async throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let contract = try makeArmedContract(fixture: fixture, allocationID: "packet-locked")

        final class PIDBox { var value: pid_t = 0 }
        let observed = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }
        GrokProcess.cliOverrideForTests = URL(fileURLWithPath: "/usr/bin/true")
        GrokProcess.armedKeychainClientForTests = nil

        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "locked-v3", path: fixture.container),
            options: GrokLaunchOptions(hardBudgetLaunchContract: contract)
        )
        XCTAssertEqual(observed.value, 0)
        XCTAssertNil(process.activeProcessGeneration)
        XCTAssertEqual(
            process.state,
            .failed("Armed v3 tests must inject a Keychain client. Live Keychain was not read. No Grok process was launched.")
        )
        XCTAssertEqual(process.launchReceipt?.outcome, .failed)
    }

    @MainActor
    func testProductionStartMaterializationFailureDoesNotSpawnOfficialOrCandidate() async throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let contract = try makeArmedContract(fixture: fixture, allocationID: "packet-missing")
        GrokProcess.armedKeychainClientForTests = client { _, _ in errSecItemNotFound }
        GrokProcess.cliOverrideForTests = URL(fileURLWithPath: "/usr/bin/true")

        final class PIDBox { var value: pid_t = 0 }
        let observed = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }

        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "missing-v3", path: fixture.container),
            options: GrokLaunchOptions(hardBudgetLaunchContract: contract)
        )
        XCTAssertEqual(observed.value, 0)
        XCTAssertNil(process.activeProcessGeneration)
        XCTAssertEqual(
            process.state,
            .failed("Armed v3 credential materialization failed. No Grok process was launched.")
        )
    }

    @MainActor
    func testProductionStartRefusesModelDriftAfterDispatchLatch() async throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let contract = try makeArmedContract(
            fixture: fixture,
            allocationID: "packet-drift",
            latchDispatch: true
        )
        GrokProcess.armedKeychainClientForTests = client { _, item in
            item?.pointee = [Data([0x01])] as NSArray
            return errSecSuccess
        }
        final class PIDBox { var value: pid_t = 0 }
        let observed = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "drift-v3", path: fixture.container),
            options: GrokLaunchOptions(
                model: "grok-4.6",
                hardBudgetLaunchContract: contract
            )
        )
        XCTAssertEqual(observed.value, 0)
        XCTAssertNil(process.activeProcessGeneration)
        XCTAssertEqual(
            process.state,
            .failed("Acceptance route changed after authorization. No Grok process was launched.")
        )
    }

    @MainActor
    func testProductionStartSpawnsCandidateWithInjectedKeychainNotOfficialCLI() async throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let contract = try makeArmedContract(fixture: fixture, allocationID: "packet-spawn")
        let sentinel = Array("S4B3-START-\(UUID().uuidString)-END".utf8)
        GrokProcess.armedKeychainClientForTests = client { _, item in
            item?.pointee = [Data(sentinel)] as NSArray
            return errSecSuccess
        }
        GrokProcess.cliOverrideForTests = URL(fileURLWithPath: "/usr/bin/true")

        final class PIDBox { var value: pid_t = 0 }
        let observed = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }

        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "spawn-v3", path: fixture.container),
            options: GrokLaunchOptions(hardBudgetLaunchContract: contract)
        )
        XCTAssertNotEqual(observed.value, 0)
        XCTAssertEqual(
            process.launchReceipt?.candidateBinarySHA256,
            contract.candidateExecutionLease.identity.binarySHA256
        )
        XCTAssertNil(Data(String(describing: process.launchReceipt as Any).utf8).range(of: Data(sentinel)))
        if case .failed(let message) = process.state {
            XCTAssertFalse(message.contains("Keychain materialization remains locked"))
            XCTAssertFalse(message.contains(String(decoding: sentinel, as: UTF8.self)))
        } else {
            XCTFail("expected ACP startup failure after the credential receiver exited")
        }
        await process.stop()
    }

    @MainActor
    func testProductionStartRefusesArmedV3MCPDetourWithoutSpawning() async throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let contract = try makeArmedContract(fixture: fixture, allocationID: "packet-mcp")
        GrokProcess.armedKeychainClientForTests = client { _, item in
            item?.pointee = [Data([0x01])] as NSArray
            return errSecSuccess
        }

        final class PIDBox { var value: pid_t = 0 }
        let observed = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }

        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "mcp-v3", path: fixture.container),
            options: GrokLaunchOptions(
                mcpServers: [
                    MCPServerConfig(name: "external", command: "/usr/bin/true")
                ],
                hardBudgetLaunchContract: contract
            )
        )
        XCTAssertEqual(observed.value, 0)
        XCTAssertEqual(
            process.state,
            .failed("Armed credential launch refuses Browser, Computer Use, MCP, and non-managed-provider detours.")
        )
    }

    func testV3PreflightRefusesEveryOrdinaryToolOrHelperDetour() {
        let authorization = authorization()
        XCTAssertNil(GrokArmedCredentialLaunchPreflight.refusalMessage(
            authorization: authorization,
            browserEnabled: false,
            computerUseEnabled: false,
            requestedMCPServerNames: [],
            authBoundary: .officialHelper
        ))
        for refusal in [
            GrokArmedCredentialLaunchPreflight.refusalMessage(
                authorization: authorization,
                browserEnabled: true,
                computerUseEnabled: false,
                requestedMCPServerNames: [],
                authBoundary: .officialHelper
            ),
            GrokArmedCredentialLaunchPreflight.refusalMessage(
                authorization: authorization,
                browserEnabled: false,
                computerUseEnabled: true,
                requestedMCPServerNames: [],
                authBoundary: .officialHelper
            ),
            GrokArmedCredentialLaunchPreflight.refusalMessage(
                authorization: authorization,
                browserEnabled: false,
                computerUseEnabled: false,
                requestedMCPServerNames: ["external"],
                authBoundary: .officialHelper
            ),
            GrokArmedCredentialLaunchPreflight.refusalMessage(
                authorization: authorization,
                browserEnabled: false,
                computerUseEnabled: false,
                requestedMCPServerNames: [],
                authBoundary: .nativeSession
            ),
        ] {
            XCTAssertNotNil(refusal)
        }
    }

    func testV3TransferUsesCandidateDescriptorAndLeaksSentinelNowhere() throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        let sentinel = Array("S4B3-MATERIALIZER-\(UUID().uuidString)-END".utf8)
        let materializer = GrokArmedCredentialMaterializer(keychain: client { _, item in
            item?.pointee = [Data(sentinel)] as NSArray
            return errSecSuccess
        })
        let transfer = try materializer.materialize(authorization: authorization())
        let arguments = ["agent", "stdio"]
        let environment = ["HOME": fixture.container.path, "PATH": "/usr/bin:/bin"]
        XCTAssertFalse(GrokCredentialTransportV1.argumentsOrEnvironmentContainTransfer(
            transfer,
            arguments: arguments,
            environment: environment
        ))

        let launched = try GrokCandidateProcessLauncher.spawn(
            lease: lease,
            arguments: arguments,
            environment: environment,
            currentDirectory: fixture.container,
            credentialTransferV3: transfer
        )
        try launched.standardInput.close()
        let output = try launched.standardOutput.fileHandleForReading.readToEnd() ?? Data()
        let error = try launched.standardError.fileHandleForReading.readToEnd() ?? Data()
        waitForProcessExit(launched.process)
        XCTAssertEqual(output, Data("transport=fd-v1,result=ok\n".utf8))
        XCTAssertTrue(error.isEmpty)
        XCTAssertNil(output.range(of: Data(sentinel)))
        XCTAssertNil(error.range(of: Data(sentinel)))

        let receipt = GrokLaunchReceipt(options: GrokLaunchOptions())
        XCTAssertNil(Data(String(describing: receipt).utf8).range(of: Data(sentinel)))
        for relative in try FileManager.default.subpathsOfDirectory(atPath: fixture.container.path) {
            let url = fixture.container.appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: url) else { continue }
            XCTAssertNil(data.range(of: Data(sentinel)), "sentinel persisted in \(relative)")
        }
    }

    func testV3TransferRejectsContaminatedArgumentsOrEnvironmentWithoutSpawningOrLeakingError() throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        let sentinelText = "S4B3-CONTAMINATED-\(UUID().uuidString)-END"
        let sentinel = Array(sentinelText.utf8)
        let materializer = GrokArmedCredentialMaterializer(keychain: client { _, item in
            item?.pointee = [Data(sentinel)] as NSArray
            return errSecSuccess
        })
        final class PIDBox { var value: pid_t = 0 }
        let observed = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }

        let contaminatedInputs: [(arguments: [String], environment: [String: String])] = [
            (["agent", "--token=\(sentinelText)"], ["HOME": fixture.container.path, "PATH": "/usr/bin:/bin"]),
            (["agent", "stdio"], ["HOME": fixture.container.path, "PATH": "/usr/bin:/bin", "TOKEN": sentinelText]),
        ]
        for input in contaminatedInputs {
            let transfer = try materializer.materialize(authorization: authorization())
            XCTAssertThrowsError(try GrokCandidateProcessLauncher.spawn(
                lease: lease,
                arguments: input.arguments,
                environment: input.environment,
                currentDirectory: fixture.container,
                credentialTransferV3: transfer
            )) { error in
                guard case .credentialTransportFailed? = error as? GrokCandidateProcessLauncher.LaunchError else {
                    return XCTFail("expected generic credential transport refusal")
                }
                XCTAssertFalse(error.localizedDescription.contains(sentinelText))
            }
            XCTAssertEqual(transfer.byteCount, 0)
        }
        XCTAssertEqual(observed.value, 0)
    }

    private func authorization() -> GrokArmedCredentialAuthorizationV3 {
        try! XCTUnwrap(GrokArmedCredentialAuthorizationV3(
            managedProviderID: account,
            authScheme: "bearer",
            expectedProvenanceSHA256: String(repeating: "a", count: 64)
        ))
    }

    private func makeArmedContract(
        fixture: CandidateRuntimeTestFixture,
        allocationID: String,
        latchDispatch: Bool = false
    ) throws -> HardBudgetLaunchContract {
        CandidateRuntimeTestFixture.installSignatureOverride()
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        let manifest = fixture.container.appendingPathComponent("manifest.json")
        let ledger = fixture.container.appendingPathComponent("ledger.json")
        let manifestData = Data("{\"campaign\":\"\(allocationID)\"}".utf8)
        try manifestData.write(to: manifest)
        try Data("{}".utf8).write(to: ledger)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledger.path)
        let manifestSHA = SHA256.hash(data: manifestData)
            .map { String(format: "%02x", $0) }
            .joined()
        let expectation: ArmedV3DispatchExpectation?
        if latchDispatch {
            let modelID = "deepseek-deepseek-v4-flash-0731"
            let providerFacing = "deepseek/deepseek-v4-flash-0731"
            let provenanceSHA = String(repeating: "a", count: 64)
            let route = AcceptanceHardBudgetRoute(
                model: providerFacing,
                endpointSHA256: provenanceSHA,
                apiBackend: "chat_completions",
                requestBoundTokens: 100,
                maxPayloadBytes: 80,
                maxOutputTokens: 20,
                boundProvenanceSHA256: provenanceSHA,
                managedProviderID: account,
                authScheme: "bearer"
            )
            let packet = AcceptanceTurnBudget(
                packetID: allocationID,
                allocationID: allocationID,
                marker: "EXACT-V3",
                promptHash: String(repeating: "1", count: 64),
                tokenAllocation: 100,
                maxModelCalls: 1,
                route: route
            )
            let authorization = AcceptanceBudgetAuthorization(
                runID: "schema-3",
                campaignTokenCeiling: 20_000_000,
                emergencyReserveTokens: 1_000_000,
                hardBudgetManifestSHA256: manifestSHA,
                expectedCLIBuild: fixture.cliBuild,
                budget: packet,
                authorizationManifestPath: "/tmp/authorization.json",
                hardBudgetCLIManifestPath: manifest.path,
                hardBudgetLedgerPath: ledger.path,
                candidateExecutionLease: lease,
                credentialAuthorizationV3: route.credentialAuthorizationV3
            )
            expectation = try XCTUnwrap(ArmedV3DispatchExpectation.tryMake(
                authorization: authorization,
                selectedModelID: modelID,
                customModel: CustomModel(
                    id: modelID,
                    model: providerFacing,
                    baseURL: "https://openrouter.ai/api/v1",
                    apiBackend: .chatCompletions,
                    providerID: account
                ),
                provider: Provider(
                    id: account,
                    name: "OpenRouter",
                    baseURL: "https://openrouter.ai/api/v1",
                    authScheme: .bearer
                ),
                candidate: lease.identity
            ))
        } else {
            expectation = nil
        }
        return try XCTUnwrap(HardBudgetLaunchContract(
            manifestPath: manifest.path,
            ledgerPath: ledger.path,
            allocationID: allocationID,
            expectedManifestSHA256: manifestSHA,
            candidateExecutionLease: lease,
            credentialAuthorizationV3: expectation?.credentialAuthorizationV3 ?? authorization(),
            dispatchExpectation: expectation
        ))
    }

    private func client(
        _ body: @escaping GrokArmedCredentialKeychainClient.CopyMatching
    ) -> GrokArmedCredentialKeychainClient {
        GrokArmedCredentialKeychainClient(copyMatching: body)
    }

    private func waitForProcessExit(_ process: GrokManagedProcess) {
        for _ in 0..<200 where process.isRunning {
            usleep(10_000)
        }
        XCTAssertFalse(process.isRunning)
    }
}
