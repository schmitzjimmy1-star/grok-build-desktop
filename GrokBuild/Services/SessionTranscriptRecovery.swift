import Foundation

/// Reconciles GrokBuild tabs with one known grok CLI `chat_history.jsonl`.
///
/// Imported message UUIDs are intentionally not treated as identity: grok history does
/// not store GrokBuild's streaming UUIDs. Stable identity is the normalized user prompt,
/// its occurrence number, assistant role, and its ordinal inside that logical turn.
enum SessionTranscriptRecovery {
    struct Result {
        let messages: [Message]
        let changed: Bool
        let authoritativeTailAssistantID: UUID?
    }

    /// Returns reconciled messages when recovery changed the transcript; `nil` otherwise.
    /// This is safe for empty, partial, and already-complete transcripts and is idempotent.
    static func recoverIfNeeded(
        sessionID: UUID,
        grokSessionID: String?,
        workspacePath: URL,
        currentMessages: [Message]
    ) -> [Message]? {
        guard let result = reconcile(
            sessionID: sessionID,
            grokSessionID: grokSessionID,
            workspacePath: workspacePath,
            currentMessages: currentMessages
        ), result.changed else {
            return nil
        }
        return result.messages
    }

    /// Reconcile and also report whether the backend already committed a terminal
    /// assistant answer. Completion handling uses that receipt to suppress a late ACP
    /// copy of the same final answer.
    static func reconcile(
        sessionID: UUID,
        grokSessionID: String?,
        workspacePath: URL,
        currentMessages: [Message]
    ) -> Result? {
        guard let grokSessionID,
              let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
                  workspacePath: workspacePath,
                  grokSessionID: grokSessionID
              ),
              GrokSessionTranscriptImporter.hasRecoverableTranscript(at: historyURL) else {
            return nil
        }

        let imported = GrokSessionTranscriptImporter.importMessages(from: historyURL)
        let reconciled = SessionTranscriptReconciler.reconcile(
            local: currentMessages,
            authoritative: imported
        )
        let changed = SessionTranscriptReconciler.contentSignature(reconciled)
            != SessionTranscriptReconciler.contentSignature(currentMessages)
        if changed {
            SessionMessageStore.replaceAfterAuthoritativeReconciliation(
                reconciled,
                for: sessionID
            )
        }

        let authoritativeTail = SessionTranscriptReconciler.authoritativeTailAssistantContent(
            local: reconciled,
            authoritative: imported
        )
        let authoritativeTailAssistantID = authoritativeTail.flatMap { tail in
            let normalizedTail = SessionTranscriptReconciler.normalizedContent(tail)
            return reconciled.last(where: {
                $0.role == .assistant
                    && SessionTranscriptReconciler.normalizedContent($0.content) == normalizedTail
            })?.id
        }
        return Result(
            messages: reconciled,
            changed: changed,
            authoritativeTailAssistantID: authoritativeTailAssistantID
        )
    }
}

enum SessionTranscriptReconciler {
    private struct TurnKey: Hashable {
        let prompt: String
        let occurrence: Int
    }

    private struct Turn {
        let key: TurnKey
        let userIndex: Int
        let assistantIndices: [Int]
    }

    static func reconcile(local: [Message], authoritative: [Message]) -> [Message] {
        let authoritativeTurns = turns(in: authoritative)
        guard !authoritativeTurns.isEmpty else { return local }

        let initialLocalKeys = Set(turns(in: local).map(\.key))
        let lastInitiallyMatchedAuthoritativeIndex = authoritativeTurns.lastIndex {
            initialLocalKeys.contains($0.key)
        } ?? -1

        var result = local
        for (authoritativeIndex, authoritativeTurn) in authoritativeTurns.enumerated() {
            let currentLocalTurns = turns(in: result)
            if let localTurn = currentLocalTurns.first(where: { $0.key == authoritativeTurn.key }) {
                reconcileAssistants(
                    in: &result,
                    localTurn: localTurn,
                    authoritative: authoritative,
                    authoritativeTurn: authoritativeTurn
                )
            } else if authoritativeIndex > lastInitiallyMatchedAuthoritativeIndex {
                // Only import an unmatched authoritative suffix. A divergent/missing
                // historical turn must never displace newer local work.
                result.append(authoritative[authoritativeTurn.userIndex])
                for index in authoritativeTurn.assistantIndices {
                    result.append(authoritative[index])
                }
            }
        }
        return result
    }

    static func contentSignature(_ messages: [Message]) -> [String] {
        messages.map { "\($0.role.rawValue)\u{1F}\($0.content)" }
    }

    static func normalizedContent(_ text: String) -> String {
        normalized(text)
    }

    static func authoritativeTailAssistantContent(
        local: [Message],
        authoritative: [Message]
    ) -> String? {
        guard let localTurn = turns(in: local).last,
              let authoritativeTurn = turns(in: authoritative).last,
              localTurn.key == authoritativeTurn.key,
              let finalIndex = authoritativeTurn.assistantIndices.last else {
            return nil
        }
        return authoritative[finalIndex].content
    }

    private static func reconcileAssistants(
        in result: inout [Message],
        localTurn: Turn,
        authoritative: [Message],
        authoritativeTurn: Turn
    ) {
        for (ordinal, authoritativeIndex) in authoritativeTurn.assistantIndices.enumerated() {
            let authoritativeMessage = authoritative[authoritativeIndex]
            let authoritativeText = normalized(authoritativeMessage.content)

            let refreshedTurn = turns(in: result).first { $0.key == localTurn.key } ?? localTurn
            let localAssistantMessages = refreshedTurn.assistantIndices.map { result[$0] }
            let equivalentIndices = refreshedTurn.assistantIndices.filter { index in
                let localText = normalized(result[index].content)
                return localText == authoritativeText
                    || whitespaceFingerprint(localText) == whitespaceFingerprint(authoritativeText)
            }
            if let retainedIndex = equivalentIndices.first {
                // ACP chunk boundaries can omit a newline that the durable history later
                // restores. Keep the original streaming UUID, adopt authoritative spacing,
                // and collapse any completion-time copy of the same final.
                result[retainedIndex].content = authoritativeMessage.content
                for duplicateIndex in equivalentIndices.dropFirst().reversed() {
                    result.remove(at: duplicateIndex)
                }
                continue
            }
            if localAssistantMessages.contains(where: {
                normalized($0.content).contains(authoritativeText)
            }) {
                continue
            }

            if ordinal < refreshedTurn.assistantIndices.count {
                let localIndex = refreshedTurn.assistantIndices[ordinal]
                let localText = normalized(result[localIndex].content)
                if authoritativeText.hasPrefix(localText) {
                    // Extend the original streaming message in place so its UUID and
                    // timestamp remain stable across repeated reconciliation.
                    result[localIndex].content = authoritativeMessage.content
                    continue
                }
                // Divergent local text may be worker activity or newer UI state. Preserve
                // it and add the settled backend synthesis as the next assistant result.
            }

            let insertionIndex = nextUserIndex(after: refreshedTurn.userIndex, in: result)
                ?? result.endIndex
            result.insert(authoritativeMessage, at: insertionIndex)
        }
    }

    private static func turns(in messages: [Message]) -> [Turn] {
        var occurrences: [String: Int] = [:]
        var result: [Turn] = []
        var currentUserIndex: Int?
        var currentKey: TurnKey?
        var assistantIndices: [Int] = []

        func finishCurrentTurn() {
            if let currentUserIndex, let currentKey {
                result.append(Turn(
                    key: currentKey,
                    userIndex: currentUserIndex,
                    assistantIndices: assistantIndices
                ))
            }
        }

        for (index, message) in messages.enumerated() {
            switch message.role {
            case .user:
                finishCurrentTurn()
                let prompt = normalized(message.content)
                let occurrence = occurrences[prompt, default: 0]
                occurrences[prompt] = occurrence + 1
                currentUserIndex = index
                currentKey = TurnKey(prompt: prompt, occurrence: occurrence)
                assistantIndices = []
            case .assistant:
                if currentUserIndex != nil,
                   !normalized(message.content).isEmpty {
                    assistantIndices.append(index)
                }
            case .system:
                continue
            }
        }
        finishCurrentTurn()
        return result
    }

    private static func nextUserIndex(after userIndex: Int, in messages: [Message]) -> Int? {
        guard userIndex + 1 < messages.count else { return nil }
        return messages[(userIndex + 1)...].firstIndex { $0.role == .user }
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func whitespaceFingerprint(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace })
    }
}
