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
        XCTAssertEqual(InlineMathNormalizer.normalize("Euler: $e^{i\\pi}+1=0$"), "Euler: e^i\\pi+1=0")
        XCTAssertEqual(InlineMathNormalizer.normalize("value $x_1$"), "value x_1")
        XCTAssertEqual(InlineMathNormalizer.normalize("cost $5"), "cost $5")
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

    func testStandardBackslashMathDelimitersAreParsed() {
        let blocks = MarkdownBlockParser.parse(
            #"Define \(I=\int_0^1 x\,dx\), then \[I=\frac12.\] Done"#
        )
        let latex = blocks.compactMap { block -> (String, Bool)? in
            if case .latex(let expression, let display) = block {
                return (expression, display)
            }
            return nil
        }

        XCTAssertEqual(latex.count, 1)
        XCTAssertEqual(latex[0].0, #"I=\frac12."#)
        XCTAssertTrue(latex[0].1)
        XCTAssertEqual(
            InlineMathNormalizer.normalize(#"Define \(I=\int_0^1 x\,dx\)"#),
            "Define I=∫_0^1 x dx"
        )
    }

    func testInlineMathDoesNotSplitMarkdownTableRows() {
        let markdown = #"""
        | Step | Operation | Result |
        | --- | --- | --- |
        | 1 | Choose \(u=\ln(1+x)\) | \(I=\frac14\) |
        | 2 | Finish | Done |
        """#
        let topLevel = MarkdownBlockParser.parse(markdown)
        XCTAssertEqual(topLevel.count, 1)
        guard case .text(let text) = topLevel[0] else {
            return XCTFail("Expected table to remain one Markdown text block")
        }
        let parsed = MarkdownTextBlockParser.parse(text).map(\.content)
        guard case .table(_, let rows) = parsed.first else {
            return XCTFail("Expected a parsed table")
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(InlineMathNormalizer.normalize(rows[0][1]), "Choose u=ln(1+x)")
        XCTAssertEqual(InlineMathNormalizer.normalize(rows[0][2]), "I=1/4")
        XCTAssertEqual(
            InlineMathNormalizer.normalize(#"\(I=\tfrac{\ln 2}{2}-\tfrac12\left(x-1\right)\)"#),
            "I=ln 2/2-1/2(x-1)"
        )
    }

    func testLooksLikeInlineMathPredicate() {
        XCTAssertFalse(MarkdownBlockParser.looksLikeInlineMath("5"))
        XCTAssertFalse(MarkdownBlockParser.looksLikeInlineMath("PATH"))
        XCTAssertTrue(MarkdownBlockParser.looksLikeInlineMath("[0,1]"))
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

    func testSingleColumnPipeWrappedTable() {
        let blocks = MarkdownTextBlockParser.parse(
            """
            | Range |
            | --- |
            | \\(0\\le x\\le 1\\) |
            """
        ).map(\.content)

        XCTAssertEqual(
            blocks,
            [.table(headers: ["Range"], rows: [[#"\(0\le x\le 1\)"#]])]
        )
        guard case .table(_, let rows) = blocks.first else {
            return XCTFail("Expected a single-column table")
        }
        XCTAssertEqual(InlineMathNormalizer.normalize(rows[0][0]), "0≤ x≤ 1")
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

    func testInlineMarkdownLinksAreStyledAndIndividuallyDiscoverable() {
        let source = "Use [Actor](https://developer.apple.com/documentation/swift/actor) and [Concurrency](https://developer.apple.com/swift/)."
        let links = InlineMarkdownPresentation.links(in: source)

        XCTAssertEqual(links.map(\.title), ["Actor", "Concurrency"])
        XCTAssertEqual(
            links.map(\.destination.absoluteString),
            [
                "https://developer.apple.com/documentation/swift/actor",
                "https://developer.apple.com/swift/",
            ]
        )
        XCTAssertEqual(
            InlineMarkdownPresentation.spokenText(source),
            "Use Actor and Concurrency."
        )
        XCTAssertTrue(InlineMarkdownPresentation.rendered(source).runs.contains { $0.link != nil })
    }

    func testMathAndTableAccessibilityProvideSemanticLabels() {
        XCTAssertEqual(
            MathAccessibility.spokenDescription(#"\frac{1}{2} \le x"#),
            "Equation: 1/2 ≤ x"
        )
        XCTAssertEqual(
            MarkdownTableAccessibility.summary(
                headers: ["Tool", "Status"],
                rows: [["Terminal", "Ready"]]
            ),
            "Table, 2 columns, 1 data row"
        )
        XCTAssertEqual(
            MarkdownTableAccessibility.cellLabel(
                headers: ["Tool", "Status"],
                value: "Ready",
                column: 1
            ),
            "Status: Ready"
        )
        XCTAssertEqual(
            MarkdownTableAccessibility.linearDescription(
                headers: ["Tool", "Status"],
                rows: [["Terminal", "Ready"]]
            ),
            "Row 1: Tool: Terminal; Status: Ready."
        )
        XCTAssertTrue(
            RichContentFallback.mermaid(source: "A-->B")
                .contains("Mermaid source: A-->B")
        )
        XCTAssertTrue(
            RichContentFallback.latex(source: #"x^2"#)
                .contains("Source: x^2")
        )
    }

    func testStreamingPresentationWithholdsIncompleteCodeAndTableConstructs() {
        let code = StreamingMarkdownPresentation.make("Before\n```swift\nlet ready = false")
        XCTAssertEqual(code.visibleText, "Before\n")
        XCTAssertEqual(code.withheldConstruct, .codeFence)

        let table = StreamingMarkdownPresentation.make(
            "| Tool | State |\n| --- | --- |\n| MCP | Ready |"
        )
        XCTAssertEqual(table.withheldConstruct, .table)

        XCTAssertNil(
            StreamingMarkdownPresentation.make("```swift\nlet ready = true\n```").withheldConstruct
        )
    }

    func testTableLayoutUsesReadingWidthAndWeightsLongerColumns() {
        let widths = MarkdownTableLayout.columnWidths(
            headers: ["Area", "Ownership", "Status"],
            rows: [["ACP", "ChatStore owns the generation-bound completion barrier", "Ready"]],
            availableWidth: 720
        )

        XCTAssertEqual(widths.count, 3)
        XCTAssertEqual(widths.reduce(0, +), 720, accuracy: 0.5)
        XCTAssertGreaterThan(widths[1], widths[0])
        XCTAssertGreaterThan(widths[1], widths[2])
        XCTAssertTrue(widths.allSatisfy { $0 >= MarkdownTableLayout.minimumColumnWidth })
    }

}
