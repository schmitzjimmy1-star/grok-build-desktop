import SwiftUI

/// The quiet, pre-send canvas for a new session with an active workspace.
/// Selecting an intent only seeds the composer; ChatView remains the send gate.
struct WelcomeStateView: View {
    let workspaceName: String
    var onSelect: (WorkbenchIntent) -> Void

    var body: some View {
        VStack(spacing: 12) {
            GrokBrandMarkView()
                .frame(width: 24, height: 24)
            Text("What do you want to work on?")
                .font(AppTheme.Typography.heading)
            Text(workspaceName)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(WorkbenchIntent.defaults) { item in
                    CodexPromptPill(item: item) {
                        onSelect(item)
                    }
                }
            }
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
    }
}

/// Shared by the workspace welcome and the no-project state so the app mark has
/// one presentation owner while the states keep their independent layouts.
struct GrokBrandMarkView: View {
    var body: some View {
        Group {
            if let icon = GrokBrandIcon.mark() {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CodexPromptPill: View {
    let item: WorkbenchIntent
    var onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(item.title)
                    .font(AppTheme.Typography.label)
            }
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isHovered ? AppTheme.Palette.surfaceHover : AppTheme.Palette.surface,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.prompt)
        .accessibilityLabel("\(item.title). \(item.detail)")
        .accessibilityHint("Adds an editable \(item.title.lowercased()) request to the message composer.")
    }
}
