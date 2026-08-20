import Foundation

/// Codex parity Slice 7 — pure responsive thresholds derived from available
/// conversation width. Order of sacrifice when space runs out:
/// 1. the contextual inspector overlay yields first (collapsed strip below 900);
/// 2. the sidebar collapses next;
/// 3. the transcript never compresses below its readable minimum.
enum ResponsiveLayoutPolicy {
    /// Minimum chat-area width at which the bounded top-trailing activity canvas
    /// overlay can be shown without covering most of the reading column.
    /// Below this the overlay stands down and an open inspector becomes a
    /// collapsed strip; the user's open/closed state is preserved and the
    /// panel returns when the window widens.
    static let inspectorMinimumChatWidth: Double = 900

    /// P3D (2026-08-15): the live-worker surface is a 340-pt activity canvas,
    /// not the old 260-pt receipt rail. Dock only when the full canvas plus its
    /// breathing room still leaves the 812-pt readable transcript. Below that,
    /// use the bounded overlay; below 900, collapse to the named worker control.
    static let inspectorDockMinimumChatWidth: Double = 1180

    static let activityCanvasWidth: CGFloat = 340

    /// The transcript's readable minimum: the 760-pt reading column plus its
    /// 26-pt horizontal padding on each side.
    static let conversationReadableMinimum: Double = 812

    /// The narrowest the project sidebar can render. Auto-collapse triggers only
    /// when even this minimum would compress the conversation below its readable
    /// minimum, so a user-chosen wider sidebar never flips visibility by itself.
    /// F3 (2026-08-20): the persistent Codex-style rail gives long project and
    /// session names room while leaving the conversation usable at the floor.
    static let sidebarMinimumWidth: Double = 280

    /// Ignore sub-point geometry jitter. Writing `@State` on every 0.01-pt
    /// `onGeometryChange` rebuilds ChatView, including the transcript
    /// ScrollView, and pins a core at 100% (2026-08-14 installed sample).
    static let measuredWidthEpsilon: Double = 1

    /// Keep the current inspector chrome across the 900 / 1,180 thresholds so
    /// overlay ↔ dock ↔ strip cannot chase a noisy measurement.
    static let inspectorHysteresis: Double = 16

    /// One of three mutually exclusive inspector mounts. Unmeasured (`.infinity`)
    /// starts docked so the default 1440×900 window does not flash overlay.
    enum InspectorPlacement: Equatable {
        case collapsedStrip
        case overlay
        case dockedColumn
    }

    static func inspectorFits(chatAreaWidth: Double) -> Bool {
        chatAreaWidth >= inspectorMinimumChatWidth
    }

    /// Whether the open inspector mounts as a docked third column instead of a
    /// top-trailing overlay. The measured width must include the docked column
    /// itself (the whole chat area), or docking would shrink the measurement
    /// and immediately undock — an oscillation, not a layout.
    static func inspectorDocks(chatAreaWidth: Double) -> Bool {
        chatAreaWidth >= inspectorDockMinimumChatWidth
    }

    static func shouldCommitMeasuredWidth(current: Double, next: Double) -> Bool {
        if current.isNaN || next.isNaN { return current.isNaN != next.isNaN }
        if current.isInfinite || next.isInfinite { return current != next }
        return abs(current - next) >= measuredWidthEpsilon
    }

    static func inspectorPlacement(
        chatAreaWidth: Double,
        current: InspectorPlacement
    ) -> InspectorPlacement {
        if chatAreaWidth.isInfinite || chatAreaWidth.isNaN {
            return .dockedColumn
        }
        switch current {
        case .dockedColumn:
            if chatAreaWidth >= inspectorDockMinimumChatWidth - inspectorHysteresis {
                return .dockedColumn
            }
            if chatAreaWidth >= inspectorMinimumChatWidth - inspectorHysteresis {
                return .overlay
            }
            return .collapsedStrip
        case .overlay:
            if chatAreaWidth >= inspectorDockMinimumChatWidth {
                return .dockedColumn
            }
            if chatAreaWidth >= inspectorMinimumChatWidth - inspectorHysteresis {
                return .overlay
            }
            return .collapsedStrip
        case .collapsedStrip:
            if chatAreaWidth >= inspectorDockMinimumChatWidth {
                return .dockedColumn
            }
            if chatAreaWidth >= inspectorMinimumChatWidth {
                return .overlay
            }
            return .collapsedStrip
        }
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
