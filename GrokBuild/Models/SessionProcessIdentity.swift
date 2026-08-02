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
