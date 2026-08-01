import Foundation
import CryptoKit
import XCTest
@testable import GrokBuild

final class OpenRouterOAuthTests: XCTestCase {
    // MARK: - PKCE

    func testPKCEChallengeIsS256Base64URLOfVerifier() {
        let pkce = OpenRouterOAuth.generatePKCE()
        // Verifier length is within the RFC 7636 43–128 range.
        XCTAssertGreaterThanOrEqual(pkce.verifier.count, 43)
        XCTAssertLessThanOrEqual(pkce.verifier.count, 128)
        // base64url alphabet only — no +, /, or = padding.
        XCTAssertNil(pkce.verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertNil(pkce.challenge.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        // Challenge is exactly S256(verifier), base64url.
        let expected = OpenRouterOAuth.base64URL(Data(SHA256.hash(data: Data(pkce.verifier.utf8))))
        XCTAssertEqual(pkce.challenge, expected)
        // Two generations differ (random verifier).
        XCTAssertNotEqual(OpenRouterOAuth.generatePKCE().verifier, pkce.verifier)
    }

    // MARK: - Authorization URL

    func testAuthorizationURLCarriesCallbackChallengeAndMethod() {
        let callback = URL(string: "http://127.0.0.1:52123/cb-abc")!
        let url = OpenRouterOAuth.authorizationURL(callbackURL: callback, challenge: "CHAL")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.host, "openrouter.ai")
        XCTAssertEqual(components.path, "/auth")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["callback_url"], callback.absoluteString)
        XCTAssertEqual(items["code_challenge"], "CHAL")
        XCTAssertEqual(items["code_challenge_method"], "S256")
    }

    // MARK: - Code extraction

    func testExtractCodeFromRequestLine() {
        XCTAssertEqual(
            OpenRouterOAuth.extractCode(fromRequestLine: "GET /cb-xyz?code=ABC123 HTTP/1.1"),
            "ABC123"
        )
        XCTAssertEqual(
            OpenRouterOAuth.extractCode(fromRequestLine: "GET /cb-xyz?state=s&code=ABC123 HTTP/1.1"),
            "ABC123"
        )
        XCTAssertNil(OpenRouterOAuth.extractCode(fromRequestLine: "GET /cb-xyz HTTP/1.1"))
        XCTAssertNil(OpenRouterOAuth.extractCode(fromRequestLine: "garbage"))
    }

    // MARK: - Exchange request / response

    func testExchangeRequestPostsCodeAndVerifier() throws {
        let request = OpenRouterOAuth.exchangeRequest(code: "the-code", verifier: "the-verifier")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/auth/keys")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(body?["code"], "the-code")
        XCTAssertEqual(body?["code_verifier"], "the-verifier")
        XCTAssertEqual(body?["code_challenge_method"], "S256")
    }

    func testParseKeyResponse() throws {
        XCTAssertEqual(
            try OpenRouterOAuth.parseKeyResponse(Data(#"{"key":"sk-or-abc"}"#.utf8)),
            "sk-or-abc"
        )
        XCTAssertThrowsError(try OpenRouterOAuth.parseKeyResponse(Data(#"{"key":""}"#.utf8)))
        XCTAssertThrowsError(try OpenRouterOAuth.parseKeyResponse(Data(#"{}"#.utf8)))
        XCTAssertThrowsError(try OpenRouterOAuth.parseKeyResponse(Data("not json".utf8)))
    }

    // MARK: - Loopback callback server (real TCP, no OpenRouter)

    func testLoopbackServerCapturesCodeFromRealRequest() async throws {
        let server = LoopbackCallbackServer()
        let callbackURL = try await server.start()
        defer { server.stop() }

        XCTAssertEqual(callbackURL.host, "127.0.0.1")
        XCTAssertNotNil(callbackURL.port)

        // Hit the callback exactly as the browser redirect would, concurrently with the wait.
        async let captured = server.waitForCode(timeout: 10)
        var withCode = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)!
        withCode.queryItems = [URLQueryItem(name: "code", value: "live-code-42")]
        let (_, response) = try await URLSession(configuration: .ephemeral).data(from: withCode.url!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let code = try await captured
        XCTAssertEqual(code, "live-code-42")
    }

    func testLoopbackServerTimesOutWhenNoRequestArrives() async throws {
        let server = LoopbackCallbackServer()
        _ = try await server.start()
        defer { server.stop() }
        do {
            _ = try await server.waitForCode(timeout: 0.5)
            XCTFail("expected timeout")
        } catch {
            guard case OpenRouterOAuth.OAuthError.timedOut = error else {
                return XCTFail("expected timedOut, got \(error)")
            }
        }
    }

    // MARK: - Full connect() with a stubbed exchange + fake browser

    func testConnectExchangesCapturedCodeForKey() async throws {
        OAuthURLProtocolStub.reset()
        defer { OAuthURLProtocolStub.reset() }
        OAuthURLProtocolStub.responder = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBodySafe()) as? [String: String]
            XCTAssertEqual(body?["code"], "browser-code")
            XCTAssertFalse((body?["code_verifier"] ?? "").isEmpty)
            return (200, Data(#"{"key":"sk-or-connected"}"#.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OAuthURLProtocolStub.self]
        let session = URLSession(configuration: config)

        // The "browser" simply GETs the callback URL with a code, as OpenRouter would.
        let key = try await OpenRouterOAuth.connect(session: session, timeout: 10) { authURL in
            let callback = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
                .queryItems!.first(where: { $0.name == "callback_url" })!.value!
            var redirect = URLComponents(string: callback)!
            redirect.queryItems = [URLQueryItem(name: "code", value: "browser-code")]
            Task { _ = try? await URLSession(configuration: .ephemeral).data(from: redirect.url!) }
        }
        XCTAssertEqual(key, "sk-or-connected")
    }
}

private extension URLRequest {
    func httpBodySafe() -> Data {
        if let body = httpBody { return body }
        if let stream = httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }
        return Data()
    }
}

private final class OAuthURLProtocolStub: URLProtocol, @unchecked Sendable {
    static var responder: (@Sendable (URLRequest) -> (Int, Data))?

    static func reset() { responder = nil }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "openrouter.ai"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, data) = responder(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
