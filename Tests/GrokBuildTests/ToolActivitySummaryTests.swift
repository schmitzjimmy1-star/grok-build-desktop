import XCTest
@testable import GrokBuild

final class ToolActivitySummaryTests: XCTestCase {
    private func item(
        title: String,
        kind: String,
        status: String? = "completed",
        isFailed: Bool = false,
        isRecovered: Bool = false
    ) -> ToolActivitySummaryPresentation.Item {
        .init(
            title: title,
            kind: kind,
            status: status,
            isFailed: isFailed,
            isRecovered: isRecovered
        )
    }

    func testLiveCommandSummaryDoesNotExposeArguments() {
        let summary = ToolActivitySummaryPresentation.summary(for: [
            item(title: "rm -rf definitely-not-for-display", kind: "execute", status: "running")
        ])

        XCTAssertEqual(summary, "Running command")
        XCTAssertFalse(summary.contains("rm -rf"))
    }

    func testActiveStatusNormalizationIncludesPendingAndQueued() {
        XCTAssertTrue(ToolActivitySummaryPresentation.isActive(" in_progress "))
        XCTAssertTrue(ToolActivitySummaryPresentation.isActive("queued"))
        XCTAssertFalse(ToolActivitySummaryPresentation.isActive("succeeded"))
        XCTAssertFalse(ToolActivitySummaryPresentation.isActive(nil))
    }

    func testSettledSummaryGroupsCategoriesInReceiptOrder() {
        let summary = ToolActivitySummaryPresentation.summary(for: [
            item(title: "Read README", kind: "read"),
            item(title: "Read Package.swift", kind: "read"),
            item(title: "Search sources", kind: "search"),
            item(title: "swift test", kind: "terminal")
        ])

        XCTAssertEqual(summary, "Read files · Searched · Ran command")
    }

    func testUnresolvedFailureOutranksCategorySummary() {
        XCTAssertEqual(
            ToolActivitySummaryPresentation.summary(for: [
                item(title: "Read", kind: "read"),
                item(title: "Build", kind: "execute", status: "failed", isFailed: true)
            ]),
            "1 tool call failed"
        )
    }

    func testRecoveredFailureDoesNotPoisonSettledSummary() {
        XCTAssertEqual(
            ToolActivitySummaryPresentation.summary(for: [
                item(
                    title: "Build retry",
                    kind: "execute",
                    status: "failed",
                    isFailed: true,
                    isRecovered: true
                ),
                item(title: "Build retry", kind: "execute")
            ]),
            "Ran commands"
        )
    }
}
