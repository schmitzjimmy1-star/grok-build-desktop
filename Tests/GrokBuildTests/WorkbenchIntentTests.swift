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

        XCTAssertTrue(source.contains("Text(\"What do you want to work on?\")"))
        XCTAssertTrue(source.contains("private struct CodexPromptPill"))
        XCTAssertTrue(source.contains("ForEach(WorkbenchIntent.defaults)"))
        // The welcome model pill was removed 2026-08-03 (redundant with the composer's
        // always-visible model menu); model choice must not reappear mid-canvas.
        XCTAssertFalse(source.contains("grok-starter-model-selector"))
        XCTAssertTrue(source.contains("TextField(\"Describe a task\""))
        XCTAssertTrue(source.contains("grok-send-startup-status"))
        XCTAssertTrue(source.contains("mode.displayName"))
        XCTAssertFalse(source.contains("default: return \"Agent\""),
                       "unknown ACP mode ids must not be relabeled Agent")
        XCTAssertTrue(source.contains("Text(\"Grok agent runs in this folder.\")"))
        XCTAssertTrue(source.contains("Text(item.detail)"))
        XCTAssertTrue(source.contains("private var showsTaskContextStrip"))
        XCTAssertFalse(source.contains("Text(\"Recent tasks\")"))
        XCTAssertFalse(source.contains("showComposerDetails"))

        // The leading cluster is add/context then run mode; the trailing cluster
        // is model, voice, send. No Details toggle anywhere.
        let primaryStart = try XCTUnwrap(source.range(of: "private var composerPrimaryControls"))
        let primaryEnd = try XCTUnwrap(source.range(of: "private var composerAddMenu", range: primaryStart.upperBound..<source.endIndex))
        let primarySource = String(source[primaryStart.lowerBound..<primaryEnd.lowerBound])
        XCTAssertTrue(primarySource.contains("composerAddMenu"))
        XCTAssertTrue(primarySource.contains("modeSelector"))
        XCTAssertFalse(primarySource.contains("composerDetailsToggle"))

        // Telemetry relocated to the model popover: context, usage, and the
        // generation-bound route/process/model receipt remain reachable.
        XCTAssertTrue(source.contains("Section(\"Session telemetry\")"))
        XCTAssertTrue(source.contains("grok-model-route-contract"))
        XCTAssertTrue(source.contains("Route, process, and model receipt"))
    }
}
