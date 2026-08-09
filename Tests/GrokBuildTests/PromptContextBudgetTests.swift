import Foundation
import XCTest
@testable import GrokBuild

final class PromptContextBudgetTests: XCTestCase {
    func testProjectInstructionsMeaningfullyReduceFreshTurnContextWithoutLosingContracts() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let data = try Data(contentsOf: root.appendingPathComponent("AGENTS.md"))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertGreaterThanOrEqual(
            PromptContextBudget.reductionPercent(currentBytes: data.count),
            PromptContextBudget.minimumProjectInstructionReductionPercent
        )
        for required in [
            "CANONICAL_WORKTREE.md", "ARCHITECTURE.md", "make test", "make ship",
            "Computer Use", "DD2GCQJVB4", "GrokBuildComputerUseMCP", "agent-desktop",
            "schmitzjimmy1-star/grok-build-desktop", "rimusz/grok-build-desktop",
            "/Applications/GrokBuild.app", "docs/OUTSTANDING.md",
        ] {
            XCTAssertTrue(text.contains(required), "compressed instructions lost required contract: \(required)")
        }
    }

    func testContributorReportDefersUnrequestedSchemasAndRetainsRequiredFields() {
        let report = PromptContextBudget.report(
            projectInstructions: Data(repeating: 1, count: 2_400),
            skillDescriptions: ["browser skill", "computer use skill"],
            mcpServerDescriptors: ["grokbuild-browser", "grokbuild-computer-use"],
            requestedToolSchemas: [Data(repeating: 2, count: 120)],
            deferredToolSchemas: [Data(repeating: 3, count: 8_000)],
            sessionHistory: Data(repeating: 4, count: 80)
        )

        XCTAssertEqual(report.bytes(for: .projectInstructions), 2_400)
        XCTAssertEqual(report.bytes(for: .requestedToolSchemas), 120)
        XCTAssertEqual(report.deferredBytes, 8_000)
        XCTAssertFalse(report.contributors.first { $0.kind == .requestedToolSchemas }!.isDeferred)
        XCTAssertEqual(report.bytes(for: .providerWrapper), 0, "opaque provider bytes must never be guessed")
    }
}

final class OwnedProcessLedgerTests: XCTestCase {
    func testLedgerRequiresExactTabBackendGenerationAndChildFingerprint() {
        let tab = UUID()
        let child = OwnedProcessFingerprint(
            pid: 42,
            executablePath: "/tmp/fixture-child",
            startSeconds: 100,
            startMicroseconds: 2
        )
        var ledger = OwnedProcessLedger()
        ledger.begin(OwnedProcessIdentity(
            localTabID: tab,
            backendSessionID: nil,
            processGeneration: 7,
            rootPID: 41
        ))
        ledger.record([child])
        ledger.rebindBackend("backend-a")

        XCTAssertTrue(ledger.owns(
            localTabID: tab,
            backendSessionID: "backend-a",
            processGeneration: 7,
            child: child
        ))
        XCTAssertFalse(ledger.owns(localTabID: UUID(), backendSessionID: "backend-a", processGeneration: 7, child: child))
        XCTAssertFalse(ledger.owns(localTabID: tab, backendSessionID: "backend-b", processGeneration: 7, child: child))
        XCTAssertFalse(ledger.owns(localTabID: tab, backendSessionID: "backend-a", processGeneration: 8, child: child))
    }

    func testFiveConsecutiveProcessTreeFixturesEndAtZero() throws {
        for _ in 0..<5 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "sleep 30 & wait"]
            try process.run()
            usleep(40_000)
            let fingerprints = OwnedProcessTree.fingerprints(of: OwnedProcessTree.descendants(of: process.processIdentifier))
            XCTAssertFalse(fingerprints.isEmpty)
            OwnedProcessTree.signal(SIGTERM, to: fingerprints)
            process.terminate()
            process.waitUntilExit()
            usleep(20_000)
            XCTAssertTrue(fingerprints.allSatisfy { !OwnedProcessTree.stillMatches($0) })
        }
    }
}
