import Foundation

enum GrokAuthenticationState: Equatable, Sendable {
    case checking
    case signedIn(source: String)
    case signedOut
    case unavailable

    var label: String {
        switch self {
        case .checking: return "Checking…"
        case .signedIn: return "Signed in"
        case .signedOut: return "Sign-in required"
        case .unavailable: return "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "Checking the local grok CLI without sending a provider request."
        case .signedIn(let source):
            return "The grok CLI reports an active \(source) session."
        case .signedOut:
            return "Sign in through xAI's browser flow, then check again."
        case .unavailable:
            return "GrokBuild could not verify the local grok CLI sign-in state."
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

enum GrokAuthentication {
    static func check() async -> GrokAuthenticationState {
        guard GrokCLIService.locateGrokCLI() != nil else { return .unavailable }
        do {
            let result = try await GrokCLIService().run(
                ["models"],
                allowFailure: true,
                timeout: 20
            )
            return status(from: result)
        } catch {
            return .unavailable
        }
    }

    /// Parses only coarse authentication state. Raw CLI output never enters UI state, logs,
    /// receipts, or diagnostics because it may evolve to include account-specific details.
    static func status(from result: GrokCLIResult) -> GrokAuthenticationState {
        let output = result.combinedOutput
        let lower = output.lowercased()
        if result.exitCode == 0, lower.contains("logged in with grok.com") {
            return .signedIn(source: "grok.com")
        }
        if lower.contains("not logged in")
            || lower.contains("login required")
            || lower.contains("authentication required")
            || lower.contains("run `grok login")
            || lower.contains("run grok login") {
            return .signedOut
        }
        return .unavailable
    }

    static func loginCommand(cliURL: URL? = GrokCLIService.locateGrokCLI()) -> String? {
        guard let cliURL else { return nil }
        return "\(shellQuote(cliURL.path)) login --oauth"
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
