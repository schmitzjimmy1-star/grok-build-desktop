import Foundation

/// Codex parity Slice 5 — pure presentation projection for the compact
/// contextual inspector that replaced the right-side Activity dashboard.
///
/// Truth boundaries:
/// - Subagent counts and rows come only from the settled snapshot's workers or,
///   mid-turn, the generation-bound live projection. No invented workers.
/// - The Computer Use section appears only when the capability is configured or
///   a lifecycle receipt exists; its state is the receipt's own label.
/// - MCP evidence separates request/configuration/process/catalog/invocation.
///   Sources names only attachments and MCP servers actually evidenced by a
///   current-turn invocation receipt.
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

    struct MCPToolReceipt: Equatable {
        let id: String
        let role: MCPToolReceiptRole?
        let qualifiedToolName: String?
        let serverName: String?
        let discoveredQualifiedToolNames: [String]
        let statusLabel: String
        let isSettled: Bool
    }

    struct MCPCapabilities: Equatable {
        let requestedServers: [SourceItem]
        let configuredServers: [SourceItem]
        let processStates: [SourceItem]
        let discoveredTools: [SourceItem]
        let exercisedTools: [SourceItem]
        let unavailableTools: [SourceItem]

        var isEmpty: Bool {
            requestedServers.isEmpty && configuredServers.isEmpty && processStates.isEmpty
                && discoveredTools.isEmpty && exercisedTools.isEmpty
                && unavailableTools.isEmpty
        }
    }

    struct Model: Equatable {
        let subagents: Subagents?
        let computerUse: ComputerUse?
        let sources: Sources?
        let mcpCapabilities: MCPCapabilities?
        let hasRunDetails: Bool
        let failedToolCount: Int
        let unresolvedErrors: [String]
        let isSettled: Bool
        let isLive: Bool

        var isEmpty: Bool {
            subagents == nil && computerUse == nil && sources == nil && mcpCapabilities == nil
                && !hasRunDetails && failedToolCount == 0 && unresolvedErrors.isEmpty
        }

        static let empty = Model(
            subagents: nil,
            computerUse: nil,
            sources: nil,
            mcpCapabilities: nil,
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
        computerUseStateLabel: String?,
        configuredMCPNames: [String] = [],
        mcpProcessStatuses: [MCPServerStatus] = [],
        requestedQualifiedToolNames: [String] = [],
        mcpToolReceipts: [MCPToolReceipt] = []
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
        let mcpCapabilities = capabilitiesSection(
            configuredMCPNames: configuredMCPNames,
            processStatuses: mcpProcessStatuses,
            requestedMCPNames: requestedMCPNames,
            requestedQualifiedToolNames: requestedQualifiedToolNames,
            receipts: mcpToolReceipts
        )

        return Model(
            subagents: subagents,
            computerUse: computerUse,
            sources: sources,
            mcpCapabilities: mcpCapabilities,
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
            } else if worker.isUnresolved {
                if normalized == "unknown" || normalized == "orphaned" {
                    noReport += 1
                } else {
                    failed += 1
                }
            } else if worker.isCompleted {
                done += 1
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
        // Requested MCP intent belongs in the MCP evidence section. Activity
        // Sources contains only files plus servers with actual tool receipts.
        let requested: [SourceItem] = []
        var seen = Set<String>()
        let used = evidencedMCPServers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted()
            .map { SourceItem(id: "mcp-used|\($0)", label: $0, detail: "Used — tool receipt observed") }
        let sources = Sources(attachments: attachments, requestedMCPs: requested, usedMCPServers: used)
        return sources.isEmpty ? nil : sources
    }

    static func capabilitiesSection(
        configuredMCPNames: [String],
        processStatuses: [MCPServerStatus],
        requestedMCPNames: [String],
        requestedQualifiedToolNames: [String],
        receipts: [MCPToolReceipt]
    ) -> MCPCapabilities? {
        let requestedTools = uniqueQualified(requestedQualifiedToolNames)
        let discoveredTools = uniqueQualified(receipts.flatMap(\.discoveredQualifiedToolNames))
        let exercisedTools = uniqueQualified(receipts.compactMap { receipt in
            receipt.role == .invocation ? receipt.qualifiedToolName : nil
        })
        let relevantServers = Set(
            requestedMCPNames
                + requestedTools.compactMap(MCPQualifiedToolIdentity.serverName)
                + receipts.compactMap(\.serverName)
                + discoveredTools.compactMap(MCPQualifiedToolIdentity.serverName)
        )

        let configured = uniqueNames(configuredMCPNames)
            .filter { relevantServers.contains($0) }
            .map {
                SourceItem(
                    id: "mcp-configured|\($0)",
                    label: $0,
                    detail: "Configured — process readiness separate"
                )
            }
        let requested = uniqueNames(requestedMCPNames).map {
            SourceItem(
                id: "mcp-requested|\($0)",
                label: $0,
                detail: "Requested for this turn — use unproven"
            )
        }
        let process = processStatuses
            .filter { relevantServers.contains($0.name) }
            .map {
                SourceItem(
                    id: "mcp-process|\($0.name)",
                    label: $0.name,
                    detail: $0.state.displayName
                )
            }
        let discovered = discoveredTools
            .filter { requestedTools.isEmpty || requestedTools.contains($0) }
            .map {
                SourceItem(
                    id: "mcp-discovered|\($0)",
                    label: $0,
                    detail: "Discovered — current-turn catalog receipt"
                )
            }
        let exercised = exercisedTools.map { qualified in
            let status = receipts.last(where: {
                $0.role == .invocation && $0.qualifiedToolName == qualified
            })?.statusLabel ?? "Status not settled"
            return SourceItem(
                id: "mcp-exercised|\(qualified)",
                label: qualified,
                detail: "Exercised — current-turn tool receipt: \(status)"
            )
        }
        let hasSettledDiscovery = receipts.contains { $0.role == .discovery && $0.isSettled }
        let unavailable = hasSettledDiscovery
            ? requestedTools.filter { !discoveredTools.contains($0) && !exercisedTools.contains($0) }
                .map {
                    SourceItem(
                        id: "mcp-unavailable|\($0)",
                        label: $0,
                        detail: "Unavailable for this turn"
                    )
                }
            : []

        let result = MCPCapabilities(
            requestedServers: requested,
            configuredServers: configured,
            processStates: process,
            discoveredTools: discovered,
            exercisedTools: exercised,
            unavailableTools: unavailable
        )
        return result.isEmpty ? nil : result
    }

    private static func uniqueNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted()
    }

    private static func uniqueQualified(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap(MCPQualifiedToolIdentity.normalized)
            .filter { seen.insert($0).inserted }
            .sorted()
    }
}

/// Header dropdown facts for a developer glance. The right rail tracks
/// subagents; this list never invents workers, usage, or failures.
enum RunInspectorQuickLook {
    struct Fact: Equatable {
        let phase: String
        let lines: [String]
    }

    static func make(
        inspector: ContextInspectorProjection.Model,
        modelLabel: String,
        tokenCount: Int?
    ) -> Fact {
        let phase: String
        if inspector.isLive {
            phase = "Live"
        } else if inspector.isSettled {
            phase = "Finished"
        } else {
            phase = "Idle"
        }

        var lines: [String] = []
        let model = modelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            lines.append(model)
        }
        if let tokenCount {
            lines.append("\(compactTokens(tokenCount)) tokens")
        }
        if let workers = inspector.subagents {
            lines.append(workers.compactLabel)
        }
        if inspector.failedToolCount > 0 {
            let count = inspector.failedToolCount
            lines.append("\(count) failed \(count == 1 ? "tool" : "tools")")
        }
        if !inspector.unresolvedErrors.isEmpty {
            let count = inspector.unresolvedErrors.count
            lines.append("\(count) unresolved \(count == 1 ? "error" : "errors")")
        }
        if lines.isEmpty {
            lines.append("No run evidence")
        }
        return Fact(phase: phase, lines: lines)
    }

    static func compactTokens(_ total: Int) -> String {
        if total >= 1_000_000 {
            return "\((Double(total) / 1_000_000).formatted(.number.precision(.fractionLength(1))))M"
        }
        if total >= 1_000 {
            return "\((Double(total) / 1_000).formatted(.number.precision(.fractionLength(1))))K"
        }
        return total.formatted()
    }
}
