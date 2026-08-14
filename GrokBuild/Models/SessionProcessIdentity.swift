import Foundation

enum SessionProcessLRUDecision: Equatable, Sendable {
    case noLiveProcess(preservedBackendID: String?)
    case evictVerified(preservedBackendID: String?)
    case evictWithoutAdoptingMismatchedReceipt(preservedBackendID: String?)

    var preservedBackendID: String? {
        switch self {
        case .noLiveProcess(let id), .evictVerified(let id),
             .evictWithoutAdoptingMismatchedReceipt(let id):
            return id
        }
    }
}

/// Prevents the four-process LRU from assigning a process/backend receipt to a
/// different local tab. A mismatch is stopped, but its identity is never adopted.
enum SessionProcessLRUPolicy {
    static func decision(
        expectedTabID: UUID,
        persistedBackendID: String?,
        activeProcessGeneration: UInt64?,
        launchReceipt: GrokLaunchReceipt?
    ) -> SessionProcessLRUDecision {
        guard let activeProcessGeneration else {
            return .noLiveProcess(preservedBackendID: persistedBackendID)
        }
        guard let launchReceipt,
              launchReceipt.localTabID == expectedTabID,
              launchReceipt.processGeneration == activeProcessGeneration,
              launchReceipt.backendSessionID == persistedBackendID else {
            return .evictWithoutAdoptingMismatchedReceipt(
                preservedBackendID: persistedBackendID
            )
        }
        return .evictVerified(preservedBackendID: persistedBackendID)
    }
}

enum SessionRuntimeProtectionReason: String, Equatable, Hashable, Sendable {
    case starting
    case busy
    case activeSchedule

    var displayName: String {
        switch self {
        case .starting: return "Agent starting"
        case .busy: return "Active turn"
        case .activeSchedule: return "Active schedule"
        }
    }
}

struct SessionRuntimeRetentionCandidate: Equatable, Sendable {
    let id: UUID
    let connectionState: GrokProcessState
    let hasLiveProcess: Bool
    let isSelected: Bool
    let lastActivationOrdinal: UInt64
    let hasAuthoritativeActiveSchedule: Bool
}

struct SessionRuntimeRetentionDecision: Equatable, Sendable {
    let retainedSessionIDs: Set<UUID>
    let evictionCandidateIDs: [UUID]
    let protectionReasonsBySessionID: [UUID: Set<SessionRuntimeProtectionReason>]
    let retainedLiveCount: Int
    let softCapExcess: Int

    var exceedsSoftCap: Bool { softCapExcess > 0 }
}

/// Pure ownership policy for the normal four-process window. Starting turns, active
/// turns, and exact live schedule leases may overflow the soft cap; ordinary idle
/// sessions outside the selected/MRU window remain eviction candidates.
enum SessionRuntimeRetentionPolicy {
    static func decision(
        candidates: [SessionRuntimeRetentionCandidate],
        normalCap: Int
    ) -> SessionRuntimeRetentionDecision {
        let boundedCap = max(0, normalCap)
        var retained: Set<UUID> = []
        var reasons: [UUID: Set<SessionRuntimeProtectionReason>] = [:]

        for candidate in candidates where candidate.hasLiveProcess {
            var candidateReasons: Set<SessionRuntimeProtectionReason> = []
            switch candidate.connectionState {
            case .starting:
                candidateReasons.insert(.starting)
            case .busy:
                candidateReasons.insert(.busy)
            case .idle, .ready, .failed:
                break
            }
            if candidate.hasAuthoritativeActiveSchedule {
                candidateReasons.insert(.activeSchedule)
            }
            if !candidateReasons.isEmpty {
                reasons[candidate.id] = candidateReasons
                retained.insert(candidate.id)
            }
        }

        // Protected runtimes do not consume an ordinary MRU slot. This is what
        // permits four idle sessions plus a selected scheduled session to remain
        // live while still bounding unprotected idle runtimes to `normalCap`.
        let ordinaryCandidates = candidates
            .filter { $0.hasLiveProcess && reasons[$0.id] == nil }
            .sorted { lhs, rhs in
                if lhs.isSelected != rhs.isSelected { return lhs.isSelected }
                if lhs.lastActivationOrdinal != rhs.lastActivationOrdinal {
                    return lhs.lastActivationOrdinal > rhs.lastActivationOrdinal
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        retained.formUnion(ordinaryCandidates.prefix(boundedCap).map(\.id))
        let evictionCandidates = candidates.compactMap { candidate in
            candidate.hasLiveProcess && !retained.contains(candidate.id) ? candidate.id : nil
        }

        let retainedLiveCount = retained.count
        return SessionRuntimeRetentionDecision(
            retainedSessionIDs: retained,
            evictionCandidateIDs: evictionCandidates,
            protectionReasonsBySessionID: reasons,
            retainedLiveCount: retainedLiveCount,
            softCapExcess: max(0, retainedLiveCount - boundedCap)
        )
    }
}
