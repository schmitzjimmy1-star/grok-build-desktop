import Foundation
import XCTest

final class ActivityParityFixtureTests: XCTestCase {
    private let backendID = "019fc389-b16a-7053-b79e-33017125294b"
    private let artifactPath = "/Users/jimmyschmitz/Documents/Grok Git/evidence-packet-1893-columbian-exposition.md"

    func testRedactedFixtureProvesExactBackendCountsAndUsage() throws {
        let events = try loadEvents()
        let updates = try events.map(update)
        let toolNamesByCallID = toolNameIndex(updates)

        XCTAssertEqual(events.count, 30)
        XCTAssertTrue(events.allSatisfy { params($0)["sessionId"] as? String == backendID })

        let spawned = updates.filter { $0["sessionUpdate"] as? String == "subagent_spawned" }
        let completedWorkers = updates.filter {
            $0["sessionUpdate"] as? String == "subagent_finished"
                && $0["status"] as? String == "completed"
        }
        XCTAssertEqual(spawned.count, 2)
        XCTAssertEqual(completedWorkers.count, 2)
        XCTAssertEqual(Set(completedWorkers.compactMap { $0["child_session_id"] as? String }), Set([
            "019fc38a-0792-79c1-b6bd-4905c88962e4",
            "019fc38a-0792-79c1-b6bd-491e945ad7cc",
        ]))
        XCTAssertEqual(Set(completedWorkers.compactMap { $0["tool_calls"] as? Int }), Set([45, 35]))
        XCTAssertEqual(Set(completedWorkers.compactMap { $0["duration_ms"] as? Int }), Set([149_254, 173_148]))

        let failedFetches = updates.filter { update in
            guard update["sessionUpdate"] as? String == "tool_call_update",
                  update["status"] as? String == "failed",
                  let callID = update["toolCallId"] as? String else { return false }
            return toolNamesByCallID[callID] == "web_fetch"
        }
        XCTAssertEqual(failedFetches.count, 5)
        XCTAssertTrue(failedFetches.allSatisfy {
            (($0["rawOutput"] as? [String: Any])?["error"] as? String) == "tool_execution_failed"
        })

        let completedWrites = updates.filter { update in
            guard update["sessionUpdate"] as? String == "tool_call_update",
                  update["status"] as? String == "completed",
                  let callID = update["toolCallId"] as? String else { return false }
            return toolNamesByCallID[callID] == "write"
        }
        XCTAssertEqual(completedWrites.count, 1)
        XCTAssertTrue(updates.contains { update in
            guard let rawInput = update["rawInput"] as? [String: Any] else { return false }
            return rawInput["file_path"] as? String == artifactPath
        })

        let completedTurns = updates.filter { $0["sessionUpdate"] as? String == "turn_completed" }
        let turn = try XCTUnwrap(completedTurns.only)
        XCTAssertEqual(turn["stop_reason"] as? String, "end_turn")
        let usage = try XCTUnwrap(turn["usage"] as? [String: Any])
        XCTAssertEqual(usage["totalTokens"] as? Int, 1_276_441)
        XCTAssertEqual(usage["modelCalls"] as? Int, 15)
        XCTAssertEqual(usage["numTurns"] as? Int, 8)

        let plans = updates.filter { $0["sessionUpdate"] as? String == "plan" }
        XCTAssertEqual(plans.count, 2)
        let finalEntries = try XCTUnwrap(plans.last?["entries"] as? [[String: Any]])
        XCTAssertEqual(finalEntries.count, 3)
        XCTAssertTrue(finalEntries.allSatisfy { $0["status"] as? String == "completed" })
        XCTAssertTrue(toolNamesByCallID.values.contains("get_command_or_subagent_output"))
    }

    func testFixtureIsBundledSecretSafeAndIndependentOfLiveState() throws {
        let eventFixtureURL = try fixtureURL("chicago-evidence-run-redacted.jsonl")
        let fixtureText = try String(contentsOf: eventFixtureURL, encoding: .utf8)
        let manifestURL = try fixtureURL("manifest.json")
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let combined = fixtureText + manifestText

        XCTAssertFalse(combined.contains("/.grok/"))
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("authorization:"))
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("bearer "))
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("api_key"))
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("access_token"))
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("refresh_token"))
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("key_prefix"))
        XCTAssertFalse(combined.localizedCaseInsensitiveContains("system_prompt"))
        XCTAssertTrue(combined.contains("[redacted"))
        XCTAssertLessThanOrEqual(fixtureText.split(separator: "\n").map(\.utf8.count).max() ?? 0, 2_500)

        let manifest = try JSONSerialization.jsonObject(with: Data(manifestText.utf8)) as? [String: Any]
        XCTAssertEqual(manifest?["sourceSessionID"] as? String, backendID)
        let expected = try XCTUnwrap(manifest?["expected"] as? [String: Any])
        XCTAssertEqual(expected["spawnedWorkers"] as? Int, 2)
        XCTAssertEqual(expected["completedWorkers"] as? Int, 2)
        XCTAssertEqual(expected["failedToolCalls"] as? Int, 5)
        XCTAssertEqual(expected["writtenArtifacts"] as? Int, 1)
        XCTAssertEqual(expected["completedParentTurns"] as? Int, 1)
        XCTAssertEqual(expected["totalTokens"] as? Int, 1_276_441)
        XCTAssertEqual(expected["modelCalls"] as? Int, 15)
    }

    private func loadEvents() throws -> [[String: Any]] {
        let data = try Data(contentsOf: fixtureURL("chicago-evidence-run-redacted.jsonl"))
        let lines = try XCTUnwrap(String(data: data, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: true)
        return try lines.map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
    }

    private func update(_ event: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(params(event)["update"] as? [String: Any])
    }

    private func params(_ event: [String: Any]) -> [String: Any] {
        event["params"] as? [String: Any] ?? [:]
    }

    private func toolNameIndex(_ updates: [[String: Any]]) -> [String: String] {
        updates.reduce(into: [:]) { result, update in
            guard let callID = update["toolCallId"] as? String,
                  let meta = update["_meta"] as? [String: Any],
                  let tool = meta["x.ai/tool"] as? [String: Any],
                  let name = tool["name"] as? String else { return }
            result[callID] = name
        }
    }

    private func fixtureURL(_ filename: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(
            forResource: filename,
            withExtension: nil,
            subdirectory: "Fixtures/ActivityParity"
        ))
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
