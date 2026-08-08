import XCTest
@testable import GrokBuild

/// Codex parity Slice 5 — pure contracts for the contextual inspector projection.
final class ContextInspectorProjectionTests: XCTestCase {
    private func worker(_ id: String, title: String, status: String) -> RunEvidenceSnapshot.Worker {
        RunEvidenceSnapshot.Worker(
            id: id,
            title: title,
            status: status,
            childID: nil,
            durationMilliseconds: nil,
            toolCallCount: nil,
            redactedError: nil
        )
    }

    func testSubagentCountsSeparateRunningDoneFailedAndNoReport() {
        let summary = ContextInspectorProjection.subagentSummary([
            worker("a", title: "researcher", status: "running"),
            worker("b", title: "writer", status: "completed"),
            worker("c", title: "checker", status: "failed"),
            worker("d", title: "ghost", status: "unknown"),
            worker("e", title: "orphan", status: "orphaned"),
        ])
        XCTAssertEqual(summary.runningCount, 1)
        XCTAssertEqual(summary.doneCount, 1)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.noReportCount, 2,
                       "unknown/orphaned workers are no-report, never silently successful")
        XCTAssertEqual(summary.compactLabel, "1 running · 1 done · 1 failed · 2 no final report")
        XCTAssertEqual(summary.rows.count, 5, "no invented workers, none dropped")
    }

    func testRequestedMCPsAreNeverPresentedAsUsed() throws {
        let sources = try XCTUnwrap(ContextInspectorProjection.sourcesSection(
            attachmentNames: ["README.md"],
            requestedMCPNames: ["chrome-devtools"],
            evidencedMCPServers: []
        ))
        XCTAssertEqual(sources.requestedMCPs.map(\.label), ["chrome-devtools"])
        XCTAssertEqual(sources.requestedMCPs.first?.detail, "Requested — not yet evidenced")
        XCTAssertTrue(sources.usedMCPServers.isEmpty,
                      "a requested MCP without a tool receipt must never appear used")

        let evidenced = try XCTUnwrap(ContextInspectorProjection.sourcesSection(
            attachmentNames: [],
            requestedMCPNames: [],
            evidencedMCPServers: ["chrome-devtools", "chrome-devtools", " "]
        ))
        XCTAssertEqual(evidenced.usedMCPServers.map(\.label), ["chrome-devtools"],
                       "used servers deduplicate and drop empties")
        XCTAssertEqual(evidenced.usedMCPServers.first?.detail, "Used — tool receipt observed")
    }

    func testComputerUseSectionGatesOnConfigurationOrLifecycle() {
        let absent = ContextInspectorProjection.model(
            live: nil, snapshot: nil, attachmentNames: [], requestedMCPNames: [],
            evidencedMCPServers: [], computerUseConfigured: false, computerUseStateLabel: nil
        )
        XCTAssertNil(absent.computerUse,
                     "no configuration and no lifecycle receipt means no Computer Use section")

        let configured = ContextInspectorProjection.model(
            live: nil, snapshot: nil, attachmentNames: [], requestedMCPNames: [],
            evidencedMCPServers: [], computerUseConfigured: true, computerUseStateLabel: nil
        )
        XCTAssertEqual(configured.computerUse?.stateLabel, "Configured")

        let lifecycle = ContextInspectorProjection.model(
            live: nil, snapshot: nil, attachmentNames: [], requestedMCPNames: [],
            evidencedMCPServers: [], computerUseConfigured: true, computerUseStateLabel: "Ready"
        )
        XCTAssertEqual(lifecycle.computerUse?.stateLabel, "Ready",
                       "a real lifecycle receipt outranks the configured fallback")
    }

    func testEmptyModelIsEmptyAndFailuresAreNeverDropped() {
        XCTAssertTrue(ContextInspectorProjection.Model.empty.isEmpty)

        let snapshot = RunEvidenceSnapshot(
            binding: .init(
                localTabID: UUID(), workspaceID: UUID(), backendSessionID: "b",
                processGeneration: 1, requestID: "r", isSettled: true
            ),
            goalSummary: nil,
            plan: [],
            workers: [],
            tools: .init(succeeded: 3, failed: 2, cancelled: 0, unknown: 0),
            artifacts: [],
            gitReviewFiles: [],
            process: .init(state: "Ready", model: "grok-4.5", mcps: []),
            continuity: .init(status: "backendBound", reason: "fresh", provenance: "p", requiresRecoveryAction: false),
            usage: .init(totalTokens: 1, modelCalls: 1, turnCount: 1),
            outcome: .completed,
            unresolvedErrors: ["exit 127"],
            nextAction: "n"
        )
        let model = ContextInspectorProjection.model(
            live: nil, snapshot: snapshot, attachmentNames: [], requestedMCPNames: [],
            evidencedMCPServers: [], computerUseConfigured: false, computerUseStateLabel: nil
        )
        XCTAssertEqual(model.failedToolCount, 2,
                       "failed tools survive compaction")
        XCTAssertEqual(model.unresolvedErrors, ["exit 127"])
        XCTAssertTrue(model.hasRunDetails)
        XCTAssertTrue(model.isSettled)
        XCTAssertFalse(model.isEmpty)
    }
}
