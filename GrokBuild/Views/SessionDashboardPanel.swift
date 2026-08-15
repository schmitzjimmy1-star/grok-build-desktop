import SwiftUI
import UniformTypeIdentifiers

/// Snapshot of a live session for the dashboard (owned by `ContentView`).
struct SessionDashboardEntry: Identifiable, Hashable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case needsInput
        case working
        case idle
        case failed

        var title: String {
            switch self {
            case .needsInput: return "Needs input"
            case .working: return "Working"
            case .idle: return "Idle"
            case .failed: return "Failed"
            }
        }

        var systemImage: String {
            switch self {
            case .needsInput: return "hand.raised"
            case .working: return "ellipsis.circle"
            case .idle: return "moon.zzz"
            case .failed: return "exclamationmark.triangle"
            }
        }
    }

    let id: UUID
    let title: String
    let workspaceName: String
    let group: Group
    let modelName: String
    let pendingCount: Int
    let lastActivationOrdinal: UInt64
    let runtimeLease: SessionRuntimeLease?
    let runtimeProtectionReasons: Set<SessionRuntimeProtectionReason>

    init(
        id: UUID,
        title: String,
        workspaceName: String,
        group: Group,
        modelName: String,
        pendingCount: Int,
        lastActivationOrdinal: UInt64,
        runtimeLease: SessionRuntimeLease? = nil,
        runtimeProtectionReasons: Set<SessionRuntimeProtectionReason> = []
    ) {
        self.id = id
        self.title = title
        self.workspaceName = workspaceName
        self.group = group
        self.modelName = modelName
        self.pendingCount = pendingCount
        self.lastActivationOrdinal = lastActivationOrdinal
        self.runtimeLease = runtimeLease
        self.runtimeProtectionReasons = runtimeProtectionReasons
    }
}

enum SessionDashboardPresentation {
    static func ordered(_ entries: [SessionDashboardEntry]) -> [SessionDashboardEntry] {
        entries.sorted { lhs, rhs in
            let lhsGroup = SessionDashboardEntry.Group.allCases.firstIndex(of: lhs.group) ?? 0
            let rhsGroup = SessionDashboardEntry.Group.allCases.firstIndex(of: rhs.group) ?? 0
            if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }
            if lhs.lastActivationOrdinal != rhs.lastActivationOrdinal {
                return lhs.lastActivationOrdinal > rhs.lastActivationOrdinal
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func accessibilityIdentifier(for id: UUID) -> String {
        "grok-session-dashboard-row-\(id.uuidString.lowercased())"
    }

    static func accessibilityLabel(
        for entry: SessionDashboardEntry,
        isSelected: Bool
    ) -> String {
        var parts = [
            "Session: \(entry.title)",
            entry.workspaceName,
            entry.modelName,
            entry.group.title
        ]
        if entry.pendingCount > 0 {
            parts.append("\(entry.pendingCount) pending")
        }
        if let lease = entry.runtimeLease {
            parts.append("Runtime pinned for \(lease.activeScheduleCount) active schedule\(lease.activeScheduleCount == 1 ? "" : "s")")
            parts.append("Process generation \(lease.processGeneration)")
        } else if !entry.runtimeProtectionReasons.isEmpty {
            parts.append(entry.runtimeProtectionReasons.map(\.displayName).sorted().joined(separator: " and "))
        }
        if isSelected {
            parts.append("Selected")
        }
        return parts.joined(separator: ", ")
    }
}

struct SessionDashboardPanel: View {
    let entries: [SessionDashboardEntry]
    let selectedSessionID: UUID?
    var runHistoryBySessionID: [UUID: [RunHistory.Record]] = [:]
    var softCapExcess: Int = 0
    var onSelect: (UUID) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var exportRecord: RunHistory.Record?

    private var orderedEntries: [SessionDashboardEntry] {
        SessionDashboardPresentation.ordered(entries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Session dashboard")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            if softCapExcess > 0 {
                Label(
                    "Runtime soft cap exceeded by \(softCapExcess). Active or scheduled work is retained instead of being silently stopped.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .accessibilityIdentifier("grok-runtime-soft-cap-warning")
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "hammer",
                    description: Text("Open a project and start a build session to track work here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(SessionDashboardEntry.Group.allCases, id: \.self) { group in
                            let groupEntries = orderedEntries.filter { $0.group == group }
                            if !groupEntries.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(group.title, systemImage: group.systemImage)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(color(for: group))
                                        .accessibilityAddTraits(.isHeader)

                                    ForEach(groupEntries) { entry in
                                        Button {
                                            onSelect(entry.id)
                                        } label: {
                                            HStack(alignment: .top) {
                                                Image(systemName: group.systemImage)
                                                    .foregroundStyle(color(for: group))
                                                    .frame(width: 20)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(entry.title)
                                                        .font(.headline)
                                                    Text(entry.workspaceName)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                    HStack(spacing: 8) {
                                                        Text(entry.modelName)
                                                            .font(.caption2)
                                                            .foregroundStyle(.tertiary)
                                                        if entry.pendingCount > 0 {
                                                            Text("\(entry.pendingCount) pending")
                                                                .font(.caption2.weight(.medium))
                                                                .foregroundStyle(.orange)
                                                        }
                                                    }
                                                    if let lease = entry.runtimeLease {
                                                        runtimeLeaseDetails(lease)
                                                    } else if !entry.runtimeProtectionReasons.isEmpty {
                                                        Text(entry.runtimeProtectionReasons.map(\.displayName).sorted().joined(separator: " • "))
                                                            .font(.caption2.weight(.medium))
                                                            .foregroundStyle(.orange)
                                                    }
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                            .background(
                                                selectedSessionID == entry.id
                                                    ? AppTheme.Palette.accentSoft
                                                    : Color.clear,
                                                in: RoundedRectangle(
                                                    cornerRadius: AppTheme.Radius.small,
                                                    style: .continuous
                                                )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityIdentifier(
                                            SessionDashboardPresentation.accessibilityIdentifier(for: entry.id)
                                        )
                                        .accessibilityLabel(
                                            SessionDashboardPresentation.accessibilityLabel(
                                                for: entry,
                                                isSelected: selectedSessionID == entry.id
                                            )
                                        )
                                        .accessibilityHint("Open this existing local session tab")
                                        .accessibilityAddTraits(
                                            selectedSessionID == entry.id ? [.isButton, .isSelected] : .isButton
                                        )
                                    }
                                }
                            }
                        }
                        RunHistorySection(
                            entries: entries,
                            runHistoryBySessionID: runHistoryBySessionID,
                            exportRecord: $exportRecord
                        )
                    }
                    .padding()
                }
                .accessibilityIdentifier("grok-session-dashboard-list")
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .accessibilityIdentifier("grok-session-dashboard")
        .fileExporter(
            isPresented: Binding(
                get: { exportRecord != nil },
                set: { if !$0 { exportRecord = nil } }
            ),
            document: exportRecord.map { RedactedRunHistoryDocument(record: $0) },
            contentType: .json,
            defaultFilename: "GrokBuild-redacted-run-receipt"
        ) { _ in
            exportRecord = nil
        }
    }

    private func color(for group: SessionDashboardEntry.Group) -> Color {
        switch group {
        case .needsInput: return .orange
        case .working: return .accentColor
        case .idle: return .secondary
        case .failed: return .red
        }
    }

    @ViewBuilder
    private func runtimeLeaseDetails(_ lease: SessionRuntimeLease) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Runtime pinned • \(lease.activeScheduleCount) active schedule\(lease.activeScheduleCount == 1 ? "" : "s")")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Backend \(lease.backendSessionID) • process generation \(lease.processGeneration)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text("Last scheduler receipt \(lease.lastSchedulerReceiptAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let settled = lease.lastSettledCheckpointAt {
                Text("Last settled checkpoint \(settled.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let next = lease.nextScheduledCheckpointAt {
                Text("Next scheduled checkpoint \(next.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(lease.isTurnActive
                ? "Stop ends this process and releases the lease; closing or quitting also stops scheduled work."
                : "Keep this session and GrokBuild open; cancel its schedules before closing it safely.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("grok-runtime-lease")
    }
}
