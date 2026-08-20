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
        let chatView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        let welcomeState = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/WelcomeStateView.swift"),
            encoding: .utf8
        )
        let composer = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatComposer.swift"),
            encoding: .utf8
        )
        let source = chatView + "\n" + welcomeState + "\n" + composer

        XCTAssertTrue(source.contains("Text(\"What should we build?\")"))
        XCTAssertTrue(chatView.contains("WelcomeStateView("))
        XCTAssertFalse(chatView.contains("private var welcomeState"))
        XCTAssertTrue(source.contains("Text(\"Loading saved conversation…\")"))
        XCTAssertTrue(source.contains("private var restoredEmptyState"))
        XCTAssertTrue(welcomeState.contains("private struct WorkbenchIntentStarter"))
        XCTAssertTrue(welcomeState.contains("ForEach(WorkbenchIntent.defaults)"))
        XCTAssertTrue(chatView.contains("grok-composer-workspace-chip"))
        XCTAssertTrue(chatView.contains("grok-composer-branch-chip"))
        XCTAssertTrue(chatView.contains("GitService.currentBranch(in: workspace.path)"))
        // The welcome model pill was removed 2026-08-03 (redundant with the composer's
        // always-visible model menu); model choice must not reappear mid-canvas.
        XCTAssertFalse(source.contains("grok-starter-model-selector"))
        XCTAssertTrue(source.contains("TextField(\"Describe a task\""))
        XCTAssertTrue(source.contains("grok-send-startup-status"))
        XCTAssertTrue(source.contains("mode.displayName"))
        XCTAssertFalse(source.contains("default: return \"Agent\""),
                       "unknown ACP mode ids must not be relabeled Agent")
        XCTAssertFalse(source.contains("Text(\"Grok agent runs in this folder.\")"),
                       "welcome no longer repeats the folder-as-cwd line")
        XCTAssertTrue(source.contains("Text(item.detail)"),
                      "Ask/Build/Review starters explain their outcome before seeding the composer")
        XCTAssertTrue(source.contains("accessibilityLabel(\"\\(item.title). \\(item.detail)\")"))
        XCTAssertTrue(welcomeState.contains(".accessibilityRemoveTraits(.isSelected)"),
                      "intent starters must not inherit a stale selected trait")
        XCTAssertTrue(source.contains(".frame(width: 30, height: 30)"))
        XCTAssertTrue(source.contains(".font(.system(size: 30, weight: .medium))"))
        XCTAssertTrue(source.contains(".padding(.vertical, 40)"))
        XCTAssertFalse(source.contains("grok-task-context-strip"),
                       "the transient task-contract bar must not return below the header")
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
