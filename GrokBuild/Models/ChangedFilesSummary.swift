import Foundation

/// Codex parity Slice 3 — pure presentation projection for the inline
/// changed-files summary card shown after a settled assistant turn.
///
/// Truth boundaries:
/// - The gate is the settled `RunEvidenceSnapshot` and its generation-bound
///   `gitReviewFiles` recording. No snapshot, or an empty recording, means no card.
/// - Turn attribution comes only from the snapshot's successful write/edit tool
///   artifacts inside the workspace, intersected with the Git file list. A dirty
///   repository file with no matching artifact is never called agent-edited.
/// - Per-file +/− counts are parsed from the already-fetched unified diffs; files
///   without a parseable diff (for example untracked placeholders) report nil and
///   totals disclose partial coverage.
enum ChangedFilesSummaryProjection {
    struct FileRow: Identifiable, Equatable {
        let path: String
        let additions: Int?
        let deletions: Int?
        let isTurnAttributed: Bool

        var id: String { path }
    }

    struct Summary: Equatable {
        let headline: String
        let scopeNote: String?
        let rows: [FileRow]
        let turnAttributedCount: Int
        let additionsTotal: Int?
        let deletionsTotal: Int?
        /// False when at least one listed file has no parseable diff counts, so
        /// the totals must not read as complete.
        let hasCompleteCounts: Bool
    }

    /// The compact number of file rows shown before "Show N more files".
    static let visibleRowLimit = 3

    static func summary(
        snapshot: RunEvidenceSnapshot?,
        diffs: [ChatStore.DetectedDiff],
        workspace: URL?
    ) -> Summary? {
        guard let snapshot else { return nil }
        let gitFiles = snapshot.gitReviewFiles
        guard !gitFiles.isEmpty else { return nil }

        let attributedPaths = attributedWorkspacePaths(snapshot: snapshot, workspace: workspace)
        let countsByPath = diffCountsByPath(diffs)

        func row(_ path: String) -> FileRow {
            let counts = countsByPath[path]
            return FileRow(
                path: path,
                additions: counts?.additions,
                deletions: counts?.deletions,
                isTurnAttributed: attributedPaths.contains(path)
            )
        }

        let attributedRows = gitFiles.filter(attributedPaths.contains).sorted().map(row)
        let otherRows = gitFiles.filter { !attributedPaths.contains($0) }.sorted().map(row)
        let rows = attributedRows + otherRows

        let counted = rows.compactMap { r -> (Int, Int)? in
            guard let a = r.additions, let d = r.deletions else { return nil }
            return (a, d)
        }
        let additionsTotal = counted.isEmpty ? nil : counted.reduce(0) { $0 + $1.0 }
        let deletionsTotal = counted.isEmpty ? nil : counted.reduce(0) { $0 + $1.1 }

        let headline: String
        let scopeNote: String?
        if attributedRows.isEmpty {
            headline = "\(rows.count) changed \(rows.count == 1 ? "file" : "files") in project"
            scopeNote = "Repository-wide changes — not attributed to this turn."
        } else {
            headline = "Edited \(attributedRows.count) \(attributedRows.count == 1 ? "file" : "files")"
            scopeNote = otherRows.isEmpty
                ? nil
                : "\(otherRows.count) more changed \(otherRows.count == 1 ? "file" : "files") in the project \(otherRows.count == 1 ? "is" : "are") not attributed to this turn."
        }

        return Summary(
            headline: headline,
            scopeNote: scopeNote,
            rows: rows,
            turnAttributedCount: attributedRows.count,
            additionsTotal: additionsTotal,
            deletionsTotal: deletionsTotal,
            hasCompleteCounts: counted.count == rows.count
        )
    }

    /// Workspace-relative paths of this turn's successful write/edit artifacts.
    /// `RunArtifact` rows are admitted only after a successful terminal tool
    /// status, so presence alone is the success receipt.
    static func attributedWorkspacePaths(
        snapshot: RunEvidenceSnapshot,
        workspace: URL?
    ) -> Set<String> {
        var result: Set<String> = []
        let workspacePrefix = workspace.map { $0.standardizedFileURL.path + "/" }
        for artifact in snapshot.artifacts where artifact.location == .workspace {
            var path = artifact.path
            if let workspacePrefix, path.hasPrefix(workspacePrefix) {
                path = String(path.dropFirst(workspacePrefix.count))
            }
            result.insert(path)
        }
        return result
    }

    /// Parses "+/−" line counts from one unified diff body. Returns nil for
    /// bodies that are not unified diffs (for example the untracked-file
    /// placeholder), so absent counts stay absent instead of reading as zero.
    static func diffCounts(fromUnifiedDiff raw: String) -> (additions: Int, deletions: Int)? {
        var additions = 0
        var deletions = 0
        var sawHunk = false
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") { sawHunk = true; continue }
            guard sawHunk else { continue }
            if line.hasPrefix("+++") || line.hasPrefix("---") { continue }
            if line.hasPrefix("+") { additions += 1 } else if line.hasPrefix("-") { deletions += 1 }
        }
        return sawHunk ? (additions, deletions) : nil
    }

    private static func diffCountsByPath(
        _ diffs: [ChatStore.DetectedDiff]
    ) -> [String: (additions: Int, deletions: Int)] {
        var result: [String: (additions: Int, deletions: Int)] = [:]
        for diff in diffs {
            guard let path = diff.filePath, result[path] == nil else { continue }
            if let counts = diffCounts(fromUnifiedDiff: diff.raw) {
                result[path] = counts
            }
        }
        return result
    }
}
