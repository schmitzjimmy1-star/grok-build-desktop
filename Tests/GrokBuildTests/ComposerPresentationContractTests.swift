import XCTest
@testable import GrokBuild

/// Codex parity Slice 4 — the plan-named `ComposerPresentationContract` suite.
///
/// Proves three things about the replaced composer: every authoring control is
/// present in the Codex shape, the Details shelf is gone in every spelling, and
/// each piece of relocated telemetry remains reachable from its new truthful
/// home (model popover, header, inline card, or project menu).
final class ComposerPresentationContractTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func chromeSource() throws -> String {
        try [
            "GrokBuild/Views/ChatView.swift",
            "GrokBuild/Views/ChatTopBar.swift",
            "GrokBuild/Views/ChatComposer.swift",
            "GrokBuild/Views/ChatHeaderReviewToggle.swift",
        ].map(source).joined(separator: "\n")
    }

    func testAuthoringControlsArePresentInTheCodexShape() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let chrome = try chromeSource()

        // One rounded surface with the Describe a task editor on top…
        XCTAssertTrue(chrome.contains("TextField(\"Describe a task\""))
        XCTAssertTrue(chrome.contains("ComposerDensityPolicy.minimumLineCount...ComposerDensityPolicy.maximumLineCount"),
                      "one-line idle height growing to the existing eight-line cap")
        XCTAssertTrue(chrome.contains(".grokGlassSurface("),
                      "the composer keeps its single rounded surface")

        // …and a bottom row of immediate authoring/run controls only.
        XCTAssertTrue(chatView.contains("private var composerAddMenu"))
        XCTAssertTrue(chrome.contains("grok-mode-selector"))
        XCTAssertTrue(
            chatView.contains("if !store.availableModes.isEmpty"),
            "the mode control is hidden when ACP advertised no session modes"
        )
        XCTAssertTrue(chrome.contains("grok-model-effort-selector"))
        XCTAssertTrue(chatView.contains("MicButton("))
        XCTAssertTrue(chatView.contains("sessionActionButton"))

        // Chips render inside the composer envelope, not a detached toolbar.
        let composer = try source("GrokBuild/Views/ChatComposer.swift")
        XCTAssertTrue(composer.contains("struct ChatComposer"))
        XCTAssertTrue(composer.contains("FileChipBar("))
        XCTAssertTrue(composer.contains("PromptMCPChipBar("))
    }

    func testVisualQuietDensityKeepsTargetsWhileReducingCardWeight() throws {
        XCTAssertEqual(ComposerControlMetrics.minimumHitTarget, 36)
        XCTAssertEqual(ComposerDensityPolicy.editorMinimumHeight, 36)
        XCTAssertEqual(ComposerDensityPolicy.minimumLineCount, 1)
        XCTAssertEqual(ComposerDensityPolicy.maximumLineCount, 8)
        XCTAssertEqual(ComposerDensityPolicy.surfaceHorizontalPadding, 11)
        XCTAssertEqual(ComposerDensityPolicy.surfaceVerticalPadding, 7)
        XCTAssertEqual(ComposerDensityPolicy.outerHorizontalPadding, 20)
        XCTAssertEqual(ComposerDensityPolicy.outerVerticalPadding, 5)
        XCTAssertFalse(ComposerDensityPolicy.surfaceHasShadow)

        let composer = try source("GrokBuild/Views/ChatComposer.swift")
        XCTAssertTrue(composer.contains("ComposerDensityPolicy.surfaceVerticalPadding"))
        XCTAssertTrue(composer.contains("ComposerDensityPolicy.outerVerticalPadding"))
        XCTAssertTrue(composer.contains("shadowed: ComposerDensityPolicy.surfaceHasShadow"))
    }

    func testDetailsShelfIsAbsentInEverySpelling() throws {
        let chrome = try chromeSource()
        for forbidden in [
            "showComposerDetails",
            "composerDetailsToggle",
            "composerDetailsDisclosure",
            "composerDetailsAccessibilityValue",
            "composerCenterHint",
            "grok-composer-details-toggle",
            "private var projectStatusRow",
            "private var reviewControls",
            "⏎ send",
        ] {
            XCTAssertFalse(chrome.contains(forbidden),
                           "Details residue `\(forbidden)` must not return under the composer")
        }
    }

    func testRelocatedTelemetryRemainsReachableFromTruthfulHomes() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let chrome = try chromeSource()

        // Model popover: context budget, settled usage, route/process receipt.
        XCTAssertTrue(chatView.contains("Section(\"Session telemetry\")"))
        XCTAssertTrue(chatView.contains("store.currentModelContextLabel"))
        XCTAssertTrue(chatView.contains("store.sessionUsageSummary"))
        XCTAssertTrue(chatView.contains("Route, process, and model receipt"))
        XCTAssertTrue(chatView.contains("store.sessionReceiptDetailLines"))
        XCTAssertTrue(chatView.contains("grok-model-route-contract"))

        // Header: Review state and the inspector toggle (Slice 2 homes).
        XCTAssertTrue(chrome.contains("grok-header-review-toggle"))
        XCTAssertTrue(chatView.contains("grok-run-inspector-toggle"))

        // Conversation: the inline changed-files card (Slice 3 home).
        XCTAssertTrue(chatView.contains("ChangedFilesSummaryCard("))

        // Project menu: branch/worktree switching relocated from the status row.
        XCTAssertTrue(chrome.contains("Button(\"Branches & Worktrees…\""))
        XCTAssertTrue(chrome.contains("onSwitchBranch()"))

        // Add/context menu: files, MCPs, skills, and the Browser/Computer Use
        // project tools with their status refresh still wired.
        XCTAssertTrue(chatView.contains("Attach Files…"))
        XCTAssertTrue(chatView.contains("Section(\"MCP connections\")"))
        XCTAssertTrue(chatView.contains("Section(\"Skills and workflows\")"))
        XCTAssertTrue(chatView.contains("Section(\"Project tools\")"))
        XCTAssertTrue(chatView.contains("await refreshToolPillStatus()"))
    }

    func testTopBarComposerAndReviewToggleAreExtractedComponents() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        let topBar = try source("GrokBuild/Views/ChatTopBar.swift")
        let composer = try source("GrokBuild/Views/ChatComposer.swift")
        let review = try source("GrokBuild/Views/ChatHeaderReviewToggle.swift")

        XCTAssertTrue(chatView.contains("ChatTopBar("))
        XCTAssertTrue(chatView.contains("ChatComposer("))
        XCTAssertTrue(chatView.contains("ChatHeaderReviewToggle("))
        XCTAssertTrue(topBar.contains("struct ChatTopBar"))
        XCTAssertTrue(composer.contains("struct ChatComposer"))
        XCTAssertTrue(review.contains("struct ChatHeaderReviewToggle"))
        XCTAssertTrue(review.contains("grok-header-review-toggle"))
        XCTAssertTrue(composer.contains("TextField(\"Describe a task\""))
        XCTAssertTrue(topBar.contains("tasksStatus"))
        XCTAssertFalse(chatView.contains("private func openInButton"))
    }

    func testEmptyComposerAccessibilityValueIncludesDescribeATask() {
        XCTAssertEqual(ChatComposerAccessibility.identifier, "grok-message-composer")
        XCTAssertEqual(ChatComposerAccessibility.label, "Message composer")
        XCTAssertEqual(ChatComposerAccessibility.value(forDraft: ""), "Describe a task")
        XCTAssertTrue(
            ChatComposerAccessibility.value(forDraft: "").contains("Describe a task")
        )
        XCTAssertEqual(ChatComposerAccessibility.value(forDraft: "hello"), "5 characters")
        XCTAssertFalse(ChatComposerAccessibility.value(forDraft: "hello").contains("Empty"))
    }

    func testComposerKeepsStableIdentifierAndDoesNotAnnounceEmpty() throws {
        let composer = try source("GrokBuild/Views/ChatComposer.swift")
        XCTAssertTrue(composer.contains("ChatComposerAccessibility.identifier"))
        XCTAssertTrue(composer.contains("ChatComposerAccessibility.label"))
        XCTAssertTrue(composer.contains("ChatComposerAccessibility.value(forDraft: input)"))
        XCTAssertFalse(
            composer.contains("input.isEmpty ? \"Empty\""),
            "empty composer AX value must include Describe a task, not Empty"
        )
        XCTAssertFalse(
            composer.contains("accessibilityIdentifier(\"grok-message-composer\")"),
            "identifier must stay on ChatComposerAccessibility so the contract has one owner"
        )
    }

    func testCampaignComputerUseSurfacesKeepStableIdentifiers() throws {
        let contentView = try source("GrokBuild/ContentView.swift")
        let settingsView = try source("GrokBuild/Views/SettingsView.swift")
        let appPane = try source("GrokBuild/Views/Settings/AppUpdatesSettingsPane.swift")
        let chatView = try source("GrokBuild/Views/ChatView.swift")
        XCTAssertTrue(contentView.contains("accessibilityIdentifier(\"grok-upgrade-banner\")"))
        XCTAssertTrue(contentView.contains("accessibilityIdentifier(\"grok-upgrade-banner-open\")"))
        XCTAssertTrue(contentView.contains("accessibilityIdentifier(\"grok-upgrade-banner-dismiss\")"))
        XCTAssertTrue(contentView.contains(".accessibilityElement(children: .contain)"))
        XCTAssertTrue(chatView.contains("accessibilityIdentifier(\"grok-acp-error-banner\")"))
        XCTAssertTrue(chatView.contains("accessibilityElement(children: .ignore)"))
        XCTAssertTrue(chatView.contains("accessibilityAddTraits(.isStaticText)"))
        XCTAssertTrue(settingsView.contains(".accessibilityIdentifier(tab.accessibilityIdentifier)"))
        XCTAssertTrue(appPane.contains("accessibilityIdentifier(\"grok-app-build-identity\")"))
        XCTAssertTrue(appPane.contains(".accessibilityElement(children: .contain)"))
        XCTAssertFalse(appPane.contains("accessibilityLabel(\"Build identity\")"))
    }
}
