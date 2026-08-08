import Foundation

/// Codex parity Slice 5 — pure presentation projection for the compact
/// contextual inspector that replaced the right-side Activity dashboard.
///
/// Truth boundaries:
/// - Subagent counts and rows come only from the settled snapshot's workers or,
///   mid-turn, the generation-bound live projection. No invented workers.
/// - The Computer Use section appears only when the capability is configured or
///   a lifecycle receipt exists; its state is the receipt's own label.
/// - Sources separate three claims that must never merge: prompt attachments,
///   MCPs *requested* for the next prompt, and MCP servers *actually evidenced*
///   by tool receipts. A requested MCP is never presented as used.
/// - `unresolvedErrorCount`/`failedToolCount` preserve failure visibility; the
///   compact panel may summarize but never hide a failed tool.
enum ContextInspectorProjection {
    struct SubagentRow: Identifiable, Equatable {
        let id: String
        let name: String
        let statusLabel: String
        let isActive: Bool
    }

    struct Subagents: Equatable {
        let runningCount: Int
        let doneCount: Int
        let failedCount: Int
        let noReportCount: Int
        let rows: [SubagentRow]

        /// "2 running · 3 done · 1 failed" with zero segments omitted.
        var compactLabel: String {
            var parts: [String] = []
            if runningCount > 0 { parts.append("\(runningCount) running") }
            if doneCount > 0 { parts.append("\(doneCount) done") }
            if failedCount > 0 { parts.append("\(failedCount) failed") }
            if noReportCount > 0 { parts.append("\(noReportCount) no final report") }
            return parts.isEmpty ? "No workers" : parts.joined(separator: " · ")
        }
    }

    struct ComputerUse: Equatable {
        let stateLabel: String
        let detail: String?
    }

    struct SourceItem: Identifiable, Equatable {
        let id: String
        let label: String
        let detail: String?
    }

    struct Sources: Equatable {
        let attachments: [SourceItem]
        let requestedMCPs: [SourceItem]
        let usedMCPServers: [SourceItem]

        var isEmpty: Bool {
            attachments.isEmpty && requestedMCPs.isEmpty && usedMCPServers.isEmpty
        }
    }

    struct Model: Equatable {
        let subagents: Subagents?
        let computerUse: ComputerUse?
        let sources: Sources?
        let hasRunDetails: Bool
        let failedToolCount: Int
        let unresolvedErrors: [String]
        let isSettled: Bool
        let isLive: Bool

        var isEmpty: Bool {
            subagents == nil && computerUse == nil && sources == nil
                && !hasRunDetails && failedToolCount == 0 && unresolvedErrors.isEmpty
        }

        static let empty = Model(
            subagents: nil,
            computerUse: nil,
            sources: nil,
            hasRunDetails: false,
            failedToolCount: 0,
            unresolvedErrors: [],
            isSettled: false,
            isLive: false
        )
    }

    /// Bounded row list before the view's "N more" note.
    static let visibleSubagentRowLimit = 6

    static func model(
        live: RunEvidenceLiveProjection?,
        snapshot: RunEvidenceSnapshot?,
        attachmentNames: [String],
        requestedMCPNames: [String],
        evidencedMCPServers: [String],
        computerUseConfigured: Bool,
        computerUseStateLabel: String?
    ) -> Model {
        let workers = snapshot?.workers ?? live?.workers ?? []
        let subagents: Subagents? = workers.isEmpty ? nil : subagentSummary(workers)

        let computerUse: ComputerUse?
        if let computerUseStateLabel, !computerUseStateLabel.isEmpty {
            computerUse = ComputerUse(stateLabel: computerUseStateLabel, detail: nil)
        } else if computerUseConfigured {
            computerUse = ComputerUse(
                stateLabel: "Configured",
                detail: "Starts with the session's next launch."
            )
        } else {
            computerUse = nil
        }

        let sources = sourcesSection(
            attachmentNames: attachmentNames,
            requestedMCPNames: requestedMCPNames,
            evidencedMCPServers: evidencedMCPServers
        )

        return Model(
            subagents: subagents,
            computerUse: computerUse,
            sources: sources,
            hasRunDetails: snapshot != nil || live != nil,
            failedToolCount: snapshot?.tools.failed ?? 0,
            unresolvedErrors: snapshot?.unresolvedErrors ?? [],
            isSettled: snapshot != nil,
            isLive: snapshot == nil && live != nil
        )
    }

    static func subagentSummary(_ workers: [RunEvidenceSnapshot.Worker]) -> Subagents {
        var running = 0, done = 0, failed = 0, noReport = 0
        var rows: [SubagentRow] = []
        for worker in workers {
            let normalized = worker.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if worker.isActive {
                running += 1
            } else if worker.isCompleted {
                done += 1
            } else if normalized == "unknown" || normalized == "orphaned" {
                noReport += 1
            } else {
                failed += 1
            }
            rows.append(SubagentRow(
                id: worker.id,
                name: worker.title,
                statusLabel: ActivitySidebarPresentation.activityStatus(worker.status),
                isActive: worker.isActive
            ))
        }
        return Subagents(
            runningCount: running,
            doneCount: done,
            failedCount: failed,
            noReportCount: noReport,
            rows: rows
        )
    }

    static func sourcesSection(
        attachmentNames: [String],
        requestedMCPNames: [String],
        evidencedMCPServers: [String]
    ) -> Sources? {
        let attachments = attachmentNames
            .map { SourceItem(id: "file|\($0)", label: $0, detail: "Attached file") }
        // Requested is a per-prompt intent — never a usage claim.
        let requested = requestedMCPNames
            .map { SourceItem(id: "mcp-requested|\($0)", label: $0, detail: "Requested — not yet evidenced") }
        var seen = Set<String>()
        let used = evidencedMCPServers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted()
            .map { SourceItem(id: "mcp-used|\($0)", label: $0, detail: "Used — tool receipt observed") }
        let sources = Sources(attachments: attachments, requestedMCPs: requested, usedMCPServers: used)
        return sources.isEmpty ? nil : sources
    }
}
