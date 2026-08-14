import Foundation

/// Typed child-ledger read outcome. `loadChildToolReceipts` returns `nil` when
/// unreadable and `[]` when the ledger was read but contained no terminal tools.
enum ChildLedgerReadOutcome: String, Sendable, Equatable, Codable {
    case unreadable
    case empty
    case receipts

    static func from(receipts: [ChildToolReceipt]?) -> ChildLedgerReadOutcome {
        guard let receipts else { return .unreadable }
        return receipts.isEmpty ? .empty : .receipts
    }
}

/// One read-only, generation-bound projection of the settled evidence for a
/// single parent turn. It intentionally contains receipts, not mutable runtime
/// controls: Grok remains the lifecycle and tool executor.
struct RunEvidenceSnapshot: Equatable, Sendable {
    /// Per-parent-turn coordination observations. Counts come only from typed
    /// spawn tool rows and generation-bound ACP lifecycle receipts; missing
    /// backend usage remains nil instead of being presented as zero.
    struct CoordinationMetrics: Equatable, Sendable, Codable, Hashable {
        let requestedChildCount: Int
        let spawnedChildCount: Int
        let finishedChildCount: Int
        let maximumUsefulConcurrency: Int
        let childToolCallCount: Int?
        let unresolvedIdentityCount: Int
        let stopToSettleMilliseconds: Int?
        let parentTotalTokens: Int?
        let childTotalTokens: Int?
    }

    struct Binding: Equatable, Sendable {
        let localTabID: UUID?
        let workspaceID: UUID?
        let backendSessionID: String?
        let processGeneration: UInt64?
        /// The backend prompt/turn ID when ACP reports one. It is not inferred
        /// from assistant prose or a local message UUID.
        let requestID: String?
        let isSettled: Bool
    }

    struct PlanStep: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let status: String

        var isCurrent: Bool {
            status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "in_progress"
        }
    }

    struct Worker: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let status: String
        /// The plan step that was current when this worker first crossed the
        /// generation-bound lifecycle stream. `nil` means no owning step was
        /// authoritative at that boundary.
        let owningPlanStepID: String?
        let childID: String?
        let durationMilliseconds: Int?
        let toolCallCount: Int?
        let redactedError: String?
        var childToolReceipts: [ChildToolReceipt]? = nil
        /// Exact runtime model emitted by Grok for this child lifecycle.
        var runtimeModelID: String? = nil
        /// Configured `[subagents.roles.*]` model for this worker's role name, when the
        /// title matches a role exactly. Declared routing from config — displayed as
        /// "(configured)", never as a runtime billing claim.
        var routedModel: String? = nil
        /// Distinguishes an unreadable child ledger from a read ledger with zero tools.
        var childLedgerReadOutcome: ChildLedgerReadOutcome? = nil

        init(
            id: String,
            title: String,
            status: String,
            owningPlanStepID: String? = nil,
            childID: String?,
            durationMilliseconds: Int?,
            toolCallCount: Int?,
            redactedError: String?,
            childToolReceipts: [ChildToolReceipt]? = nil,
            runtimeModelID: String? = nil,
            routedModel: String? = nil,
            childLedgerReadOutcome: ChildLedgerReadOutcome? = nil
        ) {
            self.id = id
            self.title = title
            self.status = status
            self.owningPlanStepID = owningPlanStepID
            self.childID = childID
            self.durationMilliseconds = durationMilliseconds
            self.toolCallCount = toolCallCount
            self.redactedError = redactedError
            self.childToolReceipts = childToolReceipts
            self.runtimeModelID = runtimeModelID
            self.routedModel = routedModel
            self.childLedgerReadOutcome = childLedgerReadOutcome
        }

        var isActive: Bool { BackgroundActivityStatusPolicy.isActive(status) }
        var isCompleted: Bool {
            status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "completed"
        }
        /// A completed child lifecycle does not report whether the child's
        /// individual tool calls succeeded. Keep that outcome unresolved until
        /// ACP supplies typed child-tool results; child prose is not authority.
        var hasReconciledChildToolReceipts: Bool {
            switch childLedgerReadOutcome {
            case .unreadable:
                return false
            case .empty:
                return (toolCallCount ?? 0) == 0
            case .receipts:
                guard let childToolReceipts else { return false }
                return childToolReceipts.count == (toolCallCount ?? 0)
            case nil:
                guard let childToolReceipts else { return (toolCallCount ?? 0) == 0 }
                return childToolReceipts.count == (toolCallCount ?? 0)
            }
        }
        var hasUnresolvedChildToolOutcome: Bool {
            guard isCompleted else { return false }
            if childLedgerReadOutcome == .unreadable { return true }
            guard (toolCallCount ?? 0) > 0 else { return false }
            return !hasReconciledChildToolReceipts
                || (childToolReceipts ?? []).contains { $0.status != .succeeded }
        }
        var isUnresolved: Bool {
            let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return hasUnresolvedChildToolOutcome
                || ["unknown", "orphaned", "not_settled", "status_not_settled", "cancelled", "stopped"]
                    .contains(normalized)
        }
    }

    struct ToolSummary: Equatable, Sendable {
        let succeeded: Int
        let failed: Int
        let cancelled: Int
        let unknown: Int

        var total: Int { succeeded + failed + cancelled + unknown }
    }

    struct Usage: Equatable, Sendable {
        let totalTokens: Int?
        let modelCalls: Int?
        let turnCount: Int?
        let inputTokens: Int?
        let outputTokens: Int?
        let cachedReadTokens: Int?
        let reasoningTokens: Int?
        let apiDurationMilliseconds: Int?
        let costUsdTicks: Int?
        let modelUsage: [ModelUsageReceipt]

        init(
            totalTokens: Int?,
            modelCalls: Int?,
            turnCount: Int?,
            inputTokens: Int? = nil,
            outputTokens: Int? = nil,
            cachedReadTokens: Int? = nil,
            reasoningTokens: Int? = nil,
            apiDurationMilliseconds: Int? = nil,
            costUsdTicks: Int? = nil,
            modelUsage: [ModelUsageReceipt] = []
        ) {
            self.totalTokens = totalTokens
            self.modelCalls = modelCalls
            self.turnCount = turnCount
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cachedReadTokens = cachedReadTokens
            self.reasoningTokens = reasoningTokens
            self.apiDurationMilliseconds = apiDurationMilliseconds
            self.costUsdTicks = costUsdTicks
            self.modelUsage = modelUsage
        }
    }

    struct ProcessReceipt: Equatable, Sendable {
        struct MCP: Identifiable, Equatable, Sendable {
            let name: String
            let state: String
            let reason: String?

            var id: String { name }
        }

        let state: String
        let model: String?
        let mcps: [MCP]
    }

    struct Continuity: Equatable, Sendable {
        let status: String
        let reason: String
        let provenance: String
        let requiresRecoveryAction: Bool
    }

    let binding: Binding
    let goalSummary: String?
    let plan: [PlanStep]
    let workers: [Worker]
    /// Optional for compatibility with checkpoints written before Slice 1.
    var coordination: CoordinationMetrics? = nil
    let tools: ToolSummary
    let artifacts: [ChatStore.RunArtifact]
    /// Git is a distinct authority from tool-write artifacts. It is refreshed
    /// by ContentView, then recorded here without allowing SwiftUI to decide
    /// what constitutes a run or a settled lifecycle.
    let gitReviewFiles: [String]
    let process: ProcessReceipt
    let continuity: Continuity
    let usage: Usage
    let outcome: ChatStore.TurnOutcome
    let unresolvedErrors: [String]
    let nextAction: String

    var activeWorkerCount: Int { workers.filter(\.isActive).count }
    var completedWorkerCount: Int { workers.filter(\.isCompleted).count }
    var unresolvedWorkerCount: Int { workers.filter(\.isUnresolved).count }
    var currentPlanStep: PlanStep? { plan.first(where: \.isCurrent) }

    static func unboundWorker(
        from event: SubagentSpawnedEvent,
        rolesByName: [String: String] = [:]
    ) -> Worker {
        let childLabel = String(event.childID.prefix(8))
        let description = event.description?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title: String
        if !description.isEmpty {
            title = "Unbound subagent (child \(childLabel)…): \(description)"
        } else if let subagentType = event.subagentType?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !subagentType.isEmpty {
            title = "Unbound subagent (child \(childLabel)…): \(subagentType)"
        } else {
            title = "Unbound subagent (child \(childLabel)…)"
        }
        let roleName = event.subagentType ?? ""
        return Worker(
            id: "unbound|\(event.childID)",
            title: title,
            status: "unknown",
            owningPlanStepID: nil,
            childID: event.childID,
            durationMilliseconds: nil,
            toolCallCount: nil,
            redactedError: nil,
            childToolReceipts: nil,
            runtimeModelID: event.modelID,
            routedModel: SubagentRouting.routedModel(forWorkerTitle: roleName, rolesByName: rolesByName),
            childLedgerReadOutcome: nil
        )
    }

    func replacingGitReviewFiles(_ paths: [String]) -> RunEvidenceSnapshot {
        RunEvidenceSnapshot(
            binding: binding,
            goalSummary: goalSummary,
            plan: plan,
            workers: workers,
            coordination: coordination,
            tools: tools,
            artifacts: artifacts,
            gitReviewFiles: paths,
            process: process,
            continuity: continuity,
            usage: usage,
            outcome: outcome,
            unresolvedErrors: unresolvedErrors,
            nextAction: nextAction
        )
    }
}
