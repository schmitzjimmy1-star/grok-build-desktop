import AppKit
import XCTest
@testable import GrokBuild

/// Visual Quiet P5 — the app icon, dead workflow chrome, and bundled helpers
/// stay honest as the release package evolves.
final class VisualQuietBundleTests: XCTestCase {
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

    func testVectorIconMasterAndCommittedFallbackAreReleaseGrade() throws {
        let svg = try source("AppIcon.svg")
        let renderer = try source("scripts/render-app-icon.swift")
        let packaging = try source("scripts/build-macos-app.sh")
        let pngURL = repositoryRoot.appendingPathComponent("AppIcon.png")
        let pngData = try Data(contentsOf: pngURL)
        let representation = try XCTUnwrap(NSBitmapImageRep(data: pngData))

        XCTAssertTrue(svg.contains("viewBox=\"0 0 1024 1024\""))
        XCTAssertTrue(svg.contains("rx=\"218\""), "master should retain a native macOS squircle")
        XCTAssertEqual(representation.pixelsWide, 1024)
        XCTAssertEqual(representation.pixelsHigh, 1024)
        XCTAssertTrue(representation.hasAlpha)
        XCTAssertLessThan(pngData.count, 150_000, "fallback PNG should not be a bloated upscale")

        XCTAssertTrue(renderer.contains("let pixelSize = 1024"))
        XCTAssertTrue(renderer.contains("hasAlpha: true"))
        XCTAssertTrue(renderer.contains("representation(using: .png"))
        XCTAssertTrue(renderer.contains("options: .atomic"))
        XCTAssertTrue(packaging.contains("$ROOT_DIR/AppIcon.svg"))
        XCTAssertTrue(packaging.contains("scripts/render-app-icon.swift"))
        XCTAssertTrue(packaging.contains("$BUILD_DIR/AppIcon-master.png"))
        XCTAssertTrue(packaging.contains("test -s \"$APP_BUNDLE/Contents/Resources/AppIcon.icns\""))
        XCTAssertFalse(packaging.contains("iconutil -c icns \"$iconset_dir\" -o \"$APP_BUNDLE/Contents/Resources/AppIcon.icns\" >/dev/null 2>&1 || true"))
    }

    func testDeadWorkflowPillChromeIsGoneButRealWorkflowEntryPointsRemain() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let contentView = try source("GrokBuild/ContentView.swift")
        let settingsView = try source("GrokBuild/Views/SettingsView.swift")

        for deadSymbol in [
            "showWorkflowsPill",
            "workflowsStatusPill",
            "workflowMenuTitle",
            "onOpenWorkflowSettings",
            "workflowsEnabled",
        ] {
            XCTAssertFalse(chatView.contains(deadSymbol), "ChatView retained dead symbol \(deadSymbol)")
            XCTAssertFalse(contentView.contains(deadSymbol), "ContentView retained dead symbol \(deadSymbol)")
        }

        XCTAssertTrue(chatView.contains("@State private var showSavedWorkflows = false"))
        XCTAssertTrue(chatView.contains("@State private var showDeepResearch = false"))
        XCTAssertTrue(chatView.contains(".sheet(isPresented: $showSavedWorkflows)"))
        XCTAssertTrue(chatView.contains(".sheet(isPresented: $showDeepResearch)"))
        XCTAssertTrue(settingsView.contains("case workflows"), "Workflows must remain a first-class Settings pane")
    }

    func testComputerUseUpdaterAndSkillsRemainFirstClassPackageContents() throws {
        let packaging = try source("scripts/build-macos-app.sh")
        let packageManifest = try source("Package.swift")

        XCTAssertTrue(packaging.contains("ERROR: Missing GrokBuildComputerUseMCP helper binary"))
        XCTAssertTrue(packaging.contains("$SCRIPT_DIR/bundle-agent-desktop.sh"))
        XCTAssertTrue(packaging.contains("grokbuild-install-update.sh"))
        XCTAssertTrue(packaging.contains("GrokBuild/Resources/Skills"))
        XCTAssertTrue(packageManifest.contains("Resources/Skills/grokbuild-browser-control"))
        XCTAssertTrue(packageManifest.contains("Resources/Skills/grokbuild-computer-use"))
        XCTAssertTrue(packageManifest.contains("Resources/Skills/grokbuild-grok-web"))
    }
}
