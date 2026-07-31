import SwiftUI

struct GrokkingIndicator: View {
    /// When the current turn started; used to show elapsed time and a "warming up" hint.
    var startedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            let phase = Int(context.date.timeIntervalSince1970 / 0.45) % 3
            let elapsed = startedAt.map { max(0, context.date.timeIntervalSince($0)) }
            HStack(spacing: 4) {
                Text("Grokking")
                Text(String(repeating: ".", count: phase + 1))
                    .frame(width: 16, alignment: .leading)
                if let elapsed, elapsed >= 3 {
                    Text("· \(Int(elapsed))s")
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    // Local models can take a while to load on first use.
                    if elapsed >= 8 {
                        Text("· warming up the model may take a moment")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
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
                        .font(.system(size: 9, weight: .semibold))
                    Text(headerTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded, !text.isEmpty {
                Text(text)
                    .font(.system(size: 12))
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
    let title: String
    let kind: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(kind)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }

    private var iconName: String {
        let k = kind.lowercased()
        if k.contains("browser") { return "globe" }
        if k.contains("read") { return "doc.text" }
        if k.contains("edit") || k.contains("write") { return "pencil" }
        if k.contains("exec") || k.contains("run") || k.contains("terminal") { return "terminal" }
        return "wrench"
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tools) { tool in
                        ToolCallRow(title: tool.title, kind: tool.kind)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 3)
    }

    private var summaryTitle: String {
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
                .font(.system(size: 11, weight: .semibold))
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
