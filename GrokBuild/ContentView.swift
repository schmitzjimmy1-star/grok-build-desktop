import SwiftUI
import AppKit

struct ContentView: View {
    private enum AppRoute: Equatable {
        case session
        case settings
    }

    fileprivate struct LiveSession: Identifiable {
        let id: UUID
        let store: ChatStore
        var workspace: Workspace
        var title: String
        /// The grok session id to resume, known even before the process is started (lazy
        /// restore). Stays valid across LRU teardown so the session can be re-resumed on send.
        var grokSessionID: String?
    }

    /// Most-recently-used session ids (front = most recent). Drives the LRU cap on live
    /// `grok agent stdio` processes so steady-state memory doesn't scale with session count.
    @State private var recentSessionOrder: [UUID] = []
    /// Maximum number of sessions kept connected (with a live grok process) at once. Others
    /// are torn down and re-resumed on demand when their next prompt is submitted.
    private let maxConnectedSessions = 4

    @State private var workspaceStore = WorkspaceStore()
    @State private var placeholderStore = ChatStore()
    @State private var liveSessions: [LiveSession] = []
    @State private var selectedSessionID: UUID?
    @State private var selectedWorkspaceID: Workspace.ID?

    @State private var showPicker = false
    @State private var route: AppRoute = .session
    @State private var selectedSettingsTab: SettingsTab = .agents
    @State private var showSessions = false
    @State private var showSessionDashboard = false
    @State private var showPreview = false
    @State private var gitCheckoutRequest: GitCheckoutRequest?
    @State private var gitError: String?
    @State private var projectChangedDiffs: [ChatStore.DetectedDiff] = []
    @State private var boundedGitRefreshTask: Task<Void, Never>?
    @State private var didBootstrap = false
    @State private var isRestoringSessions = false
    @State private var restoredSessionCount = 0
    @State private var totalSessionsToRestore = 0
    @State private var restoreStatusText = "Restoring sessions..."
    @State private var sessionListRevision = 0
    /// Rejects stale asynchronous transcript hydration after rapid A → B → A switching.
    @State private var sessionSelectionGeneration: UInt64 = 0
    @State private var cachedSessionTitles: [UUID: String] = [:]
    /// Metadata is loaded in one background snapshot during restore. Keeping it in memory lets
    /// layout persistence answer counts/generations without touching transcript files on the
    /// main actor or decoding any unselected body.
    @State private var transcriptMetadataByID: [UUID: SessionMessageStore.Metadata] = [:]
    /// FIFO chain for asynchronous transcript writes; each link awaits its predecessor
    /// so metadata merges and layout stamps can never complete out of submission order.
    @State private var transcriptPersistChain: Task<Void, Never>?
    @State private var sessionLayout = SessionLayoutSnapshot(
        records: [],
        sessionOrderByWorkspace: [:],
        selectedSessionID: nil,
        selectedWorkspaceID: nil
    )
    @State private var sessionLayoutAuthority: SessionLayoutAuthority = .empty
    @State private var sessionLayoutFailure: SessionLayoutFailureCode?
    /// Only prompt-boundary, reconciliation, recovery, close, and quit paths may make a
    /// transcript dirty. Selecting a tab writes layout metadata, never every transcript body.
    @State private var dirtyTranscriptIDs: Set<UUID> = []
    @State private var pendingActivationDates: [UUID: Date] = [:]
    @State private var pendingActivationOrdinals: [UUID: UInt64] = [:]
    @State private var isUpgradeBannerDismissed = false
    @State private var showUpgradeBanner = false
    @State private var bannerAppVersion: String?
    @State private var bannerCLIVersion: String?
    @AppStorage(SidebarVisibility.storageKey)
    private var isSidebarVisible = SidebarVisibility.defaultVisible

    private var gitErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { gitError != nil },
            set: { isPresented in
                if !isPresented { gitError = nil }
            }
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
            if sessionLayoutFailure != nil {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Saved session migration failed. Legacy sessions are open read-only.")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.10))
                .accessibilityElement(children: .combine)
            }
            if showUpgradeBanner {
                UpdatesBanner(
                    appVersion: bannerAppVersion,
                    cliVersion: bannerCLIVersion,
                    onAction: {
                        Task {
                            await UpdateUI.presentUpdatePanel(refresh: false) {
                                refreshUpgradeBannerState()
                            }
                        }
                    },
                    onDismiss: {
                        isUpgradeBannerDismissed = true
                        refreshUpgradeBannerState()
                    }
                )
            }

            HSplitView {
            if SidebarVisibility.shouldShow(preference: isSidebarVisible, settingsPresented: route == .settings) {
            SidebarView(
                workspaces: $workspaceStore.workspaces,
                orderedWorkspaces: workspaceStore.orderedWorkspaces,
                pinnedWorkspaceIDs: workspaceStore.pinnedWorkspaceIDs,
                selectedWorkspaceID: $selectedWorkspaceID,
                sessions: sidebarSessions,
                hiddenSessionCounts: hiddenSessionCounts,
                selectedSessionID: selectedSessionID,
                activityLane: sidebarActivityLane,
                agentEntries: agentHubEntries,
                connections: activeStore.promptMCPOptions,
                attachedConnectionNames: activeStore.selectedPromptMCPNames,
                expandedSessionWorkspaceIDs: $sessionLayout.expandedSessionWorkspaceIDs,
                hiddenSessionWorkspaceIDs: $sessionLayout.hiddenSessionWorkspaceIDs,
                onAddWorkspace: { showPicker = true },
                onSelectWorkspace: { ws in
                    route = .session
                    selectProject(ws)
                },
                onSelectSession: { selectSession($0) },
                onSelectActivity: { entry in
                    route = .session
                    selectSession(entry.sessionID)
                },
                onStartSessionAsAgent: { entry in
                    route = .session
                    let workspace = workspaceStore.workspaces.first(where: { $0.id == selectedWorkspaceID })
                        ?? workspaceStore.orderedWorkspaces.first
                    guard let workspace else {
                        showPicker = true
                        return
                    }
                    let agent = entry.agentSelection.isEmpty ? nil : entry.agentSelection
                    Task { await createLiveSession(for: workspace, agent: agent) }
                },
                onOpenAgentSettings: { openSettings(tab: .agents) },
                onToggleConnection: { name in
                    activeStore.togglePromptMCPAttachment(named: name)
                },
                onManageConnections: { openSettings(tab: .mcpServers) },
                onNewSessionForWorkspace: { workspace in
                    Task { await createLiveSession(for: workspace) }
                },
                onRenameSession: { id, name in
                    renameSession(id: id, to: name)
                },
                onCloseSession: { id in
                    closeSession(id: id)
                },
                onMoveWorkspace: { source, destination in
                    workspaceStore.moveWorkspaces(from: source, to: destination)
                },
                onPinWorkspace: { workspaceStore.pin($0) },
                onUnpinWorkspace: { workspaceStore.unpin($0) },
                onRemoveWorkspace: { removeWorkspace($0) },
                onMoveSession: { workspaceID, source, destination in
                    moveSessions(for: workspaceID, from: source, to: destination)
                },
                onSwitchBranch: { gitCheckoutRequest = GitCheckoutRequest(project: $0) },
                onCreateWorktree: { gitCheckoutRequest = GitCheckoutRequest(project: $0, focusCreateWorktree: true) },
                onSessionDisclosureChanged: { persistSessionLayout() },
                onOpenSettings: { openSettings(tab: selectedSettingsTab) }
            )
            .frame(minWidth: 220, idealWidth: 244, maxWidth: 280)
            }

            if route == .settings {
                SettingsView(
                    store: activeStore,
                    selectedTab: $selectedSettingsTab,
                    onBackToChat: { route = .session },
                    onConfigurationChanged: handleConfigurationChange,
                    onSettingsApplyRequest: handleConfigurationChange
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    ChatView(
                        store: activeStore,
                        isSidebarVisible: isSidebarVisible,
                        onToggleSidebar: { isSidebarVisible.toggle() },
                        onOpenSettings: { openSettings(tab: selectedSettingsTab) },
                        reviewFileCount: activeReviewDiffs.count,
                        reviewFileNames: activeReviewDiffs.compactMap(\.filePath),
                        isReviewVisible: showPreview,
                        onToggleReview: {
                            if !activeReviewDiffs.isEmpty {
                                showPreview.toggle()
                            }
                        },
                        onSelectSession: { selectSession($0) },
                        onBrowseSessions: { showSessions = true },
                        onNewSession: { startNewSessionForCurrentProject() },
                        onAddProject: { showPicker = true },
                        onOpenProjectIn: { openCurrentProject(in: $0) },
                        onToggleBrowserTools: { toggleBrowserToolsFromChat() },
                        onSelectBrowserRuntime: { selectBrowserRuntimeFromChat($0) },
                        onToggleComputerUse: { toggleComputerUseFromChat() },
                        onOpenBrowserSettings: { openSettings(tab: .browser) },
                        onOpenComputerUseSettings: { openSettings(tab: .computerUse) },
                        onOpenAgentSettings: { openSettings(tab: .agents) },
                        onOpenMemorySettings: { openSettings(tab: .memory) },
                        onOpenWorkflowSettings: { openSettings(tab: .workflows) },
                        onForkSession: { Task { await forkCurrentSession() } },
                        onOpenDashboard: { showSessionDashboard = true },
                        onSwitchBranch: {
                            if let workspace = currentWorkspace {
                                gitCheckoutRequest = GitCheckoutRequest(project: workspace)
                            }
                        },
                        onRevealArtifact: revealArtifact
                    )
                    .id(activeStore.tabSessionID)
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                    if showPreview {
                        PreviewPane(
                            diffs: activeReviewDiffs,
                            workspace: currentWorkspace,
                            onClose: { showPreview = false }
                        )
                        .frame(minWidth: 360, idealWidth: 460, maxWidth: 620, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            }
            .disabled(isRestoringSessions)
            }

            if isRestoringSessions {
                sessionRestoreOverlay
            }
        }
        .background(AppTheme.Palette.canvas)
        .tint(AppTheme.Palette.accent)
        .onAppear(perform: bootstrap)
        .onAppear { refreshUpgradeBannerState() }
        .onAppear { refreshSessionTitles() }
        .onChange(of: sessionListRevision) { _, _ in
            refreshSessionTitles()
        }
        .onChange(of: activeStore.gitRefreshRevision) { _, _ in
            scheduleBoundedGitRefresh(for: activeStore)
        }
        .onReceive(NotificationCenter.default.publisher(for: .grokBuildUpdateAvailable)) { _ in
            isUpgradeBannerDismissed = false
            refreshUpgradeBannerState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .grokBuildUpdateStateChanged)) { _ in
            refreshUpgradeBannerState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarRequested)) { _ in
            isSidebarVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .subagentRolesChanged)) { _ in
            refreshAgentHubRoles()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            flushTranscriptsForTermination()
        }
        .onChange(of: selectedWorkspaceID) { _, _ in
            // Discovered agents and MCP connections are per-workspace; both store
            // guards make repeats cheap, and neither call writes any configuration.
            Task {
                await activeStore.loadDiscoveredAgentsIfNeeded()
                await activeStore.refreshPromptMCPOptions()
            }
        }
        .sheet(isPresented: $showPicker) {
            WorkspacePicker(initialDirectory: currentWorkspace?.path) { url in
                addWorkspace(url: url)
            }
        }
        .sheet(isPresented: $showSessions) {
            SessionBrowserView(
                workspaces: currentWorkspace.map { [$0] } ?? [],
                highlightedWorkspaceID: selectedWorkspaceID,
                liveSessionsByGrokID: liveSessionsByGrokID,
                selectedGrokSessionID: activeStore.grokSessionId,
                onResume: { showSessions = false },
                onResumeSession: { session, workspace in
                    Task { await createLiveSession(for: workspace, resumeSession: session) }
                },
                onSelectLive: { selectSession($0) }
            )
        }
        .sheet(isPresented: $showSessionDashboard) {
            SessionDashboardPanel(
                entries: dashboardEntries,
                selectedSessionID: selectedSessionID
            ) { sessionID in
                showSessionDashboard = false
                selectSession(sessionID)
            }
        }
        .sheet(item: $gitCheckoutRequest) { request in
            GitCheckoutSheet(
                project: request.project,
                focusCreateWorktree: request.focusCreateWorktree,
                onSwitchBranch: { branch in
                    Task { await switchBranch(project: request.project, branch: branch) }
                },
                onOpenWorktree: { worktree in
                    Task { await openWorktree(worktree, from: request.project) }
                },
                onCreateBranch: { branch in
                    Task { await createAndSwitchBranch(project: request.project, branch: branch) }
                },
                onCreateWorktree: { branch, path in
                    Task { await createWorktree(project: request.project, branch: branch, path: path) }
                }
            )
        }
        .alert("Git action failed", isPresented: gitErrorAlertPresented) {
            Button("OK", role: .cancel) { gitError = nil }
        } message: {
            if let gitError {
                Text(gitError)
            }
        }
        .modifier(ContentViewNotificationHandlers(
            activeStore: activeStore,
            liveSessions: liveSessions,
            sessionListRevision: $sessionListRevision,
            selectedWorkspaceID: $selectedWorkspaceID,
            showPicker: $showPicker,
            showSessions: $showSessions,
            onWorkspaceChange: handleWorkspaceChange,
            onRefreshGitReview: refreshGitReviewFromTranscriptBoundary,
            onNewSession: startNewSessionForCurrentProject,
            onPersistSessionLayout: { persistSessionLayout(saveMessages: $0) },
            onTranscriptBoundary: markTranscriptDirtyAndPersist,
            onSessionStarted: { Task { await enforceConnectionCap() } },
            openSettings: { tab in openSettings(tab: tab ?? selectedSettingsTab) }
        ))
    }

    // MARK: - Subviews

    private var sessionRestoreOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)

            VStack(spacing: 5) {
                Text("Restoring Sessions")
                    .font(.headline)
                Text(restoreStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if totalSessionsToRestore > 0 {
                ProgressView(value: Double(restoredSessionCount), total: Double(totalSessionsToRestore))
                    .frame(width: 220)
                Text("\(restoredSessionCount) of \(totalSessionsToRestore)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.overlay))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.overlay)
                .stroke(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }

    private var activeSession: LiveSession? {
        guard let selectedSessionID else { return nil }
        return liveSessions.first { $0.id == selectedSessionID }
    }

    private var activeStore: ChatStore {
        activeSession?.store ?? placeholderStore
    }

    private var currentWorkspace: Workspace? {
        activeSession?.workspace ?? selectedWorkspaceID.flatMap { id in
            workspaceStore.workspaces.first(where: { $0.id == id })
        }
    }

    private var activeReviewDiffs: [ChatStore.DetectedDiff] {
        projectChangedDiffs
    }

    private func openSettings(tab: SettingsTab) {
        selectedSettingsTab = tab
        route = .settings
    }

    private func handleConfigurationChange(_ change: ConfigurationChange) {
        let stores = liveSessions.map(\.store) + [placeholderStore]
        Task {
            for store in stores {
                await store.applyConfigurationChange(change)
            }
        }
    }

    private func handleConfigurationChange(
        _ request: SettingsApplyRequest
    ) async -> SettingsApplyReceipt {
        switch request.applyScope {
        case .externalConfigOnly, .futureSessions:
            return .completed(
                request: request,
                status: .success,
                summary: "Saved for future eligible sessions."
            )

        case .activeTabRestart:
            let store = activeStore
            return await store.applySettingsRequest(
                request.bound(to: store.settingsApplyTarget)
            )

        case .allEligibleLiveTabs:
            let stores = liveSessions.map(\.store).filter {
                $0.settingsApplyTarget.processGeneration != nil
            }
            guard !stores.isEmpty else {
                return .completed(
                    request: request,
                    status: .success,
                    summary: "Saved; no live tabs require a restart."
                )
            }
            var receipts: [SettingsApplyReceipt] = []
            for store in stores {
                receipts.append(await store.applySettingsRequest(
                    request.bound(to: store.settingsApplyTarget)
                ))
            }
            let status: SettingsApplyReceiptStatus
            if receipts.allSatisfy({ $0.status == .success }) {
                status = .success
            } else if receipts.allSatisfy({ $0.status == .failure }) {
                status = .failure
            } else {
                status = .partial
            }
            return .completed(
                request: request,
                status: status,
                summary: "Applied to \(receipts.filter { $0.status == .success }.count) of \(receipts.count) eligible live tabs.",
                effectiveSession: receipts.first(where: {
                    $0.effectiveSession?.localTabID == selectedSessionID
                })?.effectiveSession
            )
        }
    }

    /// Agents hub roles snapshot, loaded off the main actor at bootstrap and whenever
    /// Settings saves roles (`.subagentRolesChanged`).
    @State private var agentHubRoles: [SubagentRole] = []

    /// Agents hub entries: grok's default + custom roles + the active store's discovered
    /// agents. Reading `discoveredAgents` here registers observation, so late discovery
    /// updates the hub without extra plumbing.
    private var agentHubEntries: [AgentHubEntry] {
        AgentHubProjection.entries(
            discovered: activeStore.discoveredAgents,
            roles: agentHubRoles,
            defaultSelection: UserDefaults.standard.string(forKey: GrokSettingsKeys.selectedAgent) ?? ""
        )
    }

    private func refreshAgentHubRoles() {
        Task {
            let roles = await GrokBuildBackgroundWork.run({ SubagentRoleStore.load() }, priority: .utility)
            agentHubRoles = roles
            await activeStore.loadDiscoveredAgentsIfNeeded()
            await activeStore.refreshPromptMCPOptions()
        }
    }

    /// Sidebar Activity lane: a pure projection over every live session's already-observed
    /// agentic mirrors. Reading the `@Observable` store fields here registers observation,
    /// so the lane updates live without any polling or notification plumbing.
    private var sidebarActivityLane: SidebarActivityLane {
        _ = sessionListRevision
        return SidebarActivityProjection.lane(from: liveSessions.map { session in
            SidebarActivityProjection.SessionInput(
                sessionID: session.id,
                sessionTitle: sessionTitle(for: session),
                backgroundActivities: session.store.backgroundActivities,
                scheduledTasks: session.store.scheduledTasks,
                workflowRuns: session.store.workflowRuns
            )
        })
    }

    private var dashboardEntries: [SessionDashboardEntry] {
        _ = sessionListRevision
        return liveSessions.map { session in
            let store = session.store
            let pending = store.pendingPermissions.count
                + store.pendingQuestions.count
                + (store.pendingExitPlan == nil ? 0 : 1)
            let group: SessionDashboardEntry.Group
            switch store.connectionState {
            case .failed:
                group = .failed
            case .busy:
                group = store.isStreaming || pending > 0 ? (pending > 0 ? .needsInput : .working) : .working
            case .ready:
                group = pending > 0 ? .needsInput : .idle
            case .starting:
                group = .working
            case .idle:
                group = .idle
            }
            if pending > 0 { return SessionDashboardEntry(
                id: session.id,
                title: sessionTitle(for: session),
                workspaceName: session.workspace.displayName,
                group: .needsInput,
                modelName: store.modelDisplayName(store.currentModel),
                pendingCount: pending,
                lastActivationOrdinal: sessionLayout.records.first(where: { $0.id == session.id })?
                    .lastActivationOrdinal ?? 0
            ) }
            return SessionDashboardEntry(
                id: session.id,
                title: sessionTitle(for: session),
                workspaceName: session.workspace.displayName,
                group: group,
                modelName: store.modelDisplayName(store.currentModel),
                pendingCount: pending,
                lastActivationOrdinal: sessionLayout.records.first(where: { $0.id == session.id })?
                    .lastActivationOrdinal ?? 0
            )
        }
    }

    private func forkCurrentSession() async {
        guard let source = activeSession,
              let grokID = source.store.grokSessionId ?? source.grokSessionID else { return }
        purgeEmptySessions(in: source.workspace.id)
        let id = UUID()
        let store = ChatStore()
        let title = "Fork of \(computeSessionTitle(for: source))"
        liveSessions.append(
            LiveSession(id: id, store: store, workspace: source.workspace, title: title, grokSessionID: nil)
        )
        selectedSessionID = id
        selectedWorkspaceID = source.workspace.id
        noteSessionUsed(id)
        sessionListRevision &+= 1
        persistSessionLayout()
        store.bindTabSession(
            id,
            savedModel: source.store.currentModel,
            savedAgent: source.store.persistedAgentSelection
        )
        await store.startForked(workspace: source.workspace, fromSessionID: grokID)
        await enforceConnectionCap()
    }

    private func toggleBrowserToolsFromChat() {
        var settings = BrowserSettingsStore.load()
        guard AgentBrowserService.browserToolsConfigurationIssue(settings: settings) == nil else {
            openSettings(tab: .browser)
            return
        }

        settings.enabled.toggle()
        BrowserSettingsStore.save(settings)
        BrowserSettingsStore.saveApplied(settings)

        Task {
            await activeStore.reloadConfiguration()
        }
    }

    private func selectBrowserRuntimeFromChat(_ runtimeMode: BrowserRuntimeMode) {
        var settings = BrowserSettingsStore.load()
        guard AgentBrowserService.browserRuntimeConfigurationIssue(settings: settings, mode: runtimeMode) == nil else {
            return
        }
        guard settings.runtimeMode != runtimeMode else { return }

        settings.runtimeMode = runtimeMode
        BrowserSettingsStore.save(settings)
        BrowserSettingsStore.saveApplied(settings)

        guard settings.enabled else { return }
        Task {
            await activeStore.reloadConfiguration()
        }
    }

    private func toggleComputerUseFromChat() {
        let settings = ComputerUseSettingsStore.load()
        Task {
            let result = await ComputerUseService.applyEnabled(!settings.enabled) {
                await activeStore.reloadConfiguration()
            }
            if case .needsSetup = result {
                openSettings(tab: .computerUse)
            }
        }
    }

    private var liveSessionsByGrokID: [String: UUID] {
        Dictionary(
            uniqueKeysWithValues: liveSessions.compactMap { session in
                guard let grokID = session.store.grokSessionId else { return nil }
                return (grokID, session.id)
            }
        )
    }

    /// Cached title for use inside `body`. Reading `store.messages` (which
    /// `computeSessionTitle` does) from body subscribes ContentView to every
    /// streamed chunk of every session; the cache confines that read to
    /// `refreshSessionTitles()`, which runs on `sessionListRevision` bumps —
    /// the boundaries where titles can actually change.
    private func sessionTitle(for session: LiveSession) -> String {
        cachedSessionTitles[session.id] ?? session.title
    }

    private func refreshSessionTitles() {
        cachedSessionTitles = Dictionary(
            uniqueKeysWithValues: liveSessions.map { ($0.id, computeSessionTitle(for: $0)) }
        )
    }

    /// Fresh computation for event paths (fork, layout persist) that may run
    /// in the same event turn as a revision bump, before the cache refreshes.
    private func computeSessionTitle(for session: LiveSession) -> String {
        let liveKey = session.id.uuidString
        if let custom = SessionNameStore.name(for: liveKey) {
            return custom
        }
        if let grokId = session.store.grokSessionId,
           let custom = SessionNameStore.name(for: grokId) {
            return custom
        }
        if let auto = SessionTitle.auto(from: session.store.messages) {
            return auto
        }
        if let saved = sessionLayout.records.first(where: { $0.id == session.id })?.title,
           !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return saved
        }
        return session.title
    }

    private func renameSession(id: UUID, to name: String) {
        SessionNameStore.setName(name, for: id.uuidString)
        if let grokId = liveSessions.first(where: { $0.id == id })?.store.grokSessionId {
            SessionNameStore.setName(name, for: grokId)
        }
        sessionListRevision &+= 1
        persistSessionLayout()
    }

    private func closeSession(id: UUID) {
        guard let index = liveSessions.firstIndex(where: { $0.id == id }) else { return }
        let closing = liveSessions[index]
        let store = closing.store
        liveSessions.remove(at: index)

        if selectedSessionID == id {
            if let sibling = liveSessions.last(where: { $0.workspace.id == closing.workspace.id }) {
                selectSession(sibling.id)
            } else if let any = liveSessions.last {
                selectSession(any.id)
            } else {
                selectedSessionID = nil
            }
        }
        sessionListRevision &+= 1
        persistSessionLayout()
        SessionMessageStore.remove(for: id)
        Task {
            await store.shutdownPermanently()
        }
    }

    private func sessionHasPersistedContent(_ sessionID: UUID) -> Bool {
        if let metadata = transcriptMetadataByID[sessionID] {
            return metadata.restorableMessageCount > 0
        }
        return SessionRestorePolicy.sessionHasPersistedContent(sessionID)
    }

    private func sessionHasContent(_ session: LiveSession) -> Bool {
        SessionRestorePolicy.sessionHasContent(
            hasUserMessages: session.store.hasUserMessages,
            liveGrokSessionID: session.store.grokSessionId,
            savedGrokSessionID: session.grokSessionID,
            sessionID: session.id,
            hasPersistedContent: transcriptMetadataByID[session.id].map {
                $0.restorableMessageCount > 0
            }
        )
    }

    private func isSessionEmpty(_ session: LiveSession) -> Bool {
        !sessionHasContent(session)
    }

    private func preferredSessionID(for workspace: Workspace, saved: SessionLayoutSnapshot? = nil) -> UUID? {
        let snapshot = saved ?? sessionLayout
        let idsInWorkspace = liveSessions(for: workspace.id).map(\.id)
        return SessionRestorePolicy.preferredSessionID(
            for: workspace.id,
            saved: snapshot,
            liveSessionIDsInWorkspace: idsInWorkspace,
            currentSelectedSessionID: selectedSessionID,
            currentSelectedWorkspaceID: selectedWorkspaceID,
            recentSessionOrder: recentSessionOrder,
            hasContent: { id in
                if let session = liveSessions.first(where: { $0.id == id }) {
                    return sessionHasContent(session)
                }
                return sessionHasPersistedContent(id)
            }
        )
    }

    private func purgeEmptySessions(in workspaceID: Workspace.ID? = nil, keeping id: UUID? = nil) {
        let staleIDs = liveSessions
            .filter { session in
                session.id != id
                    && isSessionEmpty(session)
                    && (workspaceID == nil || session.workspace.id == workspaceID)
            }
            .map(\.id)
        for staleID in staleIDs {
            closeSession(id: staleID)
        }
    }

    private func liveSessions(for workspaceID: Workspace.ID) -> [LiveSession] {
        liveSessions.filter { $0.workspace.id == workspaceID }
    }

    private var hiddenSessionCounts: [Workspace.ID: Int] {
        _ = sessionListRevision
        var counts: [Workspace.ID: Int] = [:]
        for workspace in workspaceStore.workspaces {
            let total = liveSessions(for: workspace.id).count
            counts[workspace.id] = max(0, total - SessionLayoutStore.maxSidebarSessions)
        }
        return counts
    }

    private var sidebarSessions: [SidebarSession] {
        _ = sessionListRevision
        var result: [SidebarSession] = []
        for workspace in workspaceStore.workspaces {
            let visibleIDs = visibleSessionIDs(for: workspace.id)
            for session in liveSessions where visibleIDs.contains(session.id) {
                let savedRecord = sessionLayout.records.first { $0.id == session.id }
                result.append(
                    SidebarSession(
                        id: session.id,
                        workspaceID: session.workspace.id,
                        title: sessionTitle(for: session),
                        modelName: session.store.modelDisplayName(session.store.currentModel),
                        lastAccessed: savedRecord?.lastAccessed,
                        isRunning: session.store.connectionState == .busy
                            || session.store.connectionState == .starting
                            || session.store.isStreaming
                    )
                )
            }
        }
        return result
    }

    private func visibleSessionIDs(for workspaceID: Workspace.ID) -> [UUID] {
        let eligible = liveSessions(for: workspaceID)
        var order = sessionLayout.sessionOrderByWorkspace[workspaceID] ?? eligible.map(\.id)
        order.removeAll { id in !eligible.contains { $0.id == id } }
        for session in eligible where !order.contains(session.id) {
            order.append(session.id)
        }
        if order.count > SessionLayoutStore.maxSidebarSessions {
            let selected = selectedSessionID
            var trimmed = Array(order.prefix(SessionLayoutStore.maxSidebarSessions))
            if let selected, eligible.contains(where: { $0.id == selected }), !trimmed.contains(selected) {
                trimmed[SessionLayoutStore.maxSidebarSessions - 1] = selected
            }
            order = trimmed
        }
        return order
    }

    private func moveSessions(for workspaceID: UUID, from source: IndexSet, to destination: Int) {
        let order = visibleSessionIDs(for: workspaceID)
        let allForWorkspace = liveSessions.filter { $0.workspace.id == workspaceID }.map(\.id)
        var fullOrder = sessionLayout.sessionOrderByWorkspace[workspaceID] ?? allForWorkspace
        fullOrder.removeAll { id in !allForWorkspace.contains(id) }
        for id in allForWorkspace where !fullOrder.contains(id) {
            fullOrder.append(id)
        }

        let visible = order
        var movedVisible = visible
        movedVisible.move(fromOffsets: source, toOffset: destination)

        var newFull = fullOrder
        let visibleSet = Set(visible)
        var visibleIndex = 0
        for idx in newFull.indices {
            if visibleSet.contains(newFull[idx]) {
                newFull[idx] = movedVisible[visibleIndex]
                visibleIndex += 1
            }
        }

        sessionLayout.sessionOrderByWorkspace[workspaceID] = newFull
        persistSessionLayout()
        sessionListRevision &+= 1
    }

    private func persistSessionLayout(saveMessages: Bool = false) {
        guard sessionLayoutAuthority != .legacyV2Fallback,
              sessionLayoutFailure == nil else { return }
        guard saveMessages, !dirtyTranscriptIDs.isEmpty else {
            encodeAndSaveSessionLayout(recordFlushReceipt: saveMessages)
            return
        }
        // The dirty snapshot is taken at the prompt boundary on the main actor, but the
        // file write (read envelope + merge + full JSON re-encode) moves off it — the
        // old synchronous `storageQueue.sync` stalled the UI exactly when a long answer
        // settled. Ordering is preserved two ways: writes chain FIFO behind the previous
        // task, and the layout re-encode (which stamps transcript generations) runs only
        // after its transcript write completes, so a stamp can never precede its file.
        let dirtyIDs = dirtyTranscriptIDs
        let dirtyMessages = Dictionary(uniqueKeysWithValues: liveSessions.compactMap { session in
            dirtyIDs.contains(session.id) ? (session.id, session.store.messages) : nil
        })
        let previous = transcriptPersistChain
        transcriptPersistChain = Task { @MainActor in
            await previous?.value
            let saved = await GrokBuildBackgroundWork.run({
                SessionMessageStore.saveAll(dirtyMessages)
            }, priority: .utility)
            transcriptMetadataByID.merge(saved) { _, new in new }
            dirtyTranscriptIDs.subtract(saved.keys)
            encodeAndSaveSessionLayout(recordFlushReceipt: true)
        }
    }

    /// Final synchronous flush at app termination. The async chain covers normal
    /// operation; quitting inside the small in-flight window must not lose the last
    /// turn, so any still-dirty transcript is written before the process exits.
    private func flushTranscriptsForTermination() {
        guard sessionLayoutAuthority != .legacyV2Fallback,
              sessionLayoutFailure == nil,
              !dirtyTranscriptIDs.isEmpty else { return }
        let dirtyIDs = dirtyTranscriptIDs
        let dirtyMessages = Dictionary(uniqueKeysWithValues: liveSessions.compactMap { session in
            dirtyIDs.contains(session.id) ? (session.id, session.store.messages) : nil
        })
        let saved = SessionMessageStore.saveAll(dirtyMessages)
        transcriptMetadataByID.merge(saved) { _, new in new }
        dirtyTranscriptIDs.subtract(saved.keys)
        encodeAndSaveSessionLayout(recordFlushReceipt: true)
    }

    private func encodeAndSaveSessionLayout(recordFlushReceipt: Bool) {
        guard sessionLayoutAuthority != .legacyV2Fallback,
              sessionLayoutFailure == nil else { return }
        var records: [SavedSessionRecord] = []
        var forkLedger = sessionLayout.forkLedger
        for session in liveSessions {
            // Prefer the live process id, but fall back to the known/saved id so lazily-restored
            // (not-yet-started) and LRU-evicted sessions are still persisted and resumable.
            let grokSessionID = session.store.persistedPendingRecoveryIntent == nil
                ? (session.store.durableGrokSessionID ?? session.grokSessionID)
                : nil
            guard sessionHasContent(session) else { continue }
            let existing = sessionLayout.records.first { $0.id == session.id }
            for entry in session.store.pendingForkLedgerEntries
                where !forkLedger.contains(where: { $0.id == entry.id }) {
                forkLedger.append(entry)
            }
            let latestForkEntry = forkLedger
                .filter { $0.localSessionID == session.id }
                .max { $0.createdAt < $1.createdAt }
            let backendBinding: SessionBackendBinding? = {
                guard let grokSessionID else {
                    return session.store.persistedPendingRecoveryIntent == nil
                        ? existing?.backendBinding
                        : nil
                }
                let receipt = session.store.persistedContinuityReceipt
                let verification: SessionBackendBindingVerification = {
                    switch receipt?.status {
                    case .verified, .backendOnly, .recoveryForked:
                        return .verified
                    case .diverged, .compositeSuspected, .backendMissing:
                        return .failed
                    case .localOnly, .backendBound, .verifying, .verificationIncomplete, nil:
                        return .unverified
                    }
                }()
                if existing?.backendBinding?.backendID == grokSessionID {
                    var binding = existing?.backendBinding
                    binding?.verification = verification
                    if let receipt { binding?.continuityReceipt = receipt }
                    return binding
                }
                let matchingFork = latestForkEntry?.successorBackendID == grokSessionID
                    ? latestForkEntry
                    : nil
                return SessionBackendBinding(
                    backendID: grokSessionID,
                    origin: matchingFork == nil ? .runtime : .recoveryFork,
                    predecessorBackendID: matchingFork?.predecessorBackendID
                        ?? existing?.backendBinding?.backendID,
                    verification: verification,
                    continuityReceipt: receipt
                )
            }()
            records.append(
                SavedSessionRecord(
                    id: session.id,
                    workspaceID: session.workspace.id,
                    backendBinding: backendBinding,
                    title: computeSessionTitle(for: session),
                    modelIntent: session.store.persistedModelIntent,
                    modelExecutionState: session.store.persistedModelExecutionState,
                    agentIntent: session.store.persistedAgentIntent,
                    lastAccessed: pendingActivationDates[session.id]
                        ?? existing?.lastAccessed
                        ?? .distantPast,
                    lastActivationOrdinal: pendingActivationOrdinals[session.id]
                        ?? existing?.lastActivationOrdinal
                        ?? 0,
                    transcriptGeneration: transcriptMetadataByID[session.id]?.generation
                        ?? existing?.transcriptGeneration
                        ?? 0,
                    transcriptStorageVersion: transcriptMetadataByID[session.id]?.storageVersion
                        ?? existing?.transcriptStorageVersion
                        ?? 1,
                    forkLedgerReference: latestForkEntry?.id.uuidString
                        ?? existing?.forkLedgerReference,
                    pendingRecoveryIntent: session.store.persistedPendingRecoveryIntent
                )
            )
        }

        var order = sessionLayout.sessionOrderByWorkspace
        var selectedByWorkspace = sessionLayout.selectedSessionIDByWorkspace
        let workspaceIDs = Set(workspaceStore.workspaces.map(\.id))
        let expandedSessionWorkspaceIDs = sessionLayout.expandedSessionWorkspaceIDs.intersection(workspaceIDs)
        let hiddenSessionWorkspaceIDs = sessionLayout.hiddenSessionWorkspaceIDs.intersection(workspaceIDs)
        let recordIDs = Set(records.map(\.id))
        for workspace in workspaceStore.workspaces {
            let ids = liveSessions(for: workspace.id).map(\.id)
            var workspaceOrder = order[workspace.id] ?? ids
            workspaceOrder.removeAll { id in !ids.contains(id) }
            for id in ids where !workspaceOrder.contains(id) {
                workspaceOrder.append(id)
            }
            order[workspace.id] = workspaceOrder
            if let selectedByWorkspaceID = selectedByWorkspace[workspace.id],
               !ids.contains(selectedByWorkspaceID) {
                selectedByWorkspace[workspace.id] = nil
            }
        }

        if let selectedSessionID,
           let selectedSession = liveSessions.first(where: { $0.id == selectedSessionID }),
           recordIDs.contains(selectedSessionID) {
            selectedByWorkspace[selectedSession.workspace.id] = selectedSessionID
        }

        sessionLayout = SessionLayoutSnapshot(
            records: records,
            sessionOrderByWorkspace: order,
            selectedSessionID: selectedSessionID,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedSessionIDByWorkspace: selectedByWorkspace,
            expandedSessionWorkspaceIDs: expandedSessionWorkspaceIDs,
            hiddenSessionWorkspaceIDs: hiddenSessionWorkspaceIDs,
            activationCounter: sessionLayout.activationCounter,
            forkLedger: forkLedger
        )
        recentSessionOrder = SessionRestorePolicy.recentSessionOrder(from: records)
        let layoutReceipt = SessionLayoutStore.saveSessions(sessionLayout)
        if recordFlushReceipt {
            _ = SessionLayoutStore.recordFlushReceipt(
                layoutReceipt: layoutReceipt,
                transcriptCount: SessionMessageStore.storedTranscriptCount
            )
        }
        if layoutReceipt.committed {
            sessionLayoutAuthority = .v3Committed
            sessionLayoutFailure = nil
            pendingActivationDates = pendingActivationDates.filter { !recordIDs.contains($0.key) }
            pendingActivationOrdinals = pendingActivationOrdinals.filter { !recordIDs.contains($0.key) }
        }
    }

    private func markTranscriptDirtyAndPersist(_ sessionID: UUID) {
        dirtyTranscriptIDs.insert(sessionID)
        persistSessionLayout(saveMessages: true)
    }

    // MARK: - Logic

    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        isRestoringSessions = true
        restoreStatusText = "Loading saved sessions..."
        Task {
            let loaded = await GrokBuildBackgroundWork.run({
                _ = SessionMessageStore.migrateLegacyIfNeeded()
                return SessionLayoutStore.loadSessionsResult()
            })
            sessionLayout = loaded.snapshot
            sessionLayoutAuthority = loaded.authority
            sessionLayoutFailure = loaded.failure
            await restorePersistedSessions()
            isRestoringSessions = false
            refreshAgentHubRoles()
        }
    }

    private func restorePersistedSessions() async {
        let saved = sessionLayout
        guard !saved.records.isEmpty else {
            if workspaceStore.workspaces.isEmpty {
                selectedWorkspaceID = nil
                selectedSessionID = nil
                placeholderStore.clearProject()
            } else if let wsID = saved.selectedWorkspaceID,
                      let workspace = workspaceStore.workspaces.first(where: { $0.id == wsID }) {
                selectProject(workspace)
            }
            return
        }

        let restorableRecords = saved.records.filter { record in
            workspaceStore.workspaces.contains { $0.id == record.workspaceID }
        }
        guard !restorableRecords.isEmpty else { return }

        totalSessionsToRestore = restorableRecords.count
        restoredSessionCount = 0
        restoreStatusText = "Preparing saved sessions..."
        isRestoringSessions = true
        defer {
            isRestoringSessions = false
            restoreStatusText = "Restoring sessions..."
        }

        let restoreMetadata = await GrokBuildBackgroundWork.run({
            Dictionary(uniqueKeysWithValues: restorableRecords.compactMap { record in
                SessionMessageStore.metadata(for: record.id).map { (record.id, $0) }
            })
        }, priority: .utility)
        transcriptMetadataByID.merge(restoreMetadata) { _, new in new }
        var restoreCandidates: [SessionRestoreCandidate] = []

        // Lazy restore: only rebuild lightweight session state here (no grok process spawn).
        // The selected session is started below; the rest resume on demand when first opened.
        for record in restorableRecords {
            guard let workspace = workspaceStore.workspaces.first(where: { $0.id == record.workspaceID }) else { continue }
            guard liveSessions.first(where: { $0.id == record.id }) == nil else { continue }
            restoreStatusText = "Restoring \(workspace.displayName)"

            let store = ChatStore()
            let transcriptMetadata = restoreMetadata[record.id]
            let durableGrokID = record.grokSessionID
            let title = restoredTitle(for: record)
            store.prepare(workspace: workspace, savedGrokSessionID: durableGrokID)
            store.bindTabSession(
                record.id,
                modelIntent: record.modelIntent,
                savedModelExecutionState: record.modelExecutionState,
                agentIntent: record.agentIntent,
                savedGrokSessionID: durableGrokID,
                savedBackendBinding: record.backendBinding,
                savedForkLedgerEntry: record.forkLedgerReference.flatMap { reference in
                    saved.forkLedger.first { $0.id.uuidString == reference }
                },
                savedPendingRecoveryIntent: record.pendingRecoveryIntent
            )
            liveSessions.append(
                LiveSession(
                    id: record.id,
                    store: store,
                    workspace: workspace,
                    title: title,
                    grokSessionID: durableGrokID
                )
            )
            // Metadata is sufficient for restore selection. The selected tab hydrates its one
            // transcript in `selectSession`; background tabs never decode bodies at launch.
            let hasLocalTranscript = (transcriptMetadata?.restorableMessageCount ?? 0) > 0
            restoreCandidates.append(
                SessionRestoreCandidate(
                    id: record.id,
                    workspaceID: record.workspaceID,
                    lastActivationOrdinal: record.lastActivationOrdinal,
                    lastAccessed: record.lastAccessed,
                    hasLocalTranscript: hasLocalTranscript,
                    hasContent: hasLocalTranscript || record.backendBinding != nil,
                    hasVerifiedBinding: record.backendBinding?.verification == .verified,
                    isDiverged: record.backendBinding?.verification == .failed
                )
            )
            restoredSessionCount += 1
        }

        sessionListRevision &+= 1
        recentSessionOrder = SessionRestorePolicy.recentSessionOrder(from: restorableRecords)

        let workspaceID = saved.selectedWorkspaceID
            ?? restorableRecords.max(by: {
                if $0.lastActivationOrdinal != $1.lastActivationOrdinal {
                    return $0.lastActivationOrdinal < $1.lastActivationOrdinal
                }
                return $0.id.uuidString > $1.id.uuidString
            })?.workspaceID
            ?? liveSessions.first?.workspace.id

        guard let workspaceID,
              let workspace = workspaceStore.workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }
        let restoreInterval = GrokBuildPerformance.begin(.restoreDecision)
        let decision = SessionRestorePolicy.restoreDecision(
            input: SessionRestoreInput(
                workspaceID: workspaceID,
                savedSelectedSessionID: saved.selectedSessionIDByWorkspace[workspaceID]
                    ?? saved.selectedSessionID,
                workspaceWasRepaired: saved.selectedWorkspaceID != nil
                    && saved.selectedWorkspaceID != workspaceID,
                candidates: restoreCandidates
            )
        )
        restoreInterval.end()
        if let selected = decision.selectedSessionID {
            selectSession(
                selected,
                recordsActivation: false,
                reconcilePersistedTranscript: false
            )
        } else if decision.createdNewTab {
            _ = await createLiveSession(for: workspace)
        }
    }

    private func restoredTitle(for record: SavedSessionRecord) -> String {
        if let title = record.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        guard let grokID = record.grokSessionID else {
            return SessionTitle.defaultTitle
        }
        return "Session \(grokID.prefix(8))"
    }

    private func addWorkspace(url: URL) {
        let ws = Workspace(name: url.lastPathComponent, path: url)
        workspaceStore.add(ws)
        Task {
            await createLiveSession(for: ws)
        }
    }

    private func removeWorkspace(_ workspace: Workspace) {
        for sessionID in liveSessions.filter({ $0.workspace.id == workspace.id }).map(\.id) {
            closeSession(id: sessionID)
        }

        if selectedWorkspaceID == workspace.id {
            selectedWorkspaceID = workspaceStore.orderedWorkspaces
                .first(where: { $0.id != workspace.id })?
                .id
        }

        workspaceStore.remove(workspace)
        if workspaceStore.workspaces.isEmpty {
            selectedWorkspaceID = nil
            selectedSessionID = nil
            placeholderStore.clearProject()
        }
        persistSessionLayout()
    }

    private func refreshGitReviewFromTranscriptBoundary() {
        Task { @MainActor in
            await refreshProjectChangedFiles()
        }
    }

    @MainActor
    private func refreshProjectChangedFiles() async {
        guard let workspace = currentWorkspace else {
            projectChangedDiffs = []
            return
        }

        do {
            let files = try await GitService.changedFiles(in: workspace.path)
            var diffs: [ChatStore.DetectedDiff] = []
            for file in files {
                let diff = try await GitService.diffForChangedFile(file, in: workspace.path)
                diffs.append(ChatStore.DetectedDiff(raw: diff, filePath: file.path))
            }
            guard currentWorkspace?.id == workspace.id else { return }
            projectChangedDiffs = diffs
            activeStore.recordGitReviewFiles(diffs.compactMap(\.filePath), workspaceID: workspace.id)
            if diffs.isEmpty {
                showPreview = false
            }
        } catch {
            guard currentWorkspace?.id == workspace.id else { return }
            projectChangedDiffs = []
        }
    }

    @MainActor
    private func scheduleBoundedGitRefresh(for store: ChatStore) {
        boundedGitRefreshTask?.cancel()
        guard store === activeStore,
              let workspaceID = store.currentWorkspace?.id else { return }
        boundedGitRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  store === activeStore,
                  currentWorkspace?.id == workspaceID else { return }
            await refreshProjectChangedFiles()
        }
    }

    private func revealArtifact(_ artifact: ChatStore.RunArtifact) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: artifact.path)])
    }

    private func openCurrentProject(in target: ProjectOpenTarget) {
        guard let workspace = currentWorkspace else { return }
        switch target {
        case .finder:
            NSWorkspace.shared.open(workspace.path)
        case .cursor:
            openProject(
                workspace.path,
                bundleIdentifiers: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"],
                appNames: ["Cursor"]
            )
        case .vsCode:
            openProject(
                workspace.path,
                bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
                appNames: ["Visual Studio Code", "Visual Studio Code - Insiders"]
            )
        case .terminal:
            openProject(
                workspace.path,
                bundleIdentifiers: ["com.apple.Terminal"],
                appNames: ["Terminal"]
            )
        case .iTerm:
            openProject(
                workspace.path,
                bundleIdentifiers: ["com.googlecode.iterm2"],
                appNames: ["iTerm", "iTerm2"]
            )
        case .zed:
            openProject(
                workspace.path,
                bundleIdentifiers: ["dev.zed.Zed", "dev.zed.Zed-Preview", "com.zed.Zed"],
                appNames: ["Zed", "Zed Preview"]
            )
        }
    }

    private func openProject(_ url: URL, bundleIdentifiers: [String], appNames: [String]) {
        guard let appURL = InstalledAppFinder.installedApp(bundleIdentifiers: bundleIdentifiers, appNames: appNames) else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }

    private func handleWorkspaceChange(_ newID: Workspace.ID?) {
        if let id = newID,
           let ws = workspaceStore.workspaces.first(where: { $0.id == id }) {
            route = .session
            if activeSession?.workspace.id == id { return }
            selectProject(ws)
        }
    }

    private func selectProject(_ workspace: Workspace) {
        selectedWorkspaceID = workspace.id
        if let active = activeSession, active.workspace.id == workspace.id {
            return
        }
        if let preferred = preferredSessionID(for: workspace) {
            selectSession(preferred)
        } else {
            Task { await createLiveSession(for: workspace) }
        }
    }

    private func selectSession(
        _ id: UUID,
        recordsActivation: Bool = true,
        reconcilePersistedTranscript: Bool = true
    ) {
        let switchInterval = GrokBuildPerformance.begin(.tabSwitchToInteractive)
        guard let session = liveSessions.first(where: { $0.id == id }) else {
            switchInterval.end()
            return
        }
        let needsHydration = session.store.messages.isEmpty
        let needsReconciliation = !needsHydration
            && reconcilePersistedTranscript
            && session.store.continuityPermitsAuthoritativeReconciliation
        sessionSelectionGeneration &+= 1
        let selectionGeneration = sessionSelectionGeneration
        purgeEmptySessions(in: session.workspace.id, keeping: id)
        let savedRecord = sessionLayout.records.first(where: { $0.id == id })
        // Selection can happen while the restored tab's lazy process is still starting.
        // Rebind semantic intent together with the backend id; inherited defaults stay inherited.
        session.store.bindTabSession(
            id,
            modelIntent: savedRecord?.modelIntent ?? .inheritProjectDefault,
            savedModelExecutionState: savedRecord?.modelExecutionState ?? .unknown,
            agentIntent: savedRecord?.agentIntent ?? .inheritGlobalDefault,
            savedGrokSessionID: session.grokSessionID,
            savedBackendBinding: savedRecord?.backendBinding,
            savedForkLedgerEntry: savedRecord?.forkLedgerReference.flatMap { reference in
                sessionLayout.forkLedger.first { $0.id.uuidString == reference }
            },
            savedPendingRecoveryIntent: savedRecord?.pendingRecoveryIntent
        )
        session.store.syncWorkspaceReasoningEffortFromStorage()
        session.store.syncTabModelToLiveProcessIfNeeded()
        selectedSessionID = id
        selectedWorkspaceID = session.workspace.id
        refreshGitReviewFromTranscriptBoundary()
        if recordsActivation {
            noteSessionUsed(id)
        }
        Task {
            if needsHydration || needsReconciliation {
                let localMessages = await GrokBuildBackgroundWork.run({
                    SessionMessageStore.messages(for: id)
                }, priority: .utility)
                guard !Task.isCancelled,
                      selectedSessionID == id,
                      sessionSelectionGeneration == selectionGeneration else {
                    switchInterval.end()
                    return
                }

                if needsHydration {
                    // Backend history is not continuity authority. Restore only the local
                    // durable transcript here; Slice 3 imports/reconciles the exact backend
                    // after its keyed comparison permits the relationship.
                    session.store.restorePersistedMessages(localMessages)
                } else if needsReconciliation {
                    // Preserve the v3 selection path's ordering: disk is merged into the
                    // already-live transcript before authenticated continuity reconciliation.
                    // Only the file read and recovery parser leave the main actor.
                    session.store.mergePersistedMessages(localMessages)
                    let reconciliationMessages = session.store.messages
                    let recovered = await GrokBuildBackgroundWork.run({
                        SessionTranscriptRecovery.recoverIfNeeded(
                            sessionID: id,
                            grokSessionID: session.grokSessionID,
                            workspacePath: session.workspace.path,
                            currentMessages: reconciliationMessages
                        )
                    }, priority: .utility)
                    guard !Task.isCancelled,
                          selectedSessionID == id,
                          sessionSelectionGeneration == selectionGeneration else {
                        switchInterval.end()
                        return
                    }
                    if let recovered {
                        session.store.restorePersistedMessages(recovered)
                    }
                }
                refreshGitReviewFromTranscriptBoundary()
            }
            guard !Task.isCancelled,
                  selectedSessionID == id,
                  sessionSelectionGeneration == selectionGeneration else {
                switchInterval.end()
                return
            }
            // Selection is presentation only. `ChatStore.deliverPrompt` owns the lazy,
            // continuity-gated resume when the user actually submits new work.
            await refreshProjectChangedFiles()
            await Task.yield()
            await Task.yield()
            switchInterval.end()
        }
        persistSessionLayout()
    }

    /// Move a session to the front of the true MRU order. Background writes and streamed
    /// chunks never call this path, so persistence cannot manufacture recency.
    private func noteSessionUsed(_ id: UUID) {
        sessionLayout.activationCounter &+= 1
        let usedAt = Date()
        pendingActivationDates[id] = usedAt
        pendingActivationOrdinals[id] = sessionLayout.activationCounter
        if let index = sessionLayout.records.firstIndex(where: { $0.id == id }) {
            sessionLayout.records[index].lastAccessed = usedAt
            sessionLayout.records[index].lastActivationOrdinal = sessionLayout.activationCounter
        }
        recentSessionOrder.removeAll { $0 == id }
        recentSessionOrder.insert(id, at: 0)
    }

    /// Tear down grok processes for sessions beyond the MRU cap so the resident footprint
    /// stays bounded. The selected/most-recent sessions and any actively-working session are kept.
    private func enforceConnectionCap() async {
        let keep = Set(recentSessionOrder.prefix(maxConnectedSessions))
        let evictionCandidates = liveSessions.map(\.id).filter { !keep.contains($0) }
        for id in evictionCandidates {
            guard let index = liveSessions.firstIndex(where: { $0.id == id }) else { continue }
            let session = liveSessions[index]
            if keep.contains(session.id) || session.id == selectedSessionID { continue }
            // Skip sessions with no live process, and never interrupt one mid-turn.
            guard session.store.connectionState != .idle,
                  session.store.connectionState != .busy else { continue }
            let decision = await session.store.shutdownForLRUEviction(
                expectedTabID: session.id,
                persistedBackendID: session.grokSessionID
            )
            // Re-resolve after the await: closing or reordering a tab cannot make an
            // old array index adopt another tab's backend receipt.
            if let currentIndex = liveSessions.firstIndex(where: { $0.id == id }) {
                liveSessions[currentIndex].grokSessionID = decision.preservedBackendID
            }
        }
    }

    private func startNewSessionForCurrentProject() {
        guard let workspace = currentWorkspace else { return }
        Task { await createLiveSession(for: workspace) }
    }

    @discardableResult
    private func createLiveSession(
        for workspace: Workspace,
        resumeSession: GrokSessionInfo? = nil,
        agent: String? = nil
    ) async -> UUID {
        purgeEmptySessions(in: workspace.id)
        let id = UUID()
        let store = ChatStore()
        let title = resumeSession.flatMap { session in
            SessionNameStore.name(for: session.id)
                ?? (session.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : session.summary)
        } ?? SessionTitle.defaultTitle
        liveSessions.append(
            LiveSession(id: id, store: store, workspace: workspace, title: title, grokSessionID: resumeSession?.id)
        )
        selectedSessionID = id
        selectedWorkspaceID = workspace.id
        projectChangedDiffs = []
        noteSessionUsed(id)
        Task { await refreshProjectChangedFiles() }
        sessionListRevision &+= 1
        persistSessionLayout()
        if let resumeSession {
            store.prepare(workspace: workspace, savedGrokSessionID: resumeSession.id)
            store.bindTabSession(id, modelIntent: .inheritProjectDefault)
            await store.start(workspace: workspace, resumeSession: resumeSession)
        } else {
            store.prepare(workspace: workspace)
            // An Agents-hub launch binds the explicit agent intent before any process
            // exists; the lazy first-send launch then carries `--agent` naturally.
            store.bindTabSession(
                id,
                modelIntent: .inheritProjectDefault,
                agentIntent: agent.map { .explicit($0) } ?? .inheritGlobalDefault
            )
        }
        // A fresh ChatStore starts with empty discovery/connection inventories, which
        // blanked the Agents hub and Connections lane until the next workspace switch.
        // Both loads are guarded and read-only.
        Task {
            await store.loadDiscoveredAgentsIfNeeded()
            await store.refreshPromptMCPOptions()
        }
        await enforceConnectionCap()
        return id
    }

    private func switchBranch(project: Workspace, branch: String) async {
        do {
            _ = try await GitService.run(["switch", branch], in: project.path)
            await createLiveSession(for: project)
            gitCheckoutRequest = nil
        } catch {
            gitError = error.localizedDescription
        }
    }

    private func createAndSwitchBranch(project: Workspace, branch: String) async {
        do {
            _ = try await GitService.run(["switch", "-c", branch], in: project.path)
            await createLiveSession(for: project)
            gitCheckoutRequest = nil
        } catch {
            gitError = error.localizedDescription
        }
    }

    private func openWorktree(_ worktree: GitWorktreeInfo, from project: Workspace) async {
        let path = worktree.path.standardizedFileURL
        if path.path == project.path.standardizedFileURL.path {
            if let branch = worktree.branch,
               branch != GitService.currentBranch(in: project.path) {
                await switchBranch(project: project, branch: branch)
            } else {
                gitCheckoutRequest = nil
            }
            return
        }

        if let existing = workspaceStore.workspaces.first(where: {
            $0.path.standardizedFileURL.path == path.path
        }) {
            selectProject(existing)
            await createLiveSession(for: existing)
        } else {
            let workspace = Workspace(name: path.lastPathComponent, path: path)
            workspaceStore.add(workspace)
            await createLiveSession(for: workspace)
        }
        gitCheckoutRequest = nil
    }

    private func createWorktree(project: Workspace, branch: String, path: String) async {
        do {
            let pathURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            _ = try await GitService.run(["worktree", "add", "-b", branch, pathURL.path], in: project.path)
            let workspace = Workspace(name: pathURL.lastPathComponent, path: pathURL)
            workspaceStore.add(workspace)
            await createLiveSession(for: workspace)
            gitCheckoutRequest = nil
        } catch {
            gitError = error.localizedDescription
        }
    }

    private func refreshUpgradeBannerState() {
        guard !isUpgradeBannerDismissed else {
            showUpgradeBanner = false
            bannerAppVersion = nil
            bannerCLIVersion = nil
            return
        }

        let appAvailable = UpdateScheduler.hasActionableAppUpdate
        let cliAvailable = UpdateScheduler.hasActionableCLIUpdate

        guard appAvailable || cliAvailable else {
            showUpgradeBanner = false
            bannerAppVersion = nil
            bannerCLIVersion = nil
            return
        }

        bannerAppVersion = appAvailable ? UpdateScheduler.cachedAppRelease?.latestVersion : nil
        bannerCLIVersion = cliAvailable ? UpdateScheduler.cachedCLIStatus?.latestVersion : nil
        showUpgradeBanner = true
    }
}

private struct UpdatesBanner: View {
    let appVersion: String?
    let cliVersion: String?
    let onAction: () -> Void
    let onDismiss: () -> Void

    private var subtitle: String {
        switch (appVersion, cliVersion) {
        case let (app?, nil):
            return "GrokBuild \(app) is ready to download and install."
        case let (nil, cli?):
            return "grok CLI \(cli) is ready to update."
        case let (app?, cli?):
            return "GrokBuild \(app) and grok CLI \(cli) have updates ready."
        default:
            return "Review available updates."
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Button(action: onAction) {
                    Text("Updates Available")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss until next launch")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

extension Notification.Name {
    static let chooseWorkspaceRequested = Notification.Name("chooseWorkspaceRequested")
    static let sessionsRequested = Notification.Name("sessionsRequested")
    static let stopGenerationRequested = Notification.Name("stopGenerationRequested")
    static let focusInputRequested = Notification.Name("focusInputRequested")
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
    static let newSessionRequested = Notification.Name("newSessionRequested")
    static let liveSessionMessagesChanged = Notification.Name("liveSessionMessagesChanged")
    static let liveSessionModelChanged = Notification.Name("liveSessionModelChanged")
    static let liveSessionAgentChanged = Notification.Name("liveSessionAgentChanged")
    static let workspaceAgentSettingsChanged = Notification.Name("workspaceAgentSettingsChanged")
    static let subagentRolesChanged = Notification.Name("subagentRolesChanged")
    static let grokBuildUpdateAvailable = Notification.Name("grokBuildUpdateAvailable")
    static let grokBuildUpdateStateChanged = Notification.Name("grokBuildUpdateStateChanged")
    static let grokBuildUpdaterPhaseChanged = Notification.Name("grokBuildUpdaterPhaseChanged")
    static let grokBuildCLIUpdaterPhaseChanged = Notification.Name("grokBuildCLIUpdaterPhaseChanged")
    static let grokBuildRestartSessionsRequested = Notification.Name("grokBuildRestartSessionsRequested")
    static let grokBuildPrepareForShutdown = Notification.Name("grokBuildPrepareForShutdown")
    static let grokBuildShutdownComplete = Notification.Name("grokBuildShutdownComplete")
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
    static let workflowsConfigChanged = Notification.Name("workflowsConfigChanged")
}

private struct ContentViewNotificationHandlers: ViewModifier {
    let activeStore: ChatStore
    let liveSessions: [ContentView.LiveSession]
    @Binding var sessionListRevision: Int
    @Binding var selectedWorkspaceID: Workspace.ID?
    @Binding var showPicker: Bool
    @Binding var showSessions: Bool
    let onWorkspaceChange: (Workspace.ID?) -> Void
    let onRefreshGitReview: () -> Void
    let onNewSession: () -> Void
    let onPersistSessionLayout: (Bool) -> Void
    let onTranscriptBoundary: (UUID) -> Void
    let onSessionStarted: () -> Void
    /// nil = keep the remembered tab; a value forces that tab.
    let openSettings: (SettingsTab?) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .chooseWorkspaceRequested)) { _ in
                showPicker = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .sessionsRequested)) { _ in
                showSessions = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .stopGenerationRequested)) { _ in
                activeStore.requestStop()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusInputRequested)) { _ in
                // handled inside ChatView via focus
            }
            .onChange(of: selectedWorkspaceID) { _, newID in
                onWorkspaceChange(newID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .newSessionRequested)) { _ in
                onNewSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
                // An actionable update routes to the App tab; otherwise honor the
                // remembered tab instead of clobbering it back to Agents on every ⌘,.
                openSettings(UpdateScheduler.hasAnyActionableUpdate ? .app : nil)
            }
            .onChange(of: activeStore.grokSessionId) { _, newSessionID in
                // `GrokProcess.shutdown()` clears its live id. The quit handler has already
                // persisted the valid receipt; never overwrite it with teardown's transient nil.
                guard SessionIdentityPersistencePolicy.shouldPersistChangedSessionID(newSessionID) else {
                    return
                }
                onPersistSessionLayout(true)
                onSessionStarted()
            }
            .onReceive(NotificationCenter.default.publisher(for: .liveSessionMessagesChanged)) { note in
                handleLiveSessionMessagesChanged(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .workspaceAgentSettingsChanged)) { note in
                handleWorkspaceAgentSettingsChanged(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .liveSessionModelChanged)) { _ in
                onPersistSessionLayout(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .liveSessionAgentChanged)) { _ in
                onPersistSessionLayout(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .grokBuildPrepareForShutdown)) { _ in
                handlePrepareForShutdown()
            }
            .onReceive(NotificationCenter.default.publisher(for: .grokBuildRestartSessionsRequested)) { _ in
                handleRestartSessionsRequested()
            }
    }

    private func handleLiveSessionMessagesChanged(_ note: Notification) {
        sessionListRevision &+= 1
        let notifyingStore = note.object as? ChatStore
        if let store = notifyingStore,
           let session = liveSessions.first(where: { $0.store === store }) {
            onTranscriptBoundary(session.id)
        }
        // Git review refreshes only at prompt boundaries (send / turn complete /
        // failure), never per streamed chunk. Assistant transcript text is not a
        // repository snapshot and never opens review or becomes an apply input.
        if notifyingStore == nil || notifyingStore === activeStore {
            onRefreshGitReview()
        }
    }

    private func handleWorkspaceAgentSettingsChanged(_ note: Notification) {
        guard let workspaceID = note.userInfo?["workspaceID"] as? UUID else { return }
        for session in liveSessions where session.workspace.id == workspaceID {
            session.store.syncWorkspaceReasoningEffortFromStorage()
        }
    }

    private func handlePrepareForShutdown() {
        onPersistSessionLayout(true)
        Task {
            for session in liveSessions {
                await session.store.shutdownPermanently()
            }
            // AppDelegate holds termination open (bounded) until this arrives.
            NotificationCenter.default.post(name: .grokBuildShutdownComplete, object: nil)
        }
    }

    private func handleRestartSessionsRequested() {
        Task {
            for session in liveSessions {
                await session.store.retryConnection()
            }
        }
    }
}
