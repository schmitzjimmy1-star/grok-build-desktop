import XCTest
@testable import GrokBuild

/// OUTSTANDING D-1/D-2 (2026-08-08): review scopes and the gated per-file revert.
final class GitReviewScopeTests: XCTestCase {
    private func makeRepo() async throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-review-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try await GitService.run(["init"], in: root)
        try "baseline\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try await GitService.run(["add", "-A"], in: root)
        _ = try await GitService.run(
            ["-c", "user.name=GrokBuild Tests", "-c", "user.email=tests@grokbuild.invalid",
             "commit", "-m", "baseline"], in: root)
        return root
    }

    func testScopesSeparateWorkingTreeStagedAndLastCommit() async throws {
        let root = try await makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        // Modify tracked (unstaged), stage a new file, leave one untracked.
        try "changed\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "staged\n".write(to: root.appendingPathComponent("staged.txt"), atomically: true, encoding: .utf8)
        _ = try await GitService.run(["add", "staged.txt"], in: root)
        try "loose\n".write(to: root.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)

        let workingTree = try await GitService.changedFiles(scope: .workingTree, in: root)
        XCTAssertEqual(Set(workingTree.map(\.path)), ["tracked.txt", "staged.txt", "untracked.txt"])

        let unstaged = try await GitService.changedFiles(scope: .unstaged, in: root)
        XCTAssertEqual(Set(unstaged.map(\.path)), ["tracked.txt", "untracked.txt"])

        let staged = try await GitService.changedFiles(scope: .staged, in: root)
        XCTAssertEqual(staged.map(\.path), ["staged.txt"])
        let stagedDiff = try await GitService.diffForChangedFile(
            try XCTUnwrap(staged.first), scope: .staged, in: root)
        XCTAssertTrue(stagedDiff.contains("+staged"))

        let lastCommit = try await GitService.changedFiles(scope: .lastCommit, in: root)
        XCTAssertEqual(lastCommit.map(\.path), ["tracked.txt"])
        let commitDiff = try await GitService.diffForChangedFile(
            try XCTUnwrap(lastCommit.first), scope: .lastCommit, in: root)
        XCTAssertTrue(commitDiff.contains("+baseline"))

        // No verifiable base branch in a remote-less repo whose default base
        // does not resolve: the branch scope is empty, never an error.
        _ = try await GitService.run(["branch", "-M", "work"], in: root)
        let branch = try await GitService.changedFiles(scope: .branch, in: root)
        XCTAssertTrue(branch.isEmpty)
    }

    func testRevertPathRestoresTrackedAndRemovesUntracked() async throws {
        let root = try await makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let tracked = root.appendingPathComponent("tracked.txt")
        try "mangled\n".write(to: tracked, atomically: true, encoding: .utf8)
        let trackedResult = try await GitService.revertPath("tracked.txt", in: root)
        let trackedReceipt = try XCTUnwrap(trackedResult)
        XCTAssertEqual(try String(contentsOf: tracked, encoding: .utf8), "baseline\n")
        XCTAssertTrue(trackedReceipt.unrelatedChangesSurvived)
        XCTAssertFalse(trackedReceipt.recoveryRef.isEmpty)

        let loose = root.appendingPathComponent("untracked.txt")
        try "loose\n".write(to: loose, atomically: true, encoding: .utf8)
        let untrackedResult = try await GitService.revertPath("untracked.txt", in: root)
        let untrackedReceipt = try XCTUnwrap(untrackedResult)
        XCTAssertFalse(FileManager.default.fileExists(atPath: loose.path))
        XCTAssertNotEqual(untrackedReceipt.recoveryRef, trackedReceipt.recoveryRef)

        // A clean path is a no-op, not an error.
        let cleanResult = try await GitService.revertPath("tracked.txt", in: root)
        XCTAssertNil(cleanResult)
        XCTAssertEqual(try String(contentsOf: tracked, encoding: .utf8), "baseline\n")
    }

    func testFixtureCoverageForCleanMixedRenamedDeletedAndUnrelatedDirtyStates() async throws {
        let root = try await makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let cleanFiles = try await GitService.changedFiles(scope: .workingTree, in: root)
        XCTAssertTrue(cleanFiles.isEmpty)
        try "rename me\n".write(to: root.appendingPathComponent("rename-old.txt"), atomically: true, encoding: .utf8)
        try "delete me\n".write(to: root.appendingPathComponent("delete-me.txt"), atomically: true, encoding: .utf8)
        _ = try await GitService.run(["add", "-A"], in: root)
        _ = try await GitService.run(
            ["-c", "user.name=GrokBuild Tests", "-c", "user.email=tests@grokbuild.invalid",
             "commit", "-m", "fixture files"], in: root)

        _ = try await GitService.run(["mv", "rename-old.txt", "rename-new.txt"], in: root)
        _ = try await GitService.run(["rm", "delete-me.txt"], in: root)
        try "unstaged\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "untracked\n".write(to: root.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        let mixed = try await GitService.changedFiles(scope: .workingTree, in: root)
        XCTAssertEqual(Set(mixed.map(\.path)), ["rename-new.txt", "delete-me.txt", "tracked.txt", "untracked.txt"])
        XCTAssertEqual(mixed.first(where: { $0.path == "rename-new.txt" })?.originalPath, "rename-old.txt")
        XCTAssertTrue(mixed.contains(where: { $0.path == "delete-me.txt" && $0.status.contains("D") }))
        XCTAssertTrue(mixed.contains(where: { $0.path == "untracked.txt" && $0.status == "??" }))
    }

    func testRecoverableRevertPreservesUnrelatedDirtyStateAndRejectsTraversal() async throws {
        let root = try await makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("tracked.txt")
        let unrelated = root.appendingPathComponent("unrelated.txt")
        try "selected edit\n".write(to: selected, atomically: true, encoding: .utf8)
        try "unrelated edit\n".write(to: unrelated, atomically: true, encoding: .utf8)

        let revertResult = try await GitService.revertPath("tracked.txt", in: root)
        let receipt = try XCTUnwrap(revertResult)
        XCTAssertEqual(try String(contentsOf: selected, encoding: .utf8), "baseline\n")
        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "unrelated edit\n")
        XCTAssertTrue(receipt.unrelatedChangesSurvived)
        let stashPaths = try await GitService.run(["stash", "show", "--name-only", receipt.recoveryRef], in: root)
        XCTAssertTrue(stashPaths.contains("tracked.txt"))

        do {
            _ = try await GitService.revertPath("../outside.txt", in: root)
            XCTFail("path traversal must fail closed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("path boundary"))
        }
    }

    func testPaneWiresScopePickerAndGatedRevert() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pane = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/PreviewPane.swift"),
            encoding: .utf8)
        XCTAssertTrue(pane.contains("grok-review-scope"), "the scope picker is addressable")
        XCTAssertTrue(pane.contains(".confirmationDialog("),
                      "revert is destructive and must confirm first")
        XCTAssertTrue(pane.contains("Save recovery stash and revert this file"),
                      "revert is recoverable and explicit")
        XCTAssertTrue(pane.contains("grok-review-readiness"),
                      "publication readiness is presented as review state")
        XCTAssertTrue(pane.contains("if scope == .workingTree,")
                      && pane.contains("let path = diff.filePath,"),
                      "revert renders only in the all-changes scope for an exact path")
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8)
        XCTAssertTrue(content.contains("if diffs.isEmpty, reviewScope == .workingTree {"),
                      "only the default scope may auto-close the pane")
        XCTAssertTrue(content.contains("workingTreeFiles.map(\\.path), workspaceID: workspace.id"),
                      "the header chip and card attribution always read the full working tree")
        XCTAssertTrue(content.contains("showing fresh repository truth without guessing"),
                      "last-turn attribution failure falls back honestly")
    }
}
