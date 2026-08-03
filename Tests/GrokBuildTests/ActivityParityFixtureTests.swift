import Foundation
import XCTest
@testable import GrokBuild

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

    @MainActor
    func testFreshBackendBindingIsIdentifiedAndSettledWithoutFalseVerification() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-slice4-fresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        count_file='\(root.appendingPathComponent("new-count").path)'
        new_count=0
        if [ -f "$count_file" ]; then new_count=$(sed -n '1p' "$count_file"); fi
        current_backend='\(backendID)'
        if [ "$new_count" -gt 0 ]; then current_backend='slice-4-fork-backend'; fi
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id" ;;
            *'"method":"session/new"'*)
              new_count=$((new_count + 1))
              printf '%s\\n' "$new_count" > "$count_file"
              if [ "$new_count" -gt 1 ]; then current_backend='slice-4-fork-backend'; fi
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"%s","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id" "$current_backend"
              ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id" ;;
            *'"method":"session/prompt"'*)
              # grok 0.2.118 emits live private lifecycle updates through
              # _x.ai/session_notification even though updates.jsonl normalizes
              # the same receipt as _x.ai/session/update.
              printf '{"jsonrpc":"2.0","method":"_x.ai/session_notification","params":{"sessionId":"%s","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn"}}}\\n' "$current_backend"
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let tabID = UUID()
        let store = ChatStore()
        store.bindTabSession(tabID, savedModel: nil)
        await store.start(workspace: Workspace(name: "slice-4", path: root))
        let generation = try XCTUnwrap(store.process.activeProcessGeneration)

        XCTAssertEqual(store.grokSessionId, backendID)
        XCTAssertEqual(store.continuityStatus, .backendBound)
        XCTAssertEqual(store.continuityReceipt.reason, .freshBackendBound)
        XCTAssertEqual(store.continuityHeadline, "New backend bound")
        XCTAssertEqual(store.continuityReceipt.localTabID, tabID)
        XCTAssertEqual(store.continuityReceipt.backendID, backendID)
        XCTAssertEqual(store.continuityReceipt.processGeneration, generation)
        XCTAssertNotEqual(store.continuityReceipt.reason, .noBackendBinding)
        XCTAssertTrue(store.sessionReceiptDetailLines.contains {
            $0.contains("Continuity: New backend bound")
                && $0.contains("reason freshBackendBound")
        })

        store.bindTabSession(tabID, savedModel: nil)
        XCTAssertEqual(store.grokSessionId, backendID)
        XCTAssertEqual(store.continuityStatus, .backendBound)
        XCTAssertEqual(store.continuityReceipt.reason, .freshBackendBound)

        let sent = await store.sendAndWait("Count this settled prompt")
        XCTAssertTrue(sent)
        XCTAssertEqual(store.continuityReceipt.localMessageCount, 1)
        XCTAssertEqual(store.continuityReceipt.backendMessageCount, 1)
        XCTAssertEqual(store.continuityReceipt.matchingPrefixCount, 1)
        XCTAssertEqual(store.continuityReceipt.processGeneration, generation)

        await store.startNewSession()
        XCTAssertEqual(store.grokSessionId, "slice-4-fork-backend")
        XCTAssertEqual(store.continuityStatus, .recoveryForked)
        XCTAssertEqual(store.continuityReceipt.reason, .recoveryForked)
        XCTAssertEqual(store.continuityReceipt.backendID, "slice-4-fork-backend")
        XCTAssertEqual(store.continuityReceipt.processGeneration, generation + 1)
        XCTAssertEqual(store.pendingForkLedgerEntries.last?.reason, .explicitFreshStart)
        await store.shutdownPermanently()
    }

    @MainActor
    func testRunArtifactsRemainDistinctFromPreexistingGitReviewFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-slice3-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await GitService.run(["init"], in: root)
        let preexistingURL = root.appendingPathComponent("preexisting.txt")
        try "baseline\n".write(to: preexistingURL, atomically: true, encoding: .utf8)
        try "fake-grok\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        _ = try await GitService.run(["add", "preexisting.txt", ".gitignore"], in: root)
        _ = try await GitService.run([
            "-c", "user.name=GrokBuild Tests",
            "-c", "user.email=tests@grokbuild.invalid",
            "commit", "-m", "baseline",
        ], in: root)
        try "dirty before run\n".write(to: preexistingURL, atomically: true, encoding: .utf8)
        let artifactURL = root.appendingPathComponent("current-output.md")
        try "current run\n".write(to: artifactURL, atomically: true, encoding: .utf8)

        let scriptURL = root.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"\(backendID)","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id" ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: nil)
        await store.start(workspace: Workspace(name: "slice-3", path: root))
        let generation = try XCTUnwrap(store.process.activeProcessGeneration)
        store.setStreamingForTests(true)
        let callID = "slice-3-write"
        store.process.routeSessionUpdateForTests([
            "sessionUpdate": "tool_call_update",
            "toolCallId": callID,
            "kind": "edit",
            "rawInput": ["file_path": "current-output.md"],
        ], sessionID: backendID, backendEventID: "write-start", processGeneration: generation)
        store.process.routeSessionUpdateForTests([
            "sessionUpdate": "tool_call_update",
            "toolCallId": callID,
            "status": "completed",
        ], sessionID: backendID, backendEventID: "write-complete", processGeneration: generation)
        store.process.routeSessionUpdateForTests([
            "sessionUpdate": "turn_completed",
        ], sessionID: backendID, backendEventID: "turn-complete", processGeneration: generation)

        for _ in 0..<100 where store.runArtifacts.isEmpty || store.gitRefreshRevision < 2 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(store.runArtifacts.map(\.path), [artifactURL.standardizedFileURL.path])
        XCTAssertEqual(store.runArtifacts.first?.location, .workspace)
        XCTAssertEqual(store.gitRefreshRevision, 2)
        let reviewFiles = try await GitService.changedFiles(in: root)
        XCTAssertEqual(Set(reviewFiles.map(\.path)), Set(["preexisting.txt", "current-output.md"]))
        XCTAssertFalse(store.runArtifacts.contains { $0.path.hasSuffix("preexisting.txt") })
        await store.shutdownPermanently()

        let missingStore = ChatStore()
        missingStore.bindTabSession(UUID(), savedModel: nil)
        await missingStore.start(workspace: Workspace(name: "slice-3-missing-completion", path: root))
        let missingGeneration = try XCTUnwrap(missingStore.process.activeProcessGeneration)
        missingStore.setStreamingForTests(true)
        missingStore.process.routeTurnCompletionReceiptMissingForTests(
            sessionID: backendID,
            processGeneration: missingGeneration
        )
        for _ in 0..<100 where missingStore.runEvidenceSnapshot == nil {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        let incomplete = try XCTUnwrap(missingStore.runEvidenceSnapshot)
        XCTAssertEqual(incomplete.outcome, .completionReceiptMissing)
        XCTAssertFalse(incomplete.binding.isSettled)
        XCTAssertNil(incomplete.usage.totalTokens)
        XCTAssertEqual(incomplete.process.state, "Incomplete — completion receipt missing")
        XCTAssertEqual(missingStore.latestTurnOutcome, .completionReceiptMissing)
        await missingStore.shutdownPermanently()
    }

    @MainActor
    func testParityFixtureCorrelatesTerminalWorkersExactlyOnceAndRejectsStaleGeneration() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-slice2-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"\(backendID)","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id"
              ;;
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }

        let tabID = UUID()
        let store = ChatStore()
        store.bindTabSession(tabID, savedModel: nil)
        await store.start(workspace: Workspace(name: "slice-1", path: fixtureRoot))
        XCTAssertEqual(store.process.sessionId, backendID)
        let generation = try XCTUnwrap(store.process.activeProcessGeneration)
        store.setStreamingForTests(true)

        let lifecycleEnvelopes = try loadEvents().filter { envelope in
            guard let lifecycleUpdate = try? update(envelope),
                  let kind = lifecycleUpdate["sessionUpdate"] as? String else { return false }
            return kind == "subagent_spawned" || kind == "subagent_finished"
        }
        XCTAssertEqual(lifecycleEnvelopes.count, 4)

        // Route the complete parent update stream. Wait/collection is deliberately
        // included here: it must annotate the two spawn-created workers rather
        // than manufacture a third unnamed worker.
        for envelope in try loadEvents() {
            let eventParams = params(envelope)
            guard let update = try? self.update(envelope) else { continue }
            if update["sessionUpdate"] as? String == "turn_completed" {
                for _ in 0..<100 where store.liveRunEvidenceProjection?.workers.count != 2
                    || store.liveRunEvidenceProjection?.artifacts.count != 1 {
                    await Task.yield()
                    try await Task.sleep(for: .milliseconds(5))
                }
                let live = try XCTUnwrap(store.liveRunEvidenceProjection)
                XCTAssertEqual(live.binding.localTabID, tabID)
                XCTAssertEqual(live.binding.backendSessionID, backendID)
                XCTAssertEqual(live.binding.processGeneration, generation)
                XCTAssertEqual(live.workers.count, 2)
                XCTAssertEqual(live.artifacts.count, 1)
                XCTAssertEqual(live.tools.filter { $0.status == "Failed" }.count, 5)
                XCTAssertEqual(live.process.state, "In progress — not settled")
                XCTAssertNil(store.runEvidenceSnapshot)
            }
            let eventMeta = eventParams["_meta"] as? [String: Any]
            store.process.routeSessionUpdateForTests(
                update,
                sessionID: backendID,
                backendEventID: eventMeta?["eventId"] as? String,
                processGeneration: generation
            )
        }

        for envelope in lifecycleEnvelopes {
            let eventParams = params(envelope)
            let eventMeta = eventParams["_meta"] as? [String: Any]
            store.process.routeSessionUpdateForTests(
                try update(envelope),
                sessionID: backendID,
                backendEventID: eventMeta?["eventId"] as? String,
                processGeneration: generation
            )
        }

        // Replayed terminal envelopes are the same authoritative facts, not two
        // more completions. A late line from the replaced generation is discarded
        // at GrokProcess before it can enter ChatStore's stream.
        for envelope in lifecycleEnvelopes.suffix(2) {
            let eventParams = params(envelope)
            let eventMeta = eventParams["_meta"] as? [String: Any]
            store.process.routeSessionUpdateForTests(
                try update(envelope),
                sessionID: backendID,
                backendEventID: eventMeta?["eventId"] as? String,
                processGeneration: generation
            )
            store.process.routeSessionUpdateForTests(
                try update(envelope),
                sessionID: backendID,
                backendEventID: "stale-\(eventMeta?["eventId"] as? String ?? "event")",
                processGeneration: generation &- 1
            )
        }

        for _ in 0..<100 where store.subagentFinishedEvents.count < 2
            || store.runArtifacts.count < 1
            || store.gitRefreshRevision < 2
            || store.runEvidenceSnapshot == nil {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(store.subagentSpawnedEvents.count, 2)
        XCTAssertEqual(store.subagentFinishedEvents.count, 2)
        XCTAssertEqual(Set(store.subagentFinishedEvents.map(\.childID)), Set([
            "019fc38a-0792-79c1-b6bd-4905c88962e4",
            "019fc38a-0792-79c1-b6bd-491e945ad7cc",
        ]))
        XCTAssertEqual(Set(store.subagentFinishedEvents.compactMap(\.toolCallCount)), Set([45, 35]))
        XCTAssertEqual(Set(store.subagentFinishedEvents.compactMap(\.durationMilliseconds)), Set([149_254, 173_148]))
        XCTAssertTrue(store.subagentFinishedEvents.allSatisfy {
            $0.identity.localTabID == tabID
                && $0.identity.backendSessionID == backendID
                && $0.identity.processGeneration == generation
                && $0.status == "completed"
                && $0.redactedError == nil
        })

        let workers = store.backgroundActivities.filter { $0.kind == .subagent }
        XCTAssertEqual(workers.count, 2)
        XCTAssertEqual(Set(workers.compactMap(\.childID)), Set([
            "019fc38a-0792-79c1-b6bd-4905c88962e4",
            "019fc38a-0792-79c1-b6bd-491e945ad7cc",
        ]))
        XCTAssertEqual(Set(workers.compactMap(\.durationMilliseconds)), Set([149_254, 173_148]))
        XCTAssertEqual(Set(workers.compactMap(\.toolCallCount)), Set([45, 35]))
        XCTAssertTrue(workers.allSatisfy {
            $0.status == "completed"
                && $0.toolCallID != nil
                && $0.collectionReceiptCount == 1
        })
        XCTAssertEqual(store.runArtifacts.count, 1)
        XCTAssertEqual(store.runArtifacts.first?.path, artifactPath)
        XCTAssertEqual(store.runArtifacts.first?.status, "Completed")
        XCTAssertEqual(store.runArtifacts.first?.location, .external)
        XCTAssertEqual(
            store.gitRefreshRevision,
            2,
            "one successful write plus the ordered turn settlement must request two bounded refreshes"
        )
        XCTAssertEqual(store.latestTurnOutcome, .completed)
        XCTAssertNil(store.liveRunEvidenceProjection)
        let snapshot = try XCTUnwrap(store.runEvidenceSnapshot)
        XCTAssertEqual(snapshot.binding.localTabID, tabID)
        XCTAssertEqual(snapshot.binding.backendSessionID, backendID)
        XCTAssertEqual(snapshot.binding.processGeneration, generation)
        XCTAssertEqual(snapshot.binding.requestID, "840615e0-d48a-47c4-9cf8-6f550a84af7d")
        XCTAssertTrue(snapshot.binding.isSettled)
        XCTAssertEqual(snapshot.workers.count, 2)
        XCTAssertEqual(snapshot.completedWorkerCount, 2)
        XCTAssertEqual(snapshot.activeWorkerCount, 0)
        XCTAssertEqual(snapshot.tools.failed, 5)
        XCTAssertEqual(snapshot.artifacts.count, 1)
        XCTAssertEqual(snapshot.outcome, .completed)
        XCTAssertEqual(snapshot.usage.modelCalls, 15)
        XCTAssertEqual(snapshot.usage.totalTokens, 1_276_441)
        XCTAssertEqual(snapshot.plan.count, 3)
        XCTAssertTrue(snapshot.plan.allSatisfy { $0.status == "completed" })
        let failedFetches = store.liveToolCalls.filter { $0.terminalStatus == .failed }
        XCTAssertEqual(failedFetches.count, 5)
        XCTAssertTrue(failedFetches.allSatisfy {
            $0.title == "web_fetch"
                && $0.target?.hasPrefix("https://") == true
                && $0.detail?.contains("HTTP request failed") == true
                && $0.diagnosticDetail?.contains("tool_execution_failed") == true
                && !$0.isRecovered
        })
        XCTAssertEqual(failedFetches.map(\.recoveredByToolCallID).compactMap { $0 }.count, 0)

        let failed = ChatStore.LiveToolCall(
            id: "failed",
            title: "web_fetch",
            kind: "tool",
            status: "failed",
            terminalStatus: .failed,
            detail: "HTTP request failed",
            diagnosticDetail: nil,
            target: "https://example.com/a",
            retryOfToolCallID: nil,
            recoveredByToolCallID: nil
        )
        let retry = ChatStore.LiveToolCall(
            id: "retry",
            title: "web_fetch",
            kind: "tool",
            status: "completed",
            terminalStatus: .succeeded,
            detail: nil,
            diagnosticDetail: nil,
            target: "https://example.com/a",
            retryOfToolCallID: "failed",
            recoveredByToolCallID: nil
        )
        XCTAssertEqual(failed.settled(against: [failed, retry]).recoveredByToolCallID, "retry")
        XCTAssertNil(failed.settled(against: [failed]).recoveredByToolCallID)
        await store.shutdownPermanently()
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
