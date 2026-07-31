import XCTest
@testable import GrokBuild

final class AppMenuTests: XCTestCase {
    func testUpdateMenuUsesStandardApplicationMenuCopy() {
        XCTAssertEqual(
            AppMenuCopy.updateMenuTitle(hasActionableUpdate: false),
            "Check for Updates…"
        )
        XCTAssertEqual(
            AppMenuCopy.updateMenuTitle(hasActionableUpdate: true),
            "Updates Available…"
        )
    }
}
