import SwiftUI

struct MessageBubble: View {
    let message: Message
    /// When true, render assistant text plainly — `RichMessageView` re-parses the full
    /// body on every chunk and can freeze the UI on long streaming turns.
    var isStreaming: Bool = false
    /// Incrementally maintained by `ChatStore` per display flush. Passing it in keeps
    /// per-render work O(1); the batch `make` fallback covers a missing value only.
    var streamingPresentation: StreamingMarkdownPresentation? = nil
    var showsAssistantHeader: Bool = true

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 96)
                Text(message.content)
                    .textSelection(.enabled)
                    .font(AppTheme.Typography.body)
                    .lineSpacing(2)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        AppTheme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                            .stroke(AppTheme.Palette.glassBorder, lineWidth: 1)
                    }
                    .frame(maxWidth: 500, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(message.content)")
        case .assistant:
            if !message.content.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    if showsAssistantHeader {
                        Text("Build agent")
                            .font(AppTheme.Typography.section)
                            .foregroundStyle(AppTheme.Palette.textMuted)
                    }

                    if isStreaming {
                        // Settled bubbles must never pay for a streaming scan: the
                        // presentation is computed only on this branch, preferring the
                        // store's incremental value over the full-string fallback.
                        let presentation = streamingPresentation
                            ?? StreamingMarkdownPresentation.make(message.content)
                        if !presentation.visibleText.isEmpty {
                            Text(presentation.visibleText)
                                .textSelection(.enabled)
                                .font(AppTheme.Typography.body)
                                .lineSpacing(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let withheld = presentation.withheldConstruct {
                            Label(withheld.displayLabel, systemImage: "text.line.first.and.arrowtriangle.forward")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Palette.textMuted)
                                .accessibilityLabel(withheld.displayLabel)
                        }
                    } else {
                        RichMessageView(text: message.content, messageID: message.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
            }
        case .system:
            Text(message.content)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.Palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Note: \(message.content)")
        }
    }
}
