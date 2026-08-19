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

    @discardableResult
    private func run(_ executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        return text
    }

    func testVectorIconMasterAndCommittedFallbackAreReleaseGrade() throws {
        let svg = try source("AppIcon.svg")
        let renderer = try source("scripts/render-app-icon.swift")
        let packaging = try source("scripts/build-macos-app.sh")
        let provider = try source("GrokBuild/AppIconProvider.swift")
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
        XCTAssertTrue(packaging.contains("$SCRIPT_DIR/package-app-icon.sh"))
        XCTAssertFalse(provider.contains("Bundle.main.executableURL"), "stale .build icons must not outrank bundle resources")
        XCTAssertTrue(provider.contains("Bundle.main.path(forResource: name, ofType: \"icns\")"))
    }

    func testSharedIconPackagerProducesAllTenICNSRepresentations() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VisualQuietBundleTests")
            .appendingPathComponent(UUID().uuidString)
        let build = temporaryRoot.appendingPathComponent("build")
        let app = temporaryRoot.appendingPathComponent("GrokBuild.app")
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        _ = try run(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [
                repositoryRoot.appendingPathComponent("scripts/package-app-icon.sh").path,
                repositoryRoot.path,
                build.path,
                app.path,
            ]
        )

        let iconURL = app.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let image = try XCTUnwrap(NSImage(contentsOf: iconURL))
        XCTAssertTrue(image.isValid)
        XCTAssertEqual(
            image.representations.map { "\($0.pixelsWide)x\($0.pixelsHigh)" },
            ["1024x1024", "512x512", "512x512", "256x256", "256x256", "128x128", "64x64", "32x32", "32x32", "16x16"]
        )
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
        XCTAssertTrue(chatView.contains("showSavedWorkflows = true"), "Saved Workflows needs a surviving compact trigger")
        XCTAssertTrue(chatView.contains("Label(\"Saved Workflows…\", systemImage: \"doc.text\")"))
        XCTAssertTrue(settingsView.contains("case workflows"), "Workflows must remain a first-class Settings pane")
    }

    func testComputerUseUpdaterAndSkillsRemainFirstClassPackageContents() throws {
        let packaging = try source("scripts/build-macos-app.sh")
        let developmentPackaging = try source("scripts/build-dev-app.sh")
        let packageManifest = try source("Package.swift")

        XCTAssertTrue(packaging.contains("ERROR: Missing GrokBuildComputerUseMCP helper binary"))
        XCTAssertTrue(packaging.contains("$SCRIPT_DIR/bundle-agent-desktop.sh"))
        let bundler = try source("scripts/bundle-agent-desktop.sh")
        XCTAssertTrue(bundler.contains("${HOME}/.grokbuild/computer-use/agent-desktop"))
        let computerUse = try source("GrokBuild/Services/ComputerUseService.swift")
        XCTAssertTrue(computerUse.contains("/.grokbuild/computer-use/agent-desktop"))
        XCTAssertTrue(packaging.contains("grokbuild-install-update.sh"))
        XCTAssertTrue(packaging.contains("GrokBuild/Resources/Skills"))
        XCTAssertTrue(packageManifest.contains("Resources/Skills/grokbuild-browser-control"))
        XCTAssertTrue(packageManifest.contains("Resources/Skills/grokbuild-computer-use"))
        XCTAssertTrue(packageManifest.contains("Resources/Skills/grokbuild-grok-web"))
        XCTAssertTrue(developmentPackaging.contains("$SCRIPT_DIR/package-app-icon.sh"))
        XCTAssertTrue(developmentPackaging.contains("<key>CFBundleIconFile</key>"))
    }
}
