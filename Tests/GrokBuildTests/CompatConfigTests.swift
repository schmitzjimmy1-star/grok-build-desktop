import XCTest
@testable import GrokBuild

final class CompatConfigTests: XCTestCase {
    func testCompatConfigRewriteAddsSection() {
        let rewritten = CompatConfigStore.rewrite("", flavor: .cursor, enabled: true)
        XCTAssertTrue(rewritten.contains("[compat.cursor]"))
        for capability in CompatFlavor.cursor.supportedCapabilities {
            XCTAssertTrue(rewritten.contains("\(capability) = true"))
        }
        XCTAssertFalse(rewritten.contains("enabled ="))
    }

    func testCompatConfigRewriteUpdatesExisting() {
        let original = """
        [compat.claude]
        enabled = false
        """
        let rewritten = CompatConfigStore.rewrite(original, flavor: .claude, enabled: true)
        XCTAssertEqual(CompatConfigStore.isEnabled(.claude, contents: rewritten), true)
        XCTAssertFalse(rewritten.contains("enabled ="))
        XCTAssertTrue(rewritten.contains("skills = true"))
        XCTAssertTrue(rewritten.contains("sessions = true"))
    }

    func testCompatAggregateIsOffWhenAnySupportedCellIsOff() {
        let original = """
        [compat.cursor]
        skills = true
        rules = false
        """
        XCTAssertFalse(CompatConfigStore.isEnabled(.cursor, contents: original))
    }

    func testCodexWritesOnlyCurrentlySupportedSessionsCell() {
        let rewritten = CompatConfigStore.rewrite("", flavor: .codex, enabled: false)
        XCTAssertTrue(rewritten.contains("sessions = false"))
        XCTAssertFalse(rewritten.contains("skills ="))
        XCTAssertFalse(rewritten.contains("enabled ="))
    }
}
