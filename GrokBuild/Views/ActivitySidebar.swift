import SwiftUI

/// Small, deterministic presentation helpers shared by the settled activity
/// drawer and the compact task pill. These helpers format existing receipts;
/// they do not decide lifecycle state.
enum ActivitySidebarPresentation {
    static func coordinationSummary(_ metrics: RunEvidenceSnapshot.CoordinationMetrics) -> String {
        "\(metrics.requestedChildCount) requested • \(metrics.spawnedChildCount) spawned • \(metrics.finishedChildCount) finished • max \(metrics.maximumUsefulConcurrency) concurrent"
    }

    static func coordinationUsage(_ metrics: RunEvidenceSnapshot.CoordinationMetrics) -> String? {
        let parts = [
            metrics.parentTotalTokens.map { "\($0.formatted()) parent tokens" },
            metrics.childTotalTokens.map { "\($0.formatted()) child tokens" },
            metrics.childToolCallCount.map { "\($0) child tool calls" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    static func summaryDetail(_ snapshot: RunEvidenceSnapshot) -> String {
        if snapshot.outcome == .failed {
            return "The backend confirmed that this turn ended with an error."
        }
        if snapshot.outcome == .cancelled {
            return "The backend confirmed that this turn was cancelled before completion."
        }
        if snapshot.outcome == .completionReceiptMissing {
            return "The reply arrived, but the backend never confirmed the turn finished."
        }
        if snapshot.outcome == .userStopped {
            return "You stopped this run before it finished."
        }
        if snapshot.activeWorkerCount > 0 {
            return "Turn completed; \(snapshot.activeWorkerCount) \(snapshot.activeWorkerCount == 1 ? "worker is" : "workers are") still active."
        }
        if snapshot.unresolvedWorkerCount > 0 {
            return "Turn completed; \(snapshot.unresolvedWorkerCount) worker \(snapshot.unresolvedWorkerCount == 1 ? "receipt remains" : "receipts remain") unresolved."
        }
        if !snapshot.unresolvedErrors.isEmpty {
            return "Turn completed with \(snapshot.unresolvedErrors.count) unresolved \(snapshot.unresolvedErrors.count == 1 ? "error" : "errors")."
        }
        return "Turn completed; no tool or worker failures were reported."
    }

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
            redactedError: activity.redactedError,
            childToolReceipts: activity.childToolReceipts,
            runtimeModelID: activity.runtimeModelID,
            childLedgerReadOutcome: activity.childLedgerReadOutcome
        )
    }

    static func workerReceiptDetail(
        status: String,
        durationMilliseconds: Int?,
        toolCallCount: Int?,
        redactedError: String?,
        childToolReceipts: [ChildToolReceipt]? = nil,
        runtimeModelID: String? = nil,
        routedModel: String? = nil,
        childLedgerReadOutcome: ChildLedgerReadOutcome? = nil
    ) -> String {
        var parts: [String] = []
        if let runtimeModelID, !runtimeModelID.isEmpty {
            parts.append("Ran on \(runtimeModelID) (Grok ACP)")
        }
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
        } else if normalized == "cancelled" {
            parts.append("Cancelled before finish")
        }
        if let redactedError {
            parts.append("Error: \(TranscriptTextPresentation.singleLine(redactedError, maxLength: 120))")
        } else if BackgroundActivityStatusPolicy.canonicalWorkerTerminalStatus(status) == "completed" {
            let toolCount = toolCallCount ?? 0
            if childLedgerReadOutcome == .unreadable {
                parts.append("Child ledger unreadable")
            } else if toolCount == 0 {
                if childLedgerReadOutcome == .empty {
                    parts.append("Child ledger confirmed zero tools")
                }
            } else if let childToolReceipts, childToolReceipts.count == toolCount {
                let succeeded = childToolReceipts.filter { $0.status == .succeeded }.count
                parts.append("Child receipts: \(succeeded)/\(toolCount) succeeded")
                let exercised = childToolReceipts.filter { $0.mcpReceiptRole == .invocation }
                    .compactMap { receipt -> String? in
                        guard let name = receipt.qualifiedToolName else { return nil }
                        let server = MCPQualifiedToolIdentity.serverName(from: name)
                        return server.map { "\(name) \(receipt.status.rawValue) via \($0)" }
                            ?? "\(name) \(receipt.status.rawValue)"
                    }
                parts.append(contentsOf: exercised)
            } else if childLedgerReadOutcome != .empty {
                parts.append("Child tool outcomes were not reported to the parent receipt")
            }
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
        case "cancelled", "canceled": return "Cancelled"
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
    /// Codex parity Slice 5: the compact grouped presentation (Subagents,
    /// Computer Use, Sources, Run details) built by `ContextInspectorProjection`.
    var inspector: ContextInspectorProjection.Model = .empty
    /// When true the panel mounts as a workbench column, not a floating overlay.
    var docked: Bool = false

    @State private var confirmsContinueAsNew = false
    /// The run-evidence ledger opens in view by default (owner decision,
    /// 2026-08-08): the collapsed disclosure hid the most information-dense
    /// receipts behind an extra click every time the inspector opened.
    @State private var showsExecutionReceipts = true
    @State private var subagentRowsExpanded = false

    var body: some View {
        // Codex parity Slice 5: a compact contextual inspector, not a dashboard.
        // Short optional sections; deep generation-bound receipts stay one
        // disclosure away under Run details. Recovery always outranks parity.
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot, snapshot.continuity.requiresRecoveryAction {
                    continuityCard(snapshot)
                }

                if let subagents = inspector.subagents {
                    subagentsSection(subagents)
                }

                // The Computer Use readiness note was removed from the inspector
                // (owner decision, 2026-08-08): it restated a feature toggle on
                // every open. The projection still carries the receipt
                // (`inspector.computerUse`) for tests and future surfaces;
                // Settings → Computer Use remains the control surface.

                if let capabilities = inspector.mcpCapabilities {
                    mcpCapabilitiesSection(capabilities)
                }

                if let sources = inspector.sources {
                    sourcesSection(sources)
                }

                if inspector.failedToolCount > 0 || !inspector.unresolvedErrors.isEmpty {
                    unresolvedErrorsLine
                }

                if inspector.hasRunDetails {
                    Divider()
                    DisclosureGroup(isExpanded: $showsExecutionReceipts) {
                        ScrollView {
                            runDetailsContent
                                .padding(.top, 10)
                        }
                        .frame(maxHeight: 360)
                    } label: {
                        Label("Run details", systemImage: "list.bullet.rectangle")
                            .font(AppTheme.Typography.captionStrong)
                    }
                    .accessibilityHint("Opens the generation-bound worker, tool, artifact, model, process, continuity, and usage receipts.")
                    .accessibilityIdentifier("grok-inspector-run-details")
                }

                if inspector.isEmpty {
                    Text("No activity for this task yet.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            // Escape closes the inspector without losing state (Slice 5 contract).
            Button("") { onClose() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        // Workbench W-1 (2026-08-08): a leaner overlay budget — the inspector is
        // a receipt surface, not a second canvas.
        .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(AppTheme.Palette.sidebar)
        .modifier(ActivitySidebarChrome(docked: docked))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run inspector")
        .accessibilityIdentifier("grok-run-inspector")
        .confirmationDialog("Continue this transcript as a new conversation?", isPresented: $confirmsContinueAsNew) {
            Button("Continue as New", role: .destructive, action: onContinueAsNew)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local messages stay in this tab. The previous backend is preserved, and no new backend starts until you send.")
        }
    }

    /// Compact Subagents section: status counts with an optional row disclosure.
    private func subagentsSection(_ subagents: ContextInspectorProjection.Subagents) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Subagents").font(AppTheme.Typography.captionStrong)
            DisclosureGroup(isExpanded: $subagentRowsExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(subagents.rows.prefix(ContextInspectorProjection.visibleSubagentRowLimit)) { row in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(row.isActive ? Color.green : AppTheme.Palette.textMuted)
                                .frame(width: 5, height: 5)
                            Text(row.name)
                                .font(AppTheme.Typography.caption)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(row.statusLabel)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if subagents.rows.count > ContextInspectorProjection.visibleSubagentRowLimit {
                        Text("\(subagents.rows.count - ContextInspectorProjection.visibleSubagentRowLimit) more in Run details")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text(subagents.compactLabel)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("grok-inspector-subagents")
        }
    }

    /// Sources/Context: attachments and requested MCPs are intents; only
    /// receipt-evidenced servers are labeled used.
    private func sourcesSection(_ sources: ContextInspectorProjection.Sources) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources").font(AppTheme.Typography.captionStrong)
            ForEach(sources.usedMCPServers) { item in
                sourceRow(item, systemImage: "checkmark.circle")
            }
            ForEach(sources.attachments) { item in
                sourceRow(item, systemImage: "paperclip")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grok-inspector-sources")
    }

    /// Five non-interchangeable MCP facts. Catalog discovery never receives a
    /// "used" checkmark, and a process-ready row never names a capability.
    private func mcpCapabilitiesSection(_ capabilities: ContextInspectorProjection.MCPCapabilities) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MCP evidence").font(AppTheme.Typography.captionStrong)
            ForEach(capabilities.requestedServers) { capabilityRow($0, systemImage: "circle.dotted") }
            ForEach(capabilities.configuredServers) { capabilityRow($0, systemImage: "gearshape") }
            ForEach(capabilities.processStates) { capabilityRow($0, systemImage: "bolt.horizontal.circle") }
            ForEach(capabilities.discoveredTools) { capabilityRow($0, systemImage: "magnifyingglass.circle") }
            ForEach(capabilities.exercisedTools) { capabilityRow($0, systemImage: "play.circle") }
            ForEach(capabilities.unavailableTools) { capabilityRow($0, systemImage: "questionmark.circle") }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grok-inspector-mcp-evidence")
    }

    private func capabilityRow(_ item: ContextInspectorProjection.SourceItem, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(AppTheme.Typography.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail = item.detail {
                    Text(detail)
                        .font(AppTheme.Typography.section)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label)\(item.detail.map { ", " + $0 } ?? "")")
    }

    private func sourceRow(_ item: ContextInspectorProjection.SourceItem, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(item.label)
                .font(AppTheme.Typography.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
        }
        .help(item.detail ?? item.label)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label)\(item.detail.map { ", " + $0 } ?? "")")
    }

    /// Failed tools and unresolved errors never disappear behind compactness.
    private var unresolvedErrorsLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(
                inspector.failedToolCount > 0
                    ? "\(inspector.failedToolCount) failed \(inspector.failedToolCount == 1 ? "tool" : "tools")"
                    : "Unresolved errors",
                systemImage: "exclamationmark.triangle"
            )
            .font(AppTheme.Typography.captionStrong)
            .foregroundStyle(.orange)
            ForEach(inspector.unresolvedErrors.indices, id: \.self) { index in
                Text(inspector.unresolvedErrors[index])
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityIdentifier("grok-inspector-unresolved")
    }

    /// The deep evidence stack, unchanged in content: settled snapshots keep the
    /// summary, artifacts, review files, workers, run/tool receipts; live turns
    /// keep the generation-bound live sections.
    @ViewBuilder private var runDetailsContent: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 14) {
                summaryCard(snapshot)
                if !snapshot.artifacts.isEmpty { artifacts(snapshot) }
                if !snapshot.gitReviewFiles.isEmpty { reviewFiles(snapshot) }
                if !snapshot.workers.isEmpty { workers(snapshot) }
                runDetails(snapshot)
                toolStatus(snapshot)
            }
        } else if let liveProjection {
            VStack(alignment: .leading, spacing: 14) {
                liveSummaryCard(liveProjection)
                if !liveProjection.plan.isEmpty { livePlan(liveProjection) }
                if !liveProjection.artifacts.isEmpty { liveArtifacts(liveProjection) }
                if !liveProjection.workers.isEmpty { liveWorkers(liveProjection) }
                if !liveProjection.tools.isEmpty { liveTools(liveProjection) }
                liveRunDetails(liveProjection)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Run inspector").font(AppTheme.Typography.heading)
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
            .help("Hide run inspector").accessibilityLabel("Hide run inspector")
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
                                childToolReceipts: worker.childToolReceipts,
                                runtimeModelID: worker.runtimeModelID,
                                routedModel: worker.routedModel,
                                childLedgerReadOutcome: worker.childLedgerReadOutcome
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
                    Text(ActivitySidebarPresentation.summaryDetail(snapshot))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // Workbench W-1: a trivial turn does not earn a 2×2 grid of zeros —
            // one quiet line carries the same truth. Any nonzero fact restores
            // the full grid.
            if snapshot.workers.isEmpty, snapshot.tools.failed == 0, snapshot.artifacts.isEmpty {
                // Successful tool runs are a receipt too — a 20-tool turn must
                // never read as "nothing happened".
                Text(snapshot.tools.total > 0
                    ? "\(compactUsage(snapshot.usage)) tokens · \(snapshot.tools.total) \(snapshot.tools.total == 1 ? "tool" : "tools") succeeded"
                    : "\(compactUsage(snapshot.usage)) tokens · no workers, tools, or artifacts")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.secondary)
            } else {
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
        }
        .padding(12)
        .grokGlassSurface(cornerRadius: AppTheme.Radius.large, emphasized: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Run outcome: \(snapshot.outcome.displayName). \(ActivitySidebarPresentation.summaryDetail(snapshot))"
        )
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
                // Workbench W-1: cap the list — the full set lives one click away
                // behind the header Review chip; the inspector shows the shape.
                ForEach(snapshot.gitReviewFiles.prefix(5), id: \.self) { path in
                    Label(ActivitySidebarPresentation.displayPath(path, relativeTo: workspace), systemImage: "doc.text")
                        .font(AppTheme.Typography.caption).lineLimit(2).textSelection(.enabled)
                }
                if snapshot.gitReviewFiles.count > 5 {
                    Text("\(snapshot.gitReviewFiles.count - 5) more — open Review in the header for the full list.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(.tertiary)
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
                                childToolReceipts: worker.childToolReceipts,
                                runtimeModelID: worker.runtimeModelID,
                                routedModel: worker.routedModel,
                                childLedgerReadOutcome: worker.childLedgerReadOutcome
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
            childToolReceipts: worker.childToolReceipts,
            runtimeModelID: worker.runtimeModelID,
            routedModel: worker.routedModel,
            childLedgerReadOutcome: worker.childLedgerReadOutcome
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
            if let coordination = snapshot.coordination {
                detailRow("Coordination", value: ActivitySidebarPresentation.coordinationSummary(coordination))
                if coordination.unresolvedIdentityCount > 0 {
                    detailRow("Unresolved identities", value: "\(coordination.unresolvedIdentityCount)")
                }
                if let usage = ActivitySidebarPresentation.coordinationUsage(coordination) {
                    detailRow("Parent / children", value: usage)
                }
                if let stop = coordination.stopToSettleMilliseconds {
                    detailRow("Stop to settle", value: ThreadRunSpinePresentation.durationLabel(stop))
                }
            }
            detailRow("Usage", value: usageLabel(snapshot.usage))
            let tokenSplit = [
                snapshot.usage.inputTokens.map { "\($0.formatted()) input" },
                snapshot.usage.outputTokens.map { "\($0.formatted()) output" },
                snapshot.usage.cachedReadTokens.map { "\($0.formatted()) cached read" },
                snapshot.usage.reasoningTokens.map { "\($0.formatted()) reasoning" },
            ].compactMap { $0 }
            if !tokenSplit.isEmpty {
                detailRow("Token split", value: tokenSplit.joined(separator: " • "))
            }
            if let duration = snapshot.usage.apiDurationMilliseconds {
                detailRow("Provider API time", value: ThreadRunSpinePresentation.durationLabel(duration))
            }
            if !snapshot.usage.modelUsage.isEmpty {
                detailRow(
                    "Models used",
                    value: snapshot.usage.modelUsage.map { usage in
                        let split = [
                            usage.totalTokens.map { "\($0.formatted()) total" },
                            usage.inputTokens.map { "\($0.formatted()) in" },
                            usage.outputTokens.map { "\($0.formatted()) out" },
                        ].compactMap { $0 }.joined(separator: " · ")
                        return split.isEmpty ? usage.modelID : "\(usage.modelID) · \(split)"
                    }.joined(separator: " • ")
                )
            }
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
        let cost = usage.costUsdTicks.map {
            " • \(SessionUsageLedger.dollars(Double($0) / 1_000_000_000)) provider-reported"
        } ?? ""
        return "\(tokens) tokens • \(calls)\(cost)"
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

    private func summarySymbol(_ snapshot: RunEvidenceSnapshot) -> String {
        if snapshot.outcome == .failed { return "xmark.octagon" }
        if snapshot.outcome == .cancelled { return "slash.circle" }
        if snapshot.outcome == .completionReceiptMissing { return "exclamationmark.triangle" }
        if snapshot.outcome == .userStopped { return "stop.circle" }
        if snapshot.activeWorkerCount > 0 { return "bolt.circle" }
        if snapshot.unresolvedWorkerCount > 0 || !snapshot.unresolvedErrors.isEmpty {
            return "checkmark.circle.badge.exclamationmark"
        }
        return "checkmark.circle"
    }

    private func summaryColor(_ snapshot: RunEvidenceSnapshot) -> Color {
        if snapshot.outcome == .failed { return .red }
        if snapshot.outcome == .cancelled
            || snapshot.outcome == .completionReceiptMissing
            || snapshot.unresolvedWorkerCount > 0
            || !snapshot.unresolvedErrors.isEmpty {
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

/// Overlay chrome reads as a floating card; docked chrome reads as a column.
private struct ActivitySidebarChrome: ViewModifier {
    let docked: Bool

    func body(content: Content) -> some View {
        if docked {
            content
                .overlay(alignment: .leading) {
                    Divider()
                }
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.composer, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.composer, style: .continuous)
                        .stroke(AppTheme.Palette.glassBorder)
                }
                .shadow(color: AppTheme.Palette.shadow, radius: 12, y: 4)
        }
    }
}
