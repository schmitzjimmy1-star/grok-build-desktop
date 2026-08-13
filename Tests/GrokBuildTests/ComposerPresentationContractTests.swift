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

    func testAuthoringControlsArePresentInTheCodexShape() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")

        // One rounded surface with the Describe a task editor on top…
        XCTAssertTrue(chatView.contains("TextField(\"Describe a task\""))
        XCTAssertTrue(chatView.contains("ComposerDensityPolicy.minimumLineCount...ComposerDensityPolicy.maximumLineCount"),
                      "one-line idle height growing to the existing eight-line cap")
        XCTAssertTrue(chatView.contains(".grokGlassSurface("),
                      "the composer keeps its single rounded surface")

        // …and a bottom row of immediate authoring/run controls only.
        XCTAssertTrue(chatView.contains("private var composerAddMenu"))
        XCTAssertTrue(chatView.contains("grok-mode-selector"))
        XCTAssertTrue(chatView.contains("grok-model-effort-selector"))
        XCTAssertTrue(chatView.contains("MicButton("))
        XCTAssertTrue(chatView.contains("sessionActionButton"))

        // Chips render inside the composer envelope, not a detached toolbar.
        let composerStart = try XCTUnwrap(chatView.range(of: "private var composer: some View"))
        let composerSlice = String(chatView[composerStart.lowerBound..<chatView.index(composerStart.upperBound, offsetBy: 900)])
        XCTAssertTrue(composerSlice.contains("FileChipBar("))
        XCTAssertTrue(composerSlice.contains("PromptMCPChipBar("))
    }

    func testDetailsShelfIsAbsentInEverySpelling() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")
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
            XCTAssertFalse(chatView.contains(forbidden),
                           "Details residue `\(forbidden)` must not return under the composer")
        }
    }

    func testRelocatedTelemetryRemainsReachableFromTruthfulHomes() throws {
        let chatView = try source("GrokBuild/Views/ChatView.swift")

        // Model popover: context budget, settled usage, route/process receipt.
        XCTAssertTrue(chatView.contains("Section(\"Session telemetry\")"))
        XCTAssertTrue(chatView.contains("store.currentModelContextLabel"))
        XCTAssertTrue(chatView.contains("store.sessionUsageSummary"))
        XCTAssertTrue(chatView.contains("Route, process, and model receipt"))
        XCTAssertTrue(chatView.contains("store.sessionReceiptDetailLines"))
        XCTAssertTrue(chatView.contains("grok-model-route-contract"))

        // Header: Review state and the inspector toggle (Slice 2 homes).
        XCTAssertTrue(chatView.contains("grok-header-review-toggle"))
        XCTAssertTrue(chatView.contains("grok-activity-sidebar-toggle"))

        // Conversation: the inline changed-files card (Slice 3 home).
        XCTAssertTrue(chatView.contains("ChangedFilesSummaryCard("))

        // Project menu: branch/worktree switching relocated from the status row.
        XCTAssertTrue(chatView.contains("Button(\"Branches & Worktrees…\""))
        XCTAssertTrue(chatView.contains("onSwitchBranch()"))

        // Add/context menu: files, MCPs, skills, and the Browser/Computer Use
        // project tools with their status refresh still wired.
        XCTAssertTrue(chatView.contains("Attach Files…"))
        XCTAssertTrue(chatView.contains("Section(\"MCP connections\")"))
        XCTAssertTrue(chatView.contains("Section(\"Skills and workflows\")"))
        XCTAssertTrue(chatView.contains("Section(\"Project tools\")"))
        XCTAssertTrue(chatView.contains("await refreshToolPillStatus()"))
    }
}
