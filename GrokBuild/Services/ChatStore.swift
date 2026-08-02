import Foundation
import Observation
import SwiftUI
import AppKit

struct TurnSettlementCoordinator {
    struct Decision: Equatable {
        let assistantID: UUID
        let ok: Bool
    }

    private(set) var generation = 0
    private var assistantID: UUID?
    private var promptResult: Bool?
    private var completionConsumed = false
    private var finalized = false

    mutating func begin(assistantID: UUID) -> Int {
        generation &+= 1
        self.assistantID = assistantID
        promptResult = nil
        completionConsumed = false
        finalized = false
        return generation
    }

    mutating func recordPromptResult(generation: Int, ok: Bool) -> Decision? {
        guard generation == self.generation, assistantID != nil, !finalized else { return nil }
        promptResult = ok
        return takeDecisionIfReady()
    }

    mutating func recordCompletionConsumed() -> Decision? {
        guard assistantID != nil, !finalized else { return nil }
        completionConsumed = true
        return takeDecisionIfReady()
    }

    mutating func invalidate() {
        generation &+= 1
        assistantID = nil
        promptResult = nil
        completionConsumed = false
        finalized = true
    }

    private mutating func takeDecisionIfReady() -> Decision? {
        guard let assistantID, let promptResult else { return nil }
        // A failed RPC is terminal even when the CLI never emits completion. Success
        // waits until the completion event has crossed ChatStore's event queue.
        guard !promptResult || completionConsumed else { return nil }
        finalized = true
        return Decision(assistantID: assistantID, ok: promptResult)
    }
}

enum PermissionRequestDisposition: Equatable {
    case allow(optionID: String)
    case deny(optionID: String?)
    case prompt
}

enum PermissionRequestPolicy {
    static func disposition(
        mode: GrokPermissionMode,
        isYolo: Bool,
        options: [PermissionOption]
    ) -> PermissionRequestDisposition {
        if isYolo || mode == .alwaysApprove {
            if let allow = options.first(where: { isAllow($0) }) {
                return .allow(optionID: allow.id)
            }
            return .deny(optionID: options.first(where: { isDeny($0) })?.id)
        }
        if mode == .denyUnapproved {
            return .deny(optionID: options.first(where: { isDeny($0) })?.id)
        }
        return .prompt
    }

    private static func isAllow(_ option: PermissionOption) -> Bool {
        let kind = option.kind.lowercased()
        return kind.contains("allow") || kind.contains("approve")
    }

    private static func isDeny(_ option: PermissionOption) -> Bool {
        let kind = option.kind.lowercased()
        return kind.contains("reject") || kind.contains("deny") || kind.contains("cancel")
    }
}

@Observable
@MainActor
final class ChatStore {
    private struct SessionSelection: Codable {
        var mode: String?
        var model: String?
    }

    /// Reasoning effort for the active project (not global).
    private var workspaceReasoningEffort: String = ""

    private(set) var messages: [Message] = []
    /// Grok session id restored from disk before a live process is started (lazy restore).
    private(set) var savedGrokSessionID: String?
    /// Exact local/backend relationship. It is checked before any saved backend can be
    /// resumed and is intentionally independent from process/model readiness.
    private(set) var continuityReceipt: SessionContinuityReceipt = .localOnly
    private(set) var persistedContinuityReceipt: SessionContinuityReceipt?
    private(set) var pendingForkLedgerEntries: [SessionForkLedgerEntry] = []
    private(set) var pendingRecoveryIntent: SessionPendingRecoveryIntent?
    private(set) var recoveryCandidates: [SessionRecoveryCandidate] = []
    private(set) var isLoadingRecoveryCandidates = false
    private(set) var recoveryCandidateError: String?
    private var continuityBackendID: String?
    private var boundForkLedgerEntry: SessionForkLedgerEntry?

    /// True when this tab resumes an existing grok session rather than a fresh chat.
    var isResumedSessionTab: Bool {
        grokSessionId != nil || savedGrokSessionID != nil
    }

    func clearMessages() {
        messages.removeAll()
    }
    private(set) var isStreaming = false
    private(set) var lastError: String?
    /// Set when a model switch fails/times out; shown as a dismissible banner in the chat.
    var modelSwitchError: String?
    /// `true` when the failed switch can be resolved by starting a new session; the banner
    /// then offers a "Start New Session" action.
    var modelSwitchNeedsNewSession = false

    // VS Code extension-style turn state
    private(set) var isGrokking = false
    private(set) var thinkingText = ""
    private(set) var thinkingDuration: TimeInterval?
    private(set) var isThinkingExpanded = false
    /// Bumped on every streamed thinking/answer chunk. A streaming answer appends to the
    /// existing assistant message's content, which changes neither `messages.count` nor
    /// `isGrokking` — so the transcript needs this to auto-scroll the growing answer into
    /// view instead of stranding it below the fold behind the thinking chip.
    private(set) var streamRevision = 0
    private(set) var liveToolCalls: [LiveToolCall] = []
    private var thinkingStartedAt: Date?
    /// When the current turn began — drives the elapsed/"warming up" indicator.
    private(set) var turnStartedAt: Date?

    struct LiveToolCall: Identifiable, Hashable {
        let id: String
        let title: String
        let kind: String
        let status: String?
        let detail: String?

        var isFailed: Bool {
            guard let status else { return false }
            return ["failed", "error", "rejected"].contains(status.lowercased())
        }

        var isComplete: Bool {
            guard let status else { return false }
            return ["completed", "complete", "success", "succeeded"].contains(status.lowercased())
        }
    }

    /// Set when the underlying grok CLI indicates the user is not authenticated.
    var authRequiredMessage: String?

    // MARK: - ACP Rich State
    private(set) var connectionState: GrokProcessState = .idle
    private(set) var currentMode: AgentMode = .agent
    private(set) var availableModes: [AgentMode] = [.agent, .plan, .yolo]
    private(set) var pendingPermissions: [PermissionRequest] = []
    private(set) var pendingExitPlan: ExitPlanRequest?
    private(set) var pendingQuestions: [QuestionRequest] = []
    private(set) var availableSlashCommands: [SlashCommand] = GrokCommandCatalog.cached()
    /// Local goal state updated when the user sends `/goal …`; cleared on new session.
    private(set) var goalState: SessionGoalState?
    private(set) var fileAttachments: [FileAttachment] = []
    private(set) var isYolo: Bool = false

    var grokSessionId: String? { process.sessionId }
    var durableGrokSessionID: String? { process.sessionId ?? savedGrokSessionID }
    var persistedPendingRecoveryIntent: SessionPendingRecoveryIntent? { pendingRecoveryIntent }
    var effectiveLaunchReceipt: GrokLaunchReceipt? { process.launchReceipt }
    var effectivePermissionMode: GrokPermissionMode {
        process.launchReceipt?.permissionMode ?? .ask
    }

    var continuityStatus: SessionContinuityStatus { continuityReceipt.status }

    var continuityBlocksSend: Bool {
        SessionSendGate.decision(for: continuityStatus) == .block
    }

    var continuityPermitsAuthoritativeReconciliation: Bool {
        switch continuityStatus {
        case .verified, .backendOnly, .recoveryForked:
            return true
        case .localOnly, .verifying, .diverged, .compositeSuspected, .backendMissing,
             .verificationIncomplete:
            return false
        }
    }

    var shouldShowContinuityBanner: Bool {
        switch continuityStatus {
        case .verified, .backendOnly, .recoveryForked:
            return false
        case .localOnly:
            return hasUserMessages
        case .verifying, .diverged, .compositeSuspected, .backendMissing,
             .verificationIncomplete:
            return true
        }
    }

    var continuityHeadline: String {
        switch continuityStatus {
        case .localOnly: return "Messages restored locally"
        case .verifying: return "Checking conversation continuity"
        case .diverged: return "Conversation continuity does not match"
        case .compositeSuspected: return "This transcript may combine multiple conversations"
        case .backendMissing: return "The saved Grok conversation is unavailable"
        case .verificationIncomplete: return "Conversation continuity could not be verified"
        case .backendOnly: return "Backend conversation restored"
        case .verified: return "Conversation continuity verified"
        case .recoveryForked: return "Continuing in a safe new conversation"
        }
    }

    var continuityMessage: String {
        switch continuityStatus {
        case .localOnly:
            return "Your local messages are safe. Grok will start a new conversation when you send."
        case .verifying:
            return "GrokBuild is comparing this local transcript with its exact saved backend before starting it."
        case .diverged, .compositeSuspected:
            return "This tab’s saved conversation does not match its Grok backend. Your local messages are safe, and Send is blocked until recovery is explicitly chosen."
        case .backendMissing:
            return "Your local messages remain readable. GrokBuild will not send them to an empty, missing, or unreadable saved backend."
        case .verificationIncomplete:
            return "The bounded verification did not finish, so GrokBuild left the backend stopped and Send blocked."
        case .backendOnly:
            return "The exact backend history was imported before the session resumed."
        case .verified:
            return "The local transcript is an exact or verified prefix match for the saved backend."
        case .recoveryForked:
            return "The prior relationship is preserved in the local fork ledger."
        }
    }

    var continuityDetails: String {
        let backend = continuityBackendID.map { "…\($0.suffix(8))" } ?? "none"
        return "Backend \(backend) · local \(continuityReceipt.localMessageCount) rows · backend \(continuityReceipt.backendMessageCount) rows · matched prefix \(continuityReceipt.matchingPrefixCount) · reason \(continuityReceipt.reason.rawValue)"
    }

    // MARK: - Model selection (real models from `grok models` + initialize modelState)
    private(set) var currentModel: String = "grok-4.5"
    private(set) var modelExecutionState: ModelExecutionState = .unknown
    private(set) var availableModels: [String] = []
    private var modelDisplayNames: [String: String] = [:]
    private var modelContextTokens: [String: Int] = ["grok-4.5": 500_000]
    private var builtInModelIDs = Set<String>()
    private var customModelsByID: [String: CustomModel] = [:]
    private var pendingConfigurationChange: ConfigurationChange?
    private var pendingRuntimeReload = false

    /// Set when a streaming turn has produced no ACP events for `turnStallThreshold`.
    /// The UI offers Stop-and-retry; nothing is killed automatically, because a long
    /// tool run is indistinguishable from a wedge without the user's judgment.
    private(set) var turnStalledSince: Date?
    private var lastTurnEventAt = Date()
    private var stallWatchdogTask: Task<Void, Never>?
    static let turnStallThreshold: TimeInterval = 120
    private(set) var isApplyingConfiguration = false
    private(set) var configurationStatusMessage: String?
    private(set) var usedContextTokens: Int?

    // Persist mode/model choices per Grok session id.
    private let sessionSelectionsKey = "grokbuild.sessionSelections.v1"
    private let defaults = UserDefaults.standard
    private var sessionSelections: [String: SessionSelection] = [:]

    /// Stable GrokBuild tab id (`LiveSession.id`) for per-tab model persistence.
    private(set) var tabSessionID: UUID?
    private var tabHasExplicitModel = false
    private var tabModelIntent: TabModelIntent = .inheritProjectDefault

    // MARK: - Session agent (per tab, launched via `--agent`)
    /// Explicit per-tab session-agent selection id. Empty string with `tabHasExplicitAgent`
    /// means "grok default"; when `tabHasExplicitAgent` is false the tab follows the global
    /// default (`grokbuild.selectedAgent`).
    private(set) var currentAgent: String = ""
    private var tabHasExplicitAgent = false
    private var tabAgentIntent: TabAgentIntent = .inheritGlobalDefault
    /// Agents discovered for the current workspace (`grok inspect --json`), loaded lazily for the
    /// composer agent picker.
    private(set) var discoveredAgents: [GrokAgentInfo] = []
    /// ID of the workspace whose agents have been loaded; `nil` means not yet loaded.
    /// Scoped per workspace so switching projects triggers a fresh load.
    private var loadedAgentsWorkspaceID: UUID?

    // MARK: - Scheduled tasks (grok `scheduler_*` tools, mirrored by observing ACP tool calls)
    /// Tasks grok has scheduled, mirrored from observed `scheduler_*` tool activity in this session.
    private(set) var scheduledTasks: [ScheduledTask] = []
    private var scheduledTaskTracker = ScheduledTaskTracker()

    // MARK: - Background activity (scheduled + background shells, monitors, subagents)
    private(set) var backgroundActivities: [BackgroundActivity] = []
    private var backgroundTaskTracker = BackgroundTaskTracker()

    // MARK: - Prompt queue (send while streaming)
    private(set) var promptQueue: [String] = []

    /// Unsent composer text for this tab. ChatView is recreated on tab switch
    /// (`.id(tabSessionID)` resets scroll identity), so the draft lives here to
    /// survive switching away and back. In-memory only — not persisted.
    var composerDraft: String = ""

    // MARK: - /btw aside panel
    private(set) var btwAsideText: String?
    private var pendingBtw = false
    private var pendingShareURLCapture = false
    private var lastSharedURL: String?

    /// Test-only: whether the next assistant URL should be treated as a `/share` result.
    var isPendingShareURLCaptureForTests: Bool { pendingShareURLCapture }

    /// Test-only: force streaming so queue-send guards can be exercised without a live process.
    func setStreamingForTests(_ value: Bool) {
        isStreaming = value
    }

    var pendingRuntimeReloadForTests: Bool { pendingRuntimeReload }
    var savedGrokSessionIDForTests: String? { savedGrokSessionID }

    // MARK: - Workflow runs (grok `workflow` tools, mirrored by observing ACP tool calls)
    private(set) var workflowRuns: [WorkflowRun] = []
    private var workflowRunTracker = WorkflowRunTracker()

    private var launchForkSession = false
    private var launchNewSessionID: String?

    private(set) var commandHistory: [String] = []
    private var historyIndex: Int?

    let process: GrokProcess
    private let continuityKeyOverride: Data?
    private(set) var currentWorkspace: Workspace?
    // (removed Agent personas - see AGENTS.md + sub-agents in Grok Build CLI)

    private(set) var streamingMessageID: UUID?
    private var connectionWatchdogTask: Task<Void, Never>?
    private var streamingTextBuffer = StreamingTextBuffer()
    private var streamingTextFlushTask: Task<Void, Never>?
    private var deferredPromptCompletion: (assistantID: UUID, ok: Bool)?
    private var turnSettlement = TurnSettlementCoordinator()
    private var activeTurnBackendSessionID: String?
    private var authoritativeTailAssistantID: UUID?
    private var closedTurnAssistantID: UUID?
    private var closedTurnHasAuthoritativeHistory = false
    private var pendingLateChunkPersistence = false
    private var firstChunkInterval: GrokBuildPerformanceInterval?

    init(process: GrokProcess? = nil, continuityKeyOverride: Data? = nil) {
        self.process = process ?? GrokProcess()
        self.continuityKeyOverride = continuityKeyOverride
        applyBuiltInModelCatalog(GrokModelCatalog.cachedOrFallback())
        loadSessionSelections()
        Task { [weak self] in await self?.consumeOutput() }
    }

    private func loadSessionSelections() {
        guard let data = defaults.data(forKey: sessionSelectionsKey),
              let decoded = try? JSONDecoder().decode([String: SessionSelection].self, from: data) else {
            return
        }
        sessionSelections = decoded
    }

    // MARK: Context

    func setWorkspace(_ workspace: Workspace) async {
        await start(workspace: workspace)
    }

    func prepare(workspace: Workspace, savedGrokSessionID: String? = nil) {
        resetSessionUI()
        self.savedGrokSessionID = savedGrokSessionID
        continuityBackendID = savedGrokSessionID
        continuityReceipt = savedGrokSessionID == nil
            ? .localOnly
            : Self.verifyingContinuityReceipt(localMessageCount: 0)
        persistedContinuityReceipt = nil
        pendingForkLedgerEntries = []
        pendingRecoveryIntent = nil
        recoveryCandidates = []
        recoveryCandidateError = nil
        isLoadingRecoveryCandidates = false
        boundForkLedgerEntry = nil
        currentWorkspace = workspace
        applyBuiltInModelCatalog(GrokModelCatalog.cachedOrFallback())
        mergeCustomModels()
        loadWorkspaceReasoningEffort()
        Task { [weak self] in
            guard let self else { return }
            self.applyBuiltInModelCatalog(await GrokModelCatalog.shared.models())
        }
    }

    /// Bind this store to a sidebar tab and apply its saved backend session, model, and agent.
    /// Reasserting the backend id here matters during launch: the persisted transcript can be
    /// visible before the selected tab's lazy `session/load` task has finished.
    func bindTabSession(
        _ id: UUID,
        savedModel: String?,
        savedAgent: String? = nil,
        savedGrokSessionID: String? = nil
    ) {
        bindTabSession(
            id,
            modelIntent: savedModel.map(TabModelIntent.explicit) ?? .inheritProjectDefault,
            savedModelExecutionState: .unknown,
            agentIntent: savedAgent.map(TabAgentIntent.explicit) ?? .inheritGlobalDefault,
            savedGrokSessionID: savedGrokSessionID
        )
    }

    /// v3 binding preserves semantic intent. Resolving an inherited or legacy model for
    /// display/process launch must never silently turn it into a per-tab override.
    func bindTabSession(
        _ id: UUID,
        modelIntent: TabModelIntent,
        savedModelExecutionState: ModelExecutionState = .unknown,
        agentIntent: TabAgentIntent = .inheritGlobalDefault,
        savedGrokSessionID: String? = nil,
        savedBackendBinding: SessionBackendBinding? = nil,
        savedForkLedgerEntry: SessionForkLedgerEntry? = nil,
        savedPendingRecoveryIntent: SessionPendingRecoveryIntent? = nil
    ) {
        tabSessionID = id
        let durableBackendID = savedBackendBinding?.backendID ?? savedGrokSessionID
        let isSameContinuityBinding = continuityBackendID == durableBackendID
        if let durableBackendID, !durableBackendID.isEmpty {
            self.savedGrokSessionID = durableBackendID
        }
        continuityBackendID = durableBackendID
        if !isSameContinuityBinding || persistedContinuityReceipt == nil {
            persistedContinuityReceipt = savedBackendBinding?.continuityReceipt
        }
        if !isSameContinuityBinding || boundForkLedgerEntry == nil {
            boundForkLedgerEntry = savedForkLedgerEntry
        }
        pendingRecoveryIntent = savedPendingRecoveryIntent
        if savedPendingRecoveryIntent != nil {
            self.savedGrokSessionID = nil
            continuityBackendID = nil
            boundForkLedgerEntry = nil
            continuityReceipt = Self.recoveryForkedContinuityReceipt(
                localMessages: messages,
                localTag: savedPendingRecoveryIntent?.transcriptTag
            )
            persistedContinuityReceipt = continuityReceipt
        } else if durableBackendID == nil {
            continuityReceipt = Self.localOnlyContinuityReceipt(localMessageCount: messages.count)
        } else if !isSameContinuityBinding {
            continuityReceipt = Self.verifyingContinuityReceipt(localMessageCount: messages.count)
        }
        tabModelIntent = modelIntent
        tabAgentIntent = agentIntent
        let ownsActiveReceipt = process.activeProcessGeneration != nil
            && process.launchReceipt?.localTabID == id
        modelExecutionState = ownsActiveReceipt
            ? process.modelExecutionState
            : savedModelExecutionState
        tabHasExplicitModel = false
        tabHasExplicitAgent = false
        currentAgent = defaultAgentSelection
        if case .explicit(let savedAgent) = agentIntent {
            currentAgent = savedAgent
            tabHasExplicitAgent = true
        }
        switch modelIntent {
        case .inheritProjectDefault:
            applyInheritedModelIfAvailable()
        case .explicit(let savedModel):
            applyTabModel(savedModel)
        case .legacyUnknown(let savedModel):
            applyLegacyModelIfAvailable(savedModel)
        }
    }

    @discardableResult
    func verifyContinuityBeforeResume(backendID: String? = nil) async -> SessionContinuityStatus {
        guard let workspace = currentWorkspace else {
            continuityReceipt = Self.localOnlyContinuityReceipt(localMessageCount: messages.count)
            persistedContinuityReceipt = continuityReceipt
            continuityBackendID = nil
            return .localOnly
        }
        let targetBackendID = backendID ?? savedGrokSessionID
        guard let targetBackendID, !targetBackendID.isEmpty else {
            continuityReceipt = Self.localOnlyContinuityReceipt(localMessageCount: messages.count)
            persistedContinuityReceipt = continuityReceipt
            continuityBackendID = nil
            return .localOnly
        }

        let expectedTabID = tabSessionID
        let expectedWorkspaceID = workspace.id
        let completeLocalSnapshot = messages
        let localSnapshot = boundForkLedgerEntry?.localMessagesForBackendVerification(messages)
            ?? completeLocalSnapshot
        let continuityKeyOverride = continuityKeyOverride
        continuityBackendID = targetBackendID
        continuityReceipt = Self.verifyingContinuityReceipt(localMessageCount: localSnapshot.count)

        let verification = await Task.detached(priority: .userInitiated) {
            let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
                workspacePath: workspace.path,
                grokSessionID: targetBackendID
            )
            guard let historyURL else {
                return SessionContinuityVerification(
                    receipt: SessionContinuityReceipt(
                        status: .backendMissing,
                        reason: .backendHistoryMissing,
                        normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
                        authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
                        localMessageCount: localSnapshot.count,
                        backendMessageCount: 0,
                        matchingPrefixCount: 0,
                        localTranscriptTag: nil,
                        backendTranscriptTag: nil,
                        verifiedAt: Date()
                    ),
                    backendMessages: []
                )
            }
            do {
                guard let key = try (continuityKeyOverride
                    ?? KeychainSessionLifecycleIntegrityKeyProvider().existingKey()) else {
                    return SessionContinuityVerification(
                        receipt: SessionContinuityReceipt(
                            status: .verificationIncomplete,
                            reason: .integrityKeyUnavailable,
                            normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
                            authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
                            localMessageCount: localSnapshot.count,
                            backendMessageCount: 0,
                            matchingPrefixCount: 0,
                            localTranscriptTag: nil,
                            backendTranscriptTag: nil,
                            verifiedAt: Date()
                        ),
                        backendMessages: []
                    )
                }
                return SessionTranscriptRecovery.verifyContinuity(
                    localMessages: localSnapshot,
                    backendHistoryURL: historyURL,
                    key: key
                )
            } catch {
                return SessionContinuityVerification(
                    receipt: SessionContinuityReceipt(
                        status: .verificationIncomplete,
                        reason: .integrityKeyUnavailable,
                        normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
                        authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
                        localMessageCount: localSnapshot.count,
                        backendMessageCount: 0,
                        matchingPrefixCount: 0,
                        localTranscriptTag: nil,
                        backendTranscriptTag: nil,
                        verifiedAt: Date()
                    ),
                    backendMessages: []
                )
            }
        }.value

        guard tabSessionID == expectedTabID,
              currentWorkspace?.id == expectedWorkspaceID,
              continuityBackendID == targetBackendID else {
            return continuityStatus
        }

        continuityReceipt = verification.receipt
        persistedContinuityReceipt = verification.receipt
        if [.verified, .backendOnly].contains(verification.receipt.status),
           !verification.backendMessages.isEmpty {
            let reconciledSuffix = SessionTranscriptReconciler.reconcile(
                local: localSnapshot,
                authoritative: verification.backendMessages
            )
            if SessionTranscriptReconciler.contentSignature(reconciledSuffix)
                != SessionTranscriptReconciler.contentSignature(localSnapshot) {
                if let boundForkLedgerEntry,
                   [.localOnlyStart, .resumeFallback, .explicitContinueAsNew].contains(boundForkLedgerEntry.reason) {
                    let prefixCount = min(
                        boundForkLedgerEntry.localMessageCountAtFork,
                        completeLocalSnapshot.count
                    )
                    messages = filteredPersistedMessages(
                        Array(completeLocalSnapshot.prefix(prefixCount)) + reconciledSuffix
                    )
                } else {
                    messages = filteredPersistedMessages(reconciledSuffix)
                }
                if let tabSessionID {
                    SessionMessageStore.replaceAfterAuthoritativeReconciliation(
                        messages,
                        for: tabSessionID
                    )
                }
                streamRevision &+= 1
                notifyMessagesChanged()
            }
        }
        return verification.receipt.status
    }

    /// Load review-only candidates after an explicit Relink action. This bounded scan
    /// never runs during startup and never mutates the current binding.
    func reviewRecoveryCandidates() async {
        guard let workspace = currentWorkspace else {
            recoveryCandidateError = "Select a project before reviewing histories."
            return
        }
        let expectedTabID = tabSessionID
        let expectedWorkspaceID = workspace.id
        let localSnapshot = messages
        let continuityKeyOverride = continuityKeyOverride
        isLoadingRecoveryCandidates = true
        recoveryCandidateError = nil
        recoveryCandidates = []

        let result = await Task.detached(priority: .userInitiated) {
            do {
                guard let key = try (continuityKeyOverride
                    ?? KeychainSessionLifecycleIntegrityKeyProvider().existingKey()) else {
                    return Result<[SessionRecoveryCandidate], Error>.failure(
                        SessionRecoveryReviewError.integrityKeyUnavailable
                    )
                }
                return .success(SessionTranscriptRecovery.recoveryCandidates(
                    workspacePath: workspace.path,
                    workspaceName: workspace.displayName,
                    localMessages: localSnapshot,
                    key: key
                ))
            } catch {
                return .failure(error)
            }
        }.value

        guard tabSessionID == expectedTabID,
              currentWorkspace?.id == expectedWorkspaceID else { return }
        isLoadingRecoveryCandidates = false
        switch result {
        case .success(let candidates):
            recoveryCandidates = candidates
        case .failure:
            recoveryCandidateError = "Recovery histories could not be reviewed safely."
        }
    }

    /// Preserve the local transcript and explicitly detach the failed backend. No Grok
    /// process is started here; the next accepted send creates the successor lazily.
    @discardableResult
    func continueAsNew() async -> Bool {
        guard let predecessor = continuityBackendID ?? savedGrokSessionID,
              SessionSendGate.decision(for: continuityStatus) == .block else {
            return false
        }
        let localSnapshot = messages
        let continuityKeyOverride = continuityKeyOverride
        let localTag = await Task.detached(priority: .utility) {
            guard let key = continuityKeyOverride
                ?? (try? KeychainSessionLifecycleIntegrityKeyProvider().existingKey()) else {
                return nil as String?
            }
            return SessionTranscriptRecovery.transcriptSequenceTag(localSnapshot, key: key)
        }.value
        pendingRecoveryIntent = SessionPendingRecoveryIntent(
            action: .continueAsNew,
            predecessorBackendID: predecessor,
            chosenAt: Date(),
            localMessageCountAtChoice: localSnapshot.count,
            transcriptTag: localTag
        )
        savedGrokSessionID = nil
        continuityBackendID = nil
        boundForkLedgerEntry = nil
        continuityReceipt = Self.recoveryForkedContinuityReceipt(
            localMessages: localSnapshot,
            localTag: localTag
        )
        persistedContinuityReceipt = continuityReceipt
        recoveryCandidates = []
        recoveryCandidateError = nil
        appendSystemNote(
            "Recovery choice: Continue as New. The prior backend remains preserved; a new conversation will be created on the next send."
        )
        notifyMessagesChanged()
        return true
    }

    /// Re-verify the exact selected candidate, then durably bind it. Candidate discovery
    /// alone is never sufficient and this action does not start a backend process.
    @discardableResult
    func relink(to candidate: SessionRecoveryCandidate) async -> Bool {
        guard candidate.isRelinkable,
              let workspace = currentWorkspace,
              let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
                  workspacePath: workspace.path,
                  grokSessionID: candidate.backendID
              ) else { return false }
        let expectedTabID = tabSessionID
        let expectedWorkspaceID = workspace.id
        let predecessor = continuityBackendID ?? savedGrokSessionID
        let localSnapshot = messages
        let continuityKeyOverride = continuityKeyOverride
        let verification = await Task.detached(priority: .userInitiated) {
            do {
                guard let key = try (continuityKeyOverride
                    ?? KeychainSessionLifecycleIntegrityKeyProvider().existingKey()) else {
                    return nil as SessionContinuityVerification?
                }
                return SessionTranscriptRecovery.verifyContinuity(
                    localMessages: localSnapshot,
                    backendHistoryURL: historyURL,
                    key: key
                )
            } catch {
                return nil
            }
        }.value
        guard tabSessionID == expectedTabID,
              currentWorkspace?.id == expectedWorkspaceID,
              let verification,
              [.verified, .backendOnly].contains(verification.receipt.status) else {
            recoveryCandidateError = "That history no longer verifies against this tab. No binding changed."
            return false
        }

        if !verification.backendMessages.isEmpty {
            let reconciled = SessionTranscriptReconciler.reconcile(
                local: localSnapshot,
                authoritative: verification.backendMessages
            )
            if SessionTranscriptReconciler.contentSignature(reconciled)
                != SessionTranscriptReconciler.contentSignature(localSnapshot) {
                messages = filteredPersistedMessages(reconciled)
                if let expectedTabID {
                    SessionMessageStore.replaceAfterAuthoritativeReconciliation(
                        messages,
                        for: expectedTabID
                    )
                }
                streamRevision &+= 1
            }
        }

        let entry = await makeForkLedgerEntry(
            predecessorBackendID: predecessor,
            successorBackendID: candidate.backendID,
            reason: .explicitRelink,
            localMessagesAtFork: messages
        )
        if let entry,
           !pendingForkLedgerEntries.contains(where: { $0.id == entry.id }) {
            pendingForkLedgerEntries.append(entry)
            boundForkLedgerEntry = entry
        }
        pendingRecoveryIntent = nil
        savedGrokSessionID = candidate.backendID
        continuityBackendID = candidate.backendID
        continuityReceipt = verification.receipt
        persistedContinuityReceipt = verification.receipt
        recoveryCandidateError = nil
        appendSystemNote(
            "Recovery choice: Relinked to verified backend …\(candidate.backendID.suffix(8))."
        )
        notifyMessagesChanged()
        return true
    }

    private enum SessionRecoveryReviewError: Error {
        case integrityKeyUnavailable
    }

    private static func verifyingContinuityReceipt(localMessageCount: Int) -> SessionContinuityReceipt {
        SessionContinuityReceipt(
            status: .verifying,
            reason: .verificationPending,
            normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
            authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
            localMessageCount: localMessageCount,
            backendMessageCount: 0,
            matchingPrefixCount: 0,
            localTranscriptTag: nil,
            backendTranscriptTag: nil,
            verifiedAt: Date()
        )
    }

    private static func localOnlyContinuityReceipt(localMessageCount: Int) -> SessionContinuityReceipt {
        SessionContinuityReceipt(
            status: .localOnly,
            reason: .noBackendBinding,
            normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
            authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
            localMessageCount: localMessageCount,
            backendMessageCount: 0,
            matchingPrefixCount: 0,
            localTranscriptTag: nil,
            backendTranscriptTag: nil,
            verifiedAt: Date()
        )
    }

    private static func recoveryForkedContinuityReceipt(
        localMessages: [Message],
        localTag: String?
    ) -> SessionContinuityReceipt {
        SessionContinuityReceipt(
            status: .recoveryForked,
            reason: .recoveryForked,
            normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
            authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
            localMessageCount: localMessages.filter {
                $0.role == .user || $0.role == .assistant
            }.count,
            backendMessageCount: 0,
            matchingPrefixCount: 0,
            localTranscriptTag: localTag,
            backendTranscriptTag: nil,
            verifiedAt: Date()
        )
    }

    /// Global default session agent from Settings → Agents (`grokbuild.selectedAgent`).
    private var defaultAgentSelection: String {
        defaults.string(forKey: GrokSettingsKeys.selectedAgent) ?? ""
    }

    /// The agent this tab will actually launch with: an explicit per-tab override when set,
    /// otherwise the global default.
    var effectiveAgentSelection: String {
        tabHasExplicitAgent ? currentAgent : defaultAgentSelection
    }

    /// `true` when this tab overrides the global default agent.
    var hasExplicitAgent: Bool { tabHasExplicitAgent }

    /// Display label for the tab's effective session agent.
    var effectiveAgentDisplayName: String {
        GrokAgentProfiles.displayName(for: effectiveAgentSelection)
    }

    /// The value to persist for this tab (nil when it follows the global default).
    var persistedAgentSelection: String? {
        tabHasExplicitAgent ? currentAgent : nil
    }

    var persistedModelIntent: TabModelIntent {
        tabModelIntent
    }

    var persistedModelExecutionState: ModelExecutionState { modelExecutionState }

    var persistedAgentIntent: TabAgentIntent {
        tabHasExplicitAgent ? .explicit(currentAgent) : tabAgentIntent
    }

    /// Set this session's agent and restart its grok process (agents can only change at launch).
    func setSessionAgent(_ selection: String) async {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        // No-op when this tab already explicitly uses the chosen agent.
        if tabHasExplicitAgent, trimmed == currentAgent { return }
        currentAgent = trimmed
        tabHasExplicitAgent = true
        tabAgentIntent = .explicit(trimmed)
        notifyAgentChanged()
        guard currentWorkspace != nil else { return }
        await restartProcess(resumeSessionID: grokSessionId ?? savedGrokSessionID)
        appendSystemNote("Switched session agent to \(GrokAgentProfiles.displayName(for: trimmed)).")
    }

    /// Load agents discovered for the current workspace (reloads when the workspace changes).
    func loadDiscoveredAgentsIfNeeded() async {
        guard let workspaceID = currentWorkspace?.id,
              loadedAgentsWorkspaceID != workspaceID else { return }
        loadedAgentsWorkspaceID = workspaceID
        let agents = (try? await GrokCLIService().listAgents(cwd: currentWorkspace?.path)) ?? []
        discoveredAgents = agents
    }

    /// Reload per-project reasoning effort only (model stays per tab).
    func syncWorkspaceReasoningEffortFromStorage() {
        loadWorkspaceReasoningEffort()
    }

    /// @deprecated Use `syncWorkspaceReasoningEffortFromStorage()` — model is per tab now.
    func syncWorkspaceAgentSettingsFromStorage() {
        syncWorkspaceReasoningEffortFromStorage()
    }

    /// Refresh this tab from its own live receipt when switching tabs. Process launch
    /// already carried the resolved model; selection must not issue a hidden second
    /// `session/set_model` merely to make the picker look confirmed.
    func syncTabModelToLiveProcessIfNeeded() {
        guard process.launchReceipt?.localTabID == tabSessionID,
              process.activeProcessGeneration != nil else { return }
        modelExecutionState = process.modelExecutionState
        if modelExecutionState.status == .confirmed,
           let effective = modelExecutionState.effectiveModelID {
            currentModel = effective
        }
    }

    func clearProject() {
        resetSessionUI()
        currentWorkspace = nil
    }

    private func resetSessionUI() {
        messages.removeAll()
        streamingMessageID = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
        goalState = nil
        clearWorkflowRunState()
        clearBackgroundTaskState()
        promptQueue.removeAll()
        btwAsideText = nil
        pendingBtw = false
        pendingShareURLCapture = false
        clearTurnState()
        connectionState = .idle
        lastError = nil
    }

    var hasUserMessages: Bool {
        messages.contains { $0.role == .user }
    }

    func start(workspace: Workspace, resumeSession: GrokSessionInfo? = nil, preserveMessages: Bool = false) async {
        currentWorkspace = workspace
        mergeCustomModels()
        loadWorkspaceReasoningEffort()
        if !preserveMessages {
            clearTransientSessionState()
        } else {
            clearTurnState()
        }
        await restartProcess(resumeSessionID: resumeSession?.id)
    }

    /// Restore a previously saved transcript when reopening a session tab.
    func restorePersistedMessages(_ saved: [Message]) {
        messages = filteredPersistedMessages(saved)
        streamingMessageID = nil
        if let pendingRecoveryIntent {
            continuityReceipt = Self.recoveryForkedContinuityReceipt(
                localMessages: messages,
                localTag: pendingRecoveryIntent.transcriptTag
            )
            persistedContinuityReceipt = continuityReceipt
        } else if savedGrokSessionID == nil {
            continuityReceipt = Self.localOnlyContinuityReceipt(localMessageCount: messages.count)
            persistedContinuityReceipt = continuityReceipt
        }
    }

    /// Load persisted (and optionally grok on-disk) transcript for a tab.
    func restorePersistedMessages(
        for sessionID: UUID,
        grokSessionID: String?,
        workspace: Workspace
    ) {
        let saved = SessionMessageStore.messages(for: sessionID)
        let recovered = SessionTranscriptRecovery.recoverIfNeeded(
            sessionID: sessionID,
            grokSessionID: grokSessionID,
            workspacePath: workspace.path,
            currentMessages: saved
        )
        restorePersistedMessages(recovered ?? saved)
    }

    /// A lazy `session/load` can finish after tab selection and, for some provider
    /// backends, leave the prepared in-memory transcript empty even though the tab's
    /// durable local transcript is intact. Rehydrate only that empty post-start state;
    /// never replace visible/newer local work.
    @discardableResult
    func recoverPersistedMessagesAfterStartIfEmpty(
        for sessionID: UUID,
        grokSessionID: String?,
        workspace: Workspace
    ) -> Bool {
        guard messages.isEmpty,
              SessionMessageStore.hasRestorableTranscript(for: sessionID) else {
            return false
        }
        restorePersistedMessages(
            for: sessionID,
            grokSessionID: grokSessionID,
            workspace: workspace
        )
        return !messages.isEmpty
    }

    /// Re-run the bounded exact-history reconciliation when selecting an already-loaded
    /// tab. This closes the window where the tab was restored before a late backend final
    /// was durable, without scanning or polling any unrelated session directory.
    func reconcilePersistedMessages(
        for sessionID: UUID,
        grokSessionID: String?,
        workspace: Workspace
    ) {
        mergePersistedMessages(SessionMessageStore.messages(for: sessionID))
        if let recovered = SessionTranscriptRecovery.recoverIfNeeded(
            sessionID: sessionID,
            grokSessionID: grokSessionID,
            workspacePath: workspace.path,
            currentMessages: messages
        ) {
            restorePersistedMessages(recovered)
        }
    }

    /// Merge disk transcript into memory without dropping messages already loaded.
    func mergePersistedMessages(_ saved: [Message]) {
        let filtered = filteredPersistedMessages(saved)
        guard !filtered.isEmpty else { return }
        if messages.isEmpty {
            messages = filtered
            streamingMessageID = nil
            return
        }
        var seen = Set(messages.map(\.id))
        for message in filtered where !seen.contains(message.id) {
            messages.append(message)
            seen.insert(message.id)
        }
        streamingMessageID = nil
    }

    // setAgent for personas removed - use CLI's AGENTS.md, skills, or --agent for custom profiles.

    func reloadConfiguration() async {
        guard currentWorkspace != nil else { return }
        // Never kill an in-flight response for a wiring change — queue it like model
        // changes are queued, and apply it when the turn completes.
        if isStreaming {
            pendingRuntimeReload = true
            configurationStatusMessage = "Configuration changes will apply after the current response."
            return
        }
        await performRuntimeReload()
    }

    /// Restarts with the current grok session resumed, so browser/computer-use/MCP/
    /// permission wiring changes keep the live conversation context instead of silently
    /// dropping it with a fresh `session/new`.
    private func performRuntimeReload() async {
        pendingRuntimeReload = false
        if configurationStatusMessage == "Configuration changes will apply after the current response." {
            configurationStatusMessage = nil
        }
        let resumeID = grokSessionId ?? savedGrokSessionID
        await restartProcess(resumeSessionID: resumeID)
        if connectionState == .ready {
            appendSystemNote("Reloaded Grok configuration.")
        } else {
            configurationStatusMessage = lastError ?? "Grok configuration could not be reloaded."
        }
    }

    /// Applies a typed config change without restarting unrelated live sessions.
    func applyConfigurationChange(_ change: ConfigurationChange) async {
        mergeCustomModels()
        guard change.impact == .modelRuntime,
              !change.affectedModelIDs.isEmpty,
              change.affectedModelIDs.contains(currentModel),
              currentWorkspace != nil else {
            return
        }

        if isStreaming {
            if var pending = pendingConfigurationChange {
                pending.affectedModelIDs.formUnion(change.affectedModelIDs)
                pendingConfigurationChange = pending
            } else {
                pendingConfigurationChange = change
            }
            configurationStatusMessage = "Model changes will apply after the current response."
            return
        }

        await applyRuntimeConfigurationChange()
    }

    private func applyRuntimeConfigurationChange() async {
        pendingConfigurationChange = nil
        // One restart applies the whole current launch configuration, so a general
        // reload queued during the same turn is satisfied here too.
        pendingRuntimeReload = false
        isApplyingConfiguration = true
        configurationStatusMessage = "Applying model configuration…"
        let resumeID = grokSessionId ?? savedGrokSessionID
        await restartProcess(resumeSessionID: resumeID)
        isApplyingConfiguration = false
        if connectionState == .ready {
            configurationStatusMessage = "Model configuration applied."
            appendSystemNote("Applied updated model configuration.")
        } else {
            configurationStatusMessage = lastError ?? "Model configuration could not be applied."
        }
    }

    func startNewSession() async {
        let predecessorBackendID = durableGrokSessionID
        let localMessagesAtFork = messages
        messages.removeAll()
        streamingMessageID = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
        goalState = nil
        clearWorkflowRunState()
        if currentWorkspace != nil {
            await restartProcess()
            if let predecessorBackendID,
               let successorBackendID = process.sessionId,
               predecessorBackendID != successorBackendID {
                await recordRecoveryFork(
                    predecessorBackendID: predecessorBackendID,
                    successorBackendID: successorBackendID,
                    reason: .explicitFreshStart,
                    localMessagesAtFork: localMessagesAtFork
                )
            }
        }
    }

    func resumeSession(_ session: GrokSessionInfo) async {
        guard currentWorkspace != nil else {
            lastError = "Select a project first."
            return
        }
        clearTransientSessionState()
        await restartProcess(resumeSessionID: session.id)
    }

    /// Clears in-flight turn UI and pending prompts without wiping the saved transcript.
    private func clearTransientSessionState() {
        streamingMessageID = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
        goalState = nil
        messages.removeAll()
        clearWorkflowRunState()
        clearTurnState()
    }

    private func clearWorkflowRunState() {
        workflowRunTracker.reset()
        workflowRuns = []
    }

    private func clearBackgroundTaskState() {
        backgroundTaskTracker.reset()
        backgroundActivities = []
    }

    private func restartProcess(resumeSessionID: String? = nil) async {
        guard let ws = currentWorkspace else { return }
        // A populated restored tab always belongs to its saved backend session. Several
        // asynchronous launch paths can request a restart without carrying that id; resolving
        // it centrally prevents any of them from silently replacing the visible conversation
        // with a fresh default-model session.
        let effectiveResumeSessionID = Self.resolvedResumeSessionID(
            requested: resumeSessionID,
            saved: savedGrokSessionID,
            hasUserMessages: hasUserMessages
        )
        if let effectiveResumeSessionID {
            let status = await verifyContinuityBeforeResume(backendID: effectiveResumeSessionID)
            guard SessionSendGate.decision(for: status) != .block else {
                connectionWatchdogTask?.cancel()
                connectionState = .idle
                lastError = nil
                return
            }
        } else {
            continuityReceipt = Self.localOnlyContinuityReceipt(localMessageCount: messages.count)
            persistedContinuityReceipt = continuityReceipt
            continuityBackendID = nil
        }
        let hadLocalConversationBeforeStart = messages.contains {
            $0.role == .user
                || ($0.role == .assistant
                    && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        clearTurnState()
        isStreaming = false
        streamingMessageID = nil
        connectionWatchdogTask?.cancel()
        usedContextTokens = nil
        connectionState = .starting
        lastError = nil
        startConnectionWatchdog()
        applyBuiltInModelCatalog(await GrokModelCatalog.shared.models())
        let settings = loadPermissionSettings()
        let savedSelection = effectiveResumeSessionID.flatMap { sessionSelections[$0] }
        let modelForLaunch = modelForProcessLaunch(fallbackSelection: savedSelection)
        let reasoningEffortForLaunch = modelSupportsReasoningEffort(modelForLaunch) ? workspaceReasoningEffort : ""
        let browserSettings = BrowserSettingsStore.loadApplied()
        let computerUseSettings = ComputerUseSettingsStore.loadApplied()
        if browserSettings.enabled {
            do {
                try BrowserSkillInstaller.installIfNeeded(settings: browserSettings)
            } catch {
                lastError = "Browser skill install failed: \(error.localizedDescription)"
            }
            do {
                _ = try await AgentBrowserService.ensureExternalBrowserStarted(settings: browserSettings)
            } catch {
                lastError = "External browser auto-start failed: \(error.localizedDescription)"
            }
        }
        if computerUseSettings.enabled {
            do {
                try ComputerUseSkillInstaller.installIfNeeded(settings: computerUseSettings)
            } catch {
                lastError = "Computer Use skill install failed: \(error.localizedDescription)"
            }
        }
        let mcpServers = [
            AgentBrowserService.browserMCPConfig(settings: browserSettings),
            ComputerUseService.computerUseMCPConfig(settings: computerUseSettings)
        ].compactMap { $0 }
        let opts = GrokLaunchOptions(
            localTabID: tabSessionID,
            agent: GrokAgentProfiles.launchArgument(for: effectiveAgentSelection),
            // Memory is a single app-scoped toggle: on → `--experimental-memory`, off → `--no-memory`.
            noMemory: !settings.memoryEnabled,
            experimentalMemory: settings.memoryEnabled,
            permissionMode: settings.permissionMode,
            reasoningEffort: reasoningEffortForLaunch,
            model: modelForLaunch.isEmpty ? nil : modelForLaunch,
            sandboxProfile: settings.sandboxProfile,
            disableWebSearch: settings.disableWebSearch,
            noSubagents: settings.noSubagents,
            allowRules: lineList(settings.allowRules),
            denyRules: lineList(settings.denyRules),
            resumeSessionID: effectiveResumeSessionID,
            forkSession: launchForkSession,
            newSessionID: launchNewSessionID,
            mcpServers: mcpServers
        )
        let spawnInterval = GrokBuildPerformance.begin(.processSpawnToACPReady)
        await process.start(workspace: ws, options: opts)
        spawnInterval.end()
        connectionWatchdogTask?.cancel()
        connectionState = process.state
        if case .failed(let message) = process.state {
            lastError = message
            return
        }
        let resumedBackendID = effectiveResumeSessionID
        if process.sessionLoadStartedFreshFallback,
           let oldBackendID = resumedBackendID,
           let sessionID = tabSessionID,
           let reconciliation = SessionTranscriptRecovery.reconcile(
               sessionID: sessionID,
               grokSessionID: oldBackendID,
               workspacePath: ws.path,
               currentMessages: messages
           ) {
            if reconciliation.changed {
                messages = filteredPersistedMessages(reconciliation.messages)
                streamRevision &+= 1
            }
        }
        savedGrokSessionID = process.sessionId ?? effectiveResumeSessionID
        continuityBackendID = savedGrokSessionID
        if let successorBackendID = process.sessionId {
            let forkReason: SessionForkLedgerReason? = {
                if process.sessionLoadStartedFreshFallback { return .resumeFallback }
                if launchForkSession { return .explicitBackendFork }
                if effectiveResumeSessionID == nil, hadLocalConversationBeforeStart {
                    return pendingRecoveryIntent?.action == .continueAsNew
                        ? .explicitContinueAsNew
                        : .localOnlyStart
                }
                return nil
            }()
            if let forkReason {
                await recordRecoveryFork(
                    predecessorBackendID: pendingRecoveryIntent?.predecessorBackendID
                        ?? effectiveResumeSessionID,
                    successorBackendID: successorBackendID,
                    reason: forkReason
                )
                if forkReason == .explicitContinueAsNew {
                    pendingRecoveryIntent = nil
                }
            }
        }
        modelExecutionState = process.modelExecutionState
        availableModes = process.availableModes
        syncModelsFromProcess()
        if process.sessionLoadStartedFreshFallback {
            let hasLocalTranscript = messages.contains {
                $0.role == .user
                    || ($0.role == .assistant
                        && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let oldID = resumedBackendID ?? "unknown"
            let newID = savedGrokSessionID ?? "unknown"
            if hasLocalTranscript {
                appendSystemNote(
                    "Session recovery fork: \(oldID) could not resume, so GrokBuild reconciled its available transcript and continued as \(newID)."
                )
            } else {
                appendSystemNote(
                    "Session recovery fork: \(oldID) could not resume and no prior transcript was recoverable; continued as \(newID)."
                )
            }
            notifyMessagesChanged()
        }
        restoreSessionSelection(savedSelection)
        saveCurrentSessionSelection()
        if !process.availableSlashCommands.isEmpty {
            applyAvailableSlashCommands(process.availableSlashCommands)
        }
    }

    nonisolated static func resolvedResumeSessionID(
        requested: String?,
        saved: String?,
        hasUserMessages: Bool
    ) -> String? {
        if let requested, !requested.isEmpty { return requested }
        guard hasUserMessages, let saved, !saved.isEmpty else { return nil }
        return saved
    }

    private func recordRecoveryFork(
        predecessorBackendID: String?,
        successorBackendID: String,
        reason: SessionForkLedgerReason,
        localMessagesAtFork: [Message]? = nil
    ) async {
        let localMessages = localMessagesAtFork ?? messages
        guard let entry = await makeForkLedgerEntry(
            predecessorBackendID: predecessorBackendID,
            successorBackendID: successorBackendID,
            reason: reason,
            localMessagesAtFork: localMessages
        ) else { return }
        if !pendingForkLedgerEntries.contains(where: {
            $0.predecessorBackendID == entry.predecessorBackendID
                && $0.successorBackendID == entry.successorBackendID
                && $0.reason == entry.reason
        }) {
            pendingForkLedgerEntries.append(entry)
        }
        continuityReceipt = SessionContinuityReceipt(
            status: .recoveryForked,
            reason: .recoveryForked,
            normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
            authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
            localMessageCount: localMessages.filter { $0.role == .user || $0.role == .assistant }.count,
            backendMessageCount: 0,
            matchingPrefixCount: 0,
            localTranscriptTag: entry.transcriptTag,
            backendTranscriptTag: nil,
            verifiedAt: Date()
        )
        persistedContinuityReceipt = continuityReceipt
        boundForkLedgerEntry = entry
        notifyMessagesChanged()
    }

    private func makeForkLedgerEntry(
        predecessorBackendID: String?,
        successorBackendID: String,
        reason: SessionForkLedgerReason,
        localMessagesAtFork: [Message]
    ) async -> SessionForkLedgerEntry? {
        guard let localSessionID = tabSessionID else { return nil }
        let continuityKeyOverride = continuityKeyOverride
        let localTag = await Task.detached(priority: .utility) {
            guard let key = continuityKeyOverride
                ?? (try? KeychainSessionLifecycleIntegrityKeyProvider().existingKey()) else {
                return nil as String?
            }
            return SessionTranscriptRecovery.transcriptSequenceTag(
                localMessagesAtFork,
                key: key
            )
        }.value
        return SessionForkLedgerEntry(
            id: UUID(),
            localSessionID: localSessionID,
            predecessorBackendID: predecessorBackendID,
            successorBackendID: successorBackendID,
            reason: reason,
            createdAt: Date(),
            localMessageCountAtFork: localMessagesAtFork.count,
            transcriptTag: localTag
        )
    }

    private func startConnectionWatchdog() {
        connectionWatchdogTask?.cancel()
        connectionWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            await self?.markConnectionTimedOutIfNeeded()
        }
    }

    private func markConnectionTimedOutIfNeeded() async {
        guard connectionState == .starting else { return }
        lastError = process.state.errorMessage ?? "Timed out while connecting to grok."
        connectionState = .failed(lastError ?? "Timed out while connecting to grok.")
        await process.stop()
    }

    // MARK: Messaging

    @discardableResult
    func send(_ text: String) async -> Bool {
        await deliverPrompt(text, waitForCompletion: false)
    }

    @discardableResult
    func sendAndWait(_ text: String) async -> Bool {
        await deliverPrompt(text, waitForCompletion: true)
    }

    var hasGoalCommand: Bool {
        availableSlashCommands.contains { $0.name == "goal" }
    }

    @discardableResult
    func setGoal(_ objective: String, budget: Int? = nil) async -> Bool {
        let trimmed = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let budget {
            return await send("/goal \(trimmed) --budget \(budget)")
        }
        return await send("/goal \(trimmed)")
    }

    var hasShareCommand: Bool {
        availableSlashCommands.contains { $0.name == "share" }
    }

    var hasBtwCommand: Bool {
        availableSlashCommands.contains { $0.name == "btw" }
    }

    var hasCreateSkillCommand: Bool {
        availableSlashCommands.contains { $0.name == "create-skill" }
    }

    var hasForkCommand: Bool {
        availableSlashCommands.contains { $0.name == "fork" }
    }

    @discardableResult
    func shareSession() async -> Bool {
        pendingShareURLCapture = true
        let ok = await send("/share")
        if !ok {
            // Avoid capturing an unrelated later assistant URL if /share never started.
            pendingShareURLCapture = false
        }
        return ok
    }

    func copyLastSharedURLToPasteboard() -> Bool {
        guard let lastSharedURL else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastSharedURL, forType: .string)
        return true
    }

    func removeQueuedPrompt(at index: Int) {
        guard promptQueue.indices.contains(index) else { return }
        promptQueue.remove(at: index)
    }

    func enqueuePrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        promptQueue.append(trimmed)
    }

    func sendQueuedPromptNow(at index: Int) async -> Bool {
        guard promptQueue.indices.contains(index) else { return false }
        guard !isStreaming else {
            lastError = "Wait for the current response to finish."
            return false
        }
        let text = promptQueue.remove(at: index)
        let ok = await deliverPrompt(text, waitForCompletion: false, fromQueue: true)
        if !ok {
            // Put the prompt back so a failed send does not drop queued work.
            let insertAt = min(index, promptQueue.count)
            promptQueue.insert(text, at: insertAt)
        }
        return ok
    }

    func clearBtwAside() {
        btwAsideText = nil
    }

    /// Start a new grok process forked from an existing session id (new tab).
    func startForked(workspace: Workspace, fromSessionID: String) async {
        currentWorkspace = workspace
        mergeCustomModels()
        loadWorkspaceReasoningEffort()
        launchForkSession = true
        launchNewSessionID = UUID().uuidString
        clearTransientSessionState()
        await restartProcess(resumeSessionID: fromSessionID)
        launchForkSession = false
        launchNewSessionID = nil
        appendSystemNote("Forked from session \(fromSessionID.prefix(8))…")
    }

    @discardableResult
    func forkIntoWorktree(branch: String, path: String, fromSessionID: String?) async -> Bool {
        if hasForkCommand {
            var command = "/fork --worktree"
            if !branch.isEmpty { command += " --branch \(branch)" }
            if !path.isEmpty { command += " --path \(path)" }
            return await send(command)
        }
        guard let fromSessionID else { return false }
        // Fallback: caller should create worktree via GitService then startForked.
        _ = fromSessionID
        return false
    }

    @discardableResult
    func refreshGoalStatus() async -> Bool {
        await send("/goal status")
    }

    @discardableResult
    func pauseGoal() async -> Bool {
        await send("/goal pause")
    }

    @discardableResult
    func resumeGoal() async -> Bool {
        await send("/goal resume")
    }

    @discardableResult
    func clearGoal() async -> Bool {
        await send("/goal clear")
    }

    // MARK: - Scheduled tasks

    /// True when grok advertises the `/loop` command (scheduling is available in this session).
    var hasLoopCommand: Bool {
        availableSlashCommands.contains { $0.name == "loop" }
    }

    /// Ask grok to enumerate its scheduled tasks (drives `scheduler_list`); the reply's tool
    /// output refreshes ``scheduledTasks`` authoritatively.
    @discardableResult
    func refreshScheduledTasks() async -> Bool {
        await send("List all my scheduled tasks (use scheduler_list) and do nothing else.")
    }

    /// Schedule a recurring prompt via grok's `/loop` command.
    @discardableResult
    func createScheduledTask(interval: String, prompt: String) async -> Bool {
        let trimmedInterval = interval.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInterval.isEmpty, !trimmedPrompt.isEmpty else { return false }
        return await send("/loop \(trimmedInterval) \(trimmedPrompt)")
    }

    /// Ask grok to cancel a scheduled task by id (drives `scheduler_delete`).
    @discardableResult
    func cancelScheduledTask(_ id: String) async -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("Cancel the scheduled task with id \(trimmed) (use scheduler_delete) and do nothing else.")
    }

    // MARK: - Workflow runs

    var hasWorkflowCommand: Bool {
        availableSlashCommands.contains { $0.name == "workflow" || $0.name == "workflows" }
    }

    var hasDeepResearchCommand: Bool {
        availableSlashCommands.contains { $0.name == "deep-research" }
    }

    @discardableResult
    func refreshWorkflowRuns() async -> Bool {
        if hasWorkflowCommand {
            return await send("/workflows")
        }
        return await send("List all my workflow runs (use the workflow tool) and do nothing else.")
    }

    @discardableResult
    func pauseWorkflowRun(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("/workflow pause \(trimmed)")
    }

    @discardableResult
    func resumeWorkflowRun(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("/workflow resume \(trimmed)")
    }

    @discardableResult
    func stopWorkflowRun(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("/workflow stop \(trimmed)")
    }

    @discardableResult
    func startDeepResearch(_ query: String) async -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return await send("/deep-research \(trimmed)")
    }

    @discardableResult
    func launchSavedWorkflow(name: String, args: [String: Any]? = nil) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let args, !args.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: args),
           let json = String(data: data, encoding: .utf8) {
            return await send("/workflow \(trimmed) \(json)")
        }
        return await send("/workflow \(trimmed)")
    }

    // MARK: - Memory

    /// Save a note to grok's global memory (`~/.grok/memory/MEMORY.md`). grok's file watcher
    /// reindexes it on the next memory search, so it becomes recallable in future sessions.
    ///
    /// This writes the file directly rather than sending `/remember`: that slash command is a
    /// TUI-only pager builtin and is not exposed over `grok agent stdio` (ACP).
    @discardableResult
    func remember(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let url = try MemoryStore.appendGlobalNote(trimmed)
            appendSystemNote("Remembered — saved to \(url.path).")
            return true
        } catch {
            lastError = "Couldn't save memory note: \(error.localizedDescription)"
            return false
        }
    }

    private func deliverPrompt(_ text: String, waitForCompletion: Bool, fromQueue: Bool = false) async -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || fileAttachments.contains(where: { !$0.isHidden }) else { return false }
        guard currentWorkspace != nil else {
            lastError = "Select a project first."
            return false
        }
        if continuityBlocksSend, continuityStatus != .verifying {
            return false
        }
        if isStreaming {
            if waitForCompletion {
                lastError = "Wait for the current response to finish."
                return false
            }
            if !fromQueue {
                enqueuePrompt(trimmed)
                return true
            }
            lastError = "Wait for the current response to finish."
            return false
        }
        if connectionState != .ready {
            if process.sessionId == nil && connectionState != .starting {
                // Restored tabs render their local transcript before the live Grok
                // session finishes its lazy resume. If the user sends during that
                // window, resume the saved session here too; starting without its id
                // silently forks the visible conversation onto the default model.
                await restartProcess(resumeSessionID: savedGrokSessionID)
            }
            guard connectionState == .ready else {
                if lastError == nil {
                    lastError = connectionState == .starting
                        ? "Grok is still starting…"
                        : connectionState.errorMessage ?? "Grok is not ready yet."
                }
                return false
            }
        }
        guard SessionSendGate.decision(for: continuityStatus) != .block else {
            return false
        }

        if commandHistory.last != trimmed {
            commandHistory.append(trimmed)
        }
        historyIndex = nil

        clearTurnState()
        isGrokking = true
        turnStartedAt = Date()
        startStallWatchdog()

        if let attachmentBlock = AttachmentPromptBuilder.build(from: fileAttachments) {
            trimmed = trimmed.isEmpty ? attachmentBlock : "\(attachmentBlock)\n\n\(trimmed)"
        }
        if let goalCommand = GoalCommand.parse(from: trimmed) {
            SessionGoalStateMutation.apply(goalCommand, to: &goalState)
        }
        if trimmed.lowercased().hasPrefix("/btw") {
            pendingBtw = true
        }
        fileAttachments.removeAll()

        let userMsg = Message(role: .user, content: trimmed)
        messages.append(userMsg)
        notifyMessagesChanged()

        let assistant = Message(role: .assistant, content: "")
        messages.append(assistant)
        streamingMessageID = assistant.id
        activeTurnBackendSessionID = durableGrokSessionID
        let turnGeneration = turnSettlement.begin(assistantID: assistant.id)
        firstChunkInterval?.end()
        firstChunkInterval = GrokBuildPerformance.begin(.firstSendToFirstChunk)
        isStreaming = true
        lastError = nil
        authRequiredMessage = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        connectionState = .busy

        let payload = trimmed

        if waitForCompletion {
            let ok = await process.send(payload)
            applyTurnSettlementDecision(
                turnSettlement.recordPromptResult(generation: turnGeneration, ok: ok)
            )
            return ok
        }

        Task { [weak self] in
            guard let self else { return }
            let ok = await self.process.send(payload)
            self.applyTurnSettlementDecision(
                self.turnSettlement.recordPromptResult(generation: turnGeneration, ok: ok)
            )
        }

        return true
    }

    private func finishPrompt(assistantID: UUID, ok: Bool) {
        if !streamingTextBuffer.isEmpty || streamingTextFlushTask != nil {
            deferredPromptCompletion = (assistantID, ok)
            scheduleStreamingTextFlushIfNeeded()
            return
        }
        finishPromptNow(assistantID: assistantID, ok: ok)
    }

    private func finishPromptNow(assistantID: UUID, ok: Bool) {
        firstChunkInterval?.end()
        firstChunkInterval = nil
        let settledAssistantID = authoritativeTailAssistantID ?? assistantID
        if ok, let idx = messages.firstIndex(where: { $0.id == settledAssistantID }) {
            captureAsideAndShare(from: messages[idx].content)
        }

        isStreaming = false
        isGrokking = false
        turnStartedAt = nil
        streamingMessageID = nil
        closedTurnAssistantID = ok ? settledAssistantID : nil
        stopStallWatchdog()
        if let start = thinkingStartedAt, !thinkingText.isEmpty {
            thinkingDuration = Date().timeIntervalSince(start)
        }
        if ok {
            connectionState = .ready
            notifyMessagesChanged()
            activeTurnBackendSessionID = nil
            authoritativeTailAssistantID = nil
            if pendingConfigurationChange != nil {
                Task { [weak self] in
                    guard let self else { return }
                    await self.applyRuntimeConfigurationChange()
                    self.drainPromptQueueIfNeeded()
                }
            } else if pendingRuntimeReload {
                Task { [weak self] in
                    guard let self else { return }
                    await self.performRuntimeReload()
                    self.drainPromptQueueIfNeeded()
                }
            } else {
                drainPromptQueueIfNeeded()
            }
            return
        }

        pendingShareURLCapture = false
        closedTurnHasAuthoritativeHistory = false
        authoritativeTailAssistantID = nil
        activeTurnBackendSessionID = nil
        lastError = process.state.errorMessage ?? "Failed to send to grok."
        connectionState = process.state == .ready ? .ready : process.state
        if let idx = messages.firstIndex(where: { $0.id == assistantID }),
           messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: idx)
        }
        notifyMessagesChanged()
    }

    private func applyTurnSettlementDecision(_ decision: TurnSettlementCoordinator.Decision?) {
        guard let decision else { return }
        finishPrompt(assistantID: decision.assistantID, ok: decision.ok)
    }

    private func drainPromptQueueIfNeeded() {
        guard !isStreaming, !promptQueue.isEmpty else { return }
        let next = promptQueue.removeFirst()
        Task { [weak self] in
            _ = await self?.deliverPrompt(next, waitForCompletion: false)
        }
    }

    private func captureAsideAndShare(from assistantText: String) {
        let trimmed = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if pendingBtw {
            btwAsideText = trimmed
            pendingBtw = false
        }
        if pendingShareURLCapture, let url = ShareURLParser.firstURL(in: trimmed) {
            lastSharedURL = url
            pendingShareURLCapture = false
            appendSystemNote("Share link copied to clipboard.")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        }
    }

    func toggleThinkingExpanded() {
        isThinkingExpanded.toggle()
    }

    func clearTurnState() {
        firstChunkInterval?.end()
        firstChunkInterval = nil
        cancelStreamingTextFlush()
        invalidateTurnSettlement()
        isGrokking = false
        thinkingText = ""
        thinkingDuration = nil
        thinkingStartedAt = nil
        turnStartedAt = nil
        isThinkingExpanded = false
        liveToolCalls = []
    }

    private func invalidateTurnSettlement() {
        turnSettlement.invalidate()
        activeTurnBackendSessionID = nil
        authoritativeTailAssistantID = nil
        closedTurnAssistantID = nil
        closedTurnHasAuthoritativeHistory = false
    }

    func stop() {
        firstChunkInterval?.end()
        firstChunkInterval = nil
        cancelStreamingTextFlush()
        invalidateTurnSettlement()
        isStreaming = false
        isGrokking = false
        turnStartedAt = nil
        streamingMessageID = nil
        stopStallWatchdog()
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        process.interrupt()
        connectionState = .ready
    }

    func shutdown() async {
        firstChunkInterval?.end()
        firstChunkInterval = nil
        cancelStreamingTextFlush()
        invalidateTurnSettlement()
        connectionWatchdogTask?.cancel()
        stopStallWatchdog()
        isStreaming = false
        isGrokking = false
        streamingMessageID = nil
        await process.stop()
        connectionState = .idle
    }

    /// Terminal variant of `shutdown()` for a closed tab or app quit: also ends the
    /// process's ACP event stream, which terminates `consumeOutput()` and lets the
    /// store/process pair deallocate. A store must not reconnect after this.
    func shutdownPermanently() async {
        firstChunkInterval?.end()
        firstChunkInterval = nil
        cancelStreamingTextFlush()
        invalidateTurnSettlement()
        connectionWatchdogTask?.cancel()
        stopStallWatchdog()
        isStreaming = false
        isGrokking = false
        streamingMessageID = nil
        await process.shutdown()
        connectionState = .idle
    }

    func respondToExitPlan(_ request: ExitPlanRequest, verdict: ExitPlanRequest.PlanVerdict, comment: String = "") {
        process.respondToExitPlan(request.id.base, verdict: verdict)
        let marker: String
        switch verdict {
        case .approved: marker = "[Plan approved]"
        case .rejected: marker = "[Plan rejected]"
        case .abandoned: marker = "[Plan cancelled]"
        }
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = trimmedComment.isEmpty ? marker : "\(marker) \(trimmedComment)"
        Task { _ = await send(payload) }
        pendingExitPlan = nil
    }

    func respondToQuestion(_ request: QuestionRequest, answers: [String: String]) {
        process.respondToQuestion(request.id.base, answers: answers)
        pendingQuestions.removeAll { $0.id == request.id }
    }

    func cancelQuestion(_ request: QuestionRequest) {
        process.respondToQuestionCancelled(request.id.base)
        pendingQuestions.removeAll { $0.id == request.id }
    }

    func addFileAttachment(path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !fileAttachments.contains(where: { $0.path == standardized }) else { return }
        fileAttachments.append(FileAttachment(path: standardized, workspaceRoot: currentWorkspace?.path))
    }

    func removeFileAttachment(id: UUID) {
        fileAttachments.removeAll { $0.id == id }
    }

    func toggleFileAttachmentHidden(id: UUID) {
        guard let idx = fileAttachments.firstIndex(where: { $0.id == id }) else { return }
        fileAttachments[idx].isHidden.toggle()
    }

    var hasVisibleFileAttachments: Bool {
        fileAttachments.contains { !$0.isHidden }
    }

    func respondToPermission(_ request: PermissionRequest, with optionId: String) {
        // Permission is an ACP decision only. The CLI remains the sole executor so its
        // sandbox, deny rules, and hooks cannot be bypassed by a client-side file write.
        process.respondToPermission(request, with: optionId)
        pendingPermissions.removeAll { $0.id == request.id }
    }

    private func denyPermission(_ request: PermissionRequest, optionID: String?) {
        if let optionID {
            process.respondToPermission(request, with: optionID)
        } else {
            process.rejectPermission(
                request,
                reason: "The effective GrokBuild launch policy denied this unapproved tool request."
            )
        }
        pendingPermissions.removeAll { $0.id == request.id }
    }

    private func recordAutomaticPermissionDecision(
        _ request: PermissionRequest,
        allowed: Bool,
        mode: GrokPermissionMode
    ) {
        let receipt = LiveToolCall(
            id: request.toolCall.id,
            title: displayTitle(for: request.toolCall),
            kind: displayKind(for: request.toolCall),
            status: allowed ? "completed" : "rejected",
            detail: allowed
                ? "Allowed automatically by the live \(mode.displayName) policy."
                : "Denied automatically by the live \(mode.displayName) policy."
        )
        if let index = liveToolCalls.firstIndex(where: { $0.id == receipt.id }) {
            liveToolCalls[index] = receipt
        } else {
            liveToolCalls.append(receipt)
        }
    }

    func setMode(_ mode: AgentMode) {
        process.setMode(mode)
        // Optimistically update; will be confirmed by modeChanged event
        currentMode = mode
        isYolo = (mode == .yolo)
        saveCurrentSessionSelection()
    }

    /// Convenience for the three common modes
    func setAgentMode() { setMode(.agent) }
    func setPlanMode()  { setMode(.plan) }
    func setYoloMode()  { setMode(.yolo) }

    var currentReasoningEffort: String {
        workspaceReasoningEffort
    }

    var currentReasoningEffortLevel: ReasoningEffortLevel {
        ReasoningEffortLevel(storedValue: currentReasoningEffort)
    }

    func reasoningEffortDisplayName(_ raw: String) -> String {
        ReasoningEffortLevel(storedValue: raw).displayName
    }

    func needsReasoningEffortConfirmation(for effort: String) -> Bool {
        effort != currentReasoningEffort && hasUserMessages
    }

    func applyReasoningEffort(_ effort: String, strategy: ReasoningEffortRestartStrategy) async {
        guard effort != currentReasoningEffort else { return }
        workspaceReasoningEffort = effort
        saveWorkspaceAgentSettings()
        guard currentWorkspace != nil else { return }

        if strategy == .summarizeAndRestart, hasUserMessages, connectionState == .ready, !isStreaming {
            _ = await sendAndWait("/compact")
        }

        let resumeID = process.sessionId
        await restartProcess(resumeSessionID: resumeID)
        appendSystemNote("Reasoning effort: \(reasoningEffortDisplayName(effort)).")
    }

    func setModel(_ model: String) {
        guard availableModels.contains(model) else { return }
        let previous = currentModel
        let previousIntent = persistedModelIntent
        currentModel = model
        modelSwitchError = nil
        modelSwitchNeedsNewSession = false
        process.modelSwitchError = nil
        process.modelSwitchNeedsNewSession = false
        tabHasExplicitModel = true
        tabModelIntent = .explicit(model)
        let handle = process.setModel(model)
        modelExecutionState = handle == nil
            ? ModelExecutionState.savedIntent(modelID: model)
            : process.modelExecutionState
        saveCurrentSessionSelection()
        notifyModelChanged()

        guard let handle else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = await handle.result.value
            let identity = handle.identity
            guard self.tabSessionID == identity.localTabID,
                  self.process.activeProcessGeneration == identity.processGeneration,
                  self.process.sessionId == identity.backendSessionID,
                  result.identity == identity else { return }

            self.modelExecutionState = result
            switch result.status {
            case .confirmed:
                if let effective = result.effectiveModelID {
                    self.currentModel = effective
                }
            case .requested:
                // ACP accepted the request without exposing the effective model.
                // Preserve intent, but do not paint it as live.
                self.currentModel = model
            case .rejected:
                self.currentModel = previous
                self.tabModelIntent = previousIntent
                self.tabHasExplicitModel = {
                    if case .explicit = previousIntent { return true }
                    return false
                }()
                self.modelSwitchError = self.process.modelSwitchError
                    ?? "Grok did not accept the requested model."
                self.modelSwitchNeedsNewSession = self.process.modelSwitchNeedsNewSession
            case .unknown, .pending:
                break
            }
            self.saveCurrentSessionSelection()
            self.notifyModelChanged()
        }
    }

    var isModelRequestPending: Bool { modelExecutionState.status == .pending }

    private var modelReceiptIsCurrentProcess: Bool {
        guard let identity = modelExecutionState.identity,
              let generation = process.activeProcessGeneration else { return false }
        return identity.processGeneration == generation
            && identity.localTabID == tabSessionID
            && identity.backendSessionID == process.sessionId
    }

    var modelSelectorStatusLabel: String {
        switch modelExecutionState.status {
        case .confirmed:
            return modelReceiptIsCurrentProcess ? "Live" : "Last live"
        case .pending:
            return modelReceiptIsCurrentProcess ? "Pending" : "Stale"
        case .requested:
            return modelExecutionState.identity == nil ? "Saved" : "Requested"
        case .rejected:
            return "Rejected"
        case .unknown:
            return "Unknown"
        }
    }

    var modelSelectorDisplayLabel: String {
        "\(modelDisplayName(currentModel)) · \(modelSelectorStatusLabel)"
    }

    var modelAccessibilityValue: String {
        let requested = modelExecutionState.requestedModelID.map(modelDisplayName)
        let effective = modelExecutionState.effectiveModelID.map(modelDisplayName)
        switch modelExecutionState.status {
        case .confirmed:
            if modelReceiptIsCurrentProcess, let effective {
                return "Live model \(effective), confirmed by the current process."
            }
            return "Last confirmed model \(effective ?? "unknown"); no current-process confirmation."
        case .pending:
            return "Requesting \(requested ?? modelDisplayName(currentModel)); confirmation pending."
        case .requested:
            if modelExecutionState.identity == nil {
                return "Saved model \(requested ?? modelDisplayName(currentModel)) for this tab; no active process."
            }
            return "Requested model \(requested ?? modelDisplayName(currentModel)); backend model not independently exposed."
        case .rejected:
            let fallback = effective.map { " The last confirmed model is \($0)." } ?? ""
            return "Model request for \(requested ?? "unknown") was rejected.\(fallback)"
        case .unknown:
            return "Current backend model is unknown."
        }
    }

    var sessionReceiptCompactLabel: String {
        switch modelExecutionState.status {
        case .confirmed where modelReceiptIsCurrentProcess:
            return "Live · \(modelDisplayName(modelExecutionState.effectiveModelID ?? currentModel))"
        case .pending:
            return "Model pending"
        case .requested:
            return modelExecutionState.identity == nil ? "Model saved" : "Model requested"
        case .rejected:
            return "Model rejected"
        case .confirmed:
            return "Last model receipt"
        case .unknown:
            return process.activeProcessGeneration == nil ? "No active process" : "Model unknown"
        }
    }

    var sessionReceiptDetailLines: [String] {
        var lines = [modelAccessibilityValue]
        guard let receipt = process.launchReceipt else {
            lines.append("No process launch receipt for this tab.")
            return lines
        }
        let pid = receipt.processIdentifier.map(String.init) ?? "unavailable"
        lines.append("Process generation \(receipt.processGeneration), PID \(pid), \(receipt.outcome.rawValue).")
        lines.append("Tab \(Self.shortReceiptID(receipt.localTabID?.uuidString)); backend \(Self.shortReceiptID(receipt.backendSessionID)).")
        lines.append("Requested model: \(receipt.requestedModelID.map(modelDisplayName) ?? "CLI default").")
        lines.append("Agent: \(GrokAgentProfiles.displayName(for: receipt.requestedAgentID ?? "")); effort: \(receipt.requestedReasoningEffort?.isEmpty == false ? receipt.requestedReasoningEffort! : "default").")
        lines.append("Permissions: \(receipt.permissionMode.displayName); sandbox: \(receipt.sandboxProfile).")
        let capabilities = [
            receipt.memoryEnabled ? "memory" : nil,
            receipt.webSearchEnabled ? "web" : nil,
            receipt.subagentsEnabled ? "subagents" : nil,
            receipt.browserEnabled ? "browser" : nil,
            receipt.computerUseEnabled ? "computer use" : nil,
        ].compactMap { $0 }
        lines.append("Launched capabilities: \(capabilities.isEmpty ? "none" : capabilities.joined(separator: ", ")).")
        lines.append("MCP servers: \(receipt.mcpServerNames.isEmpty ? "none" : receipt.mcpServerNames.joined(separator: ", ")).")
        return lines
    }

    private static func shortReceiptID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        return value.count > 8 ? "…\(value.suffix(8))" : value
    }

    func modelDisplayName(_ id: String) -> String {
        modelDisplayNames[id] ?? id
    }

    var currentModelSupportsReasoningEffort: Bool {
        modelSupportsReasoningEffort(currentModel)
    }

    var isCurrentModelCustom: Bool {
        isCustomModel(currentModel)
    }

    func isCustomModel(_ id: String) -> Bool {
        customModelsByID[id] != nil
    }

    func modelSupportsReasoningEffort(_ id: String) -> Bool {
        customModelsByID[id]?.supportsReasoningEffort ?? true
    }

    var currentModelContextLabel: String {
        guard let limit = modelContextTokens[currentModel] else { return "—/—" }
        let used = usedContextTokens ?? 0
        return "\(Self.compactTokenCount(used))/\(Self.compactTokenCount(limit))"
    }

    var contextUsageFraction: Double {
        guard let limit = modelContextTokens[currentModel], limit > 0 else { return 0 }
        return min(1, Double(usedContextTokens ?? 0) / Double(limit))
    }

    var currentModelContextLimit: Int? {
        modelContextTokens[currentModel]
    }

    private static func compactTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M"
        }
        if tokens >= 1_000 {
            return "\(tokens / 1_000)K"
        }
        return "\(tokens)"
    }

    func setYolo(_ enabled: Bool) {
        isYolo = enabled
        if enabled {
            for perm in pendingPermissions {
                switch PermissionRequestPolicy.disposition(
                    mode: effectivePermissionMode,
                    isYolo: true,
                    options: perm.options
                ) {
                case .allow(let optionID):
                    respondToPermission(perm, with: optionID)
                case .deny(let optionID):
                    denyPermission(perm, optionID: optionID)
                case .prompt:
                    break
                }
            }
            pendingPermissions.removeAll()
        }
    }

    /// Attempts to restart the grok process (useful after running `grok login`).
    func retryConnection() async {
        authRequiredMessage = nil
        lastError = nil
        if currentWorkspace != nil {
            await restartProcess()
        }
    }

    func reportError(_ message: String) {
        lastError = message
    }

    // MARK: History

    func previousHistory(from current: String) -> String? {
        guard !commandHistory.isEmpty else { return nil }
        if let idx = historyIndex {
            let ni = max(0, idx - 1)
            historyIndex = ni
            return commandHistory[ni]
        } else {
            historyIndex = commandHistory.count - 1
            return commandHistory.last
        }
    }

    func nextHistory(from current: String) -> String? {
        guard let idx = historyIndex else { return nil }
        let ni = idx + 1
        if ni < commandHistory.count {
            historyIndex = ni
            return commandHistory[ni]
        }
        historyIndex = nil
        return ""
    }

    // MARK: Diffs + Apply (public API used by preview)

    struct DetectedDiff: Identifiable, Hashable {
        let id = UUID()
        let raw: String
        let filePath: String?
    }

    func detectedDiffs(in message: Message) -> [DetectedDiff] {
        guard message.role == .assistant else { return [] }
        var out: [DetectedDiff] = []
        let content = message.content

        // ```diff / ```patch blocks
        if let re = try? NSRegularExpression(pattern: "```(?:diff|patch)\\s*([\\s\\S]*?)```", options: .caseInsensitive) {
            let ns = content as NSString
            for m in re.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
                if m.numberOfRanges > 1 {
                    let d = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    out.append(.init(raw: d, filePath: DiffUtils.firstFilePath(in: d)))
                }
            }
        }

        if out.isEmpty && content.contains("diff --git") {
            let parts = content.components(separatedBy: "\ndiff --git")
            for (i, p) in parts.enumerated() {
                var block = p
                if i > 0 { block = "diff --git" + block }
                if block.contains("diff --git") {
                    let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                    out.append(.init(raw: trimmed, filePath: DiffUtils.firstFilePath(in: trimmed)))
                }
            }
        }
        return out
    }

    @discardableResult
    func applyDiffs(from message: Message, workspace: Workspace) async -> (applied: Int, errors: [String]) {
        let diffs = detectedDiffs(in: message)
        guard !diffs.isEmpty else { return (0, []) }

        var applied = 0
        var errs: [String] = []
        for d in diffs {
            do {
                try await DiffUtils.applyUnifiedDiff(d.raw, root: workspace.path)
                applied += 1
            } catch {
                errs.append("\(d.filePath ?? "file"): \(error.localizedDescription)")
            }
        }
        if applied > 0 {
            appendSystem("Applied \(applied) patch(es).")
        }
        return (applied, errs)
    }

    // MARK: Internal

    private func consumeOutput() async {
        for await event in process.acpEventStream {
            handleAcpEvent(event)
        }
    }

    private func touchTurnActivity() {
        lastTurnEventAt = Date()
        if turnStalledSince != nil { turnStalledSince = nil }
    }

    private func startStallWatchdog() {
        stallWatchdogTask?.cancel()
        turnStalledSince = nil
        lastTurnEventAt = Date()
        stallWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.isStreaming else { return }
                self.evaluateTurnStall(now: Date())
            }
        }
    }

    private func stopStallWatchdog() {
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
        turnStalledSince = nil
    }

    func evaluateTurnStall(now: Date) {
        guard isStreaming else {
            turnStalledSince = nil
            return
        }
        if now.timeIntervalSince(lastTurnEventAt) >= Self.turnStallThreshold, turnStalledSince == nil {
            turnStalledSince = now
        }
    }

    func setLastTurnEventAtForTests(_ date: Date) {
        lastTurnEventAt = date
    }

    private func handleAcpEvent(_ event: AcpEvent) {
        if isStreaming { touchTurnActivity() }
        switch event {
        case .messageChunk(let text):
            isGrokking = false
            appendAssistantText(text)
        case .thoughtChunk(let text):
            isGrokking = false
            if thinkingStartedAt == nil { thinkingStartedAt = Date() }
            thinkingText += text
            streamRevision &+= 1
        case .toolCall(let tc):
            flushAllPendingAssistantText()
            isGrokking = false
            if !liveToolCalls.contains(where: { $0.id == tc.id }) {
                liveToolCalls.append(liveToolCall(from: tc))
            }
            if QuestionRequest.isQuestionTool(tc),
               let items = QuestionRequest.questionsFromToolCall(tc),
               !pendingQuestions.contains(where: { $0.id == AnyHashable(tc.id) }) {
                pendingQuestions.append(QuestionRequest(
                    id: AnyHashable(tc.id),
                    sessionId: process.sessionId ?? "",
                    questions: items,
                    isResolved: false,
                    answerSummary: nil
                ))
            }
        case .toolCallUpdate(let tc):
            if let idx = liveToolCalls.firstIndex(where: { $0.id == tc.id }) {
                liveToolCalls[idx] = mergedToolCall(existing: liveToolCalls[idx], update: tc)
            } else {
                liveToolCalls.append(liveToolCall(from: tc))
            }
            if QuestionRequest.isQuestionTool(tc),
               let items = QuestionRequest.questionsFromToolCall(tc),
               !pendingQuestions.contains(where: { $0.id == AnyHashable(tc.id) }) {
                pendingQuestions.append(QuestionRequest(
                    id: AnyHashable(tc.id),
                    sessionId: process.sessionId ?? "",
                    questions: items,
                    isResolved: false,
                    answerSummary: nil
                ))
            }
        case .plan:
            break
        case .planFileContent(let content):
            if !content.isEmpty, var plan = pendingExitPlan {
                plan.planText = content
                pendingExitPlan = plan
            }
        case .exitPlanRequest(let req):
            pendingExitPlan = req
        case .questionRequest(let req):
            if !pendingQuestions.contains(where: { $0.id == req.id }) {
                pendingQuestions.append(req)
            }
        case .availableCommands(let commands):
            applyAvailableSlashCommands(commands)
        case .schedulerActivity(let payload):
            scheduledTaskTracker.apply(update: payload)
            scheduledTasks = scheduledTaskTracker.tasks
            backgroundTaskTracker.apply(update: payload)
            backgroundActivities = backgroundTaskTracker.activities
        case .workflowActivity(let payload):
            workflowRunTracker.apply(update: payload)
            workflowRuns = workflowRunTracker.runs
        case .backgroundActivity(let payload):
            backgroundTaskTracker.apply(update: payload)
            backgroundActivities = backgroundTaskTracker.activities
            scheduledTasks = backgroundTaskTracker.activities.compactMap(\.scheduledTask)
        case .turnCompleted:
            // This event shares the same AsyncStream queue as text/tool updates. By
            // acknowledging only here, `process.send` cannot outrun already-yielded
            // synthesis chunks and detach them from their assistant message.
            flushAllPendingAssistantText()
            reconcileActiveTurnFromBackend()
            process.acknowledgeTurnCompleted()
            applyTurnSettlementDecision(turnSettlement.recordCompletionConsumed())
        case .permissionRequest(let req):
            let liveMode = effectivePermissionMode
            switch PermissionRequestPolicy.disposition(
                mode: liveMode,
                isYolo: isYolo,
                options: req.options
            ) {
            case .allow(let optionID):
                respondToPermission(req, with: optionID)
                recordAutomaticPermissionDecision(req, allowed: true, mode: liveMode)
            case .deny(let optionID):
                denyPermission(req, optionID: optionID)
                recordAutomaticPermissionDecision(req, allowed: false, mode: liveMode)
            case .prompt:
                if !pendingPermissions.contains(where: { $0.id == req.id }) {
                    pendingPermissions.append(req)
                }
            }
        case .modeChanged(let mode):
            currentMode = mode
            availableModes = process.availableModes // keep in sync
            saveCurrentSessionSelection()
        case .contextUsage(let totalTokens):
            usedContextTokens = totalTokens

        case .rawLine(let line):
            appendAssistantText(line, allowClosedTurn: false)
        case .error(let msg):
            lastError = msg
        }
    }

    private func liveToolCall(from toolCall: ToolCall) -> LiveToolCall {
        LiveToolCall(
            id: toolCall.id,
            title: displayTitle(for: toolCall),
            kind: displayKind(for: toolCall),
            status: toolCall.status,
            detail: toolCall.detail
        )
    }

    private func mergedToolCall(existing: LiveToolCall, update: ToolCall) -> LiveToolCall {
        let title = isPlaceholderTitle(update.title) ? existing.title : displayTitle(for: update)
        let kind = isPlaceholderKind(update.kind) ? existing.kind : displayKind(for: update)
        return LiveToolCall(
            id: existing.id,
            title: title,
            kind: kind,
            status: update.status ?? existing.status,
            detail: update.detail ?? existing.detail
        )
    }

    private func displayTitle(for toolCall: ToolCall) -> String {
        if !isPlaceholderTitle(toolCall.title) {
            return toolCall.title
        }
        if let name = toolCall.rawInput?["toolName"] as? String
            ?? toolCall.rawInput?["tool_name"] as? String
            ?? toolCall.rawInput?["name"] as? String {
            return name
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
        return "Tool call"
    }

    private func displayKind(for toolCall: ToolCall) -> String {
        if !isPlaceholderKind(toolCall.kind) {
            return toolCall.kind
        }
        if let name = toolCall.rawInput?["toolName"] as? String
            ?? toolCall.rawInput?["tool_name"] as? String,
           name.hasPrefix("browser_") {
            return "browser"
        }
        return "tool"
    }

    private func isPlaceholderTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "unknown" || normalized == "tool call"
    }

    private func isPlaceholderKind(_ kind: String) -> Bool {
        let normalized = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "unknown"
    }

    private func reconcileActiveTurnFromBackend() {
        guard let sessionID = tabSessionID,
              let backendID = activeTurnBackendSessionID,
              let workspace = currentWorkspace,
              let result = SessionTranscriptRecovery.reconcile(
                  sessionID: sessionID,
                  grokSessionID: backendID,
                  workspacePath: workspace.path,
                  currentMessages: messages
              ) else {
            return
        }
        if result.changed {
            messages = filteredPersistedMessages(result.messages)
            streamRevision &+= 1
        }
        if let authoritativeID = result.authoritativeTailAssistantID {
            authoritativeTailAssistantID = authoritativeID
            streamingMessageID = authoritativeID
            closedTurnHasAuthoritativeHistory = true
        }
    }

    private func appendAssistantText(_ text: String, allowClosedTurn: Bool = true) {
        if closedTurnHasAuthoritativeHistory {
            // Completion reconciliation already committed the terminal backend answer.
            // Ignore a late ACP copy instead of rendering the synthesis twice.
            return
        }
        let targetID = streamingMessageID ?? (allowClosedTurn ? closedTurnAssistantID : nil)
        guard let id = targetID,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }

        let clean = text.replacingOccurrences(of: "<<USER>> ", with: "")
        if clean.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(">") &&
           !clean.contains("diff") { return }

        if !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !messages[idx].content.isEmpty {
            firstChunkInterval?.end()
            firstChunkInterval = nil
            streamingTextBuffer.append(clean)
            if streamingMessageID == nil {
                pendingLateChunkPersistence = true
            }
            scheduleStreamingTextFlushIfNeeded()
        }
    }

    private func applyAvailableSlashCommands(_ commands: [SlashCommand]) {
        availableSlashCommands = commands
        GrokCommandCatalog.record(commands)
    }

    private func scheduleStreamingTextFlushIfNeeded() {
        guard streamingTextFlushTask == nil, !streamingTextBuffer.isEmpty else {
            if streamingTextBuffer.isEmpty { finishDeferredPromptIfNeeded() }
            return
        }
        streamingTextFlushTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(20))
                } catch {
                    return
                }
                guard let self else { return }
                let hasMore = self.flushNextAssistantTextBatch()
                if !hasMore {
                    self.streamingTextFlushTask = nil
                    self.finishDeferredPromptIfNeeded()
                    self.persistLateChunkIfNeeded()
                    return
                }
            }
        }
    }

    @discardableResult
    private func flushNextAssistantTextBatch() -> Bool {
        guard let id = streamingMessageID ?? closedTurnAssistantID,
              let idx = messages.firstIndex(where: { $0.id == id }) else {
            streamingTextBuffer.clear()
            return false
        }
        let batch = streamingTextBuffer.popNextBatch()
        if !batch.isEmpty {
            messages[idx].content += batch
            streamRevision &+= 1
        }
        return !streamingTextBuffer.isEmpty
    }

    private func flushAllPendingAssistantText() {
        guard !streamingTextBuffer.isEmpty,
              let id = streamingMessageID ?? closedTurnAssistantID,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let remaining = streamingTextBuffer.drain()
        guard !remaining.isEmpty else { return }
        messages[idx].content += remaining
        streamRevision &+= 1
    }

    private func finishDeferredPromptIfNeeded() {
        guard streamingTextBuffer.isEmpty,
              let deferredPromptCompletion else { return }
        self.deferredPromptCompletion = nil
        finishPromptNow(
            assistantID: deferredPromptCompletion.assistantID,
            ok: deferredPromptCompletion.ok
        )
    }

    private func persistLateChunkIfNeeded() {
        guard pendingLateChunkPersistence,
              streamingTextBuffer.isEmpty,
              deferredPromptCompletion == nil else { return }
        pendingLateChunkPersistence = false
        if let id = closedTurnAssistantID,
           let idx = messages.firstIndex(where: { $0.id == id }) {
            captureAsideAndShare(from: messages[idx].content)
        }
        notifyMessagesChanged()
    }

    private func cancelStreamingTextFlush() {
        streamingTextFlushTask?.cancel()
        streamingTextFlushTask = nil
        streamingTextBuffer.clear()
        deferredPromptCompletion = nil
        pendingLateChunkPersistence = false
    }

    private func appendSystem(_ text: String) {
        messages.append(Message(role: .system, content: text))
    }

    /// Status notes repeat verbatim — reloading configuration several times
    /// used to stack identical "Reloaded Grok configuration." lines down the
    /// transcript. Collapse a note that just repeats the trailing one.
    private func appendSystemNote(_ text: String) {
        guard !ChatStore.isDuplicateTrailingNote(text, in: messages) else { return }
        appendSystem(text)
    }

    nonisolated static func isDuplicateTrailingNote(_ text: String, in messages: [Message]) -> Bool {
        guard let last = messages.last else { return false }
        return last.role == .system && last.content == text
    }

    private func filteredPersistedMessages(_ saved: [Message]) -> [Message] {
        saved.filter {
            !SessionMessageStore.isLegacyResumeNote($0)
                && !SessionMessageStore.isStaleSessionFallbackNote($0)
        }
    }

    private func notifyMessagesChanged() {
        NotificationCenter.default.post(name: .liveSessionMessagesChanged, object: self)
    }

    private func notifyModelChanged() {
        NotificationCenter.default.post(name: .liveSessionModelChanged, object: self)
    }

    private func notifyAgentChanged() {
        NotificationCenter.default.post(name: .liveSessionAgentChanged, object: self)
    }

    private func loadPermissionSettings() -> GrokPermissionSettings {
        GrokPermissionSettings(
            permissionMode: defaults.string(forKey: GrokSettingsKeys.permissionMode) ?? GrokPermissionSettings.defaults.permissionMode,
            sandboxProfile: defaults.string(forKey: GrokSettingsKeys.sandboxProfile) ?? "",
            reasoningEffort: workspaceReasoningEffort,
            disableWebSearch: defaults.bool(forKey: GrokSettingsKeys.disableWebSearch),
            noSubagents: defaults.bool(forKey: GrokSettingsKeys.noSubagents),
            allowRules: defaults.string(forKey: GrokSettingsKeys.allowRules) ?? "",
            denyRules: defaults.string(forKey: GrokSettingsKeys.denyRules) ?? "",
            selectedAgent: defaults.string(forKey: GrokSettingsKeys.selectedAgent) ?? "",
            memoryEnabled: defaults.bool(forKey: GrokSettingsKeys.memoryEnabled)
        )
    }

    /// Whether cross-session memory is enabled for new/restarted sessions (Settings → Memory).
    var isMemoryEnabled: Bool {
        defaults.bool(forKey: GrokSettingsKeys.memoryEnabled)
    }

    private func lineList(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func syncModelsFromProcess() {
        if !process.availableModelsInfo.isEmpty {
            builtInModelIDs = Set(process.availableModelsInfo.map(\.id))
            availableModels = process.availableModelsInfo.map { $0.id }
            modelDisplayNames = Dictionary(uniqueKeysWithValues: process.availableModelsInfo.map { ($0.id, $0.name) })
            modelContextTokens = Dictionary(uniqueKeysWithValues: process.availableModelsInfo.compactMap { model in
                guard let tokens = model.contextTokens else { return nil }
                return (model.id, tokens)
            })
        }
        mergeCustomModels()
    }

    private func applyBuiltInModelCatalog(_ models: [GrokModelInfo]) {
        guard !models.isEmpty, process.availableModelsInfo.isEmpty else { return }
        let previousBuiltInIDs = builtInModelIDs
        builtInModelIDs = Set(models.map(\.id))

        for removed in previousBuiltInIDs.subtracting(builtInModelIDs) where customModelsByID[removed] == nil {
            modelDisplayNames.removeValue(forKey: removed)
            if removed != "grok-4.5" { modelContextTokens.removeValue(forKey: removed) }
        }
        for model in models {
            modelDisplayNames[model.id] = model.name
        }
        if builtInModelIDs.contains("grok-4.5") {
            modelContextTokens["grok-4.5"] = modelContextTokens["grok-4.5"] ?? 500_000
        }

        let customIDs = availableModels.filter { customModelsByID[$0] != nil }
        availableModels = models.map(\.id) + customIDs.filter { !builtInModelIDs.contains($0) }
        mergeCustomModels()

        guard !tabHasExplicitModel else { return }
        if case .legacyUnknown(let legacyModel) = tabModelIntent,
           availableModels.contains(legacyModel) {
            currentModel = legacyModel
            return
        }
        let preferred = workspaceDefaultModel().flatMap { availableModels.contains($0) ? $0 : nil }
            ?? models.first(where: \.isDefault)?.id
            ?? models.first?.id
        if let preferred, !availableModels.contains(currentModel) || previousBuiltInIDs.contains(currentModel) {
            currentModel = preferred
            notifyModelChanged()
        }
    }

    /// Fold custom OpenAI-compatible models from `~/.grok/config.toml` into the picker so they
    /// are selectable alongside the agent's built-in models. Without this they are only reachable
    /// by typing `/model <id>`, since the composer list is otherwise driven by the agent's
    /// advertised `modelState.availableModels`. Idempotent — safe to call on every resync.
    private func mergeCustomModels() {
        let previousCustomModelIDs = Set(customModelsByID.keys)
        let processModelIDs = Set(process.availableModelsInfo.map(\.id))
        availableModels.removeAll { previousCustomModelIDs.contains($0) && !processModelIDs.contains($0) }
        for removedID in previousCustomModelIDs where !processModelIDs.contains(removedID) {
            modelDisplayNames.removeValue(forKey: removedID)
            modelContextTokens.removeValue(forKey: removedID)
        }
        let customModels = CustomModelStore.load().models
        customModelsByID = [:]
        for model in customModels {
            customModelsByID[model.id] = model
        }
        let acpContextModelIDs = Set(process.availableModelsInfo.compactMap { model in
            model.contextTokens == nil ? nil : model.id
        })

        for model in customModels {
            if !availableModels.contains(model.id) {
                availableModels.append(model.id)
            }
            // Prefer the explicit display name, then the provider model name (what the connected
            // agent reports), then the table id — so the label is consistent before/after connect.
            let name = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let providerModel = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
            modelDisplayNames[model.id] = !name.isEmpty ? name : (!providerModel.isEmpty ? providerModel : model.id)
            if !acpContextModelIDs.contains(model.id) {
                if let contextTokens = model.contextTokens {
                    modelContextTokens[model.id] = contextTokens
                } else {
                    modelContextTokens.removeValue(forKey: model.id)
                }
            }
        }
    }

    private func workspaceDefaultModel() -> String? {
        guard let workspace = currentWorkspace else { return nil }
        let model = SessionLayoutStore.agentSettings(for: workspace.id).model?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let model, !model.isEmpty else { return nil }
        return model
    }

    private func loadWorkspaceReasoningEffort() {
        guard let workspace = currentWorkspace else { return }
        let saved = SessionLayoutStore.agentSettings(for: workspace.id)
        // A workspace with no saved effort inherits the global default (Settings →
        // Permissions → "Default reasoning effort"); the composer picker then overrides
        // it per project.
        let globalDefault = defaults.string(forKey: GrokSettingsKeys.reasoningEffort) ?? ""
        workspaceReasoningEffort = Self.resolveReasoningEffort(saved: saved.reasoningEffort, globalDefault: globalDefault)
    }

    private func applyTabModel(_ model: String) {
        guard availableModels.contains(model) else { return }
        currentModel = model
        tabHasExplicitModel = true
        tabModelIntent = .explicit(model)
    }

    private func applyLegacyModelIfAvailable(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, availableModels.contains(trimmed) else { return }
        currentModel = trimmed
        tabHasExplicitModel = false
    }

    private func applyInheritedModelIfAvailable() {
        guard let model = workspaceDefaultModel(), availableModels.contains(model) else { return }
        currentModel = model
        tabHasExplicitModel = false
    }

    private func modelForProcessLaunch(fallbackSelection: SessionSelection?) -> String {
        if tabHasExplicitModel, availableModels.contains(currentModel) {
            return currentModel
        }
        if case .legacyUnknown(let model) = tabModelIntent,
           availableModels.contains(model) {
            currentModel = model
            return model
        }
        if let model = workspaceDefaultModel(), availableModels.contains(model) {
            currentModel = model
            return model
        }
        if let model = fallbackSelection?.model,
           availableModels.contains(model) {
            currentModel = model
            return model
        }
        if availableModels.contains(currentModel) {
            return currentModel
        }
        if let first = availableModels.first {
            currentModel = first
            return first
        }
        return currentModel
    }

    /// Resolves the effective per-project reasoning effort: an explicitly saved value
    /// (including an empty "Default") wins; otherwise the workspace inherits the global
    /// default configured in Settings → Permissions.
    nonisolated static func resolveReasoningEffort(saved: String?, globalDefault: String) -> String {
        saved ?? globalDefault
    }

    private func saveWorkspaceAgentSettings() {
        guard let workspace = currentWorkspace else { return }
        var existing = SessionLayoutStore.agentSettings(for: workspace.id)
        existing.reasoningEffort = workspaceReasoningEffort
        SessionLayoutStore.saveAgentSettings(existing, for: workspace.id)
        NotificationCenter.default.post(
            name: .workspaceAgentSettingsChanged,
            object: nil,
            userInfo: ["workspaceID": workspace.id]
        )
    }

    private func restoreSessionSelection(_ fallbackSelection: SessionSelection?) {
        let selection = process.sessionId.flatMap { sessionSelections[$0] } ?? fallbackSelection

        modelExecutionState = process.modelExecutionState
        if modelExecutionState.status == .confirmed,
           let effective = modelExecutionState.effectiveModelID {
            currentModel = effective
        } else if let requested = modelExecutionState.requestedModelID {
            currentModel = requested
        } else if tabHasExplicitModel, availableModels.contains(currentModel) {
            // Preserve the explicit control value. The launch receipt remains Unknown
            // until ACP independently reports an effective model.
        } else if case .legacyUnknown(let model) = tabModelIntent,
                  availableModels.contains(model) {
            currentModel = model
        } else if let model = workspaceDefaultModel(), availableModels.contains(model) {
            currentModel = model
        } else if let model = selection?.model, availableModels.contains(model) {
            currentModel = model
        } else if !availableModels.contains(currentModel) {
            currentModel = availableModels.first ?? currentModel
        }

        let selectedMode = selection?.mode.map(AgentMode.init(rawValue:)) ?? process.currentMode
        if availableModes.contains(selectedMode) {
            currentMode = selectedMode
        } else {
            currentMode = availableModes.first ?? .agent
        }
        isYolo = (currentMode == .yolo)
        if currentMode != process.currentMode {
            process.setMode(currentMode)
        }
    }

    private func saveCurrentSessionSelection() {
        guard let sessionId = process.sessionId else { return }
        sessionSelections[sessionId] = SessionSelection(
            mode: currentMode.rawValue,
            model: currentModel
        )
        if let data = try? JSONEncoder().encode(sessionSelections) {
            defaults.set(data, forKey: sessionSelectionsKey)
        }
    }

    private func statusName(for state: GrokProcessState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .starting:
            return "starting"
        case .ready:
            return "ready"
        case .busy:
            return "busy"
        case .failed:
            return "error"
        }
    }
}

// MARK: - Diff utilities (extracted)

enum DiffUtils {
    static func firstFilePath(in diff: String) -> String? {
        for line in diff.components(separatedBy: .newlines) {
            if line.hasPrefix("diff --git ") {
                let comps = line.split(separator: " ")
                if comps.count >= 4 {
                    let b = String(comps[3])
                    return b.hasPrefix("b/") ? String(b.dropFirst(2)) : b
                }
            }
            if line.hasPrefix("+++ b/") { return String(line.dropFirst(6)) }
            if line.hasPrefix("--- a/") { return String(line.dropFirst(6)) }
            if line.hasPrefix("--- ") && !line.contains("--- /dev/null") {
                let p = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                return p.hasPrefix("a/") ? String(p.dropFirst(2)) : p
            }
        }
        return nil
    }

    static func applyUnifiedDiff(_ diffText: String, root: URL) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-\(UUID().uuidString).patch")
        try diffText.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Await termination instead of blocking the caller (this used to hold the
        // main actor through /usr/bin/patch).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/patch")
        p.arguments = ["-p1", "-d", root.path, "-i", tmp.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            p.terminationHandler = { _ in continuation.resume() }
            do {
                try p.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        if p.terminationStatus != 0 {
            try naiveApply(diffText, root: root)
        }
    }

    private static func naiveApply(_ diff: String, root: URL) throws {
        let lines = diff.components(separatedBy: .newlines)
        var target: String?
        var content: [String] = []
        var inHunk = false

        for line in lines {
            if line.hasPrefix("+++ b/") { target = String(line.dropFirst(6)) }
            else if line.hasPrefix("@@") { inHunk = true }
            else if inHunk {
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    content.append(String(line.dropFirst()))
                } else if !line.hasPrefix("-") && !line.hasPrefix("\\") {
                    content.append(line)
                }
            }
        }
        guard let t = target else {
            throw NSError(domain: "GrokBuild", code: -1, userInfo: [NSLocalizedDescriptionKey: "No target path in diff"])
        }
        let dest = root.appendingPathComponent(t)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.joined(separator: "\n").write(to: dest, atomically: true, encoding: .utf8)
    }
}
