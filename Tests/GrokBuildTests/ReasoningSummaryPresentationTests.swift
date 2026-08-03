import Foundation
import XCTest
@testable import GrokBuild

final class ReasoningSummaryPresentationTests: XCTestCase {
    @MainActor
    func testFixtureTravelsThroughACPAndCollapsesExactlyOnceAtSettlement() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-slice6-summary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let scriptURL = root.appendingPathComponent("fake-grok")
        let fixturePath = try fixtureURL().path
        let script = """
        #!/bin/sh
        fixture='\(fixturePath)'
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"slice-6-public-summary-fixture","models":{"currentModelId":"grok-4.5","availableModels":[]}}}\\n' "$id" ;;
            *'"method":"session/set_model"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"model":{"Ok":"grok-4.5"}}}}\\n' "$id" ;;
            *'"method":"session/prompt"'*)
              while IFS= read -r event; do printf '%s\\n' "$event"; done < "$fixture"
              printf '{"jsonrpc":"2.0","method":"_x.ai/session/update","params":{"sessionId":"slice-6-public-summary-fixture","update":{"sessionUpdate":"turn_completed","stop_reason":"end_turn"}}}\\n'
              printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "$id"
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        GrokProcess.cliOverrideForTests = scriptURL
        defer { GrokProcess.cliOverrideForTests = nil }
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: nil)
        await store.start(workspace: Workspace(name: "slice-6", path: root))
        let sent = await store.sendAndWait("Render the public summary fixture")

        XCTAssertTrue(sent)
        XCTAssertEqual(store.reasoningSummaryChunks, try loadFixtureChunks())
        XCTAssertEqual(store.reasoningSummaryChunks.count, 5)
        XCTAssertFalse(store.isThinkingExpanded)
        XCTAssertNotNil(store.thinkingDuration)
        await store.shutdownPermanently()
    }

    func testPublicSummaryFixtureRendersEveryStageOnceInBackendOrder() throws {
        let chunks = try loadFixtureChunks()
        let presentation = ReasoningSummaryPresentation.make(chunks: chunks, expanded: false)

        XCTAssertEqual(presentation.sourceStageCount, 5)
        XCTAssertEqual(presentation.stages.map(\.ordinal), [1, 2, 3, 4, 5])
        XCTAssertEqual(presentation.stages.map(\.kind), [
            .plan, .currentAction, .fallback, .synthesis, .completion,
        ])
        XCTAssertEqual(presentation.stages.map(\.text), chunks)
        XCTAssertEqual(Set(presentation.stages.map(\.text)).count, chunks.count)
        XCTAssertFalse(presentation.isTruncated)
    }

    func testPresentationBoundaryPreventsFusedChunksWithoutChangingSources() throws {
        let chunks = try loadFixtureChunks()
        let original = chunks
        let presentation = ReasoningSummaryPresentation.make(chunks: chunks, expanded: false)

        XCTAssertEqual(chunks, original)
        XCTAssertTrue(presentation.presentationOnlyText.contains("now.\n\nFallback:"))
        XCTAssertFalse(presentation.presentationOnlyText.contains("now.Fallback:"))
        XCTAssertEqual(
            presentation.presentationOnlyText.components(separatedBy: "Fallback:").count - 1,
            1
        )
    }

    func testExplicitWhitespaceWithinEachBackendChunkIsPreserved() {
        let chunks = ["Plan:\n  - first\n  - second", "Current action:\tchecking source"]
        let presentation = ReasoningSummaryPresentation.make(chunks: chunks, expanded: false)

        XCTAssertEqual(presentation.stages.map(\.text), chunks)
    }

    func testTokenSizedACPChunksJoinOnlyAcrossExplicitBoundaries() {
        let chunks = [
            "The", " user", " wants", " me", " to", ":\n", "1", ".", " No", " tools", " and", " no", " files", ".",
        ]
        let presentation = ReasoningSummaryPresentation.make(chunks: chunks, expanded: false)

        XCTAssertEqual(presentation.sourceChunkCount, 14)
        XCTAssertEqual(presentation.sourceStageCount, 1)
        XCTAssertEqual(presentation.stages.map(\.text), ["The user wants me to:\n1. No tools and no files."])
    }

    func testCompactAndExpandedViewsRemainBoundedAndNeverDuplicateStages() {
        let chunks = (1...30).map { index in
            "Stage \(index): " + String(repeating: "evidence ", count: 180) + "end."
        }
        let compact = ReasoningSummaryPresentation.make(chunks: chunks, expanded: false)
        let expanded = ReasoningSummaryPresentation.make(chunks: chunks, expanded: true)

        XCTAssertLessThanOrEqual(compact.stages.count, ReasoningSummaryPresentation.compactStageLimit)
        XCTAssertLessThanOrEqual(compact.displayedCharacterCount, ReasoningSummaryPresentation.compactCharacterLimit)
        XCTAssertLessThanOrEqual(expanded.stages.count, ReasoningSummaryPresentation.expandedStageLimit)
        XCTAssertLessThanOrEqual(expanded.displayedCharacterCount, ReasoningSummaryPresentation.expandedCharacterLimit)
        XCTAssertEqual(Set(compact.stages.map(\.ordinal)).count, compact.stages.count)
        XCTAssertEqual(Set(expanded.stages.map(\.ordinal)).count, expanded.stages.count)
        XCTAssertTrue(compact.isTruncated)
        XCTAssertTrue(expanded.isTruncated)
    }

    func testThinkingChromeExposesOrderedAccessibleStagesAndBoundedExpansion() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let chrome = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Views/GrokChatChrome.swift"),
            encoding: .utf8
        )
        let store = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        let persistence = try String(
            contentsOf: root.appendingPathComponent("GrokBuild/Services/SessionLayoutStore.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(chrome.contains("reasoning summary stage"))
        XCTAssertTrue(chrome.contains("accessibilitySortPriority"))
        XCTAssertTrue(chrome.contains("Show more summary"))
        XCTAssertTrue(chrome.contains("Showing the first"))
        XCTAssertTrue(store.contains("reasoningSummaryChunks.append(publicSummary)"))
        XCTAssertTrue(store.contains("isThinkingExpanded = false"))
        XCTAssertFalse(persistence.contains("reasoningSummaryChunks"))
    }

    func testFixtureContainsOnlyPublicSummaryUpdates() throws {
        let url = try fixtureURL()
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text.split(whereSeparator: \.isNewline).count, 5)
        XCTAssertEqual(text.components(separatedBy: "agent_thought_chunk").count - 1, 5)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("chain_of_thought"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("system_prompt"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("authorization"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("api_key"))
    }

    private func loadFixtureChunks() throws -> [String] {
        let text = try String(contentsOf: fixtureURL(), encoding: .utf8)
        return try text.split(whereSeparator: \.isNewline).map { line in
            let envelope = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            )
            let params = try XCTUnwrap(envelope["params"] as? [String: Any])
            let update = try XCTUnwrap(params["update"] as? [String: Any])
            let content = try XCTUnwrap(update["content"] as? [String: Any])
            return try XCTUnwrap(content["text"] as? String)
        }
    }

    private func fixtureURL() throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(
                forResource: "reasoning-summary-stages",
                withExtension: "jsonl",
                subdirectory: "Fixtures/ActivityParity"
            )
        )
    }
}
