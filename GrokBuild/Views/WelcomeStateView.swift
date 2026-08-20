import SwiftUI

/// The quiet, pre-send canvas for a new session with an active workspace.
/// Selecting an intent only seeds the composer; ChatView remains the send gate.
struct WelcomeStateView: View {
    let workspaceName: String
    var onSelect: (WorkbenchIntent) -> Void

    var body: some View {
        VStack(spacing: 18) {
            GrokBrandMarkView()
                .frame(width: 44, height: 44)
            VStack(spacing: 6) {
                Text("What should we build?")
                    .font(.system(size: 30, weight: .medium))
                Text("Start with a goal for \(workspaceName). You can edit it before anything runs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(WorkbenchIntent.defaults) { item in
                    WorkbenchIntentStarter(item: item) {
                        onSelect(item)
                    }
                }
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(.vertical, 40)
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
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkbenchIntentStarter: View {
    let item: WorkbenchIntent
    var onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(AppTheme.Typography.captionStrong)
                        .foregroundStyle(isHovered ? Color.primary : Color.primary.opacity(0.88))
                    Text(item.detail)
                        .font(AppTheme.Typography.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .background(
                isHovered ? AppTheme.Palette.surfaceHover : Color.clear,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.prompt)
        .accessibilityLabel("\(item.title). \(item.detail)")
        .accessibilityHint("Adds an editable \(item.title.lowercased()) request to the message composer.")
    }
}
