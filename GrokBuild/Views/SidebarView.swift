import SwiftUI
import AppKit

struct SidebarSession: Identifiable, Hashable {
    let id: UUID
    let workspaceID: Workspace.ID
    let title: String
    let modelName: String
    let lastAccessed: Date?
    let isRunning: Bool
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
        return "Session: \(session.title), \(session.modelName), \(state), \(activity)"
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
    @Binding var expandedSessionWorkspaceIDs: Set<Workspace.ID>
    @Binding var hiddenSessionWorkspaceIDs: Set<Workspace.ID>

    var onAddWorkspace: () -> Void
    var onSelectWorkspace: (Workspace) -> Void
    var onSelectSession: (UUID) -> Void = { _ in }
    var onNewSessionForWorkspace: (Workspace) -> Void = { _ in }
    var onRenameSession: (UUID, String) -> Void = { _, _ in }
    var onCloseSession: (UUID) -> Void = { _ in }
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
    var onOpenSettings: () -> Void

    @State private var filter = ""
    @State private var isFilterVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renamingSessionID: UUID?
    @State private var renameText = ""

    private let collapsedSessionLimit = 5

    private var filtered: [Workspace] {
        let base = filter.isEmpty ? orderedWorkspaces : orderedWorkspaces.filter {
            $0.displayName.localizedCaseInsensitiveContains(filter)
        }
        return base
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
            HStack(spacing: 6) {
                Text("GrokBuild")
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { isFilterVisible.toggle() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Filter sessions")
                .accessibilityHint(isFilterVisible ? "Hides the session filter field." : "Shows a field that filters sessions by title.")
                .accessibilityValue(isFilterVisible ? "Visible" : "Hidden")
                Button(action: onOpenActivity) {
                    Image(systemName: "bell")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Session activity")
                .accessibilityHint("Opens the session activity dashboard.")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Navigation-only rail (Codex parity Slice 1): Activity moved to the
            // header bell; Workflows lives in Settings and the composer command menu.
            VStack(spacing: 2) {
                CodexRailButton(title: "New chat", systemImage: "square.and.pencil", action: onNewChat)
                CodexRailButton(title: "Sessions", systemImage: "clock.arrow.circlepath", action: onBrowseSessions)
                CodexRailButton(title: "Plugins", systemImage: "shippingbox", action: onOpenPlugins)
                CodexRailButton(title: "Security", systemImage: "checkmark.shield", action: onOpenSecurity)
            }
            .padding(.horizontal, 8)
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

            List {
                Section {
                    ForEach(filtered) { ws in
                        Button {
                            onSelectWorkspace(ws)
                        } label: {
                            let projectSessions = sessions(for: ws.id)
                            WorkspaceRow(
                                workspace: ws,
                                isPinned: pinnedWorkspaceIDs.contains(ws.id),
                                isSelected: selectedWorkspaceID == ws.id,
                                hasSessions: !projectSessions.isEmpty,
                                areSessionsHidden: hiddenSessionWorkspaceIDs.contains(ws.id),
                                onToggleSessions: {
                                    toggleSessionVisibility(for: ws.id)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            projectContextMenu(for: ws)
                        }

                        let projectSessions = sessions(for: ws.id)
                        if (selectedWorkspaceID == ws.id || !projectSessions.isEmpty),
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

            HStack(spacing: 9) {
                Circle()
                    .fill(Color.blue.opacity(0.9))
                    .frame(width: 22, height: 22)
                    .overlay {
                        Text(String(NSFullUserName().prefix(1)).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                Text(NSFullUserName().isEmpty ? NSUserName() : NSFullUserName())
                    .font(AppTheme.Typography.captionStrong)
                    .lineLimit(1)
                Spacer()
                Button(action: onOpenSettings) {
                    Image(systemName: "questionmark.circle")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Help and settings")
                .accessibilityHint("Opens Settings.")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenSettings)
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
            isSelected: selectedSessionID == session.id,
            onSelect: { onSelectSession(session.id) },
            onRename: {
                renamingSessionID = session.id
                renameText = session.title
            },
            onClose: { onCloseSession(session.id) }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 2, trailing: 10))
        .listRowBackground(Color.clear)
        .contextMenu {
            Button("Rename…") {
                renamingSessionID = session.id
                renameText = session.title
            }
            Button("Close Session", role: .destructive) {
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
        .onHover { isHovered = $0 }
    }
}

private struct SessionSidebarRow: View {
    let session: SidebarSession
    let isSelected: Bool
    var onSelect: () -> Void
    var onRename: () -> Void
    var onClose: () -> Void
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
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(
                    isSelected ? AppTheme.Palette.accentSoft : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SessionSidebarMetadata.accessibilityLabel(for: session))
            .accessibilityIdentifier("grok-sidebar-session-row")

            Menu {
                Button("Rename…", action: onRename)
                Button("Close Session", role: .destructive, action: onClose)
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
        HStack(spacing: 10) {
            Image(systemName: isPinned ? "pin.fill" : "folder")
                .foregroundStyle(isPinned || isSelected ? Color.primary : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(workspace.displayName)
                        .font(isSelected ? .body.weight(.semibold) : .body)
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
                Text(workspace.path.path)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .secondary : .tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            isSelected ? AppTheme.Palette.accentSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.small)
        )
    }
}
