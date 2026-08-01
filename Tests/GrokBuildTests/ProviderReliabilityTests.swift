import Foundation
import XCTest
@testable import GrokBuild

final class ProviderReliabilityTests: XCTestCase {
    func testSecureRepositorySerializesMutationsAndEnforcesOwnerOnlyPermissions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-config-repository-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.toml")
        let repository = GrokConfigRepository(configURL: url)

        let queue = DispatchQueue(label: "config-writers", attributes: .concurrent)
        let group = DispatchGroup()
        for index in 0..<24 {
            group.enter()
            queue.async {
                defer { group.leave() }
                try? repository.update { contents in
                    contents + "\n[fixture.\(index)]\nenabled = true\n"
                }
            }
        }
        group.wait()

        let contents = repository.read()
        for index in 0..<24 {
            XCTAssertTrue(contents.contains("[fixture.\(index)]"))
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testProviderEncodingOmitsCredentialAndKeepsAuthScheme() throws {
        let provider = Provider(
            id: "openai",
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            apiKey: "never-serialize-me",
            authScheme: .bearer
        )
        let data = try JSONEncoder().encode(provider)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("never-serialize-me"))
        XCTAssertFalse(text.contains("apiKey"))
        XCTAssertTrue(text.contains("bearer"))
    }

    func testCredentialMigrationPrefersProviderKeyAndIsIdempotent() throws {
        let store = InMemoryProviderCredentialStore()
        let providers = [Provider(
            id: "openai",
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            apiKey: "provider-key"
        )]
        let models = [CustomModel(
            id: "one",
            model: "gpt-test",
            baseURL: "https://api.openai.com/v1",
            apiKey: "older-model-key"
        )]

        let first = ProviderCredentialMigrator.migrate(
            providers: providers,
            models: models,
            credentialStore: store
        )
        XCTAssertTrue(first.didMigrate)
        XCTAssertFalse(first.storageFailed)
        XCTAssertEqual(first.providers.first?.apiKey, "provider-key")
        XCTAssertEqual(try store.credential(for: "openai"), "provider-key")

        let second = ProviderCredentialMigrator.migrate(
            providers: providers.map {
                Provider(id: $0.id, name: $0.name, baseURL: $0.baseURL)
            },
            models: models,
            credentialStore: store
        )
        XCTAssertFalse(second.didMigrate)
        XCTAssertEqual(second.providers.first?.apiKey, "provider-key")
    }

    func testCredentialMigrationReportsConflictingModelKeysWithoutGuessing() throws {
        let store = InMemoryProviderCredentialStore()
        let provider = Provider(id: "custom", name: "Custom", baseURL: "https://example.test/v1")
        let models = [
            CustomModel(id: "one", model: "one", baseURL: provider.baseURL, apiKey: "key-a"),
            CustomModel(id: "two", model: "two", baseURL: provider.baseURL, apiKey: "key-b")
        ]

        let result = ProviderCredentialMigrator.migrate(
            providers: [provider],
            models: models,
            credentialStore: store
        )
        XCTAssertEqual(result.issues.map(\.kind), [.conflict])
        XCTAssertNil(try store.credential(for: provider.id))
        XCTAssertEqual(result.providers.first?.apiKey, "")
    }

    func testCredentialMigrationRollsBackNewEntriesOnStorageFailure() throws {
        let store = InMemoryProviderCredentialStore(failingProviderID: "second")
        let providers = [
            Provider(id: "first", name: "First", baseURL: "https://first.test/v1", apiKey: "first-key"),
            Provider(id: "second", name: "Second", baseURL: "https://second.test/v1", apiKey: "second-key")
        ]

        let result = ProviderCredentialMigrator.migrate(
            providers: providers,
            models: [],
            credentialStore: store
        )
        XCTAssertTrue(result.storageFailed)
        XCTAssertNil(try store.credential(for: "first"))
        XCTAssertNil(try store.credential(for: "second"))
    }

    func testProviderRequestUsesOnlyConfiguredAuthenticationHeaders() throws {
        let bearer = Provider(
            id: "bearer",
            name: "Bearer",
            baseURL: "https://example.test/v1",
            apiKey: "secret",
            authScheme: .bearer
        )
        let bearerRequest = try ProviderModelFetcher.request(for: bearer)
        XCTAssertEqual(bearerRequest.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertNil(bearerRequest.value(forHTTPHeaderField: "api-key"))

        var header = bearer
        header.authScheme = .apiKeyHeader
        let headerRequest = try ProviderModelFetcher.request(for: header)
        XCTAssertNil(headerRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(headerRequest.value(forHTTPHeaderField: "api-key"), "secret")

        var both = bearer
        both.authScheme = .bearerAndAPIKey
        let bothRequest = try ProviderModelFetcher.request(for: both)
        XCTAssertEqual(bothRequest.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(bothRequest.value(forHTTPHeaderField: "api-key"), "secret")

        let local = Provider(
            id: "local",
            name: "Local",
            baseURL: "http://127.0.0.1:11434/v1",
            apiKey: "must-not-be-sent",
            authScheme: .bearer
        )
        let localRequest = try ProviderModelFetcher.request(for: local)
        XCTAssertNil(localRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(localRequest.value(forHTTPHeaderField: "api-key"))
    }

    func testValidationDistinguishesMissingModelFromBadCredential() async throws {
        let session = makeStubSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/models")
            let payload = #"{"object":"list","data":[{"id":"available-model"}]}"#
            return (200, Data(payload.utf8))
        }
        let provider = Provider(
            id: "custom",
            name: "Custom",
            baseURL: "https://example.test/v1",
            apiKey: "secret"
        )

        let result = await ProviderModelFetcher.validate(
            provider: provider,
            configuredModelIDs: ["missing-model"],
            session: session,
            now: Date(timeIntervalSince1970: 42)
        )
        XCTAssertEqual(result.status, .modelUnavailable)
        XCTAssertEqual(result.missingModelIDs, ["missing-model"])
        XCTAssertEqual(result.models.map(\.id), ["available-model"])
    }

    func testValidationClassifiesProviderFailures() async throws {
        let cases: [(Int, ProviderValidationStatus)] = [
            (401, .unauthorized),
            (403, .unauthorized),
            (404, .endpointMissing),
            (429, .rateLimited),
            (503, .providerUnavailable)
        ]
        for (code, expected) in cases {
            let session = makeStubSession { _ in (code, Data("{}".utf8)) }
            let result = await ProviderModelFetcher.validate(
                provider: Provider(id: "p", name: "P", baseURL: "https://example.test/v1", apiKey: "secret"),
                configuredModelIDs: [],
                session: session
            )
            XCTAssertEqual(result.status, expected, "HTTP \(code)")
        }
    }

    func testValidationClassifiesMalformedAndEmptyCatalogs() async throws {
        let malformed = makeStubSession { _ in (200, Data("not-json".utf8)) }
        let provider = Provider(id: "p", name: "P", baseURL: "https://example.test/v1")

        let malformedResult = await ProviderModelFetcher.validate(
            provider: provider,
            configuredModelIDs: [],
            session: malformed
        )
        let empty = makeStubSession { _ in (200, Data(#"{"data":[]}"#.utf8)) }
        let emptyResult = await ProviderModelFetcher.validate(
            provider: provider,
            configuredModelIDs: [],
            session: empty
        )
        XCTAssertEqual(malformedResult.status, .incompatibleResponse)
        XCTAssertEqual(emptyResult.status, .emptyCatalog)
    }

    func testValidationClassifiesTimeoutAsOffline() async throws {
        let session = makeStubSession { _ in throw URLError(.timedOut) }
        let result = await ProviderModelFetcher.validate(
            provider: Provider(id: "p", name: "P", baseURL: "https://example.test/v1"),
            configuredModelIDs: [],
            session: session
        )
        XCTAssertEqual(result.status, .timeoutOrOffline)
    }

    func testUpdatePropagatesReadFailureInsteadOfRewritingFromEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-config-read-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("config.toml")
        let original = "[keep]\nvalue = true\n"
        try original.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }

        let repository = GrokConfigRepository(configURL: url)
        XCTAssertThrowsError(try repository.update { $0 + "\n[injected]\n" })

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original)

        // A genuinely missing file still starts the rewrite from empty.
        let freshURL = root.appendingPathComponent("fresh.toml")
        let freshRepository = GrokConfigRepository(configURL: freshURL)
        try freshRepository.update { contents in
            XCTAssertEqual(contents, "")
            return "[fresh]\n"
        }
        XCTAssertEqual(try String(contentsOf: freshURL, encoding: .utf8), "[fresh]\n")
    }

    func testValidationClassifiesInsecureRemoteEndpointWithoutNetworking() async {
        let session = makeStubSession { request in
            XCTFail("No request may be issued for a credentialed remote http endpoint, got \(request)")
            return (200, Data())
        }
        let result = await ProviderModelFetcher.validate(
            provider: Provider(
                id: "insecure",
                name: "Insecure",
                baseURL: "http://api.example.com/v1",
                apiKey: "secret",
                authScheme: .bearer
            ),
            configuredModelIDs: [],
            session: session
        )
        XCTAssertEqual(result.status, .insecureEndpoint)
    }

    func testValidationBlocksCrossOriginRedirectWithoutFollowingIt() async {
        URLProtocolStub.reset()
        defer { URLProtocolStub.reset() }
        URLProtocolStub.redirectLocations = [
            "https://api.example.test/v1/models": "https://evil.example/v1/models"
        ]
        let session = makeStubSession { _ in
            (200, Data(#"{"data":[{"id":"model-behind-redirect"}]}"#.utf8))
        }

        let result = await ProviderModelFetcher.validate(
            provider: Provider(
                id: "redirecting",
                name: "Redirecting",
                baseURL: "https://api.example.test/v1",
                apiKey: "secret"
            ),
            configuredModelIDs: [],
            session: session
        )
        XCTAssertEqual(result.status, .redirectBlocked)
        XCTAssertEqual(
            URLProtocolStub.recordedRequestURLs,
            ["https://api.example.test/v1/models"],
            "the cross-origin target must never be requested"
        )
    }

    private func makeStubSession(
        handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)
    ) -> URLSession {
        URLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

final class InMemoryProviderCredentialStore: ProviderCredentialStoring, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()
    private let failingProviderID: String?

    init(failingProviderID: String? = nil) {
        self.failingProviderID = failingProviderID
    }

    func credential(for providerID: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[providerID]
    }

    func setCredential(_ credential: String, for providerID: String) throws {
        if providerID == failingProviderID { throw ProviderCredentialError.verificationFailed }
        lock.lock()
        defer { lock.unlock() }
        values[providerID] = credential
    }

    func removeCredential(for providerID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[providerID] = nil
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    /// URLs (absolute string) that answer with a 302 to the mapped Location.
    static var redirectLocations: [String: String] = [:]
    private static let recordLock = NSLock()
    private static var _recordedRequestURLs: [String] = []

    static var recordedRequestURLs: [String] {
        recordLock.lock()
        defer { recordLock.unlock() }
        return _recordedRequestURLs
    }

    static func reset() {
        recordLock.lock()
        defer { recordLock.unlock() }
        redirectLocations = [:]
        _recordedRequestURLs = []
    }

    private static func record(_ url: URL?) {
        recordLock.lock()
        defer { recordLock.unlock() }
        if let url { _recordedRequestURLs.append(url.absoluteString) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.record(request.url)

        if let requestURL = request.url,
           let location = Self.redirectLocations[requestURL.absoluteString],
           let target = URL(string: location) {
            let redirectResponse = HTTPURLResponse(
                url: requestURL,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": location]
            )!
            // Signal the redirect so the session consults the task delegate; also
            // deliver the 302 itself so a refused redirect terminates the load.
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: redirectResponse)
            client?.urlProtocol(self, didReceive: redirectResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
