import XCTest
@testable import GrokBuild

/// Visual Quiet P4 — system accent settings must not recolor GrokBuild chrome.
final class VisualQuietAccentTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testWorkbenchSwiftSourcesDoNotInheritSystemAccentOrRawOrange() throws {
        let sourceRoot = repositoryRoot.appendingPathComponent("GrokBuild")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        let forbidden = [
            "Color.accentColor",
            ".foregroundStyle(.tint)",
            ".foregroundColor(.accentColor)",
            ".tint(.accentColor)",
            ".accentColor(",
            "Color.orange",
            ".foregroundStyle(.orange)",
            ".foregroundColor(.orange)",
            ".fill(.orange)",
            "NSColor.controlAccentColor",
            ".controlAccentColor",
            "NSColor.systemOrange",
            ".systemOrange",
            ".buttonStyle(.borderedProminent)",
            "BorderedProminentButtonStyle(",
        ]

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard fileURL.lastPathComponent != "AppTheme.swift" else { continue }
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(
                of: repositoryRoot.path + "/",
                with: ""
            )
            for token in forbidden {
                XCTAssertFalse(
                    text.contains(token),
                    "\(relativePath) must route \(token) through AppTheme semantics"
                )
            }
        }
    }

    func testSemanticAccentWarningLinkAndPrimaryActionOwnersAreExplicit() throws {
        let theme = try source("GrokBuild/AppTheme.swift")
        let richMessage = try source("GrokBuild/Views/RichMessageView.swift")

        XCTAssertTrue(theme.contains("static let accentNSColor = adaptiveNSColor("))
        XCTAssertTrue(theme.contains("static let accent = Color(nsColor: accentNSColor)"))
        XCTAssertTrue(theme.contains("static let accentForegroundNSColor = adaptiveNSColor("))
        XCTAssertTrue(theme.contains("static let accentForeground = Color(nsColor: accentForegroundNSColor)"))
        XCTAssertTrue(theme.contains("static let warningNSColor = adaptiveNSColor("))
        XCTAssertTrue(theme.contains("static let linkNSColor = adaptiveNSColor("))
        XCTAssertTrue(theme.contains("struct GrokProminentButtonStyle: ButtonStyle"))
        XCTAssertTrue(theme.contains(".fill(backgroundColor)"))
        XCTAssertTrue(theme.contains("AppTheme.Palette.accentForeground"))
        XCTAssertTrue(richMessage.contains("foregroundColor = AppTheme.Palette.link"))
    }

    func testAppKitAndPrimaryActionCallSitesUseTheThemeOwner() throws {
        let updatePanel = try source("GrokBuild/UpdatePanel.swift")
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let composerViews = try source("GrokBuild/Views/ComposerViews.swift")

        XCTAssertTrue(updatePanel.contains("button.bezelColor = AppTheme.Palette.accentNSColor"))
        XCTAssertTrue(updatePanel.contains("button.contentTintColor = AppTheme.Palette.accentForegroundNSColor"))
        XCTAssertTrue(chatView.contains("Button(action: onAddProject)"))
        XCTAssertTrue(chatView.contains(".buttonStyle(GrokProminentButtonStyle())"))
        XCTAssertTrue(composerViews.contains("Button(\"Set Goal\")"))
        XCTAssertTrue(composerViews.contains("Button(\"Approve & continue\")"))
        XCTAssertTrue(composerViews.contains(".buttonStyle(GrokProminentButtonStyle())"))
    }

    func testHighTrafficSurfacesUseOnlySemanticP4Tokens() throws {
        let highTrafficFiles = [
            "GrokBuild/Views/ChatView.swift",
            "GrokBuild/Views/ComposerViews.swift",
            "GrokBuild/Views/GrokChatChrome.swift",
            "GrokBuild/Views/ActivitySidebar.swift",
            "GrokBuild/Views/RichMessageView.swift",
            "GrokBuild/Views/LivePlanSpine.swift",
            "GrokBuild/Views/SlashAutocompleteView.swift",
            "GrokBuild/Views/PreviewPane.swift",
            "GrokBuild/Views/SessionDashboardPanel.swift",
            "GrokBuild/Views/SidebarView.swift",
        ]

        for path in highTrafficFiles {
            let text = try source(path)
            XCTAssertFalse(text.contains(".accentColor"), "\(path) retains a system accent leak")
            XCTAssertFalse(text.contains(".orange"), "\(path) retains a raw orange leak")
            XCTAssertFalse(text.contains(".borderedProminent"), "\(path) retains native prominent styling")
        }
    }
}
