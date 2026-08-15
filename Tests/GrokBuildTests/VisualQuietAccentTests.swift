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
            "Color.orange",
            ".foregroundStyle(.orange)",
            ".buttonStyle(.borderedProminent)",
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

        XCTAssertTrue(theme.contains("static let accent = adaptive("))
        XCTAssertTrue(theme.contains("static let accentForeground = adaptive("))
        XCTAssertTrue(theme.contains("static let warningNSColor = adaptiveNSColor("))
        XCTAssertTrue(theme.contains("static let linkNSColor = adaptiveNSColor("))
        XCTAssertTrue(theme.contains("struct GrokProminentButtonStyle: ButtonStyle"))
        XCTAssertTrue(theme.contains(".fill(backgroundColor)"))
        XCTAssertTrue(theme.contains("AppTheme.Palette.accentForeground"))
        XCTAssertTrue(richMessage.contains("foregroundColor = AppTheme.Palette.link"))
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
