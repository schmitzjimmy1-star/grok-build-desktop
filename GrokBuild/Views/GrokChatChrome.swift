import SwiftUI

struct GrokkingIndicator: View {
    /// Retained for call-site compatibility and future non-animated diagnostics.
    var startedAt: Date?

    var body: some View {
        // A TimelineView here used to tick inside the transcript's LazyVStack every
        // 450 ms. When a provider stayed silent, each tick forced another full layout;
        // on a long transcript SwiftUI never caught up and pinned a core at 100%.
        Text("Agent working…")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Agent working")
            .accessibilityValue("Waiting for the next result")
    }
}

struct ThinkingBlock: View {
    let summaryChunks: [String]
    let duration: TimeInterval?
    let isExpanded: Bool
    let isLive: Bool
    var onToggle: () -> Void
    @State private var showsMoreSummary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppTheme.Typography.badge)
                    Text(headerTitle)
                        .font(AppTheme.Typography.label)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide thinking" : "Show thinking")
            .accessibilityValue("\(headerTitle). \(isExpanded ? "Expanded" : "Collapsed")")
            .accessibilityHint("Reveals or hides the agent's reasoning summary.")

            if isExpanded, !summaryChunks.isEmpty {
                let presentation = ReasoningSummaryPresentation.make(
                    chunks: summaryChunks,
                    expanded: showsMoreSummary
                )
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(presentation.stages) { stage in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stage.kind.displayName)
                                .font(AppTheme.Typography.badge)
                                .foregroundStyle(.secondary)
                            Text(stage.text)
                                .font(AppTheme.Typography.caption)
                                .lineSpacing(2)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(stage.kind.displayName), reasoning summary stage \(stage.ordinal) of \(presentation.sourceStageCount)"
                        )
                        .accessibilityValue(stage.text)
                        .accessibilitySortPriority(Double(presentation.sourceStageCount - stage.ordinal))
                    }

                    if presentation.isTruncated || showsMoreSummary {
                        Button(showsMoreSummary ? "Show less summary" : "Show more summary") {
                            showsMoreSummary.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(AppTheme.Typography.caption)
                        .accessibilityHint("Changes the bounded number of visible reasoning summary stages.")

                        if showsMoreSummary, presentation.isTruncated {
                            Text("Showing the first \(presentation.stages.count) of \(presentation.sourceStageCount) public summary stages within the display limit.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, 3)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { showsMoreSummary = false }
        }
    }

    private var headerTitle: String {
        if isLive { return "Thinking…" }
        if let duration {
            let seconds = max(1, Int(duration.rounded()))
            return "Thought for \(seconds)s"
        }
        return "Thinking"
    }
}

struct ToolCallRow: View {
    let tool: ChatStore.LiveToolCall
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if tool.detail == nil {
                rowLabel
            } else {
                Button {
                    if reduceMotion {
                        isExpanded.toggle()
                    } else {
                        withAnimation(.easeOut(duration: 0.14)) { isExpanded.toggle() }
                    }
                } label: {
                    rowLabel
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide tool details" : "Show tool details")
            }

            if isExpanded, let detail = tool.detail {
                VStack(alignment: .leading, spacing: 5) {
                    if let target = tool.target {
                        Text("Target: \(target)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text(tool.isFailed ? "Error: \(detail)" : detail)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(tool.isFailed ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                    if let diagnostic = tool.diagnosticDetail {
                        DisclosureGroup("Diagnostic payload") {
                            Text(diagnostic)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .padding(.top, 3)
                        }
                        .font(.caption2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 22)
                .padding(.trailing, 4)
                .accessibilityLabel("Tool details: \(detail)")
            }
        }
        .padding(.vertical, 2)
    }

    private var rowLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(tool.isFailed ? Color.red : Color.secondary)
                .frame(width: 14)
            Text(ToolActionPresentation.title(rawTitle: tool.title, kind: tool.kind, status: tool.status))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(tool.isFailed ? Color.primary : Color.secondary)
                .lineLimit(1)
            Spacer()
            if let statusLabel {
                Label(statusLabel, systemImage: statusIconName)
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
            } else {
                Text(tool.kind)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if tool.detail != nil {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: ComposerControlMetrics.minimumHitTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ToolActionPresentation.title(rawTitle: tool.title, kind: tool.kind, status: tool.status)), \(statusLabel ?? tool.kind)")
        .accessibilityValue(tool.detail == nil ? "No additional details" : (isExpanded ? "Details expanded" : "Details collapsed"))
        .accessibilityHint(tool.detail == nil ? "Tool activity status." : "Reveals or hides tool details.")
    }

    private var iconName: String {
        let k = tool.kind.lowercased()
        if k.contains("browser") { return "globe" }
        if k.contains("read") { return "doc.text" }
        if k.contains("edit") || k.contains("write") { return "pencil" }
        if k.contains("exec") || k.contains("run") || k.contains("terminal") { return "terminal" }
        return "wrench"
    }

    private var statusLabel: String? {
        guard let status = tool.status?.lowercased() else { return nil }
        if tool.isRecovered { return "Failed · Recovered" }
        switch tool.terminalStatus {
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .stale: return "Stale"
        case .unknown: return "Unknown"
        case nil: break
        }
        if status == "in_progress" || status == "running" { return "Running" }
        if status == "pending" { return "Pending" }
        return status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var statusIconName: String {
        if tool.isRecovered { return "arrow.clockwise.circle.fill" }
        if tool.isFailed { return "exclamationmark.triangle.fill" }
        if tool.isComplete { return "checkmark.circle.fill" }
        return "circle.dotted"
    }

    private var statusColor: Color {
        if tool.isRecovered { return AppTheme.Palette.warning }
        if tool.isFailed { return .red }
        if tool.isComplete { return .green }
        return .secondary
    }
}

/// Clean-room presentation policy for the collapsed tool-activity row. It
/// borrows the useful product idea of describing *what kind of work happened*
/// instead of repeating a bare receipt count, while retaining GrokBuild's own
/// ACP-derived status and failure authority. Live command arguments stay behind
/// the explicit disclosure so a streaming summary never leaks them by accident.
enum ToolActivitySummaryPresentation {
    struct Item: Equatable {
        let title: String
        let kind: String
        let status: String?
        let isFailed: Bool
        let isRecovered: Bool
    }

    private enum Kind: Hashable {
        case read
        case edit
        case search
        case command
        case web
        case media
        case other
    }

    static func summary(for items: [Item], liveThought: Bool = false) -> String {
        let unresolvedFailures = items.filter { $0.isFailed && !$0.isRecovered }.count
        if unresolvedFailures > 0 {
            return "\(unresolvedFailures) tool \(unresolvedFailures == 1 ? "call" : "calls") failed"
        }

        if let active = items.last(where: { isActive($0.status) }) {
            return activeSummary(for: active)
        }
        if liveThought, items.isEmpty { return "Thinking…" }
        guard !items.isEmpty else { return "Tool activity" }

        var order: [Kind] = []
        var counts: [Kind: Int] = [:]
        for item in items {
            let itemKind = classify(item)
            if counts[itemKind] == nil { order.append(itemKind) }
            counts[itemKind, default: 0] += 1
        }
        return order.map { completedSummary(for: $0, count: counts[$0, default: 1]) }
            .joined(separator: " · ")
    }

    static func isActive(_ status: String?) -> Bool {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pending", "queued", "in_progress", "inprogress", "running": true
        default: false
        }
    }

    private static func activeSummary(for item: Item) -> String {
        switch classify(item) {
        case .read: "Reading \(safeTitle(item.title, fallback: "files"))"
        case .edit: "Editing \(safeTitle(item.title, fallback: "files"))"
        case .search: "Searching"
        case .command: "Running command"
        case .web: "Browsing"
        case .media: "Generating image"
        case .other: "Using \(safeTitle(item.title, fallback: "tool"))"
        }
    }

    private static func completedSummary(for kind: Kind, count: Int) -> String {
        switch kind {
        case .read: count == 1 ? "Read file" : "Read files"
        case .edit: count == 1 ? "Edited file" : "Edited files"
        case .search: "Searched"
        case .command: count == 1 ? "Ran command" : "Ran commands"
        case .web: "Browsed"
        case .media: count == 1 ? "Generated image" : "Generated images"
        case .other: count == 1 ? "Used tool" : "Used tools"
        }
    }

    private static func classify(_ item: Item) -> Kind {
        let haystack = "\(item.kind) \(item.title)".lowercased()
        if containsAny(haystack, ["imagine", "image", "media"]) { return .media }
        if containsAny(haystack, ["browser", "navigate", "fetch", "http", "web"]) { return .web }
        if containsAny(haystack, ["search", "find", "grep", "ripgrep"]) { return .search }
        if containsAny(haystack, ["edit", "write", "patch", "apply_patch"]) { return .edit }
        if containsAny(haystack, ["read", "inspect", "open_file"]) { return .read }
        if containsAny(haystack, ["execute", "exec", "terminal", "shell", "command", "run"]) { return .command }
        return .other
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains(where: value.contains)
    }

    private static func safeTitle(_ title: String, fallback: String) -> String {
        let value = TranscriptTextPresentation.singleLine(title, maxLength: 80)
        return value.isEmpty ? fallback : value
    }
}

struct ToolActivityGroup: View {
    let tools: [ChatStore.LiveToolCall]
    let turnOutcome: ChatStore.TurnOutcome?
    let isExpanded: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: summaryIconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    Text(summaryTitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(tools.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: ComposerControlMetrics.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide tool activity" : "Show tool activity")
            .accessibilityValue("\(summaryTitle), \(tools.count) \(tools.count == 1 ? "item" : "items")")
            .accessibilityHint("Reveals or hides the individual tool events.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tools) { tool in
                        ToolCallRow(tool: tool)
                    }
                }
                .padding(.leading, 20)
            }

            if let turnOutcome {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Run summary")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Label(
                            turnOutcome.displayName,
                            systemImage: turnOutcome == .completed ? "checkmark.circle" : "slash.circle"
                        )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if unresolvedFailureCount > 0 {
                        Text("Next: inspect the failed call details. A recovery label requires an explicit backend retry correlation.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 20)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Run summary: \(turnOutcome.displayName)")
                .accessibilityValue(unresolvedFailureCount == 0
                    ? "No unresolved tool failures"
                    : "\(unresolvedFailureCount) tool calls still need review")
            }
        }
        .padding(.vertical, 3)
    }

    private var summaryTitle: String {
        ToolActivitySummaryPresentation.summary(for: tools.map {
            .init(
                title: $0.title,
                kind: $0.kind,
                status: $0.status,
                isFailed: $0.isFailed,
                isRecovered: $0.isRecovered
            )
        })
    }

    private var summaryIconName: String {
        browserToolCount > 0 ? "globe" : "wrench"
    }

    private var unresolvedFailureCount: Int {
        tools.filter { $0.isFailed && !$0.isRecovered }.count
    }

    private var browserToolCount: Int {
        tools.filter { $0.kind.localizedCaseInsensitiveContains("browser") }.count
    }
}

/// Plain graphite close affordance for in-window panels. Sheets have no real
/// traffic lights on macOS, so the previous one-live-two-dead fake lights
/// read as a broken window and carried the app's only saturated red.
struct PanelCloseButton: View {
    var onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(AppTheme.Typography.section)
                .foregroundStyle(isHovered ? Color.primary : AppTheme.Palette.textMuted)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isHovered ? AppTheme.Palette.surfaceHover : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Close")
        .accessibilityLabel("Close")
        .keyboardShortcut(.cancelAction)
    }
}
