import XCTest
@testable import GrokBuild

final class ArmedV3DispatchExpectationTests: XCTestCase {
    private let provenanceSHA = String(repeating: "c", count: 64)
    private let endpointSHA = String(repeating: "a", count: 64)
    private let modelID = "deepseek-deepseek-v4-flash-0731"
    private let providerFacing = "deepseek/deepseek-v4-flash-0731"

    func testMatchingManagedProviderBindsPacketDigestAfterLiveCrossCheck() {
        let expectation = ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(),
            selectedModelID: modelID,
            customModel: matchingCustomModel(),
            provider: matchingProvider(),
            candidate: matchingCandidate()
        )
        XCTAssertEqual(expectation?.managedProviderID, "openrouter")
        XCTAssertEqual(expectation?.authScheme, "bearer")
        XCTAssertEqual(expectation?.providerFacingModel, providerFacing)
        XCTAssertEqual(expectation?.credentialAuthorizationV3.keychainAccount, "openrouter")
        XCTAssertEqual(expectation?.credentialAuthorizationV3.expectedProvenanceSHA256, provenanceSHA)
    }

    func testPacketOnlyAuthorizationIsNotSufficientWithoutMatchingLiveModel() {
        XCTAssertNil(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(),
            selectedModelID: "grok-4.6",
            customModel: CustomModel(
                id: "grok-4.6",
                model: "grok-4.6",
                baseURL: "https://api.x.ai/v1",
                apiBackend: .responses
            ),
            provider: matchingProvider(),
            candidate: matchingCandidate()
        ))
    }

    func testProviderMismatchRefuses() {
        XCTAssertNil(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(),
            selectedModelID: modelID,
            customModel: matchingCustomModel(providerID: "openai"),
            provider: Provider(
                id: "openai",
                name: "ChatGPT",
                baseURL: "https://api.openai.com/v1",
                authScheme: .bearer
            ),
            candidate: matchingCandidate()
        ))
    }

    func testAuthSchemeMismatchRefuses() {
        XCTAssertNil(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(),
            selectedModelID: modelID,
            customModel: matchingCustomModel(),
            provider: matchingProvider(authScheme: .apiKeyHeader),
            candidate: matchingCandidate()
        ))
    }

    func testProviderFacingModelMismatchRefuses() {
        XCTAssertNil(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(),
            selectedModelID: modelID,
            customModel: matchingCustomModel(model: "openrouter/auto"),
            provider: matchingProvider(),
            candidate: matchingCandidate()
        ))
    }

    func testAttachedAuthorizationDriftRefuses() {
        let drifted = GrokArmedCredentialAuthorizationV3(
            managedProviderID: "openrouter",
            authScheme: "bearer",
            expectedProvenanceSHA256: String(repeating: "d", count: 64)
        )
        XCTAssertNil(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(attachedAuthorization: drifted),
            selectedModelID: modelID,
            customModel: matchingCustomModel(),
            provider: matchingProvider(),
            candidate: matchingCandidate()
        ))
    }

    func testAPIBackendMismatchRefuses() {
        XCTAssertNil(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(),
            selectedModelID: modelID,
            customModel: CustomModel(
                id: modelID,
                model: providerFacing,
                baseURL: "https://openrouter.ai/api/v1",
                apiBackend: .responses,
                providerID: "openrouter"
            ),
            provider: matchingProvider(),
            candidate: matchingCandidate()
        ))
    }

    func testLocalEndpointWithoutOfficialHelperRefuses() {
        XCTAssertNil(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(
                providerID: "ollama",
                authScheme: "bearer",
                model: "llama3"
            ),
            selectedModelID: "local-llama",
            customModel: CustomModel(
                id: "local-llama",
                model: "llama3",
                baseURL: "http://127.0.0.1:11434/v1",
                apiBackend: .chatCompletions,
                providerID: "ollama"
            ),
            provider: Provider(
                id: "ollama",
                name: "Ollama",
                baseURL: "http://127.0.0.1:11434/v1",
                authScheme: .bearer
            ),
            candidate: matchingCandidate()
        ))
    }

    func testCLIBuildMismatchRefuses() {
        XCTAssertNil(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(),
            selectedModelID: modelID,
            customModel: matchingCustomModel(),
            provider: matchingProvider(),
            candidate: matchingCandidate(cliBuild: "1.0.5 (deadbeef)")
        ))
    }

    func testAPIKeyHeaderMapsToCanonicalV3Scheme() {
        XCTAssertEqual(ProviderAuthScheme.bearer.armedV3CanonicalScheme, "bearer")
        XCTAssertEqual(ProviderAuthScheme.apiKeyHeader.armedV3CanonicalScheme, "x_api_key")
        XCTAssertEqual(ProviderAuthScheme.bearerAndAPIKey.armedV3CanonicalScheme, "bearer_and_x_api_key")
        XCTAssertNil(ProviderAuthScheme.none.armedV3CanonicalScheme)
        XCTAssertEqual(HardBudgetProvenanceV3.canonicalAuthHeaderNames("x_api_key"), ["x-api-key"])
        XCTAssertEqual(
            HardBudgetProvenanceV3.canonicalAuthHeaderNames("bearer_and_x_api_key"),
            ["authorization", "x-api-key"]
        )
    }

    func testChatStoreBindUsesLiveSnapshotNotPacketAuthAlone() {
        let snapshot = CustomModelStore.Snapshot(
            models: [matchingCustomModel()],
            defaultModelID: modelID,
            writeSafety: .writable,
            usesOfficialProviderProjection: true,
            officiallyProjectedModelIDs: [modelID],
            unsafeFlatModelIDs: []
        )
        let bound = ArmedV3DispatchExpectation.bindAuthorization(
            authorization: authorization(),
            selectedModelID: modelID,
            customModelSnapshot: snapshot,
            providers: [matchingProvider()],
            candidate: matchingCandidate()
        )
        XCTAssertEqual(bound?.keychainAccount, "openrouter")
        XCTAssertEqual(bound?.expectedProvenanceSHA256, provenanceSHA)

        XCTAssertNil(ArmedV3DispatchExpectation.bindAuthorization(
            authorization: authorization(),
            selectedModelID: "grok-4.6",
            customModelSnapshot: snapshot,
            providers: [matchingProvider()],
            candidate: matchingCandidate()
        ))
        XCTAssertNil(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(campaignTokenCeiling: 4_000_000),
            selectedModelID: modelID,
            customModel: matchingCustomModel(),
            provider: matchingProvider(),
            candidate: matchingCandidate()
        ))
    }

    func testSpawnAdmissionRefusesModelAndMCPDrift() throws {
        let expectation = try XCTUnwrap(ArmedV3DispatchExpectation.tryMake(
            authorization: authorization(),
            selectedModelID: modelID,
            customModel: matchingCustomModel(),
            provider: matchingProvider(),
            candidate: matchingCandidate()
        ))
        XCTAssertNil(expectation.spawnAdmissionRefusal(options: GrokLaunchOptions(model: modelID)))
        XCTAssertNotNil(expectation.spawnAdmissionRefusal(options: GrokLaunchOptions(model: "grok-4.6")))
        XCTAssertNotNil(expectation.spawnAdmissionRefusal(options: GrokLaunchOptions(
            model: modelID,
            mcpGatewayEnabled: true
        )))
        XCTAssertNotNil(expectation.spawnAdmissionRefusal(options: GrokLaunchOptions(
            model: modelID,
            allowedMCPServerNames: ["grokbuild-browser"]
        )))
    }

    private func matchingCustomModel(
        model: String? = nil,
        providerID: String = "openrouter"
    ) -> CustomModel {
        CustomModel(
            id: modelID,
            model: model ?? providerFacing,
            baseURL: "https://openrouter.ai/api/v1",
            apiBackend: .chatCompletions,
            providerID: providerID
        )
    }

    private func matchingProvider(authScheme: ProviderAuthScheme = .bearer) -> Provider {
        Provider(
            id: "openrouter",
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            authScheme: authScheme
        )
    }

    private func matchingCandidate(cliBuild: String = "1.0.5 (86f0c70)") -> GrokCandidateRuntimeIdentity {
        GrokCandidateRuntimeIdentity(
            binaryPath: "/tmp/xai-grok-pager",
            provenancePath: "/tmp/candidate-provenance.json",
            provenanceSHA256: String(repeating: "b", count: 64),
            binarySHA256: String(repeating: "e", count: 64),
            binarySize: 1,
            architecture: "arm64",
            sourceSHA: String(repeating: "f", count: 40),
            cliBuild: cliBuild,
            signature: GrokCandidateSignatureReceipt(
                teamIdentifier: "DD2GCQJVB4",
                designatedRequirement: "fixture"
            )
        )
    }

    private func authorization(
        attachedAuthorization: GrokArmedCredentialAuthorizationV3? = nil,
        providerID: String = "openrouter",
        authScheme: String = "bearer",
        model: String? = nil,
        campaignTokenCeiling: Int = 20_000_000
    ) -> AcceptanceBudgetAuthorization {
        let route = AcceptanceHardBudgetRoute(
            model: model ?? providerFacing,
            endpointSHA256: endpointSHA,
            apiBackend: "chat_completions",
            requestBoundTokens: 100,
            maxPayloadBytes: 80,
            maxOutputTokens: 20,
            boundProvenanceSHA256: provenanceSHA,
            managedProviderID: providerID,
            authScheme: authScheme
        )
        let packetAuth = attachedAuthorization ?? route.credentialAuthorizationV3
        return AcceptanceBudgetAuthorization(
            runID: "schema-3",
            campaignTokenCeiling: campaignTokenCeiling,
            emergencyReserveTokens: 1_000_000,
            hardBudgetManifestSHA256: String(repeating: "a", count: 64),
            expectedCLIBuild: "1.0.5 (86f0c70)",
            budget: AcceptanceTurnBudget(
                packetID: "packet",
                allocationID: "allocation",
                marker: "EXACT-V3",
                promptHash: String(repeating: "1", count: 64),
                tokenAllocation: 100,
                maxModelCalls: 1,
                route: route
            ),
            authorizationManifestPath: "/tmp/authorization.json",
            hardBudgetCLIManifestPath: "/tmp/cli-manifest.json",
            hardBudgetLedgerPath: "/tmp/ledger.json",
            candidateExecutionLease: nil,
            credentialAuthorizationV3: packetAuth
        )
    }
}
