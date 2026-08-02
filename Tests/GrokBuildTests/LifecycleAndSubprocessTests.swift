import Foundation
import XCTest
@testable import GrokBuild

/// Slice-3/4 contracts: closed sessions deallocate, and runtime reloads never kill a
/// streaming turn.
@MainActor
final class SessionLifecycleTests: XCTestCase {
    func testShutdownPermanentlyReleasesStoreAndProcess() async throws {
        weak var weakStore: ChatStore?
        weak var weakProcess: GrokProcess?
        do {
            let store = ChatStore()
            weakStore = store
            weakProcess = store.process
            XCTAssertNotNil(weakStore)
            await store.shutdownPermanently()
        }
        // The consume loop ends asynchronously once the ACP stream finishes.
        for _ in 0..<200 where weakStore != nil || weakProcess != nil {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(weakStore, "a closed session's ChatStore must deallocate once the ACP stream ends")
        XCTAssertNil(weakProcess, "the GrokProcess must deallocate with its store")
    }

    func testReloadConfigurationDefersWhileStreaming() async throws {
        let store = ChatStore()
        store.prepare(workspace: Workspace(name: "demo", path: URL(fileURLWithPath: "/tmp/demo")))
        store.setStreamingForTests(true)

        await store.reloadConfiguration()

        XCTAssertTrue(store.pendingRuntimeReloadForTests,
                      "a reload during streaming must queue instead of restarting the session")
        XCTAssertEqual(
            store.configurationStatusMessage,
            "Configuration changes will apply after the current response."
        )
        await store.shutdownPermanently()
    }

    func testReloadConfigurationWithoutWorkspaceIsANoOp() async {
        let store = ChatStore()
        await store.reloadConfiguration()
        XCTAssertFalse(store.pendingRuntimeReloadForTests)
        XCTAssertNil(store.configurationStatusMessage)
        await store.shutdownPermanently()
    }

    func testTurnStallFlagsQuietStreamAndClearsOnActivityOrStop() async {
        let store = ChatStore()
        store.setStreamingForTests(true)

        store.setLastTurnEventAtForTests(Date().addingTimeInterval(-30))
        store.evaluateTurnStall(now: Date())
        XCTAssertNil(store.turnStalledSince, "recent activity must not read as a stall")

        store.setLastTurnEventAtForTests(Date().addingTimeInterval(-(ChatStore.turnStallThreshold + 1)))
        store.evaluateTurnStall(now: Date())
        XCTAssertNotNil(store.turnStalledSince, "a two-minute-quiet stream must surface as stalled")

        store.stop()
        XCTAssertNil(store.turnStalledSince, "Stop must clear the stall banner")

        store.setStreamingForTests(false)
        store.evaluateTurnStall(now: Date.distantFuture)
        XCTAssertNil(store.turnStalledSince, "a finished turn can never be stalled")
        await store.shutdownPermanently()
    }
}

final class SettingsRuntimeContractTests: XCTestCase {
    private func request(
        id: UUID = UUID(),
        tabID: UUID,
        backendID: String = "backend-a",
        generation: UInt64 = 7
    ) -> SettingsApplyRequest {
        SettingsApplyRequest(
            id: id,
            configurationGeneration: 3,
            capability: .memory,
            persistenceOwner: .userDefaults,
            applyScope: .activeTabRestart,
            requiresProcessRestart: true,
            redactedSummary: "Memory launch setting saved.",
            target: SettingsApplyTarget(
                localTabID: tabID,
                backendSessionID: backendID,
                processGeneration: generation
            )
        )
    }

    private func liveReceipt(
        tabID: UUID,
        backendID: String,
        generation: UInt64,
        outcome: GrokLaunchOutcome
    ) -> EffectiveSessionReceipt {
        var receipt = GrokLaunchReceipt(
            options: GrokLaunchOptions(
                localTabID: tabID,
                experimentalMemory: true,
                resumeSessionID: backendID
            ),
            workspaceID: UUID(),
            processIdentifier: 42,
            processGeneration: generation
        )
        receipt.backendSessionID = backendID
        receipt.outcome = outcome
        return receipt.effectiveSessionReceipt(activeProcessGeneration: generation)
    }

    func testRuntimeReloadQueueCoalescesGeneralModelAndSettingsChanges() {
        let tabID = UUID()
        let firstID = UUID()
        var queue = RuntimeConfigurationReloadQueue()
        queue.enqueueGeneralReload()
        queue.enqueue(.models(["model-a"]))
        queue.enqueue(.models(["model-b", "model-a"]))
        queue.enqueue(request(id: firstID, tabID: tabID))
        queue.enqueue(request(id: firstID, tabID: tabID))
        queue.enqueue(request(tabID: tabID))

        XCTAssertTrue(queue.hasPending)
        let batch = queue.drain()
        XCTAssertTrue(batch.requestsGeneralReload)
        XCTAssertEqual(batch.affectedModelIDs, ["model-a", "model-b"])
        XCTAssertEqual(batch.settingsRequests.count, 2)
        XCTAssertFalse(queue.hasPending)
    }

    func testApplyReceiptRequiresExactNewerTabBackendAndGeneration() {
        let tabID = UUID()
        let apply = request(tabID: tabID)
        let accepted = SettingsApplyReceiptResolver.resolve(
            request: apply,
            connectionIsReady: true,
            liveReceipt: liveReceipt(
                tabID: tabID,
                backendID: "backend-a",
                generation: 8,
                outcome: .loaded
            )
        )
        XCTAssertEqual(accepted.status, .success)

        let wrongTab = SettingsApplyReceiptResolver.resolve(
            request: apply,
            connectionIsReady: true,
            liveReceipt: liveReceipt(
                tabID: UUID(),
                backendID: "backend-a",
                generation: 8,
                outcome: .loaded
            )
        )
        XCTAssertEqual(wrongTab.status, .failure)

        let wrongBackend = SettingsApplyReceiptResolver.resolve(
            request: apply,
            connectionIsReady: true,
            liveReceipt: liveReceipt(
                tabID: tabID,
                backendID: "backend-b",
                generation: 8,
                outcome: .loaded
            )
        )
        XCTAssertEqual(wrongBackend.status, .failure)

        let staleGeneration = SettingsApplyReceiptResolver.resolve(
            request: apply,
            connectionIsReady: true,
            liveReceipt: liveReceipt(
                tabID: tabID,
                backendID: "backend-a",
                generation: 7,
                outcome: .loaded
            )
        )
        XCTAssertEqual(staleGeneration.status, .failure)
    }

    func testRecoveryForkIsPartialRatherThanFalseSuccess() {
        let tabID = UUID()
        let apply = request(tabID: tabID)
        let forked = SettingsApplyReceiptResolver.resolve(
            request: apply,
            connectionIsReady: true,
            liveReceipt: liveReceipt(
                tabID: tabID,
                backendID: "backend-b",
                generation: 8,
                outcome: .recoveryForked
            )
        )
        XCTAssertEqual(forked.status, .partial)
        XCTAssertEqual(forked.effectiveSession?.launchOutcome, .recoveryForked)
        XCTAssertTrue(forked.accessibilityValue.contains("Partially applied"))
    }

    func testProcessLRUNeverAdoptsMismatchedIdentity() {
        let tabID = UUID()
        var launch = GrokLaunchReceipt(
            options: GrokLaunchOptions(localTabID: tabID, resumeSessionID: "backend-a"),
            processGeneration: 9
        )
        launch.backendSessionID = "backend-a"
        launch.outcome = .loaded

        XCTAssertEqual(
            SessionProcessLRUPolicy.decision(
                expectedTabID: tabID,
                persistedBackendID: "backend-a",
                activeProcessGeneration: 9,
                launchReceipt: launch
            ),
            .evictVerified(preservedBackendID: "backend-a")
        )

        launch.backendSessionID = "backend-b"
        XCTAssertEqual(
            SessionProcessLRUPolicy.decision(
                expectedTabID: tabID,
                persistedBackendID: "backend-a",
                activeProcessGeneration: 9,
                launchReceipt: launch
            ),
            .evictWithoutAdoptingMismatchedReceipt(preservedBackendID: "backend-a")
        )

        XCTAssertEqual(
            SessionProcessLRUPolicy.decision(
                expectedTabID: UUID(),
                persistedBackendID: "backend-a",
                activeProcessGeneration: 9,
                launchReceipt: launch
            ),
            .evictWithoutAdoptingMismatchedReceipt(preservedBackendID: "backend-a")
        )
    }

    @MainActor
    func testStreamingSettingsRequestsShareOneExactReconnect() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-settings-reload-\(UUID().uuidString)", isDirectory: true)
        let grokHome = fixtureRoot.appendingPathComponent("grok-home", isDirectory: true)
        let workspaceURL = fixtureRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let previousGrokHome = GrokSessionTranscriptImporter.grokHomeDirectory
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { GrokSessionTranscriptImporter.grokHomeDirectory = previousGrokHome }

        let backendID = "settings-reload-backend"
        let historyURL = try XCTUnwrap(GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspaceURL,
            grokSessionID: backendID
        ))
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"type":"user","content":"synthetic settings fixture"}
        {"type":"assistant","content":"synthetic fixture complete"}
        """.write(to: historyURL, atomically: true, encoding: .utf8)

        let launchLog = fixtureRoot.appendingPathComponent("launches.log")
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(launchLog.path)'
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/load"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }

        let tabID = UUID()
        let workspace = Workspace(name: "fixture", path: workspaceURL)
        let store = ChatStore(continuityKeyOverride: Data(repeating: 0x42, count: 32))
        store.prepare(workspace: workspace, savedGrokSessionID: backendID)
        store.restorePersistedMessages([
            Message(role: .user, content: "synthetic settings fixture"),
            Message(role: .assistant, content: "synthetic fixture complete"),
        ])
        store.bindTabSession(
            tabID,
            modelIntent: .inheritProjectDefault,
            savedGrokSessionID: backendID
        )
        await store.start(
            workspace: workspace,
            resumeSession: GrokSessionInfo(
                id: backendID,
                created: "",
                updated: "",
                status: "",
                summary: ""
            ),
            preserveMessages: true
        )
        XCTAssertEqual(store.connectionState, .ready)
        XCTAssertEqual(store.effectiveSessionReceipt?.processGeneration, 1)

        store.setStreamingForTests(true)
        let first = request(tabID: tabID, backendID: backendID, generation: 1)
        let second = SettingsApplyRequest(
            configurationGeneration: 4,
            capability: .permissions,
            persistenceOwner: .userDefaults,
            applyScope: .activeTabRestart,
            requiresProcessRestart: true,
            redactedSummary: "Permission launch settings saved.",
            target: store.settingsApplyTarget
        )
        let firstTask = Task { await store.applySettingsRequest(first) }
        let secondTask = Task { await store.applySettingsRequest(second) }
        for _ in 0..<100 where store.pendingSettingsApplyCountForTests < 2 {
            await Task.yield()
        }
        XCTAssertEqual(store.pendingSettingsApplyCountForTests, 2)
        XCTAssertEqual(
            store.configurationStatusMessage,
            "Settings saved. Restart queued until the current response finishes."
        )

        await store.applyQueuedRuntimeReloadsForTests()
        let receipts = await [firstTask.value, secondTask.value]
        XCTAssertEqual(receipts.map(\.status), [.success, .success])
        XCTAssertEqual(store.effectiveSessionReceipt?.processGeneration, 2)
        XCTAssertEqual(store.effectiveSessionReceipt?.backendSessionID, backendID)
        XCTAssertEqual(store.effectiveSessionReceipt?.localTabID, tabID)

        let launches = try String(contentsOf: launchLog, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
        XCTAssertEqual(launches.count, 2, "two queued Apply requests must share one reconnect")
        await store.shutdownPermanently()
    }
}

/// Earlier subprocess-hygiene contracts: one-shot helpers drain their pipes and cannot
/// wedge their caller forever. Kept distinct from the coherence plan's Settings Slice 5.
final class SubprocessHygieneTests: XCTestCase {
    private let bigOutputScript =
        "i=0; while [ $i -lt 300 ]; do printf '%01024d' 0; i=$((i+1)); done"

    func testGrokCLIRunTimesOutAndKillsHungProcess() async throws {
        GrokCLIService.cliOverrideForTests = URL(fileURLWithPath: "/bin/sleep")
        defer { GrokCLIService.cliOverrideForTests = nil }

        let started = ContinuousClock.now
        do {
            _ = try await GrokCLIService().run(["30"], timeout: 1)
            XCTFail("expected a timeout")
        } catch GrokCLIService.CLIError.timedOut {
            // expected
        }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(8))
    }

    func testGrokCLIRunCancellationTerminatesChildPromptly() async throws {
        GrokCLIService.cliOverrideForTests = URL(fileURLWithPath: "/bin/sleep")
        defer { GrokCLIService.cliOverrideForTests = nil }

        let task = Task { try await GrokCLIService().run(["30"], timeout: nil) }
        try await Task.sleep(for: .milliseconds(200))
        let started = ContinuousClock.now
        task.cancel()
        _ = try? await task.value
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
    }

    func testGrokCLIRunDrainsLargeOutput() async throws {
        GrokCLIService.cliOverrideForTests = URL(fileURLWithPath: "/bin/sh")
        defer { GrokCLIService.cliOverrideForTests = nil }

        let result = try await GrokCLIService().run(["-c", bigOutputScript], timeout: 30)
        XCTAssertEqual(result.stdout.count, 300 * 1024)
    }

    func testGitRunnerDrainsOutputBeyondPipeBuffer() async throws {
        let output = try await GitService.runExecutable(
            "/bin/sh",
            args: ["-c", bigOutputScript],
            in: FileManager.default.temporaryDirectory,
            timeout: 30
        )
        XCTAssertEqual(output.count, 300 * 1024,
                       "output past the ~64 KiB pipe buffer must not deadlock the runner")
    }

    func testGitRunnerTimesOut() async {
        do {
            _ = try await GitService.runExecutable(
                "/bin/sleep",
                args: ["30"],
                in: FileManager.default.temporaryDirectory,
                timeout: 1
            )
            XCTFail("expected a timeout")
        } catch {
            guard case GitService.GitError.timedOut = error else {
                return XCTFail("expected GitError.timedOut, got \(error)")
            }
        }
    }

    func testAgentBrowserRunTimesOut() async {
        do {
            _ = try await AgentBrowserService.run(["/bin/sleep", "30"], timeout: 1)
            XCTFail("expected a timeout")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("did not finish"),
                          "unexpected error: \(error.localizedDescription)")
        }
    }

    func testAgentBrowserRunDrainsLargeOutput() async throws {
        let output = try await AgentBrowserService.run(
            ["/bin/sh", "-c", bigOutputScript],
            timeout: 30
        )
        XCTAssertEqual(output.count, 300 * 1024)
    }

    // MARK: - Shared BoundedProcess runner

    func testBoundedProcessSeparatePipesCaptureStreamsAndStatus() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf out; printf err 1>&2; exit 3"]
        let out = Pipe(); let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let result = try await BoundedProcess.run(process, stdout: out, stderr: err, timeout: 30)
        XCTAssertEqual(result.status, 3)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "out")
        XCTAssertEqual(String(decoding: result.stderr, as: UTF8.self), "err")
    }

    func testBoundedProcessMergedPipeCombinesStreams() async throws {
        // AppUpdater's shape: one pipe for both streams.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf A; printf B 1>&2"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let result = try await BoundedProcess.run(process, stdout: pipe, stderr: nil, timeout: 30)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(Set(String(decoding: result.stdout, as: UTF8.self)), Set("AB"))
    }

    func testBoundedProcessTimesOutAndFlags() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        let started = ContinuousClock.now
        let result = try await BoundedProcess.run(process, timeout: 1)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(8))
    }
}
