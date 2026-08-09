import Foundation

enum MCPServerLifecycle: String, Sendable, Equatable {
    case connecting
    case ready
    case degraded
    case failed
    case disabled
    case stopped

    var displayName: String {
        switch self {
        case .connecting: return "Connecting"
        case .ready: return "Process ready"
        case .degraded: return "Degraded"
        case .failed: return "Failed"
        case .disabled: return "Disabled"
        case .stopped: return "Stopped"
        }
    }
}

/// Secret-free, generation-local evidence for one configured MCP server.
/// `ready` means ACP accepted the session and the bounded MCP startup barrier
/// elapsed. It proves process lifecycle only: no tool inventory, capability
/// discovery, or current-turn use is implied.
struct MCPServerStatus: Identifiable, Sendable, Equatable {
    let name: String
    let state: MCPServerLifecycle
    let reason: String?
    let evidence: String

    var id: String { name }

    var accessibilitySummary: String {
        let suffix = reason.map { " — \($0)" } ?? ""
        return "\(name): \(state.displayName)\(suffix)"
    }
}

/// Keeps the first billable prompt behind the initial stdio MCP handshake.
///
/// ACP can report a newly-created session before Grok's MCP children have
/// completed their own `initialize`/`tools/list` exchange. There is no stable
/// readiness notification in the installed CLI contract, so this is a small,
/// cancellable settle barrier rather than a claim of protocol-level health.
enum MCPReadinessPolicy {
    /// The current CLI normally completes the bundled MCP set in about 1.1s.
    /// Leave a little headroom without making sessions feel hung.
    static let settleMilliseconds = 1_500

    static let connectingEvidence = "Launch requested; waiting for the ACP session and bounded MCP startup barrier."
    static let readyEvidence = "ACP session established; bounded MCP startup barrier elapsed. Tool inventory and use remain unproven."
    static let stoppedEvidence = "The owning Grok process is stopped."

    static func connectingStatuses(for servers: [MCPServerConfig]) -> [MCPServerStatus] {
        statuses(
            for: servers.map(\.name),
            state: .connecting,
            reason: nil,
            evidence: connectingEvidence
        )
    }

    static func readyStatuses(for servers: [MCPServerConfig]) -> [MCPServerStatus] {
        statuses(
            for: servers.map(\.name),
            state: .ready,
            reason: nil,
            evidence: readyEvidence
        )
    }

    static func failedStatuses(
        for servers: [MCPServerConfig],
        reason: String? = "ACP startup failed before MCP readiness."
    ) -> [MCPServerStatus] {
        failedStatuses(for: servers.map(\.name), reason: reason)
    }

    static func failedStatuses(
        for names: [String],
        reason: String? = "ACP startup failed before MCP readiness."
    ) -> [MCPServerStatus] {
        statuses(
            for: names,
            state: .failed,
            reason: reason,
            evidence: "The current process generation did not reach the ready boundary."
        )
    }

    static func stoppedStatuses(for names: [String]) -> [MCPServerStatus] {
        statuses(
            for: names,
            state: .stopped,
            reason: nil,
            evidence: stoppedEvidence
        )
    }

    private static func statuses(
        for names: [String],
        state: MCPServerLifecycle,
        reason: String?,
        evidence: String
    ) -> [MCPServerStatus] {
        names.map {
            MCPServerStatus(name: $0, state: state, reason: reason, evidence: evidence)
        }
    }

    static func waitForInitialMCPSet(_ servers: [MCPServerConfig]) async throws {
        guard !servers.isEmpty else { return }
        try await Task.sleep(for: .milliseconds(settleMilliseconds))
    }
}
