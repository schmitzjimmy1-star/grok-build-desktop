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
        let resultDetail: String?
        let owningPlanStepID: String?
    }

    static func progressLabel(_ plan: [RunEvidenceSnapshot.PlanStep]) -> String {
        let completed = PlanSpinePresentation.completedCount(plan)
        return "\(completed) completed · \(max(0, plan.count - completed)) remaining"
    }

    static func persistedPlan(_ checkpoint: AssistantTurnCheckpoint?) -> [RunEvidenceSnapshot.PlanStep] {
        (checkpoint?.plan ?? []).map { .init(id: $0.id, title: $0.title, status: $0.status) }
    }

    static func persistedWorkers(_ checkpoint: AssistantTurnCheckpoint?) -> [RunEvidenceSnapshot.Worker] {
        guard let checkpoint else { return [] }
        if let receipts = checkpoint.workerReceipts {
            return receipts.map {
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
                    routedModel: $0.routedModel
                )
            }
        }
        return checkpoint.workers.map {
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

    static func persistedArtifacts(_ checkpoint: AssistantTurnCheckpoint?) -> [ChatStore.RunArtifact] {
        (checkpoint?.artifacts ?? []).map {
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
        if snapshot.outcome == .failed { return "Failed checkpoint" }
        if snapshot.outcome == .cancelled { return "Cancelled checkpoint" }
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
                duration: durationLabel(tool.durationMilliseconds),
                worker: "Parent agent",
                outputBoundary: outputBoundary(
                    toolID: tool.id,
                    artifacts: projection.artifacts,
                    workspace: workspace
                ),
                // Tool detail can change on every ACP receipt. Rendering that
                // selectable text inside the transcript's LazyVStack created a
                // macOS 26 layout feedback loop. The authoritative result is
                // retained and shown after settlement instead.
                resultDetail: nil,
                owningPlanStepID: tool.owningPlanStepID
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
                duration: durationLabel(tool.durationMilliseconds),
                worker: "Parent agent",
                outputBoundary: outputBoundary(toolID: tool.id, artifacts: artifacts, workspace: workspace),
                resultDetail: tool.resultDetail,
                owningPlanStepID: tool.owningPlanStepID
            )
        }
    }

    static func tools(_ tools: [ToolRow], ownedBy step: RunEvidenceSnapshot.PlanStep) -> [ToolRow] {
        tools.filter { $0.owningPlanStepID == step.id }
    }

    static func unownedTools(_ tools: [ToolRow], plan: [RunEvidenceSnapshot.PlanStep]) -> [ToolRow] {
        let stepIDs = Set(plan.map(\.id))
        return tools.filter { tool in
            guard let stepID = tool.owningPlanStepID else { return true }
            return !stepIDs.contains(stepID)
        }
    }

    static func artifacts(
        _ artifacts: [ChatStore.RunArtifact],
        ownedBy step: RunEvidenceSnapshot.PlanStep
    ) -> [ChatStore.RunArtifact] {
        artifacts.filter { $0.owningPlanStepID == step.id }
    }

    static func unownedArtifacts(
        _ artifacts: [ChatStore.RunArtifact],
        plan: [RunEvidenceSnapshot.PlanStep]
    ) -> [ChatStore.RunArtifact] {
        let stepIDs = Set(plan.map(\.id))
        return artifacts.filter { artifact in
            guard let stepID = artifact.owningPlanStepID else { return true }
            return !stepIDs.contains(stepID)
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

    static func durationLabel(_ milliseconds: Int?) -> String {
        guard let milliseconds, milliseconds >= 0 else { return "Duration not reported" }
        if milliseconds < 1_000 { return "\(milliseconds) ms" }
        return String(format: "%.1f s", Double(milliseconds) / 1_000)
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

/// Slice 10's compact header contract. Every field is passed from an existing
/// owner (ACP/run evidence, the persisted local turn checkpoint, Git, or the
/// saved session binding). This type formats facts; it owns no lifecycle.
enum ThreadTaskContractPresentation {
    struct WorkerHandoff: Identifiable, Equatable {
        let id: String
        let parentBackendSessionID: String
        let childBackendSessionID: String
        let title: String
        let status: String

        var displayText: String {
            "Parent \(parentBackendSessionID) → Child \(childBackendSessionID) · \(status)"
        }
    }

    static func phase(
        live: RunEvidenceLiveProjection?,
        snapshot: RunEvidenceSnapshot?,
        checkpoint: AssistantTurnCheckpoint?,
        connectionState: GrokProcessState,
        isPreparingSubmit: Bool,
        canResumeSavedTask: Bool,
        continuityRequiresRecovery: Bool,
        isResumedSession: Bool
    ) -> String {
        if isPreparingSubmit { return "Preparing task — not dispatched" }
        if let live { return ThreadRunSpinePresentation.livePhase(live) }
        if case .busy = connectionState { return "Working — live receipt pending" }
        if continuityRequiresRecovery { return "Fresh thread required" }
        if let snapshot { return ThreadRunSpinePresentation.checkpointLabel(snapshot) }
        if canResumeSavedTask { return "Paused locally — ready to resume" }
        switch connectionState {
        case .ready: return "Connected — idle"
        case .starting: return isResumedSession ? "Resuming saved task" : "Starting agent…"
        case .failed: return "Connection failed"
        case .idle:
            if let checkpoint { return checkpoint.outcome == "Stopped by you" ? "Stopped" : "Saved checkpoint — no process running" }
            return "Draft — no process running"
        case .busy: return "Working — live receipt pending"
        }
    }

    static func objective(
        live: RunEvidenceLiveProjection?,
        snapshot: RunEvidenceSnapshot?,
        checkpoint: AssistantTurnCheckpoint?,
        latestUserText: String?,
        fallback: String
    ) -> String {
        let candidate = live?.goalSummary
            ?? snapshot?.goalSummary
            ?? checkpoint?.objective
            ?? latestUserText
            ?? fallback
        return TranscriptTextPresentation.singleLine(candidate, maxLength: 240)
    }

    static func modelReceipt(
        current: String,
        checkpoint: AssistantTurnCheckpoint?,
        connectionState: GrokProcessState
    ) -> String {
        guard case .idle = connectionState,
              let model = checkpoint?.modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty else { return current }
        return "\(model) · saved checkpoint"
    }

    static func requestedToolFamilies(
        current: [String],
        checkpoint: AssistantTurnCheckpoint?
    ) -> [String] {
        let names = current.isEmpty ? (checkpoint?.requestedToolFamilies ?? []) : current
        return names.map { name in
            switch BuiltInToolConnection(rawValue: name) {
            case .browser?: "Browser"
            case .computerUse?: "Computer Use"
            case nil: name
            }
        }.reduce(into: [String]()) { result, name in
            guard !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
            result.append(name)
        }
    }

    /// Selects the state owner before presentation formatting. A latched submit
    /// owns the exact frozen set; otherwise an edited composer owns its visible
    /// draft attachments. Only a quiet composer falls back to the active/settled
    /// turn so the task contract cannot contradict an on-screen MCP chip.
    static func currentRequestedToolNames(
        pending: Set<String>?,
        draft: Set<String>,
        currentTurn: [String],
        composerOwnsVisibleContext: Bool
    ) -> [String] {
        if let pending { return pending.sorted() }
        if composerOwnsVisibleContext { return draft.sorted() }
        if !currentTurn.isEmpty { return currentTurn }
        return draft.sorted()
    }

    static func workerHandoffs(
        live: RunEvidenceLiveProjection?,
        snapshot: RunEvidenceSnapshot?,
        checkpoint: AssistantTurnCheckpoint?
    ) -> [WorkerHandoff] {
        let parent = live?.binding.backendSessionID
            ?? snapshot?.binding.backendSessionID
            ?? checkpoint?.parentBackendSessionID
        guard let parent else { return [] }
        let workers: [(String, String, String, String?)]
        if let live {
            workers = live.workers.map { ($0.id, $0.title, $0.status, $0.childID) }
        } else if let snapshot {
            workers = snapshot.workers.map { ($0.id, $0.title, $0.status, $0.childID) }
        } else {
            workers = (checkpoint?.workers ?? []).map {
                ($0.id, $0.title, $0.status, $0.childBackendSessionID)
            }
        }
        return workers.compactMap { id, title, status, child -> WorkerHandoff? in
            guard let child, !child.isEmpty else { return nil }
            return WorkerHandoff(
                id: id,
                parentBackendSessionID: parent,
                childBackendSessionID: child,
                title: title,
                status: ActivitySidebarPresentation.activityStatus(status)
            )
        }
    }
}

struct ThreadTaskContractView: View {
    let objective: String
    let phase: String
    let project: String
    let worktree: String
    let branch: String?
    let modelReceipt: String
    let requestedToolFamilies: [String]
    let reviewState: String
    let checkpoint: AssistantTurnCheckpoint?
    let workerHandoffs: [ThreadTaskContractPresentation.WorkerHandoff]
    let backgroundReceiptCount: Int
    let scheduledTaskCount: Int
    let canCancelPending: Bool
    let canStopTurn: Bool
    let canPauseGoal: Bool
    let canResumeGoal: Bool
    let canResumeSavedTask: Bool
    let canContinueAsNew: Bool
    let onCancelPending: () -> Void
    let onStopTurn: () -> Void
    let onPauseGoal: () -> Void
    let onResumeGoal: () -> Void
    let onResumeSavedTask: () -> Void
    let onContinueAsNew: () -> Void
    let onOpenActivity: () -> Void

    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                Text(objective)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text(phase)
                    .lineLimit(1)
                Text("·").foregroundStyle(.tertiary)
                Text(project)
                if let branch {
                    Text("·").foregroundStyle(.tertiary)
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 6)
                Text(modelReceipt)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Task contract")
        .accessibilityValue("\(objective), \(phase), \(project), \(modelReceipt), \(reviewState)")
        .accessibilityHint(isExpanded ? "Closes the task contract." : "Shows worktree, tools, checkpoint, identities, and task controls.")
        .accessibilityIdentifier("grok-task-contract-toggle")
        // Keep the transcript's geometry fixed while ACP receipts stream. An
        // inline expansion can repeatedly rebuild AppKit's SelectionOverlay on
        // macOS 26; a native popover avoids that framework feedback loop.
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            contractDetails
        }
        .font(AppTheme.Typography.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .background(AppTheme.Palette.canvas)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var contractDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            contractRow("Worktree", worktree)
            contractRow("Review", reviewState)
            contractRow(
                "Requested tools",
                requestedToolFamilies.isEmpty
                    ? "No attached MCP or GUI tools"
                    : requestedToolFamilies.joined(separator: ", ")
            )
            if let checkpoint {
                contractRow(
                    "Checkpoint",
                    "\(checkpoint.outcome) · \(checkpoint.isSettled ? "settled" : "not settled") · \(checkpoint.nextAction)"
                )
                if let tab = checkpoint.localTabID, let backend = checkpoint.parentBackendSessionID {
                    contractRow(
                        "Identity",
                        "Tab \(tab.uuidString) · backend \(backend) · generation \(checkpoint.processGeneration.map(String.init) ?? "not reported")"
                    )
                }
            }
            ForEach(workerHandoffs) { handoff in
                contractRow("Worker · \(handoff.title)", handoff.displayText)
            }
            if backgroundReceiptCount > 0 || scheduledTaskCount > 0 {
                Button {
                    isExpanded = false
                    onOpenActivity()
                } label: {
                    Label(
                        "\(backgroundReceiptCount) background receipts · \(scheduledTaskCount) scheduled tasks in this thread",
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .buttonStyle(.link)
                .accessibilityHint("Opens the owning thread's authoritative run inspector receipts.")
            }

            HStack(spacing: 10) {
                if canCancelPending {
                    Button("Cancel pending", action: onCancelPending)
                        .help("Returns the exact draft to editing before any provider dispatch.")
                        .keyboardShortcut(.cancelAction)
                }
                if canStopTurn {
                    Button("Stop turn", action: onStopTurn)
                        .help("Stops the exact active process; this is not Pause or backend completion.")
                        .keyboardShortcut(".", modifiers: .command)
                }
                if canPauseGoal {
                    Button("Pause goal", action: onPauseGoal)
                        .help("Sends Grok's native /goal pause command. It does not suspend an active model call.")
                }
                if canResumeGoal {
                    Button("Resume goal", action: onResumeGoal)
                        .help("Sends Grok's native /goal resume command.")
                }
                if canResumeSavedTask {
                    Button("Resume saved task", action: onResumeSavedTask)
                        .help("Loads the exact saved Grok backend after continuity verification; no prompt is sent.")
                }
                if canContinueAsNew {
                    Button("Continue as New", action: onContinueAsNew)
                        .help("Preserves the prior record and clears the unsafe backend binding for the next send.")
                }
                Button("Run inspector") {
                    isExpanded = false
                    onOpenActivity()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if canStopTurn {
                Text("An active model turn can be stopped, not paused. Pause remains available only for Grok goals and workflow runs that expose it.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 680, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grok-task-contract-details")
    }

    private func contractRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .fontWeight(.semibold)
                .frame(width: 104, alignment: .leading)
            Text(value)
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ThreadRunSpineView: View {
    let live: RunEvidenceLiveProjection?
    let snapshot: RunEvidenceSnapshot?
    let checkpoint: AssistantTurnCheckpoint?
    let settledTools: [AssistantTurnTrace.Tool]
    let workspace: URL?
    let onOpenActivity: () -> Void
    let onRevealArtifact: (ChatStore.RunArtifact) -> Void

    @State private var receiptsExpanded = false

    private var plan: [RunEvidenceSnapshot.PlanStep] {
        live?.plan ?? snapshot?.plan ?? ThreadRunSpinePresentation.persistedPlan(checkpoint)
    }
    private var workers: [RunEvidenceSnapshot.Worker] {
        live?.workers ?? snapshot?.workers ?? ThreadRunSpinePresentation.persistedWorkers(checkpoint)
    }
    private var artifacts: [ChatStore.RunArtifact] {
        live?.artifacts ?? snapshot?.artifacts ?? ThreadRunSpinePresentation.persistedArtifacts(checkpoint)
    }
    private var parentBackendSessionID: String? {
        live?.binding.backendSessionID ?? snapshot?.binding.backendSessionID ?? checkpoint?.parentBackendSessionID
    }
    private var tools: [ThreadRunSpinePresentation.ToolRow] {
        if let live { return ThreadRunSpinePresentation.liveTools(live, workspace: workspace) }
        return ThreadRunSpinePresentation.settledTools(
            settledTools,
            artifacts: artifacts,
            workspace: workspace
        )
    }
    private var ungroupedTools: [ThreadRunSpinePresentation.ToolRow] {
        live == nil
            ? ThreadRunSpinePresentation.unownedTools(tools, plan: plan)
            : tools
    }
    private var ungroupedArtifacts: [ChatStore.RunArtifact] {
        return ThreadRunSpinePresentation.unownedArtifacts(artifacts, plan: plan)
    }

    var body: some View {
        Group {
            if let live {
                liveSummary(live)
            } else {
                settledSummary
            }
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

    /// Keep the streaming transcript at one stable row. The phase and current
    /// typed todo remain visible, while detailed tool/output grouping waits for
    /// the authoritative settled checkpoint. This avoids macOS 26 repeatedly
    /// remeasuring a changing subtree inside ChatView's LazyVStack.
    private func liveSummary(_ projection: RunEvidenceLiveProjection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("Run", systemImage: "waveform.path")
                .font(.system(size: 13, weight: .semibold))
            Text(ThreadRunSpinePresentation.livePhase(projection))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let current = plan.first(where: \.isCurrent) {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(current.title)
                    .font(AppTheme.Typography.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !plan.isEmpty {
                Text(ThreadRunSpinePresentation.progressLabel(plan))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Button("Run inspector", action: onOpenActivity)
                .buttonStyle(.link)
                .font(AppTheme.Typography.caption)
        }
        .frame(minHeight: 26)
    }

    private var settledSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Run", systemImage: "checklist.checked")
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
                    ForEach(ThreadRunSpinePresentation.tools(tools, ownedBy: step)) { tool in
                        toolRow(tool, isCurrent: false)
                            .padding(.leading, 18)
                    }
                    ForEach(ThreadRunSpinePresentation.artifacts(artifacts, ownedBy: step)) { artifact in
                        artifactRow(artifact)
                            .padding(.leading, 18)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(PlanSpinePresentation.stepAccessibilityLabel(step))
            }

            ForEach(ThreadRunSpinePresentation.unownedWorkers(workers, plan: plan)) { worker in
                workerRow(worker)
            }

            if !ungroupedTools.isEmpty {
                DisclosureGroup(isExpanded: $receiptsExpanded) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(ungroupedTools) { tool in toolRow(tool, isCurrent: false) }
                    }
                    .padding(.top, 6)
                } label: {
                    Text(live == nil
                        ? "\(ungroupedTools.count) ungrouped tool \(ungroupedTools.count == 1 ? "receipt" : "receipts")"
                        : "\(ungroupedTools.count) tool \(ungroupedTools.count == 1 ? "receipt" : "receipts")")
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

                if !snapshot.unresolvedErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warnings and unresolved decisions")
                            .font(AppTheme.Typography.caption.weight(.semibold))
                        ForEach(snapshot.unresolvedErrors, id: \.self) { warning in
                            Text(warning)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(.orange)
                        }
                        Text("No exact producing plan step was reported for these receipts.")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else if let checkpoint {
                Label(
                    checkpoint.requiresRecoveryAction ? "Recovery required" : "Checkpoint saved",
                    systemImage: checkpoint.requiresRecoveryAction
                        ? "exclamationmark.triangle.fill" : "bookmark.fill"
                )
                .font(AppTheme.Typography.caption)
                .foregroundStyle(checkpoint.requiresRecoveryAction ? Color.orange : Color.secondary)

                Text(checkpoint.nextAction)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)

                if let warnings = checkpoint.unresolvedErrors, !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warnings and unresolved decisions")
                            .font(AppTheme.Typography.caption.weight(.semibold))
                        ForEach(warnings, id: \.self) { warning in
                            Text(warning)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if !ungroupedArtifacts.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ungrouped artifacts")
                        .font(AppTheme.Typography.caption.weight(.semibold))
                    ForEach(ungroupedArtifacts) { artifact in artifactRow(artifact) }
                }
            }

            HStack(spacing: 14) {
                Button("Run inspector", action: onOpenActivity)
                    .buttonStyle(.link)
            }
            .font(AppTheme.Typography.caption)
        }
    }

    private var phase: String {
        if let live { return ThreadRunSpinePresentation.livePhase(live) }
        if let snapshot { return ThreadRunSpinePresentation.settledPhase(snapshot) }
        return checkpoint?.outcome ?? "No run"
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
        else if checkpoint != nil { parts.append("Checkpoint saved") }
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
            runtimeModelID: worker.runtimeModelID,
            routedModel: worker.routedModel,
            childLedgerReadOutcome: worker.childLedgerReadOutcome
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
            if let parentBackendSessionID, let childID = worker.childID {
                Text("Parent \(parentBackendSessionID) → Child \(childID)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
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
            if let resultDetail = tool.resultDetail, !resultDetail.isEmpty {
                Text(resultDetail)
                    .font(AppTheme.Typography.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.family) tool, \(tool.operation)")
        .accessibilityValue("\(tool.status), \(tool.duration), \(tool.worker), \(tool.outputBoundary), \(tool.resultDetail ?? "no command output reported")")
    }

    private func artifactRow(_ artifact: ChatStore.RunArtifact) -> some View {
        Button {
            onRevealArtifact(artifact)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(
                    ActivitySidebarPresentation.displayPath(artifact.path, relativeTo: workspace),
                    systemImage: (snapshot?.gitReviewFiles ?? checkpoint?.gitReviewFiles ?? []).contains(where: {
                        artifact.path.hasSuffix("/\($0)") || artifact.path == $0
                    }) == true ? "doc.badge.ellipsis" : "doc"
                )
                .font(AppTheme.Typography.caption)
                .lineLimit(1)
                Text("Exact path · parent tool \(artifact.toolCallID)\(artifact.workerID.map { " · worker \($0)" } ?? "")")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .buttonStyle(.plain)
        .help("Open exact local artifact: \(artifact.path)")
        .accessibilityLabel("Open artifact \(artifact.path)")
        .accessibilityValue("Produced by tool \(artifact.toolCallID)\(artifact.workerID.map { ", worker \($0)" } ?? ", parent agent")")
    }
}
