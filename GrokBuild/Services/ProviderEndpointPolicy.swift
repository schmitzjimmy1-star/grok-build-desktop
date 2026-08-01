import Foundation

/// Parsed-URL trust rules for provider endpoints.
///
/// Locality is decided from the URL's exact host, never from substring matching, so
/// `https://localhost.evil.example` or a `127.0.0.1` buried in a query string can no
/// longer classify as local. This is also the one home for the transport rules
/// GrokBuild's own provider requests obey: credentials travel only over HTTPS unless
/// the endpoint is genuinely this machine, and redirects never cross origins.
enum ProviderEndpointPolicy {
    /// How a base URL's host classifies for trust decisions.
    enum Locality: Equatable {
        /// Standards-defined loopback: `localhost`, `*.localhost`, `127.0.0.0/8`, `::1`.
        case loopback
        /// Hosts GrokBuild has always treated as this-machine (`0.0.0.0`,
        /// `host.docker.internal`). Kept so existing local setups keep working.
        case localAlias
        case remote
    }

    /// Classifies a base URL, or nil when it does not parse as an http(s) URL with a host.
    static func locality(ofBaseURL baseURL: String) -> Locality? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let rawHost = components.host, !rawHost.isEmpty else {
            return nil
        }
        // IPv6 hosts can surface bracketed depending on how the URL was formed.
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()

        if host == "localhost" || host.hasSuffix(".localhost") { return .loopback }
        if isIPv4Loopback(host) { return .loopback }
        if host == "::1" || host.hasPrefix("::1%") { return .loopback }
        if host == "0.0.0.0" || host == "host.docker.internal" { return .localAlias }
        return .remote
    }

    /// `true` when the URL parses and its exact host is loopback or a local alias.
    static func isLocal(baseURL: String) -> Bool {
        switch locality(ofBaseURL: baseURL) {
        case .loopback, .localAlias: return true
        case .remote, .none: return false
        }
    }

    static func isHTTPS(_ baseURL: String) -> Bool {
        URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?
            .scheme?.lowercased() == "https"
    }

    /// A transport problem worth blocking a save over, or nil when acceptable.
    /// Remote `http://` endpoints are rejected: the credential and catalog would travel
    /// cleartext. Loopback and local aliases may use http, and a provider whose owner
    /// explicitly opted into trusted-LAN http passes with the UI carrying the warning.
    static func transportIssue(forBaseURL baseURL: String, allowingInsecureHTTP: Bool = false) -> String? {
        guard locality(ofBaseURL: baseURL) == .remote, !isHTTPS(baseURL) else { return nil }
        if allowingInsecureHTTP { return nil }
        return "Remote endpoints must use https:// — http:// is allowed only for local servers."
    }

    /// Scheme + host + port + path only. Query, fragment, and userinfo never leave the app
    /// in diagnostics: some providers put tokens in query parameters.
    static func redactedDisplay(urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), components.scheme != nil else {
            return "<unparseable URL>"
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string ?? "<unparseable URL>"
    }

    private static func isIPv4Loopback(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber),
                  let value = Int(part), (0...255).contains(value) else {
                return false
            }
            octets.append(value)
        }
        return octets[0] == 127
    }
}

/// Refuses cross-origin, downgrade, and runaway redirects on provider catalog requests.
///
/// Foundation's default behavior re-sends custom `Authorization`/`api-key` headers to
/// wherever a 30x points, including other hosts. This delegate allows at most
/// ``maxRedirects`` hops and only to the exact origin of the original request; anything
/// else stops the redirect so the fetch surfaces the 30x as a typed failure instead of
/// carrying the credential along. Use one instance per request.
final class ProviderRedirectPolicyDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let maxRedirects = 3

    private let lock = NSLock()
    private var redirectCount = 0

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        redirectCount += 1
        let hops = redirectCount
        lock.unlock()

        guard hops <= Self.maxRedirects,
              let original = task.originalRequest?.url,
              let target = request.url,
              Self.sameOrigin(original, target) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    /// Exact scheme + host + port match (default ports normalized), so an https→http
    /// downgrade on the same host is also refused.
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        func normalizedPort(_ url: URL) -> Int? {
            if let port = url.port { return port }
            switch url.scheme?.lowercased() {
            case "https": return 443
            case "http": return 80
            default: return nil
            }
        }
        return a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host?.lowercased() == b.host?.lowercased()
            && normalizedPort(a) == normalizedPort(b)
    }
}
