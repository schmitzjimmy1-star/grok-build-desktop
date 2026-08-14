import Foundation
import Observation
import SwiftUI
import AppKit

enum BuiltInToolConnection: String, CaseIterable, Sendable {
    case browser = "grokbuild-browser"
    case computerUse = "grokbuild-computer-use"
}

struct PendingSubmitIntent: Equatable, Sendable {
    let id: UUID
    let draft: String
    let modelID: String?
    let modeID: String?
    let reasoningEffort: String
    let fileAttachments: [FileAttachment]
    let requestedMCPNames: Set<String>

    init(
        id: UUID,
        draft: String,
        modelID: String? = nil,
        modeID: String? = nil,
        reasoningEffort: String = "",
        fileAttachments: [FileAttachment] = [],
        requestedMCPNames: Set<String> = []
    ) {
        self.id = id
        self.draft = draft
        self.modelID = modelID
        self.modeID = modeID
        self.reasoningEffort = reasoningEffort
        self.fileAttachments = fileAttachments
        self.requestedMCPNames = requestedMCPNames
    }
}

enum SubmitPreparation: Equatable, Sendable {
    case latched(UUID)
    case rejected

    var intentID: UUID? {
        guard case .latched(let id) = self else { return nil }
        return id
    }
}

enum PendingSubmitIntentPolicy {
    enum LatchDecision: Equatable {
        case latch
        case duplicate
        case conflictingDraft
    }

    static func latchDecision(existing: PendingSubmitIntent?, draft: String) -> LatchDecision {
        guard let existing else { return .latch }
        return existing.draft == draft ? .duplicate : .conflictingDraft
    }

    static func routeStillMatches(
        _ intent: PendingSubmitIntent,
        modelID: String,
        modeID: String,
        reasoningEffort: String,
        fileAttachments: [FileAttachment],
        requestedMCPNames: Set<String>
    ) -> Bool {
        intent.modelID == modelID
            && intent.modeID == modeID
            && intent.reasoningEffort == reasoningEffort
            && intent.fileAttachments == fileAttachments
            && intent.requestedMCPNames == requestedMCPNames
    }

    static func backendRouteIsConfirmed(
        _ intent: PendingSubmitIntent,
        modelExecutionState: ModelExecutionState,
        expectedEffectiveModelID: String?,
        currentModeID: String
    ) -> Bool {
        let expectedProviderModel = expectedEffectiveModelID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let acceptedEffectiveModels = Set([
            intent.modelID,
            expectedProviderModel?.isEmpty == false ? expectedProviderModel : nil
        ].compactMap { $0 })
        return modelExecutionState.status == .confirmed
            && modelExecutionState.requestedModelID == intent.modelID
            && modelExecutionState.effectiveModelID.map(acceptedEffectiveModels.contains) == true
            && currentModeID == intent.modeID
    }
}

struct TurnSettlementCoordinator {
    struct Decision: Equatable {
        let assistantID: UUID
        let ok: Bool
    }

    private(set) var generation = 0
    private var assistantID: UUID?
    private var promptResult: Bool?
    private var completionResult: Bool?
    private var finalized = false

    mutating func begin(assistantID: UUID) -> Int {
        generation &+= 1
        self.assistantID = assistantID
        promptResult = nil
        completionResult = nil
        finalized = false
        return generation
    }

    mutating func recordPromptResult(generation: Int, ok: Bool) -> Decision? {
        guard generation == self.generation, assistantID != nil, !finalized else { return nil }
        promptResult = ok
        return takeDecisionIfReady()
    }

    mutating func recordCompletionConsumed(ok: Bool = true) -> Decision? {
        guard assistantID != nil, !finalized else { return nil }
        completionResult = ok
        return takeDecisionIfReady()
    }

    mutating func invalidate() {
        generation &+= 1
        assistantID = nil
        promptResult = nil
        completionResult = nil
        finalized = true
    }

    private mutating func takeDecisionIfReady() -> Decision? {
        guard let assistantID, let promptResult else { return nil }
        // A failed RPC is terminal even when the CLI never emits completion. Success
        // waits until the completion event has crossed ChatStore's event queue.
        if !promptResult {
            finalized = true
            return Decision(assistantID: assistantID, ok: false)
        }
        guard let completionResult else { return nil }
        finalized = true
        return Decision(assistantID: assistantID, ok: completionResult)
    }
}

enum StoppedTurnContinuationDecision: Equatable, Sendable {
    case reverifySameBackend
    case startFresh

    static func decision(
        receipt: SessionContinuityReceipt,
        localTabID: UUID?,
        backendID: String?,
        processGeneration: UInt64?
    ) -> Self {
        guard let localTabID,
              let backendID, !backendID.isEmpty,
              let processGeneration,
              receipt.localTabID == localTabID,
              receipt.backendID == backendID,
              receipt.processGeneration == processGeneration,
              [.backendBound, .backendOnly, .verified, .recoveryForked].contains(receipt.status)
        else {
            return .startFresh
        }
        return .reverifySameBackend
    }

    var nextAction: String {
        switch self {
        case .reverifySameBackend:
            return "Reconnect to the verified backend before sending another turn. GrokBuild will re-check continuity for this stopped session."
        case .startFresh:
            return "Start a fresh run. The prior continuity receipt did not match this stopped session."
        }
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
        options: [PermissionOption],
        mcpGatewayEnabled: Bool = false,
        isMCPInvocation: Bool = false,
        invocationServerName: String? = nil,
        allowedMCPServerNames: Set<String> = []
    ) -> PermissionRequestDisposition {
        // A thread's explicit MCP gate outranks convenience approval modes. Grok
        // CLI remains the only executor: the app answers Grok's ACP permission
        // request with its reject option and never invokes the tool client-side.
        if isMCPInvocation {
            let normalizedServer = invocationServerName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let normalizedAllowed = Set(allowedMCPServerNames.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
            guard mcpGatewayEnabled,
                  let normalizedServer,
                  normalizedAllowed.contains(normalizedServer) else {
                return .deny(optionID: options.first(where: { isDeny($0) })?.id)
            }
        }
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
    struct RunArtifact: Identifiable, Hashable {
        enum Location: String, Hashable {
            case workspace
            case external
        }

        let toolCallID: String
        let path: String
        let status: String
        let location: Location
        var owningPlanStepID: String? = nil
        var workerID: String? = nil

        var id: String { "\(toolCallID)|\(path)" }
    }

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

    /// An empty transcript shows the welcome/intent cards unless the tab is hard-blocked
    /// on continuity recovery or the composer already holds a draft. Once typing (or a
    /// starter pill) owns the task, the landing pills are the wrong chrome.
    var showsEmptyTranscriptWelcome: Bool {
        messages.isEmpty
            && !continuityRequiresRecovery
            && composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    /// The model the user actually requested when the current transcript made a live switch
    /// unsafe. Keep it separate from `currentModel`, which remains pinned to the model that
    /// produced the existing transcript until the user accepts a fresh-session boundary.
    private var pendingModelForNewSession: String?

    // VS Code extension-style turn state
    private(set) var isGrokking = false
    /// Ordered public summary chunks emitted by ACP for the active turn. These are
    /// ephemeral presentation input only: they are not transcript messages and are
    /// never written by the session/layout stores or diagnostic exporters.
    private(set) var reasoningSummaryChunks: [String] = []
    var thinkingText: String {
        ReasoningSummaryPresentation.make(
            chunks: reasoningSummaryChunks,
            expanded: true
        ).presentationOnlyText
    }
    private(set) var thinkingDuration: TimeInterval?
    private(set) var isThinkingExpanded = false
    /// Bumped on every streamed thinking/answer chunk. A streaming answer appends to the
    /// existing assistant message's content, which changes neither `messages.count` nor
    /// `isGrokking` — so the transcript needs this to auto-scroll the growing answer into
    /// view instead of stranding it below the fold behind the thinking chip.
    private(set) var streamRevision = 0
    private(set) var liveToolCalls: [LiveToolCall] = []
    /// A completed parent turn is an outcome of the run, not evidence that each
    /// individual tool call succeeded or recovered.
    private(set) var latestTurnOutcome: TurnOutcome?
    /// Successful write/edit receipts for the current turn. This is deliberately
    /// independent from Git review state: a write can be external, ignored, or
    /// otherwise absent from `git status`.
    private(set) var runArtifacts: [RunArtifact] = []
    /// The sole sidebar read model for a settled parent turn. It is ephemeral
    /// and replaced at the next turn boundary; no transcript or layout state is
    /// mutated to make a run look complete.
    private(set) var runEvidenceSnapshot: RunEvidenceSnapshot?
    private var currentRunPlan: [RunEvidenceSnapshot.PlanStep] = []
    private var currentTurnToolPlanStepIDs: [String: String] = [:]
    /// A stop is not a backend completion. If its captured receipt cannot prove
    /// ownership of the stopped process, the next launch must not quietly resume
    /// that backend and instead creates a fresh, ledgered run.
    private var forcedFreshStartAfterUserStop = false
    private var stoppedBackendIDNeedingFreshStart: String?

    /// Current receipts projected only while this exact tab/backend/process
    /// generation owns an active turn. This computed value is presentation-only:
    /// it never crosses a persistence boundary and cannot manufacture a settled
    /// lifecycle, usage receipt, or worker outcome.
    var liveRunEvidenceProjection: RunEvidenceLiveProjection? {
        guard isStreaming,
              runEvidenceSnapshot == nil,
              let localTabID = tabSessionID,
              let backendSessionID = activeTurnBackendSessionID,
              backendSessionID == process.sessionId,
              let processGeneration = process.activeProcessGeneration else { return nil }

        let workers = currentTurnEvidenceWorkers()
        let tools = parentLiveToolCalls().map { tool in
            let status: String
            let isActive: Bool
            switch tool.terminalStatus {
            case .succeeded:
                status = "Succeeded"
                isActive = false
            case .failed:
                status = tool.isRecovered ? "Recovered" : "Failed"
                isActive = false
            case .cancelled:
                status = "Cancelled"
                isActive = false
            case .stale:
                status = "Stale"
                isActive = false
            case .unknown:
                status = "Status not settled"
                isActive = false
            case nil:
                status = tool.status.map(ActivitySidebarPresentation.activityStatus) ?? "Running"
                isActive = true
            }
            return RunEvidenceLiveProjection.Tool(
                id: tool.id,
                title: tool.title,
                kind: tool.kind,
                status: status,
                detail: tool.detail.map {
                    TranscriptTextPresentation.singleLine($0, maxLength: 280)
                },
                mcpServerName: tool.mcpServerName,
                mcpReceiptRole: tool.mcpReceiptRole,
                qualifiedToolName: tool.qualifiedToolName,
                discoveredQualifiedToolNames: tool.discoveredQualifiedToolNames,
                owningPlanStepID: currentTurnToolPlanStepIDs[tool.id],
                durationMilliseconds: tool.durationMilliseconds,
                isActive: isActive
            )
        }
        let latestUserMessage = messages.last(where: { $0.role == .user })?.content
        return RunEvidenceLiveProjection(
            binding: .init(
                localTabID: localTabID,
                workspaceID: currentWorkspace?.id,
                backendSessionID: backendSessionID,
                processGeneration: processGeneration
            ),
            goalSummary: goalState?.objective ?? latestUserMessage.map {
                TranscriptTextPresentation.singleLine($0, maxLength: 240)
            },
            plan: currentRunPlan,
            workers: workers,
            tools: tools,
            artifacts: runArtifacts,
            process: .init(
                state: "In progress — not settled",
                model: modelExecutionState.effectiveModelID ?? modelExecutionState.requestedModelID,
                mcps: mcpServerStatuses.map {
                    .init(name: $0.name, state: $0.state.rawValue, reason: $0.reason)
                }
            )
        )
    }
    /// Monotonic event-driven request observed by ContentView. Successful writes
    /// and the ordered turn-settlement barrier request a bounded Git refresh; no
    /// filesystem watcher or polling loop is involved.
    private(set) var gitRefreshRevision = 0
    private var pendingArtifactPathsByToolCallID: [String: String] = [:]
    private var thinkingStartedAt: Date?
    /// When the current turn began — drives the elapsed/"warming up" indicator.
    private(set) var turnStartedAt: Date?

    enum TurnOutcome: String, Hashable {
        case completed
        case failed
        case cancelled
        case completionReceiptMissing
        case userStopped

        var displayName: String {
            switch self {
            case .completed: "Turn completed"
            case .failed: "Turn failed"
            case .cancelled: "Turn cancelled"
            case .completionReceiptMissing: "Completion receipt missing"
            case .userStopped: "Stopped by you"
            }
        }
    }

    struct LiveToolCall: Identifiable, Hashable {
        let id: String
        let title: String
        let kind: String
        let status: String?
        let terminalStatus: ToolCallTerminalStatus?
        let detail: String?
        let diagnosticDetail: String?
        let target: String?
        let mcpServerName: String?
        let mcpReceiptRole: MCPToolReceiptRole?
        let qualifiedToolName: String?
        let discoveredQualifiedToolNames: [String]
        let retryOfToolCallID: String?
        let recoveredByToolCallID: String?
        let durationMilliseconds: Int?

        init(
            id: String,
            title: String,
            kind: String,
            status: String?,
            terminalStatus: ToolCallTerminalStatus?,
            detail: String?,
            diagnosticDetail: String?,
            target: String?,
            mcpServerName: String? = nil,
            mcpReceiptRole: MCPToolReceiptRole? = nil,
            qualifiedToolName: String? = nil,
            discoveredQualifiedToolNames: [String] = [],
            retryOfToolCallID: String?,
            recoveredByToolCallID: String?,
            durationMilliseconds: Int? = nil
        ) {
            self.id = id
            self.title = title
            self.kind = kind
            self.status = status
            self.terminalStatus = terminalStatus
            self.detail = detail
            self.diagnosticDetail = diagnosticDetail
            self.target = target
            self.mcpServerName = mcpServerName
            self.mcpReceiptRole = mcpReceiptRole
            self.qualifiedToolName = qualifiedToolName
            self.discoveredQualifiedToolNames = discoveredQualifiedToolNames
            self.retryOfToolCallID = retryOfToolCallID
            self.recoveredByToolCallID = recoveredByToolCallID
            self.durationMilliseconds = durationMilliseconds
        }

        var isFailed: Bool {
            terminalStatus == .failed
        }

        var isComplete: Bool {
            terminalStatus == .succeeded
        }

        var isRecovered: Bool {
            recoveredByToolCallID != nil
        }

        func settled(against calls: [LiveToolCall]) -> LiveToolCall {
            let normalizedTerminalStatus = terminalStatus ?? .unknown
            let recoveryID: String?
            if normalizedTerminalStatus == .failed {
                recoveryID = calls.first(where: {
                    $0.retryOfToolCallID == id && $0.terminalStatus == .succeeded
                })?.id
            } else {
                recoveryID = nil
            }
            return LiveToolCall(
                id: id,
                title: title,
                kind: kind,
                status: status,
                terminalStatus: normalizedTerminalStatus,
                detail: detail,
                diagnosticDetail: diagnosticDetail,
                target: target,
                mcpServerName: mcpServerName,
                mcpReceiptRole: mcpReceiptRole,
                qualifiedToolName: qualifiedToolName,
                discoveredQualifiedToolNames: discoveredQualifiedToolNames,
                retryOfToolCallID: retryOfToolCallID,
                recoveredByToolCallID: recoveryID,
                durationMilliseconds: durationMilliseconds
            )
        }
    }

    /// Set when the underlying grok CLI indicates the user is not authenticated.
    var authRequiredMessage: String?

    // MARK: - ACP Rich State
    private(set) var connectionState: GrokProcessState = .idle
    /// Secret-free MCP lifecycle receipts for the current process generation.
    /// These are derived from the GrokProcess launch boundary, not Settings drafts.
    private(set) var mcpServerStatuses: [MCPServerStatus] = []
    private(set) var currentMode: AgentMode = .agent
    private(set) var availableModes: [AgentMode] = []
    private(set) var pendingPermissions: [PermissionRequest] = []
    private(set) var pendingExitPlan: ExitPlanRequest?
    private(set) var pendingQuestions: [QuestionRequest] = []
    private(set) var availableSlashCommands: [SlashCommand] = GrokCommandCatalog.cached()
    /// Local goal state updated when the user sends `/goal …`; cleared on new session.
    private(set) var goalState: SessionGoalState?
    private(set) var fileAttachments: [FileAttachment] = []
    /// Connected/configured MCPs available to attach to the next prompt. The
    /// selection is in-memory per tab and is consumed only after a turn starts.
    private(set) var promptMCPOptions: [PromptMCPOption] = PromptMCPInventoryCatalog.cached()
    private(set) var selectedPromptMCPNames: Set<String> = []
    /// Explicit per-thread helper toggles. They are intentionally in-memory and
    /// default off for every new/restored tab, regardless of global availability.
    private(set) var enabledBuiltInToolNames: Set<String> = []
    /// Exact prompt attachment intent captured before the composer clears.
    /// This is per-turn request evidence only; it never implies catalog or use.
    private(set) var currentTurnRequestedMCPNames: [String] = []
    private(set) var currentTurnAttachmentNames: [String] = []
    private(set) var promptMCPInventoryIsLoading = false
    private(set) var promptMCPInventoryUnavailable = false
    private var configuredPromptMCPOptions: [PromptMCPOption] = PromptMCPInventoryCatalog.cached()
    private var loadedPromptMCPWorkspaceID: UUID?
    private(set) var isYolo: Bool = false

    var grokSessionId: String? { process.sessionId }
    var durableGrokSessionID: String? { process.sessionId ?? savedGrokSessionID }

    /// A saved task can be resumed only through the existing continuity gate.
    /// User Stop may require a fresh backend; in that case the header must not
    /// offer a control that looks like it can revive the stopped process.
    var canResumeTaskSession: Bool {
        currentWorkspace != nil
            && connectionState == .idle
            && durableGrokSessionID != nil
            && !continuityRequiresRecovery
            && !forcedFreshStartAfterUserStop
    }

    /// The latest durable checkpoint retained in the local transcript. This is
    /// presentation evidence only; live lifecycle authority remains GrokProcess.
    var latestTaskCheckpoint: AssistantTurnCheckpoint? {
        messages.reversed().compactMap { $0.assistantTrace?.checkpoint }.first
    }
    var persistedPendingRecoveryIntent: SessionPendingRecoveryIntent? { pendingRecoveryIntent }
    var effectiveLaunchReceipt: GrokLaunchReceipt? { process.launchReceipt }
    var effectiveSessionReceipt: EffectiveSessionReceipt? {
        process.launchReceipt?.effectiveSessionReceipt(
            activeProcessGeneration: process.activeProcessGeneration
        )
    }
    var settingsApplyTarget: SettingsApplyTarget {
        SettingsApplyTarget(
            localTabID: tabSessionID,
            backendSessionID: durableGrokSessionID,
            processGeneration: process.activeProcessGeneration
        )
    }
    var effectivePermissionMode: GrokPermissionMode {
        process.launchReceipt?.permissionMode ?? .ask
    }

    func mcpServerStatus(named name: String) -> MCPServerStatus? {
        mcpServerStatuses.first { $0.name == name }
    }

    var continuityStatus: SessionContinuityStatus { continuityReceipt.status }

    var continuityBlocksSend: Bool {
        SessionSendGate.decision(for: continuityStatus) == .block
    }

    /// Continuity states that genuinely block Send until the user chooses recovery.
    /// `.verifying` is deliberately excluded: submitting is what triggers the lazy
    /// resume + bounded verification (`deliverPrompt` passes `.verifying` through and
    /// re-checks the send gate after the backend loads), so disabling Send there would
    /// remove the only control that can resolve the state. The Return key path already
    /// allows it; this keeps the Send button consistent.
    var continuityRequiresRecovery: Bool {
        switch continuityStatus {
        case .diverged, .compositeSuspected, .backendMissing, .verificationIncomplete:
            return true
        case .localOnly, .backendBound, .verified, .backendOnly, .recoveryForked, .verifying:
            return false
        }
    }

    /// True while a restored tab is resuming/verifying its saved backend. Send stays
    /// enabled — submitting completes the resume — so the composer can surface a hopeful
    /// "resuming" affordance instead of an error.
    var continuityIsResuming: Bool { continuityStatus == .verifying }

    var continuityPermitsAuthoritativeReconciliation: Bool {
        switch continuityStatus {
        case .backendBound, .verified, .backendOnly, .recoveryForked:
            return true
        case .localOnly, .verifying, .diverged, .compositeSuspected, .backendMissing,
             .verificationIncomplete:
            return false
        }
    }

    var shouldShowContinuityBanner: Bool {
        switch continuityStatus {
        case .backendBound, .verified, .backendOnly, .recoveryForked:
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
        case .backendBound: return "New backend bound"
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
        case .backendBound:
            return "This fresh Grok backend is bound to the current tab and process. There was no prior backend history to verify."
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
        let generation = continuityReceipt.processGeneration.map(String.init) ?? "none"
        return "Backend \(backend) · generation \(generation) · local \(continuityReceipt.localMessageCount) rows · backend \(continuityReceipt.backendMessageCount) rows · matched prefix \(continuityReceipt.matchingPrefixCount) · reason \(continuityReceipt.reason.rawValue)"
    }

    // MARK: - Model selection (real models from `grok models` + initialize modelState)
    private(set) var currentModel: String = "grok-4.5"
    private(set) var modelExecutionState: ModelExecutionState = .unknown
    private(set) var availableModels: [String] = []
    private var modelDisplayNames: [String: String] = [:]
    private var modelContextTokens: [String: Int] = ["grok-4.5": 500_000]
    private var builtInModelIDs = Set<String>()
    private var customModelsByID: [String: CustomModel] = [:]
    /// Credential-free route configuration captured at process launch. Keeping this keyed to
    /// the process generation prevents a later Settings edit from rewriting an older receipt.
    private var routeContractsByProcessGeneration: [UInt64: ModelRouteContract] = [:]
    private var runtimeReloadQueue = RuntimeConfigurationReloadQueue()
    private var settingsApplyContinuations: [
        UUID: CheckedContinuation<SettingsApplyReceipt, Never>
    ] = [:]

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
    /// Authoritative ACP lifecycle receipts. Slice 1 records these without changing
    /// worker presentation; Slice 2 owns correlation with visible worker activities.
    private(set) var subagentSpawnedEvents: [SubagentSpawnedEvent] = []
    private(set) var subagentFinishedEvents: [SubagentFinishedEvent] = []
    /// Spawned lifecycle receipts with no matching spawn tool row (read-only).
    var unboundSubagentSpawnedEvents: [SubagentSpawnedEvent] {
        backgroundTaskTracker.unboundSpawnedEvents
    }
    private var seenSubagentLifecycleKeys: Set<String> = []
    /// Session-wide background tracking remains available for durable tasks,
    /// but run evidence may include only worker rows created or changed during
    /// the active parent turn.
    private var currentTurnWorkerActivityIDs: Set<String> = []
    /// Captured once when an owned worker first changes. This preserves the
    /// current authoritative plan-step relationship without parsing worker prose.
    private var currentTurnWorkerPlanStepIDs: [String: String] = [:]

    // MARK: - Prompt queue (send while streaming)
    private(set) var promptQueue: [String] = []

    /// Unsent composer text for this tab. ChatView is recreated on tab switch
    /// (`.id(tabSessionID)` resets scroll identity), so the draft lives here to
    /// survive switching away and back. In-memory only — not persisted.
    ///
    /// Unsent draft only. Typing here must not spawn grok; Send is the launch
    /// gate. Stop / Close / Quit still cancel a leftover synthetic warm-start
    /// task from tests.
    var composerDraft: String = ""
    private var leftoverWarmStartTask: Task<Void, Never>?
    /// Once `shutdownPermanently()` runs, this store must not spawn grok again.
    private var isPermanentlyShutdown = false
    private(set) var pendingSubmitIntent: PendingSubmitIntent?

    var isPreparingSubmit: Bool { pendingSubmitIntent != nil }

    var taskContractRequestedToolNames: [String] {
        ThreadTaskContractPresentation.currentRequestedToolNames(
            pending: pendingSubmitIntent?.requestedMCPNames,
            draft: selectedPromptMCPNames.union(enabledBuiltInToolNames),
            currentTurn: currentTurnRequestedMCPNames,
            composerOwnsVisibleContext: !selectedPromptMCPNames.isEmpty
                || !composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || hasVisibleFileAttachments
        )
    }

    var pendingSubmitStageText: String? {
        guard pendingSubmitIntent != nil else { return nil }
        if process.sessionId == nil { return "Starting agent…" }
        if process.modelExecutionState.isPending { return "Confirming model…" }
        if mcpServerStatuses.contains(where: { $0.state == .connecting }) {
            return "Preparing selected connections…"
        }
        return connectionState == .ready ? "Dispatching task…" : "Preparing task…"
    }

    /// Starting copy while `session/new` is in flight after Send. Same wording as
    /// the task strip for a fresh `.starting` process.
    var sendOwnedStartupStageText: String? {
        guard pendingSubmitIntent == nil else { return nil }
        guard connectionState == .starting else { return nil }
        guard messages.isEmpty, savedGrokSessionID == nil else { return nil }
        return ThreadTaskContractPresentation.phase(
            live: nil,
            snapshot: nil,
            checkpoint: nil,
            connectionState: .starting,
            isPreparingSubmit: false,
            canResumeSavedTask: false,
            continuityRequiresRecovery: false,
            isResumedSession: false
        )
    }

    /// Cancels only the not-yet-dispatched intent. Backend preparation may finish and
    /// remain ready, but no provider request is sent and the exact composer draft stays
    /// editable in ChatView.
    func cancelPendingSubmit() {
        pendingSubmitIntent = nil
    }

    /// Runs synchronously from the native Return/click handler so a following Escape
    /// can always address the exact pending intent before the async send task runs.
    func prepareSubmit(_ text: String) -> SubmitPreparation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || fileAttachments.contains(where: { !$0.isHidden }) else {
            return .rejected
        }
        switch PendingSubmitIntentPolicy.latchDecision(existing: pendingSubmitIntent, draft: trimmed) {
        case .duplicate, .conflictingDraft:
            return .rejected
        case .latch:
            let intent = makePendingSubmitIntent(draft: trimmed)
            pendingSubmitIntent = intent
            GrokBuildPerformance.mark(.submitIntent)
            return .latched(intent.id)
        }
    }

    private func makePendingSubmitIntent(draft: String) -> PendingSubmitIntent {
        PendingSubmitIntent(
            id: UUID(),
            draft: draft,
            modelID: currentModel,
            modeID: currentMode.rawValue,
            reasoningEffort: modelSupportsReasoningEffort(currentModel) ? workspaceReasoningEffort : "",
            fileAttachments: fileAttachments,
            requestedMCPNames: selectedPromptMCPNames.union(enabledBuiltInToolNames)
        )
    }

    private func pendingSubmitRouteStillMatches(_ intent: PendingSubmitIntent) -> Bool {
        PendingSubmitIntentPolicy.routeStillMatches(
            intent,
            modelID: currentModel,
            modeID: currentMode.rawValue,
            reasoningEffort: modelSupportsReasoningEffort(currentModel) ? workspaceReasoningEffort : "",
            fileAttachments: fileAttachments,
            requestedMCPNames: selectedPromptMCPNames.union(enabledBuiltInToolNames)
        )
    }

    private func cancelLeftoverWarmStart() {
        leftoverWarmStartTask?.cancel()
        leftoverWarmStartTask = nil
    }

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
        activeTurnBackendSessionID = value ? process.sessionId : nil
    }

    /// Test-only: ingest a background-activity ACP payload without a live process.
    func ingestBackgroundActivityForTests(_ payload: [String: Any]) {
        let previousActivities = backgroundTaskTracker.activities
        backgroundTaskTracker.apply(update: payload)
        backgroundActivities = backgroundTaskTracker.activities
        recordCurrentTurnWorkerChanges(since: previousActivities)
    }

    /// Test-only: ingest a typed `subagent_spawned` receipt without a live process.
    func ingestSubagentSpawnedForTests(_ event: SubagentSpawnedEvent) {
        let previousActivities = backgroundTaskTracker.activities
        backgroundTaskTracker.apply(spawned: event)
        backgroundActivities = backgroundTaskTracker.activities
        recordCurrentTurnWorkerChanges(since: previousActivities)
    }

    /// Test-only: a long-lived warm-start stand-in that must cancel on teardown.
    func beginSyntheticWarmStartForTests() {
        leftoverWarmStartTask = Task { try? await Task.sleep(for: .seconds(30)) }
    }

    var leftoverWarmStartIsRunningForTests: Bool { leftoverWarmStartTask != nil }

    var isPermanentlyShutdownForTests: Bool { isPermanentlyShutdown }

    /// Test-only: force a continuity status so the Send-gate predicates can be exercised
    /// without staging a full backend verification round trip.
    func setContinuityStatusForTests(_ status: SessionContinuityStatus) {
        continuityReceipt = SessionContinuityReceipt(
            status: status,
            reason: continuityReceipt.reason,
            normalizationVersion: continuityReceipt.normalizationVersion,
            authenticationSchemaVersion: continuityReceipt.authenticationSchemaVersion,
            localMessageCount: continuityReceipt.localMessageCount,
            backendMessageCount: continuityReceipt.backendMessageCount,
            matchingPrefixCount: continuityReceipt.matchingPrefixCount,
            localTranscriptTag: continuityReceipt.localTranscriptTag,
            backendTranscriptTag: continuityReceipt.backendTranscriptTag,
            verifiedAt: continuityReceipt.verifiedAt,
            localTabID: continuityReceipt.localTabID,
            backendID: continuityReceipt.backendID,
            processGeneration: continuityReceipt.processGeneration
        )
    }

    var pendingRuntimeReloadForTests: Bool { runtimeReloadQueue.hasPending }
    var pendingSettingsApplyCountForTests: Int {
        runtimeReloadQueue.pendingSettingsRequestCount
    }
    func applyQueuedRuntimeReloadsForTests() async {
        isStreaming = false
        await performCoalescedRuntimeReload()
    }
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
    /// Incremental streaming presentation for the active assistant message. Updated once
    /// per display flush with the exact appended batch (O(appended), not O(full text));
    /// `MessageBubble` consumes it instead of re-scanning the whole string per render.
    private(set) var streamingPresentation: StreamingMarkdownPresentation?
    private var streamingMarkdownAccumulator = StreamingMarkdownAccumulator()
    private var streamingAccumulatorMessageID: UUID?

    /// Session-local usage ledger, appended only from authoritative `turn_completed`
    /// receipts (agentic roadmap Slice 6). Reset when the tab prepares a new workspace
    /// binding; never estimated mid-turn.
    private(set) var sessionUsage = SessionUsageLedger()

    /// Configured `[subagents.roles.*]` name→model map for worker routing display
    /// (agentic roadmap Slice 5). Declared config, refreshed at prepare/launch;
    /// workers with no exact role-name match make no routing claim.
    private(set) var subagentRoleModelsByName: [String: String] = [:]

    /// One-line session usage HUD ("12.4k tokens · 3 calls · 2 turns · ≈$…-… est."),
    /// nil until the first settled turn. Dollar bounds appear only for models with
    /// catalog-known pricing.
    var sessionUsageSummary: String? {
        sessionUsage.summaryText(pricing: ModelPricingStore.all())
    }

    /// Provider-grouped model choices so custom/OpenRouter routes read as first-class
    /// main-agent options rather than a flat ID soup (LLM diversity).
    var groupedAvailableModels: [(label: String, ids: [String])] {
        Self.groupedModels(available: availableModels, customIDs: Set(customModelsByID.keys))
    }

    nonisolated static func groupedModels(
        available: [String],
        customIDs: Set<String>
    ) -> [(label: String, ids: [String])] {
        let custom = available.filter { customIDs.contains($0) }
        let native = available.filter { !customIDs.contains($0) }
        var groups: [(String, [String])] = []
        if !native.isEmpty { groups.append(("Grok", native)) }
        if !custom.isEmpty { groups.append(("Your models", custom)) }
        return groups
    }

    /// Makes this tab's current model the project default that *new* sessions inherit
    /// (`TabModelIntent.inheritProjectDefault` resolves through the per-workspace agent
    /// settings). Existing tabs keep their own intent; nothing restarts.
    func setCurrentModelAsProjectDefault() {
        guard let workspace = currentWorkspace else { return }
        let model = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        var settings = SessionLayoutStore.agentSettings(for: workspace.id)
        settings.model = model
        SessionLayoutStore.saveAgentSettings(settings, for: workspace.id)
        NotificationCenter.default.post(
            name: .workspaceAgentSettingsChanged,
            object: nil,
            userInfo: ["workspaceID": workspace.id]
        )
        appendSystemNote("New sessions in \(workspace.displayName) will start on \(modelDisplayName(model)).")
    }

    private func refreshSubagentRoleModels() {
        Task { [weak self] in
            let map = await Task.detached(priority: .utility) {
                SubagentRouting.rolesByName(SubagentRoleStore.load())
            }.value
            self?.subagentRoleModelsByName = map
        }
    }
    private var streamingTextFlushTask: Task<Void, Never>?
    private var deferredPromptCompletion: (assistantID: UUID, ok: Bool)?
    private var turnSettlement = TurnSettlementCoordinator()
    private var activeTurnBackendSessionID: String?
    private var activeTurnCompletionConsumed = false
    private var consumedTurnCompletionKeys: Set<String> = []
    private var authoritativeTailAssistantID: UUID?
    private var closedTurnAssistantID: UUID?
    private var closedTurnHasAuthoritativeHistory = false
    private var pendingLateChunkPersistence = false
    /// Successful completion is authoritative immediately, but backend-tail
    /// reconciliation waits until already-received text has visibly drained.
    /// Otherwise one large final ACP chunk bypasses the paced reveal and snaps in.
    private var pendingCompletionReconciliation = false
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
        sessionUsage.reset()
        refreshSubagentRoleModels()
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
        // A selected tab may already own an LRU-retained process. Its live
        // backend receipt outranks an older or absent layout binding.
        if let liveBackendID = process.sessionId,
           let generation = process.activeProcessGeneration,
           process.launchReceipt?.localTabID == id {
            self.savedGrokSessionID = liveBackendID
            continuityBackendID = liveBackendID
            continuityReceipt = continuityReceipt.reason == .noBackendBinding
                ? Self.freshBackendBoundContinuityReceipt(
                    localTabID: id,
                    backendID: liveBackendID,
                    processGeneration: generation,
                    localMessageCount: SessionTranscriptRecovery.normalizedMessageCount(messages)
                )
                : Self.identifiedContinuityReceipt(
                    continuityReceipt,
                    localTabID: id,
                    backendID: liveBackendID,
                    processGeneration: generation
                )
            persistedContinuityReceipt = continuityReceipt
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

        let identifiedReceipt = Self.identifiedContinuityReceipt(
            verification.receipt,
            localTabID: expectedTabID,
            backendID: targetBackendID,
            processGeneration: nil
        )
        continuityReceipt = identifiedReceipt
        persistedContinuityReceipt = identifiedReceipt
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
        continuityReceipt = Self.identifiedContinuityReceipt(
            verification.receipt,
            localTabID: tabSessionID,
            backendID: candidate.backendID,
            processGeneration: nil
        )
        persistedContinuityReceipt = continuityReceipt
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

    private static func freshBackendBoundContinuityReceipt(
        localTabID: UUID?,
        backendID: String,
        processGeneration: UInt64,
        localMessageCount: Int
    ) -> SessionContinuityReceipt {
        SessionContinuityReceipt(
            status: .backendBound,
            reason: .freshBackendBound,
            normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
            authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
            localMessageCount: localMessageCount,
            backendMessageCount: localMessageCount,
            matchingPrefixCount: localMessageCount,
            localTranscriptTag: nil,
            backendTranscriptTag: nil,
            verifiedAt: Date(),
            localTabID: localTabID,
            backendID: backendID,
            processGeneration: processGeneration
        )
    }

    private static func identifiedContinuityReceipt(
        _ receipt: SessionContinuityReceipt,
        localTabID: UUID?,
        backendID: String?,
        processGeneration: UInt64?
    ) -> SessionContinuityReceipt {
        SessionContinuityReceipt(
            status: receipt.status,
            reason: receipt.reason,
            normalizationVersion: receipt.normalizationVersion,
            authenticationSchemaVersion: receipt.authenticationSchemaVersion,
            localMessageCount: receipt.localMessageCount,
            backendMessageCount: receipt.backendMessageCount,
            matchingPrefixCount: receipt.matchingPrefixCount,
            localTranscriptTag: receipt.localTranscriptTag,
            backendTranscriptTag: receipt.backendTranscriptTag,
            verifiedAt: receipt.verifiedAt,
            localTabID: localTabID,
            backendID: backendID,
            processGeneration: processGeneration
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
            currentModel = selectionModelID(
                requested: modelExecutionState.requestedModelID,
                effective: effective
            )
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
        currentTurnRequestedMCPNames.removeAll()
        currentTurnAttachmentNames.removeAll()
        goalState = nil
        clearWorkflowRunState()
        clearBackgroundTaskState()
        clearSubagentLifecycleState()
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
        runtimeReloadQueue.enqueueGeneralReload()
        // Never kill an in-flight response for a wiring change. Every reload source
        // joins one queue and drains once at the ordered turn-completion boundary.
        if isStreaming {
            configurationStatusMessage = "Configuration changes will apply after the current response."
            return
        }
        await performCoalescedRuntimeReload()
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

        runtimeReloadQueue.enqueue(change)
        if isStreaming {
            configurationStatusMessage = "Model changes will apply after the current response."
            return
        }

        await performCoalescedRuntimeReload()
    }

    /// Applies one pane request to this exact tab. Streaming requests suspend until
    /// the turn completes, then share one restart with any queued model/general reload.
    func applySettingsRequest(_ request: SettingsApplyRequest) async -> SettingsApplyReceipt {
        guard request.requiresProcessRestart,
              request.applyScope == .activeTabRestart
                || request.applyScope == .allEligibleLiveTabs else {
            return .completed(
                request: request,
                status: .success,
                summary: "Saved for future eligible sessions."
            )
        }
        guard currentWorkspace != nil else {
            return .completed(
                request: request,
                status: .success,
                summary: "Saved; no project session is active."
            )
        }
        guard settingsApplyTargetMatches(request.target) else {
            return .completed(
                request: request,
                status: .failure,
                summary: "The selected tab or process changed before Apply could start. Nothing was reconnected."
            )
        }
        guard process.activeProcessGeneration != nil else {
            return .completed(
                request: request,
                status: .success,
                summary: "Saved; this tab has no live process and will use the setting when it starts."
            )
        }

        return await withCheckedContinuation { continuation in
            settingsApplyContinuations[request.id] = continuation
            runtimeReloadQueue.enqueue(request)
            if isStreaming {
                configurationStatusMessage = "Settings saved. Restart queued until the current response finishes."
            } else {
                Task { [weak self] in
                    await self?.performCoalescedRuntimeReload()
                }
            }
        }
    }

    /// Restarts with the durable backend receipt and resolves every queued Settings
    /// request against the resulting exact tab/backend/process generation.
    private func performCoalescedRuntimeReload() async {
        guard !isStreaming, !isApplyingConfiguration else { return }
        let batch = runtimeReloadQueue.drain()
        guard !batch.isEmpty else { return }

        var validSettingsRequests: [SettingsApplyRequest] = []
        for request in batch.settingsRequests {
            guard settingsApplyTargetMatches(request.target) else {
                finishSettingsApply(
                    request,
                    with: .completed(
                        request: request,
                        status: .failure,
                        summary: "The tab, backend, or process generation changed while Apply was queued. The live process was left untouched."
                    )
                )
                continue
            }
            validSettingsRequests.append(request)
        }

        let shouldRestart = batch.requestsGeneralReload
            || !batch.affectedModelIDs.isEmpty
            || validSettingsRequests.contains { $0.requiresProcessRestart }
        guard shouldRestart, currentWorkspace != nil else {
            for request in validSettingsRequests {
                finishSettingsApply(
                    request,
                    with: .completed(
                        request: request,
                        status: .success,
                        summary: "Saved for future eligible sessions."
                    )
                )
            }
            return
        }

        isApplyingConfiguration = true
        configurationStatusMessage = validSettingsRequests.isEmpty
            ? "Applying configuration…"
            : "Applying saved Settings to the current tab…"
        let resumeID = durableGrokSessionID
        await restartProcess(resumeSessionID: resumeID)
        isApplyingConfiguration = false

        let liveReceipt = effectiveSessionReceipt
        for request in validSettingsRequests {
            finishSettingsApply(
                request,
                with: SettingsApplyReceiptResolver.resolve(
                    request: request,
                    connectionIsReady: connectionState == .ready,
                    liveReceipt: liveReceipt
                )
            )
        }

        if connectionState == .ready {
            if liveReceipt?.launchOutcome == .recoveryForked {
                configurationStatusMessage = "Settings applied after a recovery fork; review the receipt."
                appendSystemNote("Applied configuration after a disclosed session recovery fork.")
            } else {
                configurationStatusMessage = validSettingsRequests.isEmpty
                    ? "Configuration applied."
                    : "Settings are live in the current tab."
                appendSystemNote("Applied updated configuration.")
            }
        } else {
            configurationStatusMessage = lastError ?? "Saved Settings could not be applied to the current tab."
        }

        if runtimeReloadQueue.hasPending, !isStreaming {
            await performCoalescedRuntimeReload()
        }
    }

    private func settingsApplyTargetMatches(_ target: SettingsApplyTarget?) -> Bool {
        guard let target else { return false }
        return target == settingsApplyTarget
    }

    private func finishSettingsApply(
        _ request: SettingsApplyRequest,
        with receipt: SettingsApplyReceipt
    ) {
        settingsApplyContinuations.removeValue(forKey: request.id)?.resume(returning: receipt)
    }

    func startNewSession(resetThreadTools: Bool = false) async {
        guard !isPermanentlyShutdown else { return }
        let predecessorBackendID = durableGrokSessionID
        let localMessagesAtFork = messages
        messages.removeAll()
        if resetThreadTools {
            selectedPromptMCPNames.removeAll()
            enabledBuiltInToolNames.removeAll()
            currentTurnRequestedMCPNames.removeAll()
        }
        streamingMessageID = nil
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        fileAttachments.removeAll()
        currentTurnAttachmentNames.removeAll()
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

    /// Explicit header Resume action. It translates to the native ACP
    /// `session/load` path through `restartProcess`, including the existing
    /// transcript-continuity verification and exact model confirmation. It does
    /// not send a provider prompt or claim work continues after the process exits.
    @discardableResult
    func resumeTaskSession() async -> Bool {
        guard canResumeTaskSession, let backendID = durableGrokSessionID else {
            lastError = continuityRequiresRecovery
                ? "This saved task requires Continue as New or an exact relink."
                : "No resumable saved task is available."
            return false
        }
        await restartProcess(resumeSessionID: backendID)
        return connectionState == .ready && process.sessionId == backendID
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
        clearSubagentLifecycleState()
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

    private func clearSubagentLifecycleState() {
        subagentSpawnedEvents = []
        subagentFinishedEvents = []
        seenSubagentLifecycleKeys = []
    }

    private func restartProcess(
        resumeSessionID: String? = nil,
        forceFreshStart: Bool = false,
        freshStartPredecessorBackendID: String? = nil
    ) async {
        guard !isPermanentlyShutdown else { return }
        guard let ws = currentWorkspace else { return }
        // A populated restored tab always belongs to its saved backend session. Several
        // asynchronous launch paths can request a restart without carrying that id; resolving
        // it centrally prevents any of them from silently replacing the visible conversation
        // with a fresh default-model session.
        // The stop guard is kept here as well as at the send boundary: workspace
        // selection and other restart paths must not bypass a required fresh start.
        let shouldForceFreshStart = forceFreshStart || forcedFreshStartAfterUserStop
        let forcedPredecessorBackendID = freshStartPredecessorBackendID
            ?? stoppedBackendIDNeedingFreshStart
        if shouldForceFreshStart {
            forcedFreshStartAfterUserStop = false
            stoppedBackendIDNeedingFreshStart = nil
        }
        let effectiveResumeSessionID = shouldForceFreshStart
            ? nil
            : Self.resolvedResumeSessionID(
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
        availableModes = []
        currentMode = .agent
        isYolo = false
        lastError = nil
        startConnectionWatchdog()
        applyBuiltInModelCatalog(await GrokModelCatalog.shared.models())
        let settings = loadPermissionSettings()
        let savedSelection = effectiveResumeSessionID.flatMap { sessionSelections[$0] }
        let modelForLaunch = modelForProcessLaunch(fallbackSelection: savedSelection)
        let routeContractForLaunch = ModelRouteContract.resolve(
            selectedModelID: modelForLaunch,
            customModel: customModelsByID[modelForLaunch]
        )
        let expectedEffectiveModelForLaunch = customModelsByID[modelForLaunch]?.model
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoningEffortForLaunch = modelSupportsReasoningEffort(modelForLaunch) ? workspaceReasoningEffort : ""
        var browserSettings = BrowserSettingsStore.loadApplied()
        var computerUseSettings = ComputerUseSettingsStore.loadApplied()
        browserSettings.enabled = browserSettings.enabled
            && enabledBuiltInToolNames.contains(BuiltInToolConnection.browser.rawValue)
        computerUseSettings.enabled = computerUseSettings.enabled
            && enabledBuiltInToolNames.contains(BuiltInToolConnection.computerUse.rawValue)
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
        let requestedMCPServerNames = selectedPromptMCPNames.union(enabledBuiltInToolNames)
        var knownConfiguredMCPServerNames: Set<String> = []
        if !requestedMCPServerNames.isEmpty {
            do {
                let catalog = try await GrokCLIService().listMCPServers(cwd: ws.path)
                knownConfiguredMCPServerNames = Set(catalog.compactMap { server in
                    server.isEnabled == false ? nil : server.name
                })
                let unsafeNames = knownConfiguredMCPServerNames.union(requestedMCPServerNames)
                    .filter { !GrokMCPGatewayLaunchPolicy.isSafeServerName($0) }
                guard unsafeNames.isEmpty else {
                    connectionWatchdogTask?.cancel()
                    connectionState = .failed("The Grok CLI MCP catalog contains a server name that cannot be represented by an exact permission rule.")
                    lastError = "MCP launch stopped before dispatch because the exact selected-server boundary could not be expressed safely."
                    return
                }
            } catch {
                connectionWatchdogTask?.cancel()
                connectionState = .failed("Could not verify the Grok CLI MCP catalog for this exact thread selection.")
                lastError = "MCP launch stopped before dispatch because GrokBuild could not verify which configured servers must remain denied."
                return
            }
        }
        mcpServerStatuses = MCPReadinessPolicy.connectingStatuses(for: mcpServers)
        let opts = GrokLaunchOptions(
            localTabID: tabSessionID,
            agent: GrokAgentProfiles.launchArgument(for: effectiveAgentSelection),
            // Memory is a single app-scoped toggle: on → `--experimental-memory`, off → `--no-memory`.
            noMemory: !settings.memoryEnabled,
            experimentalMemory: settings.memoryEnabled,
            permissionMode: settings.permissionMode,
            reasoningEffort: reasoningEffortForLaunch,
            model: modelForLaunch.isEmpty ? nil : modelForLaunch,
            expectedEffectiveModelID: expectedEffectiveModelForLaunch?.isEmpty == false
                ? expectedEffectiveModelForLaunch
                : nil,
            sandboxProfile: settings.sandboxProfile,
            disableWebSearch: settings.disableWebSearch,
            noSubagents: settings.noSubagents,
            allowRules: lineList(settings.allowRules),
            denyRules: lineList(settings.denyRules),
            resumeSessionID: effectiveResumeSessionID,
            forkSession: launchForkSession,
            newSessionID: launchNewSessionID,
            mcpServers: mcpServers,
            allowedMCPServerNames: requestedMCPServerNames,
            knownConfiguredMCPServerNames: knownConfiguredMCPServerNames,
            mcpGatewayEnabled: Self.mcpGatewayEnabled(
                selectedPromptMCPNames: selectedPromptMCPNames,
                enabledBuiltInToolNames: enabledBuiltInToolNames
            )
        )
        guard !isPermanentlyShutdown else {
            connectionWatchdogTask?.cancel()
            connectionState = .idle
            return
        }
        let spawnInterval = GrokBuildPerformance.begin(.processSpawnToACPReady)
        await process.start(workspace: ws, options: opts)
        if isPermanentlyShutdown {
            spawnInterval.end()
            await process.shutdown()
            connectionState = .idle
            return
        }
        spawnInterval.end()
        if let generation = process.launchReceipt?.processGeneration {
            routeContractsByProcessGeneration[generation] = routeContractForLaunch
            if routeContractsByProcessGeneration.count > 8,
               let oldest = routeContractsByProcessGeneration.keys.min() {
                routeContractsByProcessGeneration.removeValue(forKey: oldest)
            }
        }
        mcpServerStatuses = process.mcpServerStatuses
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
        guard let successorBackendID = process.sessionId,
              let processGeneration = process.activeProcessGeneration else {
            lastError = "Grok started without an authoritative backend binding receipt."
            connectionState = .failed(lastError ?? "Backend binding failed.")
            await process.stop()
            return
        }
        savedGrokSessionID = successorBackendID
        continuityBackendID = successorBackendID
        let forkReason: SessionForkLedgerReason? = {
            if process.sessionLoadStartedFreshFallback { return .resumeFallback }
            if launchForkSession { return .explicitBackendFork }
            if shouldForceFreshStart { return .explicitFreshStart }
            if effectiveResumeSessionID == nil, hadLocalConversationBeforeStart {
                return pendingRecoveryIntent?.action == .continueAsNew
                    ? .explicitContinueAsNew
                    : .localOnlyStart
            }
            return nil
        }()
        if let forkReason {
            await recordRecoveryFork(
                predecessorBackendID: forcedPredecessorBackendID
                    ?? pendingRecoveryIntent?.predecessorBackendID
                    ?? effectiveResumeSessionID,
                successorBackendID: successorBackendID,
                reason: forkReason
            )
            if forkReason == .explicitContinueAsNew {
                pendingRecoveryIntent = nil
            }
        } else if effectiveResumeSessionID == nil {
            continuityReceipt = Self.freshBackendBoundContinuityReceipt(
                localTabID: tabSessionID,
                backendID: successorBackendID,
                processGeneration: processGeneration,
                localMessageCount: SessionTranscriptRecovery.normalizedMessageCount(messages)
            )
            persistedContinuityReceipt = continuityReceipt
        } else {
            continuityReceipt = Self.identifiedContinuityReceipt(
                continuityReceipt,
                localTabID: tabSessionID,
                backendID: successorBackendID,
                processGeneration: processGeneration
            )
            persistedContinuityReceipt = continuityReceipt
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
            verifiedAt: Date(),
            localTabID: tabSessionID,
            backendID: successorBackendID,
            processGeneration: process.activeProcessGeneration
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
        mcpServerStatuses = MCPReadinessPolicy.failedStatuses(
            for: mcpServerStatuses.map(\.name),
            reason: "The process did not reach ACP readiness before the connection timeout."
        )
        connectionState = .failed(lastError ?? "Timed out while connecting to grok.")
        await process.stop()
    }

    // MARK: Messaging

    @discardableResult
    func send(_ text: String, preparedIntentID: UUID? = nil) async -> Bool {
        await deliverPrompt(text, waitForCompletion: false, preparedIntentID: preparedIntentID)
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

    private func deliverPrompt(
        _ text: String,
        waitForCompletion: Bool,
        fromQueue: Bool = false,
        preparedIntentID: UUID? = nil
    ) async -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var claimedPendingIntent: PendingSubmitIntent?
        defer {
            if let claimedPendingIntent,
               pendingSubmitIntent?.id == claimedPendingIntent.id {
                pendingSubmitIntent = nil
            }
        }
        let initiallyFrozenAttachments = preparedIntentID.flatMap { intentID in
            pendingSubmitIntent?.id == intentID ? pendingSubmitIntent?.fileAttachments : nil
        }
        guard !trimmed.isEmpty
                || (initiallyFrozenAttachments ?? fileAttachments).contains(where: { !$0.isHidden }) else {
            return false
        }
        guard currentWorkspace != nil else {
            lastError = "Select a project first."
            return false
        }
        if preparedIntentID == nil, pendingSubmitIntent == nil, !isStreaming {
            GrokBuildPerformance.mark(.submitIntent)
        }
        if continuityRequiresRecovery {
            // Never a dead end: the saved backend can't be safely resumed, so fork to a
            // clean backend (preserving the local transcript) and continue. continueAsNew
            // sets .recoveryForked, which the send gate below allows. This never appends to
            // the diverged/missing/composite backend, so continuity safety is intact.
            guard await continueAsNew() else { return false }
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
        if preparedIntentID != nil || (connectionState != .ready &&
            (leftoverWarmStartTask != nil || connectionState == .starting)) {
            let intent: PendingSubmitIntent
            if let preparedIntentID {
                guard let pendingSubmitIntent, pendingSubmitIntent.id == preparedIntentID else {
                    return false
                }
                intent = pendingSubmitIntent
            } else {
                switch PendingSubmitIntentPolicy.latchDecision(existing: pendingSubmitIntent, draft: trimmed) {
                case .duplicate, .conflictingDraft:
                    // A repeated Return/click while the first intent is latched is never a
                    // second queue entry or billable request.
                    return false
                case .latch:
                    break
                }
                intent = makePendingSubmitIntent(draft: trimmed)
                pendingSubmitIntent = intent
            }
            claimedPendingIntent = intent
            if let warmStart = leftoverWarmStartTask {
                await warmStart.value
            } else {
                if connectionState != .ready,
                   connectionState != .starting,
                   process.sessionId == nil {
                    let forceFreshStart = forcedFreshStartAfterUserStop
                    let predecessorBackendID = stoppedBackendIDNeedingFreshStart
                    forcedFreshStartAfterUserStop = false
                    stoppedBackendIDNeedingFreshStart = nil
                    await restartProcess(
                        resumeSessionID: savedGrokSessionID,
                        forceFreshStart: forceFreshStart,
                        freshStartPredecessorBackendID: predecessorBackendID
                    )
                }
                while connectionState == .starting, pendingSubmitIntent?.id == intent.id {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            guard pendingSubmitIntent?.id == intent.id else { return false }
            guard connectionState == .ready else {
                pendingSubmitIntent = nil
                if lastError == nil {
                    lastError = connectionState.errorMessage ?? "Grok could not prepare this task. Retry or start a new session."
                }
                return false
            }
            guard pendingSubmitRouteStillMatches(intent) else {
                lastError = "The model, mode, reasoning effort, attachments, or attached MCP set changed while the task was preparing. Review the restored draft and send again."
                return false
            }
        }
        if connectionState != .ready {
            if process.sessionId == nil && connectionState != .starting {
                // Restored tabs render their local transcript before the live Grok
                // session finishes its lazy resume. A stopped turn may override that
                // default only when its continuity receipt did not own the stopped
                // tab/backend/generation; in that case a fresh ledgered run is safer
                // than silently resuming a mismatched backend.
                let forceFreshStart = forcedFreshStartAfterUserStop
                let predecessorBackendID = stoppedBackendIDNeedingFreshStart
                forcedFreshStartAfterUserStop = false
                stoppedBackendIDNeedingFreshStart = nil
                await restartProcess(
                    resumeSessionID: savedGrokSessionID,
                    forceFreshStart: forceFreshStart,
                    freshStartPredecessorBackendID: predecessorBackendID
                )
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
        let desiredAllowedMCPServerNames = claimedPendingIntent?.requestedMCPNames
            ?? selectedPromptMCPNames.union(enabledBuiltInToolNames)
        let desiredMCPGatewayState = !desiredAllowedMCPServerNames.isEmpty
        let desiredReasoningEffort = claimedPendingIntent?.reasoningEffort
            ?? (modelSupportsReasoningEffort(currentModel) ? workspaceReasoningEffort : "")
        let frozenReasoningLaunchMismatch = claimedPendingIntent != nil
            && (process.launchReceipt?.requestedReasoningEffort ?? "") != desiredReasoningEffort
        if process.launchReceipt?.mcpGatewayEnabled != desiredMCPGatewayState
            || Set(process.launchReceipt?.allowedMCPServerNames ?? []) != desiredAllowedMCPServerNames
            || frozenReasoningLaunchMismatch {
            await restartProcess(resumeSessionID: process.sessionId ?? savedGrokSessionID)
            guard connectionState == .ready,
                  process.launchReceipt?.mcpGatewayEnabled == desiredMCPGatewayState,
                  Set(process.launchReceipt?.allowedMCPServerNames ?? []) == desiredAllowedMCPServerNames,
                  (claimedPendingIntent == nil
                    || (process.launchReceipt?.requestedReasoningEffort ?? "") == desiredReasoningEffort),
                  SessionSendGate.decision(for: continuityStatus) != .block else {
                if lastError == nil {
                    lastError = "Grok could not apply this turn's frozen reasoning-effort and MCP launch policy. Retry the turn."
                }
                return false
            }
        }

        if let claimedPendingIntent {
            var confirmationWaits = 0
            while (process.modelExecutionState.isPending
                    || process.currentMode.rawValue != claimedPendingIntent.modeID),
                  pendingSubmitIntent?.id == claimedPendingIntent.id,
                  confirmationWaits < 240 {
                confirmationWaits += 1
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard pendingSubmitIntent?.id == claimedPendingIntent.id,
                  pendingSubmitRouteStillMatches(claimedPendingIntent) else {
                lastError = "The frozen task inputs no longer match after backend preparation. Review the restored draft and send again."
                return false
            }
            modelExecutionState = process.modelExecutionState
            let expectedEffectiveModel = customModelsByID[claimedPendingIntent.modelID ?? ""]?.model
            guard PendingSubmitIntentPolicy.backendRouteIsConfirmed(
                claimedPendingIntent,
                modelExecutionState: modelExecutionState,
                expectedEffectiveModelID: expectedEffectiveModel,
                currentModeID: process.currentMode.rawValue
            ) else {
                lastError = "Grok did not confirm the frozen model and mode before dispatch. The draft was preserved and no provider request was sent."
                return false
            }
        }

        if commandHistory.last != trimmed {
            commandHistory.append(trimmed)
        }
        historyIndex = nil

        clearTurnState()
        isGrokking = true
        turnStartedAt = Date()
        startStallWatchdog()

        var attachmentBlocks: [String] = []
        currentTurnRequestedMCPNames = desiredAllowedMCPServerNames.sorted()
        if let mcpBlock = PromptMCPAttachmentPromptBuilder.build(from: currentTurnRequestedMCPNames) {
            attachmentBlocks.append(mcpBlock)
        }
        let dispatchAttachments = claimedPendingIntent?.fileAttachments ?? fileAttachments
        currentTurnAttachmentNames = dispatchAttachments
            .filter { !$0.isHidden }
            .map(\.relativePath)
        if let fileBlock = AttachmentPromptBuilder.build(from: dispatchAttachments) {
            attachmentBlocks.append(fileBlock)
        }
        if !attachmentBlocks.isEmpty {
            let attachmentBlock = attachmentBlocks.joined(separator: "\n\n")
            trimmed = trimmed.isEmpty ? attachmentBlock : "\(attachmentBlock)\n\n\(trimmed)"
        }
        if let goalCommand = GoalCommand.parse(from: trimmed) {
            SessionGoalStateMutation.apply(goalCommand, to: &goalState)
        }
        if trimmed.lowercased().hasPrefix("/btw") {
            pendingBtw = true
        }
        fileAttachments.removeAll()
        selectedPromptMCPNames.removeAll()
        pendingSubmitIntent = nil

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
        GrokBuildPerformance.mark(.dispatch)

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
        // Idempotent: the authoritative-completion force-finish (below) can settle the
        // turn before a late/stuck JSON-RPC prompt response arrives; the second call
        // must not re-run capture or flip state that already settled.
        guard isStreaming || isGrokking else { return }
        GrokBuildPerformance.mark(.settled)
        firstChunkInterval?.end()
        firstChunkInterval = nil
        let settledAssistantID = authoritativeTailAssistantID ?? assistantID
        attachCurrentTurnTrace(to: settledAssistantID)
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
            isThinkingExpanded = false
        }
        if ok {
            connectionState = .ready
            notifyMessagesChanged()
            activeTurnBackendSessionID = nil
            authoritativeTailAssistantID = nil
            if runtimeReloadQueue.hasPending {
                Task { [weak self] in
                    guard let self else { return }
                    await self.performCoalescedRuntimeReload()
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
        if latestTurnOutcome != .cancelled {
            lastError = lastError ?? process.state.errorMessage ?? "Failed to send to grok."
        }
        // An owned `turn_completed` is the lifecycle authority even when its
        // stop reason is error/cancelled. GrokProcess releases a missing prompt
        // RPC response from that acknowledgement, but can still read `.busy`
        // in this synchronous handler before its async `send` resumes and sets
        // `.ready`. Do not strand the next turn behind that harmless race.
        let hasAuthoritativeCompletion = latestTurnOutcome.map {
            [.completed, .failed, .cancelled].contains($0)
        } ?? false
        connectionState = hasAuthoritativeCompletion && process.sessionId != nil
            ? .ready
            : process.state
        if let idx = messages.firstIndex(where: { $0.id == assistantID }),
           messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: idx)
        }
        notifyMessagesChanged()
        if runtimeReloadQueue.hasPending {
            Task { [weak self] in
                await self?.performCoalescedRuntimeReload()
            }
        }
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
        reasoningSummaryChunks = []
        thinkingDuration = nil
        thinkingStartedAt = nil
        turnStartedAt = nil
        isThinkingExpanded = false
        liveToolCalls = []
        latestTurnOutcome = nil
        runArtifacts = []
        runEvidenceSnapshot = nil
        currentRunPlan = []
        currentTurnToolPlanStepIDs = [:]
        currentTurnWorkerActivityIDs = []
        currentTurnWorkerPlanStepIDs = [:]
        pendingArtifactPathsByToolCallID = [:]
        activeTurnCompletionConsumed = false
        backgroundTaskTracker.beginUserTurn()
        backgroundActivities = backgroundTaskTracker.activities
    }

    private func invalidateTurnSettlement() {
        turnSettlement.invalidate()
        activeTurnBackendSessionID = nil
        authoritativeTailAssistantID = nil
        closedTurnAssistantID = nil
        closedTurnHasAuthoritativeHistory = false
    }

    func stop() async {
        pendingSubmitIntent = nil
        let wasActiveTurn = isStreaming || isGrokking
        let stoppedAssistantID = streamingMessageID
        let stoppedBackendID = process.sessionId ?? savedGrokSessionID
        let stoppedGeneration = process.activeProcessGeneration
        let stoppedBinding = RunEvidenceSnapshot.Binding(
            localTabID: tabSessionID,
            workspaceID: currentWorkspace?.id,
            backendSessionID: stoppedBackendID,
            processGeneration: stoppedGeneration,
            requestID: nil,
            isSettled: true
        )
        let continuationDecision = StoppedTurnContinuationDecision.decision(
            receipt: continuityReceipt,
            localTabID: tabSessionID,
            backendID: stoppedBackendID,
            processGeneration: stoppedGeneration
        )
        firstChunkInterval?.end()
        firstChunkInterval = nil
        cancelLeftoverWarmStart()
        cancelStreamingTextFlush()
        attachCurrentTurnTrace(to: stoppedAssistantID)
        invalidateTurnSettlement()
        isStreaming = false
        isGrokking = false
        turnStartedAt = nil
        streamingMessageID = nil
        stopStallWatchdog()
        pendingPermissions.removeAll()
        pendingExitPlan = nil
        pendingQuestions.removeAll()
        // Drain ACP during process.stop() before marking leftovers. A
        // subagent_finished that arrives in that window is a real terminal
        // receipt and stays completed under the parent userStopped outcome.
        // markActiveSubagentsStoppedByUser then orphans/cancels only workers
        // that never finished.
        let stopStartedAt = ContinuousClock.now
        await process.stop()
        let stopDuration = stopStartedAt.duration(to: .now).components
        backgroundTaskTracker.recordStopToSettle(
            milliseconds: Int(stopDuration.seconds * 1_000)
                + Int(stopDuration.attoseconds / 1_000_000_000_000_000)
        )
        backgroundTaskTracker.markActiveSubagentsStoppedByUser()
        backgroundTaskTracker.markActiveActivitiesStopped()
        backgroundActivities = backgroundTaskTracker.activities
        mcpServerStatuses = MCPReadinessPolicy.stoppedStatuses(for: mcpServerStatuses.map(\.name))
        connectionState = .idle
        guard wasActiveTurn else { return }
        latestTurnOutcome = .userStopped
        forcedFreshStartAfterUserStop = continuationDecision == .startFresh
        stoppedBackendIDNeedingFreshStart = continuationDecision == .startFresh
            ? stoppedBackendID
            : nil
        let stoppedSnapshot = makeRunEvidenceSnapshot(
            completion: nil,
            bindingOverride: stoppedBinding,
            processStateOverride: "Stopped by you",
            nextActionOverride: continuationDecision.nextAction
        )
        runEvidenceSnapshot = stoppedSnapshot
        attachTaskCheckpoint(to: stoppedAssistantID, snapshot: stoppedSnapshot)
        notifyMessagesChanged()
    }

    /// Synchronous UI/notification entry point for the serialized async stop.
    /// Keeping the Task boundary here avoids making every SwiftUI notification
    /// modifier carry an async closure.
    func requestStop() {
        Task { await stop() }
    }

    func shutdown() async {
        pendingSubmitIntent = nil
        firstChunkInterval?.end()
        firstChunkInterval = nil
        cancelLeftoverWarmStart()
        cancelStreamingTextFlush()
        invalidateTurnSettlement()
        connectionWatchdogTask?.cancel()
        stopStallWatchdog()
        isStreaming = false
        isGrokking = false
        streamingMessageID = nil
        await process.stop()
        mcpServerStatuses = MCPReadinessPolicy.stoppedStatuses(for: mcpServerStatuses.map(\.name))
        connectionState = .idle
    }

    /// LRU teardown may stop a mismatched process for safety, but it can adopt only
    /// a receipt whose local tab, backend, and active generation match this store.
    func shutdownForLRUEviction(
        expectedTabID: UUID,
        persistedBackendID: String?
    ) async -> SessionProcessLRUDecision {
        let durablePersistedID = savedGrokSessionID ?? persistedBackendID
        let decision = SessionProcessLRUPolicy.decision(
            expectedTabID: expectedTabID,
            persistedBackendID: durablePersistedID,
            activeProcessGeneration: process.activeProcessGeneration,
            launchReceipt: process.launchReceipt
        )
        await shutdown()
        return decision
    }

    /// Terminal variant of `shutdown()` for a closed tab or app quit: also ends the
    /// process's ACP event stream, which terminates `consumeOutput()` and lets the
    /// store/process pair deallocate. A store must not reconnect after this.
    func shutdownPermanently() async {
        isPermanentlyShutdown = true
        pendingSubmitIntent = nil
        firstChunkInterval?.end()
        firstChunkInterval = nil
        cancelLeftoverWarmStart()
        cancelStreamingTextFlush()
        invalidateTurnSettlement()
        connectionWatchdogTask?.cancel()
        stopStallWatchdog()
        isStreaming = false
        isGrokking = false
        streamingMessageID = nil
        await process.shutdown()
        mcpServerStatuses = MCPReadinessPolicy.stoppedStatuses(for: mcpServerStatuses.map(\.name))
        connectionState = .idle
    }

    func respondToExitPlan(_ request: ExitPlanRequest, verdict: ExitPlanRequest.PlanVerdict) {
        guard let pendingExitPlan,
              ACPInteractionRequestIdentity.matches(
                lhsID: pendingExitPlan.id,
                lhsSessionID: pendingExitPlan.sessionId,
                rhsID: request.id,
                rhsSessionID: request.sessionId
              ),
              ACPInteractionRequestIdentity.ownsActiveSession(
                request.sessionId,
                activeSessionID: process.sessionId
              ) else { return }
        process.respondToExitPlan(request.id.base, verdict: verdict)
        self.pendingExitPlan = nil
    }

    func respondToQuestion(_ request: QuestionRequest, answers: [String: String]) {
        guard pendingQuestions.contains(where: {
            ACPInteractionRequestIdentity.matches(
                lhsID: $0.id,
                lhsSessionID: $0.sessionId,
                rhsID: request.id,
                rhsSessionID: request.sessionId
            )
        }), ACPInteractionRequestIdentity.ownsActiveSession(
            request.sessionId,
            activeSessionID: process.sessionId
        ) else { return }
        process.respondToQuestion(request.id.base, answers: answers)
        pendingQuestions.removeAll {
            ACPInteractionRequestIdentity.matches(
                lhsID: $0.id,
                lhsSessionID: $0.sessionId,
                rhsID: request.id,
                rhsSessionID: request.sessionId
            )
        }
    }

    func cancelQuestion(_ request: QuestionRequest) {
        guard pendingQuestions.contains(where: {
            ACPInteractionRequestIdentity.matches(
                lhsID: $0.id,
                lhsSessionID: $0.sessionId,
                rhsID: request.id,
                rhsSessionID: request.sessionId
            )
        }), ACPInteractionRequestIdentity.ownsActiveSession(
            request.sessionId,
            activeSessionID: process.sessionId
        ) else { return }
        process.respondToQuestionCancelled(request.id.base)
        pendingQuestions.removeAll {
            ACPInteractionRequestIdentity.matches(
                lhsID: $0.id,
                lhsSessionID: $0.sessionId,
                rhsID: request.id,
                rhsSessionID: request.sessionId
            )
        }
    }

    func addFileAttachment(path: String) {
        guard !isPreparingSubmit else { return }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !fileAttachments.contains(where: { $0.path == standardized }) else { return }
        fileAttachments.append(FileAttachment(path: standardized, workspaceRoot: currentWorkspace?.path))
    }

    func removeFileAttachment(id: UUID) {
        guard !isPreparingSubmit else { return }
        fileAttachments.removeAll { $0.id == id }
    }

    func toggleFileAttachmentHidden(id: UUID) {
        guard !isPreparingSubmit else { return }
        guard let idx = fileAttachments.firstIndex(where: { $0.id == id }) else { return }
        fileAttachments[idx].isHidden.toggle()
    }

    var hasVisibleFileAttachments: Bool {
        fileAttachments.contains { !$0.isHidden }
    }

    var selectedPromptMCPOptions: [PromptMCPOption] {
        promptMCPOptions.filter { selectedPromptMCPNames.contains($0.name) }
    }

    var attachablePromptMCPOptions: [PromptMCPOption] {
        promptMCPOptions.filter { BuiltInToolConnection(rawValue: $0.name) == nil }
    }

    func isBuiltInToolEnabled(_ connection: BuiltInToolConnection) -> Bool {
        enabledBuiltInToolNames.contains(connection.rawValue)
    }

    /// Returns whether the explicit toggle must reconnect this tab to change the
    /// immutable MCP set supplied at ACP `session/new`.
    @discardableResult
    func toggleBuiltInTool(_ connection: BuiltInToolConnection) -> Bool {
        guard !isPreparingSubmit else { return false }
        if enabledBuiltInToolNames.contains(connection.rawValue) {
            enabledBuiltInToolNames.remove(connection.rawValue)
        } else {
            enabledBuiltInToolNames.insert(connection.rawValue)
        }
        selectedPromptMCPNames.remove(connection.rawValue)
        return connectionState != .idle
    }

    func refreshPromptMCPOptions(force: Bool = false) async {
        let workspaceID = currentWorkspace?.id
        if force || loadedPromptMCPWorkspaceID != workspaceID {
            promptMCPInventoryIsLoading = true
            defer { promptMCPInventoryIsLoading = false }
            do {
                let inventory = try await GrokCLIService().listMCPServers(cwd: currentWorkspace?.path)
                configuredPromptMCPOptions = inventory
                    .filter { $0.isEnabled != false }
                    .map { server in
                        let source = switch server.source.lowercased() {
                        case "project": "Project connection"
                        case "user": "User connection"
                        default: "Connected MCP"
                        }
                        let transport = server.transport.trimmingCharacters(in: .whitespacesAndNewlines)
                        let detail = transport.isEmpty ? source : "\(source) · \(transport.uppercased())"
                        return PromptMCPOption(
                            name: server.name,
                            detail: "\(detail) · Configured; process readiness not checked",
                            isReady: false
                        )
                    }
                PromptMCPInventoryCatalog.record(configuredPromptMCPOptions)
                loadedPromptMCPWorkspaceID = workspaceID
                promptMCPInventoryUnavailable = false
            } catch {
                promptMCPInventoryUnavailable = configuredPromptMCPOptions.isEmpty
            }
        }

        var merged: [String: PromptMCPOption] = [:]
        for option in configuredPromptMCPOptions {
            merged[option.name] = option
        }
        for status in mcpServerStatuses {
            guard status.state != .disabled else { continue }
            merged[status.name] = PromptMCPOption(
                name: status.name,
                detail: "Live app connection · \(status.state.displayName)",
                isReady: status.state == .ready
            )
        }
        promptMCPOptions = merged.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let availableNames = Set(promptMCPOptions.map(\.name))
        selectedPromptMCPNames.formIntersection(availableNames)
    }

    func togglePromptMCPAttachment(named name: String) {
        guard !isPreparingSubmit else { return }
        guard promptMCPOptions.contains(where: { $0.name == name }) else { return }
        if let builtIn = BuiltInToolConnection(rawValue: name) {
            _ = toggleBuiltInTool(builtIn)
            return
        }
        if selectedPromptMCPNames.contains(name) {
            selectedPromptMCPNames.remove(name)
        } else {
            selectedPromptMCPNames.insert(name)
        }
    }

    func removePromptMCPAttachment(named name: String) {
        guard !isPreparingSubmit else { return }
        selectedPromptMCPNames.remove(name)
    }

    func respondToPermission(_ request: PermissionRequest, with optionId: String) {
        guard pendingPermissions.contains(where: {
            ACPInteractionRequestIdentity.matches(
                lhsID: $0.id,
                lhsSessionID: $0.sessionId,
                rhsID: request.id,
                rhsSessionID: request.sessionId
            )
        }), ACPInteractionRequestIdentity.ownsActiveSession(
            request.sessionId,
            activeSessionID: process.sessionId
        ) else { return }
        answerPermissionRequest(request, with: optionId)
    }

    private func answerPermissionRequest(_ request: PermissionRequest, with optionId: String) {
        // Permission is an ACP decision only. The CLI remains the sole executor so its
        // sandbox, deny rules, and hooks cannot be bypassed by a client-side file write.
        process.respondToPermission(request, with: optionId)
        pendingPermissions.removeAll {
            ACPInteractionRequestIdentity.matches(
                lhsID: $0.id,
                lhsSessionID: $0.sessionId,
                rhsID: request.id,
                rhsSessionID: request.sessionId
            )
        }
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
        pendingPermissions.removeAll {
            ACPInteractionRequestIdentity.matches(
                lhsID: $0.id,
                lhsSessionID: $0.sessionId,
                rhsID: request.id,
                rhsSessionID: request.sessionId
            )
        }
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
            terminalStatus: allowed ? .succeeded : .failed,
            detail: allowed
                ? "Allowed automatically by the live \(mode.displayName) policy."
                : "Denied automatically by the live \(mode.displayName) policy.",
            diagnosticDetail: request.toolCall.diagnosticDetail,
            target: request.toolCall.target,
            mcpServerName: mcpServerName(from: request.toolCall),
            retryOfToolCallID: request.toolCall.retryOfToolCallID,
            recoveredByToolCallID: nil
        )
        if let index = liveToolCalls.firstIndex(where: { $0.id == receipt.id }) {
            liveToolCalls[index] = receipt
        } else {
            liveToolCalls.append(receipt)
        }
    }

    func setMode(_ mode: AgentMode) {
        guard !isPreparingSubmit else { return }
        guard availableModes.contains(mode) else { return }
        process.setMode(mode)
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
        guard !isPreparingSubmit else { return }
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
        guard !isPreparingSubmit else { return }
        guard availableModels.contains(model) else { return }
        if model == currentModel {
            guard !tabHasExplicitModel else { return }
            tabHasExplicitModel = true
            tabModelIntent = .explicit(model)
            if process.activeProcessGeneration == nil {
                modelExecutionState = .savedIntent(modelID: model)
            }
            saveCurrentSessionSelection()
            notifyModelChanged()
            return
        }
        switch Self.modelSwitchSafetyBlock(
            isStreaming: isStreaming,
            hasProviderSpecificHistory: hasProviderSpecificHistory
        ) {
        case .activeTurn:
            modelSwitchError = "Wait for the current response to finish before changing models."
            modelSwitchNeedsNewSession = false
            pendingModelForNewSession = nil
            return
        case .providerHistory:
            modelSwitchError = "This session contains model-specific response history that is not replay-safe across models. Start a new session to change models."
            modelSwitchNeedsNewSession = true
            pendingModelForNewSession = model
            return
        case nil:
            break
        }
        let previous = currentModel
        let previousIntent = persistedModelIntent
        currentModel = model
        modelSwitchError = nil
        modelSwitchNeedsNewSession = false
        pendingModelForNewSession = nil
        process.modelSwitchError = nil
        process.modelSwitchNeedsNewSession = false
        tabHasExplicitModel = true
        tabModelIntent = .explicit(model)
        let expectedEffectiveModelID = customModelsByID[model]?.model
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = process.setModel(
            model,
            expectedEffectiveModelID: expectedEffectiveModelID?.isEmpty == false
                ? expectedEffectiveModelID
                : nil
        )
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
                    self.currentModel = self.selectionModelID(
                        requested: model,
                        effective: effective
                    )
                    self.routeContractsByProcessGeneration[identity.processGeneration] = ModelRouteContract.resolve(
                        selectedModelID: model,
                        customModel: self.customModelsByID[model]
                    )
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
                self.pendingModelForNewSession = self.modelSwitchNeedsNewSession ? model : nil
                if case .failed = self.process.state {
                    self.connectionState = self.process.state
                }
            case .unknown, .pending:
                break
            }
            self.saveCurrentSessionSelection()
            self.notifyModelChanged()
        }
    }

    func dismissModelSwitchIssue() {
        modelSwitchError = nil
        modelSwitchNeedsNewSession = false
        pendingModelForNewSession = nil
    }

    func resolveModelSwitchByStartingNewSession() async {
        guard modelSwitchNeedsNewSession,
              let model = Self.recoverableModelForNewSession(
                  pendingModelForNewSession,
                  availableModels: availableModels
              ) else {
            dismissModelSwitchIssue()
            return
        }
        currentModel = model
        tabHasExplicitModel = true
        tabModelIntent = .explicit(model)
        dismissModelSwitchIssue()
        saveCurrentSessionSelection()
        notifyModelChanged()
        await startNewSession(resetThreadTools: true)
    }

    var isModelRequestPending: Bool { modelExecutionState.status == .pending }

    enum ModelSwitchSafetyBlock: Equatable {
        case activeTurn
        case providerHistory
    }

    nonisolated static func modelSwitchSafetyBlock(
        isStreaming: Bool,
        hasProviderSpecificHistory: Bool
    ) -> ModelSwitchSafetyBlock? {
        if isStreaming { return .activeTurn }
        if hasProviderSpecificHistory { return .providerHistory }
        return nil
    }

    nonisolated static func recoverableModelForNewSession(
        _ requestedModel: String?,
        availableModels: [String]
    ) -> String? {
        guard let requestedModel, availableModels.contains(requestedModel) else { return nil }
        return requestedModel
    }

    private var hasProviderSpecificHistory: Bool {
        Self.hasProviderSpecificHistory(in: messages)
    }

    nonisolated static func hasProviderSpecificHistory(in messages: [Message]) -> Bool {
        messages.contains { $0.role == .assistant }
    }

    nonisolated static func mcpGatewayEnabled(
        selectedPromptMCPNames: Set<String>,
        enabledBuiltInToolNames: Set<String>
    ) -> Bool {
        !selectedPromptMCPNames.isEmpty || !enabledBuiltInToolNames.isEmpty
    }

    private var modelReceiptIsCurrentProcess: Bool {
        guard let identity = modelExecutionState.identity,
              let generation = process.activeProcessGeneration else { return false }
        return identity.processGeneration == generation
            && identity.localTabID == tabSessionID
            && identity.backendSessionID == process.sessionId
    }

    var modelSelectorStatusLabel: String {
        Self.modelSelectorStatusLabel(
            status: modelExecutionState.status,
            receiptIsCurrentProcess: modelReceiptIsCurrentProcess,
            currentModel: currentModel,
            effectiveModelID: modelExecutionState.effectiveModelID,
            requestedModelID: modelExecutionState.requestedModelID,
            providerFacingRequestedModel: modelExecutionState.requestedModelID.flatMap {
                customModelsByID[$0]?.model
            },
            requestHasIdentity: modelExecutionState.identity != nil,
            followsInheritedDefault: {
                if case .inheritProjectDefault = tabModelIntent { return true }
                return false
            }(),
            isConnecting: connectionState == .starting
        )
    }

    /// Last live/Live may only name the picker when it still matches the confirmed receipt.
    /// Inherited tabs that followed a newer CLI/project default keep that selection, but they
    /// do not inherit the previous turn's Last live badge.
    nonisolated static func currentModelMatchesConfirmedReceipt(
        currentModel: String,
        effectiveModelID: String?,
        requestedModelID: String?,
        providerFacingRequestedModel: String?
    ) -> Bool {
        let current = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return false }
        let effective = effectiveModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requested = requestedModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let provider = providerFacingRequestedModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if current == effective || current == requested { return true }
        return !requested.isEmpty
            && current == requested
            && !provider.isEmpty
            && effective == provider
    }

    nonisolated static func modelSelectorStatusLabel(
        status: ModelExecutionStatus,
        receiptIsCurrentProcess: Bool,
        currentModel: String,
        effectiveModelID: String?,
        requestedModelID: String?,
        providerFacingRequestedModel: String?,
        requestHasIdentity: Bool,
        followsInheritedDefault: Bool,
        isConnecting: Bool = false
    ) -> String {
        if isConnecting {
            switch status {
            case .confirmed:
                break
            case .rejected:
                return "Rejected"
            case .unknown, .requested, .pending:
                return "Connecting"
            }
        }
        switch status {
        case .confirmed:
            let matchesReceipt = currentModelMatchesConfirmedReceipt(
                currentModel: currentModel,
                effectiveModelID: effectiveModelID,
                requestedModelID: requestedModelID,
                providerFacingRequestedModel: providerFacingRequestedModel
            )
            if matchesReceipt {
                return receiptIsCurrentProcess ? "Live" : "Last live"
            }
            return followsInheritedDefault ? "Default" : "Saved"
        case .pending:
            return receiptIsCurrentProcess ? "Pending" : "Stale"
        case .requested:
            return requestHasIdentity ? "Requested" : "Saved"
        case .rejected:
            return "Rejected"
        case .unknown:
            if followsInheritedDefault,
               !currentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Default"
            }
            return "Unknown"
        }
    }

    var modelSelectorDisplayLabel: String {
        "\(modelDisplayName(currentModel)) · \(modelSelectorStatusLabel)"
    }

    var modelAccessibilityValue: String {
        if connectionState == .starting, modelExecutionState.status != .confirmed, modelExecutionState.status != .rejected {
            let name = modelDisplayName(currentModel)
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Connecting; live model not confirmed yet."
            }
            return "Connecting to \(name); live model not confirmed yet."
        }
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
            if case .inheritProjectDefault = tabModelIntent,
               !currentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Inherited default \(modelDisplayName(currentModel)); no live process confirmation yet."
            }
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
            if connectionState == .starting {
                return "Connecting"
            }
            return process.activeProcessGeneration == nil ? "No active process" : "Model unknown"
        }
    }

    var currentRouteContract: ModelRouteContract {
        ModelRouteContract.resolve(
            selectedModelID: currentModel,
            customModel: customModelsByID[currentModel]
        )
    }

    var currentRouteCompactLabel: String { currentRouteContract.compactLabel }
    var currentRouteSystemImage: String { currentRouteContract.systemImage }
    var currentRouteAccessibilityValue: String { currentRouteContract.accessibilityValue }

    var sessionReceiptDetailLines: [String] {
        var lines = [
            modelAccessibilityValue,
            "Continuity: \(continuityHeadline). \(continuityDetails)",
        ]
        guard let receipt = process.launchReceipt else {
            lines.append(contentsOf: currentRouteContract.detailLines)
            lines.append("No process launch receipt for this tab.")
            return lines
        }
        let pid = receipt.processIdentifier.map(String.init) ?? "unavailable"
        lines.append("Process generation \(receipt.processGeneration), PID \(pid), \(receipt.outcome.rawValue).")
        lines.append("Tab \(Self.shortReceiptID(receipt.localTabID?.uuidString)); backend \(Self.shortReceiptID(receipt.backendSessionID)).")
        lines.append("Launch requested model: \(receipt.requestedModelID.map(modelDisplayName) ?? "CLI default").")
        let routeContract = routeContractsByProcessGeneration[receipt.processGeneration]
            ?? currentRouteContract
        lines.append(contentsOf: routeContract.detailLines)
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
        lines.append(receipt.mcpGatewayEnabled
            ? "MCP gateway: exact thread selection active; Grok CLI denies every freshly observed configured server outside the selected set."
            : "MCP gateway: external tool invocation blocked by the session-scoped CLI deny rule MCPTool(*__*) plus fail-closed ACP permission responses.")
        lines.append("ACP-authorized MCP servers: \(receipt.allowedMCPServerNames.isEmpty ? "none" : receipt.allowedMCPServerNames.joined(separator: ", ")).")
        lines.append("App-injected MCP servers: \(receipt.mcpServerNames.isEmpty ? "none" : receipt.mcpServerNames.joined(separator: ", ")).")
        if !receipt.observedCLIConfiguredMCPServerNames.isEmpty {
            lines.append("CLI-configured MCP servers observed: \(receipt.observedCLIConfiguredMCPServerNames.joined(separator: ", ")).")
        }
        return lines
    }

    private static func shortReceiptID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        return value.count > 8 ? "…\(value.suffix(8))" : value
    }

    func modelDisplayName(_ id: String) -> String {
        modelDisplayNames[id] ?? id
    }

    /// Grok selects custom models by their TOML table key but reports the
    /// provider-facing `model` value after ACP confirmation. Keep the picker on
    /// the table key while preserving the provider readback in the execution
    /// receipt.
    private func selectionModelID(requested: String?, effective: String) -> String {
        guard let requested,
              let custom = customModelsByID[requested] else { return effective }
        let providerModel = custom.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return effective == requested || (!providerModel.isEmpty && effective == providerModel)
            ? requested
            : effective
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
                    options: perm.options,
                    mcpGatewayEnabled: process.launchReceipt?.mcpGatewayEnabled == true,
                    isMCPInvocation: perm.toolCall.qualifiedToolName != nil,
                    invocationServerName: MCPQualifiedToolIdentity.serverName(
                        from: perm.toolCall.qualifiedToolName
                    ),
                    allowedMCPServerNames: Set(process.launchReceipt?.allowedMCPServerNames ?? [])
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

    // MARK: Git review snapshot model

    struct DetectedDiff: Identifiable, Hashable {
        let id = UUID()
        let raw: String
        let filePath: String?
        var gitStatus: String? = nil
        var originalFilePath: String? = nil
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
            appendAssistantText(TranscriptTextPresentation.normalize(text))
        case .thoughtChunk(let text):
            isGrokking = false
            if thinkingStartedAt == nil { thinkingStartedAt = Date() }
            let publicSummary = TranscriptTextPresentation.normalize(text)
            if !publicSummary.isEmpty {
                reasoningSummaryChunks.append(publicSummary)
            }
            streamRevision &+= 1
        case .toolCall(let tc):
            flushAllPendingAssistantText()
            isGrokking = false
            recordCurrentTurnToolPlanStep(tc.id)
            if !liveToolCalls.contains(where: { $0.id == tc.id }) {
                liveToolCalls.append(liveToolCall(from: tc))
            }
            observeArtifactReceipt(tc)
        case .toolCallUpdate(let tc):
            recordCurrentTurnToolPlanStep(tc.id)
            if let idx = liveToolCalls.firstIndex(where: { $0.id == tc.id }) {
                liveToolCalls[idx] = mergedToolCall(existing: liveToolCalls[idx], update: tc)
            } else {
                liveToolCalls.append(liveToolCall(from: tc))
            }
            observeArtifactReceipt(tc)
        case .subagentSpawned(let event):
            guard ownsActiveLifecycleEvent(event.identity),
                  seenSubagentLifecycleKeys.insert(event.deduplicationKey).inserted else { break }
            subagentSpawnedEvents.append(event)
            let previousActivities = backgroundTaskTracker.activities
            backgroundTaskTracker.apply(spawned: event)
            backgroundActivities = backgroundTaskTracker.activities
            recordCurrentTurnWorkerChanges(since: previousActivities)
        case .subagentFinished(let event):
            guard ownsActiveLifecycleEvent(event.identity),
                  seenSubagentLifecycleKeys.insert(event.deduplicationKey).inserted else { break }
            subagentFinishedEvents.append(event)
            let previousActivities = backgroundTaskTracker.activities
            backgroundTaskTracker.apply(finished: event)
            backgroundActivities = backgroundTaskTracker.activities
            recordCurrentTurnWorkerChanges(since: previousActivities)
        case .plan(let payload):
            currentRunPlan = Self.applyingPlanUpdate(payload, to: currentRunPlan)
        case .planFileContent(let content):
            if !content.isEmpty, var plan = pendingExitPlan {
                plan.planText = content
                pendingExitPlan = plan
            }
        case .exitPlanRequest(let req):
            guard ACPInteractionRequestIdentity.ownsActiveSession(
                req.sessionId,
                activeSessionID: process.sessionId
            ) else { break }
            pendingExitPlan = ExitPlanRequest.merging(req, into: pendingExitPlan)
        case .questionRequest(let req):
            guard ACPInteractionRequestIdentity.ownsActiveSession(
                req.sessionId,
                activeSessionID: process.sessionId
            ) else { break }
            pendingQuestions = QuestionRequest.merging(req, into: pendingQuestions)
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
            let previousActivities = backgroundTaskTracker.activities
            backgroundTaskTracker.apply(update: payload)
            backgroundActivities = backgroundTaskTracker.activities
            recordCurrentTurnWorkerChanges(since: previousActivities)
            scheduledTasks = backgroundTaskTracker.activities.compactMap(\.scheduledTask)
        case .turnCompleted(let completion):
            guard ownsActiveCompletionEvent(completion.identity) else {
                process.rejectTurnCompletionBridge(
                    reason: completionOwnershipFailureReason(for: completion.identity)
                )
                break
            }
            // One active provider turn has exactly one terminal authority. Grok can
            // repeat the same notification while a large final text chunk is still
            // draining; replaying settlement would double usage, checkpoints, and
            // worker finalization even though no second provider turn occurred.
            guard !activeTurnCompletionConsumed else { break }
            if let key = completion.deduplicationKey {
                guard consumedTurnCompletionKeys.insert(key).inserted else { break }
            }
            activeTurnCompletionConsumed = true
            // This event shares the same AsyncStream queue as text/tool updates. By
            // acknowledging only here, `process.send` cannot outrun already-yielded
            // synthesis chunks and detach them from their assistant message. Keep
            // those accepted chunks in the display buffer: reconciliation after the
            // paced reveal verifies the same backend tail without replacing the
            // growing answer with one instantaneous full-message snap.
            pendingCompletionReconciliation = true
            reconcileCompletedTurnIfDisplayBufferIsSettled()
            refreshBoundContinuityCountsAfterSettlement()
            // The event queue is ordered: all worker receipts yielded before this
            // barrier have already crossed ChatStore. Any worker still active here
            // is explicitly unresolved, never successful by implication from the
            // parent answer.
            reconcileCurrentTurnChildToolReceipts()
            backgroundTaskTracker.markUnsettledSubagents(only: currentTurnWorkerActivityIDs)
            backgroundActivities = backgroundTaskTracker.activities
            settleToolCallsAtTurnBarrier()
            attachCurrentTurnTrace(to: streamingMessageID)
            let turnSucceeded = completion.isSuccessful
            latestTurnOutcome = if turnSucceeded {
                .completed
            } else if completion.isCancelled {
                .cancelled
            } else {
                .failed
            }
            if latestTurnOutcome == .failed {
                lastError = completion.redactedError ?? "Grok reported that this turn ended with an error."
            }
            // Slice 6: the authoritative completion receipt is the only usage source.
            sessionUsage.recordTurn(
                modelID: modelExecutionState.effectiveModelID ?? currentModel,
                totalTokens: completion.totalTokens,
                modelCalls: completion.modelCalls,
                costUsdTicks: completion.costUsdTicks,
                modelUsage: completion.modelUsage
            )
            let settledSnapshot = makeRunEvidenceSnapshot(completion: completion)
            runEvidenceSnapshot = settledSnapshot
            attachTaskCheckpoint(to: streamingMessageID, snapshot: settledSnapshot)
            // turn_completed is the lifecycle authority. Observed live 2026-08-03
            // (gpt-5.6-terra): the usage receipt settled while the prompt's JSON-RPC
            // response never resolved, leaving a stuck Stop button on a finished turn.
            // With the display buffer drained and no deferred completion pending, the
            // turn must finish now; a late response is a no-op via finishPromptNow's
            // idempotence guard.
            if isStreaming,
               deferredPromptCompletion == nil,
               streamingTextBuffer.isEmpty,
               let stuckAssistantID = streamingMessageID ?? closedTurnAssistantID {
                finishPromptNow(assistantID: stuckAssistantID, ok: turnSucceeded)
            }
            requestGitRefresh()
            process.acknowledgeTurnCompletionBridge(authoritative: true)
            applyTurnSettlementDecision(turnSettlement.recordCompletionConsumed(ok: turnSucceeded))
        case .turnCompletionReceiptMissing(let failure):
            guard ownsActiveCompletionEvent(failure.identity) else { break }
            // The watchdog is a failure boundary, never a synthetic completion.
            // Preserve every already-observed receipt, reconcile the backend tail
            // read-only, and make unresolved state explicit without claiming usage,
            // worker success, or settled continuity.
            flushAllPendingAssistantText()
            reconcileActiveTurnFromBackend()
            backgroundTaskTracker.markUnsettledSubagents(only: currentTurnWorkerActivityIDs)
            backgroundActivities = backgroundTaskTracker.activities
            settleToolCallsAtTurnBarrier()
            attachCurrentTurnTrace(to: streamingMessageID)
            latestTurnOutcome = .completionReceiptMissing
            lastError = failure.reason
            let incompleteSnapshot = makeRunEvidenceSnapshot(completion: TurnCompletionReceipt(
                identity: failure.identity,
                promptID: nil,
                stopReason: nil,
                redactedError: nil,
                totalTokens: nil,
                modelCalls: nil,
                turnCount: nil
            ))
            runEvidenceSnapshot = incompleteSnapshot
            attachTaskCheckpoint(to: streamingMessageID, snapshot: incompleteSnapshot)
            requestGitRefresh()
            process.acknowledgeTurnCompletionBridge(authoritative: false)
        case .permissionRequest(let req):
            guard ACPInteractionRequestIdentity.ownsActiveSession(
                req.sessionId,
                activeSessionID: process.sessionId
            ) else { break }
            let liveMode = effectivePermissionMode
            switch PermissionRequestPolicy.disposition(
                mode: liveMode,
                isYolo: isYolo,
                options: req.options,
                mcpGatewayEnabled: process.launchReceipt?.mcpGatewayEnabled == true,
                isMCPInvocation: req.toolCall.qualifiedToolName != nil,
                invocationServerName: MCPQualifiedToolIdentity.serverName(
                    from: req.toolCall.qualifiedToolName
                ),
                allowedMCPServerNames: Set(process.launchReceipt?.allowedMCPServerNames ?? [])
            ) {
            case .allow(let optionID):
                answerPermissionRequest(req, with: optionID)
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
            isYolo = (mode == .yolo)
            availableModes = process.availableModes
            saveCurrentSessionSelection()
        case .contextUsage(let totalTokens):
            usedContextTokens = totalTokens

        case .rawLine:
            // Plain stdout is not an assistant message. Grok can write child
            // worker/progress chatter there while structured ACP updates for the
            // parent session are still arriving. Rendering it as prose produced
            // the interleaved, unreadable transcript seen during multi-agent runs.
            break
        case .error(let msg):
            lastError = msg
        }
    }

    private func reconcileCurrentTurnChildToolReceipts() {
        let candidates = backgroundTaskTracker.activities.filter { activity in
            guard activity.kind == .subagent,
                  currentTurnWorkerActivityIDs.contains(activity.id),
                  let childID = activity.childID,
                  !childID.isEmpty else { return false }
            return activity.childToolReceipts?.count != (activity.toolCallCount ?? 0)
        }
        for activity in candidates {
            guard let childID = activity.childID else { continue }
            backgroundTaskTracker.reconcileChildToolReceipts(
                childID: childID,
                receipts: process.loadChildToolReceipts(childID: childID)
            )
        }
        backgroundActivities = backgroundTaskTracker.activities
    }

    private func ownsActiveLifecycleEvent(_ identity: ACPEventIdentity) -> Bool {
        SubagentLifecycleEventPolicy.ownsActiveSession(
            identity,
            localTabID: tabSessionID,
            backendSessionID: process.sessionId,
            processGeneration: process.activeProcessGeneration
        )
    }

    private func recordCurrentTurnWorkerChanges(since previous: [BackgroundActivity]) {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for activity in backgroundTaskTracker.activities where activity.kind == .subagent {
            if previousByID[activity.id] != activity {
                currentTurnWorkerActivityIDs.insert(activity.id)
                if currentTurnWorkerPlanStepIDs[activity.id] == nil,
                   let stepID = currentRunPlan.first(where: \.isCurrent)?.id {
                    currentTurnWorkerPlanStepIDs[activity.id] = stepID
                }
            }
        }
    }

    private func ownsActiveCompletionEvent(_ identity: ACPEventIdentity) -> Bool {
        guard isStreaming,
              activeTurnBackendSessionID == identity.backendSessionID else { return false }
        return SubagentLifecycleEventPolicy.ownsActiveSession(
            identity,
            localTabID: tabSessionID,
            backendSessionID: process.sessionId,
            processGeneration: process.activeProcessGeneration
        )
    }

    private func completionOwnershipFailureReason(for identity: ACPEventIdentity) -> String {
        var mismatches: [String] = []
        if !isStreaming { mismatches.append("no active streaming turn") }
        if activeTurnBackendSessionID != identity.backendSessionID {
            mismatches.append("turn backend")
        }
        if identity.localTabID != tabSessionID { mismatches.append("local tab") }
        if identity.backendSessionID != process.sessionId { mismatches.append("live backend") }
        if identity.processGeneration != process.activeProcessGeneration {
            mismatches.append("process generation")
        }
        let detail = mismatches.isEmpty ? "unknown ownership mismatch" : mismatches.joined(separator: ", ")
        return "ACP turn_completed was rejected at the ChatStore ownership boundary: \(detail)."
    }

    private func liveToolCall(from toolCall: ToolCall) -> LiveToolCall {
        LiveToolCall(
            id: toolCall.id,
            title: displayTitle(for: toolCall),
            kind: displayKind(for: toolCall),
            status: toolCall.status,
            terminalStatus: toolCall.terminalStatus,
            detail: toolCall.detail,
            diagnosticDetail: toolCall.diagnosticDetail,
            target: toolCall.target,
            mcpServerName: mcpServerName(from: toolCall),
            mcpReceiptRole: toolCall.mcpReceiptRole,
            qualifiedToolName: toolCall.qualifiedToolName,
            discoveredQualifiedToolNames: toolCall.discoveredQualifiedToolNames,
            retryOfToolCallID: toolCall.retryOfToolCallID,
            recoveredByToolCallID: nil,
            durationMilliseconds: toolCall.durationMilliseconds
        )
    }

    private func observeArtifactReceipt(_ toolCall: ToolCall) {
        if let path = normalizedArtifactPath(toolCall.writtenFilePath) {
            pendingArtifactPathsByToolCallID[toolCall.id] = path
        }

        guard isSuccessfulToolStatus(toolCall.status),
              let path = pendingArtifactPathsByToolCallID.removeValue(forKey: toolCall.id) else {
            return
        }

        let artifact = RunArtifact(
            toolCallID: toolCall.id,
            path: path,
            status: "Completed",
            location: artifactLocation(for: path),
            owningPlanStepID: currentTurnToolPlanStepIDs[toolCall.id],
            workerID: nil
        )
        if let index = runArtifacts.firstIndex(where: { $0.path == artifact.path }) {
            runArtifacts[index] = artifact
        } else {
            runArtifacts.append(artifact)
        }
        requestGitRefresh()
    }

    private func recordCurrentTurnToolPlanStep(_ toolCallID: String) {
        guard currentTurnToolPlanStepIDs[toolCallID] == nil,
              let stepID = currentRunPlan.first(where: \.isCurrent)?.id else { return }
        currentTurnToolPlanStepIDs[toolCallID] = stepID
    }

    private func normalizedArtifactPath(_ rawPath: String?) -> String? {
        guard let rawPath else { return nil }
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else { return nil }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL.path
        }
        guard let workspace = currentWorkspace?.path else { return trimmed }
        return workspace.appendingPathComponent(trimmed).standardizedFileURL.path
    }

    private func artifactLocation(for path: String) -> RunArtifact.Location {
        guard let workspaceRoot = currentWorkspace?.path.standardizedFileURL.path else {
            return .external
        }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardizedPath == workspaceRoot || standardizedPath.hasPrefix(workspaceRoot + "/")
            ? .workspace
            : .external
    }

    private func isSuccessfulToolStatus(_ status: String?) -> Bool {
        guard let status else { return false }
        return ["completed", "complete", "success", "succeeded"]
            .contains(status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func requestGitRefresh() {
        gitRefreshRevision &+= 1
    }

    /// ContentView owns the bounded `GitService` query. It may attach the
    /// resulting Git authority only to the current snapshot for the same tab,
    /// workspace, backend, and process generation; it cannot create a run or
    /// settle lifecycle state.
    func recordGitReviewFiles(_ paths: [String], workspaceID: UUID) {
        guard let snapshot = runEvidenceSnapshot,
              snapshot.binding.localTabID == tabSessionID,
              snapshot.binding.workspaceID == workspaceID,
              snapshot.binding.backendSessionID == process.sessionId,
              snapshot.binding.processGeneration == process.activeProcessGeneration else { return }
        runEvidenceSnapshot = snapshot.replacingGitReviewFiles(
            ActivitySidebarPresentation.uniqueFilePaths(paths)
        )
    }

    nonisolated static func applyingPlanUpdate(
        _ payload: [String: Any],
        to current: [RunEvidenceSnapshot.PlanStep]
    ) -> [RunEvidenceSnapshot.PlanStep] {
        let rawInput = payload["rawInput"] as? [String: Any]
        let entries = payload["entries"] as? [[String: Any]]
            ?? rawInput?["todos"] as? [[String: Any]]
            ?? []
        let merge = rawInput?["merge"] as? Bool ?? false
        let updates = entries.enumerated().compactMap { index, entry -> (String, String?, String)? in
            let rawTitle = entry["title"] as? String ?? entry["content"] as? String
            let title = rawTitle.map { TranscriptTextPresentation.singleLine($0, maxLength: 240) }
            let rawID = entry["id"] as? String
            let id = rawID?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? title.map { "\(index)|\($0)" }
                ?? ""
            guard !id.isEmpty, title?.isEmpty != true else { return nil }
            return (id, title, entry["status"] as? String ?? "not_reported")
        }
        guard merge else {
            return updates.compactMap { id, title, status in
                guard let title else { return nil }
                return .init(id: id, title: title, status: status)
            }
        }
        var result = current
        for (id, title, status) in updates {
            if let index = result.firstIndex(where: { $0.id == id }) {
                result[index] = .init(
                    id: id,
                    title: title ?? result[index].title,
                    status: status
                )
            } else if let title {
                result.append(.init(id: id, title: title, status: status))
            }
        }
        return result
    }

    private func makeRunEvidenceSnapshot(
        completion: TurnCompletionReceipt?,
        bindingOverride: RunEvidenceSnapshot.Binding? = nil,
        processStateOverride: String? = nil,
        nextActionOverride: String? = nil
    ) -> RunEvidenceSnapshot {
        let workers = currentTurnEvidenceWorkers()
        let parentTools = parentLiveToolCalls()
        let toolSummary = RunEvidenceSnapshot.ToolSummary(
            succeeded: parentTools.filter { $0.terminalStatus == .succeeded }.count,
            failed: parentTools.filter { $0.terminalStatus == .failed }.count,
            cancelled: parentTools.filter { $0.terminalStatus == .cancelled }.count,
            unknown: parentTools.filter { $0.terminalStatus == .unknown || $0.terminalStatus == nil }.count
        )
        let unresolvedErrors = parentTools.compactMap { tool -> String? in
            guard tool.terminalStatus == .failed, !tool.isRecovered else { return nil }
            return TranscriptTextPresentation.singleLine(tool.detail ?? tool.title, maxLength: 180)
        } + workers.compactMap { $0.redactedError } + workers.flatMap { worker in
            (worker.childToolReceipts ?? []).compactMap { receipt -> String? in
                guard receipt.status != .succeeded else { return nil }
                return "Child tool \(receipt.qualifiedToolName ?? receipt.title) ended \(receipt.status.rawValue)."
            }
        } + [completion?.redactedError].compactMap { $0 }
        let provenance: String = switch continuityStatus {
        case .localOnly: "Local only"
        case .backendBound: "Fresh backend bound"
        case .backendOnly: "Backend only"
        case .verifying: "Verification in progress"
        case .verified: "Verified continuity"
        case .recoveryForked: "Recovery fork"
        case .diverged, .compositeSuspected, .backendMissing, .verificationIncomplete: "Continuity needs review"
        }
        let outcome = latestTurnOutcome ?? .completionReceiptMissing
        // Only `turn_completed` is the parent lifecycle authority. A bridge
        // watchdog can preserve evidence, but it cannot paint the process settled.
        let processState = processStateOverride ?? (outcome == .completed
            ? "Settled"
            : outcome == .failed
                ? "Failed"
                : outcome == .cancelled
                    ? "Cancelled"
                    : outcome == .userStopped
                        ? "Stopped by you"
                        : "Incomplete — completion receipt missing")
        let nextAction: String
        if let nextActionOverride {
            nextAction = nextActionOverride
        } else if outcome == .failed {
            nextAction = "Review the provider or CLI error before retrying."
        } else if outcome == .cancelled {
            nextAction = "Review the cancellation and unresolved tool receipts before retrying."
        } else if outcome == .completionReceiptMissing {
            nextAction = "Reconnect before sending another turn; the backend completion receipt was not reported."
        } else if outcome == .userStopped {
            nextAction = "Reconnect before sending another turn."
        } else if workers.contains(where: \.isActive) {
            nextAction = "Waiting for worker receipts."
        } else if workers.contains(where: \.isUnresolved) {
            nextAction = "Review unresolved worker receipts."
        } else if !unresolvedErrors.isEmpty {
            nextAction = "Review unresolved tool or worker errors."
        } else {
            nextAction = "The agent reported no next action."
        }
        let latestUserMessage = messages.last(where: { $0.role == .user })?.content
        return RunEvidenceSnapshot(
            binding: bindingOverride ?? .init(
                localTabID: tabSessionID,
                workspaceID: currentWorkspace?.id,
                backendSessionID: process.sessionId,
                processGeneration: process.activeProcessGeneration,
                requestID: completion?.promptID,
                isSettled: outcome == .completed || outcome == .failed || outcome == .cancelled
            ),
            goalSummary: goalState?.objective ?? latestUserMessage.map {
                TranscriptTextPresentation.singleLine($0, maxLength: 240)
            },
            plan: currentRunPlan,
            workers: workers,
            coordination: backgroundTaskTracker.coordinationMetrics(
                parentTotalTokens: completion?.totalTokens
            ),
            tools: toolSummary,
            artifacts: runArtifacts,
            gitReviewFiles: [],
            process: .init(
                state: processState,
                model: modelExecutionState.effectiveModelID ?? modelExecutionState.requestedModelID,
                mcps: mcpServerStatuses.map { .init(name: $0.name, state: $0.state.rawValue, reason: $0.reason) }
            ),
            continuity: .init(
                status: continuityStatus.rawValue,
                reason: continuityReceipt.reason.rawValue,
                provenance: provenance,
                requiresRecoveryAction: continuityRequiresRecovery
            ),
            usage: .init(
                totalTokens: completion?.totalTokens,
                modelCalls: completion?.modelCalls,
                turnCount: completion?.turnCount,
                inputTokens: completion?.inputTokens,
                outputTokens: completion?.outputTokens,
                cachedReadTokens: completion?.cachedReadTokens,
                reasoningTokens: completion?.reasoningTokens,
                apiDurationMilliseconds: completion?.apiDurationMilliseconds,
                costUsdTicks: completion?.costUsdTicks,
                modelUsage: completion?.modelUsage ?? []
            ),
            outcome: outcome,
            unresolvedErrors: unresolvedErrors,
            nextAction: nextAction
        )
    }

    private func currentTurnEvidenceWorkers() -> [RunEvidenceSnapshot.Worker] {
        let activityWorkers = backgroundActivities.filter {
            $0.kind == .subagent && currentTurnWorkerActivityIDs.contains($0.id)
        }.map { worker(from: $0) }
        let boundChildIDs = Set(activityWorkers.compactMap(\.childID))
        let unbound = backgroundTaskTracker.unboundSpawnedEvents
            .filter { !boundChildIDs.contains($0.childID) }
            .map { RunEvidenceSnapshot.unboundWorker(from: $0, rolesByName: subagentRoleModelsByName) }
        return activityWorkers + unbound
    }

    private func worker(from activity: BackgroundActivity) -> RunEvidenceSnapshot.Worker {
        RunEvidenceSnapshot.Worker(
            id: activity.id,
            title: activity.title,
            status: activity.status,
            owningPlanStepID: currentTurnWorkerPlanStepIDs[activity.id],
            childID: activity.childID,
            durationMilliseconds: activity.durationMilliseconds,
            toolCallCount: activity.toolCallCount,
            redactedError: activity.redactedError,
            childToolReceipts: activity.childToolReceipts,
            runtimeModelID: activity.runtimeModelID,
            routedModel: SubagentRouting.routedModel(
                forWorkerTitle: activity.title,
                rolesByName: subagentRoleModelsByName
            ),
            childLedgerReadOutcome: activity.childLedgerReadOutcome
        )
    }

    private func refreshBoundContinuityCountsAfterSettlement() {
        guard let backendID = process.sessionId,
              let generation = process.activeProcessGeneration,
              continuityReceipt.reason != .noBackendBinding else { return }
        let backendRelativeMessages = boundForkLedgerEntry?
            .localMessagesForBackendVerification(messages) ?? messages
        let count = SessionTranscriptRecovery.normalizedMessageCount(backendRelativeMessages)
        continuityReceipt = SessionContinuityReceipt(
            status: continuityReceipt.status,
            reason: continuityReceipt.reason,
            normalizationVersion: continuityReceipt.normalizationVersion,
            authenticationSchemaVersion: continuityReceipt.authenticationSchemaVersion,
            localMessageCount: count,
            backendMessageCount: count,
            matchingPrefixCount: count,
            localTranscriptTag: continuityReceipt.localTranscriptTag,
            backendTranscriptTag: continuityReceipt.backendTranscriptTag,
            verifiedAt: Date(),
            localTabID: tabSessionID,
            backendID: backendID,
            processGeneration: generation
        )
        persistedContinuityReceipt = continuityReceipt
    }

    private func mergedToolCall(existing: LiveToolCall, update: ToolCall) -> LiveToolCall {
        let title = isPlaceholderTitle(update.title) ? existing.title : displayTitle(for: update)
        let kind = isPlaceholderKind(update.kind) ? existing.kind : displayKind(for: update)
        return LiveToolCall(
            id: existing.id,
            title: title,
            kind: kind,
            status: update.status ?? existing.status,
            terminalStatus: update.terminalStatus ?? existing.terminalStatus,
            detail: update.detail ?? existing.detail,
            diagnosticDetail: update.diagnosticDetail ?? existing.diagnosticDetail,
            target: update.target ?? existing.target,
            mcpServerName: mcpServerName(from: update) ?? existing.mcpServerName,
            mcpReceiptRole: update.mcpReceiptRole ?? existing.mcpReceiptRole,
            qualifiedToolName: update.qualifiedToolName ?? existing.qualifiedToolName,
            discoveredQualifiedToolNames: Array(Set(
                existing.discoveredQualifiedToolNames + update.discoveredQualifiedToolNames
            )).sorted(),
            retryOfToolCallID: update.retryOfToolCallID ?? existing.retryOfToolCallID,
            recoveredByToolCallID: nil,
            durationMilliseconds: update.durationMilliseconds ?? existing.durationMilliseconds
        )
    }

    private func settleToolCallsAtTurnBarrier() {
        let observedCalls = liveToolCalls
        liveToolCalls = observedCalls.map { $0.settled(against: observedCalls) }
    }

    private func attachCurrentTurnTrace(to messageID: UUID?) {
        guard let messageID,
              let index = messages.firstIndex(where: { $0.id == messageID && $0.role == .assistant }) else {
            return
        }
        let summary = reasoningSummaryChunks
            .map(TranscriptTextPresentation.normalize)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let duration = thinkingDuration ?? thinkingStartedAt.map {
            max(0, Date().timeIntervalSince($0))
        }
        let tools = parentLiveToolCalls().map { tool in
            AssistantTurnTrace.Tool(
                id: tool.id,
                title: TranscriptTextPresentation.singleLine(tool.title, maxLength: 160),
                kind: TranscriptTextPresentation.singleLine(tool.kind, maxLength: 80),
                status: tool.terminalStatus.map { String(describing: $0).capitalized }
                    ?? tool.status.map(ActivitySidebarPresentation.activityStatus)
                    ?? "Status not settled",
                mcpServerName: tool.mcpServerName,
                mcpReceiptRole: tool.mcpReceiptRole,
                qualifiedToolName: tool.qualifiedToolName,
                discoveredQualifiedToolNames: tool.discoveredQualifiedToolNames,
                resultDetail: ToolResultPresentation.transcriptOutput(
                    detail: tool.detail,
                    kind: tool.kind,
                    title: tool.title
                ),
                owningPlanStepID: currentTurnToolPlanStepIDs[tool.id],
                durationMilliseconds: tool.durationMilliseconds
            )
        }
        // Stamp the turn's model identity only from the confirmed execution
        // receipt — the receipts contract forbids naming a model without one.
        let confirmedModelID: String? = modelExecutionState.status == .confirmed
            ? modelExecutionState.effectiveModelID
            : nil
        let trace = AssistantTurnTrace(
            reasoningSummaryChunks: summary,
            thinkingDuration: duration,
            tools: tools,
            modelDisplayName: confirmedModelID.map { modelDisplayName($0) },
            agentName: currentAgent.isEmpty ? nil : currentAgent,
            checkpoint: messages[index].assistantTrace?.checkpoint
        )
        if trace.hasContent {
            messages[index].assistantTrace = trace
        }
    }

    private func attachTaskCheckpoint(
        to messageID: UUID?,
        snapshot: RunEvidenceSnapshot
    ) {
        guard let messageID,
              let index = messages.firstIndex(where: { $0.id == messageID && $0.role == .assistant }) else {
            return
        }
        let checkpoint = AssistantTurnCheckpoint(
            snapshot: snapshot,
            requestedToolFamilies: currentTurnRequestedMCPNames,
            attachmentNames: currentTurnAttachmentNames
        )
        if var trace = messages[index].assistantTrace {
            trace.checkpoint = checkpoint
            messages[index].assistantTrace = trace
        } else {
            messages[index].assistantTrace = AssistantTurnTrace(
                reasoningSummaryChunks: [],
                thinkingDuration: nil,
                tools: [],
                modelDisplayName: nil,
                agentName: nil,
                checkpoint: checkpoint
            )
        }
    }

    /// ACP may mirror a child's tool updates on the parent's live transport even
    /// though those calls are absent from the authoritative parent ledger. Once
    /// exact typed child receipts arrive, keep their IDs inside the worker and out
    /// of the parent's Tools, Sources, and transcript trace.
    private func parentLiveToolCalls() -> [LiveToolCall] {
        let childReceipts = backgroundActivities.compactMap(\.childToolReceipts).flatMap { $0 }
        let parentIDs = Set(Self.parentToolCallIDs(
            observedIDs: liveToolCalls.map(\.id),
            childReceipts: childReceipts
        ))
        return liveToolCalls.filter { parentIDs.contains($0.id) }
    }

    nonisolated static func parentToolCallIDs(
        observedIDs: [String],
        childReceipts: [ChildToolReceipt]
    ) -> [String] {
        let childIDs = Set(childReceipts.map(\.id))
        return observedIDs.filter { !childIDs.contains($0) }
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

    private func mcpServerName(from toolCall: ToolCall) -> String? {
        guard toolCall.mcpReceiptRole != .discovery else { return nil }
        let explicitName = toolCall.rawInput?["serverName"] as? String
            ?? toolCall.rawInput?["server_name"] as? String
        let toolName = toolCall.rawInput?["toolName"] as? String
            ?? toolCall.rawInput?["tool_name"] as? String
            ?? toolCall.rawInput?["name"] as? String
            ?? toolCall.rawInput?["tool"] as? String
            ?? toolCall.title
        let knownNames = Set(promptMCPOptions.map(\.name) + configuredPromptMCPOptions.map(\.name))
        return MCPToolReceiptIdentity.serverName(
            explicitName: explicitName,
            qualifiedToolName: toolName,
            knownServerNames: knownNames
        )
    }

    private func displayKind(for toolCall: ToolCall) -> String {
        if toolCall.mcpReceiptRole == .discovery { return "discovery" }
        if toolCall.mcpReceiptRole == .invocation { return "MCP tool" }
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

        let clean = TranscriptTextPresentation.normalize(text)
            .replacingOccurrences(of: "<<USER>> ", with: "")
        if clean.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(">") &&
           !clean.contains("diff") { return }

        if !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !messages[idx].content.isEmpty {
            if firstChunkInterval != nil {
                GrokBuildPerformance.mark(.firstChunk)
            }
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
                    try await Task.sleep(
                        for: .milliseconds(StreamingTextBuffer.displayCadenceMilliseconds)
                    )
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
            updateStreamingPresentation(messageID: id, appended: batch, fullContent: messages[idx].content)
            streamRevision &+= 1
        }
        return !streamingTextBuffer.isEmpty
    }

    /// Keeps the incremental accumulator bound to the exact streaming message. Any
    /// identity or raw-length desync (content replaced, turn rebound) rebuilds once
    /// from the full content instead of trusting stale incremental state.
    private func updateStreamingPresentation(messageID: UUID, appended: String, fullContent: String) {
        if streamingAccumulatorMessageID != messageID
            || streamingMarkdownAccumulator.consumedRawUTF8Count != fullContent.utf8.count - appended.utf8.count {
            streamingMarkdownAccumulator.reset()
            streamingAccumulatorMessageID = messageID
            streamingMarkdownAccumulator.append(fullContent)
        } else {
            streamingMarkdownAccumulator.append(appended)
        }
        streamingPresentation = streamingMarkdownAccumulator.makePresentation()
    }

    private func clearStreamingPresentation() {
        streamingPresentation = nil
        streamingAccumulatorMessageID = nil
        streamingMarkdownAccumulator.reset()
    }

    private func flushAllPendingAssistantText() {
        guard !streamingTextBuffer.isEmpty,
              let id = streamingMessageID ?? closedTurnAssistantID,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let remaining = streamingTextBuffer.drain()
        guard !remaining.isEmpty else { return }
        messages[idx].content += remaining
        updateStreamingPresentation(messageID: id, appended: remaining, fullContent: messages[idx].content)
        streamRevision &+= 1
    }

    private func finishDeferredPromptIfNeeded() {
        guard streamingTextBuffer.isEmpty else { return }
        reconcileCompletedTurnIfDisplayBufferIsSettled()
        guard let deferredPromptCompletion else { return }
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
        clearStreamingPresentation()
        deferredPromptCompletion = nil
        pendingLateChunkPersistence = false
        pendingCompletionReconciliation = false
    }

    private func reconcileCompletedTurnIfDisplayBufferIsSettled() {
        guard pendingCompletionReconciliation,
              streamingTextBuffer.isEmpty else { return }
        pendingCompletionReconciliation = false
        reconcileActiveTurnFromBackend()
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
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentModel = trimmed
        tabHasExplicitModel = true
        tabModelIntent = .explicit(trimmed)
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
        if tabHasExplicitModel,
           !currentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            currentModel = selectionModelID(
                requested: modelExecutionState.requestedModelID,
                effective: effective
            )
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

        currentMode = process.currentMode
        isYolo = (currentMode == .yolo)
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
