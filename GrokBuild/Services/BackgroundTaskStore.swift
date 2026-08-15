import Foundation

/// A background activity mirrored from grok ACP tool calls (scheduled tasks, background shells, monitors, subagents).
struct BackgroundActivity: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case scheduled
        case backgroundCommand
        case monitor
        case subagent
    }

    let id: String
    let kind: Kind
    var title: String
    var detail: String
    var status: String
    /// The ACP tool call that created or controls this activity, when available.
    /// Worker rows keep this separate from `id` so the row can remain stable when
    /// the backend later supplies its child identity.
    var toolCallID: String?
    /// Backend child/session identity supplied by `subagent_spawned` or the spawn
    /// tool receipt. A worker without this is not allowed to look completed.
    var childID: String?
    /// Model reported by Grok's typed `subagent_spawned` lifecycle event. This is
    /// runtime truth and must not be replaced by configured role routing.
    var runtimeModelID: String?
    /// Authoritative terminal worker receipt fields. These stay nil until the
    /// typed `subagent_finished` event arrives.
    var durationMilliseconds: Int?
    var turns: Int?
    var toolCallCount: Int?
    var tokenCount: Int?
    var redactedError: String?
    /// Typed terminal receipts read from this exact child's backend ledger.
    /// They remain child evidence and are never merged into the parent tool list.
    var childToolReceipts: [ChildToolReceipt]?
    /// Whether the child ledger was unreadable, empty, or contained receipts.
    var childLedgerReadOutcome: ChildLedgerReadOutcome?
    /// Wait/collection calls attach a receipt to an existing activity rather than
    /// creating a second worker row.
    var collectionStatus: String?
    var collectionReceiptCount: Int
    /// Populated for `.scheduled` kinds.
    var scheduledTask: ScheduledTask?

    init(
        id: String,
        kind: Kind,
        title: String,
        detail: String = "",
        status: String = "",
        scheduledTask: ScheduledTask? = nil,
        toolCallID: String? = nil,
        childID: String? = nil,
        runtimeModelID: String? = nil,
        durationMilliseconds: Int? = nil,
        turns: Int? = nil,
        toolCallCount: Int? = nil,
        tokenCount: Int? = nil,
        redactedError: String? = nil,
        childToolReceipts: [ChildToolReceipt]? = nil,
        childLedgerReadOutcome: ChildLedgerReadOutcome? = nil,
        collectionStatus: String? = nil,
        collectionReceiptCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.toolCallID = toolCallID
        self.childID = childID
        self.runtimeModelID = runtimeModelID
        self.durationMilliseconds = durationMilliseconds
        self.turns = turns
        self.toolCallCount = toolCallCount
        self.tokenCount = tokenCount
        self.redactedError = redactedError
        self.childToolReceipts = childToolReceipts
        self.childLedgerReadOutcome = childLedgerReadOutcome
        self.collectionStatus = collectionStatus
        self.collectionReceiptCount = collectionReceiptCount
        self.scheduledTask = scheduledTask
    }
}

/// Detects background-task-related tool activity from ACP `session/update` payloads.
enum BackgroundToolParsing {
    static let backgroundToolNames: Set<String> = [
        "run_terminal_command",
        "monitor",
        "kill_command_or_subagent",
        "get_command_or_subagent_output",
        "spawn_subagent",
        "spawn-subagent",
    ]

    static func backgroundToolName(inUpdate update: [String: Any]) -> String? {
        if let meta = update["_meta"] as? [String: Any],
           let tool = meta["x.ai/tool"] as? [String: Any],
           let name = tool["name"] as? String {
            let normalized = normalizedToolName(name)
            if backgroundToolNames.contains(normalized) {
                return normalized
            }
            if normalized.hasPrefix("scheduler_") {
                return normalized
            }
        }
        if let out = rawOutput(inUpdate: update),
           let type = out["type"] as? String {
            let normalized = type.lowercased().replacingOccurrences(of: "-", with: "_")
            if normalized.hasPrefix("scheduler") { return normalized }
        }
        return nil
    }

    static func normalizedToolName(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    static func toolCallId(inUpdate update: [String: Any]) -> String? {
        update["toolCallId"] as? String ?? update["tool_call_id"] as? String
    }

    static func rawInput(inUpdate update: [String: Any]) -> [String: Any]? {
        update["rawInput"] as? [String: Any]
            ?? update["raw_input"] as? [String: Any]
            ?? update["rawinput"] as? [String: Any]
    }

    static func rawOutput(inUpdate update: [String: Any]) -> [String: Any]? {
        update["rawOutput"] as? [String: Any]
            ?? update["raw_output"] as? [String: Any]
            ?? update["rawoutput"] as? [String: Any]
    }

    static func isBackgroundTerminalCommand(_ input: [String: Any]) -> Bool {
        if let background = input["background"] as? Bool { return background }
        if let background = input["is_background"] as? Bool { return background }
        if let background = input["run_in_background"] as? Bool { return background }
        return false
    }

    static func activityKind(for toolName: String, input: [String: Any]) -> BackgroundActivity.Kind? {
        let name = normalizedToolName(toolName)
        if name.hasPrefix("scheduler") { return .scheduled }
        if name == "run_terminal_command" {
            return isBackgroundTerminalCommand(input) ? .backgroundCommand : nil
        }
        if name == "monitor" { return .monitor }
        // A wait/collection tool contains the word "subagent" but is not a
        // worker. Only the explicit spawn operation may create a worker row.
        if name == "spawn_subagent" { return .subagent }
        return nil
    }

    static func title(
        for kind: BackgroundActivity.Kind,
        input: [String: Any],
        output: [String: Any]?,
        update: [String: Any]? = nil
    ) -> String {
        if let updateTitle = update?["title"] as? String,
           !updateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           normalizedToolName(updateTitle) != "spawn_subagent" {
            return updateTitle
        }
        switch kind {
        case .scheduled:
            return input["prompt"] as? String ?? output?["id"] as? String ?? "Scheduled task"
        case .backgroundCommand:
            return input["command"] as? String ?? input["cmd"] as? String ?? "Background command"
        case .monitor:
            return input["name"] as? String ?? input["target"] as? String ?? "Monitor"
        case .subagent:
            return input["name"] as? String
                ?? input["role"] as? String
                ?? input["prompt"] as? String
                ?? input["description"] as? String
                ?? "Subagent"
        }
    }

    static func workerChildID(input: [String: Any], output: [String: Any]? = nil) -> String? {
        let keys = [
            "child_session_id", "childSessionID", "child_session", "subagent_id",
            "subagentID", "task_id", "taskId"
        ]
        for key in keys {
            if let value = input[key] as? String, !value.isEmpty { return value }
            if let value = output?[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    static func referencedIDs(input: [String: Any], output: [String: Any]? = nil) -> [String] {
        let scalarKeys = [
            "child_session_id", "childSessionID", "child_session", "subagent_id",
            "subagentID", "task_id", "taskId", "command_id", "commandId", "id"
        ]
        let listKeys = ["task_ids", "taskIds", "subagent_ids", "subagentIds", "command_ids", "commandIds", "ids"]
        var seen = Set<String>()
        var result: [String] = []

        func append(_ value: String?) {
            guard let value, !value.isEmpty, seen.insert(value).inserted else { return }
            result.append(value)
        }

        for key in scalarKeys {
            append(input[key] as? String)
            append(output?[key] as? String)
        }
        for key in listKeys {
            if let values = input[key] as? [String] {
                values.forEach { append($0) }
            } else if let values = input[key] as? [Any] {
                values.forEach { append($0 as? String) }
            }
            if let values = output?[key] as? [String] {
                values.forEach { append($0) }
            } else if let values = output?[key] as? [Any] {
                values.forEach { append($0 as? String) }
            }
        }
        return result
    }
}

/// Accumulates observed background activity from ACP tool updates.
struct BackgroundTaskTracker {
    private(set) var activities: [BackgroundActivity] = []
    private var scheduledTracker = ScheduledTaskTracker()
    private var pendingInputs: [String: [String: Any]] = [:]
    private var pendingSpawnedEvents: [String: SubagentSpawnedEvent] = [:]
    private var pendingFinishedEvents: [String: SubagentFinishedEvent] = [:]
    private var observedSpawnedChildIDs: Set<String> = []
    private var observedFinishedEvents: [String: SubagentFinishedEvent] = [:]
    private var activeSpawnedChildIDs: Set<String> = []
    private var maximumUsefulConcurrency = 0
    private var stopToSettleMilliseconds: Int?
    private var anonymousWorkerSequence = 0

    /// Spawned lifecycle receipts that never bound to a spawn tool row.
    var unboundSpawnedEvents: [SubagentSpawnedEvent] {
        Array(pendingSpawnedEvents.values)
    }

    /// Finished lifecycle receipts that never bound to a spawn tool row.
    var unboundFinishedEvents: [SubagentFinishedEvent] {
        Array(pendingFinishedEvents.values)
    }

    /// Turn-scoped run-evidence workers. ChatStore still owns which activity IDs
    /// belong to the current parent turn and the role→model table; this reducer
    /// maps tracker rows plus unbound spawn receipts onto
    /// `RunEvidenceSnapshot.Worker` without inventing a `BackgroundActivity`.
    func evidenceWorkers(
        currentTurnActivityIDs: Set<String>,
        planStepIDs: [String: String],
        rolesByName: [String: String]
    ) -> [RunEvidenceSnapshot.Worker] {
        let activityWorkers = activities.filter {
            $0.kind == .subagent && currentTurnActivityIDs.contains($0.id)
        }.map { worker(from: $0, planStepIDs: planStepIDs, rolesByName: rolesByName) }
        let boundChildIDs = Set(activityWorkers.compactMap(\.childID))
        let finishedByChild = Dictionary(
            uniqueKeysWithValues: unboundFinishedEvents.map { ($0.childID, $0) }
        )
        let unboundSpawned = unboundSpawnedEvents
            .filter { !boundChildIDs.contains($0.childID) }
            .map { spawn in
                RunEvidenceSnapshot.unboundWorker(
                    from: spawn,
                    finished: finishedByChild[spawn.childID],
                    rolesByName: rolesByName
                )
            }
        let unboundSpawnedChildIDs = Set(unboundSpawned.compactMap(\.childID))
        let unboundFinished = unboundFinishedEvents
            .filter { !boundChildIDs.contains($0.childID) && !unboundSpawnedChildIDs.contains($0.childID) }
            .map { RunEvidenceSnapshot.unboundFinishedWorker(from: $0) }
        return activityWorkers + unboundSpawned + unboundFinished
    }

    private func worker(
        from activity: BackgroundActivity,
        planStepIDs: [String: String],
        rolesByName: [String: String]
    ) -> RunEvidenceSnapshot.Worker {
        RunEvidenceSnapshot.Worker(
            id: activity.id,
            title: activity.title,
            status: activity.status,
            owningPlanStepID: planStepIDs[activity.id],
            childID: activity.childID,
            durationMilliseconds: activity.durationMilliseconds,
            toolCallCount: activity.toolCallCount,
            redactedError: activity.redactedError,
            childToolReceipts: activity.childToolReceipts,
            runtimeModelID: activity.runtimeModelID,
            routedModel: SubagentRouting.routedModel(
                forWorkerTitle: activity.title,
                rolesByName: rolesByName
            ),
            childLedgerReadOutcome: activity.childLedgerReadOutcome,
            tokenCount: activity.tokenCount,
            turns: activity.turns
        )
    }

    /// Typed, per-turn observations for the settled Run receipt. This reducer
    /// owns correlation only; the parent usage value still comes from the
    /// authoritative parent `turn_completed` receipt supplied by ChatStore.
    func coordinationMetrics(parentTotalTokens: Int?) -> RunEvidenceSnapshot.CoordinationMetrics {
        let requestedRows = activities.filter { $0.kind == .subagent }
        let boundChildIDs = Set(requestedRows.compactMap(\.childID))
        let unboundLifecycleIDs = observedSpawnedChildIDs.subtracting(boundChildIDs)
        let childToolCounts = observedFinishedEvents.values.compactMap(\.toolCallCount)
        let childTokenCounts = observedFinishedEvents.values.compactMap(\.tokenCount)
        return RunEvidenceSnapshot.CoordinationMetrics(
            requestedChildCount: requestedRows.count,
            spawnedChildCount: observedSpawnedChildIDs.count,
            finishedChildCount: observedFinishedEvents.count,
            maximumUsefulConcurrency: maximumUsefulConcurrency,
            childToolCallCount: childToolCounts.isEmpty ? nil : childToolCounts.reduce(0, +),
            unresolvedIdentityCount: requestedRows.filter { $0.childID == nil }.count
                + unboundLifecycleIDs.count,
            stopToSettleMilliseconds: stopToSettleMilliseconds,
            parentTotalTokens: parentTotalTokens,
            childTotalTokens: childTokenCounts.isEmpty ? nil : childTokenCounts.reduce(0, +)
        )
    }

    mutating func recordStopToSettle(milliseconds: Int) {
        stopToSettleMilliseconds = max(0, milliseconds)
    }

    mutating func apply(update: [String: Any]) {
        scheduledTracker.apply(update: update)

        guard let toolName = BackgroundToolParsing.backgroundToolName(inUpdate: update) else { return }
        let normalizedToolName = BackgroundToolParsing.normalizedToolName(toolName)
        let callId = BackgroundToolParsing.toolCallId(inUpdate: update)
        if let callId, let input = BackgroundToolParsing.rawInput(inUpdate: update), !input.isEmpty {
            pendingInputs[callId] = mergedInput(pendingInputs[callId], with: input)
        }

        let input = callId.flatMap { pendingInputs[$0] } ?? BackgroundToolParsing.rawInput(inUpdate: update) ?? [:]
        let output = BackgroundToolParsing.rawOutput(inUpdate: update)

        if normalizedToolName.hasPrefix("scheduler") {
            syncScheduledActivities()
            if let callId { pendingInputs[callId] = nil }
            return
        }

        switch normalizedToolName {
        case "spawn_subagent":
            applySpawnToolUpdate(update, callID: callId, input: input, output: output)
            clearPendingInputIfTerminal(update, callID: callId)
            return
        case "get_command_or_subagent_output":
            applyCollectionReceipt(update, input: input, output: output)
            clearPendingInputIfTerminal(update, callID: callId)
            return
        case "kill_command_or_subagent":
            applyKillReceipt(update, input: input, output: output)
            clearPendingInputIfTerminal(update, callID: callId)
            return
        default:
            break
        }

        guard let kind = BackgroundToolParsing.activityKind(for: toolName, input: input) else {
            if let callId { pendingInputs[callId] = nil }
            return
        }

        let id = output?["id"] as? String
            ?? output?["command_id"] as? String
            ?? output?["subagent_id"] as? String
            ?? callId
            ?? UUID().uuidString
        let title = BackgroundToolParsing.title(for: kind, input: input, output: output, update: update)
        let status = update["status"] as? String
            ?? output?["status"] as? String
            ?? (output == nil ? "running" : "done")
        let detail = output?["output"] as? String ?? input["description"] as? String ?? ""

        upsert(BackgroundActivity(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            status: status
        ))

        clearPendingInputIfTerminal(update, callID: callId)
    }

    /// Binds the authoritative typed spawn receipt to the worker row created by
    /// `spawn_subagent`. The lifecycle event never creates a row by itself: a
    /// missing spawn call is evidence of an unmatched/orphaned receipt, not a
    /// reason to invent a worker.
    mutating func apply(spawned event: SubagentSpawnedEvent) {
        recordSpawnedLifecycle(event)
        guard bindSpawnedLifecycle(event) else {
            pendingSpawnedEvents[event.childID] = event
            return
        }
    }

    /// Binds one typed spawn receipt without changing the lifecycle counters.
    /// Returning false preserves the receipt for a later tool row to reconcile.
    private mutating func bindSpawnedLifecycle(_ event: SubagentSpawnedEvent) -> Bool {
        let exactTitle = event.description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let descriptionMatchedIndex = exactTitle.flatMap { expected in
            let matches = activities.indices.filter { index in
                let activity = activities[index]
                guard activity.kind == .subagent, activity.childID == nil else { return false }
                return activity.title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == expected
            }
            return matches.count == 1 ? matches[0] : nil
        }
        // Current Grok emits a spawn tool receipt before the authoritative child
        // ID, then delivers `subagent_spawned` with that ID. Bind the lifecycle
        // receipt only to the one pre-existing, still-unbound worker whose
        // backend description exactly matches its title. A missing or ambiguous
        // match remains pending rather than inventing a worker identity.
        guard let index = workerIndex(childID: event.childID) ?? descriptionMatchedIndex else {
            return false
        }
        var activity = activities[index]
        activity.childID = event.childID
        activity.runtimeModelID = event.modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !BackgroundActivityStatusPolicy.isTerminalWorkerStatus(activity.status) {
            activity.status = "running"
        }
        if activity.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || activity.title == "Subagent" {
            activity.title = event.subagentType ?? "Subagent"
        }
        if activity.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activity.detail = event.description ?? ""
        }
        activities[index] = activity
        pendingSpawnedEvents[event.childID] = nil
        reconcilePendingFinished(for: event.childID)
        return true
    }

    /// Applies only the terminal facts carried by the typed lifecycle receipt.
    /// A prose answer or a completed spawn tool call cannot reach this method and
    /// therefore cannot mark a worker successful.
    mutating func apply(finished event: SubagentFinishedEvent) {
        let effectiveEvent = observedFinishedEvents[event.childID]
            .map { mergedFinishedEvent($0, with: event) }
            ?? event
        observedFinishedEvents[event.childID] = effectiveEvent
        activeSpawnedChildIDs.remove(event.childID)
        guard let index = workerIndex(childID: event.childID) else {
            pendingFinishedEvents[event.childID] = effectiveEvent
            return
        }
        var activity = activities[index]
        activity.childID = effectiveEvent.childID
        activity.status = BackgroundActivityStatusPolicy.canonicalWorkerTerminalStatus(effectiveEvent.status)
        activity.durationMilliseconds = effectiveEvent.durationMilliseconds
        activity.turns = effectiveEvent.turns
        activity.toolCallCount = effectiveEvent.toolCallCount
        activity.tokenCount = effectiveEvent.tokenCount
        activity.redactedError = effectiveEvent.redactedError
        activity.childToolReceipts = effectiveEvent.childToolReceipts
        activity.childLedgerReadOutcome = ChildLedgerReadOutcome.from(receipts: effectiveEvent.childToolReceipts)
        activities[index] = activity
        pendingFinishedEvents[event.childID] = nil
    }

    /// Rechecks an already-bound child ledger at the parent completion barrier.
    /// This closes the small flush-order window between `subagent_finished` and
    /// the child's final JSONL write without weakening identity or count checks.
    mutating func reconcileChildToolReceipts(
        childID: String,
        receipts: [ChildToolReceipt]?
    ) {
        guard let index = workerIndex(childID: childID) else { return }
        activities[index].childLedgerReadOutcome = ChildLedgerReadOutcome.from(receipts: receipts)
        guard let receipts else { return }
        activities[index].childToolReceipts = receipts
    }

    /// Parent turn completion is a protocol ordering barrier. Any worker still
    /// active after that barrier is explicitly unresolved: a known child is
    /// orphaned (terminal evidence is missing), while a spawn with no child
    /// receipt is unknown. Neither state is counted as a success.
    mutating func markUnsettledSubagents(only activityIDs: Set<String>? = nil) {
        activities = activities.map { activity in
            guard activity.kind == .subagent,
                  activityIDs?.contains(activity.id) ?? true,
                  BackgroundActivityStatusPolicy.isActive(activity.status) else { return activity }
            var unsettled = activity
            if activity.childID == nil {
                unsettled.status = "unknown"
                if unsettled.detail.isEmpty {
                    unsettled.detail = "Worker identity was not reported."
                }
            } else {
                unsettled.status = "orphaned"
                if unsettled.detail.isEmpty {
                    unsettled.detail = "Terminal worker status was not reported."
                }
            }
            return unsettled
        }
    }

    /// Prunes live workers and other non-scheduled activities at the start of a
    /// new user turn. Scheduled tasks and their tracker state survive; settled
    /// worker receipts remain on the message checkpoint, not in this mirror.
    /// Unbound spawn/finish receipts never had activity rows, so they are
    /// dropped wholesale — a child-ID filter would leak them into the next turn.
    mutating func beginUserTurn() {
        let removed = activities.filter { $0.kind != .scheduled }
        let removedActivityIDs = Set(removed.map(\.id))
        let removedToolCallIDs = Set(removed.compactMap(\.toolCallID))

        activities.removeAll { $0.kind != .scheduled }

        pendingInputs = pendingInputs.filter { key, _ in
            !removedActivityIDs.contains(key) && !removedToolCallIDs.contains(key)
        }
        pendingSpawnedEvents = [:]
        pendingFinishedEvents = [:]
        observedSpawnedChildIDs = []
        observedFinishedEvents = [:]
        activeSpawnedChildIDs = []
        maximumUsefulConcurrency = 0
        stopToSettleMilliseconds = nil
    }

    mutating func reset() {
        activities = []
        scheduledTracker = ScheduledTaskTracker()
        pendingInputs = [:]
        pendingSpawnedEvents = [:]
        pendingFinishedEvents = [:]
        observedSpawnedChildIDs = []
        observedFinishedEvents = [:]
        activeSpawnedChildIDs = []
        maximumUsefulConcurrency = 0
        stopToSettleMilliseconds = nil
        anonymousWorkerSequence = 0
    }

    mutating func markActiveActivitiesStopped() {
        activities = activities.map { activity in
            guard activity.kind != .scheduled,
                  activity.kind != .subagent,
                  BackgroundActivityStatusPolicy.isActive(activity.status) else { return activity }
            var stopped = activity
            stopped.status = "stopped"
            return stopped
        }
    }

    /// User Stop on the parent turn. Subagents without `subagent_finished` are
    /// explicitly cancelled or orphaned — never `"stopped"` as if cleanly terminal.
    mutating func markActiveSubagentsStoppedByUser() {
        activities = activities.map { activity in
            guard activity.kind == .subagent,
                  BackgroundActivityStatusPolicy.isActive(activity.status) else { return activity }
            var stopped = activity
            if activity.childID != nil {
                stopped.status = "orphaned"
                if stopped.detail.isEmpty {
                    stopped.detail = "Stopped before terminal worker status was reported."
                }
            } else {
                stopped.status = "cancelled"
            }
            return stopped
        }
    }

    private mutating func syncScheduledActivities() {
        let scheduledIDs = Set(scheduledTracker.tasks.map(\.id))
        activities.removeAll { $0.kind == .scheduled && !scheduledIDs.contains($0.id) }
        for task in scheduledTracker.tasks {
            let title = task.prompt.isEmpty ? task.intervalHuman : task.prompt
            upsert(BackgroundActivity(
                id: task.id,
                kind: .scheduled,
                title: title,
                detail: task.intervalHuman,
                status: task.recurring ? "recurring" : "once",
                scheduledTask: task
            ))
        }
    }

    private mutating func applySpawnToolUpdate(
        _ update: [String: Any],
        callID: String?,
        input: [String: Any],
        output: [String: Any]?
    ) {
        let childID = BackgroundToolParsing.workerChildID(input: input, output: output)
        let index = workerIndex(callID: callID, childID: childID)
        let title = BackgroundToolParsing.title(
            for: .subagent,
            input: input,
            output: output,
            update: update
        )
        let detail = input["description"] as? String
            ?? input["prompt"] as? String
            ?? ""
        let toolStatus = (update["status"] as? String ?? output?["status"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let status = ["failed", "error", "rejected"].contains(toolStatus) ? "unknown" : "running"

        if let index {
            var activity = activities[index]
            activity.toolCallID = callID ?? activity.toolCallID
            activity.childID = childID ?? activity.childID
            if !title.isEmpty,
               title != "Subagent",
               (update["title"] as? String) != nil || BackgroundActivityStatusPolicy.isPlaceholderTitle(activity.title) {
                activity.title = title
            }
            if !detail.isEmpty { activity.detail = detail }
            if !BackgroundActivityStatusPolicy.isTerminalWorkerStatus(activity.status) {
                activity.status = status
            }
            activities[index] = activity
        } else {
            anonymousWorkerSequence &+= 1
            let id = callID ?? childID ?? "spawn-\(anonymousWorkerSequence)"
            activities.append(BackgroundActivity(
                id: id,
                kind: .subagent,
                title: title,
                detail: detail,
                status: status,
                toolCallID: callID,
                childID: childID
            ))
        }

        if let childID {
            reconcilePendingLifecycle(for: childID)
        } else {
            reconcilePendingSpawnedEvents()
        }
    }

    private mutating func applyCollectionReceipt(
        _ update: [String: Any],
        input: [String: Any],
        output: [String: Any]?
    ) {
        let targets = BackgroundToolParsing.referencedIDs(input: input, output: output)
        guard !targets.isEmpty else { return }
        let status = update["status"] as? String
            ?? output?["status"] as? String
            ?? "received"
        for index in activities.indices where targets.contains(where: { matches($0, activity: activities[index]) }) {
            activities[index].collectionStatus = status
            activities[index].collectionReceiptCount += 1
        }
    }

    private mutating func applyKillReceipt(
        _ update: [String: Any],
        input: [String: Any],
        output: [String: Any]?
    ) {
        let targets = BackgroundToolParsing.referencedIDs(input: input, output: output)
        guard !targets.isEmpty else { return }
        guard let rawStatus = update["status"] as? String ?? output?["status"] as? String else { return }
        let normalizedStatus = rawStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard BackgroundActivityStatusPolicy.isTerminalToolStatus(normalizedStatus) else { return }
        let killStatus = ["failed", "error", "rejected"].contains(normalizedStatus) ? "unknown" : "cancelled"
        for index in activities.indices where targets.contains(where: { matches($0, activity: activities[index]) }) {
            guard !BackgroundActivityStatusPolicy.isTerminalWorkerStatus(activities[index].status) else { continue }
            activities[index].status = killStatus
        }
    }

    private func matches(_ target: String, activity: BackgroundActivity) -> Bool {
        target == activity.id || target == activity.toolCallID || target == activity.childID
    }

    private func workerIndex(callID: String? = nil, childID: String? = nil) -> Int? {
        activities.firstIndex { activity in
            guard activity.kind == .subagent else { return false }
            if let callID, activity.toolCallID == callID || activity.id == callID { return true }
            if let childID, activity.childID == childID { return true }
            return false
        }
    }

    private mutating func reconcilePendingLifecycle(for childID: String) {
        if let spawned = pendingSpawnedEvents.removeValue(forKey: childID) {
            if !bindSpawnedLifecycle(spawned) {
                pendingSpawnedEvents[childID] = spawned
            }
        }
        reconcilePendingFinished(for: childID)
    }

    private mutating func reconcilePendingSpawnedEvents() {
        for childID in pendingSpawnedEvents.keys.sorted() {
            guard let event = pendingSpawnedEvents[childID] else { continue }
            if bindSpawnedLifecycle(event) {
                pendingSpawnedEvents[childID] = nil
            }
        }
    }

    private mutating func reconcilePendingFinished(for childID: String) {
        if let finished = pendingFinishedEvents.removeValue(forKey: childID) {
            apply(finished: finished)
        }
    }

    private mutating func recordSpawnedLifecycle(_ event: SubagentSpawnedEvent) {
        guard observedSpawnedChildIDs.insert(event.childID).inserted else { return }
        activeSpawnedChildIDs.insert(event.childID)
        maximumUsefulConcurrency = max(maximumUsefulConcurrency, activeSpawnedChildIDs.count)
        if observedFinishedEvents[event.childID] != nil {
            activeSpawnedChildIDs.remove(event.childID)
        }
    }

    /// Lifecycle delivery is at-least-once. Keep the richer terminal receipt so
    /// a sparse replay cannot erase usage or child-ledger evidence already seen.
    private func mergedFinishedEvent(
        _ existing: SubagentFinishedEvent,
        with incoming: SubagentFinishedEvent
    ) -> SubagentFinishedEvent {
        let existingCanonical = BackgroundActivityStatusPolicy.canonicalWorkerTerminalStatus(existing.status)
        let incomingCanonical = BackgroundActivityStatusPolicy.canonicalWorkerTerminalStatus(incoming.status)
        let status = incomingCanonical == "unknown" && existingCanonical != "unknown"
            ? existing.status
            : incoming.status
        let receipts: [ChildToolReceipt]?
        switch (existing.childToolReceipts, incoming.childToolReceipts) {
        case let (current?, replay?):
            receipts = replay.count >= current.count ? replay : current
        case let (current?, nil):
            receipts = current
        case let (nil, replay?):
            receipts = replay
        case (nil, nil):
            receipts = nil
        }
        return SubagentFinishedEvent(
            identity: incoming.identity,
            childID: incoming.childID,
            status: status,
            durationMilliseconds: incoming.durationMilliseconds ?? existing.durationMilliseconds,
            turns: incoming.turns ?? existing.turns,
            toolCallCount: incoming.toolCallCount ?? existing.toolCallCount,
            tokenCount: incoming.tokenCount ?? existing.tokenCount,
            redactedError: incoming.redactedError ?? existing.redactedError,
            childToolReceipts: receipts
        )
    }

    private func mergedInput(_ previous: [String: Any]?, with current: [String: Any]) -> [String: Any] {
        var merged = previous ?? [:]
        for (key, value) in current {
            merged[key] = value
        }
        return merged
    }

    private mutating func clearPendingInputIfTerminal(_ update: [String: Any], callID: String?) {
        guard let callID,
              let status = update["status"] as? String
                ?? BackgroundToolParsing.rawOutput(inUpdate: update)?["status"] as? String,
              BackgroundActivityStatusPolicy.isTerminalToolStatus(status) else { return }
        pendingInputs[callID] = nil
    }

    private mutating func upsert(_ activity: BackgroundActivity) {
        if let idx = activities.firstIndex(where: { $0.id == activity.id }) {
            var merged = activity
            if merged.title.isEmpty { merged.title = activities[idx].title }
            if merged.detail.isEmpty { merged.detail = activities[idx].detail }
            activities[idx] = merged
        } else {
            activities.append(activity)
        }
    }
}

enum BackgroundActivityStatusPolicy {
    static func isPlaceholderTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "subagent" || normalized == "spawn_subagent"
    }

    static func isActive(_ status: String) -> Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        return !["done", "complete", "success", "succeed", "failed", "error", "stopped", "cancelled", "canceled", "unknown", "orphaned", "not_settled"]
            .contains { normalized.hasPrefix($0) }
    }

    static func isTerminalWorkerStatus(_ status: String) -> Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["completed", "complete", "success", "succeeded", "done", "failed", "error", "cancelled", "canceled", "stopped"]
            .contains { normalized == $0 || normalized.hasPrefix($0 + ":") }
    }

    static func isTerminalToolStatus(_ status: String) -> Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["completed", "complete", "success", "succeeded", "done", "failed", "error", "cancelled", "canceled", "stopped", "rejected"]
            .contains { normalized == $0 || normalized.hasPrefix($0 + ":") }
    }

    static func canonicalWorkerTerminalStatus(_ status: String) -> String {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["completed", "complete", "success", "succeeded", "done"].contains(where: { normalized == $0 || normalized.hasPrefix($0 + ":") }) {
            return "completed"
        }
        if ["failed", "error", "rejected"].contains(where: { normalized == $0 || normalized.hasPrefix($0 + ":") }) {
            return "failed"
        }
        if ["cancelled", "canceled", "stopped"].contains(where: { normalized == $0 || normalized.hasPrefix($0 + ":") }) {
            return "cancelled"
        }
        return "unknown"
    }
}
