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
        let isActive: Bool
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
