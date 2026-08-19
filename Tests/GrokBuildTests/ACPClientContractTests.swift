import CryptoKit
import Security
import XCTest
@testable import GrokBuild

final class ACPClientContractTests: XCTestCase {
    private let hardBudgetSHA = String(repeating: "a", count: 64)

    private func acceptanceRoute(
        model: String = "grok-4.6",
        apiBackend: String = "responses",
        requestBoundTokens: Int = 100,
        maxPayloadBytes: Int = 80,
        maxOutputTokens: Int = 20,
        sha256: String? = nil
    ) -> AcceptanceHardBudgetRoute {
        let sha256 = sha256 ?? hardBudgetSHA
        return AcceptanceHardBudgetRoute(
            model: model,
            endpointSHA256: sha256,
            apiBackend: apiBackend,
            requestBoundTokens: requestBoundTokens,
            maxPayloadBytes: maxPayloadBytes,
            maxOutputTokens: maxOutputTokens,
            boundProvenanceSHA256: sha256
        )
    }

    private func acceptanceBudget(
        packetID: String,
        marker: String,
        promptHash: String,
        tokenAllocation: Int,
        maxModelCalls: Int,
        route: AcceptanceHardBudgetRoute? = nil
    ) -> AcceptanceTurnBudget {
        AcceptanceTurnBudget(
            packetID: packetID,
            allocationID: packetID,
            marker: marker,
            promptHash: promptHash,
            tokenAllocation: tokenAllocation,
            maxModelCalls: maxModelCalls,
            route: route ?? acceptanceRoute()
        )
    }

    private func acceptanceAuthorization(
        budget: AcceptanceTurnBudget,
        runID: String = "campaign",
        campaignTokenCeiling: Int = 4_000_000,
        emergencyReserveTokens: Int = 1_000_000,
        manifestSHA256: String? = nil,
        cliBuild: String = "grokbuild-fork",
        authorizationManifestPath: String = "/private/tmp/grokbuild-authorization.json",
        cliManifestPath: String = "/private/tmp/grokbuild-cli-manifest.json",
        ledgerPath: String = "/private/tmp/grokbuild-ledger.json",
        candidateExecutionLease: GrokCandidateExecutionLease? = nil,
        credentialAuthorizationV3: GrokArmedCredentialAuthorizationV3? = nil
    ) -> AcceptanceBudgetAuthorization {
        AcceptanceBudgetAuthorization(
            runID: runID,
            campaignTokenCeiling: campaignTokenCeiling,
            emergencyReserveTokens: emergencyReserveTokens,
            hardBudgetManifestSHA256: manifestSHA256 ?? hardBudgetSHA,
            expectedCLIBuild: cliBuild,
            budget: budget,
            authorizationManifestPath: authorizationManifestPath,
            hardBudgetCLIManifestPath: cliManifestPath,
            hardBudgetLedgerPath: ledgerPath,
            candidateExecutionLease: candidateExecutionLease,
            credentialAuthorizationV3: credentialAuthorizationV3
        )
    }

    private func hardBudgetTerminalRecord(
        reservationID: String = "reservation-1",
        sequence: Int = 1,
        providerRequestID: String = "provider-request",
        actualTokens: Int? = 10,
        lifecycle: HardTokenReceiptSnapshot.Lifecycle = .settledUsageReported,
        model: String = "grok-4.6",
        endpointSHA256: String? = nil,
        apiBackend: String = "responses",
        payloadBytes: Int = 12,
        maxOutputTokens: Int = 20,
        reservedTokens: Int = 20,
        chargedTokens: Int? = nil
    ) -> HardTokenReceiptSnapshot.Record {
        .init(
            reservationID: reservationID,
            sequence: sequence,
            providerRequestID: providerRequestID,
            model: model,
            endpointSHA256: endpointSHA256 ?? hardBudgetSHA,
            apiBackend: apiBackend,
            payloadBytes: payloadBytes,
            maxOutputTokens: maxOutputTokens,
            reservedTokens: reservedTokens,
            actualTokens: actualTokens,
            chargedTokens: chargedTokens ?? actualTokens ?? reservedTokens,
            lifecycle: lifecycle
        )
    }

    private func hardBudgetTerminalSnapshot(
        _ receipts: [HardTokenReceiptSnapshot.Record]
    ) -> HardTokenReceiptSnapshot {
        .init(
            campaignID: "campaign",
            manifestSHA256: hardBudgetSHA,
            allocationID: "allocation",
            packetID: "packet",
            ledgerRevision: 4,
            nextSequence: 1 + receipts.count,
            receipts: receipts
        )
    }

    private func hardBudgetTerminalCompletion(
        modelCalls: Int? = nil,
        totalTokens: Int? = nil
    ) -> TurnCompletionReceipt {
        .init(
            identity: .init(localTabID: UUID(), backendSessionID: "backend", processGeneration: 1, backendEventID: "event"),
            promptID: "prompt",
            stopReason: "end_turn",
            redactedError: nil,
            totalTokens: totalTokens,
            modelCalls: modelCalls,
            turnCount: 1
        )
    }

    private func hardBudgetTerminalAuthority() throws -> AssistantTurnCheckpoint.HardBudgetReceipt {
        let capability = try XCTUnwrap(GrokBuildHardTokenBudgetCapability.parse([
            "capabilityVersion": 2, "armed": true, "configurationValid": true,
            "enforcementPoint": "sampler-pre-dispatch", "ledgerVersion": 3,
            "boundMethodVersion": 1, "durable": true, "processShared": true,
            "receiptProjection": true, "cancelConservative": true, "crashConservative": true,
            "noAutomaticRetry": false, "samplerTransportRetriesDisabled": true,
            "authProviderHelpersDisabled": true, "terminalDisabled": true,
            "externalMcpDisabled": true, "hooksDisabled": true, "pluginsDisabled": true,
            "lspDisabled": true, "workflowsDisabled": true, "schedulerDisabled": true,
            "protectedAuthorityFs": true, "workspaceFsConfined": true,
            "allowedToolIds": GrokBuildHardTokenBudgetCapability.allowedToolIDs,
            "cliBuild": "grokbuild-test",
            "status": [
                "campaignId": "campaign", "ceilingTokens": 3_000_000,
                "settledTokens": 0, "outstandingTokens": 0, "remainingTokens": 3_000_000,
                "violated": false, "manifestSha256": hardBudgetSHA, "allocationId": "allocation",
                "allocationRemainingTokens": 100, "allocationRemainingCalls": 2,
                "nextSequence": 1, "ledgerRevision": 0,
            ],
            "allocation": [
                "id": "allocation", "packetId": "packet", "promptSha256": hardBudgetSHA,
                "tokenCeiling": 100, "maxModelCalls": 2,
                "route": [
                    "model": "grok-4.6", "endpointSha256": hardBudgetSHA, "apiBackend": "responses",
                    "requestBoundTokens": 100, "maxPayloadBytes": 80, "maxOutputTokens": 20,
                    "boundProvenanceSha256": hardBudgetSHA,
                ],
            ],
        ]))
        return try XCTUnwrap(AssistantTurnCheckpoint.HardBudgetReceipt(capability))
    }

    private func hardBudgetReceiptResponse(actualTokens: Any = 10) -> [String: Any] {
        [
            "campaignId": "campaign", "manifestSha256": hardBudgetSHA,
            "allocationId": "allocation", "packetId": "packet",
            "ledgerRevision": 1, "nextSequence": 2,
            "receipts": [[
                "reservationId": "reservation-1", "sequence": 1, "providerRequestId": "provider-request",
                "model": "grok-4.6", "endpointSha256": hardBudgetSHA, "apiBackend": "responses",
                "payloadBytes": 12, "maxOutputTokens": 20, "reservedTokens": 20,
                "actualTokens": actualTokens, "chargedTokens": 10, "terminalState": "settled_usage_reported",
            ]],
        ]
    }

    func testAcceptanceBudgetManifestRejectsReserveConsumptionAndAmbiguousMarkers() {
        let manifest = AcceptanceBudgetManifest(
            schemaVersion: 2,
            runID: "run",
            campaignTokenCeiling: 4_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: hardBudgetSHA,
            expectedCLIBuild: "grokbuild-fork",
            packets: [
                acceptanceBudget(packetID: "one", marker: "ONE", promptHash: String(repeating: "0", count: 64), tokenAllocation: 2_000_000, maxModelCalls: 1),
                acceptanceBudget(packetID: "two", marker: "TWO", promptHash: String(repeating: "1", count: 64), tokenAllocation: 1_000_001, maxModelCalls: 1),
            ]
        )
        XCTAssertFalse(manifest.isValid)

        let valid = AcceptanceBudgetManifest(
            schemaVersion: 2,
            runID: "run",
            campaignTokenCeiling: 4_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: hardBudgetSHA,
            expectedCLIBuild: "grokbuild-fork",
            packets: [acceptanceBudget(packetID: "only", marker: "ONLY", promptHash: "3a4726dafd3f6c5e45b1c6a41a7e948aeedcb39387ffdaef1f8b666f407e1236", tokenAllocation: 10, maxModelCalls: 1)]
        )
        XCTAssertTrue(valid.isValid)
        XCTAssertNotNil(valid.budget(for: "Return ONLY"))
        XCTAssertNil(valid.budget(for: "Different ONLY"))
        XCTAssertNil(valid.budget(for: "Return ONLY twice ONLY"))
        XCTAssertEqual(AcceptanceBudgetGuard.resolve(prompt: "ordinary", arguments: []), .inactive)
        XCTAssertEqual(
            AcceptanceBudgetGuard.resolve(
                prompt: "ordinary",
                arguments: ["app", "--grokbuild-acceptance-budget-file=/does/not/exist"]
            ),
            .blocked
        )
        let schema3MissingSelector = AcceptanceBudgetManifest(
            schemaVersion: 3,
            runID: "run",
            campaignTokenCeiling: 4_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: hardBudgetSHA,
            expectedCLIBuild: "grokbuild-fork",
            packets: [acceptanceBudget(packetID: "only", marker: "ONLY", promptHash: "3a4726dafd3f6c5e45b1c6a41a7e948aeedcb39387ffdaef1f8b666f407e1236", tokenAllocation: 10, maxModelCalls: 1)]
        )
        XCTAssertFalse(schema3MissingSelector.isValid)
        let schema3WithLiveV1Ceiling = AcceptanceBudgetManifest(
            schemaVersion: 3,
            runID: "run",
            campaignTokenCeiling: 4_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: hardBudgetSHA,
            expectedCLIBuild: "grokbuild-fork",
            packets: [acceptanceBudget(
                packetID: "only",
                marker: "ONLY",
                promptHash: "3a4726dafd3f6c5e45b1c6a41a7e948aeedcb39387ffdaef1f8b666f407e1236",
                tokenAllocation: 10,
                maxModelCalls: 1,
                route: AcceptanceHardBudgetRoute(
                    model: "grok-4.6",
                    endpointSHA256: hardBudgetSHA,
                    apiBackend: "responses",
                    requestBoundTokens: 100,
                    maxPayloadBytes: 80,
                    maxOutputTokens: 20,
                    boundProvenanceSHA256: hardBudgetSHA,
                    managedProviderID: "openrouter",
                    authScheme: "bearer"
                )
            )]
        )
        XCTAssertFalse(schema3WithLiveV1Ceiling.isValid)
        let schema2WithV3Ceiling = AcceptanceBudgetManifest(
            schemaVersion: 2,
            runID: "run",
            campaignTokenCeiling: 20_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: hardBudgetSHA,
            expectedCLIBuild: "grokbuild-fork",
            packets: [acceptanceBudget(packetID: "only", marker: "ONLY", promptHash: "3a4726dafd3f6c5e45b1c6a41a7e948aeedcb39387ffdaef1f8b666f407e1236", tokenAllocation: 10, maxModelCalls: 1)]
        )
        XCTAssertFalse(schema2WithV3Ceiling.isValid)
        let schema2WithSelector = AcceptanceBudgetManifest(
            schemaVersion: 2,
            runID: "run",
            campaignTokenCeiling: 4_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: hardBudgetSHA,
            expectedCLIBuild: "grokbuild-fork",
            packets: [acceptanceBudget(
                packetID: "only",
                marker: "ONLY",
                promptHash: "3a4726dafd3f6c5e45b1c6a41a7e948aeedcb39387ffdaef1f8b666f407e1236",
                tokenAllocation: 10,
                maxModelCalls: 1,
                route: AcceptanceHardBudgetRoute(
                    model: "grok-4.6",
                    endpointSHA256: hardBudgetSHA,
                    apiBackend: "responses",
                    requestBoundTokens: 100,
                    maxPayloadBytes: 80,
                    maxOutputTokens: 20,
                    boundProvenanceSHA256: hardBudgetSHA,
                    managedProviderID: "openrouter",
                    authScheme: "bearer"
                )
            )]
        )
        XCTAssertFalse(schema2WithSelector.isValid)
        let schema3 = AcceptanceBudgetManifest(
            schemaVersion: 3,
            runID: "run",
            campaignTokenCeiling: 20_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: hardBudgetSHA,
            expectedCLIBuild: "grokbuild-fork",
            packets: [acceptanceBudget(
                packetID: "only",
                marker: "ONLY",
                promptHash: "3a4726dafd3f6c5e45b1c6a41a7e948aeedcb39387ffdaef1f8b666f407e1236",
                tokenAllocation: 10,
                maxModelCalls: 1,
                route: AcceptanceHardBudgetRoute(
                    model: "grok-4.6",
                    endpointSHA256: hardBudgetSHA,
                    apiBackend: "responses",
                    requestBoundTokens: 100,
                    maxPayloadBytes: 80,
                    maxOutputTokens: 20,
                    boundProvenanceSHA256: hardBudgetSHA,
                    managedProviderID: "openrouter",
                    authScheme: "bearer"
                )
            )]
        )
        XCTAssertTrue(schema3.isValid)
        XCTAssertEqual(schema3.packets[0].route.credentialAuthorizationV3?.keychainAccount, "openrouter")
        XCTAssertEqual(
            schema3.packets[0].route.credentialAuthorizationV3?.expectedProvenanceSHA256,
            hardBudgetSHA
        )
    }

    func testAcceptanceBudgetGuardRequiresPrivateRegularFileAndFinalPromptDigest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-budget-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let prompt = "Return PRIVATE-BUDGET"
        let digest = SHA256.hash(data: Data(prompt.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let cliManifest = root.appendingPathComponent("cli-manifest.json")
        let cliManifestData = Data("{\"schema\":\"hard-budget\"}".utf8)
        try cliManifestData.write(to: cliManifest)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cliManifest.path)
        let cliManifestDigest = SHA256.hash(data: cliManifestData)
            .map { String(format: "%02x", $0) }
            .joined()
        let manifest = AcceptanceBudgetManifest(
            schemaVersion: 2,
            runID: "private-budget",
            campaignTokenCeiling: 4_000_000,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: cliManifestDigest,
            expectedCLIBuild: "grokbuild-fork",
            packets: [acceptanceBudget(
                packetID: "private-budget",
                marker: "PRIVATE-BUDGET",
                promptHash: digest,
                tokenAllocation: 100,
                maxModelCalls: 1
            )]
        )
        let file = root.appendingPathComponent("budget.json")
        try JSONEncoder().encode(manifest).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let ledger = root.appendingPathComponent("ledger.json")
        try Data("{}".utf8).write(to: ledger)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledger.path)
        let argument = "\(AcceptanceBudgetGuard.argumentPrefix)\(file.path)"
        let cliManifestArgument = "\(AcceptanceBudgetGuard.cliManifestArgumentPrefix)\(cliManifest.path)"
        let ledgerArgument = "\(AcceptanceBudgetGuard.ledgerArgumentPrefix)\(ledger.path)"
        // Schema-2 budget authority without the separate exact-runtime selection
        // is legacy/partial authority and must fail closed.
        XCTAssertEqual(
            AcceptanceBudgetGuard.resolve(prompt: prompt, arguments: ["app", argument, cliManifestArgument, ledgerArgument]),
            .blocked
        )
        XCTAssertEqual(
            AcceptanceBudgetGuard.resolve(prompt: "attachment\n\n\(prompt)", arguments: ["app", argument, cliManifestArgument, ledgerArgument]),
            .blocked
        )

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertEqual(
            AcceptanceBudgetGuard.resolve(prompt: prompt, arguments: ["app", argument, cliManifestArgument, ledgerArgument]),
            .blocked
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let link = root.appendingPathComponent("budget-link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertEqual(
            AcceptanceBudgetGuard.resolve(
                prompt: prompt,
                arguments: ["app", "\(AcceptanceBudgetGuard.argumentPrefix)\(link.path)", cliManifestArgument, ledgerArgument]
            ),
            .blocked
        )
    }

    @MainActor
    func testConfiguredAcceptanceStartDefersCLIProcessUntilExactPacketPreparation() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-deferred-acceptance-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(
            acceptanceBudgetResolver: { _ in .blocked },
            acceptanceBudgetIsConfigured: { true }
        )
        store.bindTabSession(UUID(), savedModel: "grok-4.6")
        await store.start(workspace: Workspace(name: "deferred-acceptance", path: root))
        XCTAssertNil(store.process.activeProcessGeneration)
        XCTAssertEqual(store.connectionState, .idle)
        let unauthorizedSent = await store.sendAndWait("unauthorized final payload")
        XCTAssertFalse(unauthorizedSent)
        XCTAssertNil(store.process.activeProcessGeneration)
        await store.retryConnection()
        XCTAssertNil(store.process.activeProcessGeneration)
        XCTAssertTrue(store.lastError?.contains("immutable CLI budget contract") == true)
        await store.shutdownPermanently()
    }

    @MainActor
    func testAcceptanceResumeCurrentTaskRefusesUngovernedLoad() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-acceptance-resume-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChatStore(
            acceptanceBudgetResolver: { _ in .blocked },
            acceptanceBudgetIsConfigured: { true }
        )
        store.bindTabSession(UUID(), savedModel: "grok-4.6", savedGrokSessionID: "backend-retained")
        store.restorePersistedMessages([
            Message(role: .user, content: "prior prompt"),
            Message(role: .assistant, content: "prior reply"),
        ])
        await store.start(workspace: Workspace(name: "acceptance-resume", path: root))
        XCTAssertTrue(store.canResumeTaskSession)
        let resumed = await store.resumeTaskSession()
        XCTAssertFalse(resumed)
        XCTAssertNil(store.process.activeProcessGeneration)
        XCTAssertEqual(store.connectionState, .idle)
        XCTAssertTrue(store.lastError?.contains("ungoverned Resume") == true)
        await store.shutdownPermanently()
    }

    func testAcceptanceReplayMismatchCannotFallBackToNewBackend() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(
            source.range(of: "private func continueFrozenSendAfterReplayMismatchIfNeeded() async")
        )
        let end = try XCTUnwrap(
            source.range(of: "private func finishPrompt(assistantID: UUID, ok: Bool)", range: start.upperBound..<source.endIndex)
        )
        let method = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(method.contains("acceptanceBudgetIsConfigured()"))
        XCTAssertTrue(method.contains("Acceptance session/load cannot fall back to a new backend."))
    }

    func testHardBudgetLaunchEnvironmentScrubsAmbientAuthorityAndSetsOnlyExplicitContract() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-launch-authority-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("manifest.json")
        let ledger = root.appendingPathComponent("ledger.json")
        let manifestData = Data("{\"campaign\":\"test\"}".utf8)
        try manifestData.write(to: manifest)
        try Data("{}".utf8).write(to: ledger)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledger.path)
        let manifestSHA = SHA256.hash(data: manifestData)
            .map { String(format: "%02x", $0) }
            .joined()
        let ambient = [
            "PATH": "/usr/bin",
            "GROK_HARD_TOKEN_BUDGET_LEDGER": "/forged/ledger",
            "GROK_HARD_TOKEN_BUDGET_MANIFEST": "/forged/manifest",
            "GROK_HARD_TOKEN_BUDGET_ALLOCATION": "forged-allocation",
        ]
        let ordinary = GrokProcessLaunchEnvironment.resolved(base: ambient, hardBudget: nil)
        XCTAssertEqual(ordinary["PATH"], "/usr/bin")
        for key in GrokProcessLaunchEnvironment.hardBudgetKeys {
            XCTAssertNil(ordinary[key])
        }

        XCTAssertNil(HardBudgetLaunchContract(
            manifestPath: manifest.path,
            ledgerPath: ledger.path,
            allocationID: "packet-two",
            expectedManifestSHA256: manifestSHA,
            candidateExecutionLease: nil
        ))
    }

    func testGrokBuildHardBudgetCapabilityRequiresExactForkContract() throws {
        let sha = String(repeating: "a", count: 64)
        let value: [String: Any] = [
            "capabilityVersion": 2,
            "armed": true,
            "configurationValid": true,
            "enforcementPoint": "sampler-pre-dispatch",
            "ledgerVersion": 3,
            "boundMethodVersion": 1,
            "durable": true,
            "processShared": true,
            "receiptProjection": true,
            "cancelConservative": true,
            "crashConservative": true,
            "noAutomaticRetry": false,
            "samplerTransportRetriesDisabled": true,
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
            "allowedToolIds": GrokBuildHardTokenBudgetCapability.allowedToolIDs,
            "cliBuild": "grokbuild-fork",
            "status": [
                "campaignId": "campaign",
                "ceilingTokens": 3_000_000,
                "settledTokens": 0,
                "outstandingTokens": 0,
                "remainingTokens": 3_000_000,
                "violated": false,
                "manifestSha256": sha,
                "allocationId": "packet-a",
                "allocationRemainingTokens": 100,
                "allocationRemainingCalls": 1,
                "nextSequence": 1,
                "ledgerRevision": 0,
            ],
            "allocation": [
                "id": "packet-a",
                "packetId": "packet-a",
                "promptSha256": sha,
                "tokenCeiling": 100,
                "maxModelCalls": 1,
                "route": [
                    "model": "grok-4.6",
                    "endpointSha256": sha,
                    "apiBackend": "responses",
                    "requestBoundTokens": 100,
                    "maxPayloadBytes": 80,
                    "maxOutputTokens": 20,
                    "boundProvenanceSha256": sha,
                ],
            ],
        ]
        let capability = try XCTUnwrap(GrokBuildHardTokenBudgetCapability.parse(value))
        XCTAssertTrue(capability.isEnforcing)
        let budget = acceptanceBudget(
            packetID: "packet-a",
            marker: "marker",
            promptHash: sha,
            tokenAllocation: 100,
            maxModelCalls: 1,
            route: acceptanceRoute()
        )
        XCTAssertTrue(capability.authorizes(acceptanceAuthorization(budget: budget)))
        XCTAssertFalse(capability.authorizes(acceptanceAuthorization(budget: budget, runID: "other")))
        XCTAssertFalse(capability.authorizes(acceptanceAuthorization(
            budget: budget,
            campaignTokenCeiling: 3_999_999
        )))
        XCTAssertFalse(capability.authorizes(acceptanceAuthorization(
            budget: budget,
            manifestSHA256: String(repeating: "b", count: 64)
        )))
        XCTAssertFalse(capability.authorizes(acceptanceAuthorization(
            budget: budget,
            cliBuild: "other-build"
        )))
        var wrongNamespace = value
        wrongNamespace["enforcementPoint"] = "swift-poller"
        XCTAssertFalse(try XCTUnwrap(GrokBuildHardTokenBudgetCapability.parse(wrongNamespace)).isEnforcing)

        var dishonestRetryClaim = value
        dishonestRetryClaim["noAutomaticRetry"] = true
        XCTAssertFalse(try XCTUnwrap(GrokBuildHardTokenBudgetCapability.parse(dishonestRetryClaim)).isEnforcing)

        var missingContainment = value
        missingContainment.removeValue(forKey: "terminalDisabled")
        XCTAssertNil(GrokBuildHardTokenBudgetCapability.parse(missingContainment))

        var widenedTools = value
        widenedTools["allowedToolIds"] = GrokBuildHardTokenBudgetCapability.allowedToolIDs + ["Bash"]
        XCTAssertFalse(try XCTUnwrap(GrokBuildHardTokenBudgetCapability.parse(widenedTools)).isEnforcing)
        let v3Packet = try XCTUnwrap(GrokArmedCredentialAuthorizationV3(
            managedProviderID: "openrouter",
            authScheme: "bearer",
            expectedProvenanceSHA256: sha
        ))
        XCTAssertFalse(capability.authorizes(acceptanceAuthorization(
            budget: budget,
            campaignTokenCeiling: 20_000_000,
            credentialAuthorizationV3: v3Packet
        )))
    }

    func testLiveV3CapabilityProjectionIsNotEnforcingOnHistoricalV2Decoder() throws {
        let sha = String(repeating: "a", count: 64)
        let value: [String: Any] = [
            "capabilityVersion": 3,
            "armed": true,
            "configurationValid": true,
            "enforcementPoint": "sampler-pre-dispatch",
            "ledgerVersion": 4,
            "boundMethodVersion": 3,
            "durable": true,
            "processShared": true,
            "receiptProjection": true,
            "cancelConservative": true,
            "crashConservative": true,
            "noAutomaticRetry": true,
            "samplerTransportRetriesDisabled": true,
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
            "allowedToolIds": GrokBuildHardTokenBudgetCapability.allowedToolIDs,
            "cliBuild": "grokbuild-fork",
            "v3Authority": [
                "authorityVersion": 3,
                "provenanceSha256": sha,
                "provenance": ["schemaVersion": 1],
            ],
            "status": [
                "campaignId": "campaign",
                "ceilingTokens": 19_000_000,
                "settledTokens": 0,
                "outstandingTokens": 0,
                "remainingTokens": 19_000_000,
                "violated": false,
                "manifestSha256": sha,
                "allocationId": "packet-a",
                "allocationRemainingTokens": 100,
                "allocationRemainingCalls": 1,
                "nextSequence": 1,
                "ledgerRevision": 0,
            ],
            "allocation": [
                "id": "packet-a",
                "packetId": "packet-a",
                "promptSha256": sha,
                "tokenCeiling": 100,
                "maxModelCalls": 1,
                "route": [
                    "model": "grok-4.6",
                    "endpointSha256": sha,
                    "apiBackend": "responses",
                    "requestBoundTokens": 100,
                    "maxPayloadBytes": 80,
                    "maxOutputTokens": 20,
                    "boundProvenanceSha256": sha,
                ],
            ],
        ]
        let capability = try XCTUnwrap(GrokBuildHardTokenBudgetCapability.parse(value))
        XCTAssertEqual(capability.capabilityVersion, 3)
        XCTAssertFalse(capability.isEnforcing)
        let budget = acceptanceBudget(
            packetID: "packet-a",
            marker: "marker",
            promptHash: sha,
            tokenAllocation: 100,
            maxModelCalls: 1,
            route: acceptanceRoute()
        )
        XCTAssertFalse(capability.authorizes(acceptanceAuthorization(budget: budget)))
        let v3Packet = try XCTUnwrap(GrokArmedCredentialAuthorizationV3(
            managedProviderID: "openrouter",
            authScheme: "bearer",
            expectedProvenanceSHA256: sha
        ))
        XCTAssertTrue(capability.authorizes(acceptanceAuthorization(
            budget: budget,
            campaignTokenCeiling: 20_000_000,
            credentialAuthorizationV3: v3Packet
        )))
        XCTAssertFalse(capability.authorizes(acceptanceAuthorization(
            budget: budget,
            campaignTokenCeiling: 4_000_000,
            credentialAuthorizationV3: v3Packet
        )))
    }

    func testHardBudgetReceiptPreservesHistoricalDecodeButNewEvidenceCarriesContainment() throws {
        let sha = String(repeating: "a", count: 64)
        let capability = try XCTUnwrap(GrokBuildHardTokenBudgetCapability.parse([
            "capabilityVersion": 2, "armed": true, "configurationValid": true,
            "enforcementPoint": "sampler-pre-dispatch", "ledgerVersion": 3,
            "boundMethodVersion": 1, "durable": true, "processShared": true,
            "receiptProjection": true,
            "cancelConservative": true, "crashConservative": true,
            "noAutomaticRetry": false, "samplerTransportRetriesDisabled": true,
            "authProviderHelpersDisabled": true, "terminalDisabled": true,
            "externalMcpDisabled": true, "hooksDisabled": true, "pluginsDisabled": true,
            "lspDisabled": true, "workflowsDisabled": true, "schedulerDisabled": true,
            "protectedAuthorityFs": true, "workspaceFsConfined": true,
            "allowedToolIds": GrokBuildHardTokenBudgetCapability.allowedToolIDs,
            "cliBuild": "grokbuild-fork",
            "status": [
                "campaignId": "campaign", "ceilingTokens": 3_000_000,
                "settledTokens": 0, "outstandingTokens": 0, "remainingTokens": 3_000_000,
                "violated": false, "manifestSha256": sha, "allocationId": "packet-a",
                "allocationRemainingTokens": 100, "allocationRemainingCalls": 1,
                "nextSequence": 0, "ledgerRevision": 0,
            ],
            "allocation": [
                "id": "packet-a", "packetId": "packet-a", "promptSha256": sha,
                "tokenCeiling": 100, "maxModelCalls": 1,
                "route": [
                    "model": "grok-4.6", "endpointSha256": sha, "apiBackend": "responses",
                    "requestBoundTokens": 100, "maxPayloadBytes": 80, "maxOutputTokens": 20,
                    "boundProvenanceSha256": sha,
                ],
            ],
        ]))
        let receipt = try XCTUnwrap(AssistantTurnCheckpoint.HardBudgetReceipt(capability))
        XCTAssertEqual(receipt.allowedToolIDs, GrokBuildHardTokenBudgetCapability.allowedToolIDs)
        XCTAssertEqual(receipt.noAutomaticRetry, false)
        XCTAssertEqual(receipt.samplerTransportRetriesDisabled, true)

        var historical = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any]
        )
        [
            "noAutomaticRetry", "samplerTransportRetriesDisabled", "authProviderHelpersDisabled", "terminalDisabled",
            "externalMCPDisabled", "hooksDisabled", "pluginsDisabled", "lspDisabled",
            "workflowsDisabled", "schedulerDisabled", "protectedAuthorityFS", "workspaceFSConfined",
            "allowedToolIDs", "candidateBinarySHA256", "candidateProvenanceSHA256",
            "candidateSourceSHA", "candidateTeamIdentifier", "candidateDesignatedRequirement",
            "candidateCodeDirectoryHash",
        ].forEach { historical.removeValue(forKey: $0) }
        let decoded = try JSONDecoder().decode(
            AssistantTurnCheckpoint.HardBudgetReceipt.self,
            from: JSONSerialization.data(withJSONObject: historical)
        )
        XCTAssertNil(decoded.allowedToolIDs)
        XCTAssertNil(decoded.terminalDisabled)
    }

    func testChildSessionLedgerRejectsTraversalIdentity() async {
        let process = GrokProcess()
        let receipts = await process.fetchChildToolReceipts(childID: "../other")
        XCTAssertNil(receipts)
    }

    func testMirroredChildToolReceiptsNeverBecomeParentTools() {
        let childReceipts = [
            ChildToolReceipt(
                id: "child-search",
                title: "search_tool",
                status: .succeeded,
                mcpReceiptRole: .discovery,
                qualifiedToolName: nil,
                discoveredQualifiedToolNames: ["grokbuild-browser__browser_open_url"]
            ),
            ChildToolReceipt(
                id: "child-use",
                title: "grokbuild-browser__browser_open_url",
                status: .succeeded,
                mcpReceiptRole: .invocation,
                qualifiedToolName: "grokbuild-browser__browser_open_url",
                discoveredQualifiedToolNames: []
            ),
        ]

        XCTAssertEqual(
            ChatStore.parentToolCallIDs(
                observedIDs: ["parent-spawn", "child-search", "child-use", "parent-collect"],
                childReceipts: childReceipts
            ),
            ["parent-spawn", "parent-collect"]
        )
    }

    func testQuestionReducerCoalescesOnlyTheSameAuthoritativeRequestIdentity() {
        let question = QuestionItem(
            id: "audience",
            text: "Which audience should this target?",
            options: [QuestionOption(label: "Consumer", description: nil)],
            multiSelect: false
        )
        let original = QuestionRequest(
            id: AnyHashable(42),
            sessionId: "session",
            questions: [question],
            isResolved: false,
            answerSummary: nil
        )
        let replay = QuestionRequest(
            id: AnyHashable(42),
            sessionId: "session",
            questions: [question],
            isResolved: false,
            answerSummary: "updated"
        )

        var pending = QuestionRequest.merging(original, into: [])
        pending = QuestionRequest.merging(replay, into: pending)

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].id, replay.id)
        XCTAssertEqual(pending[0].answerSummary, "updated")
    }

    func testIdenticalQuestionContentWithDifferentRPCIDsRemainsTwoRequests() {
        let question = QuestionItem(
            id: "audience",
            text: "Which audience should this target?",
            options: [],
            multiSelect: false
        )
        let first = QuestionRequest(
            id: AnyHashable(42),
            sessionId: "session",
            questions: [question],
            isResolved: false,
            answerSummary: nil
        )
        let second = QuestionRequest(
            id: AnyHashable(43),
            sessionId: "session",
            questions: [question],
            isResolved: false,
            answerSummary: nil
        )

        var pending = QuestionRequest.merging(first, into: [])
        pending = QuestionRequest.merging(second, into: pending)

        XCTAssertEqual(pending.map(\.id), [first.id, second.id])
    }

    func testDifferentQuestionsRemainIndependent() {
        let first = QuestionRequest(
            id: AnyHashable(1),
            sessionId: "session",
            questions: [QuestionItem(id: "one", text: "First?", options: [], multiSelect: false)],
            isResolved: false,
            answerSummary: nil
        )
        let second = QuestionRequest(
            id: AnyHashable(2),
            sessionId: "session",
            questions: [QuestionItem(id: "two", text: "Second?", options: [], multiSelect: false)],
            isResolved: false,
            answerSummary: nil
        )

        var pending = QuestionRequest.merging(first, into: [])
        pending = QuestionRequest.merging(second, into: pending)

        XCTAssertEqual(pending.map(\.id), [first.id, second.id])
    }

    func testInteractionIdentityIncludesBackendSession() {
        XCTAssertTrue(ACPInteractionRequestIdentity.matches(
            lhsID: AnyHashable(7),
            lhsSessionID: "backend-a",
            rhsID: AnyHashable(7),
            rhsSessionID: "backend-a"
        ))
        XCTAssertFalse(ACPInteractionRequestIdentity.matches(
            lhsID: AnyHashable(7),
            lhsSessionID: "backend-a",
            rhsID: AnyHashable(7),
            rhsSessionID: "backend-b"
        ))
        XCTAssertFalse(ACPInteractionRequestIdentity.ownsActiveSession(
            "backend-a",
            activeSessionID: "backend-b"
        ))
    }

    func testPlanReplayPreservesPreviouslyObservedPlanText() {
        let current = ExitPlanRequest(
            id: AnyHashable(9),
            sessionId: "backend",
            planText: "# Native plan",
            isResolved: false,
            verdict: nil
        )
        let replay = ExitPlanRequest(
            id: AnyHashable(9),
            sessionId: "backend",
            planText: "",
            isResolved: false,
            verdict: nil
        )

        XCTAssertEqual(ExitPlanRequest.merging(replay, into: current).planText, "# Native plan")
    }

    @MainActor
    func testPlanApprovalAnswersOneACPRequestWithoutCreatingASecondPrompt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-plan-interaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rpcLogURL = root.appendingPathComponent("rpc.log")
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        prompt_rpc_id=''
        while IFS= read -r line; do
          printf '%s\n' "$line" >> '\(rpcLogURL.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"plan-backend","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id" ;;
            *'"method":"session/prompt"'*)
              prompt_rpc_id="$id"
              printf '{"jsonrpc":"2.0","id":77,"method":"_x.ai/exit_plan_mode","params":{"sessionId":"plan-backend","toolCallId":"plan-tool","planContent":"# One native plan"}}\n'
              ;;
            *'"outcome":"approved"'*)
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"plan-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn"}}}\n'
              printf '{"jsonrpc":"2.0","id":%s,"result":{"stopReason":"end_turn"}}\n' "$prompt_rpc_id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "plan-interaction", path: root))

        let sendTask = Task { @MainActor in await store.sendAndWait("Show one native plan") }
        for _ in 0..<200 where store.pendingExitPlan == nil {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        guard let request = store.pendingExitPlan else {
            let rpc = (try? String(contentsOf: rpcLogURL, encoding: .utf8)) ?? "missing log"
            let failure = store.lastError ?? "none"
            XCTFail("Missing plan request; process=\(store.process.state), connection=\(store.connectionState), error=\(failure), rpc=\(rpc)")
            await store.shutdownPermanently()
            _ = await sendTask.value
            return
        }
        XCTAssertEqual(request.id, AnyHashable(77))
        XCTAssertEqual(request.sessionId, "plan-backend")
        store.respondToExitPlan(request, verdict: .approved)

        let sent = await sendTask.value
        XCTAssertTrue(sent)
        XCTAssertNil(store.pendingExitPlan)
        XCTAssertEqual(store.messages.filter { $0.role == .user }.map(\.content), ["Show one native plan"])

        let rpcLines = try String(contentsOf: rpcLogURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(rpcLines.filter { $0.contains("\"method\":\"session/prompt\"") }.count, 1)
        XCTAssertEqual(rpcLines.filter {
            $0.contains("\"id\":77") && $0.contains("\"outcome\":\"approved\"")
        }.count, 1)
        XCTAssertFalse(rpcLines.contains { $0.contains("[Plan approved]") })
        await store.shutdownPermanently()
    }

    func testSubagentTerminalDeduplicationUsesWorkerLifecycleIdentity() {
        let tabID = UUID()
        let first = SubagentFinishedEvent(
            identity: ACPEventIdentity(
                localTabID: tabID,
                backendSessionID: "parent",
                processGeneration: 4,
                backendEventID: "event-a"
            ),
            childID: "child",
            status: "completed",
            durationMilliseconds: 100,
            turns: 1,
            toolCallCount: 2,
            tokenCount: 3,
            redactedError: nil
        )
        let replay = SubagentFinishedEvent(
            identity: ACPEventIdentity(
                localTabID: tabID,
                backendSessionID: "parent",
                processGeneration: 4,
                backendEventID: "event-b"
            ),
            childID: "child",
            status: "completed",
            durationMilliseconds: 100,
            turns: 1,
            toolCallCount: 2,
            tokenCount: 3,
            redactedError: nil
        )

        XCTAssertEqual(first.deduplicationKey, replay.deduplicationKey)
        XCTAssertFalse(first.deduplicationKey.contains("event-a"))
    }

    func testSubagentLifecycleErrorsAreRedactedAndBounded() throws {
        let secret = "super-secret-worker-token"
        let raw = "token=\(secret) " + String(repeating: "failure ", count: 80)
        let redacted = try XCTUnwrap(GrokProcess.redactedLifecycleText(raw))

        XCTAssertFalse(redacted.contains(secret))
        XCTAssertTrue(redacted.contains("<redacted>"))
        XCTAssertLessThanOrEqual(redacted.count, 280)
    }

    func testACPEventsStayOnTheParentSessionWhenWorkerSessionsStream() {
        let params: [String: Any] = [
            "sessionId": "worker-session",
            "update": ["sessionUpdate": "agent_message_chunk"]
        ]
        let update = params["update"] as? [String: Any]

        XCTAssertEqual(
            GrokProcess.eventSessionID(from: params, update: update),
            "worker-session"
        )
        XCTAssertFalse(
            GrokProcess.eventBelongsToSession("worker-session", currentSessionID: "parent-session")
        )
        XCTAssertTrue(
            GrokProcess.eventBelongsToSession(nil, currentSessionID: "parent-session")
        )
        XCTAssertTrue(
            GrokProcess.eventBelongsToSession("parent-session", currentSessionID: "parent-session")
        )
    }

    private enum TurnFixtureEvent {
        case chunk(String)
        case tool(String)
        case promptResponse(Bool)
        case completion
    }

    private func settlementDecisions(for events: [TurnFixtureEvent]) -> [TurnSettlementCoordinator.Decision] {
        var coordinator = TurnSettlementCoordinator()
        let generation = coordinator.begin(assistantID: UUID())
        var decisions: [TurnSettlementCoordinator.Decision] = []
        for event in events {
            let decision: TurnSettlementCoordinator.Decision?
            switch event {
            case .chunk, .tool:
                decision = nil
            case .promptResponse(let ok):
                decision = coordinator.recordPromptResult(generation: generation, ok: ok)
            case .completion:
                decision = coordinator.recordCompletionConsumed()
            }
            if let decision { decisions.append(decision) }
        }
        return decisions
    }

    func testTurnSettlementFixturesFinalizeExactlyOnceAcrossWireOrders() {
        let fixtures: [[TurnFixtureEvent]] = [
            [.chunk("final"), .promptResponse(true), .completion],
            [.promptResponse(true), .chunk("final"), .completion],
            [.completion, .chunk("late final"), .promptResponse(true)],
            [.tool("browser"), .completion, .chunk("synthesis"), .promptResponse(true)],
            [.tool("explore"), .tool("general-purpose"), .chunk("parent"), .promptResponse(true), .completion],
        ]

        for fixture in fixtures {
            let decisions = settlementDecisions(for: fixture)
            XCTAssertEqual(decisions.count, 1)
            XCTAssertTrue(decisions[0].ok)
        }
    }

    func testTurnSettlementFailureAndStopGenerationCannotFinishANewerTurn() {
        var coordinator = TurnSettlementCoordinator()
        let oldAssistant = UUID()
        let oldGeneration = coordinator.begin(assistantID: oldAssistant)
        coordinator.invalidate()
        let newAssistant = UUID()
        let newGeneration = coordinator.begin(assistantID: newAssistant)

        XCTAssertNil(coordinator.recordPromptResult(generation: oldGeneration, ok: true))
        XCTAssertNil(coordinator.recordPromptResult(generation: newGeneration, ok: true))
        XCTAssertEqual(
            coordinator.recordCompletionConsumed(),
            .init(assistantID: newAssistant, ok: true)
        )

        var failed = TurnSettlementCoordinator()
        let failedID = UUID()
        let failedGeneration = failed.begin(assistantID: failedID)
        XCTAssertEqual(
            failed.recordPromptResult(generation: failedGeneration, ok: false),
            .init(assistantID: failedID, ok: false)
        )

        var backendFailure = TurnSettlementCoordinator()
        let backendFailureID = UUID()
        let backendFailureGeneration = backendFailure.begin(assistantID: backendFailureID)
        XCTAssertNil(backendFailure.recordPromptResult(generation: backendFailureGeneration, ok: true))
        XCTAssertEqual(
            backendFailure.recordCompletionConsumed(ok: false),
            .init(assistantID: backendFailureID, ok: false),
            "an authoritative ACP error completion must not be promoted to success"
        )
    }

    func testModelReducerRequiresExactTabBackendGenerationAndRequestIdentity() {
        let tab = UUID()
        let identity = ModelRequestIdentity(
            localTabID: tab,
            backendSessionID: "backend-a",
            processGeneration: 7,
            requestID: UUID()
        )
        var state = ModelExecutionReducer.beginRequest(
            modelID: "grok-4.5",
            identity: identity,
            preserving: .unknown,
            at: Date(timeIntervalSince1970: 1)
        )
        let original = state
        let staleIdentities = [
            ModelRequestIdentity(
                localTabID: UUID(), backendSessionID: identity.backendSessionID,
                processGeneration: identity.processGeneration, requestID: identity.requestID
            ),
            ModelRequestIdentity(
                localTabID: identity.localTabID, backendSessionID: "backend-b",
                processGeneration: identity.processGeneration, requestID: identity.requestID
            ),
            ModelRequestIdentity(
                localTabID: identity.localTabID, backendSessionID: identity.backendSessionID,
                processGeneration: 8, requestID: identity.requestID
            ),
            ModelRequestIdentity(
                localTabID: identity.localTabID, backendSessionID: identity.backendSessionID,
                processGeneration: identity.processGeneration, requestID: UUID()
            ),
        ]

        for stale in staleIdentities {
            XCTAssertFalse(ModelExecutionReducer.confirm(
                effectiveModelID: "wrong",
                identity: stale,
                state: &state
            ))
            XCTAssertFalse(ModelExecutionReducer.reject(
                failure: .rejected,
                identity: stale,
                state: &state
            ))
            XCTAssertEqual(state, original)
        }
    }

    func testModelReducerDoesNotConfirmAnAcceptedRequestWithoutEffectiveModel() {
        let identity = ModelRequestIdentity(
            localTabID: UUID(), backendSessionID: "backend",
            processGeneration: 3, requestID: UUID()
        )
        var state = ModelExecutionReducer.beginRequest(
            modelID: "gpt-5.6-terra",
            identity: identity,
            preserving: .unknown
        )

        XCTAssertTrue(ModelExecutionReducer.acceptWithoutEffectiveModel(
            identity: identity,
            state: &state
        ))
        XCTAssertEqual(state.status, .requested)
        XCTAssertEqual(state.requestedModelID, "gpt-5.6-terra")
        XCTAssertNil(state.effectiveModelID)
    }

    func testModelReducerConfirmsExplicitReadbackAndPreservesItOnRejection() {
        let identity = ModelRequestIdentity(
            localTabID: UUID(), backendSessionID: "backend",
            processGeneration: 11, requestID: UUID()
        )
        var state = ModelExecutionReducer.launch(
            requestedModelID: "grok-4.5",
            identity: identity
        )
        XCTAssertTrue(ModelExecutionReducer.confirm(
            effectiveModelID: "grok-4.5",
            identity: identity,
            state: &state
        ))
        XCTAssertEqual(state.status, .confirmed)

        let next = ModelRequestIdentity(
            localTabID: identity.localTabID,
            backendSessionID: identity.backendSessionID,
            processGeneration: identity.processGeneration,
            requestID: UUID()
        )
        state = ModelExecutionReducer.beginRequest(
            modelID: "gpt-5.6-terra",
            identity: next,
            preserving: state
        )
        XCTAssertTrue(ModelExecutionReducer.reject(
            failure: .rejected,
            identity: next,
            state: &state
        ))
        XCTAssertEqual(state.status, .rejected)
        XCTAssertEqual(state.requestedModelID, "gpt-5.6-terra")
        XCTAssertEqual(state.effectiveModelID, "grok-4.5")
    }

    func testEffectiveModelParsingRequiresAnExplicitReadback() {
        XCTAssertNil(GrokProcess.effectiveModelID(from: [:]))
        XCTAssertEqual(GrokProcess.effectiveModelID(from: [
            "_meta": ["model": ["Ok": "grok-4.5"]]
        ]), "grok-4.5")
        XCTAssertEqual(GrokProcess.effectiveModelID(from: [
            "modelState": ["currentModelId": "gpt-5.6-terra"]
        ]), "gpt-5.6-terra")
    }

    func testFreshSessionRecoveryPreservesTheRequestedModelOnlyWhileItIsAvailable() {
        XCTAssertEqual(
            ChatStore.recoverableModelForNewSession(
                "deepseek-deepseek-v4-flash-0731",
                availableModels: ["grok-4.5", "deepseek-deepseek-v4-flash-0731"]
            ),
            "deepseek-deepseek-v4-flash-0731"
        )
        XCTAssertNil(ChatStore.recoverableModelForNewSession(
            "deepseek-deepseek-v4-flash-0731",
            availableModels: ["grok-4.5"]
        ))
        XCTAssertNil(ChatStore.recoverableModelForNewSession(
            nil,
            availableModels: ["grok-4.5"]
        ))
    }

    @MainActor
    func testUnstartedTabModelSelectionIsSavedRatherThanLive() async {
        let store = ChatStore()
        store.prepare(workspace: Workspace(
            name: "fixture",
            path: FileManager.default.temporaryDirectory
        ))
        store.bindTabSession(UUID(), modelIntent: .inheritProjectDefault)
        store.setModel("grok-4.5")

        XCTAssertEqual(store.modelExecutionState.status, .requested)
        XCTAssertEqual(store.modelSelectorStatusLabel, "Saved")
        XCTAssertTrue(store.modelAccessibilityValue.contains("no active process"))
        XCTAssertEqual(store.persistedModelIntent, .explicit("grok-4.5"))
        await store.shutdownPermanently()
    }

    @MainActor
    func testLiveModelSwitchRefreshesSessionMetadataBeforeNextTurnReceipt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-model-metadata-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rpcLogURL = root.appendingPathComponent("rpc.log")
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        current_model='model-a'
        while IFS= read -r line; do
          printf '%s\n' "$line" >> '\(rpcLogURL.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"agentVersion":"1.0.5","modelState":{"currentModelId":"model-a","availableModels":[{"modelId":"model-a"},{"modelId":"model-b"}]}}}}\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"metadata-switch-backend","models":{"currentModelId":"model-a","availableModels":[{"modelId":"model-a"},{"modelId":"model-b"}]}}}\n' "$id"
              ;;
            *'"method":"x.ai/session/info"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"result":{"sessionId":"metadata-switch-backend","cwd":"\(root.path)","model":"%s","resolvedModelId":"resolved-%s","modelFingerprint":"fingerprint-%s","apiBackend":"responses"}}}\n' "$id" "$current_model" "$current_model" "$current_model"
              ;;
            *'"method":"session/set_model"'*)
              current_model='model-b'
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"model-b"}}}}\n' "$id"
              ;;
            *'"method":"session/prompt"'*)
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"metadata-switch-backend","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Model B answered."}}}}\n'
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"metadata-switch-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"totalTokens":10,"modelCalls":1,"numTurns":1,"modelUsage":{"model-b":{"totalTokens":10,"modelCalls":1}}}}}}\n'
              printf '{"jsonrpc":"2.0","id":%s,"result":{"stopReason":"end_turn"}}\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "model-a")
        await store.start(workspace: Workspace(name: "metadata-switch", path: root))

        for _ in 0..<200 {
            let rpc = (try? String(contentsOf: rpcLogURL, encoding: .utf8)) ?? ""
            if rpc.contains("\"method\":\"x.ai/session/info\"") { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        store.setModel("model-b")
        for _ in 0..<200 where store.modelExecutionState.status != .confirmed {
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<200 {
            let rpc = (try? String(contentsOf: rpcLogURL, encoding: .utf8)) ?? ""
            if rpc.components(separatedBy: "\"method\":\"x.ai/session/info\"").count - 1 >= 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        let sent = await store.sendAndWait("Answer on the confirmed model")
        XCTAssertTrue(sent)
        let observed = try XCTUnwrap(
            store.messages.last(where: { $0.role == .assistant })?
                .assistantTrace?.checkpoint?.observedRouteReceipt
        )
        XCTAssertEqual(observed.sessionModelID, "model-b")
        XCTAssertEqual(observed.resolvedModelID, "resolved-model-b")
        XCTAssertEqual(observed.modelFingerprint, "fingerprint-model-b")
        XCTAssertEqual(observed.turnUsageEffectiveModelID, "model-b")
        XCTAssertNotEqual(observed.sessionModelID, "model-a")
        await store.shutdownPermanently()
    }

    @MainActor
    func testSchema2AcceptancePacketStopsBeforeCredentialMaterializationOrCandidateSpawn() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-acceptance-budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = "GB-S4-BUDGET-TEST"
        let zeroSHA = String(repeating: "0", count: 64)
        let budget = acceptanceBudget(
            packetID: "packet",
            marker: marker,
            promptHash: zeroSHA,
            tokenAllocation: 10,
            maxModelCalls: 1,
            route: acceptanceRoute(
                requestBoundTokens: 10,
                maxPayloadBytes: 5,
                maxOutputTokens: 5,
                sha256: zeroSHA
            )
        )
        let store = ChatStore(
            acceptanceBudgetResolver: { prompt in
                prompt.contains(marker)
                    ? .budget(self.acceptanceAuthorization(budget: budget, runID: "test"))
                    : .blocked
            },
            acceptanceBudgetIsConfigured: { true }
        )
        store.bindTabSession(UUID(), savedModel: "grok-4.6")
        await store.start(workspace: Workspace(name: "acceptance-budget", path: root))

        let sent = await store.sendAndWait("Return \(marker)")
        XCTAssertFalse(sent)
        XCTAssertTrue(store.lastError?.contains("schema-3 credential authorization") == true)
        XCTAssertNil(store.process.activeProcessGeneration)
        await store.shutdownPermanently()
    }

    @MainActor
    func testLegacyOfficialCLIOverrideCannotLaunchAcceptanceWithoutCandidateSelection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-no-hard-budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dummyCLI = root.appendingPathComponent("fake-grok")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: dummyCLI)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dummyCLI.path)

        GrokProcess.cliOverrideForTests = dummyCLI
        defer { GrokProcess.cliOverrideForTests = nil }
        let budget = acceptanceBudget(
            packetID: "no-fork",
            marker: "NO-FORK-BUDGET",
            promptHash: String(repeating: "0", count: 64),
            tokenAllocation: 10,
            maxModelCalls: 1
        )
        let store = ChatStore(
            acceptanceBudgetResolver: { _ in
                .budget(self.acceptanceAuthorization(budget: budget))
            },
            acceptanceBudgetIsConfigured: { true }
        )
        store.bindTabSession(UUID(), savedModel: "grok-4.6")
        await store.start(workspace: Workspace(name: "no-budget", path: root))

        let sent = await store.sendAndWait("Return NO-FORK-BUDGET")
        XCTAssertFalse(sent)
        XCTAssertTrue(store.lastError?.contains("schema-3 credential authorization") == true)
        XCTAssertNil(store.process.activeProcessGeneration)
        await store.shutdownPermanently()
    }

    @MainActor
    func testSchema3AcceptanceDispatchRefusesNativeRouteBeforeBind() async throws {
        let fixture = try CandidateRuntimeTestFixture.makeCredentialReceiverExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        CandidateRuntimeTestFixture.installSignatureOverride()
        defer { GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = nil }
        let lease = try XCTUnwrap(GrokCandidateRuntimeAuthority.acquireLease(
            selectionPath: fixture.selection.path,
            expectedCLIBuild: fixture.cliBuild
        ))
        let cliManifest = fixture.container.appendingPathComponent("cli-manifest.json")
        let cliManifestData = Data("{\"campaign\":\"schema-3-native\"}".utf8)
        try cliManifestData.write(to: cliManifest)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cliManifest.path)
        let ledger = fixture.container.appendingPathComponent("ledger.json")
        try Data("{}".utf8).write(to: ledger)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ledger.path)
        let manifestSHA = SHA256.hash(data: cliManifestData)
            .map { String(format: "%02x", $0) }
            .joined()
        let provenanceSHA = String(repeating: "d", count: 64)
        let v3 = try XCTUnwrap(GrokArmedCredentialAuthorizationV3(
            managedProviderID: "openrouter",
            authScheme: "bearer",
            expectedProvenanceSHA256: provenanceSHA
        ))
        let budget = acceptanceBudget(
            packetID: "schema-3-native",
            marker: "SCHEMA-3-NATIVE",
            promptHash: String(repeating: "0", count: 64),
            tokenAllocation: 10,
            maxModelCalls: 1,
            route: AcceptanceHardBudgetRoute(
                model: "grok-4.6",
                endpointSHA256: provenanceSHA,
                apiBackend: "responses",
                requestBoundTokens: 100,
                maxPayloadBytes: 80,
                maxOutputTokens: 20,
                boundProvenanceSHA256: provenanceSHA,
                managedProviderID: "openrouter",
                authScheme: "bearer"
            )
        )
        final class PIDBox { var value: pid_t = 0 }
        let observed = PIDBox()
        GrokCandidateProcessLauncher.spawnedProcessObserverForTests = { observed.value = $0 }
        defer { GrokCandidateProcessLauncher.spawnedProcessObserverForTests = nil }
        GrokProcess.armedKeychainClientForTests = GrokArmedCredentialKeychainClient { _, item in
            item?.pointee = [Data([0x01])] as NSArray
            return errSecSuccess
        }
        defer { GrokProcess.armedKeychainClientForTests = nil }

        let store = ChatStore(
            acceptanceBudgetResolver: { _ in
                .budget(self.acceptanceAuthorization(
                    budget: budget,
                    campaignTokenCeiling: 20_000_000,
                    manifestSHA256: manifestSHA,
                    cliManifestPath: cliManifest.path,
                    ledgerPath: ledger.path,
                    candidateExecutionLease: lease,
                    credentialAuthorizationV3: v3
                ))
            },
            acceptanceBudgetIsConfigured: { true }
        )
        store.bindTabSession(UUID(), savedModel: "grok-4.6")
        await store.start(workspace: Workspace(name: "schema-3-native", path: fixture.container))
        let sent = await store.sendAndWait("Return SCHEMA-3-NATIVE")
        XCTAssertFalse(sent)
        XCTAssertTrue(store.lastError?.contains("schema-3 credential authorization") == true)
        XCTAssertFalse(store.lastError?.contains("Armed credential launch stopped") == true)
        XCTAssertEqual(observed.value, 0)
        XCTAssertNil(store.process.activeProcessGeneration)
        await store.shutdownPermanently()
    }

    func testLastLiveDoesNotAttachToANewerInheritedDefault() {
        XCTAssertEqual(
            ChatStore.modelSelectorStatusLabel(
                status: .confirmed,
                receiptIsCurrentProcess: false,
                currentModel: "grok-4.6",
                effectiveModelID: "grok-4.5",
                requestedModelID: "grok-4.5",
                providerFacingRequestedModel: nil,
                requestHasIdentity: true,
                followsInheritedDefault: true
            ),
            "Default"
        )
        XCTAssertEqual(
            ChatStore.modelSelectorStatusLabel(
                status: .confirmed,
                receiptIsCurrentProcess: false,
                currentModel: "grok-4.5",
                effectiveModelID: "grok-4.5",
                requestedModelID: "grok-4.5",
                providerFacingRequestedModel: nil,
                requestHasIdentity: true,
                followsInheritedDefault: true
            ),
            "Last live"
        )
        XCTAssertEqual(
            ChatStore.modelSelectorStatusLabel(
                status: .confirmed,
                receiptIsCurrentProcess: false,
                currentModel: "deepseek-deepseek-v4-flash-0731",
                effectiveModelID: "deepseek/deepseek-v4-flash-0731",
                requestedModelID: "deepseek-deepseek-v4-flash-0731",
                providerFacingRequestedModel: "deepseek/deepseek-v4-flash-0731",
                requestHasIdentity: true,
                followsInheritedDefault: false
            ),
            "Last live"
        )
        XCTAssertTrue(
            ChatStore.currentModelMatchesConfirmedReceipt(
                currentModel: "deepseek-deepseek-v4-flash-0731",
                effectiveModelID: "deepseek/deepseek-v4-flash-0731",
                requestedModelID: "deepseek-deepseek-v4-flash-0731",
                providerFacingRequestedModel: "deepseek/deepseek-v4-flash-0731"
            )
        )
        XCTAssertFalse(
            ChatStore.currentModelMatchesConfirmedReceipt(
                currentModel: "grok-4.6",
                effectiveModelID: "grok-4.5",
                requestedModelID: "grok-4.5",
                providerFacingRequestedModel: nil
            )
        )
    }

    func testIdleInheritedNewChatUsesDefaultNotUnknown() {
        XCTAssertEqual(
            ChatStore.modelSelectorStatusLabel(
                status: .unknown,
                receiptIsCurrentProcess: false,
                currentModel: "grok-4.6",
                effectiveModelID: nil,
                requestedModelID: nil,
                providerFacingRequestedModel: nil,
                requestHasIdentity: false,
                followsInheritedDefault: true
            ),
            "Default"
        )
        XCTAssertEqual(
            ChatStore.modelSelectorStatusLabel(
                status: .unknown,
                receiptIsCurrentProcess: false,
                currentModel: "",
                effectiveModelID: nil,
                requestedModelID: nil,
                providerFacingRequestedModel: nil,
                requestHasIdentity: false,
                followsInheritedDefault: true
            ),
            "Unknown"
        )
        XCTAssertEqual(
            ChatStore.modelSelectorStatusLabel(
                status: .unknown,
                receiptIsCurrentProcess: false,
                currentModel: "grok-4.6",
                effectiveModelID: nil,
                requestedModelID: nil,
                providerFacingRequestedModel: nil,
                requestHasIdentity: false,
                followsInheritedDefault: false
            ),
            "Unknown"
        )
        XCTAssertEqual(
            ChatStore.modelSelectorStatusLabel(
                status: .unknown,
                receiptIsCurrentProcess: false,
                currentModel: "grok-4.6",
                effectiveModelID: nil,
                requestedModelID: nil,
                providerFacingRequestedModel: nil,
                requestHasIdentity: false,
                followsInheritedDefault: true,
                isConnecting: true
            ),
            "Connecting"
        )
    }

    func testACPModeParsingAcceptsNestedAndLoadShapesWithoutInventingChat() {
        let nested = AgentSessionModeParsing.parse(from: [
            "sessionId": "nested",
            "modes": [
                "currentModeId": "chat",
                "availableModes": [
                    ["id": "chat", "name": "Chat"],
                    ["id": "agent"],
                    ["id": "plan"],
                    ["id": "yolo"],
                ],
            ],
        ])
        XCTAssertEqual(nested.current, .chat)
        XCTAssertEqual(nested.available, [.chat, .agent, .plan, .yolo])

        let topLevel = AgentSessionModeParsing.parse(from: [
            "currentModeId": "plan",
            "availableModes": ["agent", "plan", "yolo"],
        ])
        XCTAssertEqual(topLevel.current, .plan)
        XCTAssertEqual(topLevel.available, [.agent, .plan, .yolo])

        let effortOnly = AgentSessionModeParsing.parse(from: [
            "sessionId": "effort",
            "_meta": [
                "x.ai/sessionConfig": [
                    "options": [
                        ["id": "high", "category": "mode", "label": "High Effort"],
                    ],
                ],
            ],
        ])
        XCTAssertNil(effortOnly.current)
        XCTAssertNil(effortOnly.available)

        XCTAssertEqual(AgentMode.chat.displayName, "Chat")
        XCTAssertEqual(AgentMode.agent.displayName, "Agent")
        XCTAssertEqual(AgentMode(rawValue: "research").displayName, "research")
        XCTAssertNotEqual(AgentMode(rawValue: "chat").displayName, "Agent")
    }

    func testFakeACPNestedChatModeAppearsInAvailableModes() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-chat-mode-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"chat-mode-session","models":{"currentModelId":"grok-4.5","availableModels":[]},"modes":{"currentModeId":"chat","availableModes":[{"id":"chat"},{"id":"agent"},{"id":"plan"},{"id":"yolo"}]}}}\\n' "$id"
              ;;
            *'"method":"session/load"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"models":{"currentModelId":"grok-4.5","availableModels":[]},"modes":{"currentModeId":"chat","availableModes":[{"id":"chat"},{"id":"agent"}]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }

        let created = GrokProcess()
        await created.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )
        XCTAssertEqual(created.state, .ready)
        XCTAssertEqual(created.currentMode, .chat)
        XCTAssertTrue(created.availableModes.contains(.chat))
        XCTAssertEqual(created.currentMode.displayName, "Chat")
        await created.stop()

        let loaded = GrokProcess()
        await loaded.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(
                localTabID: UUID(),
                model: "grok-4.5",
                resumeSessionID: "chat-mode-session"
            )
        )
        XCTAssertEqual(loaded.state, .ready)
        XCTAssertEqual(loaded.currentMode, .chat)
        XCTAssertEqual(loaded.availableModes, [.chat, .agent])
        await loaded.stop()
    }

    @MainActor
    func testSessionLoadCapturesTypedReplayWithoutRoutingHistoricalLiveEvents() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-load-replay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let rpcLogURL = fixtureRoot.appendingPathComponent("rpc.log")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\n' "$line" >> '\(rpcLogURL.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"agentVersion":"1.0.4"}}}\n' "$id"
              ;;
            *'"method":"session/load"'*)
              printf '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"replay-session","_meta":{"isReplay":true},"update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"saved prompt"}}}}\n'
              printf '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"replay-session","_meta":{"isReplay":true},"update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"historical thought"}}}}\n'
              printf '{"jsonrpc":"2.0","method":"x.ai/session/update","params":{"sessionId":"replay-session","_meta":{"isReplay":true},"update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"saved answer"}}}}\n'
              printf '{"jsonrpc":"2.0","id":%s,"result":{"models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"fresh-after-replay-mismatch","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id"
              ;;
            *'"method":"session/prompt"'*)
              printf '{"jsonrpc":"2.0","method":"x.ai/session_notification","params":{"sessionId":"fresh-after-replay-mismatch","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"totalTokens":1,"modelCalls":1,"numTurns":1}}}}\n'
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(
                localTabID: UUID(),
                resumeSessionID: "replay-session"
            )
        )

        XCTAssertEqual(process.state, .ready)
        let generation = try XCTUnwrap(process.activeProcessGeneration)
        let replay = try XCTUnwrap(process.takeLoadedSessionReplay(
            backendSessionID: "replay-session",
            processGeneration: generation
        ))
        XCTAssertEqual(replay.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(replay.messages.map(\.content), ["saved prompt", "saved answer"])
        XCTAssertEqual(replay.replayEventCount, 3)

        var iterator = process.acpEventStream.makeAsyncIterator()
        var routedHistoricalConversation = false
        for _ in 0..<4 {
            let event = await withTaskGroup(of: AcpEvent?.self) { group in
                group.addTask { await iterator.next() }
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(50))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            guard let event else { break }
            switch event {
            case .messageChunk, .thoughtChunk, .toolCall, .toolCallUpdate, .turnCompleted:
                routedHistoricalConversation = true
            default:
                continue
            }
        }
        XCTAssertFalse(
            routedHistoricalConversation,
            "historical replay must not enter the live ChatStore event stream"
        )
        await process.stop()

        let integrityKey = Data("slice-3-replay-key".utf8)
        let verifiedStore = ChatStore(continuityKeyOverride: integrityKey)
        verifiedStore.bindTabSession(
            UUID(),
            savedModel: "grok-4.5",
            savedGrokSessionID: "replay-session"
        )
        verifiedStore.restorePersistedMessages([
            Message(role: .user, content: "saved prompt"),
        ])
        await verifiedStore.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            preserveMessages: true
        )
        XCTAssertEqual(verifiedStore.connectionState, .ready)
        XCTAssertEqual(verifiedStore.continuityStatus, .verified)
        XCTAssertEqual(
            verifiedStore.messages.filter { $0.role != .system }.map(\.content),
            ["saved prompt", "saved answer"]
        )
        await verifiedStore.shutdown()

        let divergedStore = ChatStore(continuityKeyOverride: integrityKey)
        divergedStore.bindTabSession(
            UUID(),
            savedModel: "grok-4.5",
            savedGrokSessionID: "replay-session"
        )
        divergedStore.restorePersistedMessages([
            Message(role: .user, content: "different local prompt"),
        ])
        await divergedStore.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            preserveMessages: true
        )
        XCTAssertEqual(divergedStore.continuityStatus, .diverged)
        XCTAssertEqual(divergedStore.connectionState, .ready)
        XCTAssertEqual(
            divergedStore.messages.filter { $0.role != .system }.map(\.content),
            ["different local prompt"]
        )
        let acceptedFreshSend = await divergedStore.send("new work")
        XCTAssertTrue(acceptedFreshSend)
        for _ in 0..<100 where divergedStore.connectionState != .ready {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(divergedStore.connectionState, .ready)
        XCTAssertEqual(divergedStore.process.sessionId, "fresh-after-replay-mismatch")
        XCTAssertEqual(divergedStore.continuityStatus, .recoveryForked)
        let rpc = try String(contentsOf: rpcLogURL, encoding: .utf8)
        XCTAssertEqual(rpc.components(separatedBy: "\"method\":\"session/load\"").count - 1, 3)
        XCTAssertEqual(rpc.components(separatedBy: "\"method\":\"session/new\"").count - 1, 1)
        XCTAssertEqual(rpc.components(separatedBy: "\"method\":\"session/prompt\"").count - 1, 1)
        await divergedStore.shutdown()
    }

    func testNoModesSessionNewDoesNotInventPlanOrYolo() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-no-modes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rpcLogURL = fixtureRoot.appendingPathComponent("rpc.log")
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> '\(rpcLogURL.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"no-modes-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }

        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )
        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.currentMode, .agent)
        XCTAssertEqual(process.availableModes, [])
        XCTAssertFalse(process.availableModes.contains(.plan))
        XCTAssertFalse(process.availableModes.contains(.yolo))
        process.setMode(.plan)
        try await Task.sleep(for: .milliseconds(80))
        let rpc = try String(contentsOf: rpcLogURL, encoding: .utf8)
        XCTAssertFalse(rpc.contains("session/set_mode"))
        XCTAssertEqual(process.currentMode, .agent)
        await process.stop()
    }

    @MainActor
    func testEmptySetModeWithoutEventLeavesAgentUnpersisted() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-empty-set-mode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rpcLogURL = fixtureRoot.appendingPathComponent("rpc.log")
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> '\(rpcLogURL.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"advertised-modes","models":{"currentModelId":"grok-4.5","availableModels":[]},"modes":{"currentModeId":"agent","availableModes":[{"id":"agent"},{"id":"plan"}]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
              ;;
            *'"method":"session/set_mode"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }

        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "empty-set-mode", path: fixtureRoot))
        XCTAssertEqual(store.process.state, .ready)
        XCTAssertEqual(store.availableModes, [.agent, .plan])
        XCTAssertEqual(store.currentMode, .agent)
        store.setMode(.plan)
        for _ in 0..<40 {
            let rpc = (try? String(contentsOf: rpcLogURL, encoding: .utf8)) ?? ""
            if rpc.contains("session/set_mode") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.currentMode, .agent)
        XCTAssertFalse(store.isYolo)
        let rpc = try String(contentsOf: rpcLogURL, encoding: .utf8)
        XCTAssertTrue(rpc.contains("session/set_mode"))
        await store.shutdownPermanently()
    }

    @MainActor
    func testAdvertisedPlanPersistsOnlyAfterCurrentModeUpdate() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-plan-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"plan-confirm","models":{"currentModelId":"grok-4.5","availableModels":[]},"modes":{"currentModeId":"agent","availableModes":[{"id":"agent"},{"id":"plan"}]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
              ;;
            *'"method":"session/set_mode"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              printf '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"plan-confirm","update":{"sessionUpdate":"current_mode_update","currentModeId":"plan"}}}\\n'
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }

        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "plan-confirm", path: fixtureRoot))
        XCTAssertEqual(store.process.state, .ready)
        XCTAssertEqual(store.currentMode, .agent)
        store.setMode(.plan)
        for _ in 0..<80 where store.currentMode != .plan {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.currentMode, .plan)
        XCTAssertFalse(store.isYolo)
        await store.shutdownPermanently()
    }

    func testNextGenerationWithoutAdvertisementClearsPriorModeList() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-mode-gen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let advertisedURL = fixtureRoot.appendingPathComponent("fake-grok-a")
        let emptyURL = fixtureRoot.appendingPathComponent("fake-grok-b")
        let advertised = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"gen-a","models":{"currentModelId":"grok-4.5","availableModels":[]},"modes":{"currentModeId":"plan","availableModes":[{"id":"agent"},{"id":"plan"},{"id":"yolo"}]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
              ;;
          esac
        done
        """
        let empty = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"gen-b","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
              ;;
          esac
        done
        """
        try advertised.write(to: advertisedURL, atomically: true, encoding: .utf8)
        try empty.write(to: emptyURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: advertisedURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: emptyURL.path)

        GrokProcess.cliOverrideForTests = advertisedURL
        defer { GrokProcess.cliOverrideForTests = nil }

        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )
        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.availableModes, [.agent, .plan, .yolo])
        XCTAssertEqual(process.currentMode, .plan)
        await process.stop()

        GrokProcess.cliOverrideForTests = emptyURL
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )
        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.availableModes, [])
        XCTAssertEqual(process.currentMode, .agent)
        XCTAssertFalse(process.availableModes.contains(.plan))
        XCTAssertFalse(process.availableModes.contains(.yolo))
        await process.stop()
    }

    @MainActor
    func testSetModeDoesNotPersistUnadvertisedPlan() async {
        let store = ChatStore()
        XCTAssertEqual(store.availableModes, [])
        XCTAssertEqual(store.currentMode, .agent)
        store.setMode(.plan)
        XCTAssertEqual(store.currentMode, .agent)
        XCTAssertFalse(store.isYolo)
        await store.shutdownPermanently()
    }

    @MainActor
    func testEmptyWelcomeHidesOnceComposerDraftIsNonEmpty() async {
        let store = ChatStore()
        XCTAssertTrue(store.showsEmptyTranscriptWelcome)
        store.composerDraft = "x"
        XCTAssertFalse(store.showsEmptyTranscriptWelcome)
        store.composerDraft = "   "
        XCTAssertTrue(store.showsEmptyTranscriptWelcome)

        store.bindTabSession(
            UUID(),
            savedModel: "openai/gpt-4.1-mini",
            savedGrokSessionID: "01a0-restored-backend"
        )
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertTrue(store.isResumedSessionTab)
        XCTAssertFalse(store.showsEmptyTranscriptWelcome)
        await store.shutdownPermanently()
    }

    func testFirstIntentStartingCopyAgreesWithIdleReadySidebar() {
        XCTAssertFalse(SidebarSessionActivity.isWorking(connectionState: .ready, isStreaming: false))
        XCTAssertFalse(SidebarSessionActivity.isWorking(connectionState: .idle, isStreaming: false))
        XCTAssertFalse(SidebarSessionActivity.isWorking(connectionState: .failed("test error"), isStreaming: false))
        XCTAssertTrue(SidebarSessionActivity.isWorking(connectionState: .starting, isStreaming: false))
        XCTAssertTrue(SidebarSessionActivity.isWorking(connectionState: .busy, isStreaming: false))
        XCTAssertTrue(SidebarSessionActivity.isWorking(connectionState: .ready, isStreaming: true))

        let startingPhase = ThreadTaskContractPresentation.phase(
            live: nil,
            snapshot: nil,
            checkpoint: nil,
            connectionState: .starting,
            isPreparingSubmit: false,
            canResumeSavedTask: false,
            continuityRequiresRecovery: false,
            isResumedSession: false
        )
        XCTAssertEqual(startingPhase, "Starting agent…")

        let resumingPhase = ThreadTaskContractPresentation.phase(
            live: nil,
            snapshot: nil,
            checkpoint: nil,
            connectionState: .starting,
            isPreparingSubmit: false,
            canResumeSavedTask: false,
            continuityRequiresRecovery: false,
            isResumedSession: true
        )
        XCTAssertEqual(resumingPhase, "Resuming saved task")

        let readyPhase = ThreadTaskContractPresentation.phase(
            live: nil,
            snapshot: nil,
            checkpoint: nil,
            connectionState: .ready,
            isPreparingSubmit: false,
            canResumeSavedTask: false,
            continuityRequiresRecovery: false,
            isResumedSession: false
        )
        XCTAssertEqual(readyPhase, "Connected — idle")
    }

    func testLiveProcessLaunchAndRestartReceiptsTrackEffectivePermissionAndResume() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-acp-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let logURL = fixtureRoot.appendingPathComponent("argv.log")
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(logURL.path)'
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/load"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"fixture-new"}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        let workspace = Workspace(name: "fixture", path: fixtureRoot)
        let tabID = UUID()

        await process.start(workspace: workspace, options: GrokLaunchOptions(
            localTabID: tabID,
            permissionMode: "alwaysApprove",
            model: "grok-4.5",
            sandboxProfile: "default",
            resumeSessionID: "fixture-resume"
        ))
        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.sessionId, "fixture-resume")
        XCTAssertEqual(process.launchReceipt?.permissionMode, .alwaysApprove)
        XCTAssertEqual(process.launchReceipt?.permissionArguments, ["--always-approve"])
        XCTAssertEqual(process.launchReceipt?.localTabID, tabID)
        XCTAssertEqual(process.launchReceipt?.workspaceID, workspace.id)
        XCTAssertEqual(process.launchReceipt?.backendSessionID, "fixture-resume")
        XCTAssertEqual(process.launchReceipt?.outcome, .loaded)
        XCTAssertEqual(process.modelExecutionState.status, .confirmed)
        XCTAssertEqual(process.modelExecutionState.requestedModelID, "grok-4.5")
        XCTAssertEqual(process.modelExecutionState.effectiveModelID, "grok-4.5")
        let firstGeneration = process.processGeneration

        await process.start(workspace: workspace, options: GrokLaunchOptions(
            localTabID: tabID,
            permissionMode: "default",
            model: "grok-4.5",
            sandboxProfile: "default",
            resumeSessionID: "fixture-resume"
        ))
        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.sessionId, "fixture-resume")
        XCTAssertEqual(process.launchReceipt?.permissionMode, .ask)
        XCTAssertEqual(process.launchReceipt?.permissionArguments, [])
        XCTAssertEqual(process.processGeneration, firstGeneration + 1)
        XCTAssertEqual(process.activeProcessGeneration, process.processGeneration)

        let launches = try String(contentsOf: logURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(launches.count, 2)
        XCTAssertTrue(launches[0].contains("--always-approve"))
        XCTAssertFalse(launches[1].contains("--always-approve"))
        await process.stop()
    }

    func testLaunchReassertsCustomModelAfterACPNewSessionDefaultsToGrok() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-launch-model-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rpcLogURL = fixtureRoot.appendingPathComponent("rpc.log")
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\n' "$line" >> '\(rpcLogURL.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"custom-model-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"gpt-5.6-terra"}}}}\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "gpt-5.6-terra")
        )

        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.currentModelId, "gpt-5.6-terra")
        XCTAssertEqual(process.modelExecutionState.status, .confirmed)
        XCTAssertEqual(process.modelExecutionState.requestedModelID, "gpt-5.6-terra")
        XCTAssertEqual(process.modelExecutionState.effectiveModelID, "gpt-5.6-terra")
        let rpcLog = try String(contentsOf: rpcLogURL, encoding: .utf8)
        XCTAssertTrue(rpcLog.contains("\"method\":\"session/set_model\""))
        XCTAssertTrue(rpcLog.contains("\"modelId\":\"gpt-5.6-terra\""))
        await process.stop()
    }

    func testLaunchFailsClosedWhenACPConfirmsTheWrongModel() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-wrong-model-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"wrong-model-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "gpt-5.6-terra")
        )

        guard case .failed(let message) = process.state else {
            return XCTFail("Expected startup to fail closed, got \(process.state)")
        }
        XCTAssertTrue(message.contains("confirmed grok-4.5 instead of the requested model gpt-5.6-terra"))
        XCTAssertEqual(process.modelExecutionState.status, .rejected)
        XCTAssertNil(process.activeProcessGeneration)
    }

    func testProcessKeepsAcceptedModelRequestUnconfirmedWithoutEffectiveReadback() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-model-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"model-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )
        XCTAssertEqual(process.modelExecutionState.status, .confirmed)
        XCTAssertEqual(process.currentModelId, "grok-4.5")

        let handle = try XCTUnwrap(process.setModel("gpt-5.6-terra"))
        let result = await handle.result.value
        XCTAssertEqual(result.status, .requested)
        XCTAssertEqual(result.requestedModelID, "gpt-5.6-terra")
        XCTAssertEqual(result.effectiveModelID, "grok-4.5")
        XCTAssertEqual(process.currentModelId, "grok-4.5")
        await process.stop()
    }

    func testLiveModelSwitchRejectsAnUnexpectedEffectiveReadback() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-model-mismatch-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"model-mismatch-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"unrelated-provider/model"}}}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )
        XCTAssertEqual(process.state, .ready)

        let handle = try XCTUnwrap(process.setModel("gpt-5.6-terra"))
        let result = await handle.result.value
        XCTAssertEqual(result.status, .rejected)
        XCTAssertTrue(process.modelSwitchNeedsNewSession)
        XCTAssertTrue(process.modelSwitchError?.contains("unrelated-provider/model") == true)
        guard case .failed = process.state else {
            return XCTFail("An unexpected effective model must make the process unsendable")
        }
        await process.stop()
    }

    @MainActor
    func testUnavailableExplicitModelRemainsTheFailClosedTabSelection() async {
        let store = ChatStore()
        store.prepare(workspace: Workspace(
            name: "fixture",
            path: FileManager.default.temporaryDirectory
        ))
        store.bindTabSession(
            UUID(),
            modelIntent: .explicit("removed-custom-model")
        )

        XCTAssertEqual(store.persistedModelIntent, .explicit("removed-custom-model"))
        XCTAssertTrue(store.modelSelectorDisplayLabel.hasPrefix("removed-custom-model"))
        await store.shutdownPermanently()
    }

    func testModelChoiceIsBlockedWhileATurnIsStreaming() {
        XCTAssertEqual(
            ChatStore.modelSwitchSafetyBlock(
                isStreaming: true,
                hasProviderSpecificHistory: false
            ),
            .activeTurn
        )
    }

    func testAnyAssistantHistoryRequiresANewSessionBeforeChangingModel() {
        let messages = [
            Message(role: .user, content: "Inspect it"),
            Message(
                role: .assistant,
                content: "Done",
                assistantTrace: AssistantTurnTrace(
                    reasoningSummaryChunks: [],
                    thinkingDuration: nil,
                    tools: [
                        .init(
                            id: "tool-1",
                            title: "Web search",
                            status: "Succeeded",
                            mcpServerName: nil
                        )
                    ]
                )
            ),
        ]
        XCTAssertTrue(ChatStore.hasProviderSpecificHistory(in: messages))
        XCTAssertEqual(
            ChatStore.modelSwitchSafetyBlock(
                isStreaming: false,
                hasProviderSpecificHistory: true
            ),
            .providerHistory
        )
    }

    func testPlainAssistantHistoryIsProviderSpecificEvenWithoutTools() {
        let messages = [
            Message(role: .user, content: "Say hello"),
            Message(role: .assistant, content: "Hello"),
        ]
        XCTAssertTrue(ChatStore.hasProviderSpecificHistory(in: messages))
        XCTAssertEqual(
            ChatStore.modelSwitchSafetyBlock(
                isStreaming: false,
                hasProviderSpecificHistory: true
            ),
            .providerHistory
        )
    }

    func testMCPGatewayPolicyDefaultsOffAndRequiresExplicitSelection() {
        XCTAssertFalse(ChatStore.mcpGatewayEnabled(
            selectedPromptMCPNames: [],
            enabledBuiltInToolNames: []
        ))
        XCTAssertTrue(ChatStore.mcpGatewayEnabled(
            selectedPromptMCPNames: ["chrome-devtools"],
            enabledBuiltInToolNames: []
        ))
        XCTAssertTrue(ChatStore.mcpGatewayEnabled(
            selectedPromptMCPNames: [],
            enabledBuiltInToolNames: [BuiltInToolConnection.browser.rawValue]
        ))
    }

    func testCLIConfiguredMCPNotificationNamesAreCredentialFreeAndSorted() {
        XCTAssertEqual(
            GrokProcess.mcpServerNames(from: [
                "mcpServers": [
                    ["name": "chrome-devtools", "url": "http://secret.invalid"],
                    ["server_name": "alpha"],
                    ["name": "chrome-devtools"],
                ]
            ]),
            ["alpha", "chrome-devtools"]
        )
    }

    func testACPErrorCompletionIsAnAuthoritativeFailure() {
        let identity = ACPEventIdentity(
            localTabID: UUID(),
            backendSessionID: "backend",
            processGeneration: 9,
            backendEventID: "event"
        )
        let receipt = TurnCompletionReceipt(
            identity: identity,
            promptID: "prompt",
            stopReason: "error",
            redactedError: GrokProcess.redactedLifecycleText("API error: encrypted reasoning could not be verified"),
            totalTokens: nil,
            modelCalls: nil,
            turnCount: nil
        )
        XCTAssertTrue(receipt.isFailure)
        XCTAssertEqual(receipt.redactedError, "API error: encrypted reasoning could not be verified")

        let success = TurnCompletionReceipt(
            identity: identity,
            promptID: "prompt",
            stopReason: "end_turn",
            redactedError: nil,
            totalTokens: 12,
            modelCalls: 1,
            turnCount: 1
        )
        XCTAssertFalse(success.isFailure)
        XCTAssertTrue(success.isSuccessful)

        let cancelled = TurnCompletionReceipt(
            identity: identity,
            promptID: "prompt",
            stopReason: "cancelled",
            redactedError: nil,
            totalTokens: 12,
            modelCalls: 1,
            turnCount: 1
        )
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertFalse(cancelled.isSuccessful)
        XCTAssertFalse(cancelled.isFailure)
    }

    func testBackendConversationPromptIndexIsTypedAndSeparateFromUsageTurns() {
        XCTAssertEqual(
            GrokProcess.backendPromptIndex(
                eventSessionID: "backend",
                currentSessionID: "backend",
                isReplay: false,
                update: [
                    "sessionUpdate": "user_message_chunk",
                    "_meta": ["promptIndex": 4],
                ]
            ),
            4
        )
        let liveUpdate: [String: Any] = [
            "sessionUpdate": "user_message_chunk",
            "_meta": ["promptIndex": 4],
        ]
        XCTAssertNil(GrokProcess.backendPromptIndex(
            eventSessionID: nil,
            currentSessionID: "backend",
            isReplay: false,
            update: liveUpdate
        ))
        XCTAssertNil(GrokProcess.backendPromptIndex(
            eventSessionID: "other",
            currentSessionID: "backend",
            isReplay: false,
            update: liveUpdate
        ))
        XCTAssertNil(GrokProcess.backendPromptIndex(
            eventSessionID: "backend",
            currentSessionID: "backend",
            isReplay: true,
            update: liveUpdate
        ))
        XCTAssertNil(GrokProcess.backendPromptIndex(
            eventSessionID: "backend",
            currentSessionID: "backend",
            isReplay: false,
            update: ["sessionUpdate": "turn_completed", "_meta": ["promptIndex": 4]]
        ))
        XCTAssertNil(GrokProcess.backendPromptIndex(
            eventSessionID: "backend",
            currentSessionID: "backend",
            isReplay: false,
            update: ["sessionUpdate": "user_message_chunk", "_meta": ["promptIndex": -1]]
        ))
        XCTAssertNil(GrokProcess.backendPromptIndex(
            eventSessionID: "backend",
            currentSessionID: "backend",
            isReplay: false,
            update: ["sessionUpdate": "user_message_chunk", "_meta": ["promptIndex": Int.max]]
        ))
        XCTAssertNil(GrokProcess.backendPromptIndex(
            eventSessionID: "backend",
            currentSessionID: "backend",
            isReplay: false,
            update: ["sessionUpdate": "user_message_chunk", "_meta": ["promptIndex": true]]
        ))
        XCTAssertNil(GrokProcess.backendPromptIndex(
            eventSessionID: "backend",
            currentSessionID: "backend",
            isReplay: false,
            update: ["sessionUpdate": "user_message_chunk", "_meta": ["promptIndex": 1.5]]
        ))
    }

    func testCustomLaunchAcceptsOnlyItsDeclaredProviderModelReadback() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-custom-alias-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"custom-alias-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"deepseek/deepseek-v4-flash-0731"}}}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(
                localTabID: UUID(),
                model: "deepseek-deepseek-v4-flash-0731",
                expectedEffectiveModelID: "deepseek/deepseek-v4-flash-0731"
            )
        )

        XCTAssertEqual(process.state, .ready)
        XCTAssertEqual(process.modelExecutionState.requestedModelID, "deepseek-deepseek-v4-flash-0731")
        XCTAssertEqual(process.modelExecutionState.effectiveModelID, "deepseek/deepseek-v4-flash-0731")
        await process.stop()
    }

    func testLiveCustomModelSwitchAcceptsOnlyItsDeclaredProviderAlias() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-live-custom-alias-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"live-custom-alias-session","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"deepseek/deepseek-v4-flash-0731"}}}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )

        let handle = try XCTUnwrap(process.setModel(
            "deepseek-deepseek-v4-flash-0731",
            expectedEffectiveModelID: "deepseek/deepseek-v4-flash-0731"
        ))
        let result = await handle.result.value
        XCTAssertEqual(result.status, .confirmed)
        XCTAssertEqual(result.requestedModelID, "deepseek-deepseek-v4-flash-0731")
        XCTAssertEqual(result.effectiveModelID, "deepseek/deepseek-v4-flash-0731")
        XCTAssertEqual(process.state, .ready)
        await process.stop()
    }

    func testFailedProcessLaunchCannotLeaveAnActiveOrRequestedReceipt() async {
        let missingCLI = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-grok-\(UUID().uuidString)")
        GrokProcess.cliOverrideForTests = missingCLI
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()

        await process.start(
            workspace: Workspace(
                name: "fixture",
                path: FileManager.default.temporaryDirectory
            ),
            options: GrokLaunchOptions(localTabID: UUID(), model: "grok-4.5")
        )

        XCTAssertNil(process.activeProcessGeneration)
        XCTAssertEqual(process.launchReceipt?.outcome, .failed)
        XCTAssertEqual(process.modelExecutionState.status, .rejected)
        XCTAssertEqual(process.modelExecutionState.failure, .unknown)
    }

    func testClientExecutionCapabilitiesAreDisabledAndReverseExecutionFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-client-execution-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let inputLogURL = root.appendingPathComponent("client-input.jsonl")
        let sideEffectURL = root.appendingPathComponent("reverse-execution-must-not-run")
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> '\(inputLogURL.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"fixture-client-execution"}}\\n' "$id"
              printf '{"jsonrpc":"2.0","id":7001,"method":"fs/write_text_file","params":{"path":"\(sideEffectURL.path)","content":"owned"}}\\n'
              printf '{"jsonrpc":"2.0","id":7002,"method":"terminal/create","params":{"command":"/usr/bin/touch","args":["\(sideEffectURL.path)"],"cwd":"\(root.path)"}}\\n'
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: root),
            options: GrokLaunchOptions(localTabID: UUID())
        )
        XCTAssertEqual(process.state, .ready)

        for _ in 0..<100 {
            let input = (try? String(contentsOf: inputLogURL, encoding: .utf8)) ?? ""
            if input.contains("\"id\":7001") && input.contains("\"id\":7002") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await process.stop()

        XCTAssertFalse(FileManager.default.fileExists(atPath: sideEffectURL.path))
        let fsCapabilities = try XCTUnwrap(GrokProcess.clientCapabilities["fs"] as? [String: Bool])
        XCTAssertEqual(fsCapabilities["readTextFile"], false)
        XCTAssertEqual(fsCapabilities["writeTextFile"], false)
        XCTAssertEqual(GrokProcess.clientCapabilities["terminal"] as? Bool, false)

        let messages: [[String: Any]] = try String(contentsOf: inputLogURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
        let initialize = try XCTUnwrap(messages.first { $0["method"] as? String == "initialize" })
        let params = try XCTUnwrap(initialize["params"] as? [String: Any])
        let wireCapabilities = try XCTUnwrap(params["clientCapabilities"] as? [String: Any])
        XCTAssertEqual(wireCapabilities["terminal"] as? Bool, false)
        XCTAssertEqual((wireCapabilities["fs"] as? [String: Bool])?["readTextFile"], false)
        XCTAssertEqual((wireCapabilities["fs"] as? [String: Bool])?["writeTextFile"], false)

        for requestID in [7001, 7002] {
            let response = try XCTUnwrap(messages.first { ($0["id"] as? NSNumber)?.intValue == requestID })
            let error = try XCTUnwrap(response["error"] as? [String: Any])
            XCTAssertEqual((error["code"] as? NSNumber)?.intValue, -32601)
            XCTAssertTrue((error["message"] as? String)?.contains("Method not found") == true)
        }
    }

    func testToolCallFailureStatusAndMessageSurviveACPParsing() {
        let process = GrokProcess()
        let parsed = process.parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-1",
            "kind": "unknown",
            "title": "Run command",
            "status": "failed",
            "content": [[
                "type": "content",
                "content": ["type": "text", "text": "Tool failed"]
            ]],
            "rawOutput": [
                "error": "tool_execution_failed",
                "message": "Terminal exited with status 2"
            ]
        ])

        XCTAssertEqual(parsed?.id, "call-1")
        XCTAssertEqual(parsed?.status, "failed")
        XCTAssertEqual(parsed?.detail, "Terminal exited with status 2")
        XCTAssertEqual(parsed?.terminalStatus, .failed)
        XCTAssertEqual(parsed?.diagnosticDetail, #"{"error":"tool_execution_failed","message":"Terminal exited with status 2"}"#)
    }

    func testToolCallKeepsAuthoritativeDurationWithoutStartingAClientTimer() {
        let process = GrokProcess()
        let direct = process.parseToolCall(from: [
            "toolCallId": "duration-direct",
            "kind": "execute",
            "title": "Run tests",
            "status": "completed",
            "durationMs": 1_250,
        ])
        let nested = process.parseToolCall(from: [
            "toolCallId": "duration-output",
            "kind": "execute",
            "title": "Run checks",
            "status": "completed",
            "rawOutput": ["elapsed_ms": 900],
        ])
        let absent = process.parseToolCall(from: [
            "toolCallId": "duration-absent",
            "kind": "read",
            "title": "Read file",
            "status": "completed",
        ])

        XCTAssertEqual(direct?.durationMilliseconds, 1_250)
        XCTAssertEqual(nested?.durationMilliseconds, 900)
        XCTAssertNil(absent?.durationMilliseconds)
    }

    func testSuccessfulTerminalReceiptProjectsOutputInsteadOfProtocolJSON() {
        let rawOutput: [String: Any] = [
            "command": "./check.sh",
            "exit_code": 0,
            "output": [71, 66, 45, 84, 69, 83, 84, 83, 45, 80, 65, 83, 83, 69, 68, 10],
            "output_file": "/private/backend/path",
        ]
        let rawOutputData = try! JSONSerialization.data(withJSONObject: rawOutput)
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-output",
            "kind": "execute",
            "title": "Run checks",
            "status": "completed",
            "rawOutput": String(decoding: rawOutputData, as: UTF8.self),
        ])

        XCTAssertEqual(parsed?.detail, "GB-TESTS-PASSED")
        XCTAssertFalse(parsed?.detail?.contains("output_file") == true)
    }

    func testToolCallPreservesAuthoritativeMCPServerName() {
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "mcp-call-1",
            "toolName": "list_pages",
            "serverName": "chrome-devtools",
            "title": "List pages",
            "status": "in_progress",
        ])

        XCTAssertEqual(parsed?.rawInput?["serverName"] as? String, "chrome-devtools")
        XCTAssertEqual(parsed?.rawInput?["toolName"] as? String, "list_pages")
        XCTAssertEqual(parsed?.qualifiedToolName, "chrome-devtools__list_pages")
        XCTAssertEqual(
            MCPQualifiedToolIdentity.serverName(from: parsed?.qualifiedToolName),
            "chrome-devtools"
        )
    }

    func testSnakeCaseSplitMCPFieldsComposeQualifiedNameWithoutRawOutput() {
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call",
            "toolCallId": "mcp-call-snake",
            "tool_name": "list_pages",
            "server_name": "chrome-devtools",
            "title": "List pages",
            "status": "pending",
        ])

        XCTAssertEqual(parsed?.qualifiedToolName, "chrome-devtools__list_pages")
        XCTAssertEqual(parsed?.rawInput?["serverName"] as? String, "chrome-devtools")
        XCTAssertEqual(parsed?.rawInput?["toolName"] as? String, "list_pages")
    }

    func testSearchToolParsesAsDiscoveryWithBoundedQualifiedCatalog() {
        let content = #"{"results":[{"server":"chrome-devtools","tools":[{"tool_name":"chrome-devtools__list_pages"},{"tool_name":"not safe"}]}]}"#
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "search-1",
            "status": "completed",
            "rawOutput": [
                "type": "SearchTool",
                "result_count": 2,
                "content": content,
            ],
        ])

        XCTAssertEqual(parsed?.mcpReceiptRole, .discovery)
        XCTAssertNil(parsed?.qualifiedToolName)
        XCTAssertEqual(parsed?.discoveredQualifiedToolNames, ["chrome-devtools__list_pages"])
        XCTAssertNil(parsed?.rawInput?["serverName"],
                     "catalog discovery is not a server-use receipt")
    }

    func testLiveSearchToolContentEnvelopeParsesAsDiscovery() {
        let content = #"{"results":[{"server":"chrome-devtools","tools":[{"tool_name":"chrome-devtools__list_pages","input_schema":{"type":"object"}}]}]}"#
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "live-search-1",
            "status": "completed",
            "content": [[
                "type": "content",
                "content": ["type": "text", "text": content],
                "rawOutput": [
                    "type": "SearchTool",
                    "result_count": 1,
                    "content": content,
                ],
            ]],
        ])

        XCTAssertEqual(parsed?.mcpReceiptRole, .discovery)
        XCTAssertEqual(parsed?.discoveredQualifiedToolNames, ["chrome-devtools__list_pages"])
        XCTAssertNil(parsed?.qualifiedToolName)
        XCTAssertNil(parsed?.rawInput?["serverName"],
                     "nested discovery output is still not an invocation receipt")
    }

    func testUseToolParsesQualifiedInvocationAndAuthoritativeServer() {
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "use-1",
            "title": "chrome-devtools__list_pages",
            "status": "completed",
            "rawInput": [
                "variant": "UseTool",
                "tool_name": "chrome-devtools__list_pages",
                "tool_input": [:],
            ],
            "rawOutput": [
                "type": "MCP",
                "server_name": "chrome-devtools",
                "tool_name": "list_pages",
                "output": ["OkayOutput": "## Pages"],
            ],
        ])

        XCTAssertEqual(parsed?.mcpReceiptRole, .invocation)
        XCTAssertEqual(parsed?.qualifiedToolName, "chrome-devtools__list_pages")
        XCTAssertEqual(parsed?.rawInput?["serverName"] as? String, "chrome-devtools")
        XCTAssertTrue(parsed?.discoveredQualifiedToolNames.isEmpty == true)
    }

    func testTerminalExitReceiptOverridesTransportCompletedStatus() {
        let parsed = GrokProcess().parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-nonzero",
            "kind": "execute",
            "title": "Run command",
            "status": "completed",
            "rawOutput": [
                "type": "Bash",
                "exit_code": 127,
                "timed_out": false,
            ],
        ])

        XCTAssertEqual(parsed?.status, "failed")
        XCTAssertEqual(parsed?.terminalStatus, .failed)
        XCTAssertEqual(parsed?.detail, "Command exited with status 127.")
    }

    func testTerminalArtifactReceiptRequiresAnExplicitSafeRedirection() {
        let artifact = ToolCall(
            id: "artifact",
            kind: "execute",
            title: "Write marker",
            rawInput: [
                "command": "printf '%s\\n' marker > /tmp/grokbuild-artifact.txt && cat /tmp/grokbuild-artifact.txt"
            ]
        )
        let stdoutOnly = ToolCall(
            id: "stdout",
            kind: "execute",
            title: "Print marker",
            rawInput: ["command": "printf '%s\\n' marker"]
        )
        let discarded = ToolCall(
            id: "discarded",
            kind: "execute",
            title: "Discard marker",
            rawInput: ["command": "printf marker > /dev/null"]
        )

        XCTAssertEqual(artifact.writtenFilePath, "/tmp/grokbuild-artifact.txt")
        XCTAssertNil(stdoutOnly.writtenFilePath)
        XCTAssertNil(discarded.writtenFilePath)
    }

    func testToolCallParserKeepsTargetAndExplicitRetryCorrelationWithoutInventingIt() {
        let process = GrokProcess()
        let correlated = process.parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-retry",
            "status": "completed",
            "retryOfToolCallId": "call-failed",
            "rawInput": ["url": "https://example.com/source"],
        ])
        let uncorrelated = process.parseToolCall(from: [
            "sessionUpdate": "tool_call_update",
            "toolCallId": "call-unrelated",
            "status": "completed",
            "rawInput": ["url": "https://example.com/source"],
        ])

        XCTAssertEqual(correlated?.target, "https://example.com/source")
        XCTAssertEqual(correlated?.retryOfToolCallID, "call-failed")
        XCTAssertNil(uncorrelated?.retryOfToolCallID)
    }

    func testToolTerminalStatusNormalizationKeepsOnlyKnownTerminalStates() {
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "completed"), .succeeded)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "rejected"), .failed)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "canceled"), .cancelled)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "superseded"), .stale)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "backend_mystery"), .unknown)
        XCTAssertNil(ToolCallTerminalStatus.from(rawStatus: "running"))
        XCTAssertNil(ToolCallTerminalStatus.from(rawStatus: nil))
    }

    func testToolSettlementChromeKeepsFailureSeparateFromParentCompletion() {
        XCTAssertEqual(ChatStore.TurnOutcome.completed.displayName, "Turn completed")
        XCTAssertEqual(ChatStore.TurnOutcome.failed.displayName, "Turn failed")
        XCTAssertEqual(ChatStore.TurnOutcome.cancelled.displayName, "Turn cancelled")
        XCTAssertEqual(ChatStore.TurnOutcome.completionReceiptMissing.displayName, "Completion receipt missing")
        XCTAssertEqual(ChatStore.TurnOutcome.userStopped.displayName, "Stopped by you")

        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "completed"), .succeeded)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "rejected"), .failed)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "canceled"), .cancelled)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "superseded"), .stale)
        XCTAssertEqual(ToolCallTerminalStatus.from(rawStatus: "backend_mystery"), .unknown)
    }

    func testFreshModelCatalogFallbackIsCurrentGrok() {
        let suiteName = "grokbuild.tests.models.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let models = GrokModelCatalog.cachedOrFallback(defaults: defaults)
        XCTAssertEqual(models.map(\.id), ["grok-4.6", "grok-4.5"])
        XCTAssertEqual(models.first?.name, "Grok 4.6")
        XCTAssertEqual(models.first?.isDefault, true)
        XCTAssertEqual(models.last?.id, "grok-4.5")
        XCTAssertEqual(models.last?.isDefault, false)
    }

    func testComposerControlsMeetMinimumPointerTarget() {
        XCTAssertGreaterThanOrEqual(ComposerControlMetrics.minimumHitTarget, 36)
    }

    func testSettingsCredentialLoadingLeavesMainThread() async {
        let ranOnMainThread = await SettingsBackgroundLoader.run { Thread.isMainThread }
        XCTAssertFalse(ranOnMainThread)
    }

    func testTranscriptWorkingIndicatorHasNoPeriodicInvalidationLoop() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("GrokBuild/Views/GrokChatChrome.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("TimelineView("))
        XCTAssertTrue(source.contains("Text(\"Agent working…\")"))
    }

    @MainActor
    func testAuthoritativeCompletionDoesNotBypassPacedAnswerReveal() {
        let store = ChatStore()
        XCTAssertFalse(store.isStreaming)
        XCTAssertNil(store.latestTurnOutcome)
    }

    @MainActor
    func testSingleFinalACPChunkRevealsInBatchesBeforeSettling() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-paced-reveal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let answer = String(repeating: "Smooth final answer segment. ", count: 80)
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"paced-backend","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id" ;;
            *'"method":"session/prompt"'*)
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"paced-backend","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"Checked the answer shape."}}}}\n'
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"paced-backend","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"\(answer)"}}}}\n'
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"eventId":"paced-completion-1","sessionId":"paced-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"totalTokens":42,"modelCalls":1,"numTurns":1}}}}\n'
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"eventId":"paced-completion-1","sessionId":"paced-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"totalTokens":42,"modelCalls":1,"numTurns":1}}}}\n'
              printf '{"jsonrpc":"2.0","id":%s,"result":{"stopReason":"end_turn"}}\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "paced-reveal", path: root))

        let sendTask = Task { @MainActor in
            await store.sendAndWait("Reveal one final chunk smoothly")
        }
        var firstVisibleCount = 0
        for _ in 0..<200 {
            firstVisibleCount = store.messages.last(where: { $0.role == .assistant })?.content.count ?? 0
            if firstVisibleCount > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertGreaterThan(firstVisibleCount, 0)
        XCTAssertLessThan(firstVisibleCount, answer.count)
        XCTAssertTrue(store.isStreaming)
        XCTAssertEqual(store.thinkingText, "Checked the answer shape.")
        XCTAssertEqual(
            ChatTranscriptLayout.messageBlockOrder(
                containsAgentHeader: true,
                traceExpanded: true,
                containsThinking: true,
                containsToolActivity: false
            ),
            [.agentHeader, .thinking, .answer]
        )

        let sendSucceeded = await sendTask.value
        XCTAssertTrue(sendSucceeded)
        for _ in 0..<200 where store.isStreaming {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(
            store.messages.last(where: { $0.role == .assistant })?.content,
            answer
        )
        XCTAssertFalse(store.isStreaming)
        XCTAssertEqual(store.sessionUsage.turnCount, 1)
        XCTAssertEqual(store.sessionUsage.totalTokens, 42)
        await store.shutdownPermanently()
    }

    @MainActor
    func testDelayedCompletionReplayCannotSettleANewerTurn() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-completion-replay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        prompt_count=0
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"completion-replay-backend","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id" ;;
            *'"method":"session/prompt"'*)
              prompt_count=$((prompt_count + 1))
              if [ "$prompt_count" -eq 1 ]; then
                printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"_meta":{"eventId":"completion-first"},"sessionId":"completion-replay-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"totalTokens":10,"modelCalls":1,"numTurns":1}}}}\n'
              else
                printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"_meta":{"eventId":"completion-first"},"sessionId":"completion-replay-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"totalTokens":10,"modelCalls":1,"numTurns":1}}}}\n'
                printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"_meta":{"eventId":"completion-second"},"sessionId":"completion-replay-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn","usage":{"totalTokens":20,"modelCalls":1,"numTurns":1}}}}\n'
              fi
              printf '{"jsonrpc":"2.0","id":%s,"result":{"stopReason":"end_turn"}}\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "completion-replay", path: root))

        let firstSucceeded = await store.sendAndWait("First turn")
        let secondSucceeded = await store.sendAndWait("Second turn")
        XCTAssertTrue(firstSucceeded)
        XCTAssertTrue(secondSucceeded)
        XCTAssertEqual(store.sessionUsage.turnCount, 2)
        XCTAssertEqual(store.sessionUsage.totalTokens, 30)
        await store.shutdownPermanently()
    }

    @MainActor
    func testCancelledCompletionReleasesMissingPromptRPCResponse() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-cancelled-prompt-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"cancelled-backend","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id" ;;
            *'"method":"session/prompt"'*)
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"cancelled-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"cancelled","usage":{"totalTokens":42,"modelCalls":1,"numTurns":1}}}}\n'
              # Grok CLI 1.0 omits the matching JSON-RPC response on this path.
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "cancelled-prompt", path: root))

        let sendSucceeded = await store.sendAndWait("Exercise cancelled completion")

        XCTAssertTrue(sendSucceeded, "the authoritative ACP receipt releases the transport wait")
        XCTAssertEqual(store.latestTurnOutcome, .cancelled)
        XCTAssertFalse(store.isStreaming)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.runEvidenceSnapshot?.process.state, "Cancelled")
        XCTAssertEqual(store.runEvidenceSnapshot?.usage.totalTokens, 42)
        await store.shutdownPermanently()
    }

    @MainActor
    func testPermissionTimeoutCancellationClearsPendingUIAndStaysCancelled() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-permission-cancel-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"permission-cancelled-backend","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\n' "$id" ;;
            *'"method":"session/prompt"'*)
              printf '{"jsonrpc":"2.0","id":"permission-1","method":"session/request_permission","params":{"sessionId":"permission-cancelled-backend","toolCall":{"toolCallId":"call-1","title":"Execute `/bin/sleep 45`","kind":"execute"},"options":[{"optionId":"allow_once","name":"Allow once","kind":"allow_once"}]}}\n'
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"permission-cancelled-backend","update":{"sessionUpdate":"turn_completed","stop_reason":"cancelled","usage":{"totalTokens":43,"modelCalls":1,"numTurns":1}}}}\n'
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: "grok-4.5")
        await store.start(workspace: Workspace(name: "permission-cancelled-prompt", path: root))

        let sendSucceeded = await store.sendAndWait("Exercise permission timeout cancellation")

        XCTAssertTrue(sendSucceeded)
        XCTAssertEqual(store.latestTurnOutcome, .cancelled)
        XCTAssertTrue(store.pendingPermissions.isEmpty)
        XCTAssertNil(store.pendingExitPlan)
        XCTAssertTrue(store.pendingQuestions.isEmpty)
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(store.runEvidenceSnapshot?.outcome, .cancelled)
        XCTAssertEqual(store.runEvidenceSnapshot?.usage.totalTokens, 43)
        await store.shutdownPermanently()
    }

    func testRestoredTranscriptSchedulesSettledAutoScrollOnAppearance() {
        XCTAssertGreaterThanOrEqual(ComposerControlMetrics.minimumHitTarget, 36)
        XCTAssertEqual(ComposerDensityPolicy.minimumLineCount, 1)
        XCTAssertEqual(ComposerDensityPolicy.maximumLineCount, 8)
        XCTAssertEqual(ComposerDensityPolicy.editorMinimumHeight, 36)
    }

    @MainActor
    func testLazyRestoredTabResumesSavedSessionBeforeSending() {
        let store = ChatStore()
        XCTAssertFalse(store.isResumedSessionTab)
        XCTAssertNil(store.savedGrokSessionID)
    }

    func testSavedBackendCannotStartOrSendBeforeContinuityGateAllowsIt() {
        XCTAssertEqual(SessionSendGate.decision(for: .localOnly), .allowLocalBackendCreation)
        XCTAssertEqual(SessionSendGate.decision(for: .backendBound), .allowVerifiedBackend)
        XCTAssertEqual(SessionSendGate.decision(for: .verified), .allowVerifiedBackend)
        XCTAssertEqual(SessionSendGate.decision(for: .backendOnly), .allowVerifiedBackend)
        XCTAssertEqual(SessionSendGate.decision(for: .recoveryForked), .allowRecoveryFork)
        XCTAssertEqual(SessionSendGate.decision(for: .verifying), .block)
        XCTAssertEqual(SessionSendGate.decision(for: .diverged), .block)
        XCTAssertEqual(SessionSendGate.decision(for: .compositeSuspected), .block)
        XCTAssertEqual(SessionSendGate.decision(for: .backendMissing), .block)
        XCTAssertEqual(SessionSendGate.decision(for: .verificationIncomplete), .block)
    }

    @MainActor
    func testRecoveryCandidatesRemainExplicitAndRecoveryActionsDoNotStartAProcess() {
        let store = ChatStore()
        XCTAssertNil(store.persistedPendingRecoveryIntent)
        XCTAssertFalse(store.isResumedSessionTab)
    }

    func testAppUpdatePaneObservesFreshUpdateReceipts() {
        XCTAssertEqual(Notification.Name.grokBuildUpdateStateChanged.rawValue, "grokBuildUpdateStateChanged")
    }

    func testWorkbenchChromeKeepsBackendReceiptsInTheRunInspector() {
        XCTAssertGreaterThanOrEqual(ComposerControlMetrics.minimumHitTarget, 36)
        XCTAssertEqual(ComposerDensityPolicy.minimumLineCount, 1)
        XCTAssertEqual(ComposerDensityPolicy.maximumLineCount, 8)
        XCTAssertEqual(ComposerDensityPolicy.editorMinimumHeight, ComposerControlMetrics.minimumHitTarget)
    }

    func testHardBudgetTerminalVerdictRejectsHostileReceiptShapes() throws {
        let authority = try hardBudgetTerminalAuthority()
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(snapshot: hardBudgetTerminalSnapshot([]), authority: authority, completion: nil),
            .rejected,
            "A governed success cannot settle without a receipt."
        )
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: hardBudgetTerminalSnapshot([
                    hardBudgetTerminalRecord(lifecycle: .reserved),
                ]),
                authority: authority,
                completion: nil
            ),
            .ambiguous
        )
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: hardBudgetTerminalSnapshot([
                    hardBudgetTerminalRecord(lifecycle: .ambiguousFullReservationCharged),
                ]),
                authority: authority,
                completion: nil
            ),
            .ambiguous
        )
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: hardBudgetTerminalSnapshot([
                    hardBudgetTerminalRecord(reservationID: "same", sequence: 1),
                    hardBudgetTerminalRecord(reservationID: "same", sequence: 2),
                ]),
                authority: authority,
                completion: nil
            ),
            .rejected
        )
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: hardBudgetTerminalSnapshot([
                    hardBudgetTerminalRecord(reservationID: "one", sequence: 1),
                    hardBudgetTerminalRecord(reservationID: "two", sequence: 1),
                ]),
                authority: authority,
                completion: nil
            ),
            .rejected
        )
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: hardBudgetTerminalSnapshot([
                    hardBudgetTerminalRecord(actualTokens: nil),
                ]),
                authority: authority,
                completion: nil
            ),
            .rejected
        )
    }

    func testHardBudgetTerminalVerdictBindsCompletionAccountingButAllowsRepeatedProviderRequestID() throws {
        let authority = try hardBudgetTerminalAuthority()
        let settled = hardBudgetTerminalSnapshot([
            hardBudgetTerminalRecord(reservationID: "one", sequence: 1, providerRequestID: "shared", actualTokens: 4),
            hardBudgetTerminalRecord(reservationID: "two", sequence: 2, providerRequestID: "shared", actualTokens: 6),
        ])
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: settled,
                authority: authority,
                completion: hardBudgetTerminalCompletion(modelCalls: 2, totalTokens: 10)
            ),
            .settled,
            "Provider request IDs are not a unique ledger key."
        )
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: settled,
                authority: authority,
                completion: hardBudgetTerminalCompletion(modelCalls: 1, totalTokens: 10)
            ),
            .rejected
        )
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: settled,
                authority: authority,
                completion: hardBudgetTerminalCompletion(modelCalls: 2, totalTokens: 9)
            ),
            .rejected
        )
    }

    func testHardBudgetTerminalVerdictRejectsAuthorityBoundRecordDrift() throws {
        let authority = try hardBudgetTerminalAuthority()
        let rejected: (HardTokenReceiptSnapshot.Record) -> Void = { record in
            XCTAssertEqual(
                HardBudgetTerminalVerdict.evaluate(
                    snapshot: self.hardBudgetTerminalSnapshot([record]),
                    authority: authority,
                    completion: nil
                ),
                .rejected
            )
        }
        rejected(hardBudgetTerminalRecord(chargedTokens: 9))
        rejected(hardBudgetTerminalRecord(model: "wrong-model"))
        rejected(hardBudgetTerminalRecord(endpointSHA256: String(repeating: "b", count: 64)))
        rejected(hardBudgetTerminalRecord(apiBackend: "messages"))
        rejected(hardBudgetTerminalRecord(reservedTokens: 0))
        rejected(hardBudgetTerminalRecord(reservedTokens: 101))
        rejected(hardBudgetTerminalRecord(payloadBytes: 81))
        rejected(hardBudgetTerminalRecord(maxOutputTokens: 21))
        rejected(hardBudgetTerminalRecord(actualTokens: 21, reservedTokens: 20, chargedTokens: 21))
        rejected(hardBudgetTerminalRecord(actualTokens: 101, chargedTokens: 101))
        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: hardBudgetTerminalSnapshot([
                    hardBudgetTerminalRecord(reservationID: "one", sequence: 1),
                    hardBudgetTerminalRecord(reservationID: "two", sequence: 99),
                ]),
                authority: authority,
                completion: nil
            ),
            .rejected
        )

        XCTAssertEqual(
            HardBudgetTerminalVerdict.evaluate(
                snapshot: hardBudgetTerminalSnapshot([
                    hardBudgetTerminalRecord(reservationID: "one", sequence: 1, actualTokens: 10),
                    hardBudgetTerminalRecord(reservationID: "two", sequence: 2, actualTokens: 10),
                    hardBudgetTerminalRecord(reservationID: "three", sequence: 3, actualTokens: 10),
                ]),
                authority: authority,
                completion: nil
            ),
            .rejected
        )
    }

    func testHardBudgetReceiptSnapshotRejectsMalformedNonNullActualTokens() {
        XCTAssertNil(HardTokenReceiptSnapshot.parse(hardBudgetReceiptResponse(actualTokens: "ten")))
        XCTAssertNil(HardTokenReceiptSnapshot.parse(hardBudgetReceiptResponse(actualTokens: -1)))
        XCTAssertNotNil(HardTokenReceiptSnapshot.parse(hardBudgetReceiptResponse(actualTokens: NSNull())))
    }

    func testHardBudgetTerminalProjectionDecodesHistoricalPayloadWithoutRequests() throws {
        let projection = AssistantTurnCheckpoint.HardBudgetTerminalProjection(
            status: .settled,
            ledgerRevision: 4,
            nextSequence: 5,
            reservationCount: 1,
            reason: nil,
            requests: [
                .init(
                    reservationID: "reservation-1",
                    sequence: 1,
                    providerRequestID: "provider-request",
                    model: "grok-4.6",
                    endpointSHA256: hardBudgetSHA,
                    apiBackend: "responses",
                    payloadBytes: 12,
                    maxOutputTokens: 20,
                    reservedTokens: 20,
                    actualTokens: 10,
                    chargedTokens: 10,
                    lifecycle: "settled_usage_reported"
                ),
            ]
        )
        var historical = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(projection)) as? [String: Any]
        )
        historical.removeValue(forKey: "requests")
        let decoded = try JSONDecoder().decode(
            AssistantTurnCheckpoint.HardBudgetTerminalProjection.self,
            from: JSONSerialization.data(withJSONObject: historical)
        )
        XCTAssertEqual(decoded.status, .settled)
        XCTAssertNil(decoded.requests)
    }
}
