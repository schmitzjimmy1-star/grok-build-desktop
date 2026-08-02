import Foundation
import CryptoKit
import Network
import AppKit

/// Browser-assisted OpenRouter key acquisition (S256 PKCE). OpenRouter's flow returns a
/// normal user-controlled **API key**, not an OAuth token set — so there is no refresh or
/// expiry machinery; the result flows into the same Keychain storage as a pasted key.
///
/// Security shape: the code_verifier never leaves this process; the code is exchanged only
/// over HTTPS; the callback listener is loopback-only, single-use, randomly-pathed, and
/// bounded by a timeout. GrokBuild opens the system browser and the user authorizes on
/// their own OpenRouter account — the app never handles their OpenRouter login.
enum OpenRouterOAuth {
    static let authBase = URL(string: "https://openrouter.ai/auth")!
    static let keyExchangeURL = URL(string: "https://openrouter.ai/api/v1/auth/keys")!

    struct PKCE: Sendable, Equatable {
        let verifier: String
        let challenge: String
    }

    enum OAuthError: LocalizedError {
        case listenerFailed(String)
        case timedOut
        case missingCode
        case exchange(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .listenerFailed(let m): return "Could not open a local callback listener: \(m)"
            case .timedOut: return "Timed out waiting for OpenRouter authorization. Try Connect again."
            case .missingCode: return "OpenRouter did not return an authorization code."
            case .exchange(let m): return "OpenRouter key exchange failed: \(m)"
            case .badResponse: return "OpenRouter returned an unexpected response with no key."
            }
        }
    }

    // MARK: - Pure, unit-testable pieces

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func generatePKCE() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        return PKCE(verifier: verifier, challenge: challenge)
    }

    static func authorizationURL(callbackURL: URL, challenge: String) -> URL {
        var components = URLComponents(url: authBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: callbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    /// Extracts `?code=` from an HTTP request line like `GET /cb-UUID?code=XYZ HTTP/1.1`.
    /// When `expectedPath` is supplied, lookalike callbacks are rejected before their code
    /// can satisfy the pending authorization.
    static func extractCode(fromRequestLine line: String, expectedPath: String? = nil) -> String? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        guard let components = URLComponents(string: "http://127.0.0.1\(parts[1])") else { return nil }
        if let expectedPath, components.path != expectedPath { return nil }
        return components.queryItems?.first(where: { $0.name == "code" })?.value?.nonEmpty
    }

    static func requestPath(fromRequestLine line: String) -> String? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2,
              let components = URLComponents(string: "http://127.0.0.1\(parts[1])") else {
            return nil
        }
        return components.path
    }

    static func exchangeRequest(code: String, verifier: String) -> URLRequest {
        var request = URLRequest(url: keyExchangeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "code": code,
            "code_verifier": verifier,
            "code_challenge_method": "S256",
        ])
        return request
    }

    static func parseKeyResponse(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = (object["key"] as? String)?.nonEmpty else {
            throw OAuthError.badResponse
        }
        return key
    }

    // MARK: - Orchestration

    /// Runs the full flow and returns a fresh OpenRouter API key. Opens the system browser;
    /// the user authorizes on their OpenRouter account and the loopback listener catches the
    /// redirect. `openURL` is injectable for tests.
    static func connect(
        session: URLSession = .shared,
        timeout: TimeInterval = 180,
        openURL: @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) async throws -> String {
        let pkce = generatePKCE()
        let server = LoopbackCallbackServer()
        let callbackURL = try await server.start()
        defer { server.stop() }

        openURL(authorizationURL(callbackURL: callbackURL, challenge: pkce.challenge))

        let code = try await server.waitForCode(timeout: timeout)
        let (data, response) = try await session.data(
            for: exchangeRequest(code: code, verifier: pkce.verifier)
        )
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OAuthError.exchange("HTTP \(http.statusCode)")
        }
        return try parseKeyResponse(data)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// A single-use loopback HTTP listener that captures the `?code=` OpenRouter redirects to.
/// Binds 127.0.0.1 on an ephemeral port with a random path; serves exactly one request,
/// replies with a close-this-window page, and tears down.
final class LoopbackCallbackServer: @unchecked Sendable {
    private let path = "/cb-\(UUID().uuidString)"
    private let lock = NSLock()
    private var listener: NWListener?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var pendingCodeResult: Result<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var resolved = false
    private var startResumed = false

    func start() async throws -> URL {
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        } catch {
            throw OpenRouterOAuth.OAuthError.listenerFailed(error.localizedDescription)
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        self.resumeStart(continuation, .failure(OpenRouterOAuth.OAuthError.listenerFailed("no port assigned")))
                        return
                    }
                    let url = URL(string: "http://127.0.0.1:\(port)\(self.path)")!
                    self.resumeStart(continuation, .success(url))
                case .failed(let error):
                    self.resumeStart(continuation, .failure(OpenRouterOAuth.OAuthError.listenerFailed(error.localizedDescription)))
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
    }

    func waitForCode(timeout: TimeInterval) async throws -> String {
        try await withTaskCancellationHandler {
            try await awaitCode(timeout: timeout)
        } onCancel: {
            self.resolve(.failure(CancellationError()))
        }
    }

    func stop() {
        lock.lock()
        let l = listener
        listener = nil
        let timeout = timeoutTask
        timeoutTask = nil
        let continuation = codeContinuation
        codeContinuation = nil
        pendingCodeResult = nil
        if continuation != nil {
            resolved = true
        }
        lock.unlock()
        timeout?.cancel()
        continuation?.resume(throwing: CancellationError())
        l?.cancel()
    }

    private func resumeStart(_ continuation: CheckedContinuation<URL, Error>, _ result: Result<URL, Error>) {
        lock.lock()
        guard !startResumed else { lock.unlock(); return }
        startResumed = true
        lock.unlock()
        continuation.resume(with: result)
    }

    private func awaitCode(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            lock.lock()
            if let pendingCodeResult {
                self.pendingCodeResult = nil
                lock.unlock()
                continuation.resume(with: pendingCodeResult)
                return
            }
            guard !resolved else {
                lock.unlock()
                continuation.resume(throwing: OpenRouterOAuth.OAuthError.missingCode)
                return
            }
            codeContinuation = continuation
            timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(max(0, timeout)))
                } catch {
                    return
                }
                self?.resolve(.failure(OpenRouterOAuth.OAuthError.timedOut))
            }
            lock.unlock()
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let firstLine = request.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).first.map(String.init) ?? request
            guard OpenRouterOAuth.requestPath(fromRequestLine: firstLine) == self.path else {
                self.sendResponse(
                    status: "404 Not Found",
                    body: "This is not the active GrokBuild authorization callback.",
                    over: connection
                )
                return
            }
            let code = OpenRouterOAuth.extractCode(fromRequestLine: firstLine, expectedPath: self.path)
            let body = code != nil
                ? "GrokBuild is connected to OpenRouter. You can close this window and return to the app."
                : "No authorization code was received. You can close this window and try Connect again."
            self.sendResponse(status: "200 OK", body: body, over: connection)
            if let code {
                self.resolve(.success(code))
            } else {
                self.resolve(.failure(OpenRouterOAuth.OAuthError.missingCode))
            }
        }
    }

    private func sendResponse(status: String, body: String, over connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func resolve(_ result: Result<String, Error>) {
        lock.lock()
        guard !resolved else { lock.unlock(); return }
        resolved = true
        let continuation = codeContinuation
        codeContinuation = nil
        if continuation == nil {
            pendingCodeResult = result
        }
        let timeout = timeoutTask
        timeoutTask = nil
        lock.unlock()
        timeout?.cancel()
        continuation?.resume(with: result)
    }
}
