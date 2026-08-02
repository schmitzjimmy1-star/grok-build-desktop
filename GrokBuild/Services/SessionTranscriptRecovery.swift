import Foundation

enum SessionContinuityStatus: String, Codable, Hashable, Sendable {
    case localOnly
    case backendOnly
    case verifying
    case verified
    case diverged
    case compositeSuspected
    case backendMissing
    case recoveryForked
    case verificationIncomplete
}

enum SessionContinuityReason: String, Codable, Hashable, Sendable {
    case noBackendBinding
    case verificationPending
    case exactMatch
    case localVerifiedPrefix
    case backendOnly
    case contentMismatch
    case nonContiguousBackendEvidence
    case backendHistoryMissing
    case backendHistoryUnreadable
    case syntheticOnlyHistory
    case boundedReadIncomplete
    case integrityKeyUnavailable
    case mixedOrUnknownProvenance
    case recoveryForked
}

struct SessionContinuityReceipt: Codable, Hashable, Sendable {
    let status: SessionContinuityStatus
    let reason: SessionContinuityReason
    let normalizationVersion: Int
    let authenticationSchemaVersion: Int
    let localMessageCount: Int
    let backendMessageCount: Int
    let matchingPrefixCount: Int
    /// Keyed, versioned HMACs. These stay in the authenticated local lifecycle
    /// snapshot and are never included in logs or exported diagnostics.
    let localTranscriptTag: String?
    let backendTranscriptTag: String?
    let verifiedAt: Date

    static let localOnly = SessionContinuityReceipt(
        status: .localOnly,
        reason: .noBackendBinding,
        normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
        authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
        localMessageCount: 0,
        backendMessageCount: 0,
        matchingPrefixCount: 0,
        localTranscriptTag: nil,
        backendTranscriptTag: nil,
        verifiedAt: .distantPast
    )
}

struct SessionContinuityVerification: Sendable {
    let receipt: SessionContinuityReceipt
    let backendMessages: [Message]
}

struct SessionRecoveryCandidate: Identifiable, Hashable, Sendable {
    var id: String { backendID }

    let backendID: String
    let workspaceName: String
    let modelID: String?
    let lastActivity: Date
    let matchingTurnCount: Int
    let mismatchCount: Int
    let localMessageCount: Int
    let backendMessageCount: Int
    let relationship: SessionContinuityStatus
    let reason: SessionContinuityReason
    let quarantinedRowCount: Int

    var isRelinkable: Bool {
        matchingTurnCount > 0
            && quarantinedRowCount == 0
            && relationship == .verified
    }

    var redactedBackendID: String { "…\(backendID.suffix(8))" }
}

enum SessionSendGateDecision: Equatable, Sendable {
    case allowLocalBackendCreation
    case allowVerifiedBackend
    case allowRecoveryFork
    case block
}

enum SessionSendGate {
    static func decision(for status: SessionContinuityStatus) -> SessionSendGateDecision {
        switch status {
        case .localOnly:
            return .allowLocalBackendCreation
        case .verified, .backendOnly:
            return .allowVerifiedBackend
        case .recoveryForked:
            return .allowRecoveryFork
        case .verifying, .diverged, .compositeSuspected, .backendMissing,
             .verificationIncomplete:
            return .block
        }
    }
}

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

    /// Explicit, bounded recovery review. The returned candidates are evidence only;
    /// this function never mutates a binding and ordinary startup never invokes it.
    static func recoveryCandidates(
        workspacePath: URL,
        workspaceName: String,
        localMessages: [Message],
        key: Data,
        maxCandidates: Int = 50
    ) -> [SessionRecoveryCandidate] {
        guard !key.isEmpty else { return [] }
        let localIdentity = identityMessages(localMessages)
        var candidates: [SessionRecoveryCandidate] = []
        let reviewDeadline = Date().addingTimeInterval(5)

        for historyURL in GrokSessionTranscriptImporter.recoveryHistoryURLs(
            workspacePath: workspacePath,
            maxCandidates: maxCandidates
        ) {
            guard !Task<Never, Never>.isCancelled, Date() < reviewDeadline else { break }
            let backendID = historyURL.deletingLastPathComponent().lastPathComponent
            let remaining = max(0, reviewDeadline.timeIntervalSinceNow)
            let imported = GrokSessionTranscriptImporter.importMessagesBounded(
                from: historyURL,
                backendSessionID: backendID,
                key: key,
                limits: .init(
                    softByteLimit: GrokSessionTranscriptImporter.BoundedImportLimits.default.softByteLimit,
                    softConversationalRowLimit: GrokSessionTranscriptImporter.BoundedImportLimits.default.softConversationalRowLimit,
                    timeLimit: remaining
                )
            )
            guard imported.outcome == .complete,
                  !imported.transcript.identityMessages.isEmpty else { continue }

            let receipt: SessionContinuityReceipt
            if imported.transcript.hasQuarantinedIdentityRows {
                receipt = failedContinuityVerification(
                    localMessages: localIdentity,
                    status: .compositeSuspected,
                    reason: .mixedOrUnknownProvenance,
                    backendMessages: imported.transcript.identityMessages
                ).receipt
            } else {
                receipt = verifyContinuity(
                    localMessages: localIdentity,
                    backendMessages: imported.transcript.identityMessages,
                    key: key
                )
            }
            let sharedPrompts = matchingUserPromptCount(
                local: localIdentity,
                backend: imported.transcript.identityMessages
            )
            let matchingTurns = matchingCompleteTurnCount(
                local: localIdentity,
                backend: imported.transcript.identityMessages
            )
            let relinkable = receipt.status == .verified
                && matchingTurns > 0
                && imported.transcript.quarantinedRowCount == 0
            guard sharedPrompts > 0 || relinkable else { continue }

            let lastActivity = (try? historyURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate ?? .distantPast
            let mismatchCount = max(
                0,
                receipt.localMessageCount + receipt.backendMessageCount
                    - (2 * receipt.matchingPrefixCount)
            )
            candidates.append(SessionRecoveryCandidate(
                backendID: backendID,
                workspaceName: workspaceName,
                modelID: imported.transcript.modelID,
                lastActivity: lastActivity,
                matchingTurnCount: matchingTurns,
                mismatchCount: mismatchCount,
                localMessageCount: receipt.localMessageCount,
                backendMessageCount: receipt.backendMessageCount,
                relationship: receipt.status,
                reason: receipt.reason,
                quarantinedRowCount: imported.transcript.quarantinedRowCount
            ))
        }

        return candidates.sorted { lhs, rhs in
            if lhs.isRelinkable != rhs.isRelinkable { return lhs.isRelinkable }
            if lhs.matchingTurnCount != rhs.matchingTurnCount {
                return lhs.matchingTurnCount > rhs.matchingTurnCount
            }
            if lhs.mismatchCount != rhs.mismatchCount {
                return lhs.mismatchCount < rhs.mismatchCount
            }
            if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
            return lhs.backendID < rhs.backendID
        }
    }

    static func verifyContinuity(
        localMessages: [Message],
        backendHistoryURL: URL,
        key: Data,
        limits: GrokSessionTranscriptImporter.BoundedImportLimits = .default
    ) -> SessionContinuityVerification {
        let imported = GrokSessionTranscriptImporter.importMessagesBounded(
            from: backendHistoryURL,
            key: key,
            limits: limits
        )
        switch imported.outcome {
        case .missing:
            return failedContinuityVerification(
                localMessages: localMessages,
                status: .backendMissing,
                reason: .backendHistoryMissing
            )
        case .unreadable:
            return failedContinuityVerification(
                localMessages: localMessages,
                status: .backendMissing,
                reason: .backendHistoryUnreadable
            )
        case .incomplete:
            return failedContinuityVerification(
                localMessages: localMessages,
                status: .verificationIncomplete,
                reason: .boundedReadIncomplete,
                backendMessages: imported.messages
            )
        case .complete:
            guard !imported.transcript.identityMessages.isEmpty else {
                return failedContinuityVerification(
                    localMessages: localMessages,
                    status: .backendMissing,
                    reason: .syntheticOnlyHistory
                )
            }
            guard !imported.transcript.hasQuarantinedIdentityRows else {
                return failedContinuityVerification(
                    localMessages: localMessages,
                    status: .compositeSuspected,
                    reason: .mixedOrUnknownProvenance,
                    backendMessages: imported.transcript.displayMessages
                )
            }
            return SessionContinuityVerification(
                receipt: verifyContinuity(
                    localMessages: localMessages,
                    backendMessages: imported.transcript.identityMessages,
                    key: key,
                    deadline: imported.verificationDeadline
                ),
                backendMessages: imported.transcript.displayMessages
            )
        }
    }

    static func verifyContinuity(
        localMessages: [Message],
        backendMessages: [Message],
        key: Data
    ) -> SessionContinuityReceipt {
        verifyContinuity(
            localMessages: localMessages,
            backendMessages: backendMessages,
            key: key,
            deadline: nil
        )
    }

    private static func verifyContinuity(
        localMessages: [Message],
        backendMessages: [Message],
        key: Data,
        deadline: Date?
    ) -> SessionContinuityReceipt {
        let local = identityMessages(localMessages)
        let backend = conversationalMessages(backendMessages)
        guard !key.isEmpty else {
            return receipt(
                status: .verificationIncomplete,
                reason: .integrityKeyUnavailable,
                local: local,
                backend: backend,
                matchingPrefixCount: 0,
                key: nil,
                localOrderedTags: nil,
                backendOrderedTags: nil
            )
        }
        guard let localOrdered = orderedTags(local, key: key, deadline: deadline),
              let backendOrdered = orderedTags(backend, key: key, deadline: deadline) else {
            return receipt(
                status: .verificationIncomplete,
                reason: .boundedReadIncomplete,
                local: local,
                backend: backend,
                matchingPrefixCount: 0,
                key: key,
                localOrderedTags: nil,
                backendOrderedTags: nil
            )
        }
        guard !local.isEmpty else {
            return receipt(
                status: .backendOnly,
                reason: .backendOnly,
                local: local,
                backend: backend,
                matchingPrefixCount: 0,
                key: key,
                localOrderedTags: localOrdered,
                backendOrderedTags: backendOrdered
            )
        }
        guard !backend.isEmpty else {
            return receipt(
                status: .backendMissing,
                reason: .syntheticOnlyHistory,
                local: local,
                backend: backend,
                matchingPrefixCount: 0,
                key: key,
                localOrderedTags: localOrdered,
                backendOrderedTags: backendOrdered
            )
        }

        let prefixCount = matchingPrefixCount(localOrdered, backendOrdered)
        if prefixCount == localOrdered.count {
            return receipt(
                status: .verified,
                reason: localOrdered.count == backendOrdered.count ? .exactMatch : .localVerifiedPrefix,
                local: local,
                backend: backend,
                matchingPrefixCount: prefixCount,
                key: key,
                localOrderedTags: localOrdered,
                backendOrderedTags: backendOrdered
            )
        }

        guard let localContent = contentIdentityTags(local, key: key, deadline: deadline),
              let backendContent = contentIdentityTags(backend, key: key, deadline: deadline) else {
            return receipt(
                status: .verificationIncomplete,
                reason: .boundedReadIncomplete,
                local: local,
                backend: backend,
                matchingPrefixCount: prefixCount,
                key: key,
                localOrderedTags: nil,
                backendOrderedTags: nil
            )
        }
        let localEvidence = Set(localContent.dropFirst(prefixCount))
        let backendEvidence = Set(backendContent.dropFirst(prefixCount))
        let composite = localEvidence.intersection(backendEvidence).count >= 2
        return receipt(
            status: composite ? .compositeSuspected : .diverged,
            reason: composite ? .nonContiguousBackendEvidence : .contentMismatch,
            local: local,
            backend: backend,
            matchingPrefixCount: prefixCount,
            key: key,
            localOrderedTags: localOrdered,
            backendOrderedTags: backendOrdered
        )
    }

    private static func failedContinuityVerification(
        localMessages: [Message],
        status: SessionContinuityStatus,
        reason: SessionContinuityReason,
        backendMessages: [Message] = []
    ) -> SessionContinuityVerification {
        let local = identityMessages(localMessages)
        let backend = conversationalMessages(backendMessages)
        return SessionContinuityVerification(
            receipt: SessionContinuityReceipt(
                status: status,
                reason: reason,
                normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
                authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
                localMessageCount: local.count,
                backendMessageCount: backend.count,
                matchingPrefixCount: 0,
                localTranscriptTag: nil,
                backendTranscriptTag: nil,
                verifiedAt: Date()
            ),
            backendMessages: backendMessages
        )
    }

    private static func receipt(
        status: SessionContinuityStatus,
        reason: SessionContinuityReason,
        local: [Message],
        backend: [Message],
        matchingPrefixCount: Int,
        key: Data?,
        localOrderedTags: [String]?,
        backendOrderedTags: [String]?
    ) -> SessionContinuityReceipt {
        SessionContinuityReceipt(
            status: status,
            reason: reason,
            normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
            authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
            localMessageCount: local.count,
            backendMessageCount: backend.count,
            matchingPrefixCount: matchingPrefixCount,
            localTranscriptTag: localOrderedTags.flatMap { tags in
                key.map { transcriptSequenceTag(from: tags, key: $0) }
            },
            backendTranscriptTag: backendOrderedTags.flatMap { tags in
                key.map { transcriptSequenceTag(from: tags, key: $0) }
            },
            verifiedAt: Date()
        )
    }

    private static func conversationalMessages(_ messages: [Message]) -> [Message] {
        messages.filter {
            ($0.role == .user || $0.role == .assistant)
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func identityMessages(_ messages: [Message]) -> [Message] {
        conversationalMessages(messages).filter { message in
            switch message.provenance?.source {
            case .backendWorker, .backendUnknown:
                return false
            case .backendRoot, nil:
                return true
            }
        }
    }

    private static func orderedTags(
        _ messages: [Message],
        key: Data,
        deadline: Date?
    ) -> [String]? {
        var tags: [String] = []
        tags.reserveCapacity(messages.count)
        for (index, message) in messages.enumerated() {
            if index.isMultiple(of: 64),
               let deadline,
               Task<Never, Never>.isCancelled || Date() >= deadline {
                return nil
            }
            tags.append(VersionedOpaqueTag.transcriptMessageTag(
                key: key,
                role: message.role.rawValue,
                ordinal: index,
                content: message.content
            ))
        }
        return deadline.map({ Date() >= $0 }) == true ? nil : tags
    }

    private static func contentIdentityTags(
        _ messages: [Message],
        key: Data,
        deadline: Date?
    ) -> [String]? {
        var tags: [String] = []
        tags.reserveCapacity(messages.count)
        for (index, message) in messages.enumerated() {
            if index.isMultiple(of: 64),
               let deadline,
               Task<Never, Never>.isCancelled || Date() >= deadline {
                return nil
            }
            tags.append(VersionedOpaqueTag.transcriptMessageTag(
                key: key,
                role: message.role.rawValue,
                ordinal: 0,
                content: message.content
            ))
        }
        return deadline.map({ Date() >= $0 }) == true ? nil : tags
    }

    static func transcriptSequenceTag(_ messages: [Message], key: Data) -> String {
        transcriptSequenceTag(
            from: orderedTags(messages, key: key, deadline: nil) ?? [],
            key: key
        )
    }

    private static func transcriptSequenceTag(from orderedTags: [String], key: Data) -> String {
        let payload = Data(orderedTags.joined(separator: "\u{1F}").utf8)
        return VersionedOpaqueTag.authenticationCode(
            key: key,
            domain: "transcript-sequence",
            schemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
            payload: payload
        )
    }

    private static func matchingPrefixCount(_ lhs: [String], _ rhs: [String]) -> Int {
        var count = 0
        while count < lhs.count, count < rhs.count, lhs[count] == rhs[count] {
            count += 1
        }
        return count
    }

    private static func matchingUserPromptCount(local: [Message], backend: [Message]) -> Int {
        func promptOccurrences(_ messages: [Message]) -> [String: Int] {
            var occurrences: [String: Int] = [:]
            for message in messages where message.role == .user {
                let normalized = SessionTranscriptReconciler.normalizedContent(message.content)
                guard !normalized.isEmpty else { continue }
                occurrences[normalized, default: 0] += 1
            }
            return occurrences
        }
        let localPrompts = promptOccurrences(local)
        let backendPrompts = promptOccurrences(backend)
        return localPrompts.reduce(into: 0) { count, pair in
            count += min(pair.value, backendPrompts[pair.key, default: 0])
        }
    }

    private static func matchingCompleteTurnCount(local: [Message], backend: [Message]) -> Int {
        func completeTurns(_ messages: [Message]) -> [String: Int] {
            var turns: [String: Int] = [:]
            var prompt: String?
            var assistants: [String] = []

            func finish() {
                guard let prompt, let final = assistants.last else { return }
                let key = "\(prompt)\u{1F}\(final)"
                turns[key, default: 0] += 1
            }

            for message in messages {
                switch message.role {
                case .user:
                    finish()
                    prompt = SessionTranscriptReconciler.normalizedContent(message.content)
                    assistants = []
                case .assistant:
                    if prompt != nil {
                        assistants.append(
                            SessionTranscriptReconciler.normalizedContent(message.content)
                        )
                    }
                case .system:
                    continue
                }
            }
            finish()
            return turns
        }

        let localTurns = completeTurns(local)
        let backendTurns = completeTurns(backend)
        return localTurns.reduce(into: 0) { count, pair in
            count += min(pair.value, backendTurns[pair.key, default: 0])
        }
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
        GrokBuildPerformance.measure(.continuityVerification) {
            guard let grokSessionID,
                  let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
                      workspacePath: workspacePath,
                      grokSessionID: grokSessionID
                  ),
                  GrokSessionTranscriptImporter.hasRecoverableTranscript(at: historyURL) else {
                return nil
            }

            let imported = GrokSessionTranscriptImporter.importTranscript(
                from: historyURL,
                backendSessionID: grokSessionID
            )
            guard imported.backendSessionID == grokSessionID,
                  !imported.hasQuarantinedIdentityRows else {
                return nil
            }
            let reconciled = SessionTranscriptReconciler.reconcile(
                local: currentMessages,
                authoritative: imported.displayMessages
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
                authoritative: imported.identityMessages
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
