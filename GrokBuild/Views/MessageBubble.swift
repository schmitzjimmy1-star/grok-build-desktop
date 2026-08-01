import SwiftUI

struct MessageBubble: View {
    let message: Message
    /// When true, render assistant text plainly — `RichMessageView` re-parses the full
    /// body on every chunk and can freeze the UI on long streaming turns.
    var isStreaming: Bool = false

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
                    Text("Build agent")
                        .font(AppTheme.Typography.section)
                        .foregroundStyle(AppTheme.Palette.textMuted)

                    if isStreaming {
                        Text(message.content)
                            .textSelection(.enabled)
                            .font(AppTheme.Typography.body)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        RichMessageView(text: message.content)
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
