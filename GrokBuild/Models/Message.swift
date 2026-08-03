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

struct Message: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    let provenance: TranscriptMessageProvenance?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        provenance: TranscriptMessageProvenance? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.provenance = provenance
    }
}

enum AssistantDiffPresentation {
    static func isExample(language: String?) -> Bool {
        guard let language else { return false }
        return ["diff", "patch"].contains(language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
