import Foundation
import XCTest
@testable import GrokBuild

/// Agentic roadmap Slice 9: the incremental `StreamingMarkdownAccumulator` must be
/// byte-for-byte equivalent to the batch `StreamingMarkdownPresentation.make` at every
/// chunk boundary, while doing O(appended) work per flush instead of re-scanning the
/// full accumulated string on the main actor.
final class StreamingPresentationTests: XCTestCase {
    /// Deterministic pseudo-random chunker (seeded LCG — tests must not use system
    /// randomness or dates per the repo's resume-safety rules).
    private struct SeededChunker {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }
        mutating func next(upTo limit: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33) % limit + 1
        }
    }

    private let corpus: [String] = [
        // Plain prose with normalization targets.
        "Hello\u{00A0}world\u{200B} line one\r\nline two\rline three\u{202F}end",
        // Streaming code fence that opens, closes, then opens again.
        "Intro\n```swift\nlet a = 1\n```\nMiddle prose\n```\npartial fence body",
        // Fence where the opening backticks arrive mid-line.
        "Text\n``",
        // Table that becomes stable after a boundary, then a trailing unstable table.
        "| A | B |\n| --- | --- |\n| 1 | 2 |\n\nDone.\n| C | D |\n| --- | --- |\n| 3 |",
        // Header + separator with no body rows yet (must not withhold).
        "| A | B |\n| --- | --- |",
        // Dash-only separator (no pipes) between pipe rows.
        "| A |\n---\n| 1 |\n| 2 |",
        // A broken run followed by a fresh valid table at the tail.
        "| A |\n| --- |\n| 1 |\nplain text\n| X |\n| --- |\n| 9 |",
        // CRLF everywhere, including inside a table.
        "| A |\r\n| --- |\r\n| 1 |\r\n",
        // Control characters and bidi marks that normalization strips.
        "safe\u{0007}text\u{202E}more\u{FEFF}end\n| P |\n| --- |\n| q |",
        // Multi-byte content (emoji + CJK) across boundaries.
        "绳一😀二三\n```\n四五六😀\n```\n| 七 | 八 |\n| --- | --- |\n| 😀 | 九 |",
    ]

    func testAccumulatorMatchesBatchPresentationAtEveryChunkBoundary() {
        for (docIndex, doc) in corpus.enumerated() {
            for seed in [UInt64(1), 7, 42, 1234] {
                var chunker = SeededChunker(seed: seed &+ UInt64(docIndex) &* 97)
                var accumulator = StreamingMarkdownAccumulator()
                var fed = ""
                var remaining = Substring(doc)
                while !remaining.isEmpty {
                    let take = min(chunker.next(upTo: 7), remaining.count)
                    let chunk = String(remaining.prefix(take))
                    remaining = remaining.dropFirst(take)
                    fed += chunk
                    accumulator.append(chunk)

                    let incremental = accumulator.makePresentation()
                    let batch = StreamingMarkdownPresentation.make(fed)
                    XCTAssertEqual(
                        incremental, batch,
                        "doc \(docIndex) seed \(seed) diverged after feeding \(fed.count) chars"
                    )
                }
                XCTAssertEqual(accumulator.consumedRawUTF8Count, doc.utf8.count)
            }
        }
    }

    func testSingleCharacterChunkingMatchesBatchForFenceAndTableDocs() {
        for doc in corpus {
            var accumulator = StreamingMarkdownAccumulator()
            var fed = ""
            for character in doc {
                let chunk = String(character)
                fed += chunk
                accumulator.append(chunk)
                XCTAssertEqual(
                    accumulator.makePresentation(),
                    StreamingMarkdownPresentation.make(fed),
                    "single-char divergence after \(fed.count) chars"
                )
            }
        }
    }

    func testResetRestoresPristineState() {
        var accumulator = StreamingMarkdownAccumulator()
        accumulator.append("```\nopen fence")
        XCTAssertEqual(accumulator.makePresentation().withheldConstruct, .codeFence)
        accumulator.reset()
        XCTAssertEqual(accumulator.consumedRawUTF8Count, 0)
        XCTAssertEqual(accumulator.makePresentation(), StreamingMarkdownPresentation.make(""))
        accumulator.append("plain")
        XCTAssertEqual(accumulator.makePresentation().visibleText, "plain")
    }

    /// Source contracts: the flush feeds the accumulator with the exact appended batch,
    /// settled bubbles never compute a streaming scan, and desyncs rebuild once.
    func testStreamingPresentationWiring() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let chatStoreSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Services/ChatStore.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(chatStoreSource.contains("updateStreamingPresentation(messageID: id, appended: batch"),
                      "the paced flush must feed the accumulator its exact appended batch")
        XCTAssertTrue(chatStoreSource.contains("updateStreamingPresentation(messageID: id, appended: remaining"),
                      "the final drain must feed the accumulator too")
        XCTAssertTrue(chatStoreSource.contains("streamingMarkdownAccumulator.consumedRawUTF8Count != fullContent.utf8.count - appended.utf8.count"),
                      "a raw-length desync must trigger a full rebuild, never stale incremental state")
        XCTAssertTrue(chatStoreSource.contains("clearStreamingPresentation()"),
                      "turn teardown must clear the per-turn presentation")

        let bubbleSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/MessageBubble.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(bubbleSource.contains("streamingPresentation\n                            ?? StreamingMarkdownPresentation.make(message.content)")
                      || bubbleSource.contains("streamingPresentation ?? StreamingMarkdownPresentation.make(message.content)"),
                      "the batch scan survives only as a fallback")
        let assistantBranch = try XCTUnwrap(bubbleSource.range(of: "if isStreaming {"))
        let beforeBranch = String(bubbleSource[..<assistantBranch.lowerBound])
        XCTAssertFalse(beforeBranch.contains("StreamingMarkdownPresentation.make"),
                       "settled bubbles must not pay for a streaming scan outside the streaming branch")
    }

    /// Source contracts: transcript writes chain FIFO off the main actor, the layout
    /// stamp waits for its transcript write, and quitting flushes synchronously.
    func testTranscriptPersistenceIsAsyncOrderedAndQuitSafe() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )

        let persistStart = try XCTUnwrap(contentSource.range(of: "private func persistSessionLayout"))
        let persistEnd = try XCTUnwrap(
            contentSource.range(of: "private func flushTranscriptsForTermination", range: persistStart.upperBound..<contentSource.endIndex)
        )
        let persistBody = String(contentSource[persistStart.lowerBound..<persistEnd.lowerBound])
        XCTAssertTrue(persistBody.contains("await previous?.value"),
                      "writes must chain FIFO so metadata cannot regress out of order")
        XCTAssertTrue(persistBody.contains("GrokBuildBackgroundWork.run"),
                      "the transcript write must leave the main actor")
        XCTAssertTrue(persistBody.contains("encodeAndSaveSessionLayout(recordFlushReceipt: true)"),
                      "the layout stamp must run only after its transcript write completes")

        let terminationStart = try XCTUnwrap(contentSource.range(of: "private func flushTranscriptsForTermination"))
        let terminationEnd = try XCTUnwrap(
            contentSource.range(of: "private func encodeAndSaveSessionLayout", range: terminationStart.upperBound..<contentSource.endIndex)
        )
        let terminationBody = String(contentSource[terminationStart.lowerBound..<terminationEnd.lowerBound])
        XCTAssertTrue(terminationBody.contains("SessionMessageStore.saveAll(dirtyMessages)"),
                      "quit must flush synchronously so an in-flight window cannot lose the last turn")
        XCTAssertTrue(contentSource.contains("NSApplication.willTerminateNotification"),
                      "the terminate hook must be observed")
    }
}
