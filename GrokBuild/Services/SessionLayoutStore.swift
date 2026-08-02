import Foundation

enum TabModelIntent: Hashable, Sendable {
    case inheritProjectDefault
    case explicit(String)
    /// v2 persisted the resolved model for every tab, so a non-nil legacy value cannot
    /// prove that the user explicitly overrode inheritance.
    case legacyUnknown(String)

    var modelID: String? {
        switch self {
        case .inheritProjectDefault: return nil
        case .explicit(let id), .legacyUnknown(let id): return id
        }
    }
}

extension TabModelIntent: Codable {
    private enum CodingKeys: String, CodingKey { case kind, id }
    private enum Kind: String, Codable { case inheritProjectDefault, explicit, legacyUnknown }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .inheritProjectDefault:
            self = .inheritProjectDefault
        case .explicit:
            self = .explicit(try container.decode(String.self, forKey: .id))
        case .legacyUnknown:
            self = .legacyUnknown(try container.decode(String.self, forKey: .id))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inheritProjectDefault:
            try container.encode(Kind.inheritProjectDefault, forKey: .kind)
        case .explicit(let id):
            try container.encode(Kind.explicit, forKey: .kind)
            try container.encode(id, forKey: .id)
        case .legacyUnknown(let id):
            try container.encode(Kind.legacyUnknown, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }
}

enum TabAgentIntent: Hashable, Sendable {
    case inheritGlobalDefault
    case explicit(String)

    var agentID: String? {
        switch self {
        case .inheritGlobalDefault: return nil
        case .explicit(let id): return id
        }
    }
}

extension TabAgentIntent: Codable {
    private enum CodingKeys: String, CodingKey { case kind, id }
    private enum Kind: String, Codable { case inheritGlobalDefault, explicit }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .inheritGlobalDefault:
            self = .inheritGlobalDefault
        case .explicit:
            self = .explicit(try container.decode(String.self, forKey: .id))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inheritGlobalDefault:
            try container.encode(Kind.inheritGlobalDefault, forKey: .kind)
        case .explicit(let id):
            try container.encode(Kind.explicit, forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }
}

enum SessionBackendBindingOrigin: String, Codable, Hashable, Sendable {
    case legacyV2
    case runtime
    case restored
    case recoveryFork
}

enum SessionBackendBindingVerification: String, Codable, Hashable, Sendable {
    case unverified
    case verified
    case failed
}

struct SessionBackendBinding: Codable, Hashable, Sendable {
    var backendID: String
    var origin: SessionBackendBindingOrigin
    var predecessorBackendID: String?
    var verification: SessionBackendBindingVerification
    var continuityReceipt: SessionContinuityReceipt? = nil
}

enum SessionForkLedgerReason: String, Codable, Hashable, Sendable {
    case localOnlyStart
    case resumeFallback
    case explicitContinueAsNew
    case explicitFreshStart
    case explicitBackendFork
    case explicitRelink
}

struct SessionForkLedgerEntry: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let localSessionID: UUID
    let predecessorBackendID: String?
    let successorBackendID: String
    let reason: SessionForkLedgerReason
    let createdAt: Date
    let localMessageCountAtFork: Int
    /// Versioned keyed HMAC of the local transcript at the fork boundary.
    let transcriptTag: String?

    func localMessagesForBackendVerification(_ messages: [Message]) -> [Message] {
        switch reason {
        case .localOnlyStart, .resumeFallback, .explicitContinueAsNew:
            return Array(messages.dropFirst(min(localMessageCountAtFork, messages.count)))
        case .explicitFreshStart, .explicitBackendFork, .explicitRelink:
            return messages
        }
    }
}

enum SessionPendingRecoveryAction: String, Codable, Hashable, Sendable {
    case continueAsNew
}

/// A durable explicit recovery choice made before a successor backend exists. The
/// authenticated v3 snapshot carries this boundary across quit/relaunch; the first
/// subsequent send creates the backend and converts it into a fork-ledger entry.
struct SessionPendingRecoveryIntent: Codable, Hashable, Sendable {
    let action: SessionPendingRecoveryAction
    let predecessorBackendID: String
    let chosenAt: Date
    let localMessageCountAtChoice: Int
    let transcriptTag: String?
}

struct SavedSessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let workspaceID: UUID
    var backendBinding: SessionBackendBinding?
    var title: String?
    var modelIntent: TabModelIntent
    var modelExecutionState: ModelExecutionState
    var agentIntent: TabAgentIntent
    var lastAccessed: Date
    /// Stable MRU tie-breaker. Only an intentional tab activation increments it.
    var lastActivationOrdinal: UInt64
    var transcriptGeneration: UInt64
    var transcriptStorageVersion: Int
    var forkLedgerReference: String?
    var pendingRecoveryIntent: SessionPendingRecoveryIntent?

    var grokSessionID: String? {
        get { backendBinding?.backendID }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                backendBinding = nil
                return
            }
            if backendBinding?.backendID == trimmed { return }
            backendBinding = SessionBackendBinding(
                backendID: trimmed,
                origin: .runtime,
                predecessorBackendID: backendBinding?.backendID,
                verification: .unverified
            )
        }
    }

    /// Compatibility accessors for call sites that have not yet moved to the intent reducer.
    /// New persistence always encodes the explicit intent fields, never these aliases.
    var model: String? {
        get { modelIntent.modelID }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            modelIntent = trimmed.isEmpty ? .inheritProjectDefault : .explicit(trimmed)
        }
    }

    var agent: String? {
        get { agentIntent.agentID }
        set {
            guard let newValue else {
                agentIntent = .inheritGlobalDefault
                return
            }
            agentIntent = .explicit(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    init(
        id: UUID,
        workspaceID: UUID,
        grokSessionID: String? = nil,
        title: String? = nil,
        model: String? = nil,
        modelExecutionState: ModelExecutionState = .unknown,
        agent: String? = nil,
        lastAccessed: Date,
        lastActivationOrdinal: UInt64 = 0,
        transcriptGeneration: UInt64 = 0,
        transcriptStorageVersion: Int = 1,
        forkLedgerReference: String? = nil,
        pendingRecoveryIntent: SessionPendingRecoveryIntent? = nil
    ) {
        self.init(
            id: id,
            workspaceID: workspaceID,
            backendBinding: grokSessionID.map {
                SessionBackendBinding(
                    backendID: $0,
                    origin: .runtime,
                    predecessorBackendID: nil,
                    verification: .unverified
                )
            },
            title: title,
            modelIntent: model.map(TabModelIntent.explicit) ?? .inheritProjectDefault,
            modelExecutionState: modelExecutionState,
            agentIntent: agent.map(TabAgentIntent.explicit) ?? .inheritGlobalDefault,
            lastAccessed: lastAccessed,
            lastActivationOrdinal: lastActivationOrdinal,
            transcriptGeneration: transcriptGeneration,
            transcriptStorageVersion: transcriptStorageVersion,
            forkLedgerReference: forkLedgerReference,
            pendingRecoveryIntent: pendingRecoveryIntent
        )
    }

    init(
        id: UUID,
        workspaceID: UUID,
        backendBinding: SessionBackendBinding?,
        title: String?,
        modelIntent: TabModelIntent,
        modelExecutionState: ModelExecutionState = .unknown,
        agentIntent: TabAgentIntent,
        lastAccessed: Date,
        lastActivationOrdinal: UInt64,
        transcriptGeneration: UInt64 = 0,
        transcriptStorageVersion: Int = 1,
        forkLedgerReference: String? = nil,
        pendingRecoveryIntent: SessionPendingRecoveryIntent? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.backendBinding = backendBinding
        self.title = title
        self.modelIntent = modelIntent
        self.modelExecutionState = modelExecutionState
        self.agentIntent = agentIntent
        self.lastAccessed = lastAccessed
        self.lastActivationOrdinal = lastActivationOrdinal
        self.transcriptGeneration = transcriptGeneration
        self.transcriptStorageVersion = transcriptStorageVersion
        self.forkLedgerReference = forkLedgerReference
        self.pendingRecoveryIntent = pendingRecoveryIntent
    }

    private enum CodingKeys: String, CodingKey {
        case id, workspaceID, backendBinding, title, modelIntent, modelExecutionState, agentIntent
        case lastAccessed, lastActivationOrdinal, transcriptGeneration
        case transcriptStorageVersion, forkLedgerReference, pendingRecoveryIntent
        // Defensive aliases for an uncommitted early v3 candidate. Authoritative v2 uses
        // LegacySavedSessionRecordV2 below.
        case model, agent, grokSessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        if let decoded = try container.decodeIfPresent(SessionBackendBinding.self, forKey: .backendBinding) {
            backendBinding = decoded
        } else if let legacyID = try container.decodeIfPresent(String.self, forKey: .grokSessionID) {
            backendBinding = SessionBackendBinding(
                backendID: legacyID,
                origin: .legacyV2,
                predecessorBackendID: nil,
                verification: .unverified
            )
        } else {
            backendBinding = nil
        }
        title = try container.decodeIfPresent(String.self, forKey: .title)
        if let decoded = try container.decodeIfPresent(TabModelIntent.self, forKey: .modelIntent) {
            modelIntent = decoded
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .model) {
            modelIntent = .legacyUnknown(legacy)
        } else {
            modelIntent = .inheritProjectDefault
        }
        modelExecutionState = try container.decodeIfPresent(
            ModelExecutionState.self,
            forKey: .modelExecutionState
        ) ?? .unknown
        if let decoded = try container.decodeIfPresent(TabAgentIntent.self, forKey: .agentIntent) {
            agentIntent = decoded
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .agent) {
            agentIntent = .explicit(legacy)
        } else {
            agentIntent = .inheritGlobalDefault
        }
        lastAccessed = try container.decode(Date.self, forKey: .lastAccessed)
        lastActivationOrdinal = try container.decodeIfPresent(UInt64.self, forKey: .lastActivationOrdinal) ?? 0
        transcriptGeneration = try container.decodeIfPresent(UInt64.self, forKey: .transcriptGeneration) ?? 0
        transcriptStorageVersion = try container.decodeIfPresent(Int.self, forKey: .transcriptStorageVersion) ?? 1
        forkLedgerReference = try container.decodeIfPresent(String.self, forKey: .forkLedgerReference)
        pendingRecoveryIntent = try container.decodeIfPresent(
            SessionPendingRecoveryIntent.self,
            forKey: .pendingRecoveryIntent
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encodeIfPresent(backendBinding, forKey: .backendBinding)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(modelIntent, forKey: .modelIntent)
        try container.encode(modelExecutionState, forKey: .modelExecutionState)
        try container.encode(agentIntent, forKey: .agentIntent)
        try container.encode(lastAccessed, forKey: .lastAccessed)
        try container.encode(lastActivationOrdinal, forKey: .lastActivationOrdinal)
        try container.encode(transcriptGeneration, forKey: .transcriptGeneration)
        try container.encode(transcriptStorageVersion, forKey: .transcriptStorageVersion)
        try container.encodeIfPresent(forkLedgerReference, forKey: .forkLedgerReference)
        try container.encodeIfPresent(pendingRecoveryIntent, forKey: .pendingRecoveryIntent)
    }
}

enum SessionTabModelPolicy {
    static func resolvedModel(
        intent: TabModelIntent,
        workspaceDefault: String?,
        appDefault: String
    ) -> String {
        resolvedModel(
            tabModel: intent.modelID,
            workspaceDefault: workspaceDefault,
            appDefault: appDefault
        )
    }

    /// Pick the model for a tab without mutating its saved intent.
    static func resolvedModel(
        tabModel: String?,
        workspaceDefault: String?,
        appDefault: String
    ) -> String {
        for candidate in [tabModel, workspaceDefault, appDefault] {
            if let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !candidate.isEmpty {
                return candidate
            }
        }
        return appDefault
    }
}

enum SessionIdentityPersistencePolicy {
    static func shouldPersistChangedSessionID(_ sessionID: String?) -> Bool {
        guard let sessionID else { return false }
        return !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SessionLayoutSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var records: [SavedSessionRecord]
    var sessionOrderByWorkspace: [UUID: [UUID]]
    var selectedSessionID: UUID?
    var selectedWorkspaceID: UUID?
    var selectedSessionIDByWorkspace: [UUID: UUID]
    var expandedSessionWorkspaceIDs: Set<UUID>
    var hiddenSessionWorkspaceIDs: Set<UUID>
    var activationCounter: UInt64
    var forkLedger: [SessionForkLedgerEntry]

    init(
        records: [SavedSessionRecord],
        sessionOrderByWorkspace: [UUID: [UUID]],
        selectedSessionID: UUID?,
        selectedWorkspaceID: UUID?,
        selectedSessionIDByWorkspace: [UUID: UUID] = [:],
        expandedSessionWorkspaceIDs: Set<UUID> = [],
        hiddenSessionWorkspaceIDs: Set<UUID> = [],
        activationCounter: UInt64? = nil,
        forkLedger: [SessionForkLedgerEntry] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.records = records
        self.sessionOrderByWorkspace = sessionOrderByWorkspace
        self.selectedSessionID = selectedSessionID
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedSessionIDByWorkspace = selectedSessionIDByWorkspace
        self.expandedSessionWorkspaceIDs = expandedSessionWorkspaceIDs
        self.hiddenSessionWorkspaceIDs = hiddenSessionWorkspaceIDs
        self.activationCounter = activationCounter ?? records.map(\.lastActivationOrdinal).max() ?? 0
        self.forkLedger = forkLedger
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, records, sessionOrderByWorkspace, selectedSessionID
        case selectedWorkspaceID, selectedSessionIDByWorkspace
        case expandedSessionWorkspaceIDs, hiddenSessionWorkspaceIDs, activationCounter
        case forkLedger
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        records = try container.decode([SavedSessionRecord].self, forKey: .records)
        sessionOrderByWorkspace = try container.decode([UUID: [UUID]].self, forKey: .sessionOrderByWorkspace)
        selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
        selectedWorkspaceID = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceID)
        selectedSessionIDByWorkspace = try container.decodeIfPresent([UUID: UUID].self, forKey: .selectedSessionIDByWorkspace) ?? [:]
        expandedSessionWorkspaceIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .expandedSessionWorkspaceIDs) ?? []
        hiddenSessionWorkspaceIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .hiddenSessionWorkspaceIDs) ?? []
        activationCounter = try container.decodeIfPresent(UInt64.self, forKey: .activationCounter)
            ?? records.map(\.lastActivationOrdinal).max() ?? 0
        forkLedger = try container.decodeIfPresent([SessionForkLedgerEntry].self, forKey: .forkLedger) ?? []
    }
}

struct LegacySavedSessionRecordV2: Codable, Hashable {
    let id: UUID
    let workspaceID: UUID
    var grokSessionID: String?
    var title: String?
    var model: String?
    var agent: String?
    var lastAccessed: Date
}

struct LegacySessionLayoutSnapshotV2: Codable {
    var records: [LegacySavedSessionRecordV2]
    var sessionOrderByWorkspace: [UUID: [UUID]]
    var selectedSessionID: UUID?
    var selectedWorkspaceID: UUID?
    var selectedSessionIDByWorkspace: [UUID: UUID]
    var expandedSessionWorkspaceIDs: Set<UUID>
    var hiddenSessionWorkspaceIDs: Set<UUID>

    private enum CodingKeys: String, CodingKey {
        case records, sessionOrderByWorkspace, selectedSessionID, selectedWorkspaceID
        case selectedSessionIDByWorkspace, expandedSessionWorkspaceIDs, hiddenSessionWorkspaceIDs
    }

    init(
        records: [LegacySavedSessionRecordV2],
        sessionOrderByWorkspace: [UUID: [UUID]],
        selectedSessionID: UUID?,
        selectedWorkspaceID: UUID?,
        selectedSessionIDByWorkspace: [UUID: UUID] = [:],
        expandedSessionWorkspaceIDs: Set<UUID> = [],
        hiddenSessionWorkspaceIDs: Set<UUID> = []
    ) {
        self.records = records
        self.sessionOrderByWorkspace = sessionOrderByWorkspace
        self.selectedSessionID = selectedSessionID
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedSessionIDByWorkspace = selectedSessionIDByWorkspace
        self.expandedSessionWorkspaceIDs = expandedSessionWorkspaceIDs
        self.hiddenSessionWorkspaceIDs = hiddenSessionWorkspaceIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decode([LegacySavedSessionRecordV2].self, forKey: .records)
        sessionOrderByWorkspace = try container.decode([UUID: [UUID]].self, forKey: .sessionOrderByWorkspace)
        selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
        selectedWorkspaceID = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceID)
        selectedSessionIDByWorkspace = try container.decodeIfPresent([UUID: UUID].self, forKey: .selectedSessionIDByWorkspace) ?? [:]
        expandedSessionWorkspaceIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .expandedSessionWorkspaceIDs) ?? []
        hiddenSessionWorkspaceIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .hiddenSessionWorkspaceIDs) ?? []
    }
}

struct WorkspaceLayoutSnapshot: Codable {
    var pinnedWorkspaceIDs: [UUID]
    var workspaceOrder: [UUID]
    var agentSettingsByWorkspace: [UUID: WorkspaceAgentSettings]

    init(
        pinnedWorkspaceIDs: [UUID],
        workspaceOrder: [UUID],
        agentSettingsByWorkspace: [UUID: WorkspaceAgentSettings] = [:]
    ) {
        self.pinnedWorkspaceIDs = pinnedWorkspaceIDs
        self.workspaceOrder = workspaceOrder
        self.agentSettingsByWorkspace = agentSettingsByWorkspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinnedWorkspaceIDs = try container.decode([UUID].self, forKey: .pinnedWorkspaceIDs)
        workspaceOrder = try container.decode([UUID].self, forKey: .workspaceOrder)
        agentSettingsByWorkspace = try container.decodeIfPresent([UUID: WorkspaceAgentSettings].self, forKey: .agentSettingsByWorkspace) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case pinnedWorkspaceIDs, workspaceOrder, agentSettingsByWorkspace
    }
}

struct WorkspaceAgentSettings: Codable, Hashable {
    var model: String?
    var reasoningEffort: String?
}

enum SessionLayoutAuthority: String, Codable, Equatable {
    case v3Committed
    case migratedV2
    case legacyV2Fallback
    case empty
}

enum SessionLayoutFailureCode: String, Codable, Equatable {
    case incompleteV3Commit
    case v3DecodeFailed
    case v3MarkerMismatch
    case integrityKeyUnavailable
    case v2DecodeFailed
    case v3WriteVerificationFailed
}

struct SessionLayoutLoadResult: Equatable {
    let snapshot: SessionLayoutSnapshot
    let authority: SessionLayoutAuthority
    let failure: SessionLayoutFailureCode?
}

struct SessionLayoutSaveReceipt: Codable, Equatable, Sendable {
    let committed: Bool
    let schemaVersion: Int
    let recordCount: Int
    let activationCounter: UInt64
    let savedAt: Date
    let failure: SessionLayoutFailureCode?
}

struct SessionPersistenceFlushReceipt: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let recordCount: Int
    let transcriptCount: Int
    let activationCounter: UInt64
    let flushedAt: Date
}

private struct SessionLayoutV3CommitMarker: Codable {
    struct TranscriptGeneration: Codable, Equatable {
        let id: UUID
        let generation: UInt64
    }

    let schemaVersion: Int
    let recordCount: Int
    let recordIDs: [UUID]
    let transcriptGenerations: [TranscriptGeneration]
    let activationCounter: UInt64
    let candidateByteCount: Int
    let integrityTag: String
    let committedAt: Date
}

enum SessionLayoutStore {
    static let maxSidebarSessions = 10
    static let maxPinnedProjects = 5
    static let legacySessionKey = "GrokBuild.sessionLayout.v2"
    static let sessionV3CandidateKey = "GrokBuild.sessionLayout.v3"
    static let sessionV3CommitMarkerKey = "GrokBuild.sessionLayout.v3.committed"
    static let lastFlushReceiptKey = "GrokBuild.sessionLifecycle.lastFlush.v1"
    private static let workspaceLayoutKey = "GrokBuild.workspaceLayout.v1"

    static func loadSessions() -> SessionLayoutSnapshot {
        loadSessionsResult().snapshot
    }

    static func loadSessionsResult(
        defaults: UserDefaults = .standard,
        keyProvider: any SessionLifecycleIntegrityKeyProviding = KeychainSessionLifecycleIntegrityKeyProvider()
    ) -> SessionLayoutLoadResult {
        GrokBuildPerformance.measure(.layoutLoad) {
            let candidate = defaults.data(forKey: sessionV3CandidateKey)
            let markerData = defaults.data(forKey: sessionV3CommitMarkerKey)
            if candidate != nil || markerData != nil {
                guard let candidate, let markerData else {
                    return fallbackToV2(
                        defaults: defaults,
                        failure: .incompleteV3Commit
                    )
                }
                do {
                    guard let key = try keyProvider.existingKey() else {
                        return fallbackToV2(defaults: defaults, failure: .integrityKeyUnavailable)
                    }
                    return validateCommittedV3(candidate: candidate, markerData: markerData, key: key)
                        ?? fallbackToV2(defaults: defaults, failure: .v3MarkerMismatch)
                } catch {
                    return fallbackToV2(defaults: defaults, failure: .integrityKeyUnavailable)
                }
            }

            guard let legacyData = defaults.data(forKey: legacySessionKey) else {
                return SessionLayoutLoadResult(snapshot: emptySnapshot(), authority: .empty, failure: nil)
            }
            guard let legacy = try? JSONDecoder().decode(LegacySessionLayoutSnapshotV2.self, from: legacyData) else {
                return SessionLayoutLoadResult(snapshot: emptySnapshot(), authority: .empty, failure: .v2DecodeFailed)
            }
            let migrated = migrateV2(legacy)
            let save = saveSessions(migrated, defaults: defaults, keyProvider: keyProvider)
            return SessionLayoutLoadResult(
                snapshot: migrated,
                authority: save.committed ? .migratedV2 : .legacyV2Fallback,
                failure: save.failure
            )
        }
    }

    @discardableResult
    static func saveSessions(
        _ snapshot: SessionLayoutSnapshot,
        defaults: UserDefaults = .standard,
        keyProvider: any SessionLifecycleIntegrityKeyProviding = KeychainSessionLifecycleIntegrityKeyProvider()
    ) -> SessionLayoutSaveReceipt {
        var candidate = snapshot
        candidate.schemaVersion = SessionLayoutSnapshot.currentSchemaVersion
        candidate.activationCounter = max(
            candidate.activationCounter,
            candidate.records.map(\.lastActivationOrdinal).max() ?? 0
        )
        let now = Date()
        do {
            let data = try JSONEncoder().encode(candidate)
            let key = try keyProvider.existingOrCreateKey()
            defaults.set(data, forKey: sessionV3CandidateKey)
            guard defaults.synchronize(),
                  defaults.data(forKey: sessionV3CandidateKey) == data,
                  let decoded = try? JSONDecoder().decode(SessionLayoutSnapshot.self, from: data),
                  decoded == candidate else {
                return failedSave(candidate, at: now, code: .v3WriteVerificationFailed)
            }
            let marker = SessionLayoutV3CommitMarker(
                schemaVersion: candidate.schemaVersion,
                recordCount: candidate.records.count,
                recordIDs: candidate.records.map(\.id).sorted { $0.uuidString < $1.uuidString },
                transcriptGenerations: candidate.records
                    .map { SessionLayoutV3CommitMarker.TranscriptGeneration(
                        id: $0.id,
                        generation: $0.transcriptGeneration
                    ) }
                    .sorted { $0.id.uuidString < $1.id.uuidString },
                activationCounter: candidate.activationCounter,
                candidateByteCount: data.count,
                integrityTag: VersionedOpaqueTag.authenticationCode(
                    key: key,
                    domain: "session-layout",
                    schemaVersion: candidate.schemaVersion,
                    payload: data
                ),
                committedAt: now
            )
            let markerData = try JSONEncoder().encode(marker)
            defaults.set(markerData, forKey: sessionV3CommitMarkerKey)
            guard defaults.synchronize(),
                  defaults.data(forKey: sessionV3CommitMarkerKey) == markerData,
                  validateCommittedV3(candidate: data, markerData: markerData, key: key)?.snapshot == candidate else {
                return failedSave(candidate, at: now, code: .v3WriteVerificationFailed)
            }
            return SessionLayoutSaveReceipt(
                committed: true,
                schemaVersion: candidate.schemaVersion,
                recordCount: candidate.records.count,
                activationCounter: candidate.activationCounter,
                savedAt: now,
                failure: nil
            )
        } catch {
            return failedSave(candidate, at: now, code: .integrityKeyUnavailable)
        }
    }

    static func recordFlushReceipt(
        layoutReceipt: SessionLayoutSaveReceipt,
        transcriptCount: Int,
        defaults: UserDefaults = .standard
    ) -> SessionPersistenceFlushReceipt? {
        guard layoutReceipt.committed else { return nil }
        let receipt = SessionPersistenceFlushReceipt(
            schemaVersion: layoutReceipt.schemaVersion,
            recordCount: layoutReceipt.recordCount,
            transcriptCount: transcriptCount,
            activationCounter: layoutReceipt.activationCounter,
            flushedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(receipt) else { return nil }
        defaults.set(data, forKey: lastFlushReceiptKey)
        guard defaults.synchronize(),
              defaults.data(forKey: lastFlushReceiptKey) == data else { return nil }
        return receipt
    }

    static func lastFlushReceipt(defaults: UserDefaults = .standard) -> SessionPersistenceFlushReceipt? {
        guard let data = defaults.data(forKey: lastFlushReceiptKey) else { return nil }
        return try? JSONDecoder().decode(SessionPersistenceFlushReceipt.self, from: data)
    }

    static func migrateV2(_ legacy: LegacySessionLayoutSnapshotV2) -> SessionLayoutSnapshot {
        let sortedForOrdinal = legacy.records.sorted {
            if $0.lastAccessed != $1.lastAccessed { return $0.lastAccessed < $1.lastAccessed }
            return $0.id.uuidString < $1.id.uuidString
        }
        let ordinalByID = Dictionary(
            uniqueKeysWithValues: sortedForOrdinal.enumerated().map {
                ($0.element.id, UInt64($0.offset + 1))
            }
        )
        let records = legacy.records.map { record in
            let model = record.model?.trimmingCharacters(in: .whitespacesAndNewlines)
            let agent = record.agent?.trimmingCharacters(in: .whitespacesAndNewlines)
            return SavedSessionRecord(
                id: record.id,
                workspaceID: record.workspaceID,
                backendBinding: record.grokSessionID.map {
                    SessionBackendBinding(
                        backendID: $0,
                        origin: .legacyV2,
                        predecessorBackendID: nil,
                        verification: .unverified
                    )
                },
                title: record.title,
                modelIntent: model.flatMap { $0.isEmpty ? nil : $0 }
                    .map(TabModelIntent.legacyUnknown) ?? .inheritProjectDefault,
                // v2 agent persistence already wrote nil for inheritance and a value only
                // after an explicit per-tab choice.
                agentIntent: agent.map(TabAgentIntent.explicit) ?? .inheritGlobalDefault,
                lastAccessed: record.lastAccessed,
                lastActivationOrdinal: ordinalByID[record.id] ?? 0
            )
        }
        return SessionLayoutSnapshot(
            records: records,
            sessionOrderByWorkspace: legacy.sessionOrderByWorkspace,
            selectedSessionID: legacy.selectedSessionID,
            selectedWorkspaceID: legacy.selectedWorkspaceID,
            selectedSessionIDByWorkspace: legacy.selectedSessionIDByWorkspace,
            expandedSessionWorkspaceIDs: legacy.expandedSessionWorkspaceIDs,
            hiddenSessionWorkspaceIDs: legacy.hiddenSessionWorkspaceIDs,
            activationCounter: UInt64(records.count)
        )
    }

    static func loadWorkspaceLayout() -> WorkspaceLayoutSnapshot {
        guard let data = UserDefaults.standard.data(forKey: workspaceLayoutKey),
              let decoded = try? JSONDecoder().decode(WorkspaceLayoutSnapshot.self, from: data) else {
            return WorkspaceLayoutSnapshot(pinnedWorkspaceIDs: [], workspaceOrder: [])
        }
        return decoded
    }

    static func saveWorkspaceLayout(_ snapshot: WorkspaceLayoutSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: workspaceLayoutKey)
        }
    }

    static func agentSettings(for workspaceID: UUID) -> WorkspaceAgentSettings {
        loadWorkspaceLayout().agentSettingsByWorkspace[workspaceID] ?? WorkspaceAgentSettings()
    }

    static func saveAgentSettings(_ settings: WorkspaceAgentSettings, for workspaceID: UUID) {
        var layout = loadWorkspaceLayout()
        layout.agentSettingsByWorkspace[workspaceID] = settings
        saveWorkspaceLayout(layout)
    }

    static func removeAgentSettings(for workspaceID: UUID) {
        var layout = loadWorkspaceLayout()
        layout.agentSettingsByWorkspace.removeValue(forKey: workspaceID)
        saveWorkspaceLayout(layout)
    }

    private static func validateCommittedV3(
        candidate: Data,
        markerData: Data,
        key: Data
    ) -> SessionLayoutLoadResult? {
        guard let snapshot = try? JSONDecoder().decode(SessionLayoutSnapshot.self, from: candidate),
              let marker = try? JSONDecoder().decode(SessionLayoutV3CommitMarker.self, from: markerData) else {
            return nil
        }
        let expectedGenerations = snapshot.records
            .map { SessionLayoutV3CommitMarker.TranscriptGeneration(
                id: $0.id,
                generation: $0.transcriptGeneration
            ) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard
              snapshot.schemaVersion == SessionLayoutSnapshot.currentSchemaVersion,
              marker.schemaVersion == snapshot.schemaVersion,
              marker.recordCount == snapshot.records.count,
              marker.recordIDs == snapshot.records.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }),
              marker.transcriptGenerations == expectedGenerations,
              marker.activationCounter == snapshot.activationCounter,
              marker.candidateByteCount == candidate.count,
              marker.integrityTag == VersionedOpaqueTag.authenticationCode(
                  key: key,
                  domain: "session-layout",
                  schemaVersion: snapshot.schemaVersion,
                  payload: candidate
              ) else {
            return nil
        }
        return SessionLayoutLoadResult(snapshot: snapshot, authority: .v3Committed, failure: nil)
    }

    private static func fallbackToV2(
        defaults: UserDefaults,
        failure: SessionLayoutFailureCode
    ) -> SessionLayoutLoadResult {
        guard let data = defaults.data(forKey: legacySessionKey),
              let legacy = try? JSONDecoder().decode(LegacySessionLayoutSnapshotV2.self, from: data) else {
            return SessionLayoutLoadResult(snapshot: emptySnapshot(), authority: .empty, failure: failure)
        }
        return SessionLayoutLoadResult(
            snapshot: migrateV2(legacy),
            authority: .legacyV2Fallback,
            failure: failure
        )
    }

    private static func failedSave(
        _ snapshot: SessionLayoutSnapshot,
        at date: Date,
        code: SessionLayoutFailureCode
    ) -> SessionLayoutSaveReceipt {
        SessionLayoutSaveReceipt(
            committed: false,
            schemaVersion: snapshot.schemaVersion,
            recordCount: snapshot.records.count,
            activationCounter: snapshot.activationCounter,
            savedAt: date,
            failure: code
        )
    }

    private static func emptySnapshot() -> SessionLayoutSnapshot {
        SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [:],
            selectedSessionID: nil,
            selectedWorkspaceID: nil
        )
    }
}
