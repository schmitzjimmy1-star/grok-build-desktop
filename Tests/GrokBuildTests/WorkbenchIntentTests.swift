import XCTest
@testable import GrokBuild

final class WorkbenchIntentTests: XCTestCase {
    func testDefaultsAreExactlyTheThreePlainLanguageIntents() {
        XCTAssertEqual(WorkbenchIntent.defaults.map(\.title), ["Ask", "Build", "Review"])
        XCTAssertEqual(WorkbenchIntent.defaults.count, 3)
    }

    func testEachIntentIsFullyPopulatedAndSeedsANormalEditableRequest() {
        for item in WorkbenchIntent.defaults {
            XCTAssertFalse(item.icon.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(item.detail.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(item.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(item.prompt.hasPrefix("/"), "\(item.title) should not start with a slash command")
        }
    }

    func testIntentsExplainOutcomesWithoutRequiringDeveloperVocabulary() {
        XCTAssertEqual(
            WorkbenchIntent.defaults.map(\.detail),
            [
                "Understand the project or get clear guidance.",
                "Create, change, or fix something with a safe plan.",
                "Check existing work and explain the best next step.",
            ]
        )
    }

    func testIntentIdentifiersAreStableAndUnique() {
        let identifiers = WorkbenchIntent.defaults.map(\.id)

        XCTAssertEqual(identifiers, ["Ask", "Build", "Review"])
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testQuietWorkbenchKeepsStarterModelChoiceAndDeveloperDetails() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Text(\"What would you like to do?\")"))
        XCTAssertTrue(source.contains("ForEach(WorkbenchIntent.defaults)"))
        // The welcome model pill was removed 2026-08-03 (redundant with the composer's
        // always-visible model menu); model choice must not reappear mid-canvas.
        XCTAssertFalse(source.contains("grok-starter-model-selector"))
        XCTAssertTrue(source.contains("TextField(\"Ask, build, or review…  / for skills\""))
        XCTAssertTrue(source.contains("@State private var showComposerDetails = false"))

        let primaryStart = try XCTUnwrap(source.range(of: "private var composerPrimaryControls"))
        let primaryEnd = try XCTUnwrap(source.range(of: "private var composerActionControls", range: primaryStart.upperBound..<source.endIndex))
        let primarySource = String(source[primaryStart.lowerBound..<primaryEnd.lowerBound])
        XCTAssertFalse(primarySource.contains("modeSelector"))
        XCTAssertTrue(primarySource.contains("composerMCPMenu"))
        XCTAssertTrue(primarySource.contains("composerCommandMenu"))
        XCTAssertTrue(primarySource.contains("composerDetailsToggle"))
        XCTAssertTrue(primarySource.contains("modelSelector"))

        // Details row: leading edge is pure telemetry (context + usage); agent mode
        // lives with the trailing action cluster beside review/Activity.
        let detailsStart = try XCTUnwrap(source.range(of: "private var composerDetailLeadingControls"))
        let detailsEnd = try XCTUnwrap(source.range(of: "private var composerDetailActionControls", range: detailsStart.upperBound..<source.endIndex))
        let detailsSource = String(source[detailsStart.lowerBound..<detailsEnd.lowerBound])
        XCTAssertFalse(detailsSource.contains("modeSelector"))
        XCTAssertFalse(detailsSource.contains("modelSelector"))
        XCTAssertTrue(detailsSource.contains("ContextUsageIndicator"))
    }
}
