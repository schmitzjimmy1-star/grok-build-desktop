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
        for key in ["toolSummaryReceipt", "processReceipt", "continuityReceipt", "usageReceipt", "coordinationReceipt", "artifacts", "workerReceipts", "routeReceipt", "structuredRouteReceipt", "observedRouteReceipt"] {
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

    func testProjectionUsesOnlyTheBoundedNewestMessageWindow() throws {
        let dropped = message(backend: "dropped-before-window", timestamp: 0, outcome: .completed)
        let retained = (0..<RunHistory.maximumSourceMessages).map { index in
            message(backend: "retained-tail", timestamp: TimeInterval(index + 1), outcome: .completed)
        }

        let records = RunHistory.records(from: [dropped] + retained)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.backendSessionID, "retained-tail")
        XCTAssertEqual(records.first?.turns.count, RunHistory.maximumTurnsPerRun)
        XCTAssertEqual(records.first?.turns.first?.timestamp, retained.suffix(RunHistory.maximumTurnsPerRun).first?.timestamp)
        let record = try XCTUnwrap(records.first)
        XCTAssertTrue(record.sourceWindowWasTruncated)
        XCTAssertEqual(record.sourceMessageCount, RunHistory.maximumSourceMessages + 1)
        XCTAssertTrue(RunHistory.markdown(for: record).contains("newest 1024 of 1025 local messages retained"))
    }

    func testExportCapsCollectionsAndDisclosesObservedCounts() throws {
        let workers = (0...RunHistory.maximumWorkersPerTurn).map { index in
            RunEvidenceSnapshot.Worker(
                id: "worker-\(index)",
                title: "worker \(index)",
                status: "completed",
                childID: index == RunHistory.maximumWorkersPerTurn ? "sk-omitted-worker" : "child-\(index)",
                durationMilliseconds: nil,
                toolCallCount: 0,
                redactedError: nil
            )
        }
        let artifacts = (0...RunHistory.maximumArtifactsPerTurn).map { index in
            ChatStore.RunArtifact(
                toolCallID: "artifact-\(index)",
                path: "/private/raw/\(index)",
                status: index == RunHistory.maximumArtifactsPerTurn ? "Bearer omitted-artifact" : "succeeded",
                location: .external,
                owningPlanStepID: nil,
                workerID: nil
            )
        }
        let tools = (0...RunHistory.maximumToolsPerTurn).map { index in
            AssistantTurnTrace.Tool(
                id: "tool-\(index)",
                title: index == RunHistory.maximumToolsPerTurn ? "sk-omitted-tool" : "tool \(index)",
                kind: "execute",
                status: "Succeeded",
                mcpServerName: nil
            )
        }
        let checkpoint = AssistantTurnCheckpoint(
            snapshot: snapshot(backend: "bounded", outcome: .completed, workers: workers, artifacts: artifacts),
            requestedToolFamilies: []
        )
        let message = Message(
            role: .assistant,
            content: "unexported transcript prose",
            timestamp: Date(timeIntervalSince1970: 20),
            assistantTrace: .init(reasoningSummaryChunks: [], thinkingDuration: nil, tools: tools, checkpoint: checkpoint)
        )
        let record = try XCTUnwrap(RunHistory.records(from: [message]).first)
        let json = try XCTUnwrap(String(data: RunHistory.jsonData(for: record), encoding: .utf8))
        let markdown = RunHistory.markdown(for: record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let turn = try XCTUnwrap((object["turns"] as? [[String: Any]])?.first)

        XCTAssertEqual(object["sourceWindow"] as? String, "all 1 local messages considered")
        XCTAssertEqual((turn["workers"] as? [[String: Any]])?.count, RunHistory.maximumWorkersPerTurn)
        XCTAssertEqual(turn["workersObserved"] as? Int, workers.count)
        XCTAssertEqual(turn["workersRetained"] as? Int, RunHistory.maximumWorkersPerTurn)
        XCTAssertEqual((turn["artifacts"] as? [[String: Any]])?.count, RunHistory.maximumArtifactsPerTurn)
        XCTAssertEqual(turn["artifactsObserved"] as? Int, artifacts.count)
        XCTAssertEqual((turn["toolSequence"] as? [[String: Any]])?.count, RunHistory.maximumToolsPerTurn)
        XCTAssertEqual(turn["toolSequenceObserved"] as? Int, tools.count)
        XCTAssertTrue(markdown.contains("24 of 25 retained"))
        for forbidden in ["sk-omitted", "Bearer omitted", "/private/raw", "unexported transcript prose"] {
            XCTAssertFalse(json.localizedCaseInsensitiveContains(forbidden), "JSON leaked \(forbidden)")
            XCTAssertFalse(markdown.localizedCaseInsensitiveContains(forbidden), "Markdown leaked \(forbidden)")
        }
    }

    func testSnapshotsKeepEachSessionIndependent() {
        let firstID = UUID()
        let secondID = UUID()
        let snapshots = RunHistory.snapshots(for: [
            (id: firstID, messages: [message(backend: "backend-a", timestamp: 1, outcome: .completed)]),
            (id: secondID, messages: [
                message(backend: "backend-b", timestamp: 2, outcome: .completed),
                message(backend: "backend-b", timestamp: 3, outcome: .userStopped)
            ])
        ])

        XCTAssertEqual(snapshots[firstID]?.count, 1)
        XCTAssertEqual(snapshots[secondID]?.count, 1)
        XCTAssertEqual(snapshots[firstID]?.first?.backendSessionID, "backend-a")
        XCTAssertEqual(snapshots[secondID]?.first?.turns.count, 2)
        XCTAssertTrue(snapshots[secondID]?.first?.hasStopResumeBoundary ?? false)
    }

    func testDashboardPresentationLinesStayHonestAboutMissingReceipts() throws {
        let record = try XCTUnwrap(RunHistory.records(from: [
            message(backend: "backend-a", timestamp: 1, outcome: .completed)
        ]).first)
        let latest = try XCTUnwrap(record.latest)

        XCTAssertEqual(
            RunHistory.Presentation.checkpointSummary(for: record),
            "1 historical checkpoint • Turn completed • grok-4.6"
        )
        XCTAssertEqual(RunHistory.Presentation.routeLine(for: record), "Route: not retained")
        XCTAssertTrue(RunHistory.Presentation.toolsLine(for: latest).hasPrefix("Tools: "))
        XCTAssertTrue(RunHistory.Presentation.toolsLine(for: latest).contains(latest.topology))
    }

    func testContentViewSnapshotsThroughRunHistoryHelper() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        let panel = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SessionDashboardPanel.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(content.contains("RunHistory.snapshots("))
        XCTAssertFalse(content.contains("RunHistory.records(from: session.store.messages)"))
        XCTAssertTrue(panel.contains("RunHistorySection("))
        XCTAssertFalse(panel.contains("private var runHistorySection"))
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
        model: String = "grok-4.6",
        workers: [RunEvidenceSnapshot.Worker]? = nil,
        artifacts: [ChatStore.RunArtifact]? = nil
    ) -> RunEvidenceSnapshot {
        RunEvidenceSnapshot(
            binding: .init(localTabID: UUID(), workspaceID: UUID(), backendSessionID: backend, processGeneration: 7, requestID: "request-1", isSettled: true),
            goalSummary: "do not export this objective",
            plan: [],
            workers: workers ?? [.init(id: "worker", title: "sk-worker-secret", status: "completed", childID: "child", durationMilliseconds: 20, toolCallCount: 0, redactedError: nil, childToolReceipts: [])],
            tools: .init(succeeded: 1, failed: 0, cancelled: 0, unknown: 0),
            artifacts: artifacts ?? [.init(toolCallID: "tool", path: "/private/raw/path.txt", status: "succeeded", location: .external, owningPlanStepID: nil, workerID: nil)],
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
