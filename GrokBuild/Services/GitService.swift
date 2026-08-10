import Foundation

struct GitBranchInfo: Identifiable, Hashable, Sendable {
    let name: String
    let isCurrent: Bool

    var id: String { name }
}

struct GitWorktreeInfo: Identifiable, Hashable, Sendable {
    let path: URL
    let branch: String?
    let isDetached: Bool

    var id: String { path.path }

    var branchLabel: String {
        if let branch { return branch }
        return isDetached ? "detached" : "unknown"
    }
}

struct GitChangedFile: Identifiable, Hashable, Sendable {
    let path: String
    let status: String
    var originalPath: String? = nil

    var id: String { path }
}

enum GitService {
    enum GitError: LocalizedError {
        case notARepository
        case commandFailed(String)
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .notARepository: return "This folder is not a git repository."
            case .commandFailed(let message): return message
            case .timedOut(let command):
                return "`\(command)` did not finish in time and was terminated."
            }
        }
    }

    @discardableResult
    static func run(_ args: [String], in directory: URL) async throws -> String {
        try await runExecutable("/usr/bin/git", args: args, in: directory)
    }

    @discardableResult
    static func runExecutable(
        _ executable: String,
        args: [String],
        in directory: URL,
        timeout: TimeInterval? = 300
    ) async throws -> String {
        // BoundedProcess drains incrementally (reading only after termination deadlocks
        // once output exceeds the ~64 KiB pipe buffer — large diffs/status) and bounds
        // the wait.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let outcome = try await BoundedProcess.run(process, stdout: stdout, stderr: stderr, timeout: timeout)

        if outcome.timedOut {
            throw GitError.timedOut("\(URL(fileURLWithPath: executable).lastPathComponent) \(args.joined(separator: " "))")
        }
        let out = String(decoding: outcome.stdout, as: UTF8.self)
        let err = String(decoding: outcome.stderr, as: UTF8.self)
        if outcome.status == 0 {
            return out
        }
        throw GitError.commandFailed(err.isEmpty ? out : err)
    }

    @discardableResult
    static func runEnv(_ args: [String], in directory: URL) async throws -> String {
        try await runExecutable("/usr/bin/env", args: args, in: directory)
    }

    static func isRepository(_ directory: URL) -> Bool {
        gitDirectory(for: directory) != nil
    }

    static func currentBranch(in directory: URL) -> String? {
        guard let gitDir = gitDirectory(for: directory) else { return nil }
        let headURL = gitDir.appendingPathComponent("HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !head.isEmpty else {
            return nil
        }
        if head.hasPrefix("ref: ") {
            return URL(fileURLWithPath: String(head.dropFirst(5))).lastPathComponent
        }
        return String(head.prefix(7))
    }

    static func defaultBaseBranch(in directory: URL) async -> String {
        if let output = try? await run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: directory) {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("origin/") {
                return String(trimmed.dropFirst("origin/".count))
            }
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "main"
    }

    static func hasLocalChanges(in directory: URL) async -> Bool {
        guard let output = try? await run(["status", "--porcelain=v1"], in: directory) else {
            return false
        }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func hasUnpushedCommits(in directory: URL, baseBranch: String? = nil) async -> Bool {
        if let upstream = try? await run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !upstream.isEmpty,
           let count = try? await commitCount(range: "\(upstream)..HEAD", in: directory) {
            return count > 0
        }

        guard let baseBranch, !baseBranch.isEmpty else { return false }
        if let count = try? await commitCount(range: "origin/\(baseBranch)..HEAD", in: directory) {
            return count > 0
        }
        if let count = try? await commitCount(range: "\(baseBranch)..HEAD", in: directory) {
            return count > 0
        }
        return false
    }

    static func hasPullRequestSourceChanges(baseBranch: String, in directory: URL) async -> Bool {
        if await hasLocalChanges(in: directory) {
            return true
        }
        return await hasUnpushedCommits(in: directory, baseBranch: baseBranch)
    }

    private static func commitCount(range: String, in directory: URL) async throws -> Int {
        let output = try await run(["rev-list", "--count", range], in: directory)
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func commitAll(message: String, in directory: URL) async throws -> String {
        _ = try await run(["add", "-A"], in: directory)
        return try await run(["commit", "-m", message], in: directory)
    }

    static func pushCurrentBranch(in directory: URL) async throws -> String {
        try await run(["push", "-u", "origin", "HEAD"], in: directory)
    }

    static func createPullRequest(
        base: String,
        head: String,
        title: String,
        body: String,
        draft: Bool,
        in directory: URL
    ) async throws -> String {
        var args = [
            "gh", "pr", "create",
            "--base", base,
            "--head", head,
            "--title", title,
            "--body", body
        ]
        if draft {
            args.append("--draft")
        }
        return try await runEnv(args, in: directory)
    }

    static func openPullRequestInBrowser(in directory: URL) async throws -> String {
        try await runEnv(["gh", "pr", "view", "--web"], in: directory)
    }

    static func listLocalBranches(in directory: URL) async throws -> [GitBranchInfo] {
        guard isRepository(directory) else { throw GitError.notARepository }
        let output = try await run(
            ["for-each-ref", "--sort=-committerdate", "refs/heads/", "--format=%(refname:short)\t%(HEAD)"],
            in: directory
        )
        return output
            .components(separatedBy: .newlines)
            .compactMap { line -> GitBranchInfo? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
                guard let name = parts.first.map(String.init), !name.isEmpty else { return nil }
                let marker = parts.count > 1 ? String(parts[1]) : ""
                return GitBranchInfo(name: name, isCurrent: marker == "*")
            }
    }

    static func listWorktrees(in directory: URL) async throws -> [GitWorktreeInfo] {
        guard isRepository(directory) else { throw GitError.notARepository }
        let output = try await run(["worktree", "list", "--porcelain"], in: directory)
        var worktrees: [GitWorktreeInfo] = []
        var path: URL?
        var branch: String?
        var detached = false

        func flush() {
            guard let path else { return }
            worktrees.append(GitWorktreeInfo(path: path, branch: branch, isDetached: detached))
        }

        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("worktree ") {
                flush()
                path = URL(fileURLWithPath: String(line.dropFirst("worktree ".count)))
                branch = nil
                detached = false
            } else if line.hasPrefix("branch ") {
                branch = String(line.dropFirst("branch ".count))
                    .replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "detached" {
                detached = true
            } else if line.isEmpty {
                flush()
                path = nil
                branch = nil
                detached = false
            }
        }
        flush()
        return worktrees
    }

    static func changedFiles(in directory: URL) async throws -> [GitChangedFile] {
        guard isRepository(directory) else { throw GitError.notARepository }
        let output = try await run(["status", "--porcelain=v1", "-z"], in: directory)
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true)

        var result: [GitChangedFile] = []
        var index = 0
        while index < fields.count {
            let field = fields[index]
            guard field.count > 3 else {
                index += 1
                continue
            }

            let status = String(field.prefix(2))
            let pathField = field.dropFirst(3)
            var originalPath: String?

            // With `status --porcelain=v1 -z`, rename/copy order is the reverse
            // of the human format: `R  new\0old\0`. Keep the selected current
            // path as identity and retain the old path only as provenance.
            if status.hasPrefix("R") || status.hasPrefix("C") {
                index += 1
                if index < fields.count {
                    originalPath = String(fields[index])
                }
            }

            let path = String(pathField).trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                result.append(GitChangedFile(
                    path: path,
                    status: status,
                    originalPath: originalPath
                ))
            }
            index += 1
        }

        return result
    }

    static func diffForChangedFile(_ file: GitChangedFile, in directory: URL) async throws -> String {
        let output = try await run(["diff", "--no-ext-diff", "--no-color", "HEAD", "--", file.path], in: directory)
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return output
        }

        if file.status.contains("?") {
            return """
            Untracked file: \(file.path)

            This file is not tracked by git yet, so there is no unified diff against HEAD.
            """
        }

        return "Changed file: \(file.path)"
    }

    // MARK: Review scopes (OUTSTANDING D-1, 2026-08-08)

    /// The Review pane's scope model. `workingTree` is the pre-existing behavior
    /// (everything vs HEAD, staged and unstaged together — Codex's "Unstaged"
    /// bucket in practice); the other scopes narrow honestly. `lastTurn` reuses
    /// the working-tree commands and is filtered to the turn's attributed paths
    /// by the caller, which owns the run-evidence snapshot.
    enum ReviewScope: String, CaseIterable, Identifiable, Sendable {
        case workingTree
        case unstaged
        case staged
        case lastCommit
        case branch
        case lastTurn

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .workingTree: return "All changes"
            case .unstaged: return "Unstaged"
            case .staged: return "Staged"
            case .lastCommit: return "Last commit"
            case .branch: return "Branch"
            case .lastTurn: return "Last turn"
            }
        }
    }

    static func changedFiles(scope: ReviewScope, in directory: URL) async throws -> [GitChangedFile] {
        guard isRepository(directory) else { throw GitError.notARepository }
        switch scope {
        case .workingTree, .lastTurn:
            return try await changedFiles(in: directory)
        case .unstaged:
            let tracked = parseNameStatus(try await run(
                ["diff", "--name-status", "-z"], in: directory
            ))
            let untrackedOutput = try await run(
                ["ls-files", "--others", "--exclude-standard", "-z"], in: directory
            )
            let untracked = untrackedOutput
                .split(separator: "\0", omittingEmptySubsequences: true)
                .map { GitChangedFile(path: String($0), status: "??") }
            return tracked + untracked
        case .staged:
            let output = try await run(
                ["diff", "--cached", "--name-status", "-z"], in: directory)
            return parseNameStatus(output)
        case .lastCommit:
            // A repository with no commits has no HEAD; that is an empty scope,
            // not an error.
            // --root makes the initial commit list its files instead of nothing.
            guard let output = try? await run(
                ["diff-tree", "--root", "--no-commit-id", "--name-status", "-r", "-z", "HEAD"],
                in: directory) else { return [] }
            return parseNameStatus(output)
        case .branch:
            let base = await defaultBaseBranch(in: directory)
            // No verifiable base (fresh repo, no remote): an empty scope, not an error.
            guard (try? await run(["rev-parse", "--verify", "--quiet", base], in: directory)) != nil else {
                return []
            }
            let output = try await run(
                ["diff", "--name-status", "-z", "\(base)...HEAD"], in: directory)
            return parseNameStatus(output)
        }
    }

    static func diffForChangedFile(
        _ file: GitChangedFile, scope: ReviewScope, in directory: URL
    ) async throws -> String {
        switch scope {
        case .workingTree, .lastTurn:
            return try await diffForChangedFile(file, in: directory)
        case .unstaged:
            if file.status == "??" {
                return """
                Untracked file: \(file.path)

                This file is not tracked by git yet, so there is no unified diff.
                """
            }
            let output = try await run(
                ["diff", "--no-ext-diff", "--no-color", "--", file.path],
                in: directory)
            return output.isEmpty ? "Changed file: \(file.path)" : output
        case .staged:
            let output = try await run(
                ["diff", "--cached", "--no-ext-diff", "--no-color", "--", file.path],
                in: directory)
            return output.isEmpty ? "Changed file: \(file.path)" : output
        case .lastCommit:
            let output = try await run(
                ["show", "--format=", "--no-ext-diff", "--no-color", "HEAD", "--", file.path],
                in: directory)
            return output.isEmpty ? "Changed file: \(file.path)" : output
        case .branch:
            let base = await defaultBaseBranch(in: directory)
            guard (try? await run(["rev-parse", "--verify", "--quiet", base], in: directory)) != nil else {
                return "Changed file: \(file.path)"
            }
            let output = try await run(
                ["diff", "--no-ext-diff", "--no-color", "\(base)...HEAD", "--", file.path],
                in: directory)
            return output.isEmpty ? "Changed file: \(file.path)" : output
        }
    }

    /// Parse `--name-status -z` output: NUL-separated status, path,
    /// and a second path for renames/copies (the new name wins).
    static func parseNameStatus(_ output: String) -> [GitChangedFile] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true)
        var result: [GitChangedFile] = []
        var index = 0
        while index < fields.count {
            let status = String(fields[index])
            index += 1
            guard index < fields.count else { break }
            let firstPath = String(fields[index])
            var path = firstPath
            index += 1
            if status.hasPrefix("R") || status.hasPrefix("C"), index < fields.count {
                path = String(fields[index])
                index += 1
            }
            if !path.isEmpty {
                result.append(GitChangedFile(
                    path: path,
                    status: status,
                    originalPath: path == firstPath ? nil : firstPath
                ))
            }
        }
        return result
    }

    // MARK: Gated per-file revert (OUTSTANDING D-2, 2026-08-08)

    struct RevertReceipt: Equatable, Sendable {
        let path: String
        let preflightStatus: String
        let recoveryRef: String
        let postActionStatus: String
        let unrelatedChangesSurvived: Bool

        var summary: String {
            "Reverted \(path) recoverably · saved at \(recoveryRef) · post-action Git clean for selected path"
        }
    }

    /// Recoverably remove working-tree changes for exactly one selected path.
    /// Git's own stash is the recovery authority; GrokBuild does not copy or
    /// interpret file contents. Exact preflight and post-action status receipts
    /// prove the selected path changed and unrelated dirt survived byte-for-byte.
    static func revertPath(_ path: String, in directory: URL) async throws -> RevertReceipt? {
        guard isRepository(directory) else { throw GitError.notARepository }
        let normalizedPath = try validatedRepositoryRelativePath(path)
        let status = try await run(
            ["status", "--porcelain=v1", "-z", "--", normalizedPath], in: directory)
        guard !status.isEmpty else { return nil }
        let selectedEntries = statusEntries(status)
        guard !selectedEntries.contains(where: {
            $0.status.hasPrefix("R") || $0.status.hasPrefix("C")
        }) else {
            throw GitError.commandFailed(
                "Recoverable per-file revert is unavailable for a rename/copy because Git names two paths; review both paths explicitly."
            )
        }

        let allBefore = try await run(["status", "--porcelain=v1", "-z"], in: directory)
        let beforeUnrelated = statusEntries(allBefore).filter { $0.path != normalizedPath }
        let previousStash = try? await run(["rev-parse", "--verify", "refs/stash"], in: directory)
        _ = try await run(
            ["stash", "push", "--include-untracked", "--message", "GrokBuild recoverable revert: \(normalizedPath)", "--", normalizedPath],
            in: directory
        )
        let recoveryRef = try await run(["rev-parse", "--verify", "refs/stash"], in: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recoveryRef.isEmpty,
              recoveryRef != previousStash?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw GitError.commandFailed("Git did not create a recovery stash for \(normalizedPath).")
        }

        let postStatus = try await run(
            ["status", "--porcelain=v1", "-z", "--", normalizedPath], in: directory)
        let allAfter = try await run(["status", "--porcelain=v1", "-z"], in: directory)
        let afterUnrelated = statusEntries(allAfter).filter { $0.path != normalizedPath }
        guard postStatus.isEmpty else {
            throw GitError.commandFailed("Git preserved the recovery stash but the selected path is still changed: \(normalizedPath).")
        }
        guard beforeUnrelated == afterUnrelated else {
            throw GitError.commandFailed("Git preserved the recovery stash, but unrelated repository state changed; inspect \(recoveryRef).")
        }
        return RevertReceipt(
            path: normalizedPath,
            preflightStatus: status,
            recoveryRef: recoveryRef,
            postActionStatus: postStatus,
            unrelatedChangesSurvived: true
        )
    }

    private struct StatusEntry: Equatable {
        let status: String
        let path: String
    }

    private static func statusEntries(_ output: String) -> [StatusEntry] {
        let fields = output.split(separator: "\0", omittingEmptySubsequences: true)
        var result: [StatusEntry] = []
        var index = 0
        while index < fields.count {
            let field = String(fields[index])
            index += 1
            guard field.count >= 4 else { continue }
            let status = String(field.prefix(2))
            var path = String(field.dropFirst(3))
            if (status.hasPrefix("R") || status.hasPrefix("C")), index < fields.count {
                path = String(fields[index])
                index += 1
            }
            result.append(StatusEntry(status: status, path: path))
        }
        return result
    }

    private static func validatedRepositoryRelativePath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = NSString(string: trimmed).pathComponents
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.contains("\0"),
              !components.contains("..") else {
            throw GitError.commandFailed("Refusing revert outside the selected repository path boundary.")
        }
        return NSString(string: trimmed).standardizingPath
    }

    static func gitDirectory(for projectURL: URL) -> URL? {
        let dotGit = projectURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            return dotGit
        }

        guard let content = try? String(contentsOf: dotGit, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              content.hasPrefix("gitdir:") else {
            return nil
        }

        let rawPath = content.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath)
        }
        return projectURL.appendingPathComponent(rawPath).standardizedFileURL
    }
}
