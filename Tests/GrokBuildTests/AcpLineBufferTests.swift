import XCTest
@testable import GrokBuild

final class AcpLineBufferTests: XCTestCase {
    func testDrainsCompleteLinesAndKeepsRemainder() {
        var buffer = Data()
        let lines = AcpLineBuffer.drainLines(
            buffer: &buffer,
            appending: Data("{\"a\":1}\n{\"b\":2}\npartial".utf8)
        )
        XCTAssertEqual(lines, ["{\"a\":1}", "{\"b\":2}"])
        XCTAssertEqual(buffer, Data("partial".utf8))

        let more = AcpLineBuffer.drainLines(buffer: &buffer, appending: Data(" done\n".utf8))
        XCTAssertEqual(more, ["partial done"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testChunkWithoutNewlineReturnsNothing() {
        var buffer = Data()
        XCTAssertEqual(AcpLineBuffer.drainLines(buffer: &buffer, appending: Data("no newline yet".utf8)), [])
        XCTAssertEqual(buffer, Data("no newline yet".utf8))
    }

    /// A multi-byte UTF-8 codepoint split across two pipe reads must survive.
    /// The previous String-based reader decoded each chunk independently and
    /// silently dropped the whole chunk when a read ended mid-codepoint.
    func testMultiByteCodepointSplitAcrossChunksSurvives() {
        let line = Data("{\"text\":\"caf\u{00E9}\u{1F600}\"}\n".utf8)
        // Split inside the 4-byte emoji sequence.
        let splitPoint = line.count - 4
        var buffer = Data()

        XCTAssertEqual(AcpLineBuffer.drainLines(buffer: &buffer, appending: line.prefix(splitPoint)), [])
        let lines = AcpLineBuffer.drainLines(buffer: &buffer, appending: line.suffix(from: splitPoint))
        XCTAssertEqual(lines, ["{\"text\":\"caf\u{00E9}\u{1F600}\"}"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testManyLinesInOneChunk() {
        var buffer = Data()
        let payload = (1...200).map { "line-\($0)" }.joined(separator: "\n") + "\n"
        let lines = AcpLineBuffer.drainLines(buffer: &buffer, appending: Data(payload.utf8))
        XCTAssertEqual(lines.count, 200)
        XCTAssertEqual(lines.first, "line-1")
        XCTAssertEqual(lines.last, "line-200")
        XCTAssertTrue(buffer.isEmpty)
    }

    func testCarriageReturnIsPreservedForCallerTrimming() {
        var buffer = Data()
        let lines = AcpLineBuffer.drainLines(buffer: &buffer, appending: Data("crlf\r\n".utf8))
        XCTAssertEqual(lines, ["crlf\r"])
    }

    func testEmptyLinesAreYieldedEmpty() {
        var buffer = Data()
        let lines = AcpLineBuffer.drainLines(buffer: &buffer, appending: Data("\n\nx\n".utf8))
        XCTAssertEqual(lines, ["", "", "x"])
    }
}
