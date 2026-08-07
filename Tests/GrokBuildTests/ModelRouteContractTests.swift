import XCTest
@testable import GrokBuild

final class ModelRouteContractTests: XCTestCase {
    func testNativeModelIsDirectXAIWithoutAppFallback() {
        let route = ModelRouteContract.resolve(selectedModelID: "grok-4.5", customModel: nil)

        XCTAssertEqual(route.kind, .nativeXAI)
        XCTAssertEqual(route.compactLabel, "Direct xAI")
        XCTAssertTrue(route.modelIsPinned)
        XCTAssertTrue(route.servingProviderIsProven)
        XCTAssertTrue(route.detailLines.joined().contains("no alternate provider route"))
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
        XCTAssertTrue(route.detailLines.joined().contains("no remote fallback"))
    }
}
