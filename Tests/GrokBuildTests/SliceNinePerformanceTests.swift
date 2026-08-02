import XCTest
@testable import GrokBuild

final class SliceNinePerformanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RichContentCache.resetForTests()
    }

    override func tearDown() {
        RichContentCache.resetForTests()
        super.tearDown()
    }

    func testBackgroundHistoryWorkRunsOffMainActor() async {
        let ranOnMainThread = await GrokBuildBackgroundWork.run(
            { Thread.isMainThread },
            priority: .utility
        )

        XCTAssertFalse(ranOnMainThread)
    }

    func testRichContentCacheReusesParsedBlocksAndKeysIdentity() {
        let messageID = UUID()
        let source = "Before\n\n```mermaid\nflowchart LR\nA-->B\n```"
        let regularKey = RichContentCache.key(
            messageID: messageID,
            text: source,
            widthClass: .regular
        )
        let narrowKey = RichContentCache.key(
            messageID: messageID,
            text: source,
            widthClass: .narrow
        )
        let otherMessageKey = RichContentCache.key(
            messageID: UUID(),
            text: source,
            widthClass: .regular
        )
        let parsed = MarkdownBlockParser.parse(source)

        XCTAssertNotEqual(regularKey, narrowKey)
        XCTAssertNotEqual(regularKey, otherMessageKey)
        XCTAssertNil(RichContentCache.blocks(for: regularKey))

        RichContentCache.store(parsed, for: regularKey)

        XCTAssertEqual(RichContentCache.blocks(for: regularKey), parsed)
        XCTAssertNil(RichContentCache.blocks(for: narrowKey))
        XCTAssertEqual(RichContentCache.stats.blockHits, 1)
        XCTAssertEqual(RichContentCache.stats.blockMisses, 2)
    }

    func testRichContentCacheStoresInlineTextAndWebHeightsSeparately() {
        let text = "A paragraph with [a link](https://example.com)."
        let textKey = RichContentCache.textKey(text)
        let textBlocks = MarkdownTextBlockParser.parse(text)
        RichContentCache.store(textBlocks, for: textKey)

        XCTAssertEqual(RichContentCache.textBlocks(for: textKey), textBlocks)

        RichContentCache.storeWebHeight(144, kind: .mermaid, source: "A-->B")
        RichContentCache.storeWebHeight(52, kind: .latex, source: "x^2", displayMode: true)

        XCTAssertEqual(RichContentCache.cachedWebHeight(kind: .mermaid, source: "A-->B"), 144)
        XCTAssertEqual(
            RichContentCache.cachedWebHeight(kind: .latex, source: "x^2", displayMode: true),
            52
        )
        XCTAssertNil(RichContentCache.cachedWebHeight(kind: .latex, source: "x^2"))
        XCTAssertEqual(RichContentCache.stats.textHits, 1)
        XCTAssertEqual(RichContentCache.stats.webHeightHits, 2)
        XCTAssertEqual(RichContentCache.stats.webHeightMisses, 1)
    }

    func testRichContentCacheRemainsBounded() {
        for index in 0..<(RichContentCache.maximumEntries + 16) {
            let key = RichContentCache.key(
                messageID: UUID(),
                text: "message-\(index)"
            )
            RichContentCache.store([.text("message-\(index)")], for: key)
        }

        XCTAssertLessThanOrEqual(
            RichContentCache.stats.entryCount,
            RichContentCache.maximumEntries
        )
    }
}
