import XCTest
@testable import GrokBuild

final class ModelRouteContractTests: XCTestCase {
    func testStructuredCheckpointRouteReceiptIsCredentialFreeAndExplicitAboutFallback() throws {
        let model = CustomModel(
            id: "openrouter-deepseek",
            model: "deepseek/deepseek-v4-flash-0731",
            baseURL: "https://user:password@openrouter.ai/api/v1?secret=value",
            providerID: "openrouter"
        )
        let route = ModelRouteContract.resolve(selectedModelID: model.id, customModel: model)
        let receipt = AssistantTurnCheckpoint.RouteReceipt(route)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(receipt), encoding: .utf8))

        XCTAssertEqual(receipt.kind, .brokeredOpenRouter)
        XCTAssertEqual(receipt.providerModelID, "deepseek/deepseek-v4-flash-0731")
        XCTAssertTrue(receipt.modelIsPinned)
        XCTAssertFalse(receipt.servingProviderIsProven)
        XCTAssertFalse(receipt.appFallbackEnabled)
        XCTAssertFalse(json.contains("password"))
        XCTAssertFalse(json.contains("secret=value"))
    }

    func testNativeModelIsDirectXAIWithoutAppFallback() {
        let route = ModelRouteContract.resolve(selectedModelID: "grok-4.5", customModel: nil)

        XCTAssertEqual(route.kind, .nativeXAI)
        XCTAssertEqual(route.compactLabel, "Direct xAI")
        XCTAssertTrue(route.modelIsPinned)
        XCTAssertTrue(route.servingProviderIsProven)
        XCTAssertTrue(route.detailLines.joined().contains("no alternate provider route"))
    }

    func testCLIAdvertisedUserProviderIsNeverMislabelledNativeXAI() {
        let route = ModelRouteContract.resolve(
            selectedModelID: "user-gateway-model",
            customModel: nil,
            isKnownNativeModel: false
        )

        XCTAssertEqual(route.kind, .unavailable)
        XCTAssertEqual(route.compactLabel, "Provider detail unavailable")
        XCTAssertFalse(route.servingProviderIsProven)
        XCTAssertEqual(route.authBoundary, .unavailable)
        XCTAssertTrue(route.detailLines.joined().contains("does not label"))
    }

    func testDirectProviderNamesEndpointAndPinnedModel() {
        let model = CustomModel(
            id: "glm",
            model: "glm-5.2",
            baseURL: "https://api.z.ai/api/coding/paas/v4",
            providerID: "zai"
        )
        let route = ModelRouteContract.resolve(selectedModelID: model.id, customModel: model)

        XCTAssertEqual(route.kind, .directProvider)
        XCTAssertEqual(route.compactLabel, "Direct Z.ai (GLM)")
        XCTAssertEqual(route.endpointHost, "api.z.ai")
        XCTAssertTrue(route.modelIsPinned)
        XCTAssertTrue(route.servingProviderIsProven)
    }

    func testOpenRouterPinnedModelDoesNotClaimServingProviderProof() {
        let model = CustomModel(
            id: "deepseek",
            model: "deepseek/deepseek-v4",
            baseURL: "https://openrouter.ai/api/v1",
            providerID: "openrouter"
        )
        let route = ModelRouteContract.resolve(selectedModelID: model.id, customModel: model)

        XCTAssertEqual(route.kind, .brokeredOpenRouter)
        XCTAssertEqual(route.compactLabel, "OpenRouter · model pinned")
        XCTAssertTrue(route.modelIsPinned)
        XCTAssertFalse(route.servingProviderIsProven)
        XCTAssertTrue(route.detailLines.joined().contains("not claimed as proven"))
    }

    func testOpenRouterAutoIsDisclosedAsAutomaticRoute() {
        let model = CustomModel(
            id: "openrouter-auto",
            model: "openrouter/auto",
            baseURL: "https://openrouter.ai/api/v1"
        )
        let route = ModelRouteContract.resolve(selectedModelID: model.id, customModel: model)

        XCTAssertEqual(route.kind, .brokeredOpenRouter)
        XCTAssertEqual(route.compactLabel, "OpenRouter · auto route")
        XCTAssertFalse(route.modelIsPinned)
    }

    func testLoopbackEndpointIsLocalAndHasNoRemoteFallback() {
        let model = CustomModel(
            id: "ollama",
            model: "qwen3",
            baseURL: "http://127.0.0.1:11434/v1",
            providerID: "ollama"
        )
        let route = ModelRouteContract.resolve(selectedModelID: model.id, customModel: model)

        XCTAssertEqual(route.kind, .localEndpoint)
        XCTAssertEqual(route.compactLabel, "Local endpoint")
        XCTAssertEqual(route.endpointRouteIdentity, "http://127.0.0.1:11434/v1")
        XCTAssertTrue(route.detailLines.joined().contains("no remote fallback"))
    }

    func testObservationEndpointIdentityKeepsRouteBoundariesAndDropsCredentials() throws {
        let model = CustomModel(
            id: "custom",
            model: "same-model",
            baseURL: "https://user:password@example.test:8443/proxy/v1/?api_key=secret#fragment"
        )
        let route = ModelRouteContract.resolve(selectedModelID: model.id, customModel: model)

        XCTAssertEqual(route.endpointRouteIdentity, "https://example.test:8443/proxy/v1")
        XCTAssertFalse(try XCTUnwrap(route.endpointRouteIdentity).contains("password"))
        XCTAssertFalse(try XCTUnwrap(route.endpointRouteIdentity).contains("secret"))
    }
}
