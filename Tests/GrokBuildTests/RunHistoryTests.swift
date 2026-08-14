import XCTest
@testable import GrokBuild

final class RunHistoryTests: XCTestCase {
    func testGroupsOneBackendIntoHistoricalRunWithoutFlatteningTurns() {
        let first = message(backend: "backend-a", timestamp: 1, outcome: .completed)
        let legacy = Message(role: .assistant, content: "old answer without a checkpoint", timestamp: Date(timeIntervalSince1970: 2))
        let second = message(backend: "backend-a", timestamp: 3, outcome: .userStopped)
        let other = message(backend: "backend-b", timestamp: 4, outcome: .completed)

        let records = RunHistory.records(from: [first, legacy, second, other])

        XCTAssertEqual(records.count, 2)
        let backendA = try! XCTUnwrap(records.first(where: { $0.backendSessionID == "backend-a" }))
        XCTAssertEqual(backendA.turns.map(\.timestamp), [first.timestamp, second.timestamp])
        XCTAssertTrue(backendA.hasStopResumeBoundary)
        XCTAssertTrue(backendA.turns.allSatisfy(\.isHistorical))
    }

    func testExportIsDeterministicAndOmitsTranscriptAndSecretLikeValues() throws {
        let checkpoint = AssistantTurnCheckpoint(
            snapshot: snapshot(backend: "sk-backend-should-not-leak", outcome: .completed, model: "Bearer secret-value"),
            requestedToolFamilies: ["credentialless-tool"]
        )
        let message = Message(
            role: .assistant,
            content: "prompt and response prose must never export: sk-response-secret",
            timestamp: Date(timeIntervalSince1970: 10),
            assistantTrace: .init(reasoningSummaryChunks: ["private prose"], thinkingDuration: nil, tools: [], checkpoint: checkpoint)
        )
        let record = try XCTUnwrap(RunHistory.records(from: [message]).first)

        let first = try RunHistory.jsonData(for: record)
        let second = try RunHistory.jsonData(for: record)
        let json = try XCTUnwrap(String(data: first, encoding: .utf8))
        let markdown = RunHistory.markdown(for: record)

        XCTAssertEqual(first, second)
        for forbidden in ["sk-", "Bearer", "private prose", "prompt and response prose", "Keychain"] {
            XCTAssertFalse(json.localizedCaseInsensitiveContains(forbidden), "JSON leaked \(forbidden)")
            XCTAssertFalse(markdown.localizedCaseInsensitiveContains(forbidden), "Markdown leaked \(forbidden)")
        }
        XCTAssertTrue(json.contains("\"historical\" : true"))
        XCTAssertTrue(markdown.contains("Historical: yes"))
        XCTAssertTrue(markdown.contains("Route: not retained"))
    }

    func testLegacyCheckpointRoundTripProducesHonestNotRetainedFields() throws {
        let checkpoint = AssistantTurnCheckpoint(
            snapshot: snapshot(backend: "legacy", outcome: .completed),
            requestedToolFamilies: []
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(checkpoint)) as? [String: Any])
        for key in ["toolSummaryReceipt", "processReceipt", "continuityReceipt", "usageReceipt", "coordinationReceipt", "artifacts", "workerReceipts", "routeReceipt"] {
            object.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(AssistantTurnCheckpoint.self, from: JSONSerialization.data(withJSONObject: object))
        let record = try XCTUnwrap(RunHistory.records(from: [Message(
            role: .assistant,
            content: "legacy",
            timestamp: Date(timeIntervalSince1970: 12),
            assistantTrace: .init(reasoningSummaryChunks: [], thinkingDuration: nil, tools: [], checkpoint: legacy)
        )]).first)

        let markdown = RunHistory.markdown(for: record)
        XCTAssertTrue(markdown.contains("Tools: not retained"))
        XCTAssertTrue(markdown.contains("Usage: not retained"))
        XCTAssertTrue(markdown.contains("Artifacts: not retained"))
    }

    private func message(backend: String, timestamp: TimeInterval, outcome: ChatStore.TurnOutcome) -> Message {
        Message(
            role: .assistant,
            content: "answer",
            timestamp: Date(timeIntervalSince1970: timestamp),
            assistantTrace: .init(
                reasoningSummaryChunks: [],
                thinkingDuration: nil,
                tools: [],
                checkpoint: AssistantTurnCheckpoint(snapshot: snapshot(backend: backend, outcome: outcome), requestedToolFamilies: [])
            )
        )
    }

    private func snapshot(
        backend: String,
        outcome: ChatStore.TurnOutcome,
        model: String = "grok-4.6"
    ) -> RunEvidenceSnapshot {
        RunEvidenceSnapshot(
            binding: .init(localTabID: UUID(), workspaceID: UUID(), backendSessionID: backend, processGeneration: 7, requestID: "request-1", isSettled: true),
            goalSummary: "do not export this objective",
            plan: [],
            workers: [.init(id: "worker", title: "sk-worker-secret", status: "completed", childID: "child", durationMilliseconds: 20, toolCallCount: 0, redactedError: nil, childToolReceipts: [])],
            tools: .init(succeeded: 1, failed: 0, cancelled: 0, unknown: 0),
            artifacts: [.init(toolCallID: "tool", path: "/private/raw/path.txt", status: "succeeded", location: .external, owningPlanStepID: nil, workerID: nil)],
            gitReviewFiles: ["secret-path"],
            process: .init(state: "ready", model: model, mcps: []),
            continuity: .init(status: "bound", reason: "fresh", provenance: "hidden", requiresRecoveryAction: false),
            usage: .init(totalTokens: 123, modelCalls: 1, turnCount: 1, apiDurationMilliseconds: 55),
            outcome: outcome,
            unresolvedErrors: [],
            nextAction: "Continue with a saved checkpoint"
        )
    }
}
