import Foundation

enum MessageRole: String, Codable, Sendable {
    case user, assistant, system
}

/// Private transcript provenance retained when GrokBuild imports a backend history.
/// Ordinary live ACP messages predate this model and intentionally decode with `nil`.
/// The metadata lets display reconciliation keep useful worker output without ever
/// promoting that output to root-conversation identity evidence.
struct TranscriptMessageProvenance: Codable, Sendable, Hashable {
    enum Source: String, Codable, Sendable {
        case backendRoot
        case backendWorker
        case backendUnknown
    }

    let source: Source
    let backendSessionID: String
    let rowIndex: Int
    let agent: String?
    let opaqueContentTag: String?
}

/// Durable, secret-free task checkpoint projected from one authoritative
/// `RunEvidenceSnapshot` at the ACP settlement boundary. It lives inside the
/// existing local assistant-turn trace so quit/relaunch can still explain the
/// task contract without inventing a second transcript or scraping grok's
/// private session storage.
struct AssistantTurnCheckpoint: Codable, Sendable, Hashable {
    struct PlanStep: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let status: String
    }

    struct Worker: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let status: String
        let owningPlanStepID: String?
        let childBackendSessionID: String?
    }

    let objective: String?
    let outcome: String
    let plan: [PlanStep]
    let workers: [Worker]
    let localTabID: UUID?
    let parentBackendSessionID: String?
    let processGeneration: UInt64?
    let requestedToolFamilies: [String]
    let modelID: String?
    let nextAction: String
    let requiresRecoveryAction: Bool
    let isSettled: Bool

    init(
        snapshot: RunEvidenceSnapshot,
        requestedToolFamilies: [String]
    ) {
        objective = snapshot.goalSummary
        outcome = snapshot.outcome.displayName
        plan = snapshot.plan.map {
            PlanStep(id: $0.id, title: $0.title, status: $0.status)
        }
        workers = snapshot.workers.map {
            Worker(
                id: $0.id,
                title: $0.title,
                status: $0.status,
                owningPlanStepID: $0.owningPlanStepID,
                childBackendSessionID: $0.childID
            )
        }
        localTabID = snapshot.binding.localTabID
        parentBackendSessionID = snapshot.binding.backendSessionID
        processGeneration = snapshot.binding.processGeneration
        self.requestedToolFamilies = Array(Set(requestedToolFamilies))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        modelID = snapshot.process.model
        nextAction = snapshot.nextAction
        requiresRecoveryAction = snapshot.continuity.requiresRecoveryAction
        isSettled = snapshot.binding.isSettled
    }
}

/// Safe, local presentation receipts for one assistant turn. The summary is
/// the public ACP reasoning summary, never hidden chain-of-thought. Tool rows
/// retain only redacted labels, terminal state, and an authoritative MCP server
/// name when the backend reported one. This travels with GrokBuild's local
/// transcript and never rewrites Grok's backend history.
struct AssistantTurnTrace: Codable, Sendable, Hashable {
    struct Tool: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let kind: String?
        let status: String
        let mcpServerName: String?
        let mcpReceiptRole: MCPToolReceiptRole?
        let qualifiedToolName: String?
        let discoveredQualifiedToolNames: [String]

        init(
            id: String,
            title: String,
            kind: String? = nil,
            status: String,
            mcpServerName: String?,
            mcpReceiptRole: MCPToolReceiptRole? = nil,
            qualifiedToolName: String? = nil,
            discoveredQualifiedToolNames: [String] = []
        ) {
            self.id = id
            self.title = title
            self.kind = kind
            self.status = status
            self.mcpServerName = mcpServerName
            self.mcpReceiptRole = mcpReceiptRole
            self.qualifiedToolName = qualifiedToolName
            self.discoveredQualifiedToolNames = discoveredQualifiedToolNames
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, kind, status, mcpServerName, mcpReceiptRole
            case qualifiedToolName, discoveredQualifiedToolNames
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            title = try values.decode(String.self, forKey: .title)
            kind = try values.decodeIfPresent(String.self, forKey: .kind)
            status = try values.decode(String.self, forKey: .status)
            mcpServerName = try values.decodeIfPresent(String.self, forKey: .mcpServerName)
            mcpReceiptRole = try values.decodeIfPresent(MCPToolReceiptRole.self, forKey: .mcpReceiptRole)
            qualifiedToolName = try values.decodeIfPresent(String.self, forKey: .qualifiedToolName)
            discoveredQualifiedToolNames = try values.decodeIfPresent(
                [String].self,
                forKey: .discoveredQualifiedToolNames
            ) ?? []
        }
    }

    let reasoningSummaryChunks: [String]
    let thinkingDuration: TimeInterval?
    let tools: [Tool]
    /// The confirmed effective model that produced this turn, as a display name.
    /// Stamped at turn settlement from the generation-bound execution receipt;
    /// `nil` on transcripts recorded before the field existed and on turns whose
    /// model was never exactly confirmed — the header then falls back to the
    /// neutral "Build agent" label rather than guessing.
    var modelDisplayName: String? = nil
    /// The custom subagent role that ran the whole session's turn, when one was
    /// explicitly selected. Empty/default agent stays `nil`.
    var agentName: String? = nil
    /// Slice 10 durable task contract. Missing on legacy transcripts.
    var checkpoint: AssistantTurnCheckpoint? = nil

    var hasContent: Bool {
        !reasoningSummaryChunks.isEmpty || thinkingDuration != nil || !tools.isEmpty || checkpoint != nil
    }
}

struct Message: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    let provenance: TranscriptMessageProvenance?
    var assistantTrace: AssistantTurnTrace?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        provenance: TranscriptMessageProvenance? = nil,
        assistantTrace: AssistantTurnTrace? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.provenance = provenance
        self.assistantTrace = assistantTrace
    }
}

enum AssistantDiffPresentation {
    static func isExample(language: String?) -> Bool {
        guard let language else { return false }
        return ["diff", "patch"].contains(language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
