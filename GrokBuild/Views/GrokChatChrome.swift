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
            .accessibilityLabel("Build agent is working")
    }
}

struct ThinkingBlock: View {
    let text: String
    let duration: TimeInterval?
    let isExpanded: Bool
    let isLive: Bool
    var onToggle: () -> Void

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

            if isExpanded, !text.isEmpty {
                Text(text)
                    .font(AppTheme.Typography.caption)
                    .lineSpacing(2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, 3)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if tool.detail == nil {
                rowLabel
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { isExpanded.toggle() }
                } label: {
                    rowLabel
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide tool details" : "Show tool details")
            }

            if isExpanded, let detail = tool.detail {
                Text(detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(tool.isFailed ? Color.red : Color.secondary)
                    .textSelection(.enabled)
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
            Text(tool.title)
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
        .accessibilityLabel("\(tool.title), \(statusLabel ?? tool.kind)")
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
        if tool.isFailed { return "Failed" }
        if tool.isComplete { return "Done" }
        if status == "in_progress" || status == "running" { return "Running" }
        if status == "pending" { return "Pending" }
        return status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var statusIconName: String {
        if tool.isFailed { return "exclamationmark.triangle.fill" }
        if tool.isComplete { return "checkmark.circle.fill" }
        return "circle.dotted"
    }

    private var statusColor: Color {
        if tool.isFailed { return .red }
        if tool.isComplete { return .green }
        return .secondary
    }
}

struct ToolActivityGroup: View {
    let tools: [ChatStore.LiveToolCall]
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

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tools) { tool in
                        ToolCallRow(tool: tool)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 3)
    }

    private var summaryTitle: String {
        let failures = tools.filter(\.isFailed).count
        if failures > 0 {
            return "Tool activity · \(failures) failed"
        }
        if tools.count == 1, let tool = tools.first {
            return tool.title
        }
        if browserToolCount == tools.count {
            return "Browser activity"
        }
        if browserToolCount > 0 {
            return "Tool activity · \(browserToolCount) browser"
        }
        return "Tool activity"
    }

    private var summaryIconName: String {
        browserToolCount > 0 ? "globe" : "wrench"
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
