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
        redactedError: String?
    ) -> String {
        var parts: [String] = []
        if let durationMilliseconds {
            let seconds = Double(durationMilliseconds) / 1_000
            parts.append(seconds >= 60
                ? "\((seconds / 60).formatted(.number.precision(.fractionLength(1)))) min"
                : "\(seconds.formatted(.number.precision(.fractionLength(1)))) sec")
        }
        if let toolCallCount { parts.append("\(toolCallCount) tools") }
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "unknown" {
            parts.append("Terminal status not reported")
        } else if normalized == "orphaned" {
            parts.append("Terminal receipt not reported")
        }
        if let redactedError {
            parts.append("Error: \(TranscriptTextPresentation.singleLine(redactedError, maxLength: 120))")
        }
        return parts.joined(separator: " • ")
    }

    static func activityStatus(_ status: String) -> String {
        let clean = TranscriptTextPresentation.singleLine(status, maxLength: 48)
        guard !clean.isEmpty else { return "Running" }
        switch clean.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "unknown": return "Unknown — status not reported"
        case "orphaned": return "Orphaned — terminal status not reported"
        case "not_settled", "status_not_settled": return "Status not settled"
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
                        artifacts(snapshot)
                        reviewFiles(snapshot)
                        workers(snapshot)
                        DisclosureGroup(isExpanded: $showsExecutionReceipts) {
                            VStack(alignment: .leading, spacing: 14) {
                                runDetails(snapshot)
                                toolStatus(snapshot)
                            }
                            .padding(.top, 10)
                        } label: {
                            Label("Execution receipts", systemImage: "list.bullet.rectangle")
                                .font(AppTheme.Typography.captionStrong)
                        }
                        .accessibilityHint("Shows model, process, continuity, usage, and MCP receipts.")
                    }
                    .padding(14)
                }
            } else if let liveProjection {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        liveSummaryCard(liveProjection)
                        livePlan(liveProjection)
                        liveArtifacts(liveProjection)
                        liveWorkers(liveProjection)
                        liveTools(liveProjection)
                        liveRunDetails(liveProjection)
                    }
                    .padding(14)
                }
            } else {
                ContentUnavailableView(
                    "No settled run evidence",
                    systemImage: "checkmark.seal",
                    description: Text("Run details appear here after the parent turn settles.")
                )
                .padding()
            }
        }
        .frame(minWidth: 300, idealWidth: 330, maxWidth: 400, maxHeight: .infinity)
        .background(AppTheme.Palette.sidebar)
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1) }
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

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Activity").font(AppTheme.Typography.heading)
                    if snapshot != nil {
                        evidencePhaseBadge("Settled", color: .secondary)
                    } else if liveProjection != nil {
                        evidencePhaseBadge("Live", color: .accentColor)
                    }
                }
                Text(snapshot != nil ? "Authoritative run evidence" : liveProjection != nil
                    ? "Current receipts — not settled"
                    : "Run evidence")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "chevron.right")
                    .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Hide activity sidebar").accessibilityLabel("Hide activity sidebar")
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
        section("Observed artifacts", systemImage: "doc.badge.plus") {
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
        section("Live workers", systemImage: "person.2") {
            if live.workers.isEmpty {
                emptyState("No authoritative worker lifecycle receipts observed yet.")
            } else {
                ForEach(live.workers) { worker in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(statusColor(worker.status)).frame(width: 6, height: 6).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(worker.title).font(AppTheme.Typography.captionStrong).lineLimit(2)
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
        section("Live tools", systemImage: "wrench.and.screwdriver") {
            if live.tools.isEmpty {
                emptyState("No tool receipts observed yet.")
            } else {
                ForEach(live.tools) { tool in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tool.isActive ? Color.accentColor : statusColor(tool.status))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.title).font(AppTheme.Typography.captionStrong).lineLimit(2)
                            Text(liveToolMetadata(tool))
                                .font(AppTheme.Typography.section)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if let detail = tool.detail {
                                Text(TranscriptTextPresentation.singleLine(detail, maxLength: 180))
                                    .font(AppTheme.Typography.section)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private func liveRunDetails(_ live: RunEvidenceLiveProjection) -> some View {
        section("Live binding", systemImage: "link") {
            if let goal = live.goalSummary { detailRow("Request", value: goal) }
            if let step = live.currentPlanStep { detailRow("Current plan", value: step.title) }
            detailRow("Process", value: live.process.state)
            if let model = live.process.model { detailRow("Model", value: model) }
            detailRow("Generation", value: live.binding.processGeneration.formatted())
            detailRow("Usage", value: "Available after settlement")
            ForEach(live.process.mcps) { mcp in detailRow(mcp.name, value: mcp.state) }
        }
    }

    private func liveToolMetadata(_ tool: RunEvidenceLiveProjection.Tool) -> String {
        let kind = tool.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kind.isEmpty, kind.lowercased() != "other" else { return tool.status }
        return "\(kind) • \(tool.status)"
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
        section("Run artifacts", systemImage: "doc.badge.plus") {
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
                                redactedError: worker.redactedError
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
            redactedError: worker.redactedError
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
        section("Tool and MCP status", systemImage: "wrench.and.screwdriver") {
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
            return "The prompt returned, but ACP did not report the terminal lifecycle receipt."
        }
        if snapshot.outcome == .userStopped {
            return "The active local process was stopped before a backend completion receipt."
        }
        if snapshot.activeWorkerCount > 0 {
            return "\(snapshot.activeWorkerCount) workers still active."
        }
        if !snapshot.unresolvedErrors.isEmpty {
            return "Settled with \(snapshot.unresolvedErrors.count) unresolved errors."
        }
        return "All reported lifecycle receipts have settled."
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
