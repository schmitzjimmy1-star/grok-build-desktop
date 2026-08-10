import Foundation
import XCTest
@testable import GrokBuild

final class ProductCloseoutTests: XCTestCase {
    func testObservableContextReportNamesMeasuredAndOpaqueCLICategoriesHonestly() {
        let report = PromptContextBudget.report(
            projectInstructions: Data(repeating: 1, count: 3_112),
            skillDescriptions: ["skill catalog"],
            mcpServerDescriptors: ["progressive MCP catalog"],
            requestedToolSchemas: [Data(repeating: 2, count: 120)],
            deferredToolSchemas: [Data(repeating: 3, count: 8_000)],
            sessionHistory: Data(repeating: 4, count: 400),
            projectContext: Data(repeating: 5, count: 80),
            userContent: Data(repeating: 6, count: 40)
        )

        XCTAssertEqual(report.bytes(for: .projectInstructions), 3_112)
        XCTAssertEqual(report.bytes(for: .projectContext), 80)
        XCTAssertEqual(report.bytes(for: .userContent), 40)
        XCTAssertEqual(report.bytes(for: .requestedToolSchemas), 120)
        XCTAssertEqual(report.deferredBytes, 8_000)
        XCTAssertTrue(report.unmeasuredLabels.contains { $0.contains("system instructions") })
        XCTAssertTrue(report.unmeasuredLabels.contains { $0.contains("Provider wrapper") })
        XCTAssertFalse(
            report.contributors.first { $0.kind == .deferredToolSchemas }?.isMeasured == false,
            "deferred bytes are measured even though they are not loaded"
        )
    }

    func testReleaseBudgetsAdmitMeasuredSliceSevenAndSixEvidenceWithHeadroom() {
        XCTAssertTrue(ThreadNativeReleaseBudgets.accepts(
            coldFirstWindowMilliseconds: 494.8,
            coldFirstIntentReadyMilliseconds: 8_090.8,
            coldDispatchToFirstChunkMilliseconds: 5_500,
            warmDispatchToFirstChunkMilliseconds: 1_900,
            idleOwnedProcessCount: 0,
            minimalTerminalTurnTokens: 31_715
        ))
        XCTAssertFalse(ThreadNativeReleaseBudgets.accepts(
            coldFirstWindowMilliseconds: 751,
            coldFirstIntentReadyMilliseconds: 8_090.8,
            coldDispatchToFirstChunkMilliseconds: 5_500,
            warmDispatchToFirstChunkMilliseconds: 1_900,
            idleOwnedProcessCount: 0,
            minimalTerminalTurnTokens: 31_715
        ))
        XCTAssertFalse(ThreadNativeReleaseBudgets.accepts(
            coldFirstWindowMilliseconds: 494.8,
            coldFirstIntentReadyMilliseconds: 8_090.8,
            coldDispatchToFirstChunkMilliseconds: 5_500,
            warmDispatchToFirstChunkMilliseconds: 1_900,
            idleOwnedProcessCount: 1,
            minimalTerminalTurnTokens: 31_715
        ))
    }

    func testLaunchChoicesNameResumeNewAndBrowseWithoutStaleProcessCopy() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try [
            "GrokBuild/Views/ChatView.swift",
            "GrokBuild/Views/ComposerViews.swift",
        ].map { path in
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }.joined(separator: "\n")

        for required in [
            "Resume current task", "Start new task", "Browse old tasks",
            "grok-launch-resume-current", "grok-launch-new-task",
            "grok-launch-browse-old", "Saved task launch choices",
        ] {
            XCTAssertTrue(source.contains(required), "missing quiet launch contract: \(required)")
        }
        XCTAssertFalse(source.contains("Resuming saved session. Send to continue."))
    }
}
