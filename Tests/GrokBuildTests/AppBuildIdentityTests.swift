import Foundation
import XCTest
@testable import GrokBuild

final class AppBuildIdentityTests: XCTestCase {
    func testStampedPersonalBuildIdentifiesExactSourceLine() {
        let identity = AppBuildIdentity(infoDictionary: [
            "GrokBuildSourceRepository": "https://github.com/schmitzjimmy1-star/grok-build-desktop",
            "GrokBuildSourceBranch": "codex/warm-glass-ui",
            "GrokBuildSourceCommit": "854fda58aa8cb237772f21677259a052173c72c3",
            "GrokBuildSourceDirty": false,
            "GrokBuildBuildChannel": "personal",
        ])

        XCTAssertTrue(identity.isStamped)
        XCTAssertEqual(identity.shortCommit, "854fda58")
        XCTAssertEqual(identity.summary, "Personal • codex/warm-glass-ui @ 854fda58")
        XCTAssertEqual(
            identity.commitURL?.absoluteString,
            "https://github.com/schmitzjimmy1-star/grok-build-desktop/commit/854fda58aa8cb237772f21677259a052173c72c3"
        )
    }

    func testDirtyBuildCannotMasqueradeAsSettledReceipt() {
        let identity = AppBuildIdentity(infoDictionary: [
            "GrokBuildSourceBranch": "codex/warm-glass-ui",
            "GrokBuildSourceCommit": "0123456789abcdef",
            "GrokBuildSourceDirty": true,
        ])

        XCTAssertEqual(identity.summary, "Personal • codex/warm-glass-ui @ 01234567 (dirty)")
    }

    func testUnstampedBuildIsExplicitInsteadOfInventingACommit() {
        let identity = AppBuildIdentity(infoDictionary: [:])

        XCTAssertFalse(identity.isStamped)
        XCTAssertEqual(identity.repositoryURL, AppBuildIdentity.canonicalRepositoryURL)
        XCTAssertEqual(identity.summary, "Personal • unstamped source build")
        XCTAssertNil(identity.commitURL)
    }

    func testBothBundleBuildersAndCanonicalReceiptCarryTheTattoo() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "scripts/build-macos-app.sh",
            "scripts/build-dev-app.sh",
        ]

        for path in paths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains("GrokBuildBuildChannel"), path)
            XCTAssertTrue(source.contains("GrokBuildSourceRepository"), path)
            XCTAssertTrue(source.contains("GrokBuildSourceBranch"), path)
            XCTAssertTrue(source.contains("GrokBuildSourceCommit"), path)
            XCTAssertTrue(source.contains("GrokBuildSourceDirty"), path)
            XCTAssertTrue(source.contains("build-identity.sh"), path)
        }

        let receipt = try String(
            contentsOf: root.appendingPathComponent("CANONICAL_WORKTREE.md"),
            encoding: .utf8
        )
        XCTAssertTrue(receipt.contains("grok-build-desktop"))
        XCTAssertTrue(receipt.contains("Grok-Build-GUI"))
        XCTAssertTrue(receipt.contains("DO NOT BUILD, INSTALL, OR CONTINUE"))
    }
}
