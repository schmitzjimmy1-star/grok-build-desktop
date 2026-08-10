import Foundation

/// An ephemeral, generation-bound view of receipts observed while a parent
/// turn is still running. This is intentionally separate from
/// `RunEvidenceSnapshot`: it is never persisted, never claims settlement or
/// usage, and is replaced by the authoritative snapshot only when ACP's
/// completion barrier is consumed.
struct RunEvidenceLiveProjection: Equatable, Sendable {
    struct Binding: Equatable, Sendable {
        let localTabID: UUID
        let workspaceID: UUID?
        let backendSessionID: String
        let processGeneration: UInt64
    }

    struct Tool: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let kind: String
        let status: String
        let detail: String?
        let mcpServerName: String?
        let mcpReceiptRole: MCPToolReceiptRole?
        let qualifiedToolName: String?
        let discoveredQualifiedToolNames: [String]
        let owningPlanStepID: String?
        let durationMilliseconds: Int?
        let isActive: Bool

        init(
            id: String,
            title: String,
            kind: String,
            status: String,
            detail: String?,
            mcpServerName: String? = nil,
            mcpReceiptRole: MCPToolReceiptRole? = nil,
            qualifiedToolName: String? = nil,
            discoveredQualifiedToolNames: [String] = [],
            owningPlanStepID: String? = nil,
            durationMilliseconds: Int? = nil,
            isActive: Bool
        ) {
            self.id = id
            self.title = title
            self.kind = kind
            self.status = status
            self.detail = detail
            self.mcpServerName = mcpServerName
            self.mcpReceiptRole = mcpReceiptRole
            self.qualifiedToolName = qualifiedToolName
            self.discoveredQualifiedToolNames = discoveredQualifiedToolNames
            self.owningPlanStepID = owningPlanStepID
            self.durationMilliseconds = durationMilliseconds
            self.isActive = isActive
        }
    }

    let binding: Binding
    let goalSummary: String?
    let plan: [RunEvidenceSnapshot.PlanStep]
    let workers: [RunEvidenceSnapshot.Worker]
    let tools: [Tool]
    let artifacts: [ChatStore.RunArtifact]
    let process: RunEvidenceSnapshot.ProcessReceipt

    var activeWorkerCount: Int { workers.filter(\.isActive).count }
    var activeToolCount: Int { tools.filter(\.isActive).count }
    var currentPlanStep: RunEvidenceSnapshot.PlanStep? { plan.first(where: \.isCurrent) }
}

/// Compact, event-driven copy for the answer-adjacent live progress control.
/// It deliberately projects the same generation-bound receipts as Activity:
/// no second lifecycle, fabricated outcome, usage estimate, or periodic timer.
struct LiveProgressPresentation: Equatable, Sendable {
    let phase: String
    let activeWorkers: Int
    let activeTool: String?
    let activeMCP: String?
    let elapsedSeconds: Int?

    static func make(
        projection: RunEvidenceLiveProjection,
        startedAt: Date?,
        now: Date,
        hasAssistantText: Bool
    ) -> LiveProgressPresentation {
        let activeReceipt = projection.tools.first(where: \.isActive)
        let activeTool = activeReceipt?.title
        let activeMCP = activeReceipt?.mcpServerName
        let phase: String
        if let activeMCP {
            phase = "Using \(activeMCP)"
        } else if activeTool != nil {
            phase = "Using tools"
        } else if projection.activeWorkerCount > 0 {
            phase = "Coordinating workers"
        } else if projection.currentPlanStep != nil {
            phase = "Working the plan"
        } else if hasAssistantText {
            phase = "Writing answer"
        } else {
            phase = "Thinking"
        }
        let elapsedSeconds = startedAt.map {
            max(0, Int(now.timeIntervalSince($0).rounded(.down)))
        }
        return LiveProgressPresentation(
            phase: phase,
            activeWorkers: projection.activeWorkerCount,
            activeTool: activeTool,
            activeMCP: activeMCP,
            elapsedSeconds: elapsedSeconds
        )
    }

    var compactText: String {
        // Worker counts appear only when workers exist: "0 active workers" was
        // noise on every ordinary prompt and buried the running tool's name.
        var parts = [phase]
        if activeWorkers > 0 {
            parts.append("\(activeWorkers) active \(activeWorkers == 1 ? "worker" : "workers")")
        }
        if let activeTool {
            parts.append(TranscriptTextPresentation.singleLine(activeTool, maxLength: 48))
        }
        if let elapsedSeconds {
            parts.append("\(elapsedSeconds)s elapsed")
        }
        return parts.joined(separator: " · ")
    }

    var accessibilityValue: String {
        var parts = [phase]
        if activeWorkers > 0 {
            parts.append("\(activeWorkers) active \(activeWorkers == 1 ? "worker" : "workers")")
        }
        if let activeTool { parts.append("Active tool \(activeTool)") }
        if let elapsedSeconds { parts.append("\(elapsedSeconds) seconds elapsed") }
        return parts.joined(separator: ", ")
    }
}
