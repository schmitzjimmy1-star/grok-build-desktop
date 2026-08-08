import Foundation

/// Codex parity Slice 7 — pure responsive thresholds derived from available
/// conversation width. Order of sacrifice when space runs out:
/// 1. the contextual inspector hides first;
/// 2. the sidebar collapses next;
/// 3. the transcript never compresses below its readable minimum.
enum ResponsiveLayoutPolicy {
    /// Minimum chat-area width at which the 260-pt top-trailing inspector
    /// overlay can be shown without covering most of the reading column.
    /// Below this the inspector hides first; the user's open/closed state is
    /// preserved and the panel returns when the window widens.
    static let inspectorMinimumChatWidth: Double = 900

    /// The transcript's readable minimum: the 760-pt reading column plus its
    /// 26-pt horizontal padding on each side.
    static let conversationReadableMinimum: Double = 812

    /// The narrowest the project sidebar can render. Auto-collapse triggers only
    /// when even this minimum would compress the conversation below its readable
    /// minimum, so a user-chosen wider sidebar never flips visibility by itself.
    /// Workbench W-1 (2026-08-08): 220 → 200; the rail is navigation, not a pane.
    static let sidebarMinimumWidth: Double = 200

    static func inspectorFits(chatAreaWidth: Double) -> Bool {
        chatAreaWidth >= inspectorMinimumChatWidth
    }

    /// Whether the sidebar can stay visible without compressing the
    /// conversation below its readable minimum. With the current 1100-pt
    /// window minimum and 220–280-pt sidebar this stays true, so the sidebar
    /// remains user-controlled; the policy exists so any future smaller
    /// minimum collapses the sidebar before the transcript.
    static func sidebarFits(contentWidth: Double, sidebarWidth: Double) -> Bool {
        contentWidth - sidebarWidth >= conversationReadableMinimum
    }
}
