import SwiftUI

/// Contextual header Review control. Rendered only when the generation-bound
/// Git snapshot reports changed files, or the pane is already open so it can
/// always be closed from the header. It targets the real Git review split —
/// the same `onToggleReview` destination the changed-files entry uses — never
/// a duplicate surface. ChatView still owns the count and visibility; this
/// view only renders the control.
struct ChatHeaderReviewToggle: View {
    let reviewFileCount: Int
    let isReviewVisible: Bool
    var onToggleReview: () -> Void

    var body: some View {
        if reviewFileCount > 0 || isReviewVisible {
            Button(action: onToggleReview) {
                HStack(spacing: 3) {
                    TitlebarGlyph(systemName: "doc.on.doc")
                    if reviewFileCount > 0 {
                        Text("\(reviewFileCount)")
                            .font(AppTheme.Typography.caption)
                    }
                }
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(GrokChromeButtonStyle())
            .foregroundStyle(AppTheme.Palette.titlebarControl)
            .help(isReviewVisible
                ? "Hide the Git review pane"
                : "Show the Git review pane. Counts refresh at selection and turn boundaries.")
            .accessibilityLabel(isReviewVisible ? "Hide changed files review" : "Show changed files review")
            .accessibilityValue("\(reviewFileCount) changed \(reviewFileCount == 1 ? "file" : "files")")
            .accessibilityHint("Counts refresh when you switch sessions or a turn completes, not on external edits.")
            .accessibilityIdentifier("grok-header-review-toggle")
        }
    }
}
