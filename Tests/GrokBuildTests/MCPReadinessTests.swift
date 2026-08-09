import Foundation
import XCTest
@testable import GrokBuild

final class MCPReadinessPolicyTests: XCTestCase {
    func testConfiguredServersStartConnectingAndSettleReadyWithSecretFreeEvidence() {
        let servers = [
            MCPServerConfig(name: "grokbuild-browser"),
            MCPServerConfig(name: "grokbuild-computer-use")
        ]

        let connecting = MCPReadinessPolicy.connectingStatuses(for: servers)
        XCTAssertEqual(connecting.map(\.state), [.connecting, .connecting])
        XCTAssertTrue(connecting.allSatisfy { $0.reason == nil })

        let ready = MCPReadinessPolicy.readyStatuses(for: servers)
        XCTAssertEqual(ready.map(\.state), [.ready, .ready])
        XCTAssertTrue(ready.allSatisfy { $0.evidence.contains("startup barrier") })
        XCTAssertTrue(ready.allSatisfy { $0.evidence.contains("inventory and use remain unproven") })
        XCTAssertTrue(ready[0].accessibilitySummary.contains("grokbuild-browser: Process ready"))
    }

    func testFailedAndStoppedReceiptsNameOnlyTheConfiguredServers() {
        let failed = MCPReadinessPolicy.failedStatuses(
            for: ["grokbuild-browser"],
            reason: "fixture failed"
        )
        XCTAssertEqual(failed, [
            MCPServerStatus(
                name: "grokbuild-browser",
                state: .failed,
                reason: "fixture failed",
                evidence: "The current process generation did not reach the ready boundary."
            )
        ])

        let stopped = MCPReadinessPolicy.stoppedStatuses(for: ["grokbuild-browser"])
        XCTAssertEqual(stopped.first?.state, .stopped)
        XCTAssertEqual(stopped.first?.reason, nil)
        XCTAssertTrue(stopped.first?.evidence.contains("process is stopped") == true)
    }

    func testBarrierIsAReusableNoOpWhenNoMCPServersAreConfigured() async throws {
        let startedAt = Date()
        try await MCPReadinessPolicy.waitForInitialMCPSet([])

        XCTAssertLessThan(
            Date().timeIntervalSince(startedAt),
            0.25,
            "a plain Grok session must not inherit the MCP settle delay"
        )
    }

    func testBarrierWaitsForConfiguredMCPServers() async throws {
        let startedAt = Date()
        try await MCPReadinessPolicy.waitForInitialMCPSet([
            MCPServerConfig(name: "fixture-mcp")
        ])

        XCTAssertGreaterThanOrEqual(
            Date().timeIntervalSince(startedAt),
            Double(MCPReadinessPolicy.settleMilliseconds) / 1_000.0 * 0.8
        )
    }

    func testBarrierIsCancellable() async {
        let task = Task {
            do {
                try await MCPReadinessPolicy.waitForInitialMCPSet([
                    MCPServerConfig(name: "fixture-mcp")
                ])
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        task.cancel()

        let wasCancelled = await task.value
        XCTAssertTrue(wasCancelled)
    }
}

@MainActor
final class MCPReadinessLaunchTests: XCTestCase {
    func testACPProcessDoesNotBecomeReadyUntilMCPBarrierSettles() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-mcp-readiness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let scriptURL = fixtureRoot.appendingPathComponent("fake-grok")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*\"id\":([0-9]+).*/\\1/')
          case "$line" in
            *'\"method\":\"initialize\"'*)
              printf '{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{}}\\n' "$id"
              ;;
            *'\"method\":\"session/new\"'*)
              printf '{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":{\"sessionId\":\"mcp-readiness-fixture\"}}\\n' "$id"
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

        let process = GrokProcess()
        let startedAt = Date()
        await process.start(
            workspace: Workspace(name: "fixture", path: fixtureRoot),
            options: GrokLaunchOptions(
                mcpServers: [MCPServerConfig(name: "fixture-mcp")]
            )
        )

        XCTAssertEqual(process.state, .ready)
        XCTAssertGreaterThanOrEqual(
            Date().timeIntervalSince(startedAt),
            Double(MCPReadinessPolicy.settleMilliseconds) / 1_000.0 * 0.8
        )
        await process.stop()
    }
}
