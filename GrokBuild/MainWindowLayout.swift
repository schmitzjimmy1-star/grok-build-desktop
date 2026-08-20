import CoreGraphics
import Foundation

/// Shared main-window size policy for SwiftUI `WindowGroup` and AppKit reopen path.
enum MainWindowLayout {
    /// Comfortable floor so the sidebar and composer controls stay readable.
    static let minimumSize = CGSize(width: 1100, height: 720)
    /// Matches the default logical canvas of a 13-inch Apple Silicon MacBook Air.
    /// AppDelegate clamps this to the current screen's available frame.
    static let defaultSize = CGSize(width: 1440, height: 900)

    /// Launch as a proper primary workspace rather than a small floating utility.
    /// Applied only when no saved window frame exists; a user-resized frame is
    /// restored instead (see `AppDelegate.openMainWindow`).
    ///
    /// On displays smaller than `minimumSize` the frame is clamped up to the
    /// minimum with its top edge pinned to the visible area, so the title bar
    /// stays reachable even when the window must exceed the screen.
    static func screenFillingFrame(
        visibleFrame: CGRect,
        minimumSize: CGSize = minimumSize
    ) -> CGRect {
        let width = max(visibleFrame.width, minimumSize.width)
        let height = max(visibleFrame.height, minimumSize.height)
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.maxY - height,
            width: width,
            height: height
        )
    }
}

enum TitlebarMetrics {
    /// Clears the traffic lights in a transparent `fullSizeContentView` titlebar.
    static let trafficLightLeading: CGFloat = 78
    /// AppKit traffic-light row. The canvas ignores that safe area, so chrome
    /// has to clear it itself.
    static let systemTitlebarHeight: CGFloat = 32
    /// Workbench control row. Sits on the canvas just under the traffic lights
    /// so Dark titlebar vibrancy cannot crush the icons to canvas black.
    static let height: CGFloat = 32
    /// Small gap under the traffic-light row.
    static let belowTrafficLights: CGFloat = 8
    /// Space between the session title and the trailing header icons.
    static let headerIconGap: CGFloat = 16
    /// Extra air under the AppKit titlebar inset. Do not add
    /// `systemTitlebarHeight` here; SwiftUI still receives that safe area.
    static var contentTopInset: CGFloat { belowTrafficLights }
    /// Shared main-canvas header height.
    static var overlayTopInset: CGFloat { contentTopInset + height }
    /// Persistent Codex-style navigation rail width at ordinary window sizes.
    /// F5C keeps navigation useful without donating a quarter of the window to it.
    static let sidebarWidth: CGFloat = 248
    /// The rail draws under the titlebar; its brand row clears the traffic lights.
    static let sidebarHeaderHeight: CGFloat = 72
}

enum SidebarVisibility {
    static let storageKey = "grokbuild.sidebarVisible"
    static let defaultVisible = true

    /// Settings owns its own navigation and should use the full window instead of
    /// stacking a second sidebar beside the project sidebar.
    ///
    /// `availableContentWidth` wires the Slice 7 responsive order's second step:
    /// the sidebar auto-collapses when even its minimum width would compress the
    /// conversation below `ResponsiveLayoutPolicy.conversationReadableMinimum`.
    /// At the current 1100-pt window minimum this is unreachable by construction
    /// (1100 − 200 ≥ 812), so today the sidebar stays user-controlled; the wiring
    /// exists so any future smaller minimum collapses the sidebar before the
    /// transcript ever compresses.
    static func shouldShow(
        preference: Bool,
        settingsPresented: Bool,
        availableContentWidth: Double = .infinity
    ) -> Bool {
        preference
            && !settingsPresented
            && ResponsiveLayoutPolicy.sidebarFits(
                contentWidth: availableContentWidth,
                sidebarWidth: ResponsiveLayoutPolicy.sidebarMinimumWidth
            )
    }

    /// The persisted preference as ContentView's `@AppStorage` sees it: a
    /// missing key means the default, not `false`. Used by the View menu.
    static func currentPreference(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: storageKey) != nil else { return defaultVisible }
        return defaults.bool(forKey: storageKey)
    }
}
