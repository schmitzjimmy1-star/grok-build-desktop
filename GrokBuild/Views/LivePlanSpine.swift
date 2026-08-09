import SwiftUI

/// Workbench W-5 — pure presentation policy for the in-transcript plan spine.
/// It formats the generation-bound plan steps the live projection already
/// carries; it never decides lifecycle state or invents progress.
enum PlanSpinePresentation {
    static func isCompleted(_ status: String) -> Bool {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed", "complete", "done", "success", "succeeded": return true
        default: return false
        }
    }

    static func completedCount(_ plan: [RunEvidenceSnapshot.PlanStep]) -> Int {
        plan.filter { isCompleted($0.status) }.count
    }

    static func progressLabel(_ plan: [RunEvidenceSnapshot.PlanStep]) -> String {
        "\(completedCount(plan)) of \(plan.count) done"
    }

    static func stepAccessibilityLabel(_ step: RunEvidenceSnapshot.PlanStep) -> String {
        let state = isCompleted(step.status) ? "completed"
            : step.isCurrent ? "in progress"
            : "pending"
        return "\(step.title), \(state)"
    }
}

/// Workbench W-5 (2026-08-08): while a run is active, the live plan projection
/// renders in the transcript flow — the plan is the spine of the run, not a
/// receipt hidden behind the inspector's Run details disclosure. This view only
/// ever receives generation-bound live steps; settled turns keep the compact
/// trace and the authoritative snapshot, so the spine disappears at settlement.
struct LivePlanSpineView: View {
    let plan: [RunEvidenceSnapshot.PlanStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Label("Plan", systemImage: "list.bullet.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(PlanSpinePresentation.progressLabel(plan))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(plan) { step in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: stepSymbol(step))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stepColor(step))
                    Text(step.title)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(step.isCurrent ? .primary : .secondary)
                        .lineLimit(3)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PlanSpinePresentation.stepAccessibilityLabel(step))
            }
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run plan")
        .accessibilityValue(PlanSpinePresentation.progressLabel(plan))
        .accessibilityIdentifier("grok-plan-spine")
    }

    private func stepSymbol(_ step: RunEvidenceSnapshot.PlanStep) -> String {
        if PlanSpinePresentation.isCompleted(step.status) { return "checkmark.circle.fill" }
        return step.isCurrent ? "circle.inset.filled" : "circle"
    }

    private func stepColor(_ step: RunEvidenceSnapshot.PlanStep) -> Color {
        if PlanSpinePresentation.isCompleted(step.status) { return .secondary }
        return step.isCurrent ? .accentColor : Color(nsColor: .tertiaryLabelColor)
    }
}

/// Slice 9's answer-adjacent projection. It consumes the same live/snapshot
/// authorities as Activity and adds no lifecycle, timing, or outcome state.
enum ThreadRunSpinePresentation {
    struct ToolRow: Identifiable, Equatable {
        let id: String
        let family: String
        let operation: String
        let status: String
        let duration: String
        let worker: String
        let outputBoundary: String
    }

    static func progressLabel(_ plan: [RunEvidenceSnapshot.PlanStep]) -> String {
        let completed = PlanSpinePresentation.completedCount(plan)
        return "\(completed) completed · \(max(0, plan.count - completed)) remaining"
    }

    static func livePhase(_ projection: RunEvidenceLiveProjection) -> String {
        if let tool = projection.tools.first(where: \.isActive) {
            return "Using \(toolFamily(kind: tool.kind, mcpServerName: tool.mcpServerName))"
        }
        if projection.activeWorkerCount > 0 { return "Coordinating workers" }
        if projection.currentPlanStep != nil { return "Working the plan" }
        return "Working"
    }

    static func settledPhase(_ snapshot: RunEvidenceSnapshot) -> String {
        snapshot.outcome.displayName
    }

    static func checkpointLabel(_ snapshot: RunEvidenceSnapshot) -> String {
        if snapshot.continuity.requiresRecoveryAction { return "Recovery required" }
        if snapshot.outcome == .completionReceiptMissing { return "Checkpoint incomplete" }
        if snapshot.outcome == .userStopped { return "Stopped checkpoint" }
        return snapshot.binding.isSettled ? "Checkpoint saved" : "Checkpoint not settled"
    }

    static func liveTools(
        _ projection: RunEvidenceLiveProjection,
        workspace: URL?
    ) -> [ToolRow] {
        projection.tools.map { tool in
            ToolRow(
                id: tool.id,
                family: toolFamily(kind: tool.kind, mcpServerName: tool.mcpServerName),
                operation: operation(title: tool.title, qualifiedToolName: tool.qualifiedToolName),
                status: tool.status,
                duration: "Duration not reported",
                worker: "Parent agent",
                outputBoundary: outputBoundary(
                    toolID: tool.id,
                    artifacts: projection.artifacts,
                    workspace: workspace
                )
            )
        }
    }

    static func settledTools(
        _ tools: [AssistantTurnTrace.Tool],
        artifacts: [ChatStore.RunArtifact],
        workspace: URL?
    ) -> [ToolRow] {
        tools.map { tool in
            ToolRow(
                id: tool.id,
                family: toolFamily(kind: tool.kind, mcpServerName: tool.mcpServerName),
                operation: operation(title: tool.title, qualifiedToolName: tool.qualifiedToolName),
                status: tool.status,
                duration: "Duration not reported",
                worker: "Parent agent",
                outputBoundary: outputBoundary(toolID: tool.id, artifacts: artifacts, workspace: workspace)
            )
        }
    }

    static func workers(
        _ workers: [RunEvidenceSnapshot.Worker],
        ownedBy step: RunEvidenceSnapshot.PlanStep
    ) -> [RunEvidenceSnapshot.Worker] {
        workers.filter { $0.owningPlanStepID == step.id }
    }

    static func unownedWorkers(
        _ workers: [RunEvidenceSnapshot.Worker],
        plan: [RunEvidenceSnapshot.PlanStep]
    ) -> [RunEvidenceSnapshot.Worker] {
        let visibleStepIDs = Set(plan.map(\.id))
        return workers.filter { worker in
            guard let stepID = worker.owningPlanStepID else { return true }
            return !visibleStepIDs.contains(stepID)
        }
    }

    private static func toolFamily(kind: String?, mcpServerName: String?) -> String {
        if let server = mcpServerName?.trimmingCharacters(in: .whitespacesAndNewlines), !server.isEmpty {
            return server
        }
        if let kind = kind?.trimmingCharacters(in: .whitespacesAndNewlines),
           !kind.isEmpty, kind.lowercased() != "unknown" {
            return kind
        }
        return "Tool"
    }

    private static func operation(title: String, qualifiedToolName: String?) -> String {
        TranscriptTextPresentation.singleLine(qualifiedToolName ?? title, maxLength: 160)
    }

    private static func outputBoundary(
        toolID: String,
        artifacts: [ChatStore.RunArtifact],
        workspace: URL?
    ) -> String {
        guard let artifact = artifacts.first(where: { $0.toolCallID == toolID }) else {
            return "No file artifact reported"
        }
        return ActivitySidebarPresentation.displayPath(artifact.path, relativeTo: workspace)
    }
}

struct ThreadRunSpineView: View {
    let live: RunEvidenceLiveProjection?
    let snapshot: RunEvidenceSnapshot?
    let settledTools: [AssistantTurnTrace.Tool]
    let workspace: URL?
    let onOpenActivity: () -> Void
    let onOpenReview: () -> Void
    let onRevealArtifact: (ChatStore.RunArtifact) -> Void

    @State private var receiptsExpanded = false

    private var plan: [RunEvidenceSnapshot.PlanStep] { live?.plan ?? snapshot?.plan ?? [] }
    private var workers: [RunEvidenceSnapshot.Worker] { live?.workers ?? snapshot?.workers ?? [] }
    private var artifacts: [ChatStore.RunArtifact] { live?.artifacts ?? snapshot?.artifacts ?? [] }
    private var tools: [ThreadRunSpinePresentation.ToolRow] {
        if let live { return ThreadRunSpinePresentation.liveTools(live, workspace: workspace) }
        return ThreadRunSpinePresentation.settledTools(
            settledTools,
            artifacts: artifacts,
            workspace: workspace
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Run", systemImage: live == nil ? "checklist.checked" : "waveform.path")
                    .font(.system(size: 13, weight: .semibold))
                Text(phase)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                let activeWorkerCount = workers.filter(\.isActive).count
                if activeWorkerCount > 0 {
                    Text("\(activeWorkerCount) active \(activeWorkerCount == 1 ? "worker" : "workers")")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !plan.isEmpty {
                    Text(ThreadRunSpinePresentation.progressLabel(plan))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if let live, let activeTool = tools.first(where: { row in
                live.tools.first(where: { $0.id == row.id })?.isActive == true
            }) {
                toolRow(activeTool, isCurrent: true)
            }

            ForEach(plan) { step in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: stepSymbol(step))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(step.isCurrent ? Color.accentColor : Color.secondary)
                        Text(step.title)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(step.isCurrent ? .primary : .secondary)
                    }
                    ForEach(ThreadRunSpinePresentation.workers(workers, ownedBy: step)) { worker in
                        workerRow(worker)
                            .padding(.leading, 18)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(PlanSpinePresentation.stepAccessibilityLabel(step))
            }

            ForEach(ThreadRunSpinePresentation.unownedWorkers(workers, plan: plan)) { worker in
                workerRow(worker)
            }

            if !tools.isEmpty {
                DisclosureGroup(isExpanded: $receiptsExpanded) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(tools) { tool in toolRow(tool, isCurrent: false) }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("\(tools.count) tool \(tools.count == 1 ? "receipt" : "receipts")")
                        .font(AppTheme.Typography.caption)
                }
                .accessibilityIdentifier("grok-run-spine-tool-receipts")
            }

            if let snapshot {
                Label(
                    ThreadRunSpinePresentation.checkpointLabel(snapshot),
                    systemImage: snapshot.continuity.requiresRecoveryAction
                        ? "exclamationmark.triangle.fill" : "bookmark.fill"
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(snapshot.continuity.requiresRecoveryAction ? Color.orange : Color.secondary)

                Text(snapshot.nextAction)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            if !artifacts.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Artifacts")
                        .font(AppTheme.Typography.caption.weight(.semibold))
                    ForEach(artifacts) { artifact in
                        Button {
                            onRevealArtifact(artifact)
                        } label: {
                            Label(
                                ActivitySidebarPresentation.displayPath(artifact.path, relativeTo: workspace),
                                systemImage: "doc"
                            )
                            .font(AppTheme.Typography.caption)
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 14) {
                Button("Activity", action: onOpenActivity)
                    .buttonStyle(.link)
                if let snapshot, !snapshot.gitReviewFiles.isEmpty {
                    Button("Review \(snapshot.gitReviewFiles.count) changed", action: onOpenReview)
                        .buttonStyle(.link)
                }
            }
            .font(AppTheme.Typography.caption)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(live == nil ? "Settled run spine" : "Active run spine")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(live == nil ? "grok-run-spine-settled" : "grok-run-spine-live")
    }

    private var phase: String {
        if let live { return ThreadRunSpinePresentation.livePhase(live) }
        if let snapshot { return ThreadRunSpinePresentation.settledPhase(snapshot) }
        return "No run"
    }

    private var accessibilityValue: String {
        var parts = [phase]
        if !plan.isEmpty { parts.append(ThreadRunSpinePresentation.progressLabel(plan)) }
        let active = workers.filter(\.isActive).count
        if active > 0 { parts.append("\(active) active \(active == 1 ? "worker" : "workers")") }
        if let current = tools.first {
            parts.append("\(live == nil ? "Latest" : "Current") tool \(current.operation)")
        }
        if let snapshot { parts.append(ThreadRunSpinePresentation.checkpointLabel(snapshot)) }
        return parts.joined(separator: ", ")
    }

    private func stepSymbol(_ step: RunEvidenceSnapshot.PlanStep) -> String {
        if PlanSpinePresentation.isCompleted(step.status) { return "checkmark.circle.fill" }
        return step.isCurrent ? "circle.inset.filled" : "circle"
    }

    private func workerRow(_ worker: RunEvidenceSnapshot.Worker) -> some View {
        let receiptDetail = ActivitySidebarPresentation.workerReceiptDetail(
            status: worker.status,
            durationMilliseconds: worker.durationMilliseconds,
            toolCallCount: worker.toolCallCount,
            redactedError: worker.redactedError,
            childToolReceipts: worker.childToolReceipts,
            routedModel: worker.routedModel
        )
        return VStack(alignment: .leading, spacing: 2) {
            Label(worker.title, systemImage: worker.isActive ? "person.wave.2" : "person.2")
                .font(AppTheme.Typography.caption)
                .lineLimit(2)
            Text([
                ActivitySidebarPresentation.activityStatus(worker.status),
                receiptDetail,
            ].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(AppTheme.Typography.caption)
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func toolRow(_ tool: ThreadRunSpinePresentation.ToolRow, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: isCurrent ? "arrow.right.circle.fill" : "wrench")
                    .font(.caption2)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                Text("\(tool.family) · \(tool.operation)")
                    .font(AppTheme.Typography.caption.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(2)
            }
            Text("\(tool.status) · \(tool.duration) · \(tool.worker)")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.tertiary)
            Text(tool.outputBoundary)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.family) tool, \(tool.operation)")
        .accessibilityValue("\(tool.status), \(tool.duration), \(tool.worker), \(tool.outputBoundary)")
    }
}
