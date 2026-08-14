import Foundation

/// A bounded, local-only history projected from saved assistant checkpoints.
/// It never reads Grok's private session storage and deliberately excludes user
/// prompts, assistant response bodies, raw tool input/output, environment data,
/// and credentials.
enum RunHistory {
    static let maximumRuns = 24
    static let maximumTurnsPerRun = 24
    static let maximumTextLength = 180

    struct Turn: Identifiable, Hashable, Sendable {
        let id: UUID
        let timestamp: Date
        let checkpoint: AssistantTurnCheckpoint
        /// Settled transcript tool labels are already redacted at their source;
        /// only operation/kind/status are eligible for the export projection.
        let toolSequence: [AssistantTurnTrace.Tool]

        var outcome: String { checkpoint.outcome }
        var model: String { checkpoint.modelID.map(RunHistory.safeText) ?? "not retained" }
        var toolCount: Int? { checkpoint.toolSummaryReceipt.map { $0.succeeded + $0.failed + $0.cancelled + $0.unknown } }
        var workerCount: Int {
            checkpoint.workerReceipts?.count ?? checkpoint.workers.count
        }
        var route: String { checkpoint.routeReceipt.map(RunHistory.safeText) ?? "not retained" }
        var topology: String {
            let workers = checkpoint.workerReceipts ?? []
            guard !workers.isEmpty else { return "no parent/child receipts retained" }
            let children = workers.compactMap(\.childBackendSessionID).count
            return "1 parent; \(workers.count) worker receipt(s); \(children) child identity receipt(s)"
        }
        var isHistorical: Bool { true }
    }

    struct Record: Identifiable, Hashable, Sendable {
        let id: String
        let turns: [Turn]

        var latest: Turn? { turns.last }
        var backendSessionID: String? { latest?.checkpoint.parentBackendSessionID }
        var lastAuthoritativeContinuationPoint: String {
            guard let latest else { return "No retained checkpoint." }
            let request = latest.checkpoint.requestID.map { "request \(RunHistory.safeText($0))" } ?? "request not retained"
            return "\(request); next action: \(RunHistory.safeText(latest.checkpoint.nextAction))"
        }

        var hasStopResumeBoundary: Bool {
            turns.contains { $0.checkpoint.outcomeCode == ChatStore.TurnOutcome.userStopped.rawValue }
                && turns.count > 1
        }
    }

    static func records(from messages: [Message]) -> [Record] {
        let turns = messages.compactMap { message -> Turn? in
            guard message.role == .assistant, let checkpoint = message.assistantTrace?.checkpoint else { return nil }
            return Turn(
                id: message.id,
                timestamp: message.timestamp,
                checkpoint: checkpoint,
                toolSequence: message.assistantTrace?.tools ?? []
            )
        }
        var records: [Record] = []
        for turn in turns {
            let key = turn.checkpoint.parentBackendSessionID.map { "backend:\($0)" }
                ?? "historical:\(turn.id.uuidString.lowercased())"
            if let index = records.firstIndex(where: { $0.id == key }) {
                var updated = records[index].turns
                updated.append(turn)
                records[index] = Record(id: key, turns: Array(updated.suffix(maximumTurnsPerRun)))
            } else {
                records.append(Record(id: key, turns: [turn]))
            }
        }
        return Array(records.suffix(maximumRuns).reversed())
    }

    /// A stable, redacted receipt intended for sharing. Its schema purposefully
    /// has no prose fields from the transcript and no raw paths or tool payloads.
    static func jsonData(for record: Record) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(ExportReceipt(record: record))
    }

    static func markdown(for record: Record) -> String {
        var lines = [
            "# GrokBuild redacted Run receipt",
            "",
            "- Historical: yes (saved checkpoint; not current Live state)",
            "- Run: \(safeText(record.id))",
            "- Turns: \(record.turns.count)",
            "- Stop/resume boundary: \(record.hasStopResumeBoundary ? "observed" : "not retained")",
            "- Last authoritative continuation point: \(record.lastAuthoritativeContinuationPoint)",
            ""
        ]
        for (index, turn) in record.turns.enumerated() {
            let checkpoint = turn.checkpoint
            let tool = checkpoint.toolSummaryReceipt
            lines += [
                "## Turn \(index + 1) — \(turn.timestamp.formatted(.iso8601))",
                "",
                "- Outcome: \(safeText(checkpoint.outcome))",
                "- Model: \(turn.model)",
                "- Route: \(turn.route)",
                "- Tools: \(tool.map { "\($0.succeeded) succeeded, \($0.failed) failed, \($0.cancelled) cancelled, \($0.unknown) unknown" } ?? "not retained")",
                "- Workers: \(turn.workerCount)",
                "- Usage: \(usageLine(checkpoint.usageReceipt))",
                "- Artifacts: \(artifactLine(checkpoint.artifacts))",
                "- Unresolved evidence: \(unresolvedLine(checkpoint))",
                "- Parent/child topology: \(turn.topology)",
                "- Tool sequence: \(toolSequenceLine(turn.toolSequence))",
                "- Parallel groups: not retained as a typed checkpoint field",
                "- Retries: not retained as a typed checkpoint field",
                "- Continuity: \(continuityLine(checkpoint.continuityReceipt))",
                ""
            ]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private struct ExportReceipt: Codable {
        struct ExportTurn: Codable {
            struct ToolCounts: Codable {
                let succeeded: Int
                let failed: Int
                let cancelled: Int
                let unknown: Int
            }
            struct Usage: Codable {
                let totalTokens: Int?
                let modelCalls: Int?
                let turnCount: Int?
                let apiDurationMilliseconds: Int?
                let costUsdTicks: Int?
            }
            struct Worker: Codable {
                let status: String
                let childBackendSessionID: String?
                let toolCallCount: Int?
                let ledgerState: String
            }
            struct Artifact: Codable {
                let status: String
                let location: String
            }
            struct Tool: Codable {
                let operation: String
                let kind: String?
                let status: String
            }

            let historical: Bool
            let timestamp: Date
            let outcome: String
            let model: String?
            let route: String
            let toolCounts: ToolCounts?
            let workers: [Worker]
            let usage: Usage?
            let artifacts: [Artifact]
            let toolSequence: [Tool]
            let unresolvedEvidenceCount: Int
            let parentChildTopology: String
            let continuityStatus: String?
            let continuationPoint: String
            let toolSequenceAndParallelGroups: String
            let retries: String
        }

        let schemaVersion: Int
        let historical: Bool
        let runID: String
        let stopResumeBoundary: String
        let turns: [ExportTurn]

        init(record: Record) {
            schemaVersion = 1
            historical = true
            runID = RunHistory.safeText(record.id)
            stopResumeBoundary = record.hasStopResumeBoundary ? "observed" : "not retained"
            turns = record.turns.map { turn in
                let checkpoint = turn.checkpoint
                let tools = checkpoint.toolSummaryReceipt.map {
                    ExportTurn.ToolCounts(succeeded: $0.succeeded, failed: $0.failed, cancelled: $0.cancelled, unknown: $0.unknown)
                }
                let usage = checkpoint.usageReceipt.map {
                    ExportTurn.Usage(totalTokens: $0.totalTokens, modelCalls: $0.modelCalls, turnCount: $0.turnCount, apiDurationMilliseconds: $0.apiDurationMilliseconds, costUsdTicks: $0.costUsdTicks)
                }
                let workers = (checkpoint.workerReceipts ?? []).map {
                    ExportTurn.Worker(
                        status: RunHistory.safeText($0.status),
                        childBackendSessionID: $0.childBackendSessionID.map(RunHistory.safeText),
                        toolCallCount: $0.toolCallCount,
                        ledgerState: $0.childToolReceipts == nil ? "not retained" : "retained"
                    )
                }
                let artifacts = (checkpoint.artifacts ?? []).map {
                    ExportTurn.Artifact(status: RunHistory.safeText($0.status), location: RunHistory.safeText($0.location))
                }
                let toolSequence = turn.toolSequence.map {
                    ExportTurn.Tool(
                        operation: RunHistory.safeText($0.title),
                        kind: $0.kind.map(RunHistory.safeText),
                        status: RunHistory.safeText($0.status)
                    )
                }
                return ExportTurn(
                    historical: true,
                    timestamp: turn.timestamp,
                    outcome: RunHistory.safeText(checkpoint.outcome),
                    model: checkpoint.modelID.map(RunHistory.safeText),
                    route: turn.route,
                    toolCounts: tools,
                    workers: workers,
                    usage: usage,
                    artifacts: artifacts,
                    toolSequence: toolSequence,
                    unresolvedEvidenceCount: (checkpoint.unresolvedErrors ?? []).count,
                    parentChildTopology: turn.topology,
                    continuityStatus: checkpoint.continuityReceipt.map { RunHistory.safeText($0.status) },
                    continuationPoint: RunHistory.safeText(record.lastAuthoritativeContinuationPoint),
                    toolSequenceAndParallelGroups: "not retained as typed checkpoint fields",
                    retries: "not retained as a typed checkpoint field"
                )
            }
        }
    }

    private static func usageLine(_ usage: AssistantTurnCheckpoint.UsageReceipt?) -> String {
        guard let usage else { return "not retained" }
        var parts: [String] = []
        if let tokens = usage.totalTokens { parts.append("\(tokens) tokens") }
        if let calls = usage.modelCalls { parts.append("\(calls) model calls") }
        if let duration = usage.apiDurationMilliseconds { parts.append("\(duration) ms provider API") }
        return parts.isEmpty ? "not retained" : parts.joined(separator: "; ")
    }

    private static func artifactLine(_ artifacts: [AssistantTurnCheckpoint.Artifact]?) -> String {
        guard let artifacts else { return "not retained" }
        guard !artifacts.isEmpty else { return "none reported" }
        return artifacts.map { "\(safeText($0.location)) \(safeText($0.status))" }.sorted().joined(separator: "; ")
    }

    private static func unresolvedLine(_ checkpoint: AssistantTurnCheckpoint) -> String {
        let errors = checkpoint.unresolvedErrors?.count ?? 0
        let workers = (checkpoint.workerReceipts ?? []).filter { $0.status.lowercased() != "completed" }.count
        return errors + workers == 0 ? "none reported" : "\(errors + workers) receipt(s) require review"
    }

    private static func toolSequenceLine(_ tools: [AssistantTurnTrace.Tool]) -> String {
        guard !tools.isEmpty else { return "none retained" }
        return tools.prefix(12).map {
            "\(safeText($0.title)) (\(safeText($0.status)))"
        }.joined(separator: " → ")
    }

    private static func continuityLine(_ continuity: AssistantTurnCheckpoint.ContinuityReceipt?) -> String {
        guard let continuity else { return "not retained" }
        return "\(safeText(continuity.status)); \(safeText(continuity.reason))"
    }

    static func safeText(_ value: String) -> String {
        let collapsed = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = ["sk-", "bearer ", "keychain", "api_key", "authorization:", "grokbuild_computer_use_"]
        guard !forbidden.contains(where: { collapsed.localizedCaseInsensitiveContains($0) }) else {
            return "<redacted>"
        }
        return String(collapsed.prefix(maximumTextLength))
    }
}
