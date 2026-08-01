import Foundation

/// Imports user/assistant text from grok CLI on-disk `chat_history.jsonl` files.
enum GrokSessionTranscriptImporter {
    static var grokHomeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".grok", isDirectory: true)

    static func chatHistoryURL(workspacePath: URL, grokSessionID: String) -> URL? {
        let trimmedID = grokSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }
        let candidates = encodedWorkspacePathCandidates(workspacePath).map { encoded in
            grokHomeDirectory
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent(encoded, isDirectory: true)
                .appendingPathComponent(trimmedID, isDirectory: true)
                .appendingPathComponent("chat_history.jsonl")
        }
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            ?? candidates.first
    }

    static func hasRecoverableTranscript(at url: URL) -> Bool {
        guard let messages = try? loadMessages(from: url) else { return false }
        return conversationMessageCount(messages) > 0
    }

    static func importMessages(from url: URL) -> [Message] {
        (try? loadMessages(from: url)) ?? []
    }

    /// One-shot legacy recovery for a populated tab whose durable backend id was already
    /// lost by an older build. Match normalized user prompts within this workspace only,
    /// inspect a bounded recent candidate set, and refuse to choose unless exactly one
    /// backend history agrees. This is never used as a polling path.
    static func uniqueSessionIDMatchingTranscript(
        workspacePath: URL,
        localMessages: [Message],
        maxCandidates: Int = 200
    ) -> String? {
        guard let continuationPrompt = normalizedUserPrompts(localMessages).last,
              maxCandidates > 0 else { return nil }

        let sessionRoot = grokHomeDirectory.appendingPathComponent("sessions", isDirectory: true)
        var candidateHistoryURLs: [URL] = []
        var seenPaths: Set<String> = []
        for encodedWorkspace in encodedWorkspacePathCandidates(workspacePath) {
            let workspaceRoot = sessionRoot.appendingPathComponent(encodedWorkspace, isDirectory: true)
            let sessionDirectories = (try? FileManager.default.contentsOfDirectory(
                at: workspaceRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for directory in sessionDirectories {
                let historyURL = directory.appendingPathComponent("chat_history.jsonl")
                guard seenPaths.insert(historyURL.path).inserted,
                      FileManager.default.fileExists(atPath: historyURL.path) else { continue }
                candidateHistoryURLs.append(historyURL)
            }
        }

        candidateHistoryURLs.sort { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            return leftDate > rightDate
        }

        var matches: [String] = []
        for historyURL in candidateHistoryURLs.prefix(maxCandidates) {
            let backendPrompts = normalizedUserPrompts(importMessages(from: historyURL))
            guard backendPrompts.contains(continuationPrompt) else { continue }
            matches.append(historyURL.deletingLastPathComponent().lastPathComponent)
            if matches.count > 1 { return nil }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func conversationMessageCount(_ messages: [Message]) -> Int {
        messages.filter { $0.role == .user || $0.role == .assistant }.count
    }

    private static func normalizedUserPrompts(_ messages: [Message]) -> [String] {
        messages.compactMap { message in
            guard message.role == .user else { return nil }
            return message.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
    }

    // MARK: - Path encoding

    /// grok stores sessions under `~/.grok/sessions/%2FUsers%2F…%2Fproject` (no trailing `%2F`).
    static func encodeWorkspacePath(_ workspacePath: URL) -> String {
        encodeWorkspacePath(workspacePath.path)
    }

    /// Grok keys session directories by the workspace spelling passed at launch. macOS
    /// canonicalizes `/private/tmp` to `/tmp`, so retain the raw spelling and probe only
    /// that bounded alias pair for the already-known backend id.
    private static func encodedWorkspacePathCandidates(_ workspacePath: URL) -> [String] {
        let rawPath = workspacePath.path
        let standardizedPath = workspacePath.standardizedFileURL.path
        let basePaths = [rawPath, standardizedPath]
        var paths = basePaths
        for path in basePaths {
            if path == "/tmp" || path.hasPrefix("/tmp/") {
                paths.append("/private" + path)
            } else if path == "/private/tmp" || path.hasPrefix("/private/tmp/") {
                paths.append(String(path.dropFirst("/private".count)))
            }
        }
        var seen: Set<String> = []
        return paths.compactMap { path in
            let encoded = encodeWorkspacePath(path)
            return seen.insert(encoded).inserted ? encoded : nil
        }
    }

    private static func encodeWorkspacePath(_ rawPath: String) -> String {
        var path = rawPath
        while path.hasSuffix("/"), path.count > 1 {
            path.removeLast()
        }
        let body = String(path.dropFirst()).replacingOccurrences(of: "/", with: "%2F")
        return "%2F" + body
    }

    // MARK: - JSONL parsing

    private static func loadMessages(from url: URL) throws -> [Message] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var messages: [Message] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = row["type"] as? String else { continue }

            switch type {
            case "user":
                // Grok records injected project instructions and system reminders as
                // user-shaped rows. They are runtime context, not transcript turns.
                guard row["synthetic_reason"] == nil else { continue }
                guard let content = extractUserText(from: row["content"]),
                      !content.isEmpty,
                      !isRuntimeContextOnly(content),
                      !isSyntheticSystemReminderOnly(content) else { continue }
                messages.append(Message(role: .user, content: content))
            case "assistant":
                // Assistant rows that carry tool calls are pre-tool narration/receipts,
                // not the settled parent synthesis. Tool activity already has its own UI.
                if let toolCalls = row["tool_calls"] as? [Any], !toolCalls.isEmpty {
                    continue
                }
                guard let content = extractAssistantText(from: row["content"]),
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                messages.append(Message(role: .assistant, content: stripThinkingTags(from: content)))
            default:
                continue
            }
        }
        return messages
    }

    private static func extractUserText(from value: Any?) -> String? {
        if let text = value as? String {
            return normalizeUserText(text)
        }
        guard let parts = value as? [[String: Any]] else { return nil }
        let joined = parts.compactMap { part -> String? in
            guard (part["type"] as? String) == "text" else { return nil }
            return part["text"] as? String
        }.joined(separator: "\n")
        let normalized = normalizeUserText(joined)
        return normalized.isEmpty ? nil : normalized
    }

    private static func extractAssistantText(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let parts = value as? [[String: Any]] {
            let joined = parts.compactMap { part -> String? in
                guard (part["type"] as? String) == "text" else { return nil }
                return part["text"] as? String
            }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func normalizeUserText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let query = extractTaggedContent(trimmed, tag: "user_query") {
            return query.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func extractTaggedContent(_ text: String, tag: String) -> String? {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        guard let start = text.range(of: open),
              let end = text.range(of: close, range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound])
    }

    private static func isSyntheticSystemReminderOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<system-reminder>")
            && trimmed.hasSuffix("</system-reminder>")
    }

    private static func isRuntimeContextOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<user_info>")
            && trimmed.contains("</user_info>")
            && !trimmed.contains("<user_query>")
    }

    private static func stripThinkingTags(from text: String) -> String {
        let openTag = "<" + "redacted_thinking" + ">"
        let closeTag = "</" + "redacted_thinking" + ">"
        var result = text
        while let start = result.range(of: openTag),
              let end = result.range(of: closeTag, range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
