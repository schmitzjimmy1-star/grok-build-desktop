import XCTest
@testable import GrokBuild

/// OUTSTANDING close-out (2026-08-08) — O-5 (commit/PR popover
/// instrumentation), O-6 (dismissible migration banner with a receipt), and
/// O-7 (SessionsBrowserPanel + GitCheckoutSheet identifiers).
final class OutstandingClosureTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - O-5

    func testGitPopoverFocusesTheTitleFieldOnOpen() throws {
        let pane = try source("GrokBuild/Views/PreviewPane.swift")
        XCTAssertTrue(pane.contains("@FocusState private var gitTitleFieldFocused"),
                      "the popover owns explicit title-field focus state")
        XCTAssertTrue(pane.contains(".focused($gitTitleFieldFocused)"),
                      "the title field is the focus target")
        XCTAssertTrue(pane.contains("gitTitleFieldFocused = true"),
                      "presentation moves focus into the title field")
    }

    func testGitPopoversAreMutuallyExclusiveSoOnePrimaryClaimsCommandReturn() throws {
        let pane = try source("GrokBuild/Views/PreviewPane.swift")
        XCTAssertTrue(pane.contains("showPRPopover = false\n                showCommitPopover = true"),
                      "opening the commit popover closes the PR popover")
        XCTAssertTrue(pane.contains("showCommitPopover = false\n                showPRPopover = true"),
                      "opening the PR popover closes the commit popover")
        XCTAssertEqual(
            pane.components(separatedBy: ".keyboardShortcut(.return, modifiers: [.command])").count - 1,
            2,
            "one ⌘↩ primary per popover — mutual exclusivity keeps the claim unambiguous"
        )
    }

    func testGitPopoverActionRowsCarryIdentifiersAndHelp() throws {
        let pane = try source("GrokBuild/Views/PreviewPane.swift")
        // identifier/help are required parameters, so a future row cannot ship bare.
        XCTAssertTrue(pane.contains("identifier: String,\n        help: String,"),
                      "popoverActionRow requires instrumentation parameters")
        for id in [
            "grok-review-commit-or-push",
            "grok-review-create-pr",
            "grok-git-title",
            "grok-git-description",
            "grok-git-include-local-changes",
            "grok-git-create-draft-pr",
            "grok-git-create-pr",
            "grok-git-open-pr",
            "grok-git-commit-and-push",
            "grok-git-push-only"
        ] {
            XCTAssertTrue(pane.contains("\"\(id)\""), "PreviewPane lost identifier \(id)")
        }
    }

    // MARK: - O-6

    func testMigrationBannerMessageCountsReadOnlySessions() {
        XCTAssertEqual(
            SessionMigrationBannerPresentation.message(readOnlyCount: 0),
            "Saved session migration failed. Session saving is paused."
        )
        XCTAssertEqual(
            SessionMigrationBannerPresentation.message(readOnlyCount: 1),
            "Saved session migration failed — 1 session is open read-only."
        )
        XCTAssertEqual(
            SessionMigrationBannerPresentation.message(readOnlyCount: 3),
            "Saved session migration failed — 3 sessions are open read-only."
        )
    }

    func testMigrationBannerDetailNamesSessionsAndFailureCode() {
        let detail = SessionMigrationBannerPresentation.detail(
            failure: .v3DecodeFailed,
            sessionTitles: ["Thesis notes", "Untitled session"]
        )
        XCTAssertTrue(detail.contains("could not be decoded"))
        XCTAssertTrue(detail.contains("(code: v3DecodeFailed)"))
        XCTAssertTrue(detail.contains("• Thesis notes"))
        XCTAssertTrue(detail.contains("• Untitled session"))
        XCTAssertTrue(detail.contains("Relaunching retries the migration."))

        let empty = SessionMigrationBannerPresentation.detail(
            failure: .integrityKeyUnavailable,
            sessionTitles: []
        )
        XCTAssertTrue(empty.contains("No saved sessions were loaded read-only."))
    }

    func testMigrationBannerReceiptFallsBackToUntitledSession() {
        let records = [
            SavedSessionRecord(
                id: UUID(),
                workspaceID: UUID(),
                title: "Thesis notes",
                lastAccessed: Date(timeIntervalSince1970: 0)
            ),
            SavedSessionRecord(
                id: UUID(),
                workspaceID: UUID(),
                title: "   ",
                lastAccessed: Date(timeIntervalSince1970: 0)
            ),
            SavedSessionRecord(
                id: UUID(),
                workspaceID: UUID(),
                lastAccessed: Date(timeIntervalSince1970: 0)
            )
        ]
        XCTAssertEqual(
            SessionMigrationBannerPresentation.readOnlySessionTitles(records: records),
            ["Thesis notes", "Untitled session", "Untitled session"]
        )
    }

    func testEveryMigrationFailureCodeHasAReason() {
        let codes: [SessionLayoutFailureCode] = [
            .incompleteV3Commit, .v3DecodeFailed, .v3MarkerMismatch,
            .integrityKeyUnavailable, .v2DecodeFailed, .v3WriteVerificationFailed
        ]
        for code in codes {
            XCTAssertFalse(SessionMigrationBannerPresentation.reason(code).isEmpty,
                           "\(code.rawValue) must explain itself")
        }
    }

    func testMigrationBannerIsDismissiblePerRunWithoutTouchingPersistencePolicy() throws {
        let contentView = try source("GrokBuild/ContentView.swift")
        for id in [
            "grok-migration-banner",
            "grok-migration-banner-details",
            "grok-migration-banner-dismiss",
            "grok-migration-details"
        ] {
            XCTAssertTrue(contentView.contains("\"\(id)\""), "ContentView lost identifier \(id)")
        }
        XCTAssertTrue(contentView.contains("!isMigrationBannerDismissed"),
                      "the banner render respects the per-run dismissal")
        XCTAssertFalse(contentView.contains("isMigrationBannerDismissed = UserDefaults"),
                       "dismissal is per-run state, never persisted — the failure must resurface next launch")
        XCTAssertTrue(contentView.contains("SessionMigrationBannerPresentation.readOnlySessionTitles(records: loaded.snapshot.records)"),
                      "the receipt is captured from the actual fallback snapshot at bootstrap")
        // The write guards are untouched: dismissal hides the banner, not the failure.
        XCTAssertEqual(
            contentView.components(separatedBy: "sessionLayoutFailure == nil").count - 1,
            3,
            "all three persistence guards on the failure state remain"
        )
    }

    // MARK: - O-7

    func testSessionsBrowserPanelCarriesStableIdentifiers() throws {
        let panel = try source("GrokBuild/Views/SessionsBrowserPanel.swift")
        for id in [
            "grok-sessions-browser",
            "grok-sessions-search",
            "grok-sessions-search-run",
            "grok-sessions-recent",
            "grok-sessions-clear-empty",
            "grok-sessions-row",
            "grok-sessions-resume",
            "grok-sessions-delete"
        ] {
            XCTAssertTrue(panel.contains("\"\(id)\""), "SessionsBrowserPanel lost identifier \(id)")
        }
    }

    func testGitCheckoutSheetCarriesStableIdentifiers() throws {
        let sheet = try source("GrokBuild/Views/GitCheckoutSheet.swift")
        for id in [
            "grok-git-checkout-sheet",
            "grok-checkout-filter",
            "grok-checkout-branch-row",
            "grok-checkout-worktree-row",
            "grok-checkout-new-branch-name",
            "grok-checkout-create-branch",
            "grok-checkout-new-worktree-branch",
            "grok-checkout-new-worktree-path",
            "grok-checkout-create-worktree",
            "grok-checkout-close"
        ] {
            XCTAssertTrue(sheet.contains("\"\(id)\""), "GitCheckoutSheet lost identifier \(id)")
        }
    }
}
