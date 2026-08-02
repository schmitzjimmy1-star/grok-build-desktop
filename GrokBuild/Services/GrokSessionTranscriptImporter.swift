import Foundation

/// Imports user/assistant text from grok CLI on-disk `chat_history.jsonl` files.
enum GrokSessionTranscriptImporter {
    static let parserSchemaVersion = 1

    enum ImportedRowKind: String, Codable, Hashable, Sendable {
        case userTurn
        case rootFinal
        case workerOutput
        case assistantNonFinal
        case toolPreamble
        case synthetic
        case runtimeContext
        case unknown
    }

    enum ImportedParentRelationship: String, Codable, Hashable, Sendable {
        case root
        case child
        case unknown
    }

    enum ImportedAgentProvenance: String, Codable, Hashable, Sendable {
        case root
        case worker
        case unspecified
        case unknown
    }

    enum ImportedTerminalMarker: String, Codable, Hashable, Sendable {
        case explicitFinal
        case implicitFinal
        case notFinal
        case unknown
    }

    /// Provenance-rich intermediate row. Raw content stays only in the private Message
    /// value; diagnostics and candidate UI use counts, categorical evidence, and the
    /// optional keyed tag instead.
    struct ImportedRow: Hashable, Sendable {
        let backendSessionID: String
        let rowIndex: Int
        let role: MessageRole?
        let kind: ImportedRowKind
        let parentRelationship: ImportedParentRelationship
        let agentProvenance: ImportedAgentProvenance
        let agentName: String?
        let terminalMarker: ImportedTerminalMarker
        let opaqueContentTag: String?
        let isSynthetic: Bool
        let parserSchemaVersion: Int
        let modelID: String?
        let message: Message?
    }

    struct ImportedTranscript: Sendable {
        let backendSessionID: String
        let rows: [ImportedRow]

        /// Useful display rows retain explicitly identified worker output and the root
        /// final. Unknown/mixed rows remain quarantined in `rows` instead of being lost.
        var displayMessages: [Message] {
            rows.compactMap { row in
                switch row.kind {
                case .userTurn, .rootFinal, .workerOutput:
                    return row.message
                case .assistantNonFinal, .toolPreamble, .synthetic, .runtimeContext, .unknown:
                    return nil
                }
            }
        }

        /// Only authoritative root turns participate in backend identity proof.
        var identityMessages: [Message] {
            rows.compactMap { row in
                switch row.kind {
                case .userTurn, .rootFinal:
                    return row.message
                case .workerOutput, .assistantNonFinal, .toolPreamble,
                     .synthetic, .runtimeContext, .unknown:
                    return nil
                }
            }
        }

        var quarantinedRowCount: Int {
            rows.filter {
                $0.role == .assistant
                    && [.assistantNonFinal, .unknown].contains($0.kind)
            }.count
        }

        var hasQuarantinedIdentityRows: Bool { quarantinedRowCount > 0 }

        var modelID: String? {
            rows.reversed().compactMap(\.modelID).first
        }
    }

    struct BoundedImportLimits: Equatable, Sendable {
        let softByteLimit: Int
        let softConversationalRowLimit: Int
        let timeLimit: TimeInterval

        static let `default` = BoundedImportLimits(
            softByteLimit: 2 * 1024 * 1024,
            softConversationalRowLimit: 2_000,
            timeLimit: 5
        )
    }

    enum BoundedImportOutcome: Equatable, Sendable {
        case complete
        case missing
        case unreadable
        case incomplete
    }

    struct BoundedImportResult: Sendable {
        let transcript: ImportedTranscript
        let outcome: BoundedImportOutcome
        let bytesRead: Int
        let rowCount: Int
        /// Non-nil only after the soft byte/row bound was crossed. Downstream
        /// fingerprint work must finish inside the same deadline.
        let verificationDeadline: Date?

        var messages: [Message] { transcript.displayMessages }
    }

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
        guard let transcript = try? loadTranscript(from: url, key: nil) else { return false }
        return conversationMessageCount(transcript.identityMessages) > 0
    }

    static func importMessages(from url: URL) -> [Message] {
        importTranscript(from: url).displayMessages
    }

    static func importTranscript(
        from url: URL,
        backendSessionID: String? = nil,
        key: Data? = nil
    ) -> ImportedTranscript {
        (try? loadTranscript(
            from: url,
            backendSessionID: backendSessionID,
            key: key
        )) ?? ImportedTranscript(
            backendSessionID: backendSessionID ?? inferredBackendSessionID(from: url),
            rows: []
        )
    }

    /// Streams one exact backend history. Files at or below the normal bound are fully
    /// consumed; larger histories may continue only inside the bounded time window.
    /// Callers run this off the main actor and treat an unfinished result as unknown.
    static func importMessagesBounded(
        from url: URL,
        backendSessionID: String? = nil,
        key: Data? = nil,
        limits: BoundedImportLimits = .default
    ) -> BoundedImportResult {
        let resolvedBackendID = backendSessionID ?? inferredBackendSessionID(from: url)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BoundedImportResult(
                transcript: ImportedTranscript(backendSessionID: resolvedBackendID, rows: []),
                outcome: .missing, bytesRead: 0, rowCount: 0,
                verificationDeadline: nil
            )
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return BoundedImportResult(
                transcript: ImportedTranscript(backendSessionID: resolvedBackendID, rows: []),
                outcome: .unreadable, bytesRead: 0, rowCount: 0,
                verificationDeadline: nil
            )
        }
        defer { try? handle.close() }

        var buffer = Data()
        var rows: [ImportedRow] = []
        var bytesRead = 0
        var rowCount = 0
        var conversationalRowCount = 0
        var extendedDeadline: Date?

        func parseLine(_ line: Data) {
            guard !line.isEmpty,
                  let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                return
            }
            rowCount += 1
            let imported = importedRow(
                from: row,
                backendSessionID: resolvedBackendID,
                rowIndex: rowCount - 1,
                key: key
            )
            rows.append(imported)
            if imported.message != nil { conversationalRowCount += 1 }
        }

        do {
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                bytesRead += chunk.count
                buffer.append(chunk)

                while let newline = buffer.firstIndex(of: 0x0A) {
                    parseLine(Data(buffer[..<newline]))
                    buffer.removeSubrange(...newline)
                }

                if bytesRead > limits.softByteLimit
                    || conversationalRowCount > limits.softConversationalRowLimit {
                    if extendedDeadline == nil {
                        extendedDeadline = Date().addingTimeInterval(max(0, limits.timeLimit))
                    }
                    if Task<Never, Never>.isCancelled
                        || Date() >= (extendedDeadline ?? .distantPast) {
                        return BoundedImportResult(
                            transcript: ImportedTranscript(
                                backendSessionID: resolvedBackendID,
                                rows: rows
                            ),
                            outcome: .incomplete,
                            bytesRead: bytesRead,
                            rowCount: rowCount,
                            verificationDeadline: extendedDeadline
                        )
                    }
                }
            }
            if !buffer.isEmpty { parseLine(buffer) }
            return BoundedImportResult(
                transcript: ImportedTranscript(backendSessionID: resolvedBackendID, rows: rows),
                outcome: .complete,
                bytesRead: bytesRead,
                rowCount: rowCount,
                verificationDeadline: extendedDeadline
            )
        } catch {
            return BoundedImportResult(
                transcript: ImportedTranscript(backendSessionID: resolvedBackendID, rows: rows),
                outcome: .unreadable,
                bytesRead: bytesRead,
                rowCount: rowCount,
                verificationDeadline: extendedDeadline
            )
        }
    }

    /// Bounded history inventory for an explicit recovery review. Ordinary startup never
    /// calls this and the result is evidence only: it cannot mutate or manufacture a tab
    /// binding, even when one history shares a common final prompt.
    static func recoveryHistoryURLs(
        workspacePath: URL,
        maxCandidates: Int = 50
    ) -> [URL] {
        guard maxCandidates > 0 else { return [] }
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

        return Array(candidateHistoryURLs.prefix(maxCandidates))
    }

    static func conversationMessageCount(_ messages: [Message]) -> Int {
        messages.filter { $0.role == .user || $0.role == .assistant }.count
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

    private static func loadTranscript(
        from url: URL,
        backendSessionID: String? = nil,
        key: Data?
    ) throws -> ImportedTranscript {
        let text = try String(contentsOf: url, encoding: .utf8)
        let resolvedBackendID = backendSessionID ?? inferredBackendSessionID(from: url)
        var rows: [ImportedRow] = []
        for (rowIndex, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            rows.append(importedRow(
                from: row,
                backendSessionID: resolvedBackendID,
                rowIndex: rowIndex,
                key: key
            ))
        }
        return ImportedTranscript(backendSessionID: resolvedBackendID, rows: rows)
    }

    private static func importedRow(
        from row: [String: Any],
        backendSessionID: String,
        rowIndex: Int,
        key: Data?
    ) -> ImportedRow {
        let type = row["type"] as? String
        let modelID = row["model_id"] as? String
        let rawAgent = (row["agent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let agentName = rawAgent?.isEmpty == false ? rawAgent : nil
        let normalizedAgent = agentName?.lowercased()
        let hasParentField = row.keys.contains("parent_id")
        let parentValue = row["parent_id"]
        let hasParent: Bool = {
            guard let parentValue, !(parentValue is NSNull) else { return false }
            if let parent = parentValue as? String {
                return !parent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }()
        let explicitFinal = row["is_final"] as? Bool
        let toolCalls = row["tool_calls"] as? [Any] ?? []

        func makeMessage(
            role: MessageRole,
            content: String,
            source: TranscriptMessageProvenance.Source
        ) -> Message {
            let tag = key.map {
                VersionedOpaqueTag.transcriptMessageTag(
                    key: $0,
                    role: role.rawValue,
                    ordinal: rowIndex,
                    content: content
                )
            }
            return Message(
                role: role,
                content: content,
                provenance: TranscriptMessageProvenance(
                    source: source,
                    backendSessionID: backendSessionID,
                    rowIndex: rowIndex,
                    agent: agentName,
                    opaqueContentTag: tag
                )
            )
        }

        func result(
            role: MessageRole? = nil,
            kind: ImportedRowKind,
            parent: ImportedParentRelationship = .unknown,
            agent: ImportedAgentProvenance = .unspecified,
            terminal: ImportedTerminalMarker = .unknown,
            synthetic: Bool = false,
            message: Message? = nil
        ) -> ImportedRow {
            ImportedRow(
                backendSessionID: backendSessionID,
                rowIndex: rowIndex,
                role: role,
                kind: kind,
                parentRelationship: parent,
                agentProvenance: agent,
                agentName: agentName,
                terminalMarker: terminal,
                opaqueContentTag: message?.provenance?.opaqueContentTag,
                isSynthetic: synthetic,
                parserSchemaVersion: parserSchemaVersion,
                modelID: modelID,
                message: message
            )
        }

        switch type {
        case "system", "reasoning", "tool_call", "tool_result":
            return result(kind: .synthetic, synthetic: true)
        case "user":
            // Grok records injected project instructions and system reminders as
            // user-shaped rows. They are runtime context, not transcript turns.
            if row["synthetic_reason"] != nil {
                return result(role: .user, kind: .synthetic, synthetic: true)
            }
            guard let content = extractUserText(from: row["content"]), !content.isEmpty else {
                return result(role: .user, kind: .unknown)
            }
            if isRuntimeContextOnly(content) || isSyntheticSystemReminderOnly(content) {
                return result(role: .user, kind: .runtimeContext, synthetic: true)
            }
            return result(
                role: .user,
                kind: .userTurn,
                parent: .root,
                terminal: .notFinal,
                message: makeMessage(role: .user, content: content, source: .backendRoot)
            )
        case "assistant":
            // Assistant rows that carry tool calls are pre-tool narration/receipts,
            // not the settled parent synthesis. Tool activity already has its own UI.
            if !toolCalls.isEmpty {
                return result(
                    role: .assistant,
                    kind: .toolPreamble,
                    parent: hasParent ? .child : (hasParentField ? .root : .unknown),
                    agent: hasParent ? .worker : .unspecified,
                    terminal: .notFinal
                )
            }
            guard let content = extractAssistantText(from: row["content"]),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return result(role: .assistant, kind: .unknown)
            }
            let visibleContent = stripThinkingTags(from: content)
            let rootNames = Set(["root", "parent", "main"])
            let isWorker = hasParent
                || (normalizedAgent.map { !rootNames.contains($0) } ?? false)
            if isWorker {
                return result(
                    role: .assistant,
                    kind: .workerOutput,
                    parent: .child,
                    agent: .worker,
                    terminal: explicitFinal == true ? .explicitFinal : .unknown,
                    message: makeMessage(
                        role: .assistant,
                        content: visibleContent,
                        source: .backendWorker
                    )
                )
            }

            if explicitFinal == false {
                return result(
                    role: .assistant,
                    kind: .assistantNonFinal,
                    parent: hasParentField ? .root : .unknown,
                    agent: normalizedAgent.map { rootNames.contains($0) ? .root : .unknown } ?? .unspecified,
                    terminal: .notFinal,
                    message: makeMessage(
                        role: .assistant,
                        content: visibleContent,
                        source: .backendUnknown
                    )
                )
            }

            // Grok 0.2.118 root finals have no agent/parent/final keys; a tool-free
            // assistant row is the captured legacy terminal shape. Explicit root/final
            // metadata takes the same authoritative lane.
            let explicitRoot = explicitFinal == true
                || normalizedAgent.map(rootNames.contains) == true
                || (hasParentField && !hasParent)
            let legacyImplicitRoot = !hasParentField && agentName == nil && explicitFinal == nil
            if explicitRoot || legacyImplicitRoot {
                return result(
                    role: .assistant,
                    kind: .rootFinal,
                    parent: .root,
                    agent: explicitRoot ? .root : .unspecified,
                    terminal: explicitFinal == true ? .explicitFinal : .implicitFinal,
                    message: makeMessage(
                        role: .assistant,
                        content: visibleContent,
                        source: .backendRoot
                    )
                )
            }
            return result(
                role: .assistant,
                kind: .unknown,
                parent: .unknown,
                agent: .unknown,
                terminal: .unknown,
                message: makeMessage(
                    role: .assistant,
                    content: visibleContent,
                    source: .backendUnknown
                )
            )
        default:
            return result(kind: .unknown)
        }
    }

    private static func inferredBackendSessionID(from historyURL: URL) -> String {
        historyURL.deletingLastPathComponent().lastPathComponent
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
