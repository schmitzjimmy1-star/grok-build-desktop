import XCTest
@testable import GrokBuild

final class RunEvidenceSnapshotTests: XCTestCase {
    func testSnapshotUpdatesOnlyGitReviewFilesWithoutChangingItsRunBinding() {
        let binding = RunEvidenceSnapshot.Binding(
            localTabID: UUID(),
            workspaceID: UUID(),
            backendSessionID: "backend",
            processGeneration: 7,
            requestID: "prompt",
            isSettled: true
        )
        let snapshot = RunEvidenceSnapshot(
            binding: binding,
            goalSummary: nil,
            plan: [],
            workers: [],
            tools: .init(succeeded: 0, failed: 0, cancelled: 0, unknown: 0),
            artifacts: [],
            gitReviewFiles: [],
            process: .init(state: "Ready", model: "grok-4.5", mcps: []),
            continuity: .init(
                status: "backendBound",
                reason: "freshBackendBound",
                provenance: "Fresh backend bound",
                requiresRecoveryAction: false
            ),
            usage: .init(totalTokens: 1_276_441, modelCalls: 15, turnCount: 8),
            outcome: .completed,
            unresolvedErrors: [],
            nextAction: "No further action reported."
        )

        let updated = snapshot.replacingGitReviewFiles(["Sources/App.swift"])

        XCTAssertEqual(updated.binding, binding)
        XCTAssertEqual(updated.usage.totalTokens, 1_276_441)
        XCTAssertEqual(updated.gitReviewFiles, ["Sources/App.swift"])
    }

    @MainActor
    func testBeginningANewTurnClearsThePriorEphemeralSnapshot() async throws {
        let store = ChatStore()
        store.clearTurnState()
        XCTAssertNil(store.runEvidenceSnapshot)
    }
}
