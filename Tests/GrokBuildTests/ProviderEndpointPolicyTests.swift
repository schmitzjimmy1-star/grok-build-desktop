import Foundation
import XCTest
@testable import GrokBuild

final class ProviderEndpointPolicyTests: XCTestCase {
    // MARK: - Locality classification

    func testExactLoopbackAndAliasHostsClassifyLocal() {
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "http://localhost:11434/v1"), .loopback)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "http://LOCALHOST:8080/v1"), .loopback)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "http://api.localhost/v1"), .loopback)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "http://127.0.0.1:11434/v1"), .loopback)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "http://127.250.0.9/v1"), .loopback)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "http://[::1]:8000/v1"), .loopback)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "http://0.0.0.0:8000/v1"), .localAlias)
        XCTAssertEqual(
            ProviderEndpointPolicy.locality(ofBaseURL: "http://host.docker.internal:11434/v1"),
            .localAlias
        )
        XCTAssertTrue(ProviderEndpointPolicy.isLocal(baseURL: "http://localhost:11434/v1"))
        XCTAssertTrue(ProviderEndpointPolicy.isLocal(baseURL: "http://[::1]:8000/v1"))
    }

    func testSubstringLookalikesClassifyRemote() {
        // Every one of these classified "local" under the old substring matching.
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "https://localhost.evil.example/v1"), .remote)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "https://evil.example/v1?upstream=127.0.0.1"), .remote)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "https://127.0.0.1.evil.example/v1"), .remote)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "https://my-localhost-tunnel.example/v1"), .remote)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "http://1270.0.0.1/v1"), .remote)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "http://127.0.0.256/v1"), .remote)
        XCTAssertEqual(ProviderEndpointPolicy.locality(ofBaseURL: "https://api.openai.com/v1"), .remote)
        XCTAssertFalse(ProviderEndpointPolicy.isLocal(baseURL: "https://localhost.evil.example/v1"))
    }

    func testUnparseableOrNonHTTPURLsClassifyAsNeitherLocalNorRemote() {
        XCTAssertNil(ProviderEndpointPolicy.locality(ofBaseURL: ""))
        XCTAssertNil(ProviderEndpointPolicy.locality(ofBaseURL: "   "))
        XCTAssertNil(ProviderEndpointPolicy.locality(ofBaseURL: "not a url"))
        XCTAssertNil(ProviderEndpointPolicy.locality(ofBaseURL: "ftp://127.0.0.1/v1"))
        XCTAssertNil(ProviderEndpointPolicy.locality(ofBaseURL: "https://"))
        XCTAssertFalse(ProviderEndpointPolicy.isLocal(baseURL: "not a url"))
    }

    // MARK: - Transport rules

    func testRemoteHTTPIsATransportIssueAndLocalHTTPIsNot() {
        XCTAssertNotNil(ProviderEndpointPolicy.transportIssue(forBaseURL: "http://api.example.com/v1"))
        XCTAssertNil(ProviderEndpointPolicy.transportIssue(forBaseURL: "https://api.example.com/v1"))
        XCTAssertNil(ProviderEndpointPolicy.transportIssue(forBaseURL: "http://localhost:11434/v1"))
        XCTAssertNil(ProviderEndpointPolicy.transportIssue(forBaseURL: "http://[::1]:8000/v1"))
        XCTAssertNil(ProviderEndpointPolicy.transportIssue(forBaseURL: "http://host.docker.internal:11434/v1"))
    }

    func testValidationRejectsRemoteHTTPForModelsAndProviders() {
        let remoteHTTPModel = CustomModel(id: "m", model: "m", baseURL: "http://api.example.com/v1")
        XCTAssertNotNil(remoteHTTPModel.validationError)
        XCTAssertTrue(remoteHTTPModel.validationError?.contains("https") ?? false)

        let remoteHTTPSModel = CustomModel(id: "m", model: "m", baseURL: "https://api.example.com/v1")
        XCTAssertNil(remoteHTTPSModel.validationError)

        let localHTTPModel = CustomModel(id: "m", model: "m", baseURL: "http://localhost:8000/v1")
        XCTAssertNil(localHTTPModel.validationError)

        let remoteHTTPProvider = Provider(id: "p", name: "P", baseURL: "http://api.example.com/v1")
        XCTAssertNotNil(remoteHTTPProvider.validationError)

        let localHTTPProvider = Provider(id: "p", name: "P", baseURL: "http://127.0.0.1:11434/v1")
        XCTAssertNil(localHTTPProvider.validationError)
    }

    func testModelAndProviderLocalityUseExactHostMatching() {
        XCTAssertFalse(CustomModel(id: "m", model: "m", baseURL: "https://localhost.evil.example/v1").isLocalEndpoint)
        XCTAssertTrue(CustomModel(id: "m", model: "m", baseURL: "http://127.0.0.1:11434/v1").isLocalEndpoint)
        XCTAssertFalse(Provider(id: "p", name: "P", baseURL: "https://evil.example/v1?x=127.0.0.1").isLocalEndpoint)
        XCTAssertTrue(Provider(id: "p", name: "P", baseURL: "http://[::1]:8000/v1").isLocalEndpoint)
    }

    // MARK: - Explicit keyless (`.none`) preservation

    func testKeylessSchemeBuildsRequestWithoutAuthHeadersForRemoteEndpoint() throws {
        let provider = Provider(
            id: "keyless",
            name: "Keyless",
            baseURL: "https://keyless.example/v1",
            apiKey: "stored-but-never-sent",
            authScheme: ProviderAuthScheme.none
        )
        let request = try ProviderModelFetcher.request(for: provider)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "api-key"))
    }

    func testStoreRoundTripPreservesExplicitKeylessSchemeForRemoteProvider() throws {
        let suiteName = "endpoint-policy-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = InMemoryProviderCredentialStore()

        let provider = Provider(
            id: "keyless",
            name: "Keyless",
            baseURL: "https://keyless.example/v1",
            authScheme: ProviderAuthScheme.none
        )
        try ProviderStore.save([provider], defaults: defaults, credentialStore: credentials)

        let loaded = ProviderStore.loadResult(
            defaults: defaults,
            credentialStore: credentials,
            migrationModels: [],
            enforceConfigPermissions: false
        )
        XCTAssertEqual(loaded.providers.first?.authScheme, ProviderAuthScheme.none)
    }

    // MARK: - Credential-over-cleartext guard

    func testRequestRefusesToAttachCredentialOverRemoteHTTP() {
        let provider = Provider(
            id: "insecure",
            name: "Insecure",
            baseURL: "http://api.example.com/v1",
            apiKey: "secret",
            authScheme: .bearer
        )
        XCTAssertThrowsError(try ProviderModelFetcher.request(for: provider)) { error in
            guard case ProviderModelFetcher.FetchError.insecureEndpoint = error else {
                return XCTFail("Expected insecureEndpoint, got \(error)")
            }
        }
    }

    func testKeylessRemoteHTTPRequestProceedsWithoutCredential() throws {
        let provider = Provider(
            id: "keyless-http",
            name: "Keyless HTTP",
            baseURL: "http://lan-box.example:8000/v1",
            authScheme: ProviderAuthScheme.none
        )
        let request = try ProviderModelFetcher.request(for: provider)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "api-key"))
    }

    // MARK: - Trusted-LAN insecure-HTTP opt-in

    func testInsecureHTTPOptInBypassesTransportIssueAndRequestGuard() throws {
        XCTAssertNotNil(ProviderEndpointPolicy.transportIssue(forBaseURL: "http://lan-box.local.example/v1"))
        XCTAssertNil(ProviderEndpointPolicy.transportIssue(
            forBaseURL: "http://lan-box.local.example/v1",
            allowingInsecureHTTP: true
        ))
        // https and loopback are unaffected by the flag.
        XCTAssertNil(ProviderEndpointPolicy.transportIssue(
            forBaseURL: "https://api.example.com/v1",
            allowingInsecureHTTP: true
        ))

        let optedIn = Provider(
            id: "lan",
            name: "LAN",
            baseURL: "http://lan-box.local.example/v1",
            apiKey: "lan-key",
            authScheme: .bearer,
            allowInsecureHTTP: true
        )
        XCTAssertNil(optedIn.validationError)
        let request = try ProviderModelFetcher.request(for: optedIn)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer lan-key")

        var strict = optedIn
        strict.allowInsecureHTTP = false
        XCTAssertNotNil(strict.validationError)
        XCTAssertThrowsError(try ProviderModelFetcher.request(for: strict))
    }

    func testInsecureHTTPOptInSurvivesEncodingRoundTrip() throws {
        let provider = Provider(
            id: "lan",
            name: "LAN",
            baseURL: "http://lan-box.local.example/v1",
            allowInsecureHTTP: true
        )
        let decoded = try JSONDecoder().decode(Provider.self, from: JSONEncoder().encode(provider))
        XCTAssertTrue(decoded.allowInsecureHTTP)
        // Absent in legacy blobs decodes to the safe default.
        let legacy = try JSONDecoder().decode(
            Provider.self,
            from: Data(#"{"id":"p","name":"P","baseURL":"https://api.example.com/v1"}"#.utf8)
        )
        XCTAssertFalse(legacy.allowInsecureHTTP)
    }

    // MARK: - Diagnostics redaction

    func testRedactedDisplayDropsQueryFragmentAndUserinfo() {
        XCTAssertEqual(
            ProviderEndpointPolicy.redactedDisplay(
                urlString: "https://user:pass@api.example.com:8443/v1/models?api-key=sekrit#frag"
            ),
            "https://api.example.com:8443/v1/models"
        )
        XCTAssertEqual(
            ProviderEndpointPolicy.redactedDisplay(urlString: "https://api.example.com/v1"),
            "https://api.example.com/v1"
        )
        XCTAssertEqual(ProviderEndpointPolicy.redactedDisplay(urlString: "not a url"), "<unparseable URL>")
    }

    // MARK: - Redirect policy decisions

    private func redirectDecision(from origin: String, to target: String,
                                  delegate: ProviderRedirectPolicyDelegate? = nil) -> URLRequest? {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let policyDelegate = delegate ?? ProviderRedirectPolicyDelegate()
        let task = session.dataTask(with: URLRequest(url: URL(string: origin)!))
        let response = HTTPURLResponse(
            url: URL(string: origin)!,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": target]
        )!
        var decision: URLRequest?
        policyDelegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: target)!)
        ) { decision = $0 }
        return decision
    }

    func testRedirectDelegateAllowsSameOriginHopsWithinLimit() {
        let delegate = ProviderRedirectPolicyDelegate()
        for hop in 1...ProviderRedirectPolicyDelegate.maxRedirects {
            XCTAssertNotNil(
                redirectDecision(
                    from: "https://api.example.com/v1/models",
                    to: "https://api.example.com/v\(hop)/models",
                    delegate: delegate
                ),
                "same-origin hop \(hop) should be followed"
            )
        }
    }

    func testRedirectDelegateNormalizesDefaultPorts() {
        XCTAssertNotNil(redirectDecision(
            from: "https://api.example.com/v1/models",
            to: "https://api.example.com:443/v2/models"
        ))
    }

    func testRedirectDelegateRefusesCrossOriginDowngradePortChangeAndExcessHops() {
        XCTAssertNil(redirectDecision(
            from: "https://api.example.com/v1/models",
            to: "https://evil.example/v1/models"
        ), "cross-host redirect must be refused")

        XCTAssertNil(redirectDecision(
            from: "https://api.example.com/v1/models",
            to: "http://api.example.com/v1/models"
        ), "https→http downgrade must be refused")

        XCTAssertNil(redirectDecision(
            from: "https://api.example.com/v1/models",
            to: "https://api.example.com:8443/v1/models"
        ), "port change must be refused")

        let delegate = ProviderRedirectPolicyDelegate()
        for _ in 1...ProviderRedirectPolicyDelegate.maxRedirects {
            _ = redirectDecision(
                from: "https://api.example.com/v1/models",
                to: "https://api.example.com/v1/models",
                delegate: delegate
            )
        }
        XCTAssertNil(redirectDecision(
            from: "https://api.example.com/v1/models",
            to: "https://api.example.com/v1/models",
            delegate: delegate
        ), "hop beyond the ceiling must be refused")
    }
}
