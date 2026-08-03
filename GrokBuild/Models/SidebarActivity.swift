import Foundation

/// One row in the sidebar's persistent Activity lane.
///
/// The lane is a pure read-model over state `ChatStore` already mirrors from ACP
/// (`backgroundActivities`, `scheduledTasks`, `workflowRuns`). It creates no lifecycle,
/// never talks to the backend, and titles/details arrive already redacted upstream.
struct SidebarActivityEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case subagent
        case backgroundCommand
        case monitor
        case scheduled
        case workflow
    }

    /// Stable across refreshes: `<sessionID>/<source id>` so the same activity in two
    /// different sessions can never collide in one List.
    let id: String
    let sessionID: UUID
    let kind: Kind
    let title: String
    /// Plain-language status ("Running", "Done", "Failed", …) — not raw wire status.
    let statusLabel: String
    let isRunning: Bool
    let sessionTitle: String

    var systemImageName: String {
        switch kind {
        case .subagent: return "person.2"
        case .backgroundCommand: return "terminal"
        case .monitor: return "eye"
        case .scheduled: return "clock"
        case .workflow: return "arrow.triangle.branch"
        }
    }

    var accessibilityLabel: String {
        let kindName: String
        switch kind {
        case .subagent: kindName = "Subagent"
        case .backgroundCommand: kindName = "Background command"
        case .monitor: kindName = "Monitor"
        case .scheduled: kindName = "Scheduled task"
        case .workflow: kindName = "Workflow"
        }
        return "\(kindName): \(title), \(statusLabel), in \(sessionTitle)"
    }
}

/// The projected lane: a bounded list plus how many rows were dropped by the cap.
struct SidebarActivityLane: Equatable {
    var entries: [SidebarActivityEntry] = []
    var overflowCount: Int = 0

    var isEmpty: Bool { entries.isEmpty }
}

enum SidebarActivityProjection {
    /// Everything the lane needs from one live session. Values are copies of the
    /// session store's already-observed mirrors.
    struct SessionInput {
        let sessionID: UUID
        let sessionTitle: String
        let backgroundActivities: [BackgroundActivity]
        let scheduledTasks: [ScheduledTask]
        let workflowRuns: [WorkflowRun]
    }

    /// Default row cap keeps the lane a lane, not a log. Running work is never the
    /// part that gets dropped: rows sort running → scheduled → finished before capping.
    static let defaultLimit = 8

    static func lane(from sessions: [SessionInput], limit: Int = defaultLimit) -> SidebarActivityLane {
        var running: [SidebarActivityEntry] = []
        var standing: [SidebarActivityEntry] = []
        var finished: [SidebarActivityEntry] = []

        for session in sessions {
            // Scheduled tasks from the authoritative scheduler mirror.
            var seenScheduledTaskIDs = Set<String>()
            for task in session.scheduledTasks {
                seenScheduledTaskIDs.insert(task.id)
                standing.append(scheduledEntry(task, session: session))
            }

            for activity in session.backgroundActivities {
                if activity.kind == .scheduled {
                    // A scheduler tool call can mirror the same task into both lists;
                    // the scheduler mirror above stays authoritative.
                    if let task = activity.scheduledTask, seenScheduledTaskIDs.contains(task.id) {
                        continue
                    }
                    if let task = activity.scheduledTask {
                        seenScheduledTaskIDs.insert(task.id)
                        standing.append(scheduledEntry(task, session: session))
                    }
                    continue
                }
                let entry = backgroundEntry(activity, session: session)
                if entry.isRunning {
                    running.append(entry)
                } else {
                    finished.append(entry)
                }
            }

            for run in session.workflowRuns {
                let entry = workflowEntry(run, session: session)
                if entry.isRunning {
                    running.append(entry)
                } else {
                    finished.append(entry)
                }
            }
        }

        let ordered = running + standing + finished
        let capped = Array(ordered.prefix(max(0, limit)))
        return SidebarActivityLane(
            entries: capped,
            overflowCount: max(0, ordered.count - capped.count)
        )
    }

    // MARK: - Row builders

    private static func scheduledEntry(_ task: ScheduledTask, session: SessionInput) -> SidebarActivityEntry {
        let title = task.prompt.isEmpty ? "Scheduled task" : task.prompt
        let status: String
        if !task.intervalHuman.isEmpty {
            status = task.recurring ? "Every \(task.intervalHuman)" : "In \(task.intervalHuman)"
        } else if let next = task.nextFireAt {
            status = "Next \(next.formatted(date: .omitted, time: .shortened))"
        } else {
            status = "Scheduled"
        }
        return SidebarActivityEntry(
            id: "\(session.sessionID.uuidString)/scheduled/\(task.id)",
            sessionID: session.sessionID,
            kind: .scheduled,
            title: title,
            statusLabel: status,
            isRunning: false,
            sessionTitle: session.sessionTitle
        )
    }

    private static func backgroundEntry(_ activity: BackgroundActivity, session: SessionInput) -> SidebarActivityEntry {
        let kind: SidebarActivityEntry.Kind
        switch activity.kind {
        case .subagent: kind = .subagent
        case .backgroundCommand: kind = .backgroundCommand
        case .monitor: kind = .monitor
        case .scheduled: kind = .scheduled // unreachable; handled by caller
        }
        let isRunning = BackgroundActivityStatusPolicy.isActive(activity.status)
        let title = BackgroundActivityStatusPolicy.isPlaceholderTitle(activity.title)
            ? (activity.detail.isEmpty ? "Subagent" : activity.detail)
            : activity.title
        return SidebarActivityEntry(
            id: "\(session.sessionID.uuidString)/background/\(activity.id)",
            sessionID: session.sessionID,
            kind: kind,
            title: title,
            statusLabel: isRunning ? "Running" : plainTerminalLabel(activity.status),
            isRunning: isRunning,
            sessionTitle: session.sessionTitle
        )
    }

    private static func workflowEntry(_ run: WorkflowRun, session: SessionInput) -> SidebarActivityEntry {
        let normalized = run.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isPaused = normalized == "paused"
        let isRunning = !isPaused && BackgroundActivityStatusPolicy.isActive(run.status)
        let status: String
        if isPaused {
            status = "Paused"
        } else if isRunning {
            status = run.phase.isEmpty ? "Running" : run.phase
        } else {
            status = plainTerminalLabel(run.status)
        }
        return SidebarActivityEntry(
            id: "\(session.sessionID.uuidString)/workflow/\(run.id)",
            sessionID: session.sessionID,
            kind: .workflow,
            title: run.name.isEmpty ? "Workflow" : run.name,
            statusLabel: status,
            isRunning: isRunning,
            sessionTitle: session.sessionTitle
        )
    }

    /// Plain language over the wire status, reusing the canonical terminal buckets.
    static func plainTerminalLabel(_ status: String) -> String {
        switch BackgroundActivityStatusPolicy.canonicalWorkerTerminalStatus(status) {
        case "completed": return "Done"
        case "failed": return "Failed"
        case "cancelled": return "Stopped"
        default: return "No final status"
        }
    }
}
