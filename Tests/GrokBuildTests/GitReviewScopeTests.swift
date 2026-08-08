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
        try await GitService.revertPath("tracked.txt", in: root)
        XCTAssertEqual(try String(contentsOf: tracked, encoding: .utf8), "baseline\n")

        let loose = root.appendingPathComponent("untracked.txt")
        try "loose\n".write(to: loose, atomically: true, encoding: .utf8)
        try await GitService.revertPath("untracked.txt", in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: loose.path))

        // A clean path is a no-op, not an error.
        try await GitService.revertPath("tracked.txt", in: root)
        XCTAssertEqual(try String(contentsOf: tracked, encoding: .utf8), "baseline\n")
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
        XCTAssertTrue(pane.contains("scope == .workingTree, let path = diff.filePath"),
                      "revert renders only where there is something to discard")
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8)
        XCTAssertTrue(content.contains("if diffs.isEmpty, reviewScope == .workingTree {"),
                      "only the default scope may auto-close the pane")
        XCTAssertTrue(content.contains("workingTreeFiles.map(\\.path), workspaceID: workspace.id"),
                      "the header chip and card attribution always read the full working tree")
    }
}
