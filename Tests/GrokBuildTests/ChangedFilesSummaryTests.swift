import XCTest
@testable import GrokBuild

/// Codex parity Slice 3 — focused presentation contracts for the inline
/// changed-files card projection.
final class ChangedFilesSummaryTests: XCTestCase {
    private func snapshot(
        artifacts: [ChatStore.RunArtifact] = [],
        gitReviewFiles: [String] = [],
        outcome: ChatStore.TurnOutcome = .completed
    ) -> RunEvidenceSnapshot {
        RunEvidenceSnapshot(
            binding: .init(
                localTabID: UUID(),
                workspaceID: UUID(),
                backendSessionID: "backend",
                processGeneration: 3,
                requestID: "prompt",
                isSettled: true
            ),
            goalSummary: nil,
            plan: [],
            workers: [],
            tools: .init(succeeded: 2, failed: 1, cancelled: 0, unknown: 0),
            artifacts: artifacts,
            gitReviewFiles: gitReviewFiles,
            process: .init(state: "Ready", model: "grok-4.5", mcps: []),
            continuity: .init(
                status: "backendBound",
                reason: "freshBackendBound",
                provenance: "Fresh backend bound",
                requiresRecoveryAction: false
            ),
            usage: .init(totalTokens: 100, modelCalls: 1, turnCount: 1),
            outcome: outcome,
            unresolvedErrors: [],
            nextAction: "No further action reported."
        )
    }

    private let workspace = URL(fileURLWithPath: "/tmp/project")

    private func artifact(_ path: String) -> ChatStore.RunArtifact {
        ChatStore.RunArtifact(
            toolCallID: "call-\(path)",
            path: path,
            status: "completed",
            location: .workspace
        )
    }

    private func unifiedDiff(path: String, added: Int, removed: Int) -> ChatStore.DetectedDiff {
        var lines = ["diff --git a/\(path) b/\(path)", "--- a/\(path)", "+++ b/\(path)", "@@ -1,5 +1,5 @@"]
        lines.append(contentsOf: Array(repeating: "+new line", count: added))
        lines.append(contentsOf: Array(repeating: "-old line", count: removed))
        lines.append(" context")
        return ChatStore.DetectedDiff(raw: lines.joined(separator: "\n"), filePath: path)
    }

    // MARK: Gate

    func testNoCardWithoutASettledSnapshotOrWithoutGitChanges() {
        XCTAssertNil(ChangedFilesSummaryProjection.summary(
            snapshot: nil,
            diffs: [unifiedDiff(path: "a.swift", added: 1, removed: 0)],
            workspace: workspace
        ), "no settled turn means no card, however dirty the repository is")

        XCTAssertNil(ChangedFilesSummaryProjection.summary(
            snapshot: snapshot(gitReviewFiles: []),
            diffs: [],
            workspace: workspace
        ), "a settled turn with an empty generation-bound Git recording shows no card")
    }

    // MARK: Attribution truth

    func testDirtyRepositoryFilesAreNeverCalledAgentEdited() throws {
        let summary = try XCTUnwrap(ChangedFilesSummaryProjection.summary(
            snapshot: snapshot(gitReviewFiles: ["docs/notes.md", "Sources/App.swift"]),
            diffs: [unifiedDiff(path: "docs/notes.md", added: 4, removed: 2)],
            workspace: workspace
        ))
        XCTAssertEqual(summary.turnAttributedCount, 0)
        XCTAssertEqual(summary.headline, "2 changed files in project")
        XCTAssertEqual(summary.scopeNote, "Repository-wide changes — not attributed to this turn.")
        XCTAssertTrue(summary.rows.allSatisfy { !$0.isTurnAttributed })
    }

    func testArtifactBackedEditsLeadAndRepositoryDirtIsDisclosedSeparately() throws {
        let summary = try XCTUnwrap(ChangedFilesSummaryProjection.summary(
            snapshot: snapshot(
                artifacts: [artifact("/tmp/project/Sources/App.swift")],
                gitReviewFiles: ["docs/notes.md", "Sources/App.swift", "README.md"]
            ),
            diffs: [
                unifiedDiff(path: "Sources/App.swift", added: 10, removed: 3),
                unifiedDiff(path: "docs/notes.md", added: 1, removed: 1),
            ],
            workspace: workspace
        ))
        XCTAssertEqual(summary.headline, "Edited 1 file")
        XCTAssertEqual(summary.turnAttributedCount, 1)
        XCTAssertEqual(summary.rows.first?.path, "Sources/App.swift",
                       "turn-attributed edits lead the row order")
        XCTAssertTrue(summary.rows.first?.isTurnAttributed == true)
        XCTAssertEqual(summary.scopeNote,
                       "2 more changed files in the project are not attributed to this turn.")
    }

    func testExternalArtifactsAndNonGitArtifactsDoNotInflateTheEditedClaim() throws {
        let external = ChatStore.RunArtifact(
            toolCallID: "call-ext",
            path: "/tmp/elsewhere/out.txt",
            status: "completed",
            location: .external
        )
        let unlisted = artifact("/tmp/project/Sources/Silent.swift")
        let summary = try XCTUnwrap(ChangedFilesSummaryProjection.summary(
            snapshot: snapshot(
                artifacts: [external, unlisted],
                gitReviewFiles: ["docs/notes.md"]
            ),
            diffs: [],
            workspace: workspace
        ))
        XCTAssertEqual(summary.turnAttributedCount, 0,
                       "an external artifact or a write Git cannot see is never an Edited claim")
        XCTAssertEqual(summary.headline, "1 changed file in project")
    }

    // MARK: Diff counts

    func testDiffCountsParseHunksAndRefuseNonDiffBodies() {
        let counts = ChangedFilesSummaryProjection.diffCounts(fromUnifiedDiff:
            "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,2 +1,3 @@\n context\n+one\n+two\n-gone\n")
        XCTAssertEqual(counts?.additions, 2)
        XCTAssertEqual(counts?.deletions, 1)

        XCTAssertNil(ChangedFilesSummaryProjection.diffCounts(fromUnifiedDiff:
            "Untracked file: docs/new.md\n\nThis file is not tracked by git yet."),
            "the untracked placeholder must not read as zero additions and deletions")
    }

    func testTotalsDiscloseIncompleteCoverage() throws {
        let summary = try XCTUnwrap(ChangedFilesSummaryProjection.summary(
            snapshot: snapshot(gitReviewFiles: ["a.swift", "docs/new-folder/"]),
            diffs: [
                unifiedDiff(path: "a.swift", added: 5, removed: 2),
                ChatStore.DetectedDiff(raw: "Untracked file: docs/new-folder/", filePath: "docs/new-folder/"),
            ],
            workspace: workspace
        ))
        XCTAssertEqual(summary.additionsTotal, 5)
        XCTAssertEqual(summary.deletionsTotal, 2)
        XCTAssertFalse(summary.hasCompleteCounts,
                       "one uncounted file means the totals must disclose partial coverage")
    }

    // MARK: Transcript wiring

    func testCardRendersInTranscriptTailAndReviewTargetsTheRealPane() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatSource.contains("ChangedFilesSummaryProjection.summary("),
                      "the card gates on the projection, not on raw view state")
        XCTAssertTrue(chatSource.contains("snapshot: store.runEvidenceSnapshot"),
                      "the settled snapshot is the gate — no card without a settled turn")
        let cardSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChangedFilesSummaryCard.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(cardSource.contains("grok-changed-files-review"),
                      "the card exposes the Review action")
        XCTAssertFalse(cardSource.contains("Button(\"Undo\""),
                       "no decorative Undo control: GrokBuild has no safe real undo operation today")
    }
}
