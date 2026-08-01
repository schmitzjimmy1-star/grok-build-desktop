import Foundation

/// Persists chat transcript per live session tab (keyed by `LiveSession.id`).
/// Grok keeps conversation state server-side; this restores what the UI showed last time.
enum SessionMessageStore {
    private static let key = "GrokBuild.sessionMessages.v1"

    static func messages(for sessionID: UUID) -> [Message] {
        GrokBuildPerformance.measure(.selectedTranscriptLoad) {
            guard let data = blob(for: sessionID) else { return [] }
            return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
        }
    }

    static func save(_ messages: [Message], for sessionID: UUID) {
        saveAll([sessionID: messages])
    }

    /// Persist the exact result of a role/turn/content reconciliation. This is the only
    /// path allowed to shrink a transcript, so ordinary delayed UI saves retain the
    /// never-shrink protection while duplicate authoritative finals can be removed.
    static func replaceAfterAuthoritativeReconciliation(
        _ messages: [Message],
        for sessionID: UUID
    ) {
        GrokBuildPerformance.measure(.transcriptWrite) {
            var map = loadMap()
            let persistable = messages.filter { shouldPersist($0) }
            if persistable.isEmpty {
                map.removeValue(forKey: sessionID.uuidString)
            } else if let data = try? JSONEncoder().encode(persistable) {
                map[sessionID.uuidString] = data
            }
            UserDefaults.standard.set(map, forKey: key)
        }
    }

    /// Merge and persist several sessions' transcripts with one defaults
    /// fetch and one write. The per-session `save` used to load the full
    /// multi-session map twice and rewrite it once per call, which made
    /// `persistSessionLayout` O(sessions x total transcript bytes).
    static func saveAll(_ messagesBySession: [UUID: [Message]]) {
        guard !messagesBySession.isEmpty else { return }
        GrokBuildPerformance.measure(.transcriptWrite) {
            var map = loadMap()
            let decoder = JSONDecoder()
            let encoder = JSONEncoder()
            for (sessionID, messages) in messagesBySession {
                let mapKey = sessionID.uuidString
                let existing = map[mapKey].flatMap { try? decoder.decode([Message].self, from: $0) } ?? []
                let persistable = messages.filter { shouldPersist($0) }
                let merged = mergeTranscripts(existing: existing, incoming: persistable)
                if merged.isEmpty {
                    map.removeValue(forKey: mapKey)
                } else if let data = try? encoder.encode(merged) {
                    map[mapKey] = data
                }
            }
            UserDefaults.standard.set(map, forKey: key)
        }
    }

    /// Never drop a longer on-disk transcript when memory is temporarily empty or partial.
    private static func mergeTranscripts(existing: [Message], incoming: [Message]) -> [Message] {
        guard !existing.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return existing }
        if incoming.count >= existing.count {
            var result = incoming
            for index in 0..<min(existing.count, incoming.count)
            where existing[index].role == incoming[index].role {
                let oldText = existing[index].content
                let newText = incoming[index].content
                if oldText.count > newText.count && oldText.hasPrefix(newText) {
                    // A delayed partial UI save must not shorten a completion-time
                    // backend reconciliation with the same role/turn position.
                    result[index] = existing[index]
                }
            }
            return result
        }

        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for message in incoming {
            byID[message.id] = message
        }
        var merged: [Message] = []
        var seen: Set<UUID> = []
        for message in existing {
            merged.append(byID[message.id] ?? message)
            seen.insert(message.id)
        }
        for message in incoming where !seen.contains(message.id) {
            merged.append(message)
        }
        return merged
    }

    static func messageCount(for sessionID: UUID) -> Int {
        messages(for: sessionID).filter { $0.role == .user || $0.role == .assistant }.count
    }

    static var storedTranscriptCount: Int {
        loadMap().count
    }

    static func remove(for sessionID: UUID) {
        GrokBuildPerformance.measure(.transcriptWrite) {
            var map = loadMap()
            map.removeValue(forKey: sessionID.uuidString)
            UserDefaults.standard.set(map, forKey: key)
        }
    }

    /// Legacy resume notes added before message persistence — drop on load.
    static func isLegacyResumeNote(_ message: Message) -> Bool {
        guard message.role == .system else { return false }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("Resumed session ") && text.hasSuffix(".")
    }

    /// System note shown when grok `session/load` fell back to `session/new`.
    static func isStaleSessionFallbackNote(_ message: Message) -> Bool {
        guard message.role == .system else { return false }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("Previous grok session expired")
    }

    static func hasRestorableTranscript(for sessionID: UUID) -> Bool {
        messages(for: sessionID).contains { message in
            guard message.role == .user || message.role == .assistant else { return false }
            if message.role == .assistant,
               message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            return true
        }
    }

    /// True when local storage has no user/assistant transcript to show.
    static func needsTranscriptRecovery(_ messages: [Message]) -> Bool {
        !messages.contains { message in
            guard message.role == .user || message.role == .assistant else { return false }
            if message.role == .assistant,
               message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            return true
        }
    }

    private static func shouldPersist(_ message: Message) -> Bool {
        if isLegacyResumeNote(message) { return false }
        if isStaleSessionFallbackNote(message) { return false }
        if message.role == .assistant,
           message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    private static func blob(for sessionID: UUID) -> Data? {
        loadMap()[sessionID.uuidString]
    }

    private static func loadMap() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
    }
}
