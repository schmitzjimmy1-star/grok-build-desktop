import Foundation

enum MessageRole: String, Codable, Sendable {
    case user, assistant, system
}

/// Private transcript provenance retained when GrokBuild imports a backend history.
/// Ordinary live ACP messages predate this model and intentionally decode with `nil`.
/// The metadata lets display reconciliation keep useful worker output without ever
/// promoting that output to root-conversation identity evidence.
struct TranscriptMessageProvenance: Codable, Sendable, Hashable {
    enum Source: String, Codable, Sendable {
        case backendRoot
        case backendWorker
        case backendUnknown
    }

    let source: Source
    let backendSessionID: String
    let rowIndex: Int
    let agent: String?
    let opaqueContentTag: String?
}

/// Durable, secret-free task checkpoint projected from one authoritative
/// `RunEvidenceSnapshot` at the ACP settlement boundary. It lives inside the
/// existing local assistant-turn trace so quit/relaunch can still explain the
/// task contract without inventing a second transcript or scraping grok's
/// private session storage.
struct AssistantTurnCheckpoint: Codable, Sendable, Hashable {
    struct PlanStep: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let status: String
    }

    struct Worker: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let status: String
        let owningPlanStepID: String?
        let childBackendSessionID: String?
    }

    /// Full settled worker fields needed to reconstruct the receipt after a
    /// relaunch. The older compact `workers` array remains for transcript
    /// compatibility and parent/child identity presentation.
    struct WorkerReceipt: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let status: String
        let owningPlanStepID: String?
        let childBackendSessionID: String?
        let durationMilliseconds: Int?
        let toolCallCount: Int?
        let redactedError: String?
        let childToolReceipts: [ChildToolReceipt]?
        let runtimeModelID: String?
        let routedModel: String?
        let tokenCount: Int?
        let turns: Int?
    }

    struct Artifact: Codable, Sendable, Hashable, Identifiable {
        let toolCallID: String
        let path: String
        let status: String
        let location: String
        let owningPlanStepID: String?
        let workerID: String?

        var id: String { "\(toolCallID)|\(path)" }
    }

    /// Optional full-fidelity fields added after the original compact task
    /// checkpoint shipped. Keeping the groups optional lets older transcripts
    /// decode honestly: absent means "not retained", never zero or success.
    struct ToolSummaryReceipt: Codable, Sendable, Hashable {
        let succeeded: Int
        let failed: Int
        let cancelled: Int
        let unknown: Int
    }

    struct MCPProcessReceipt: Codable, Sendable, Hashable {
        let name: String
        let state: String
        let reason: String?
    }

    struct ProcessReceipt: Codable, Sendable, Hashable {
        let state: String
        let mcps: [MCPProcessReceipt]
    }

    struct ContinuityReceipt: Codable, Sendable, Hashable {
        let status: String
        let reason: String
        let provenance: String
    }

    struct ModelUsage: Codable, Sendable, Hashable {
        let modelID: String
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?
        let cachedReadTokens: Int?
        let cacheCreationTokens: Int?
        let reasoningTokens: Int?
        let modelCalls: Int?
        let apiDurationMilliseconds: Int?
        let costUsdTicks: Int?
    }

    struct UsageReceipt: Codable, Sendable, Hashable {
        let totalTokens: Int?
        let modelCalls: Int?
        let turnCount: Int?
        let inputTokens: Int?
        let outputTokens: Int?
        let cachedReadTokens: Int?
        let cacheCreationTokens: Int?
        let reasoningTokens: Int?
        let apiDurationMilliseconds: Int?
        let costUsdTicks: Int?
        let costIsPartial: Bool?
        let modelUsage: [ModelUsage]
    }

    /// Pre-dispatch authority reported by the exact GrokBuild CLI fork. It is a
    /// projection of the runtime-owned ledger, not app-computed budget state.
    struct HardBudgetReceipt: Codable, Sendable, Hashable {
        let capabilityVersion: Int
        let cliBuild: String
        let campaignID: String
        let manifestSHA256: String
        let allocationID: String
        let packetID: String
        let promptSHA256: String
        let allocationTokenCeiling: Int
        let allocationMaxModelCalls: Int
        let routeModel: String
        let endpointSHA256: String
        let apiBackend: String
        let requestBoundTokens: Int
        let maxPayloadBytes: Int
        let maxOutputTokens: Int
        let boundProvenanceSHA256: String
        let campaignRemainingTokens: Int
        let allocationRemainingTokens: Int
        let allocationRemainingCalls: Int
        /// New receipts retain the exact containment proof. Optionals preserve
        /// decoding for checkpoints persisted before the Slice 4A wire added it.
        let noAutomaticRetry: Bool?
        let samplerTransportRetriesDisabled: Bool?
        let authProviderHelpersDisabled: Bool?
        let terminalDisabled: Bool?
        let externalMCPDisabled: Bool?
        let hooksDisabled: Bool?
        let pluginsDisabled: Bool?
        let lspDisabled: Bool?
        let workflowsDisabled: Bool?
        let schedulerDisabled: Bool?
        let protectedAuthorityFS: Bool?
        let workspaceFSConfined: Bool?
        let allowedToolIDs: [String]?
        /// Cursor captured immediately before the governed provider dispatch.
        /// Optional so historical checkpoints remain decodable.
        let preDispatchNextSequence: Int?
        let preDispatchLedgerRevision: Int?

        init?(_ capability: GrokBuildHardTokenBudgetCapability) {
            guard capability.isEnforcing,
                  let status = capability.status,
                  let allocation = capability.allocation else { return nil }
            capabilityVersion = capability.capabilityVersion
            cliBuild = capability.cliBuild
            campaignID = status.campaignID
            manifestSHA256 = status.manifestSHA256
            allocationID = allocation.id
            packetID = allocation.packetID
            promptSHA256 = allocation.promptSHA256
            allocationTokenCeiling = allocation.tokenCeiling
            allocationMaxModelCalls = allocation.maxModelCalls
            routeModel = allocation.route.model
            endpointSHA256 = allocation.route.endpointSHA256
            apiBackend = allocation.route.apiBackend
            requestBoundTokens = allocation.route.requestBoundTokens
            maxPayloadBytes = allocation.route.maxPayloadBytes
            maxOutputTokens = allocation.route.maxOutputTokens
            boundProvenanceSHA256 = allocation.route.boundProvenanceSHA256
            campaignRemainingTokens = status.remainingTokens
            allocationRemainingTokens = status.allocationRemainingTokens
            allocationRemainingCalls = status.allocationRemainingCalls
            noAutomaticRetry = capability.noAutomaticRetry
            samplerTransportRetriesDisabled = capability.samplerTransportRetriesDisabled
            authProviderHelpersDisabled = capability.authProviderHelpersDisabled
            terminalDisabled = capability.terminalDisabled
            externalMCPDisabled = capability.externalMCPDisabled
            hooksDisabled = capability.hooksDisabled
            pluginsDisabled = capability.pluginsDisabled
            lspDisabled = capability.lspDisabled
            workflowsDisabled = capability.workflowsDisabled
            schedulerDisabled = capability.schedulerDisabled
            protectedAuthorityFS = capability.protectedAuthorityFS
            workspaceFSConfined = capability.workspaceFSConfined
            allowedToolIDs = capability.allowedToolIDs
            preDispatchNextSequence = status.nextSequence
            preDispatchLedgerRevision = status.ledgerRevision
        }
    }

    /// Terminal ledger evidence is separate from pre-dispatch authority. Older
    /// checkpoints decode without it; absent is never upgraded to settled.
    struct HardBudgetTerminalProjection: Codable, Sendable, Hashable {
        enum Status: String, Codable, Sendable { case settled, ambiguous, unavailable, rejected }
        struct Request: Codable, Sendable, Hashable {
            let reservationID: String
            let sequence: Int
            let providerRequestID: String
            let model: String
            let endpointSHA256: String
            let apiBackend: String
            let payloadBytes: Int
            let maxOutputTokens: Int
            let reservedTokens: Int
            let actualTokens: Int?
            let chargedTokens: Int
            let lifecycle: String
        }
        let status: Status
        let ledgerRevision: Int?
        let nextSequence: Int?
        let reservationCount: Int?
        let reason: String?
        let requests: [Request]?
    }

    /// Structured, credential-free route configuration frozen against the exact
    /// process generation. This proves what GrokBuild configured; ACP model and
    /// usage receipts separately prove what the CLI actually reported.
    struct RouteReceipt: Codable, Sendable, Hashable {
        enum Kind: String, Codable, Sendable {
            case nativeXAI
            case directProvider
            case brokeredOpenRouter
            case localEndpoint
            case unavailable
        }

        let kind: Kind
        let selectedModelID: String
        let providerName: String
        let appProviderID: String?
        let officialProviderID: String?
        let endpointIdentity: String?
        let providerModelID: String
        let apiBackend: String?
        let authBoundary: String
        let modelIsPinned: Bool
        let servingProviderIsProven: Bool
        let appFallbackEnabled: Bool

        init(_ route: ModelRouteContract) {
            switch route.kind {
            case .nativeXAI: kind = .nativeXAI
            case .directProvider: kind = .directProvider
            case .brokeredOpenRouter: kind = .brokeredOpenRouter
            case .localEndpoint: kind = .localEndpoint
            case .unavailable: kind = .unavailable
            }
            selectedModelID = route.selectedModelID
            providerName = route.providerName
            appProviderID = route.appProviderID
            officialProviderID = route.officialProviderID
            endpointIdentity = route.endpointRouteIdentity ?? route.endpointHost
            providerModelID = route.providerModelID
            apiBackend = route.apiBackend
            authBoundary = route.authBoundary.rawValue
            modelIsPinned = route.modelIsPinned
            servingProviderIsProven = route.servingProviderIsProven
            appFallbackEnabled = false
        }
    }

    /// Generation-bound values reported by the live CLI. Session-info fields are
    /// optional because 1.0.4 does not expose that extension; their absence is an
    /// explicit unavailable receipt, never proof of the configured route.
    struct ObservedRouteReceipt: Codable, Sendable, Hashable {
        let processGeneration: UInt64?
        let backendSessionID: String?
        let requestID: String?
        let acpAgentVersion: String?
        let catalogCurrentModelID: String?
        let catalogContainsSelectedModel: Bool?
        let sessionModelID: String?
        let resolvedModelID: String?
        let modelFingerprint: String?
        let apiBackend: String?
        /// Effective model only when the authoritative turn usage names exactly one model.
        let turnUsageEffectiveModelID: String?
        let modelUsageIDs: [String]
    }

    let objective: String?
    let outcome: String
    let plan: [PlanStep]
    let workers: [Worker]
    let localTabID: UUID?
    let parentBackendSessionID: String?
    let processGeneration: UInt64?
    let requestedToolFamilies: [String]
    let modelID: String?
    let nextAction: String
    let requiresRecoveryAction: Bool
    let isSettled: Bool
    /// Optional so transcripts written before the durable run-spine repair
    /// continue to decode without migration or invented receipts.
    let workerReceipts: [WorkerReceipt]?
    let artifacts: [Artifact]?
    let gitReviewFiles: [String]?
    let unresolvedErrors: [String]?
    /// Exact settled Activity fields. Optional for transcript compatibility.
    var workspaceID: UUID? = nil
    var requestID: String? = nil
    var outcomeCode: String? = nil
    var toolSummaryReceipt: ToolSummaryReceipt? = nil
    var processReceipt: ProcessReceipt? = nil
    var continuityReceipt: ContinuityReceipt? = nil
    var usageReceipt: UsageReceipt? = nil
    var coordinationReceipt: RunEvidenceSnapshot.CoordinationMetrics? = nil
    var attachmentNames: [String]? = nil
    /// Credential-free route detail captured from the exact process generation
    /// when this settled checkpoint was written. Absent legacy values stay absent.
    var routeReceipt: String? = nil
    var structuredRouteReceipt: RouteReceipt? = nil
    var observedRouteReceipt: ObservedRouteReceipt? = nil
    var hardBudgetReceipt: HardBudgetReceipt? = nil
    var hardBudgetTerminalProjection: HardBudgetTerminalProjection? = nil

    init(
        snapshot: RunEvidenceSnapshot,
        requestedToolFamilies: [String],
        attachmentNames: [String] = [],
        routeReceipt: String? = nil,
        routeContract: ModelRouteContract? = nil,
        observedRouteReceipt: ObservedRouteReceipt? = nil,
        hardBudgetReceipt: HardBudgetReceipt? = nil,
        hardBudgetTerminalProjection: HardBudgetTerminalProjection? = nil
    ) {
        objective = snapshot.goalSummary
        outcome = snapshot.outcome.displayName
        plan = snapshot.plan.map {
            PlanStep(id: $0.id, title: $0.title, status: $0.status)
        }
        workers = snapshot.workers.map {
            Worker(
                id: $0.id,
                title: $0.title,
                status: $0.status,
                owningPlanStepID: $0.owningPlanStepID,
                childBackendSessionID: $0.childID
            )
        }
        localTabID = snapshot.binding.localTabID
        parentBackendSessionID = snapshot.binding.backendSessionID
        processGeneration = snapshot.binding.processGeneration
        self.requestedToolFamilies = Array(Set(requestedToolFamilies))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        modelID = snapshot.process.model
        nextAction = snapshot.nextAction
        requiresRecoveryAction = snapshot.continuity.requiresRecoveryAction
        isSettled = snapshot.binding.isSettled
        workerReceipts = snapshot.workers.map {
            WorkerReceipt(
                id: $0.id,
                title: $0.title,
                status: $0.status,
                owningPlanStepID: $0.owningPlanStepID,
                childBackendSessionID: $0.childID,
                durationMilliseconds: $0.durationMilliseconds,
                toolCallCount: $0.toolCallCount,
                redactedError: $0.redactedError,
                childToolReceipts: $0.childToolReceipts,
                runtimeModelID: $0.runtimeModelID,
                routedModel: $0.routedModel,
                tokenCount: $0.tokenCount,
                turns: $0.turns
            )
        }
        artifacts = snapshot.artifacts.map {
            Artifact(
                toolCallID: $0.toolCallID,
                path: $0.path,
                status: $0.status,
                location: $0.location.rawValue,
                owningPlanStepID: $0.owningPlanStepID,
                workerID: $0.workerID
            )
        }
        gitReviewFiles = snapshot.gitReviewFiles
        unresolvedErrors = snapshot.unresolvedErrors
        workspaceID = snapshot.binding.workspaceID
        requestID = snapshot.binding.requestID
        outcomeCode = snapshot.outcome.rawValue
        toolSummaryReceipt = ToolSummaryReceipt(
            succeeded: snapshot.tools.succeeded,
            failed: snapshot.tools.failed,
            cancelled: snapshot.tools.cancelled,
            unknown: snapshot.tools.unknown
        )
        processReceipt = ProcessReceipt(
            state: snapshot.process.state,
            mcps: snapshot.process.mcps.map {
                MCPProcessReceipt(name: $0.name, state: $0.state, reason: $0.reason)
            }
        )
        continuityReceipt = ContinuityReceipt(
            status: snapshot.continuity.status,
            reason: snapshot.continuity.reason,
            provenance: snapshot.continuity.provenance
        )
        usageReceipt = UsageReceipt(
            totalTokens: snapshot.usage.totalTokens,
            modelCalls: snapshot.usage.modelCalls,
            turnCount: snapshot.usage.turnCount,
            inputTokens: snapshot.usage.inputTokens,
            outputTokens: snapshot.usage.outputTokens,
            cachedReadTokens: snapshot.usage.cachedReadTokens,
            cacheCreationTokens: snapshot.usage.cacheCreationTokens,
            reasoningTokens: snapshot.usage.reasoningTokens,
            apiDurationMilliseconds: snapshot.usage.apiDurationMilliseconds,
            costUsdTicks: snapshot.usage.costUsdTicks,
            costIsPartial: snapshot.usage.costIsPartial,
            modelUsage: snapshot.usage.modelUsage.map {
                ModelUsage(
                    modelID: $0.modelID,
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    totalTokens: $0.totalTokens,
                    cachedReadTokens: $0.cachedReadTokens,
                    cacheCreationTokens: $0.cacheCreationTokens,
                    reasoningTokens: $0.reasoningTokens,
                    modelCalls: $0.modelCalls,
                    apiDurationMilliseconds: $0.apiDurationMilliseconds,
                    costUsdTicks: $0.costUsdTicks
                )
            }
        )
        coordinationReceipt = snapshot.coordination
        self.attachmentNames = Array(Set(attachmentNames)).sorted()
        self.routeReceipt = routeReceipt
        structuredRouteReceipt = routeContract.map(RouteReceipt.init)
        self.observedRouteReceipt = observedRouteReceipt
        self.hardBudgetReceipt = hardBudgetReceipt
        self.hardBudgetTerminalProjection = hardBudgetTerminalProjection
    }

    /// Reconstitutes the settled Activity projection from the existing local
    /// checkpoint only. Legacy checkpoints remain explicit about fields that
    /// predate full-fidelity persistence instead of manufacturing receipts.
    func restoredRunEvidenceSnapshot(
        settledTools: [AssistantTurnTrace.Tool]
    ) -> RunEvidenceSnapshot {
        let legacyToolSummary = Self.toolSummary(from: settledTools)
        let tools = toolSummaryReceipt.map {
            RunEvidenceSnapshot.ToolSummary(
                succeeded: $0.succeeded,
                failed: $0.failed,
                cancelled: $0.cancelled,
                unknown: $0.unknown
            )
        } ?? legacyToolSummary
        let process = processReceipt.map {
            RunEvidenceSnapshot.ProcessReceipt(
                state: $0.state,
                model: modelID,
                mcps: $0.mcps.map { .init(name: $0.name, state: $0.state, reason: $0.reason) }
            )
        } ?? .init(
            state: "Saved checkpoint — process not running; prior state not retained",
            model: modelID,
            mcps: []
        )
        let continuity = continuityReceipt.map {
            RunEvidenceSnapshot.Continuity(
                status: $0.status,
                reason: $0.reason,
                provenance: $0.provenance,
                requiresRecoveryAction: requiresRecoveryAction
            )
        } ?? .init(
            status: "checkpointOnly",
            reason: "Detailed continuity receipt not retained by this legacy checkpoint",
            provenance: "Saved local checkpoint",
            requiresRecoveryAction: requiresRecoveryAction
        )
        let usage = usageReceipt.map {
            RunEvidenceSnapshot.Usage(
                totalTokens: $0.totalTokens,
                modelCalls: $0.modelCalls,
                turnCount: $0.turnCount,
                inputTokens: $0.inputTokens,
                outputTokens: $0.outputTokens,
                cachedReadTokens: $0.cachedReadTokens,
                cacheCreationTokens: $0.cacheCreationTokens,
                reasoningTokens: $0.reasoningTokens,
                apiDurationMilliseconds: $0.apiDurationMilliseconds,
                costUsdTicks: $0.costUsdTicks,
                costIsPartial: $0.costIsPartial,
                modelUsage: $0.modelUsage.map {
                    ModelUsageReceipt(
                        modelID: $0.modelID,
                        inputTokens: $0.inputTokens,
                        outputTokens: $0.outputTokens,
                        totalTokens: $0.totalTokens,
                        cachedReadTokens: $0.cachedReadTokens,
                        cacheCreationTokens: $0.cacheCreationTokens,
                        reasoningTokens: $0.reasoningTokens,
                        modelCalls: $0.modelCalls,
                        apiDurationMilliseconds: $0.apiDurationMilliseconds,
                        costUsdTicks: $0.costUsdTicks
                    )
                }
            )
        } ?? .init(totalTokens: nil, modelCalls: nil, turnCount: nil)

        return RunEvidenceSnapshot(
            binding: .init(
                localTabID: localTabID,
                workspaceID: workspaceID,
                backendSessionID: parentBackendSessionID,
                processGeneration: processGeneration,
                requestID: requestID,
                isSettled: isSettled
            ),
            goalSummary: objective,
            plan: plan.map { .init(id: $0.id, title: $0.title, status: $0.status) },
            workers: restoredWorkers,
            coordination: coordinationReceipt,
            tools: tools,
            artifacts: restoredArtifacts,
            gitReviewFiles: gitReviewFiles ?? [],
            process: process,
            continuity: continuity,
            usage: usage,
            outcome: Self.turnOutcome(code: outcomeCode, displayName: outcome),
            unresolvedErrors: unresolvedErrors ?? [],
            nextAction: nextAction
        )
    }

    private static func turnOutcome(code: String?, displayName: String) -> ChatStore.TurnOutcome {
        if let code, let exact = ChatStore.TurnOutcome(rawValue: code) { return exact }
        switch displayName {
        case ChatStore.TurnOutcome.failed.displayName: return .failed
        case ChatStore.TurnOutcome.cancelled.displayName: return .cancelled
        case ChatStore.TurnOutcome.completionReceiptMissing.displayName: return .completionReceiptMissing
        case ChatStore.TurnOutcome.userStopped.displayName: return .userStopped
        default: return .completed
        }
    }

    private var restoredWorkers: [RunEvidenceSnapshot.Worker] {
        if let workerReceipts {
            return workerReceipts.map {
                .init(
                    id: $0.id,
                    title: $0.title,
                    status: $0.status,
                    owningPlanStepID: $0.owningPlanStepID,
                    childID: $0.childBackendSessionID,
                    durationMilliseconds: $0.durationMilliseconds,
                    toolCallCount: $0.toolCallCount,
                    redactedError: $0.redactedError,
                    childToolReceipts: $0.childToolReceipts,
                    runtimeModelID: $0.runtimeModelID,
                    routedModel: $0.routedModel,
                    tokenCount: $0.tokenCount,
                    turns: $0.turns
                )
            }
        }
        return workers.map {
            .init(
                id: $0.id,
                title: $0.title,
                status: $0.status,
                owningPlanStepID: $0.owningPlanStepID,
                childID: $0.childBackendSessionID,
                durationMilliseconds: nil,
                toolCallCount: nil,
                redactedError: nil
            )
        }
    }

    private var restoredArtifacts: [ChatStore.RunArtifact] {
        (artifacts ?? []).map {
            .init(
                toolCallID: $0.toolCallID,
                path: $0.path,
                status: $0.status,
                location: ChatStore.RunArtifact.Location(rawValue: $0.location) ?? .external,
                owningPlanStepID: $0.owningPlanStepID,
                workerID: $0.workerID
            )
        }
    }

    private static func toolSummary(
        from tools: [AssistantTurnTrace.Tool]
    ) -> RunEvidenceSnapshot.ToolSummary {
        var succeeded = 0
        var failed = 0
        var cancelled = 0
        var unknown = 0
        for tool in tools {
            switch tool.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "succeeded", "success", "completed", "complete": succeeded += 1
            case "failed", "failure", "error": failed += 1
            case "cancelled", "canceled": cancelled += 1
            default: unknown += 1
            }
        }
        return .init(succeeded: succeeded, failed: failed, cancelled: cancelled, unknown: unknown)
    }
}

/// Safe, local presentation receipts for one assistant turn. The summary is
/// the public ACP reasoning summary, never hidden chain-of-thought. Tool rows
/// retain only redacted labels, terminal state, and an authoritative MCP server
/// name when the backend reported one. This travels with GrokBuild's local
/// transcript and never rewrites Grok's backend history.
struct AssistantTurnTrace: Codable, Sendable, Hashable {
    struct Tool: Codable, Sendable, Hashable, Identifiable {
        let id: String
        let title: String
        let kind: String?
        let status: String
        let mcpServerName: String?
        let mcpReceiptRole: MCPToolReceiptRole?
        let qualifiedToolName: String?
        let discoveredQualifiedToolNames: [String]
        let resultDetail: String?
        let owningPlanStepID: String?
        let durationMilliseconds: Int?

        init(
            id: String,
            title: String,
            kind: String? = nil,
            status: String,
            mcpServerName: String?,
            mcpReceiptRole: MCPToolReceiptRole? = nil,
            qualifiedToolName: String? = nil,
            discoveredQualifiedToolNames: [String] = [],
            resultDetail: String? = nil,
            owningPlanStepID: String? = nil,
            durationMilliseconds: Int? = nil
        ) {
            self.id = id
            self.title = title
            self.kind = kind
            self.status = status
            self.mcpServerName = mcpServerName
            self.mcpReceiptRole = mcpReceiptRole
            self.qualifiedToolName = qualifiedToolName
            self.discoveredQualifiedToolNames = discoveredQualifiedToolNames
            self.resultDetail = resultDetail
            self.owningPlanStepID = owningPlanStepID
            self.durationMilliseconds = durationMilliseconds
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, kind, status, mcpServerName, mcpReceiptRole
            case qualifiedToolName, discoveredQualifiedToolNames
            case resultDetail, owningPlanStepID, durationMilliseconds
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            title = try values.decode(String.self, forKey: .title)
            kind = try values.decodeIfPresent(String.self, forKey: .kind)
            status = try values.decode(String.self, forKey: .status)
            mcpServerName = try values.decodeIfPresent(String.self, forKey: .mcpServerName)
            mcpReceiptRole = try values.decodeIfPresent(MCPToolReceiptRole.self, forKey: .mcpReceiptRole)
            qualifiedToolName = try values.decodeIfPresent(String.self, forKey: .qualifiedToolName)
            discoveredQualifiedToolNames = try values.decodeIfPresent(
                [String].self,
                forKey: .discoveredQualifiedToolNames
            ) ?? []
            resultDetail = try values.decodeIfPresent(String.self, forKey: .resultDetail)
            owningPlanStepID = try values.decodeIfPresent(String.self, forKey: .owningPlanStepID)
            durationMilliseconds = try values.decodeIfPresent(Int.self, forKey: .durationMilliseconds)
        }
    }

    let reasoningSummaryChunks: [String]
    let thinkingDuration: TimeInterval?
    let tools: [Tool]
    /// The confirmed effective model that produced this turn, as a display name.
    /// Stamped at turn settlement from the generation-bound execution receipt;
    /// `nil` on transcripts recorded before the field existed and on turns whose
    /// model was never exactly confirmed — the header then falls back to the
    /// neutral "Build agent" label rather than guessing.
    var modelDisplayName: String? = nil
    /// The custom subagent role that ran the whole session's turn, when one was
    /// explicitly selected. Empty/default agent stays `nil`.
    var agentName: String? = nil
    /// Slice 10 durable task contract. Missing on legacy transcripts.
    var checkpoint: AssistantTurnCheckpoint? = nil

    var hasContent: Bool {
        !reasoningSummaryChunks.isEmpty || thinkingDuration != nil || !tools.isEmpty || checkpoint != nil
    }
}

struct Message: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    let provenance: TranscriptMessageProvenance?
    var assistantTrace: AssistantTurnTrace?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        provenance: TranscriptMessageProvenance? = nil,
        assistantTrace: AssistantTurnTrace? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.provenance = provenance
        self.assistantTrace = assistantTrace
    }
}

enum AssistantDiffPresentation {
    static func isExample(language: String?) -> Bool {
        guard let language else { return false }
        return ["diff", "patch"].contains(language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
