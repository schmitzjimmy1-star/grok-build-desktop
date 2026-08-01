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

/// Slice-5 contracts: one-shot helper subprocesses drain their pipes and cannot wedge
/// their caller forever.
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
