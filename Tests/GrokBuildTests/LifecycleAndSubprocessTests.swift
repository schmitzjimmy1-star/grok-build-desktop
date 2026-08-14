import Foundation
import XCTest
@testable import GrokBuild

/// Slice-3/4 contracts: closed sessions deallocate, and runtime reloads never kill a
/// streaming turn.
@MainActor
final class SessionLifecycleTests: XCTestCase {
    func testGrokProcessStopTerminatesExactSpawnedChild() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-owned-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let childPIDFile = fixtureRoot.appendingPathComponent("child.pid")
        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        sleep 30 &
        child=$!
        printf '%s' "$child" > '\(childPIDFile.path)'
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
            *'"method":"session/new"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"owned-child-backend"}}\\n' "$id"
              ;;
          esac
        done
        wait "$child" 2>/dev/null
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let tabID = UUID()
        let process = GrokProcess()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(localTabID: tabID)
        )
        XCTAssertEqual(process.state, .ready)
        let childPID = try XCTUnwrap(pid_t(String(contentsOf: childPIDFile, encoding: .utf8)))
        let childFingerprint = try XCTUnwrap(OwnedProcessTree.fingerprint(of: childPID))

        await process.stop()

        for _ in 0..<50 where OwnedProcessTree.stillMatches(childFingerprint) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(OwnedProcessTree.stillMatches(childFingerprint))
        XCTAssertNil(process.activeProcessGeneration)
        XCTAssertEqual(process.state, .idle)
    }

    func testSubagentLifecycleRejectsWrongTabBackendAndGeneration() {
        let tabID = UUID()
        let identity = ACPEventIdentity(
            localTabID: tabID,
            backendSessionID: "backend-a",
            processGeneration: 9,
            backendEventID: "event"
        )

        XCTAssertTrue(SubagentLifecycleEventPolicy.ownsActiveSession(
            identity,
            localTabID: tabID,
            backendSessionID: "backend-a",
            processGeneration: 9
        ))
        XCTAssertFalse(SubagentLifecycleEventPolicy.ownsActiveSession(
            identity,
            localTabID: UUID(),
            backendSessionID: "backend-a",
            processGeneration: 9
        ))
        XCTAssertFalse(SubagentLifecycleEventPolicy.ownsActiveSession(
            identity,
            localTabID: tabID,
            backendSessionID: "backend-b",
            processGeneration: 9
        ))
        XCTAssertFalse(SubagentLifecycleEventPolicy.ownsActiveSession(
            identity,
            localTabID: tabID,
            backendSessionID: "backend-a",
            processGeneration: 10
        ))
        XCTAssertFalse(SubagentLifecycleEventPolicy.ownsActiveSession(
            identity,
            localTabID: tabID,
            backendSessionID: "backend-a",
            processGeneration: nil
        ))
    }

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

        await store.stop()
        XCTAssertNil(store.turnStalledSince, "Stop must clear the stall banner")

        store.setStreamingForTests(false)
        store.evaluateTurnStall(now: Date.distantFuture)
        XCTAssertNil(store.turnStalledSince, "a finished turn can never be stalled")
        await store.shutdownPermanently()
    }

    func testStopCreatesASettledLocalOutcomeWithFreshStartNextActionWhenUnbound() async throws {
        let store = ChatStore()
        let workspace = Workspace(name: "demo", path: URL(fileURLWithPath: "/tmp/demo"))
        store.prepare(workspace: workspace)
        store.bindTabSession(UUID(), savedModel: nil)
        store.setStreamingForTests(true)

        await store.stop()

        let snapshot = try XCTUnwrap(store.runEvidenceSnapshot)
        XCTAssertEqual(snapshot.outcome, .userStopped)
        XCTAssertEqual(snapshot.process.state, "Stopped by you")
        XCTAssertEqual(
            snapshot.nextAction,
            "Start a fresh run. The prior continuity receipt did not match this stopped session."
        )
        XCTAssertTrue(snapshot.binding.isSettled)
        await store.shutdownPermanently()
    }

    func testStoppedTurnContinuationRequiresExactTabBackendAndGenerationReceipt() {
        let tabID = UUID()
        let receipt = SessionContinuityReceipt(
            status: .verified,
            reason: .exactMatch,
            normalizationVersion: VersionedOpaqueTag.transcriptNormalizationVersion,
            authenticationSchemaVersion: VersionedOpaqueTag.transcriptAuthenticationSchemaVersion,
            localMessageCount: 2,
            backendMessageCount: 2,
            matchingPrefixCount: 2,
            localTranscriptTag: "local",
            backendTranscriptTag: "backend",
            verifiedAt: Date(),
            localTabID: tabID,
            backendID: "backend-a",
            processGeneration: 7
        )

        XCTAssertEqual(
            StoppedTurnContinuationDecision.decision(
                receipt: receipt, localTabID: tabID, backendID: "backend-a", processGeneration: 7
            ),
            .reverifySameBackend
        )
        XCTAssertEqual(
            StoppedTurnContinuationDecision.decision(
                receipt: receipt, localTabID: tabID, backendID: "backend-a", processGeneration: 8
            ),
            .startFresh
        )
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
            *'"method":"session/set_model"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id"
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
        XCTAssertEqual(store.continuityStatus, .verified)
        XCTAssertEqual(store.continuityReceipt.reason, .exactMatch)
        XCTAssertEqual(store.continuityReceipt.localTabID, tabID)
        XCTAssertEqual(store.continuityReceipt.backendID, backendID)
        XCTAssertEqual(store.continuityReceipt.processGeneration, 1)

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
        XCTAssertEqual(store.continuityStatus, .verified)
        XCTAssertEqual(store.continuityReceipt.backendID, backendID)
        XCTAssertEqual(store.continuityReceipt.processGeneration, 2)

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

    /// A restored tab that is still verifying its saved backend must keep Send usable —
    /// submitting is what triggers the lazy resume — while only the genuine recovery
    /// states disable Send. This pins the Send-gate carve-out for `.verifying`.
    @MainActor
    func testVerifyingKeepsSendUsableWhileRecoveryStatesBlockIt() {
        let store = ChatStore()

        // Transient resume: enabled, not a recovery action, flagged as resuming.
        store.setContinuityStatusForTests(.verifying)
        XCTAssertFalse(store.continuityRequiresRecovery, "verifying must not disable Send")
        XCTAssertTrue(store.continuityIsResuming)

        // Genuinely blocking states require explicit recovery before Send.
        for blocking in [SessionContinuityStatus.diverged, .compositeSuspected, .backendMissing, .verificationIncomplete] {
            store.setContinuityStatusForTests(blocking)
            XCTAssertTrue(store.continuityRequiresRecovery, "\(blocking) must block Send until recovery")
            XCTAssertFalse(store.continuityIsResuming)
        }

        // Healthy states never block and never read as resuming.
        for healthy in [SessionContinuityStatus.localOnly, .backendBound, .verified, .backendOnly, .recoveryForked] {
            store.setContinuityStatusForTests(healthy)
            XCTAssertFalse(store.continuityRequiresRecovery, "\(healthy) must allow Send")
            XCTAssertFalse(store.continuityIsResuming)
        }
    }

    /// Continuity never disables Send: the transient verifying state resumes on send, and the
    /// hard-block states auto-fork to a fresh thread. The error-toned label is gone.
    func testSendIsNeverDisabledByContinuity() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatViewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        let buttonStart = try XCTUnwrap(chatViewSource.range(of: "private var sessionActionButton"))
        let button = String(chatViewSource[buttonStart.lowerBound...])
        XCTAssertFalse(button.contains("store.continuityRequiresRecovery ||"),
                       "continuity must not disable Send; hard blocks auto-fork on send")
        XCTAssertFalse(button.contains("store.continuityBlocksSend"),
                       "Send must not bind to the raw continuity gate")
        XCTAssertFalse(chatViewSource.contains("Send blocked by conversation continuity"),
                       "the error-toned label is replaced by state-aware copy")
    }

    /// The composer surfaces a demonstrated mismatch as a recovery note, while an ordinary
    /// restorable task gets explicit Resume/New/Browse launch choices. Send auto-forks on a
    /// mismatch — the block lives in `deliverPrompt`, not either presentation surface.
    func testComposerSurfacesContinuityStatusBannerInline() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chatViewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/ChatView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatViewSource.contains("if store.continuityRequiresRecovery {"),
                      "recovery note must be gated on the hard-block predicate")
        XCTAssertTrue(chatViewSource.contains("} else if store.continuityIsResuming && !store.messages.isEmpty {"),
                      "quiet launch choices belong on restored transcripts, not empty New chat")
        XCTAssertTrue(chatViewSource.contains("ContinuityStatusBanner("),
                      "the inline continuity note must be composed above the composer")
        XCTAssertTrue(chatViewSource.contains("LaunchSessionChoices("),
                      "a restorable launch must expose explicit session choices")
        let recoveryStart = try XCTUnwrap(chatViewSource.range(of: "kind: .needsRecovery"))
        let recoveryEnd = try XCTUnwrap(
            chatViewSource.range(
                of: "} else if store.continuityIsResuming && !store.messages.isEmpty {",
                range: recoveryStart.upperBound..<chatViewSource.endIndex
            )
        )
        let recoveryBlock = String(chatViewSource[recoveryStart.lowerBound..<recoveryEnd.lowerBound])
        XCTAssertTrue(recoveryBlock.contains("store.reviewRecoveryCandidates()"),
                      "the inline Review link must drive the explicit recovery review")

        // Send auto-forks on a hard block instead of dead-ending: deliverPrompt calls continueAsNew.
        let chatStoreSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        let deliveryStart = try XCTUnwrap(chatStoreSource.range(of: "private func deliverPrompt"))
        let deliveryEnd = try XCTUnwrap(
            chatStoreSource.range(of: "// MARK:", range: deliveryStart.upperBound..<chatStoreSource.endIndex)
        )
        let delivery = String(chatStoreSource[deliveryStart.lowerBound..<deliveryEnd.lowerBound])
        XCTAssertTrue(delivery.contains("if continuityRequiresRecovery {"),
                      "deliverPrompt must still branch on the hard-block predicate")
        XCTAssertTrue(delivery.contains("await continueAsNew()"),
                      "a hard-blocked send must auto-fork via continueAsNew, not dead-end")
    }

    func testExplicitTaskResumeUsesNativeExactSessionLoadWithoutSending() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "func resumeTaskSession() async -> Bool"))
        let end = try XCTUnwrap(
            source.range(of: "/// Clears in-flight turn UI", range: start.upperBound..<source.endIndex)
        )
        let method = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(method.contains("guard canResumeTaskSession, let backendID = durableGrokSessionID"))
        XCTAssertTrue(method.contains("await restartProcess(resumeSessionID: backendID)"))
        XCTAssertTrue(method.contains("process.sessionId == backendID"))
        XCTAssertFalse(method.contains("send("), "Resume loads the exact saved backend; it must not send a provider prompt")
    }

    /// Continue as new (used automatically on a hard-blocked send) flips the tab to
    /// `.recoveryForked`, which the send gate allows — so the user is never stuck, while the
    /// suspicious backend is never resumed (a fresh backend is created on the next send).
    @MainActor
    func testContinueAsNewClearsTheHardBlockWithoutResuming() async {
        let store = ChatStore()
        let workspace = Workspace(name: "demo", path: URL(fileURLWithPath: "/tmp/demo-continue-new"))
        store.prepare(workspace: workspace, savedGrokSessionID: "backend-diverged")
        store.restorePersistedMessages([
            Message(role: .user, content: "local prompt"),
            Message(role: .assistant, content: "local reply"),
        ])
        store.setContinuityStatusForTests(.diverged)
        XCTAssertTrue(store.continuityRequiresRecovery, "precondition: a diverged tab is hard-blocked")

        let didFork = await store.continueAsNew()
        XCTAssertTrue(didFork)
        XCTAssertEqual(store.continuityStatus, .recoveryForked)
        XCTAssertFalse(store.continuityRequiresRecovery, "Continue as new must clear the block")
        XCTAssertFalse(store.continuityIsResuming)
        // Local transcript is preserved; the fork happens without starting a process.
        XCTAssertEqual(store.messages.filter { $0.role == .user }.first?.content, "local prompt")
        await store.shutdownPermanently()
    }

    @MainActor
    func testPermanentShutdownCancelsWarmStartAndRefusesRestart() async {
        let store = ChatStore()
        store.beginSyntheticWarmStartForTests()
        XCTAssertTrue(store.leftoverWarmStartIsRunningForTests)
        await store.shutdownPermanently()
        XCTAssertFalse(store.leftoverWarmStartIsRunningForTests)
        XCTAssertTrue(store.isPermanentlyShutdownForTests)

        store.prepare(workspace: Workspace(name: "demo", path: URL(fileURLWithPath: "/tmp/demo-perm-shutdown")))
        await store.startNewSession()
        XCTAssertEqual(store.connectionState, .idle)
        XCTAssertNil(store.process.sessionId, "a permanently shut down tab must not spawn grok again")
    }

    @MainActor
    func testComposerDraftWithoutSendLeavesProcessIdle() async {
        let store = ChatStore()
        store.prepare(workspace: Workspace(name: "demo", path: URL(fileURLWithPath: "/tmp/demo-send-spawn")))
        store.composerDraft = "x"
        XCTAssertEqual(store.connectionState, .idle)
        XCTAssertNil(store.process.sessionId)
        XCTAssertFalse(store.leftoverWarmStartIsRunningForTests)
        XCTAssertFalse(SidebarSessionActivity.isWorking(connectionState: store.connectionState, isStreaming: store.isStreaming))
        await store.shutdownPermanently()
    }

    func testStartupStderrRedactsAPIKeysBeforeUI() {
        let raw = "ACP init failed api_key=sk-secret-value token=abc123"
        let redacted = GrokProcess.redactedStartupStderr(raw)
        XCTAssertFalse(redacted.contains("sk-secret-value"))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertTrue(redacted.contains("<redacted>"))
    }

    func testAutoStartedExternalBrowserLedgerTerminatesRecordedPID() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc.arguments = ["30"]
        try proc.run()
        let pid = proc.processIdentifier
        AgentBrowserService.recordAutoStartedExternalBrowserPID(pid)
        XCTAssertTrue(AgentBrowserService.recordedAutoStartedExternalBrowserPIDsForTests().contains(pid))
        AgentBrowserService.terminateAutoStartedExternalBrowsers()
        XCTAssertTrue(AgentBrowserService.recordedAutoStartedExternalBrowserPIDsForTests().isEmpty)
        let deadline = Date().addingTimeInterval(2)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertFalse(proc.isRunning, "recorded auto-started PIDs must be terminated; user Chrome is never recorded")
    }

    func testQuitDeadlineAndExternalBrowserTeardownAreWired() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appDelegate = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/AppDelegate.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            appDelegate.contains("ContinuousClock.now.advanced(by: .seconds(5))"),
            "quit must wait Gate G's five-second graceful window"
        )
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            content.contains("AgentBrowserService.terminateAutoStartedExternalBrowsers()"),
            "Quit and last-tab close must tear down auto-started GrokBuild-profile browsers"
        )
        let process = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/GrokProcess.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            process.contains("Self.redactedStartupStderr(startupStderrSnapshot())"),
            "startup stderr must be redacted before it reaches lastError"
        )
    }
}
