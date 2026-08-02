import Foundation

enum RestoreDecisionReason: String, Codable, Equatable, Sendable {
    case savedSelectionVerified
    case savedSelectionLocalTranscript
    case workspaceMRUVerified
    case workspaceMRULocalTranscript
    case createdNewBecauseNoViableTab
    case repairedMissingWorkspace
    case refusedDivergedSelection
}

struct SessionRestoreCandidate: Equatable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let lastActivationOrdinal: UInt64
    let lastAccessed: Date
    let hasLocalTranscript: Bool
    let hasContent: Bool
    let hasVerifiedBinding: Bool
    let isDiverged: Bool
}

struct SessionRestoreInput: Equatable, Sendable {
    let workspaceID: UUID
    let savedSelectedSessionID: UUID?
    let workspaceWasRepaired: Bool
    let candidates: [SessionRestoreCandidate]
}

struct RestoreDecision: Equatable, Sendable {
    let selectedSessionID: UUID?
    let reason: RestoreDecisionReason
    let rejectedCandidateReasons: [UUID: String]
    let createdNewTab: Bool
    let deferBackendStart: Bool
}

/// Pure session-selection rules for launch restore and workspace switching.
enum SessionRestorePolicy {
    static func sessionHasPersistedContent(_ sessionID: UUID) -> Bool {
        SessionMessageStore.hasRestorableTranscript(for: sessionID)
    }

    static func sessionHasRestorableTranscript(hasUserMessages: Bool, sessionID: UUID) -> Bool {
        hasUserMessages || SessionMessageStore.hasRestorableTranscript(for: sessionID)
    }

    static func sessionHasContent(
        hasUserMessages: Bool,
        liveGrokSessionID: String?,
        savedGrokSessionID: String?,
        sessionID: UUID,
        hasPersistedContent: Bool? = nil
    ) -> Bool {
        hasUserMessages
            || liveGrokSessionID != nil
            || savedGrokSessionID != nil
            || (hasPersistedContent ?? sessionHasPersistedContent(sessionID))
    }

    /// Stable MRU: activation ordinal wins, wall-clock time is display/fallback data, and
    /// UUID order makes ties deterministic without consulting transcript size.
    static func recentSessionOrder(from records: [SavedSessionRecord]) -> [UUID] {
        records.sorted(by: isMoreRecent).map(\.id)
    }

    static func restoreDecision(input: SessionRestoreInput) -> RestoreDecision {
        let candidates = input.candidates
            .filter { $0.workspaceID == input.workspaceID }
            .sorted(by: isMoreRecent)
        var rejected: [UUID: String] = [:]

        if let savedID = input.savedSelectedSessionID,
           let selected = candidates.first(where: { $0.id == savedID }) {
            if selected.isDiverged {
                rejected[savedID] = "Saved selection has divergent continuity."
            } else if selected.hasVerifiedBinding {
                return RestoreDecision(
                    selectedSessionID: savedID,
                    reason: input.workspaceWasRepaired ? .repairedMissingWorkspace : .savedSelectionVerified,
                    rejectedCandidateReasons: rejected,
                    createdNewTab: false,
                    deferBackendStart: false
                )
            } else if selected.hasLocalTranscript {
                return RestoreDecision(
                    selectedSessionID: savedID,
                    reason: input.workspaceWasRepaired ? .repairedMissingWorkspace : .savedSelectionLocalTranscript,
                    rejectedCandidateReasons: rejected,
                    createdNewTab: false,
                    deferBackendStart: true
                )
            } else {
                rejected[savedID] = "Saved selection has no local transcript or verified binding."
            }
        }

        for candidate in candidates where !candidate.isDiverged {
            if candidate.hasVerifiedBinding {
                return RestoreDecision(
                    selectedSessionID: candidate.id,
                    reason: rejected.isEmpty ? .workspaceMRUVerified : .refusedDivergedSelection,
                    rejectedCandidateReasons: rejected,
                    createdNewTab: false,
                    deferBackendStart: false
                )
            }
            if candidate.hasLocalTranscript {
                return RestoreDecision(
                    selectedSessionID: candidate.id,
                    reason: rejected.isEmpty ? .workspaceMRULocalTranscript : .refusedDivergedSelection,
                    rejectedCandidateReasons: rejected,
                    createdNewTab: false,
                    deferBackendStart: true
                )
            }
            if candidate.hasContent {
                rejected[candidate.id] = "Content exists without a local transcript or verified binding."
            }
        }

        return RestoreDecision(
            selectedSessionID: nil,
            reason: rejected.values.contains(where: { $0.contains("divergent") })
                ? .refusedDivergedSelection
                : .createdNewBecauseNoViableTab,
            rejectedCandidateReasons: rejected,
            createdNewTab: true,
            deferBackendStart: true
        )
    }

    /// Pick the best already-open session for an interactive workspace switch. Unlike cold
    /// restore this may retain the current in-memory tab even before it is persisted.
    static func preferredSessionID(
        for workspaceID: UUID,
        saved: SessionLayoutSnapshot,
        liveSessionIDsInWorkspace: [UUID],
        currentSelectedSessionID: UUID?,
        currentSelectedWorkspaceID: UUID?,
        recentSessionOrder: [UUID],
        hasContent: (UUID) -> Bool
    ) -> UUID? {
        guard !liveSessionIDsInWorkspace.isEmpty else { return nil }
        let inWorkspace = Set(liveSessionIDsInWorkspace)

        if let currentSelectedSessionID,
           currentSelectedWorkspaceID == workspaceID,
           inWorkspace.contains(currentSelectedSessionID) {
            return currentSelectedSessionID
        }
        if let remembered = saved.selectedSessionIDByWorkspace[workspaceID],
           inWorkspace.contains(remembered), hasContent(remembered) {
            return remembered
        }
        if let savedID = saved.selectedSessionID,
           inWorkspace.contains(savedID), hasContent(savedID) {
            return savedID
        }
        for id in recentSessionOrder where inWorkspace.contains(id) && hasContent(id) {
            return id
        }
        return liveSessionIDsInWorkspace.first(where: hasContent)
            ?? liveSessionIDsInWorkspace.last
    }

    /// Compatibility wrapper for existing callers and focused tests. The decision remains pure:
    /// all transcript/content facts are precomputed once into candidates before comparison.
    static func restoreSelectedSessionID(
        saved: SessionLayoutSnapshot,
        workspaceID: UUID,
        liveSessionIDsInWorkspace: [UUID],
        hasTranscript: (UUID) -> Bool,
        hasContent: (UUID) -> Bool,
        preferredSessionID: (UUID) -> UUID?
    ) -> UUID? {
        let recordByID = Dictionary(uniqueKeysWithValues: saved.records.map { ($0.id, $0) })
        let candidates = liveSessionIDsInWorkspace.map { id -> SessionRestoreCandidate in
            let record = recordByID[id]
            return SessionRestoreCandidate(
                id: id,
                workspaceID: record?.workspaceID ?? workspaceID,
                lastActivationOrdinal: record?.lastActivationOrdinal ?? 0,
                lastAccessed: record?.lastAccessed ?? .distantPast,
                hasLocalTranscript: hasTranscript(id),
                hasContent: hasContent(id),
                hasVerifiedBinding: record?.backendBinding?.verification == .verified,
                isDiverged: false
            )
        }
        let remembered = saved.selectedSessionIDByWorkspace[workspaceID]
            ?? saved.selectedSessionID
            ?? preferredSessionID(workspaceID)
        return restoreDecision(
            input: SessionRestoreInput(
                workspaceID: workspaceID,
                savedSelectedSessionID: remembered,
                workspaceWasRepaired: false,
                candidates: candidates
            )
        ).selectedSessionID
    }

    private static func isMoreRecent(_ lhs: SavedSessionRecord, _ rhs: SavedSessionRecord) -> Bool {
        if lhs.lastActivationOrdinal != rhs.lastActivationOrdinal {
            return lhs.lastActivationOrdinal > rhs.lastActivationOrdinal
        }
        if lhs.lastAccessed != rhs.lastAccessed { return lhs.lastAccessed > rhs.lastAccessed }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func isMoreRecent(_ lhs: SessionRestoreCandidate, _ rhs: SessionRestoreCandidate) -> Bool {
        if lhs.lastActivationOrdinal != rhs.lastActivationOrdinal {
            return lhs.lastActivationOrdinal > rhs.lastActivationOrdinal
        }
        if lhs.lastAccessed != rhs.lastAccessed { return lhs.lastAccessed > rhs.lastAccessed }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
