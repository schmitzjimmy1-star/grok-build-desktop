import Foundation

enum ModelExecutionStatus: String, Codable, Hashable, Sendable {
    case unknown
    case requested
    case pending
    case confirmed
    case rejected
}

enum ModelExecutionFailure: String, Codable, Hashable, Sendable {
    case incompatibleAgent
    case timedOut
    case rejected
    case processStopped
    case unknown
}

/// Exact identity for one launch-model or `session/set_model` request. Async
/// completions may mutate visible state only while this complete tuple still
/// matches the pending receipt.
struct ModelRequestIdentity: Codable, Hashable, Sendable {
    let localTabID: UUID?
    let backendSessionID: String?
    let processGeneration: UInt64
    let requestID: UUID
}

/// Credential-free model truth retained with the tab's v3 lifecycle record.
/// A receipt from an older process remains useful historical evidence, but UI
/// callers must compare its generation with the active launch receipt before
/// describing it as live.
struct ModelExecutionState: Codable, Hashable, Sendable {
    var status: ModelExecutionStatus
    var requestedModelID: String?
    var effectiveModelID: String?
    var identity: ModelRequestIdentity?
    var failure: ModelExecutionFailure?
    var updatedAt: Date?

    static let unknown = ModelExecutionState(
        status: .unknown,
        requestedModelID: nil,
        effectiveModelID: nil,
        identity: nil,
        failure: nil,
        updatedAt: nil
    )

    static func savedIntent(modelID: String, at date: Date = Date()) -> ModelExecutionState {
        ModelExecutionState(
            status: .requested,
            requestedModelID: modelID,
            effectiveModelID: nil,
            identity: nil,
            failure: nil,
            updatedAt: date
        )
    }

    var isPending: Bool { status == .pending }
}

/// Pure reducer for generation-bound model state. The identity match is the
/// stale-callback gate: wrong-tab, wrong-backend, old-process, duplicate, and
/// out-of-order completions leave the current receipt byte-for-byte unchanged.
enum ModelExecutionReducer {
    static func launch(
        requestedModelID: String?,
        identity: ModelRequestIdentity,
        at date: Date = Date()
    ) -> ModelExecutionState {
        let requested = normalized(requestedModelID)
        return ModelExecutionState(
            status: requested == nil ? .unknown : .requested,
            requestedModelID: requested,
            effectiveModelID: nil,
            identity: identity,
            failure: nil,
            updatedAt: date
        )
    }

    static func beginRequest(
        modelID: String,
        identity: ModelRequestIdentity,
        preserving state: ModelExecutionState,
        at date: Date = Date()
    ) -> ModelExecutionState {
        ModelExecutionState(
            status: .pending,
            requestedModelID: normalized(modelID),
            effectiveModelID: state.identity?.processGeneration == identity.processGeneration
                ? state.effectiveModelID
                : nil,
            identity: identity,
            failure: nil,
            updatedAt: date
        )
    }

    @discardableResult
    static func rebindBackend(
        _ backendSessionID: String?,
        identity: ModelRequestIdentity,
        state: inout ModelExecutionState
    ) -> ModelRequestIdentity? {
        guard state.identity == identity else { return nil }
        let rebound = ModelRequestIdentity(
            localTabID: identity.localTabID,
            backendSessionID: normalized(backendSessionID),
            processGeneration: identity.processGeneration,
            requestID: identity.requestID
        )
        state.identity = rebound
        return rebound
    }

    @discardableResult
    static func confirm(
        effectiveModelID: String,
        identity: ModelRequestIdentity,
        state: inout ModelExecutionState,
        at date: Date = Date()
    ) -> Bool {
        guard state.identity == identity,
              let effective = normalized(effectiveModelID) else { return false }
        state.status = .confirmed
        state.effectiveModelID = effective
        state.failure = nil
        state.updatedAt = date
        return true
    }

    /// ACP accepted the write but did not expose the effective model. That is a
    /// request receipt, never confirmation.
    @discardableResult
    static func acceptWithoutEffectiveModel(
        identity: ModelRequestIdentity,
        state: inout ModelExecutionState,
        at date: Date = Date()
    ) -> Bool {
        guard state.identity == identity else { return false }
        state.status = state.requestedModelID == nil ? .unknown : .requested
        state.failure = nil
        state.updatedAt = date
        return true
    }

    @discardableResult
    static func reject(
        failure: ModelExecutionFailure,
        identity: ModelRequestIdentity,
        state: inout ModelExecutionState,
        at date: Date = Date()
    ) -> Bool {
        guard state.identity == identity else { return false }
        state.status = .rejected
        state.failure = failure
        state.updatedAt = date
        return true
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
