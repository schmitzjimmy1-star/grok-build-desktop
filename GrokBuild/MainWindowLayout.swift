import CoreGraphics

/// Shared main-window size policy for SwiftUI `WindowGroup` and AppKit reopen path.
enum MainWindowLayout {
    /// Comfortable floor so the sidebar and composer controls stay readable.
    static let minimumSize = CGSize(width: 1100, height: 720)
    /// Matches the default logical canvas of a 13-inch Apple Silicon MacBook Air.
    /// AppDelegate clamps this to the current screen's available frame.
    static let defaultSize = CGSize(width: 1440, height: 900)

    /// Composer fills the chat column (no artificial mid-width cap).
    static let composerMaxWidth: CGFloat = .infinity

    /// Launch as a proper primary workspace rather than a small floating utility.
    static func screenFillingFrame(visibleFrame: CGRect) -> CGRect {
        visibleFrame
    }
}

enum SidebarVisibility {
    static let storageKey = "grokbuild.sidebarVisible"
    static let defaultVisible = true

    /// Settings owns its own navigation and should use the full window instead of
    /// stacking a second sidebar beside the project sidebar.
    static func shouldShow(preference: Bool, settingsPresented: Bool) -> Bool {
        preference && !settingsPresented
    }
}
