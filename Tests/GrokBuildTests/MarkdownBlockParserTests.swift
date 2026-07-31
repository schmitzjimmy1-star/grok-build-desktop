import XCTest
@testable import GrokBuild

final class MarkdownBlockParserTests: XCTestCase {
    func testCurrencyAndShellVariablesStayText() {
        let costBlocks = MarkdownBlockParser.parse("It costs $5 to $10")
        XCTAssertEqual(costBlocks.count, 1)
        if case .text(let s) = costBlocks[0] {
            XCTAssertEqual(s, "It costs $5 to $10")
        } else {
            XCTFail("Expected plain text block")
        }

        let pathBlocks = MarkdownBlockParser.parse("echo $PATH now")
        XCTAssertEqual(pathBlocks.count, 1)
        if case .text(let s) = pathBlocks[0] {
            XCTAssertEqual(s, "echo $PATH now")
        } else {
            XCTFail("Expected plain text block")
        }
    }

    func testInlineMathDetectedWithMathSignals() {
        assertInlineLatex(in: MarkdownBlockParser.parse("Euler: $e^{i\\pi}+1=0$"), expected: "e^{i\\pi}+1=0")
        assertInlineLatex(in: MarkdownBlockParser.parse("value $x_1$"), expected: "x_1")
        assertInlineLatex(in: MarkdownBlockParser.parse("$\\alpha$"), expected: "\\alpha")
    }

    func testDisplayMathStillParsed() {
        let blocks = MarkdownBlockParser.parse("Block $$a^2+b^2=c^2$$ end")
        XCTAssertEqual(blocks.count, 3)
        if case .latex(let expr, let display) = blocks[1] {
            XCTAssertEqual(expr, "a^2+b^2=c^2")
            XCTAssertTrue(display)
        } else {
            XCTFail("Expected display latex block")
        }
    }

    func testLooksLikeInlineMathPredicate() {
        XCTAssertFalse(MarkdownBlockParser.looksLikeInlineMath("5"))
        XCTAssertFalse(MarkdownBlockParser.looksLikeInlineMath("PATH"))
        XCTAssertTrue(MarkdownBlockParser.looksLikeInlineMath("x^2"))
        XCTAssertTrue(MarkdownBlockParser.looksLikeInlineMath("\\alpha"))
        XCTAssertTrue(MarkdownBlockParser.looksLikeInlineMath("a_1"))
        XCTAssertTrue(MarkdownBlockParser.looksLikeInlineMath("x=y"))
    }

    func testTextBlocksParseHeadingsTablesListsAndCode() {
        let markdown = """
        ## Browser access

        | Tool | Status |
        | --- | --- |
        | Chrome | Ready |
        | Safari | Off |

        - Keep the toolbar quiet
        - Show errors when actionable

        ```swift
        let glass = true
        ```
        """

        let blocks = MarkdownTextBlockParser.parse(markdown).map(\.content)
        XCTAssertEqual(
            blocks,
            [
                .heading(level: 2, text: "Browser access"),
                .table(
                    headers: ["Tool", "Status"],
                    rows: [
                        ["Chrome", "Ready"],
                        ["Safari", "Off"],
                    ]
                ),
                .unorderedList([
                    "Keep the toolbar quiet",
                    "Show errors when actionable",
                ]),
                .code(language: "swift", text: "let glass = true"),
            ]
        )
    }

    func testTextBlocksParseQuotesOrderedListsAndDividers() {
        let markdown = """
        > Calm interfaces are allowed.
        > Even in developer tools.

        1. Read
        2. Build
        3. Verify

        ---
        """

        XCTAssertEqual(
            MarkdownTextBlockParser.parse(markdown).map(\.content),
            [
                .quote("Calm interfaces are allowed.\nEven in developer tools."),
                .orderedList(["Read", "Build", "Verify"]),
                .divider,
            ]
        )
    }

    private func assertInlineLatex(in blocks: [MarkdownBlock], expected: String) {
        let latexBlocks = blocks.compactMap { block -> (String, Bool)? in
            if case .latex(let expr, let display) = block { return (expr, display) }
            return nil
        }
        XCTAssertEqual(latexBlocks.count, 1)
        XCTAssertEqual(latexBlocks[0].0, expected)
        XCTAssertFalse(latexBlocks[0].1)
    }
}
