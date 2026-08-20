import SwiftUI

struct MessageBubble: View {
    let message: Message
    /// When true, render assistant text plainly — `RichMessageView` re-parses the full
    /// body on every chunk and can freeze the UI on long streaming turns.
    var isStreaming: Bool = false
    /// Incrementally maintained by `ChatStore` per display flush. Passing it in keeps
    /// per-render work O(1); the batch `make` fallback covers a missing value only.
    var streamingPresentation: StreamingMarkdownPresentation? = nil
    /// Resume/recovery controls disappear while process and continuity state changes.
    /// Render one non-selectable, non-rich snapshot during that transaction so AppKit's
    /// selection overlay cannot feed back into the transcript LazyVStack layout.
    var isLayoutFrozen: Bool = false
    /// When false, keep rich Markdown but drop AppKit text selection. Auto-follow
    /// streaming and settlement use this instead of the plain-text freeze.
    var allowsTextSelection: Bool = true

    var body: some View {
        Group {
            bubbleContent
        }
        .environment(\.allowsTranscriptTextSelection, allowsTextSelection)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.role {
        case .user:
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("You")
                        .font(AppTheme.Typography.section)
                        .foregroundStyle(AppTheme.Palette.textMuted)
                    if isLayoutFrozen {
                        Text(message.content)
                            .font(AppTheme.Typography.body)
                            .lineSpacing(2)
                    } else {
                        Text(message.content)
                            .transcriptTextSelection()
                            .font(AppTheme.Typography.body)
                            .lineSpacing(2)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: 640, alignment: .leading)
                .background(
                    AppTheme.Palette.sidebarSelection,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(message.content)")
        case .assistant:
            if !message.content.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    if isLayoutFrozen {
                        Text(message.content)
                            .font(AppTheme.Typography.body)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Agent response: \(message.content)")
                    } else if isStreaming {
                        // Settled bubbles must never pay for a streaming scan: the
                        // presentation is computed only on this branch, preferring the
                        // store's incremental value over the full-string fallback.
                        let presentation = streamingPresentation
                            ?? StreamingMarkdownPresentation.make(message.content)
                        if !presentation.visibleText.isEmpty {
                            Text(presentation.visibleText)
                                .transcriptTextSelection()
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
                .padding(.bottom, 4)
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
