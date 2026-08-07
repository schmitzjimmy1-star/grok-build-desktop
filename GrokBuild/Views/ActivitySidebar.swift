import SwiftUI

/// Small, deterministic presentation helpers shared by the settled activity
/// drawer and the compact task pill. These helpers format existing receipts;
/// they do not decide lifecycle state.
enum ActivitySidebarPresentation {
    static func uniqueFilePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { rawPath in
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return path
        }
    }

    static func displayPath(_ path: String, relativeTo workspace: URL?) -> String {
        guard let workspace else { return path }
        let root = workspace.standardizedFileURL.path
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized.hasPrefix(root + "/") else { return path }
        return String(standardized.dropFirst(root.count + 1))
    }

    static func artifactLocationLabel(_ artifact: ChatStore.RunArtifact) -> String {
        artifact.location == .external ? "External artifact" : "Workspace artifact"
    }

    static func isActiveStatus(_ status: String) -> Bool {
        BackgroundActivityStatusPolicy.isActive(status)
    }

    static func activityTitle(_ activity: BackgroundActivity) -> String {
        let raw = TranscriptTextPresentation.singleLine(activity.title, maxLength: 160)
        let lowercased = raw.lowercased()
        if activity.kind == .subagent {
            if lowercased.contains("public education") { return "Public education lane" }
            if lowercased.contains("neighborhood geography")
                || (lowercased.contains("neighborhood") && lowercased.contains("geograph")) {
                return "Neighborhood geography lane"
            }
            if lowercased.contains("research this question") { return "Research subagent" }
        }
        return raw.isEmpty ? activity.kind.rawValue.capitalized : raw
    }

    static func activityDetail(_ activity: BackgroundActivity) -> String {
        let raw = TranscriptTextPresentation.singleLine(activity.detail, maxLength: 220)
        guard activity.kind == .subagent else { return raw }
        let combined = "\(activity.title) \(activity.detail)".lowercased()
        let laneDetail: String
        if combined.contains("public education") {
            laneDetail = "Research lane: public education"
        } else if combined.contains("neighborhood geography")
            || (combined.contains("neighborhood") && combined.contains("geograph")) {
            laneDetail = "Research lane: neighborhood geography"
        } else {
            laneDetail = raw
        }
        return [laneDetail, workerReceiptDetail(activity)].filter { !$0.isEmpty }.joined(separator: " • ")
    }

    static func workerReceiptDetail(_ activity: BackgroundActivity) -> String {
        guard activity.kind == .subagent else { return "" }
        return workerReceiptDetail(
            status: activity.status,
            durationMilliseconds: activity.durationMilliseconds,
            toolCallCount: activity.toolCallCount,
            redactedError: activity.redactedError
        )
    }

    static func workerReceiptDetail(
        status: String,
        durationMilliseconds: Int?,
        toolCallCount: Int?,
        redactedError: String?,
        routedModel: String? = nil
    ) -> String {
        var parts: [String] = []
        if let routedModel, !routedModel.isEmpty {
            // Declared routing from [subagents.roles.*] — config truth, not a billing claim.
            parts.append("Routes to \(routedModel) (configured)")
        }
        if let durationMilliseconds {
            let seconds = Double(durationMilliseconds) / 1_000
            parts.append(seconds >= 60
                ? "\((seconds / 60).formatted(.number.precision(.fractionLength(1)))) min"
                : "\(seconds.formatted(.number.precision(.fractionLength(1)))) sec")
        }
        if let toolCallCount { parts.append("\(toolCallCount) tools") }
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "unknown" {
            parts.append("No final report")
        } else if normalized == "orphaned" {
            parts.append("No final report (orphaned)")
        }
        if let redactedError {
            parts.append("Error: \(TranscriptTextPresentation.singleLine(redactedError, maxLength: 120))")
        }
        return parts.joined(separator: " • ")
    }

    /// Metadata line for a live tool receipt: kind • status, plus authoritative MCP
    /// attribution when the receipt carries a server name. Attribution is never
    /// inferred — an absent server simply omits the "via" segment (Slice 11 contract).
    static func liveToolMetadata(kind: String, status: String, mcpServerName: String?) -> String {
        let trimmedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !trimmedKind.isEmpty, trimmedKind.lowercased() != "other" {
            parts.append(trimmedKind)
        }
        parts.append(status)
        if let server = mcpServerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !server.isEmpty {
            parts.append("via \(server)")
        }
        return parts.joined(separator: " • ")
    }

    static func activityStatus(_ status: String) -> String {
        let clean = TranscriptTextPresentation.singleLine(status, maxLength: 48)
        guard !clean.isEmpty else { return "Running" }
        switch clean.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "unknown": return "No final report"
        case "orphaned": return "No final report (orphaned)"
        case "not_settled", "status_not_settled": return "Not finished yet"
        default: break
        }
        return clean.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

/// A read-only renderer for two deliberately separate evidence phases. Live
/// projection is generation-bound and explicitly unverified; settled evidence
/// comes only from `RunEvidenceSnapshot` after the ACP completion barrier.
struct ActivitySidebar: View {
    let snapshot: RunEvidenceSnapshot?
    let liveProjection: RunEvidenceLiveProjection?
    let workspace: URL?
    let onClose: () -> Void
    let onContinueAsNew: () -> Void
    let onReviewRecovery: () -> Void
    let onRevealArtifact: (ChatStore.RunArtifact) -> Void
    /// Idle-panel context: current changed files plus actions, so the drawer is useful
    /// before any run instead of a dead "no evidence" placard.
    var idleChangedFiles: [String] = []
    var onOpenReview: () -> Void = {}
    var onRevealFile: (String) -> Void = { _ in }

    @State private var confirmsContinueAsNew = false
    @State private var showsExecutionReceipts = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let snapshot {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        summaryCard(snapshot)
                        if snapshot.continuity.requiresRecoveryAction { continuityCard(snapshot) }
                        // The summary grid already reports zeros; an empty section
                        // repeating "none observed" below it is pure redundancy.
                        if !snapshot.artifacts.isEmpty { artifacts(snapshot) }
                        if !snapshot.gitReviewFiles.isEmpty { reviewFiles(snapshot) }
                        if !snapshot.workers.isEmpty { workers(snapshot) }
                        DisclosureGroup(isExpanded: $showsExecutionReceipts) {
                            VStack(alignment: .leading, spacing: 14) {
                                runDetails(snapshot)
                                toolStatus(snapshot)
                            }
                            .padding(.top, 10)
                        } label: {
                            Label("Technical details", systemImage: "list.bullet.rectangle")
                                .font(AppTheme.Typography.captionStrong)
                        }
                        .accessibilityHint("Shows model, process, continuity, usage, and MCP details.")
                    }
                    .padding(14)
                }
            } else if let liveProjection {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        liveSummaryCard(liveProjection)
                        if !liveProjection.plan.isEmpty { livePlan(liveProjection) }
                        if !liveProjection.artifacts.isEmpty { liveArtifacts(liveProjection) }
                        if !liveProjection.workers.isEmpty { liveWorkers(liveProjection) }
                        if !liveProjection.tools.isEmpty { liveTools(liveProjection) }
                        liveRunDetails(liveProjection)
                    }
                    .padding(14)
                }
            } else {
                idleWorkspacePanel
            }
        }
        .frame(minWidth: 260, idealWidth: 290, maxWidth: 320, maxHeight: 620)
        .background(AppTheme.Palette.sidebar)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.composer, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.composer, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        }
        .shadow(color: AppTheme.Palette.shadow, radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity sidebar")
        .accessibilityIdentifier("grok-activity-sidebar")
        .confirmationDialog("Continue this transcript as a new conversation?", isPresented: $confirmsContinueAsNew) {
            Button("Continue as New", role: .destructive, action: onContinueAsNew)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local messages stay in this tab. The previous backend is preserved, and no new backend starts until you send.")
        }
    }

    /// What the drawer shows before any run: the working state of the project, not a
    /// dead placard. Changed files open the diff review or reveal in Finder; run
    /// receipts take this space over as soon as a turn starts.
    private var idleWorkspacePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if idleChangedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Ready to work", systemImage: "checkmark.seal")
                            .font(AppTheme.Typography.captionStrong)
                        Text("Send a request and this panel fills with live workers, tools, artifacts, and usage. Changed files in the project will also appear here for review.")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Changed files (\(idleChangedFiles.count))", systemImage: "doc.on.doc")
                            .font(AppTheme.Typography.captionStrong)
                        ForEach(idleChangedFiles, id: \.self) { file in
                            HStack(spacing: 6) {
                                Button {
                                    onOpenReview()
                                } label: {
                                    Label(file, systemImage: "doc.text")
                                        .font(AppTheme.Typography.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Open the diff review for this project")
                                Spacer(minLength: 0)
                                Button {
                                    onRevealFile(file)
                                } label: {
                                    Image(systemName: "magnifyingglass.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Reveal \(file) in Finder")
                                .accessibilityLabel("Reveal \(file) in Finder")
                            }
                        }
                        Button("Open Review", action: onOpenReview)
                            .controlSize(.small)
                            .accessibilityIdentifier("grok-activity-open-review")
                    }
                    Text("Run receipts take over this panel as soon as a turn starts.")
                        .font(AppTheme.Typography.section)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .accessibilityIdentifier("grok-activity-idle-workspace")
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Activity").font(AppTheme.Typography.heading)
                    if snapshot != nil {
                        evidencePhaseBadge("Finished", color: .secondary)
                    } else if liveProjection != nil {
                        evidencePhaseBadge("Live", color: .accentColor)
                    }
                }
                Text(snapshot != nil ? "What the agent did" : liveProjection != nil
                    ? "Happening now — not final"
                    : "Workspace")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Hide activity inspector").accessibilityLabel("Hide activity inspector")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func evidencePhaseBadge(_ label: String, color: Color) -> some View {
        Text(label.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Evidence phase: \(label)")
    }

    private func liveSummaryCard(_ live: RunEvidenceLiveProjection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bolt.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("In progress")
                        .font(AppTheme.Typography.captionStrong)
                    Text("Observed receipts from the current process generation. Outcomes and usage are not settled.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    metric("Active workers", value: live.activeWorkerCount.formatted())
                    metric("Active tools", value: live.activeToolCount.formatted())
                }
                GridRow {
                    metric("Observed tools", value: live.tools.count.formatted())
                    metric("Artifacts", value: live.artifacts.count.formatted())
                }
            }
        }
        .padding(12)
        .grokGlassSurface(cornerRadius: AppTheme.Radius.large, emphasized: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Live run evidence. In progress, not settled. \(live.activeWorkerCount) active workers and \(live.activeToolCount) active tools."
        )
    }

    @ViewBuilder private func livePlan(_ live: RunEvidenceLiveProjection) -> some View {
        section("Current plan", systemImage: "list.bullet.clipboard") {
            if live.plan.isEmpty {
                emptyState("No structured plan reported for this turn.")
            } else {
                ForEach(live.plan) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(step.isCurrent ? Color.accentColor : Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(AppTheme.Typography.captionStrong).lineLimit(3)
                            Text(ActivitySidebarPresentation.activityStatus(step.status))
                                .font(AppTheme.Typography.section)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func liveArtifacts(_ live: RunEvidenceLiveProjection) -> some View {
        section("Files created so far", systemImage: "doc.badge.plus") {
            if live.artifacts.isEmpty {
                emptyState("No successful write receipts observed yet.")
            } else {
                ForEach(live.artifacts) { artifact in artifactRow(artifact) }
                Text("Observed during this turn; final run settlement is still pending.")
                    .font(AppTheme.Typography.section)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func liveWorkers(_ live: RunEvidenceLiveProjection) -> some View {
        section("Workers running", systemImage: "person.2") {
            if live.workers.isEmpty {
                emptyState("No authoritative worker lifecycle receipts observed yet.")
            } else {
                ForEach(live.workers) { worker in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(statusColor(worker.status)).frame(width: 6, height: 6).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(worker.title).font(AppTheme.Typography.captionStrong).lineLimit(2)
                            // A worker that already finished mid-turn carries its
                            // authoritative receipt; show it live, not only at settlement.
                            let detail = ActivitySidebarPresentation.workerReceiptDetail(
                                status: worker.status,
                                durationMilliseconds: worker.durationMilliseconds,
                                toolCallCount: worker.toolCallCount,
                                redactedError: worker.redactedError,
                                routedModel: worker.routedModel
                            )
                            if !detail.isEmpty {
                                Text(detail)
                                    .font(AppTheme.Typography.section)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            Text(ActivitySidebarPresentation.activityStatus(worker.status))
                                .font(AppTheme.Typography.section)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(workerAccessibilityLabel(worker))
                }
            }
        }
    }

    @ViewBuilder private func liveTools(_ live: RunEvidenceLiveProjection) -> some View {
        section("Tools running", systemImage: "wrench.and.screwdriver") {
            if live.tools.isEmpty {
                emptyState("No tool receipts observed yet.")
            } else {
                ForEach(live.tools) { tool in
                    // Tool-run inspector: the compact row expands to the full redacted
                    // receipt (already-redacted input detail plus authoritative MCP
                    // attribution) instead of a 180-character truncation dead end.
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            if let detail = tool.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(AppTheme.Typography.section)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text("No redacted input receipt for this call.")
                                    .font(AppTheme.Typography.section)
                                    .foregroundStyle(.secondary)
                            }
                            if let server = tool.mcpServerName {
                                Label("MCP server: \(server)", systemImage: "network")
                                    .font(AppTheme.Typography.section)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 14)
                        .padding(.top, 2)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(tool.isActive ? Color.accentColor : statusColor(tool.status))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.title).font(AppTheme.Typography.captionStrong).lineLimit(2)
                                Text(ActivitySidebarPresentation.liveToolMetadata(
                                    kind: tool.kind,
                                    status: tool.status,
                                    mcpServerName: tool.mcpServerName
                                ))
                                .font(AppTheme.Typography.section)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            }
                        }
                    }
                    .disclosureGroupStyle(.automatic)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Tool \(tool.title), \(ActivitySidebarPresentation.liveToolMetadata(kind: tool.kind, status: tool.status, mcpServerName: tool.mcpServerName))")
                    .accessibilityHint("Expands the redacted tool receipt.")
                }
            }
        }
    }

    @ViewBuilder private func liveRunDetails(_ live: RunEvidenceLiveProjection) -> some View {
        section("Session details", systemImage: "link") {
            if let goal = live.goalSummary { detailRow("Request", value: goal) }
            if let step = live.currentPlanStep { detailRow("Current plan", value: step.title) }
            detailRow("Process", value: live.process.state)
            if let model = live.process.model { detailRow("Model", value: model) }
            detailRow("Generation", value: live.binding.processGeneration.formatted())
            detailRow("Usage", value: "Available after settlement")
            ForEach(live.process.mcps) { mcp in detailRow(mcp.name, value: mcp.state) }
        }
    }

    private func summaryCard(_ snapshot: RunEvidenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: summarySymbol(snapshot))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(summaryColor(snapshot))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.outcome.displayName)
                        .font(AppTheme.Typography.captionStrong)
                    Text(summaryDetail(snapshot))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    metric("Workers", value: "\(snapshot.completedWorkerCount)/\(snapshot.workers.count)")
                    metric("Failed tools", value: snapshot.tools.failed.formatted())
                }
                GridRow {
                    metric("Artifacts", value: snapshot.artifacts.count.formatted())
                    metric("Usage", value: compactUsage(snapshot.usage))
                }
            }
        }
        .padding(12)
        .grokGlassSurface(cornerRadius: AppTheme.Radius.large, emphasized: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Run outcome: \(snapshot.outcome.displayName). \(summaryDetail(snapshot))")
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppTheme.Typography.captionStrong)
                .contentTransition(.numericText())
            Text(label)
                .font(AppTheme.Typography.section)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            AppTheme.Palette.accentSoft,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
        )
    }

    private func continuityCard(_ snapshot: RunEvidenceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Continuity needs review", systemImage: "exclamationmark.shield")
                .font(AppTheme.Typography.captionStrong).foregroundStyle(Color.orange)
            Text("\(snapshot.continuity.provenance) • \(snapshot.continuity.reason)")
                .font(AppTheme.Typography.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Continue as New") { confirmsContinueAsNew = true }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Review…", action: onReviewRecovery).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(11).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .overlay { RoundedRectangle(cornerRadius: AppTheme.Radius.large).stroke(Color.orange.opacity(0.24)) }
    }

    @ViewBuilder private func artifacts(_ snapshot: RunEvidenceSnapshot) -> some View {
        section("Artifacts", systemImage: "doc.badge.plus") {
            if snapshot.artifacts.isEmpty { emptyState("No successful writes reported for this run.") }
            else { ForEach(snapshot.artifacts) { artifact in artifactRow(artifact) } }
        }
    }

    @ViewBuilder private func reviewFiles(_ snapshot: RunEvidenceSnapshot) -> some View {
        section("Files in review", systemImage: "doc.on.doc") {
            if snapshot.gitReviewFiles.isEmpty { emptyState("No changed files observed yet.") }
            else {
                ForEach(snapshot.gitReviewFiles, id: \.self) { path in
                    Label(ActivitySidebarPresentation.displayPath(path, relativeTo: workspace), systemImage: "doc.text")
                        .font(AppTheme.Typography.caption).lineLimit(2).textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder private func workers(_ snapshot: RunEvidenceSnapshot) -> some View {
        section("Workers", systemImage: "person.2") {
            if snapshot.workers.isEmpty { emptyState("No workers reported.") }
            else {
                ForEach(snapshot.workers) { worker in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(statusColor(worker.status)).frame(width: 6, height: 6).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(worker.title).font(AppTheme.Typography.captionStrong).lineLimit(2)
                            let detail = ActivitySidebarPresentation.workerReceiptDetail(
                                status: worker.status,
                                durationMilliseconds: worker.durationMilliseconds,
                                toolCallCount: worker.toolCallCount,
                                redactedError: worker.redactedError,
                                routedModel: worker.routedModel
                            )
                            if !detail.isEmpty {
                                Text(detail)
                                    .font(AppTheme.Typography.section)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            Text(ActivitySidebarPresentation.activityStatus(worker.status))
                                .font(AppTheme.Typography.section)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(workerAccessibilityLabel(worker))
                }
            }
        }
    }

    private func workerAccessibilityLabel(_ worker: RunEvidenceSnapshot.Worker) -> String {
        let status = ActivitySidebarPresentation.activityStatus(worker.status)
        let detail = ActivitySidebarPresentation.workerReceiptDetail(
            status: worker.status,
            durationMilliseconds: worker.durationMilliseconds,
            toolCallCount: worker.toolCallCount,
            redactedError: worker.redactedError,
            routedModel: worker.routedModel
        )
        return detail.isEmpty
            ? "Worker \(worker.title). \(status)."
            : "Worker \(worker.title). \(status). \(detail)."
    }

    @ViewBuilder private func runDetails(_ snapshot: RunEvidenceSnapshot) -> some View {
        section("Run details", systemImage: "checkmark.seal") {
            if let goal = snapshot.goalSummary { detailRow("Request", value: goal) }
            if let step = snapshot.currentPlanStep { detailRow("Current plan", value: step.title) }
            detailRow("Outcome", value: snapshot.outcome.displayName)
            detailRow("Process", value: snapshot.process.state)
            detailRow("Continuity", value: snapshot.continuity.provenance)
            detailRow("Usage", value: usageLabel(snapshot.usage))
            detailRow("Next", value: snapshot.nextAction)
            if !snapshot.unresolvedErrors.isEmpty { detailRow("Unresolved", value: "\(snapshot.unresolvedErrors.count) reported") }
        }
    }

    @ViewBuilder private func toolStatus(_ snapshot: RunEvidenceSnapshot) -> some View {
        section("Tools and connections", systemImage: "wrench.and.screwdriver") {
            detailRow("Tools", value: "\(snapshot.tools.succeeded) succeeded • \(snapshot.tools.failed) failed")
            ForEach(snapshot.process.mcps) { mcp in detailRow(mcp.name, value: mcp.state) }
        }
    }

    private func usageLabel(_ usage: RunEvidenceSnapshot.Usage) -> String {
        let tokens = usage.totalTokens.map { $0.formatted() } ?? "Not reported"
        let calls = usage.modelCalls.map { "\($0) model calls" } ?? "model calls not reported"
        return "\(tokens) tokens • \(calls)"
    }

    private func compactUsage(_ usage: RunEvidenceSnapshot.Usage) -> String {
        guard let total = usage.totalTokens else { return "—" }
        if total >= 1_000_000 {
            return "\((Double(total) / 1_000_000).formatted(.number.precision(.fractionLength(1))))M"
        }
        if total >= 1_000 {
            return "\((Double(total) / 1_000).formatted(.number.precision(.fractionLength(1))))K"
        }
        return total.formatted()
    }

    private func summaryDetail(_ snapshot: RunEvidenceSnapshot) -> String {
        if snapshot.outcome == .completionReceiptMissing {
            return "The reply arrived, but the backend never confirmed the turn finished."
        }
        if snapshot.outcome == .userStopped {
            return "You stopped this run before it finished."
        }
        if snapshot.activeWorkerCount > 0 {
            return "\(snapshot.activeWorkerCount) \(snapshot.activeWorkerCount == 1 ? "worker" : "workers") still running."
        }
        if !snapshot.unresolvedErrors.isEmpty {
            return "Finished with \(snapshot.unresolvedErrors.count) unresolved \(snapshot.unresolvedErrors.count == 1 ? "error" : "errors")."
        }
        return "Everything finished and checked out."
    }

    private func summarySymbol(_ snapshot: RunEvidenceSnapshot) -> String {
        if snapshot.outcome == .completionReceiptMissing { return "exclamationmark.triangle" }
        if snapshot.outcome == .userStopped { return "stop.circle" }
        if snapshot.activeWorkerCount > 0 { return "bolt.circle" }
        if !snapshot.unresolvedErrors.isEmpty { return "checkmark.circle.badge.exclamationmark" }
        return "checkmark.circle"
    }

    private func summaryColor(_ snapshot: RunEvidenceSnapshot) -> Color {
        if snapshot.outcome == .completionReceiptMissing || !snapshot.unresolvedErrors.isEmpty {
            return .orange
        }
        if snapshot.outcome == .userStopped { return .secondary }
        return snapshot.activeWorkerCount > 0 ? .accentColor : .secondary
    }

    private func artifactRow(_ artifact: ChatStore.RunArtifact) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: artifact.location == .external ? "arrow.up.right.square" : "doc.text")
                .font(AppTheme.Typography.caption).foregroundStyle(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(ActivitySidebarPresentation.displayPath(artifact.path, relativeTo: workspace))
                    .font(AppTheme.Typography.captionStrong).lineLimit(3).textSelection(.enabled)
                Text("\(ActivitySidebarPresentation.artifactLocationLabel(artifact)) • \(artifact.status)")
                    .font(AppTheme.Typography.section).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { onRevealArtifact(artifact) } label: { Image(systemName: "folder") }
                .buttonStyle(.plain).help("Reveal artifact in Finder")
                .accessibilityLabel("Reveal \(artifact.path) in Finder")
        }
    }

    @ViewBuilder private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(AppTheme.Typography.captionStrong)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8, content: content)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(AppTheme.Typography.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(AppTheme.Typography.captionStrong).multilineTextAlignment(.trailing).lineLimit(3)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed", "complete", "success", "succeeded", "done": return .green
        case "failed", "error": return .red
        case "cancelled", "canceled", "stopped": return .secondary
        case "unknown", "orphaned", "not_settled": return .orange
        default: return .accentColor
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text).font(AppTheme.Typography.caption).foregroundStyle(.secondary)
    }
}
