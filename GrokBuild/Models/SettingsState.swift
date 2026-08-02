import Foundation

enum SettingsCapability: String, CaseIterable, Sendable {
    case agents
    case models
    case memory
    case workflows
    case browser
    case computerUse
    case mcpServers
    case skills
    case plugins
    case marketplace
    case hooks
    case compatibility
    case permissions
    case app
}

enum SettingsPersistenceOwner: String, Sendable {
    case userDefaults
    case grokConfig
    case keychain
    case externalIntegration
}

enum SettingsApplyScope: String, Sendable {
    case externalConfigOnly
    case futureSessions
    case activeTabRestart
    case allEligibleLiveTabs
}

/// Exact session identity captured when Apply is pressed. A delayed completion may
/// update Settings UI only when it still describes this tab/backend/process generation.
struct SettingsApplyTarget: Equatable, Sendable {
    let localTabID: UUID?
    let backendSessionID: String?
    let processGeneration: UInt64?
}

enum EffectiveSessionReceiptFreshness: String, Sendable {
    case live
    case historical
}

/// Credential-free view of the effective process state that Settings may safely display.
/// It intentionally excludes environment, endpoint, header, rule, and credential values.
struct EffectiveSessionReceipt: Equatable, Sendable {
    let localTabID: UUID?
    let workspaceID: UUID?
    let processIdentifier: Int32?
    let processGeneration: UInt64
    let backendSessionID: String?
    let launchOutcome: GrokLaunchOutcome
    let requestedModelID: String?
    let requestedAgentID: String?
    let requestedReasoningEffort: String?
    let permissionMode: GrokPermissionMode
    let sandboxProfile: String
    let memoryEnabled: Bool
    let browserEnabled: Bool
    let computerUseEnabled: Bool
    let mcpServerNames: [String]
    let startedAt: Date
    let freshness: EffectiveSessionReceiptFreshness

    var target: SettingsApplyTarget {
        SettingsApplyTarget(
            localTabID: localTabID,
            backendSessionID: backendSessionID,
            processGeneration: freshness == .live ? processGeneration : nil
        )
    }
}

extension GrokLaunchReceipt {
    func effectiveSessionReceipt(activeProcessGeneration: UInt64?) -> EffectiveSessionReceipt {
        let isLive = activeProcessGeneration == processGeneration
            && outcome != .failed
            && outcome != .stopped
        return EffectiveSessionReceipt(
            localTabID: localTabID,
            workspaceID: workspaceID,
            processIdentifier: processIdentifier,
            processGeneration: processGeneration,
            backendSessionID: backendSessionID,
            launchOutcome: outcome,
            requestedModelID: requestedModelID,
            requestedAgentID: requestedAgentID,
            requestedReasoningEffort: requestedReasoningEffort,
            permissionMode: permissionMode,
            sandboxProfile: sandboxProfile,
            memoryEnabled: memoryEnabled,
            browserEnabled: browserEnabled,
            computerUseEnabled: computerUseEnabled,
            mcpServerNames: mcpServerNames,
            startedAt: startedAt,
            freshness: isLive ? .live : .historical
        )
    }
}

enum SettingsApplyReceiptStatus: String, Sendable {
    case pending
    case success
    case partial
    case failure
}

struct SettingsApplyReceipt: Equatable, Sendable {
    let requestID: UUID
    let configurationGeneration: UInt64
    let status: SettingsApplyReceiptStatus
    let summary: String
    let target: SettingsApplyTarget?
    let effectiveSession: EffectiveSessionReceipt?
    let completedAt: Date?

    var accessibilityValue: String {
        switch status {
        case .pending: return "Pending. \(summary)"
        case .success: return "Applied. \(summary)"
        case .partial: return "Partially applied. \(summary)"
        case .failure: return "Apply failed. \(summary)"
        }
    }

    static func pending(
        requestID: UUID,
        configurationGeneration: UInt64,
        target: SettingsApplyTarget? = nil,
        summary: String
    ) -> SettingsApplyReceipt {
        SettingsApplyReceipt(
            requestID: requestID,
            configurationGeneration: configurationGeneration,
            status: .pending,
            summary: summary,
            target: target,
            effectiveSession: nil,
            completedAt: nil
        )
    }

    static func completed(
        request: SettingsApplyRequest,
        status: SettingsApplyReceiptStatus,
        summary: String,
        effectiveSession: EffectiveSessionReceipt? = nil,
        at date: Date = Date()
    ) -> SettingsApplyReceipt {
        SettingsApplyReceipt(
            requestID: request.id,
            configurationGeneration: request.configurationGeneration,
            status: status,
            summary: summary,
            target: request.target,
            effectiveSession: effectiveSession,
            completedAt: date
        )
    }
}

/// Typed Settings-to-runtime request. ConfigurationChange remains the narrow model
/// catalog/runtime signal; this type owns pane apply scope and its exact receipt.
struct SettingsApplyRequest: Equatable, Sendable {
    let id: UUID
    let configurationGeneration: UInt64
    let capability: SettingsCapability
    let persistenceOwner: SettingsPersistenceOwner
    let applyScope: SettingsApplyScope
    let requiresProcessRestart: Bool
    let requiresPermissionOrTrust: Bool
    let redactedSummary: String
    let target: SettingsApplyTarget?
    let receipt: SettingsApplyReceipt

    init(
        id: UUID = UUID(),
        configurationGeneration: UInt64,
        capability: SettingsCapability,
        persistenceOwner: SettingsPersistenceOwner,
        applyScope: SettingsApplyScope,
        requiresProcessRestart: Bool,
        requiresPermissionOrTrust: Bool = false,
        redactedSummary: String,
        target: SettingsApplyTarget? = nil
    ) {
        self.id = id
        self.configurationGeneration = configurationGeneration
        self.capability = capability
        self.persistenceOwner = persistenceOwner
        self.applyScope = applyScope
        self.requiresProcessRestart = requiresProcessRestart
        self.requiresPermissionOrTrust = requiresPermissionOrTrust
        self.redactedSummary = redactedSummary
        self.target = target
        receipt = .pending(
            requestID: id,
            configurationGeneration: configurationGeneration,
            target: target,
            summary: redactedSummary
        )
    }

    func bound(to target: SettingsApplyTarget) -> SettingsApplyRequest {
        SettingsApplyRequest(
            id: id,
            configurationGeneration: configurationGeneration,
            capability: capability,
            persistenceOwner: persistenceOwner,
            applyScope: applyScope,
            requiresProcessRestart: requiresProcessRestart,
            requiresPermissionOrTrust: requiresPermissionOrTrust,
            redactedSummary: redactedSummary,
            target: target
        )
    }
}

/// Pure generation/identity gate for accepting a reconnect as proof that a saved
/// Settings value is live. A recovery fork is usable but never painted as full success.
enum SettingsApplyReceiptResolver {
    static func resolve(
        request: SettingsApplyRequest,
        connectionIsReady: Bool,
        liveReceipt: EffectiveSessionReceipt?
    ) -> SettingsApplyReceipt {
        guard connectionIsReady,
              let liveReceipt,
              liveReceipt.freshness == .live else {
            return .completed(
                request: request,
                status: .failure,
                summary: "The setting was saved, but the current tab did not produce a live reconnect receipt. Local work and the prior binding were preserved."
            )
        }
        guard liveReceipt.localTabID == request.target?.localTabID,
              liveReceipt.processGeneration > (request.target?.processGeneration ?? 0) else {
            return .completed(
                request: request,
                status: .failure,
                summary: "A reconnect completed for a different tab or process generation, so it was not accepted as this Apply result."
            )
        }
        if liveReceipt.launchOutcome == .recoveryForked {
            return .completed(
                request: request,
                status: .partial,
                summary: "The setting is live, but the saved backend could not reconnect and GrokBuild disclosed a recovery fork.",
                effectiveSession: liveReceipt
            )
        }
        if let expectedBackendID = request.target?.backendSessionID,
           liveReceipt.backendSessionID != expectedBackendID {
            return .completed(
                request: request,
                status: .failure,
                summary: "The backend identity changed without a recovery-fork receipt, so this reconnect was rejected as proof of Apply."
            )
        }
        return .completed(
            request: request,
            status: .success,
            summary: "Saved and confirmed in the exact current tab and process generation.",
            effectiveSession: liveReceipt
        )
    }
}

enum SettingsValidationResult: Equatable, Sendable {
    case valid
    case invalid(String)

    var message: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }

    var isValid: Bool { self == .valid }
}

enum SettingsValueStatus: String, Sendable {
    case draft = "Draft"
    case saved = "Saved"
    case restartRequired = "Restart required"
    case live = "Live"
    case unknown = "Unknown"

    var accessibilityValue: String {
        switch self {
        case .draft: return "Draft changes are not saved or applied."
        case .saved: return "Saved for future eligible sessions."
        case .restartRequired: return "Applied setting saved; restart required for the current tab."
        case .live: return "Applied setting confirmed in the current live process."
        case .unknown: return "Applied state is unknown; review the latest receipt."
        }
    }
}

/// Shared four-layer value state used by editable Settings panes. `draft` is never
/// storage-backed; panes write `persisted`/`applied` only from their explicit Apply action.
struct SettingsValueState<Value: Equatable & Sendable>: Equatable, Sendable {
    var draft: Value
    var persisted: Value
    var applied: Value
    var live: Value?
    var validation: SettingsValidationResult
    var requiresRestart: Bool
    var lastOperationReceipt: SettingsApplyReceipt?
    var configurationGeneration: UInt64
    var isLoaded: Bool

    static func unloaded(default value: Value) -> SettingsValueState<Value> {
        SettingsValueState(
            draft: value,
            persisted: value,
            applied: value,
            live: nil,
            validation: .valid,
            requiresRestart: false,
            lastOperationReceipt: nil,
            configurationGeneration: 0,
            isLoaded: false
        )
    }

    var isDirty: Bool { draft != persisted }
    var canApply: Bool { isLoaded && isDirty && validation.isValid }

    var status: SettingsValueStatus {
        guard isLoaded else { return .unknown }
        if isDirty { return .draft }
        if let receipt = lastOperationReceipt,
           receipt.status == .failure || receipt.status == .partial {
            return .unknown
        }
        if requiresRestart { return .restartRequired }
        if let live, live == applied { return .live }
        return .saved
    }

    mutating func load(persisted: Value, applied: Value, live: Value?) {
        guard !isLoaded else {
            refreshLive(live)
            return
        }
        draft = persisted
        self.persisted = persisted
        self.applied = applied
        self.live = live
        requiresRestart = live.map { $0 != applied } ?? false
        isLoaded = true
    }

    mutating func refreshLive(_ value: Value?) {
        live = value
        if lastOperationReceipt?.status == .success {
            requiresRestart = value.map { $0 != applied } ?? false
        }
    }

    mutating func updateDraft(_ value: Value, validation: SettingsValidationResult = .valid) {
        draft = value
        self.validation = validation
    }

    mutating func revert() {
        draft = persisted
        validation = .valid
    }

    mutating func recordSaved(
        applied value: Value,
        requiresRestart: Bool,
        receipt: SettingsApplyReceipt
    ) {
        configurationGeneration &+= 1
        persisted = value
        applied = value
        draft = value
        self.requiresRestart = requiresRestart
        lastOperationReceipt = receipt
    }

    mutating func complete(receipt: SettingsApplyReceipt, live: Value?) {
        lastOperationReceipt = receipt
        self.live = live
        if receipt.status == .success {
            requiresRestart = live.map { $0 != applied } ?? false
        }
    }
}

enum SettingsLoadState: Equatable, Sendable {
    case checking
    case content
    case empty(String)
    case stale(String)
    case error(String)
}

enum SettingsFormRowLayout: Equatable, Sendable {
    case horizontal
    case vertical
}

enum SettingsFormRowLayoutPolicy {
    static func layout(availableWidth: CGFloat, usesAccessibilityText: Bool) -> SettingsFormRowLayout {
        availableWidth < 560 || usesAccessibilityText ? .vertical : .horizontal
    }
}

struct RuntimeConfigurationReloadBatch: Equatable, Sendable {
    let requestsGeneralReload: Bool
    let affectedModelIDs: Set<String>
    let settingsRequests: [SettingsApplyRequest]

    var isEmpty: Bool {
        !requestsGeneralReload && affectedModelIDs.isEmpty && settingsRequests.isEmpty
    }
}

/// One coalescing queue for general, model, and Settings-triggered runtime reloads.
/// A streaming turn drains it once at the ordered completion boundary.
struct RuntimeConfigurationReloadQueue: Sendable {
    private(set) var requestsGeneralReload = false
    private(set) var affectedModelIDs: Set<String> = []
    private(set) var settingsRequests: [SettingsApplyRequest] = []

    var hasPending: Bool {
        requestsGeneralReload || !affectedModelIDs.isEmpty || !settingsRequests.isEmpty
    }

    var pendingSettingsRequestCount: Int { settingsRequests.count }

    mutating func enqueueGeneralReload() {
        requestsGeneralReload = true
    }

    mutating func enqueue(_ change: ConfigurationChange) {
        if change.impact == .modelRuntime {
            affectedModelIDs.formUnion(change.affectedModelIDs)
        }
    }

    mutating func enqueue(_ request: SettingsApplyRequest) {
        guard !settingsRequests.contains(where: { $0.id == request.id }) else { return }
        settingsRequests.append(request)
    }

    mutating func drain() -> RuntimeConfigurationReloadBatch {
        let batch = RuntimeConfigurationReloadBatch(
            requestsGeneralReload: requestsGeneralReload,
            affectedModelIDs: affectedModelIDs,
            settingsRequests: settingsRequests
        )
        requestsGeneralReload = false
        affectedModelIDs.removeAll()
        settingsRequests.removeAll()
        return batch
    }
}
