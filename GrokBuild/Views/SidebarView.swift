import SwiftUI
import AppKit

struct SidebarSession: Identifiable, Hashable {
    let id: UUID
    let workspaceID: Workspace.ID
    let title: String
    let modelName: String
    let lastAccessed: Date?
    let isRunning: Bool
    /// True when this session holds an authoritative active schedule lease
    /// (recurring `/loop` or other `scheduler_*` work pinning its live runtime).
    /// Surfaced as a distinct sidebar indicator so long-horizon scheduled work is
    /// visible even when the session is otherwise idle between checkpoints.
    let hasActiveSchedule: Bool

    init(
        id: UUID,
        workspaceID: Workspace.ID,
        title: String,
        modelName: String,
        lastAccessed: Date?,
        isRunning: Bool,
        hasActiveSchedule: Bool = false
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.modelName = modelName
        self.lastAccessed = lastAccessed
        self.isRunning = isRunning
        self.hasActiveSchedule = hasActiveSchedule
    }
}

enum SidebarSessionActivity {
    /// Sidebar "working" is a live spawn or turn, not a connected unsent draft.
    static func isWorking(connectionState: GrokProcessState, isStreaming: Bool) -> Bool {
        if isStreaming { return true }
        switch connectionState {
        case .starting, .busy:
            return true
        case .ready, .idle, .failed:
            return false
        }
    }
}

enum SessionSidebarMetadata {
    static func helpText(for session: SidebarSession) -> String {
        let activity = session.lastAccessed.map {
            "Last used \($0.formatted(date: .abbreviated, time: .shortened))"
        } ?? "New session"
        return "\(session.title)\n\(session.modelName) · \(activity)"
    }

    static func accessibilityLabel(for session: SidebarSession) -> String {
        let state = session.isRunning ? "working" : "idle"
        let activity = session.lastAccessed.map {
            "last used \($0.formatted(date: .abbreviated, time: .shortened))"
        } ?? "new session"
        let schedule = session.hasActiveSchedule ? ", scheduled work active" : ""
        return "Session: \(session.title), \(session.modelName), \(state)\(schedule), \(activity)"
    }
}

enum SidebarRailAction: CaseIterable {
    case newChat
    case sessions
    case plugins
    case security
}

enum SidebarPersistentSelection: Hashable {
    case workspace(Workspace.ID)
    case session(UUID)
}

/// Selection belongs only to the persistent conversation route. The compact rail
/// launches actions or transient destinations; focus, hover, and the last click do
/// not turn those buttons into navigation selection.
enum SidebarSelectionSemantics {
    static func railActionIsSelected(_ action: SidebarRailAction) -> Bool {
        false
    }

    static func workspaceIsSelected(
        _ workspaceID: Workspace.ID,
        selectedWorkspaceID: Workspace.ID?,
        selectedSessionID: UUID?,
        isConversationRouteActive: Bool
    ) -> Bool {
        persistentSelection(
            selectedWorkspaceID: selectedWorkspaceID,
            selectedSessionID: selectedSessionID,
            isConversationRouteActive: isConversationRouteActive
        ) == .workspace(workspaceID)
    }

    static func sessionIsSelected(
        _ sessionID: UUID,
        selectedSessionID: UUID?,
        isConversationRouteActive: Bool
    ) -> Bool {
        persistentSelection(
            selectedWorkspaceID: nil,
            selectedSessionID: selectedSessionID,
            isConversationRouteActive: isConversationRouteActive
        ) == .session(sessionID)
    }

    static func persistentSelection(
        selectedWorkspaceID: Workspace.ID?,
        selectedSessionID: UUID?,
        isConversationRouteActive: Bool
    ) -> SidebarPersistentSelection? {
        guard isConversationRouteActive else { return nil }
        if let selectedSessionID {
            return .session(selectedSessionID)
        }
        return selectedWorkspaceID.map(SidebarPersistentSelection.workspace)
    }
}

struct SidebarView: View {
    @Binding var workspaces: [Workspace]
    var orderedWorkspaces: [Workspace]
    var pinnedWorkspaceIDs: [UUID]
    @Binding var selectedWorkspaceID: Workspace.ID?
    var sessions: [SidebarSession] = []
    var hiddenSessionCounts: [Workspace.ID: Int] = [:]
    var selectedSessionID: UUID?
    var isConversationRouteActive = true
    @Binding var expandedSessionWorkspaceIDs: Set<Workspace.ID>
    @Binding var hiddenSessionWorkspaceIDs: Set<Workspace.ID>

    var onAddWorkspace: () -> Void
    var onSelectWorkspace: (Workspace) -> Void
    var onSelectSession: (UUID) -> Void = { _ in }
    var onNewSessionForWorkspace: (Workspace) -> Void = { _ in }
    var onRenameSession: (UUID, String) -> Void = { _, _ in }
    var onCloseSession: (UUID) -> Void = { _ in }
    var onCloseLocalSession: (UUID) -> Void = { _ in }
    var onMoveWorkspace: (IndexSet, Int) -> Void = { _, _ in }
    var onPinWorkspace: (Workspace) -> Void = { _ in }
    var onUnpinWorkspace: (Workspace) -> Void = { _ in }
    var onRemoveWorkspace: (Workspace) -> Void = { _ in }
    var onMoveSession: (Workspace.ID, IndexSet, Int) -> Void = { _, _, _ in }
    var onSwitchBranch: (Workspace) -> Void = { _ in }
    var onCreateWorktree: (Workspace) -> Void = { _ in }
    var onSessionDisclosureChanged: () -> Void = {}
    var onNewChat: () -> Void = {}
    var onBrowseSessions: () -> Void = {}
    var onOpenActivity: () -> Void = {}
    var onOpenPlugins: () -> Void = {}
    var onOpenSecurity: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    @Binding var isFilterVisible: Bool

    @State private var filter = ""
    @State private var renamingSessionID: UUID?
    @State private var renameText = ""

    private let collapsedSessionLimit = 3

    private var filtered: [Workspace] {
        let base = filter.isEmpty ? orderedWorkspaces : orderedWorkspaces.filter {
            $0.displayName.localizedCaseInsensitiveContains(filter)
        }
        return base
    }

    private var persistentSelection: Binding<SidebarPersistentSelection?> {
        Binding(
            get: {
                SidebarSelectionSemantics.persistentSelection(
                    selectedWorkspaceID: selectedWorkspaceID,
                    selectedSessionID: visibleSelectedSessionID,
                    isConversationRouteActive: isConversationRouteActive
                )
            },
            set: { _ in
                // Project/session buttons remain the only mutation owners. The
                // List binding projects their state into native row selection.
            }
        )
    }

    /// A session can own native sidebar selection only when its row exists in
    /// this projection. Restored/placeholder identity must not hide the selected
    /// project behind a row the user cannot see or reach.
    private var visibleSelectedSessionID: UUID? {
        guard let selectedSessionID,
              let selectedWorkspaceID,
              !hiddenSessionWorkspaceIDs.contains(selectedWorkspaceID) else {
            return nil
        }
        let projectSessions = sessions(for: selectedWorkspaceID)
        let renderedSessions = isSessionsExpanded(for: selectedWorkspaceID)
            ? projectSessions
            : collapsedSessions(from: projectSessions)
        guard renderedSessions.contains(where: { $0.id == selectedSessionID }) else {
            return nil
        }
        return selectedSessionID
    }

    private func sessions(for workspaceID: Workspace.ID) -> [SidebarSession] {
        sessions.filter { $0.workspaceID == workspaceID }
    }

    private func isSessionsExpanded(for workspaceID: Workspace.ID) -> Bool {
        expandedSessionWorkspaceIDs.contains(workspaceID)
    }

    private func collapsedSessions(from sessions: [SidebarSession]) -> [SidebarSession] {
        Array(sessions.prefix(collapsedSessionLimit))
    }

    private func hiddenCount(for workspaceID: Workspace.ID, loadedSessions: [SidebarSession], isExpanded: Bool) -> Int {
        let hiddenBeyondLoaded = hiddenSessionCounts[workspaceID] ?? 0
        if isExpanded {
            return hiddenBeyondLoaded
        }
        return max(0, loadedSessions.count - collapsedSessionLimit) + hiddenBeyondLoaded
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter and Session dashboard live in ChatTopBar, to the right of
            // the session title. The rail starts here so those icons cannot
            // collide with the description.
            VStack(spacing: 2) {
                CodexRailButton(title: "New chat", systemImage: "square.and.pencil", railAction: .newChat, action: onNewChat)
                CodexRailButton(title: "Sessions", systemImage: "clock.arrow.circlepath", railAction: .sessions, action: onBrowseSessions)
                CodexRailButton(title: "Plugins", systemImage: "shippingbox", railAction: .plugins, action: onOpenPlugins)
                CodexRailButton(title: "Security", systemImage: "checkmark.shield", railAction: .security, action: onOpenSecurity)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 8)

            if isFilterVisible {
                TextField("Filter projects", text: $filter)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        AppTheme.Palette.glassTint,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                            .stroke(AppTheme.Palette.glassBorder, lineWidth: 1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            List(selection: persistentSelection) {
                Section {
                    ForEach(filtered) { ws in
                        Button {
                            onSelectWorkspace(ws)
                        } label: {
                            let projectSessions = sessions(for: ws.id)
                            WorkspaceRow(
                                workspace: ws,
                                isPinned: pinnedWorkspaceIDs.contains(ws.id),
                                isSelected: SidebarSelectionSemantics.workspaceIsSelected(
                                    ws.id,
                                    selectedWorkspaceID: selectedWorkspaceID,
                                    selectedSessionID: visibleSelectedSessionID,
                                    isConversationRouteActive: isConversationRouteActive
                                ),
                                hasSessions: !projectSessions.isEmpty,
                                areSessionsHidden: hiddenSessionWorkspaceIDs.contains(ws.id),
                                onToggleSessions: {
                                    toggleSessionVisibility(for: ws.id)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .tag(SidebarPersistentSelection.workspace(ws.id))
                        .accessibilityAddTraits(
                            SidebarSelectionSemantics.workspaceIsSelected(
                                ws.id,
                                selectedWorkspaceID: selectedWorkspaceID,
                                selectedSessionID: visibleSelectedSessionID,
                                isConversationRouteActive: isConversationRouteActive
                            ) ? .isSelected : []
                        )
                        .accessibilityRemoveTraits(
                            SidebarSelectionSemantics.workspaceIsSelected(
                                ws.id,
                                selectedWorkspaceID: selectedWorkspaceID,
                                selectedSessionID: visibleSelectedSessionID,
                                isConversationRouteActive: isConversationRouteActive
                            ) ? [] : .isSelected
                        )
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            projectContextMenu(for: ws)
                        }

                        let projectSessions = sessions(for: ws.id)
                        let ownsSelectedSession = selectedSessionID.map { id in
                            projectSessions.contains { $0.id == id }
                        } ?? false
                        if (selectedWorkspaceID == ws.id || ownsSelectedSession),
                           !hiddenSessionWorkspaceIDs.contains(ws.id) {
                            let isExpanded = isSessionsExpanded(for: ws.id)
                            let shownSessions = isExpanded ? projectSessions : collapsedSessions(from: projectSessions)

                            if isExpanded {
                                ForEach(shownSessions) { session in
                                    sessionRow(session)
                                }
                                .onMove { source, destination in
                                    onMoveSession(ws.id, source, destination)
                                }
                            } else {
                                ForEach(shownSessions) { session in
                                    sessionRow(session)
                                }
                            }

                            let hidden = hiddenCount(for: ws.id, loadedSessions: projectSessions, isExpanded: isExpanded)
                            if hidden > 0 || isExpanded {
                                Button {
                                    if isExpanded {
                                        expandedSessionWorkspaceIDs.remove(ws.id)
                                    } else {
                                        expandedSessionWorkspaceIDs.insert(ws.id)
                                    }
                                    onSessionDisclosureChanged()
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(isExpanded ? "Show less" : "Show more")
                                            .font(.caption.weight(.medium))
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption2.weight(.semibold))
                                        Spacer()
                                    }
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 2, leading: 34, bottom: 6, trailing: 10))
                                .listRowBackground(Color.clear)

                                if isExpanded, hidden > 0 {
                                    Text("\(hidden) more in Browse Sessions…")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 34, bottom: 6, trailing: 10))
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        guard filter.isEmpty else { return }
                        onMoveWorkspace(source, destination)
                    }

                } header: {
                    HStack {
                        Text("Projects")
                        Spacer()
                        Button(action: onAddWorkspace) {
                            Image(systemName: "plus")
                                .contentShape(Rectangle().inset(by: -8))
                        }
                        .buttonStyle(.plain)
                        .help("New project")
                        .accessibilityLabel("New project")
                        .accessibilityHint("Opens the folder picker to add a project.")
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(AppTheme.Palette.sidebar)

            Divider()

            Button(action: onOpenSettings) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.blue.opacity(0.9))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Text(String(NSFullUserName().prefix(1)).uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    Text(NSFullUserName().isEmpty ? NSUserName() : NSFullUserName())
                        .font(AppTheme.Typography.captionStrong)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Settings")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open Settings")
            .accessibilityValue(NSFullUserName().isEmpty ? NSUserName() : NSFullUserName())
            .accessibilityHint("Opens Settings.")
            .accessibilityIdentifier("grok-sidebar-account-settings")
        }
        .background(AppTheme.Palette.sidebar)
        .navigationTitle("GrokBuild")
        .alert("Rename Session", isPresented: renameAlertPresented) {
            TextField("Session name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renamingSessionID = nil
            }
            Button("Save") {
                if let id = renamingSessionID {
                    onRenameSession(id, renameText)
                }
                renamingSessionID = nil
            }
        }
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { renamingSessionID != nil },
            set: { if !$0 { renamingSessionID = nil } }
        )
    }

    private func toggleSessionVisibility(for workspaceID: Workspace.ID) {
        if hiddenSessionWorkspaceIDs.contains(workspaceID) {
            hiddenSessionWorkspaceIDs.remove(workspaceID)
        } else {
            hiddenSessionWorkspaceIDs.insert(workspaceID)
        }
        onSessionDisclosureChanged()
    }

    private func sessionRow(_ session: SidebarSession) -> some View {
        SessionSidebarRow(
            session: session,
            isSelected: SidebarSelectionSemantics.sessionIsSelected(
                session.id,
                selectedSessionID: selectedSessionID,
                isConversationRouteActive: isConversationRouteActive
            ),
            onSelect: { onSelectSession(session.id) },
            onRename: {
                renamingSessionID = session.id
                renameText = session.title
            },
            onClose: { onCloseSession(session.id) },
            onCloseLocal: { onCloseLocalSession(session.id) }
        )
        .tag(SidebarPersistentSelection.session(session.id))
        .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 8))
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("Rename…") {
                renamingSessionID = session.id
                renameText = session.title
            }
            Button("Close Local Tab") {
                onCloseLocalSession(session.id)
            }
            Button("Delete Session", role: .destructive) {
                onCloseSession(session.id)
            }
        }
    }

    @ViewBuilder
    private func projectContextMenu(for ws: Workspace) -> some View {
        Button("New Session") {
            onNewSessionForWorkspace(ws)
        }

        if pinnedWorkspaceIDs.contains(ws.id) {
            Button("Unpin") {
                onUnpinWorkspace(ws)
            }
        } else {
            Button("Pin to Top") {
                onPinWorkspace(ws)
            }
            .disabled(pinnedWorkspaceIDs.count >= SessionLayoutStore.maxPinnedProjects)
        }

        Button("Branches & Worktrees…") {
            onSwitchBranch(ws)
        }

        Button("New Worktree…") {
            onCreateWorktree(ws)
        }

        Divider()

        Button("Remove Project", role: .destructive) {
            onRemoveWorkspace(ws)
        }
    }
}

private struct CodexRailButton: View {
    let title: String
    let systemImage: String
    let railAction: SidebarRailAction
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                    .font(AppTheme.Typography.captionStrong)
                Spacer()
            }
            .padding(.horizontal, 8)
            // Workbench W-1 (2026-08-08): denser rail, matching the target
            // photographs' compact navigation rows.
            .frame(height: 28)
            .background(isHovered ? AppTheme.Palette.surfaceHover : Color.clear,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("grok-rail-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .accessibilityRemoveTraits(
            SidebarSelectionSemantics.railActionIsSelected(railAction) ? [] : .isSelected
        )
        .onHover { isHovered = $0 }
    }
}

private struct SessionSidebarRow: View {
    let session: SidebarSession
    let isSelected: Bool
    var onSelect: () -> Void
    var onRename: () -> Void
    var onClose: () -> Void
    var onCloseLocal: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(session.isRunning ? Color.green : AppTheme.Palette.textMuted)
                        .frame(width: 6, height: 6)
                        .opacity(isSelected || session.isRunning ? 1 : 0)
                }
                .frame(width: 10)

                Text(session.title)
                    .font(isSelected ? AppTheme.Typography.captionStrong : AppTheme.Typography.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                if session.hasActiveSchedule {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.Palette.warning)
                        .help("Scheduled work is pinning this session's live runtime")
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("grok-sidebar-session-schedule")
                }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .background(
                    isSelected ? AppTheme.Palette.accentSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SessionSidebarMetadata.accessibilityLabel(for: session))
            .accessibilityIdentifier("grok-sidebar-session-row-\(session.id.uuidString)")
            .accessibilityValue(session.id.uuidString)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
            .accessibilityAction(named: "Rename session") {
                onRename()
            }
            .accessibilityAction(named: "Delete session") {
                onClose()
            }
            .accessibilityAction(named: "Close local tab") {
                onCloseLocal()
            }

            Menu {
                Button("Rename…", action: onRename)
                Button("Close Local Tab", action: onCloseLocal)
                Button("Delete Session", role: .destructive, action: onClose)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("Session actions")
            .accessibilityLabel("Session actions for \(session.title)")
            .opacity(isHovered || isSelected ? 1 : 0)
        }
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
        .help(SessionSidebarMetadata.helpText(for: session))
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace
    var isPinned: Bool = false
    var isSelected: Bool = false
    var hasSessions: Bool = false
    var areSessionsHidden: Bool = false
    var onToggleSessions: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isPinned ? "pin.fill" : "folder")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isPinned || isSelected ? Color.primary : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(workspace.displayName)
                        .font(isSelected ? AppTheme.Typography.captionStrong : AppTheme.Typography.caption)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    if hasSessions {
                        Image(systemName: areSessionsHidden ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 3)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                TapGesture().onEnded {
                                    onToggleSessions()
                                }
                            )
                            .help(areSessionsHidden ? "Show sessions" : "Hide sessions")
                    }
                }
            }
            .help(workspace.path.path)
            .accessibilityValue(workspace.path.path)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            isSelected ? AppTheme.Palette.accentSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.small)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Project \(workspace.displayName)")
        .accessibilityValue(workspace.path.path)
    }
}
