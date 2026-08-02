import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ComposerControlMetrics {
    static let minimumHitTarget: CGFloat = 36
}

enum ProjectOpenTarget {
    case finder
    case cursor
    case vsCode
    case terminal
    case iTerm
    case zed
}

enum ChatTranscriptLayout {
    static func activeAssistantMessageID(
        messages: [Message],
        streamingMessageID: UUID?
    ) -> UUID? {
        if let streamingMessageID { return streamingMessageID }
        guard let lastTurnMessage = messages.last(where: { $0.role == .assistant || $0.role == .user }) else {
            return nil
        }
        return lastTurnMessage.role == .assistant ? lastTurnMessage.id : nil
    }

    /// Thinking belongs to the assistant response for the active turn. During
    /// streaming that response has an explicit id; after completion it is the
    /// most recent assistant message — but only when that message is the
    /// latest turn's answer. When a failed turn removed its empty assistant
    /// reply (the transcript then ends with the user prompt), this returns
    /// nil and ChatView renders the block at the transcript tail instead, so
    /// the trace is neither lost nor attached to an older answer.
    static func thinkingMessageID(
        messages: [Message],
        streamingMessageID: UUID?
    ) -> UUID? {
        activeAssistantMessageID(
            messages: messages,
            streamingMessageID: streamingMessageID
        )
    }
}

enum ChatAutoScrollPolicy {
    /// Follow-up passes after the first scroll. GPT/DeepSeek and rich Markdown can
    /// deliver one large final chunk whose SwiftUI/WebKit height settles after the
    /// stream event; a single pre-layout scroll then leaves the answer below the fold.
    /// These gaps yield immediately, then cover the next ~800 ms of layout settling.
    static let layoutSettleGapsMilliseconds = [0, 120, 240, 440]
}

enum ComposerModelMenuLayout {
    static func effortDisplayName(storedValue: String) -> String {
        ReasoningEffortLevel(storedValue: storedValue).displayName
    }
}

enum ComposerSubmissionPolicy {
    /// Clear only the exact draft GrokBuild handed to the agent and only after the
    /// session accepted it. If lazy resume is still starting — or the user typed
    /// more while send awaited readiness — the editor remains authoritative.
    static func draftAfterSubmission(
        currentDraft: String,
        submittedDraft: String,
        accepted: Bool
    ) -> String {
        accepted && currentDraft == submittedDraft ? "" : currentDraft
    }
}

enum ConnectionStatusPresentation {
    static func subtitle(
        state: GrokProcessState,
        isResumedSession: Bool,
        hasWorkspace: Bool
    ) -> String {
        switch state {
        case .starting:
            return isResumedSession ? "Resuming session…" : "Starting agent…"
        case .ready:
            return "Connected"
        case .busy:
            return "Working…"
        case .failed:
            return "Connection error"
        case .idle:
            return hasWorkspace ? "Ready" : "Idle"
        }
    }
}

struct ChatView: View {
    @Bindable var store: ChatStore
    var isSidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var reviewFileCount: Int = 0
    var isReviewVisible: Bool = false
    var onToggleReview: () -> Void = {}
    var onSelectSession: (UUID) -> Void = { _ in }
    var onBrowseSessions: () -> Void = {}
    var onNewSession: () -> Void = {}
    var onAddProject: () -> Void = {}
    var onOpenProjectIn: (ProjectOpenTarget) -> Void = { _ in }
    var onToggleBrowserTools: () -> Void = {}
    var onSelectBrowserRuntime: (BrowserRuntimeMode) -> Void = { _ in }
    var onToggleComputerUse: () -> Void = {}
    var onOpenBrowserSettings: () -> Void = {}
    var onOpenComputerUseSettings: () -> Void = {}
    var onOpenAgentSettings: () -> Void = {}
    var onOpenMemorySettings: () -> Void = {}
    var onOpenWorkflowSettings: () -> Void = {}
    var onForkSession: () -> Void = {}
    var onOpenDashboard: () -> Void = {}
    var onSwitchBranch: () -> Void = {}

    @State private var input: String = ""
    @State private var isFileDropTargeted = false
    @State private var slashActiveIndex = 0
    @State private var slashSkillsExpanded = false
    @State private var slashCommandsExpanded = false
    @State private var toolActivityExpanded = false
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var lastAutoScroll: Date = .distantPast
    @State private var voiceInput = VoiceInputService()
    @State private var pendingReasoningEffortChange: String?
    // GrokBuild is a project workbench, not a generic chat window. Keep branch,
    // agent, tools, workflows, and background-task state visible by default.
    @State private var showSessionControls = true
    @State private var toolPillStatus = ToolPillStatus()
    @State private var branchLabel = "No branch"
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BrowserSettingsKeys.appliedEnabled) private var browserToolsEnabled = BrowserSettings.defaults.enabled
    @AppStorage(ComputerUseSettingsKeys.appliedEnabled) private var computerUseEnabled = ComputerUseSettings.defaults.enabled
    @AppStorage(GrokSettingsKeys.memoryEnabled) private var memoryEnabled = GrokPermissionSettings.defaults.memoryEnabled

    @State private var showMemoryBrowser = false
    @State private var showRememberPrompt = false
    @State private var memoryNoteText = ""
    @State private var cachedCustomSubagentNames: [String] = []
    @State private var showSavedWorkflows = false
    @State private var showDeepResearch = false
    @State private var showSetGoal = false
    @State private var showCreateSkill = false
    @State private var showImagine = false
    @State private var showRecoveryReview = false
    @State private var createSkillName = ""
    @State private var imaginePrompt = ""
    // Constant default (matches WorkflowsConfigStore's missing-file default,
    // pinned by WorkflowRunTests); the real value loads in .onAppear. A file
    // read here would run on every ChatView struct init — once per streamed
    // token while ContentView invalidates.
    @State private var workflowsEnabled = true

    private var slashMatch: (query: String, range: Range<String.Index>)? {
        SlashAutocomplete.match(in: input)
    }

    private var filteredSlashCommands: [SlashCommand] {
        guard let match = slashMatch else { return [] }
        let q = match.query.lowercased()
        return store.availableSlashCommands.filter { $0.name.lowercased().hasPrefix(q) }
    }

    private var slashGroups: (skills: [SlashCommand], commands: [SlashCommand]) {
        SlashAutocompleteGroups.split(filteredSlashCommands)
    }

    private var slashFiltering: Bool {
        !(slashMatch?.query.isEmpty ?? true)
    }

    private var slashMenuEntries: [SlashMenuEntry] {
        SlashAutocompleteGroups.navigableEntries(
            skills: slashGroups.skills,
            commands: slashGroups.commands,
            skillsExpanded: slashSkillsExpanded,
            commandsExpanded: slashCommandsExpanded,
            filtering: slashFiltering
        )
    }

    private var showSlashPopover: Bool {
        !slashMenuEntries.isEmpty && inputFocused
    }

    private var hasThinkingContent: Bool {
        !store.thinkingText.isEmpty || store.thinkingDuration != nil
    }

    private var thinkingMessageID: UUID? {
        guard hasThinkingContent else { return nil }
        return ChatTranscriptLayout.thinkingMessageID(
            messages: store.messages,
            streamingMessageID: store.streamingMessageID
        )
    }

    /// A failed turn removes its empty assistant reply, leaving thinking with
    /// no anchor. Render it at the tail so the diagnostic is not lost.
    private var showThinkingAtTail: Bool {
        hasThinkingContent && thinkingMessageID == nil
    }

    private var toolActivityMessageID: UUID? {
        guard !store.liveToolCalls.isEmpty else { return nil }
        return ChatTranscriptLayout.activeAssistantMessageID(
            messages: store.messages,
            streamingMessageID: store.streamingMessageID
        )
    }

    private var showToolActivityAtTail: Bool {
        !store.liveToolCalls.isEmpty && toolActivityMessageID == nil
    }

    private var thinkingBlock: some View {
        ThinkingBlock(
            text: store.thinkingText,
            duration: store.thinkingDuration,
            isExpanded: store.isThinkingExpanded,
            isLive: store.isStreaming && store.thinkingDuration == nil
        ) {
            store.toggleThinkingExpanded()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if let authMsg = store.authRequiredMessage {
                AuthBanner(
                    message: authMsg,
                    onDismiss: { store.authRequiredMessage = nil },
                    onRetry: { Task { await store.retryConnection() } }
                )
            }

            if let error = store.lastError {
                ErrorBanner(message: error)
            }

            if let stalledSince = store.turnStalledSince {
                TurnStalledBanner(since: stalledSince) {
                    store.stop()
                }
            }

            if let switchError = store.modelSwitchError {
                ModelSwitchBanner(
                    message: switchError,
                    canStartNewSession: store.modelSwitchNeedsNewSession,
                    onStartNewSession: {
                        store.modelSwitchError = nil
                        store.modelSwitchNeedsNewSession = false
                        Task { await store.startNewSession() }
                    },
                    onDismiss: {
                        store.modelSwitchError = nil
                        store.modelSwitchNeedsNewSession = false
                    }
                )
            }

            if store.shouldShowContinuityBanner {
                SessionContinuityBanner(
                    status: store.continuityStatus,
                    headline: store.continuityHeadline,
                    message: store.continuityMessage,
                    details: store.continuityDetails,
                    onContinueAsNew: {
                        Task { _ = await store.continueAsNew() }
                    },
                    onRelink: {
                        showRecoveryReview = true
                        Task { await store.reviewRecoveryCandidates() }
                    }
                )
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if store.messages.isEmpty {
                            if store.currentWorkspace == nil {
                                noProjectState
                            } else if case .failed = store.connectionState {
                                EmptyView()
                            } else if store.isResumedSessionTab {
                                EmptyView()
                            } else {
                                welcomeState
                            }
                        }

                        ForEach(store.messages) { msg in
                            if thinkingMessageID == msg.id {
                                thinkingBlock
                            }

                            if toolActivityMessageID == msg.id {
                                toolActivityBlock
                            }

                            MessageBubble(
                                message: msg,
                                isStreaming: store.isStreaming && msg.id == store.streamingMessageID
                            )
                            .id(msg.id)
                        }

                        if showThinkingAtTail {
                            thinkingBlock
                        }

                        if store.isGrokking {
                            GrokkingIndicator(startedAt: store.turnStartedAt)
                                .padding(.leading, 2)
                        }

                        if showToolActivityAtTail {
                            toolActivityBlock
                        }

                        if let plan = store.pendingExitPlan {
                            PlanReviewCard(plan: plan) { verdict, comment in
                                store.respondToExitPlan(plan, verdict: verdict, comment: comment)
                            }
                        }

                        ForEach(store.pendingQuestions) { question in
                            QuestionCard(
                                request: question,
                                onSubmit: { answers in store.respondToQuestion(question, answers: answers) },
                                onSkip: { store.cancelQuestion(question) }
                            )
                        }

                        ForEach(store.pendingPermissions) { perm in
                            PermissionCard(
                                permission: perm,
                                effectivePermissionMode: store.effectivePermissionMode
                            ) { optionId in
                                store.respondToPermission(perm, with: optionId)
                            }
                        }

                        // A fixed 1pt element at the true bottom. Scrolling to a
                        // dedicated anchor is reliable in a LazyVStack; scrolling to the
                        // last message's id is not when that message is tall and was
                        // just streamed in — which is why long answers stranded below
                        // the fold.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorID)
                    }
                    .frame(maxWidth: AppTheme.Layout.conversationMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 24)
                }
                .background(AppTheme.Palette.canvas)
                .onAppear {
                    // Settings navigation and tab restoration recreate ChatView, so
                    // populated transcripts must reopen at the latest answer.
                    scheduleSettledAutoScroll(proxy: proxy)
                }
                .onChange(of: store.messages.count) { _, _ in
                    scheduleSettledAutoScroll(proxy: proxy)
                }
                .onChange(of: store.isGrokking) { _, _ in
                    scheduleSettledAutoScroll(proxy: proxy)
                }
                .onChange(of: store.isStreaming) { _, isStreaming in
                    if !isStreaming {
                        // The final provider event can precede the last rich-text layout.
                        scheduleSettledAutoScroll(
                            proxy: proxy,
                            performanceInterval: GrokBuildPerformance.begin(.finalChunkToSettledRender)
                        )
                    }
                }
                // Follows every streamed chunk — thinking AND answer. A streaming answer
                // grows the existing message's content (no count/isGrokking change), so
                // without this the answer streams below the fold behind the thinking chip.
                // Throttled to ~12/sec so it follows live, with a trailing scroll so the
                // final token always lands the true bottom in view.
                .onChange(of: store.streamRevision) { _, _ in
                    let now = Date()
                    if now.timeIntervalSince(lastAutoScroll) > 0.08 {
                        lastAutoScroll = now
                        scrollToBottom(proxy: proxy, instant: true)
                    }
                    scheduleSettledAutoScroll(proxy: proxy)
                }
            }

            if let goal = store.goalState {
                GoalBanner(state: goal, store: store)
                    .padding(.horizontal, 12)
            }

            if let aside = store.btwAsideText {
                BtwAsideBanner(text: aside) {
                    store.clearBtwAside()
                }
                .padding(.horizontal, 12)
            }

            composer
        }
        .onAppear { inputFocused = true }
        .onDisappear {
            autoScrollTask?.cancel()
            autoScrollTask = nil
        }
        .onChange(of: store.liveToolCalls.isEmpty) { _, isEmpty in
            if isEmpty { toolActivityExpanded = false }
        }
        .confirmationDialog(
            "Change reasoning effort?",
            isPresented: Binding(
                get: { pendingReasoningEffortChange != nil },
                set: { if !$0 { pendingReasoningEffortChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Summarize & Restart") {
                if let effort = pendingReasoningEffortChange {
                    Task {
                        await store.applyReasoningEffort(effort, strategy: .summarizeAndRestart)
                    }
                }
                pendingReasoningEffortChange = nil
            }
            Button("Restart", role: .destructive) {
                if let effort = pendingReasoningEffortChange {
                    Task {
                        await store.applyReasoningEffort(effort, strategy: .restart)
                    }
                }
                pendingReasoningEffortChange = nil
            }
            Button("Cancel", role: .cancel) {
                pendingReasoningEffortChange = nil
            }
        } message: {
            if let effort = pendingReasoningEffortChange {
                Text("Apply \(store.reasoningEffortDisplayName(effort)) when Grok restarts. Summarize & restart runs /compact first to preserve context.")
            }
        }
        .sheet(isPresented: $showMemoryBrowser) {
            MemoryBrowserPanel()
        }
        .sheet(isPresented: $showRememberPrompt) {
            rememberPromptSheet
        }
        .sheet(isPresented: $showSavedWorkflows) {
            SavedWorkflowsPanel(projectRoot: store.currentWorkspace?.path) { workflow, argsJSON in
                Task {
                    let args = Self.parseWorkflowArgsJSON(argsJSON)
                    _ = await store.launchSavedWorkflow(name: workflow.name, args: args)
                }
            }
        }
        .sheet(isPresented: $showDeepResearch) {
            DeepResearchSheet { query in
                Task { _ = await store.startDeepResearch(query) }
            }
        }
        .sheet(isPresented: $showSetGoal) {
            SetGoalSheet { objective, budget in
                Task { _ = await store.setGoal(objective, budget: budget) }
            }
        }
        .sheet(isPresented: $showCreateSkill) {
            createSkillSheet
        }
        .sheet(isPresented: $showImagine) {
            imagineSheet
        }
        .sheet(isPresented: $showRecoveryReview) {
            SessionRecoveryReviewSheet(store: store) {
                showRecoveryReview = false
            }
        }
        .onAppear {
            workflowsEnabled = WorkflowsConfigStore.loadEnabled()
            input = store.composerDraft
        }
        .onChange(of: input) { _, newValue in
            store.composerDraft = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .workflowsConfigChanged)) { _ in
            workflowsEnabled = WorkflowsConfigStore.loadEnabled()
        }
        .onChange(of: store.isStreaming) { wasStreaming, isStreamingNow in
            if wasStreaming && !isStreamingNow {
                AccessibilityNotification.Announcement("Build agent finished").post()
            }
        }
        .onChange(of: store.connectionState) { _, newState in
            if case .ready = newState {
                // Clear stale auth message if the CLI became ready again
                if store.authRequiredMessage != nil {
                    store.authRequiredMessage = nil
                }
            } else if case .failed(let msg) = newState,
                      (msg.lowercased().contains("login") || msg.lowercased().contains("auth")),
                      store.authRequiredMessage == nil {
                store.authRequiredMessage = msg
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(GrokChromeButtonStyle())
            .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
            .accessibilityLabel(isSidebarVisible ? "Hide sidebar" : "Show sidebar")

            Button(action: onNewSession) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(GrokChromeButtonStyle())
            .disabled(store.currentWorkspace == nil)
            .help("New session")

            Spacer()

            Menu {
                Button("Browse sessions", systemImage: "clock") {
                    onBrowseSessions()
                }
                Button("Session dashboard", systemImage: "square.grid.2x2") {
                    onOpenDashboard()
                }

                if store.currentWorkspace != nil {
                    Divider()
                }
                if store.isResumedSessionTab || store.grokSessionId != nil {
                    Button("Fork session", systemImage: "arrow.triangle.branch") {
                        onForkSession()
                    }
                }
                if store.hasShareCommand {
                    Button("Share session", systemImage: "square.and.arrow.up") {
                        Task { _ = await store.shareSession() }
                    }
                    .disabled(store.isStreaming)
                }
                if store.hasGoalCommand {
                    Button("Set goal…", systemImage: "target") {
                        showSetGoal = true
                    }
                    .disabled(store.isStreaming)
                }
                if store.hasCreateSkillCommand {
                    Button("Create skill…", systemImage: "hammer") {
                        createSkillName = ""
                        showCreateSkill = true
                    }
                    .disabled(store.isStreaming)
                }

                if store.currentWorkspace != nil {
                    Divider()

                    Menu("Open project in", systemImage: "arrow.up.forward.app") {
                        openInButton(title: "Finder", target: .finder, appURL: InstalledAppFinder.finderURL, fallbackSystemImage: "finder")
                        if let app = InstalledAppFinder.installedApp(bundleIdentifiers: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"], appNames: ["Cursor"]) {
                            openInButton(title: "Cursor", target: .cursor, appURL: app, fallbackSystemImage: "cursorarrow")
                        }
                        if let app = InstalledAppFinder.installedApp(bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"], appNames: ["Visual Studio Code", "Visual Studio Code - Insiders"]) {
                            openInButton(title: "VS Code", target: .vsCode, appURL: app, fallbackSystemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        Divider()
                        if let app = InstalledAppFinder.installedApp(bundleIdentifiers: ["com.apple.Terminal"], appNames: ["Terminal"]) {
                            openInButton(title: "Terminal", target: .terminal, appURL: app, fallbackSystemImage: "terminal")
                        }
                        if let app = InstalledAppFinder.installedApp(bundleIdentifiers: ["com.googlecode.iterm2"], appNames: ["iTerm", "iTerm2"]) {
                            openInButton(title: "iTerm", target: .iTerm, appURL: app, fallbackSystemImage: "terminal.fill")
                        }
                        if let app = InstalledAppFinder.installedApp(bundleIdentifiers: ["dev.zed.Zed", "dev.zed.Zed-Preview", "com.zed.Zed"], appNames: ["Zed", "Zed Preview"]) {
                            Divider()
                            openInButton(title: "Zed", target: .zed, appURL: app, fallbackSystemImage: "square.and.pencil")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .help("More actions")
            .accessibilityLabel("More actions")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(GrokChromeButtonStyle())
            .help("Settings")
            .accessibilityLabel("Open Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(AppTheme.Palette.canvas)
    }

    private func openInButton(
        title: String,
        target: ProjectOpenTarget,
        appURL: URL,
        fallbackSystemImage: String
    ) -> some View {
        Button {
            onOpenProjectIn(target)
        } label: {
            Label {
                Text(title)
            } icon: {
                InstalledAppFinder.appIcon(for: appURL, fallbackSystemImage: fallbackSystemImage)
            }
        }
    }

    private var brandMark: some View {
        Group {
            if let icon = GrokBrandIcon.mark() {
                Image(nsImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var welcomeState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 16) {
                brandMark
                Text("\(store.currentWorkspace?.displayName ?? "Project") Build Workspace")
                    .font(.system(size: 30, weight: .regular))
                    .multilineTextAlignment(.center)
                Text("Inspect code, plan changes, run tools, and review the working tree.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12),
                    count: 4
                ),
                spacing: 12
            ) {
                ForEach(QuickStartPrompt.defaults) { item in
                    QuickStartChip(item: item) {
                        input = item.prompt
                        inputFocused = true
                    }
                }
            }

            Text("⏎ send · ⇧⏎ new line · / for skills")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .padding(.horizontal, 32)
    }

    private var noProjectState: some View {
        VStack(spacing: 18) {
            brandMark
            VStack(spacing: 6) {
                Text("Welcome to GrokBuild")
                    .font(.title2.weight(.semibold))
                Text("Add a project folder to start a Grok session — then plan, build, and explore your code together.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onAddProject) {
                Label("Add Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Choose a folder to work in")
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .padding(.horizontal, 24)
    }

    private var connectionStatusColor: Color {
        switch store.continuityStatus {
        case .verifying:
            return .yellow
        case .diverged, .compositeSuspected, .backendMissing, .verificationIncomplete:
            return .orange
        case .localOnly:
            if store.hasUserMessages { return .secondary }
        case .verified, .backendOnly, .recoveryForked:
            break
        }
        switch store.connectionState {
        case .starting: return .yellow
        case .ready, .busy: return .green
        case .failed: return .red
        case .idle: return store.currentWorkspace == nil ? .secondary : .green
        }
    }

    private var connectionSubtitle: String {
        switch store.continuityStatus {
        case .verifying:
            return "Checking continuity…"
        case .diverged, .compositeSuspected, .backendMissing, .verificationIncomplete:
            return "Continuity blocked"
        case .localOnly where store.hasUserMessages:
            return "Local only"
        case .localOnly, .verified, .backendOnly, .recoveryForked:
            break
        }
        return ConnectionStatusPresentation.subtitle(
            state: store.connectionState,
            isResumedSession: store.isResumedSessionTab,
            hasWorkspace: store.currentWorkspace != nil
        )
    }

    static let bottomAnchorID = "transcript-bottom-anchor"

    private func scrollToBottom(proxy: ScrollViewProxy, instant: Bool = false) {
        guard !store.messages.isEmpty else { return }
        // Instant while streaming (animating every ~80ms would stutter); a gentle ease
        // for one-off jumps like a finished turn or a newly-added message.
        if instant || reduceMotion || store.isStreaming {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func scheduleSettledAutoScroll(
        proxy: ScrollViewProxy,
        performanceInterval: GrokBuildPerformanceInterval? = nil
    ) {
        autoScrollTask?.cancel()
        autoScrollTask = Task { @MainActor in
            defer { performanceInterval?.end() }
            for gap in ChatAutoScrollPolicy.layoutSettleGapsMilliseconds {
                if gap > 0 {
                    try? await Task.sleep(for: .milliseconds(gap))
                } else {
                    await Task.yield()
                }
                guard !Task.isCancelled else { return }
                lastAutoScroll = Date()
                scrollToBottom(proxy: proxy, instant: true)
            }
        }
    }

    /// Skill + research + imagine chips in curated order, shown as one horizontal bar.
    private var composerChips: [SlashCommand] {
        SkillSlashCommands.filter(store.availableSlashCommands)
            + ResearchSlashCommands.filter(store.availableSlashCommands)
            + ImagineSlashCommands.filter(store.availableSlashCommands)
    }

    private var composerCommandMenu: some View {
        Menu {
            if composerChips.isEmpty {
                Button {
                    input = "/"
                    inputFocused = true
                } label: {
                    Label("Browse commands with /", systemImage: "text.cursor")
                }
            } else {
                ForEach(composerChips) { command in
                    Button {
                        Task { await handleComposerChip(command) }
                    } label: {
                        Label(
                            command.name.replacingOccurrences(of: "-", with: " ").capitalized,
                            systemImage: "hammer"
                        )
                    }
                    .disabled(store.isStreaming || store.currentWorkspace == nil)
                }
            }
        } label: {
            Image(systemName: "hammer")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                // Visual glyph stays 13pt; the tappable region meets the composer's
                // 36pt pointer/keyboard target contract.
                .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Skills and workflows")
        .accessibilityValue(
            composerChips.isEmpty
                ? "Browse commands"
                : "\(composerChips.count) available"
        )
        .help("Skills and workflows")
    }

    private var toolActivityBlock: some View {
        ToolActivityGroup(
            tools: store.liveToolCalls,
            isExpanded: toolActivityExpanded
        ) {
            toolActivityExpanded.toggle()
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.fileAttachments.isEmpty {
                FileChipBar(
                    attachments: store.fileAttachments,
                    onToggleHidden: { store.toggleFileAttachmentHidden(id: $0) },
                    onRemove: { store.removeFileAttachment(id: $0) }
                )
            }

            if !store.promptQueue.isEmpty {
                promptQueueBar
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    if showSlashPopover {
                        SlashAutocompleteView(
                            entries: slashMenuEntries,
                            activeIndex: slashActiveIndex,
                            onSelect: pickSlashCommand,
                            onShowMoreSkills: {
                                slashSkillsExpanded = true
                                clampSlashActiveIndex()
                            },
                            onShowMoreCommands: {
                                slashCommandsExpanded = true
                                clampSlashActiveIndex()
                            }
                        )
                    }

                    TextField("Plan, Build, / for skills", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.composer)
                    .lineSpacing(4)
                    .focused($inputFocused)
                    .lineLimit(1...6)
                    .submitLabel(.send)
                    .onSubmit {
                        if showSlashPopover {
                            activateSlashEntry(at: slashActiveIndex)
                        } else {
                            Task { await submit() }
                        }
                    }
                    .onChange(of: input) { _, _ in
                        slashActiveIndex = 0
                        slashSkillsExpanded = false
                        slashCommandsExpanded = false
                    }
                    .onKeyPress { press in
                        if press.key == .tab, showSlashPopover, !slashMenuEntries.isEmpty {
                            activateSlashEntry(at: slashActiveIndex)
                            return .handled
                        }
                        if press.key == .return && !press.modifiers.contains(.shift) {
                            if showSlashPopover {
                                activateSlashEntry(at: slashActiveIndex)
                            } else {
                                Task { await submit() }
                            }
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(keys: [.upArrow]) { press in
                        guard press.modifiers.isEmpty else { return .ignored }
                        if showSlashPopover, !slashMenuEntries.isEmpty {
                            moveSlashSelection(by: -1)
                            return .handled
                        }
                        // History only when the caret has no line above it —
                        // multi-line drafts keep native caret movement
                        // (returning .handled unconditionally made arrows
                        // dead inside long drafts).
                        guard !input.contains("\n"),
                              let prev = store.previousHistory(from: input) else {
                            return .ignored
                        }
                        input = prev
                        return .handled
                    }
                    .onKeyPress(keys: [.downArrow]) { press in
                        guard press.modifiers.isEmpty else { return .ignored }
                        if showSlashPopover, !slashMenuEntries.isEmpty {
                            moveSlashSelection(by: 1)
                            return .handled
                        }
                        guard !input.contains("\n"),
                              let next = store.nextHistory(from: input) else {
                            return .ignored
                        }
                        input = next
                        return .handled
                    }
                }

                HStack(spacing: 9) {
                modeSelector
                modelSelector

                composerCommandMenu

                ContextUsageIndicator(
                    label: store.currentModelContextLabel,
                    fraction: store.contextUsageFraction
                )
                .help("Context usage")

                Spacer()

                reviewControls

                MicButton(voice: voiceInput, input: $input)

                Button {
                    chooseFiles()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Attach files")

                sessionActionButton
            }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: AppTheme.Layout.composerMaxWidth, alignment: .leading)
            .grokGlassSurface(
                cornerRadius: AppTheme.Radius.medium,
                emphasized: isFileDropTargeted,
                shadowed: false
            )
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFileDropTargeted) { providers in
                handleFileDrop(providers)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            sessionControlsDisclosure
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var sessionControlsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showSessionControls.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 6, height: 6)
                    Text(store.currentWorkspace?.displayName ?? "No project selected")
                        .lineLimit(1)
                    Text(connectionSubtitle)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(showSessionControls ? "Hide session controls" : "Session controls")
                        .foregroundStyle(.tertiary)
                    Image(systemName: showSessionControls ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showSessionControls ? "Hide session controls" : "Show session controls")

            if showSessionControls {
                projectStatusRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: AppTheme.Layout.composerMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var projectStatusRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let project = store.currentWorkspace {
                    Label(project.displayName, systemImage: "folder")
                        .lineLimit(1)
                    Button {
                        onSwitchBranch()
                        // Best-effort refresh once the checkout sheet has had time to act.
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            await refreshBranchLabel(project.path)
                        }
                    } label: {
                        Label(branchLabel, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    }
                    .buttonStyle(.plain)
                    .help("Branches & worktrees")
                    sessionReceiptMenu
                    agentStatusPill
                    browserStatusPill
                    computerUseStatusPill
                    if showWorkflowsPill {
                        workflowsStatusPill
                    }
                    tasksStatusPill
                    if memoryEnabled {
                        memoryStatusPill
                    }
                } else {
                    Label("No project selected", systemImage: "folder")
                }
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .task(id: store.currentWorkspace?.id) {
            await store.loadDiscoveredAgentsIfNeeded()
            cachedCustomSubagentNames = SubagentRoleStore.load().map(\.name)
            await refreshToolPillStatus()
            if let path = store.currentWorkspace?.path {
                await refreshBranchLabel(path)
            }
        }
        // Applied settings only change through flows that restart the connection,
        // so this re-probes the cached pill inputs exactly when they can differ.
        .task(id: store.connectionState) {
            await refreshToolPillStatus()
            if let path = store.currentWorkspace?.path {
                await refreshBranchLabel(path)
            }
        }
        // A finished turn may have moved HEAD (grok runs git); one read per message
        // beats the old read-on-every-render.
        .onChange(of: store.messages.count) { _, _ in
            guard let path = store.currentWorkspace?.path else { return }
            Task { await refreshBranchLabel(path) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .subagentRolesChanged)) { _ in
            cachedCustomSubagentNames = SubagentRoleStore.load().map(\.name)
        }
    }

    private func refreshBranchLabel(_ projectURL: URL) async {
        let label = await Task.detached(priority: .utility) {
            GitService.currentBranch(in: projectURL) ?? "No branch"
        }.value
        branchLabel = label
    }

    private var sessionReceiptMenu: some View {
        Menu {
            Section("Process and model receipt") {
                ForEach(store.sessionReceiptDetailLines.indices, id: \.self) { index in
                    Text(store.sessionReceiptDetailLines[index])
                }
            }
        } label: {
            Label(store.sessionReceiptCompactLabel, systemImage: "checkmark.seal")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Open generation-bound process and model details")
        .accessibilityLabel("Open session process and model details")
        .accessibilityValue(store.modelAccessibilityValue)
        .accessibilityIdentifier("grok-session-receipt")
    }

    private var agentStatusPill: some View {
        let effective = store.effectiveAgentSelection
        let title = store.effectiveAgentDisplayName
        let overriding = store.hasExplicitAgent

        return Menu {
            Section("This session's agent") {
                ForEach(GrokAgentProfiles.builtInOptions) { option in
                    Button {
                        Task { await store.setSessionAgent(option.id) }
                    } label: {
                        Label(option.title, systemImage: effective == option.id ? "checkmark" : "person")
                    }
                }
            }

            let discovered = store.discoveredAgents.map(\.name)
                .filter { name in !GrokAgentProfiles.builtInOptions.contains { $0.id == name } }
            if !discovered.isEmpty {
                Section("Discovered") {
                    ForEach(discovered, id: \.self) { name in
                        Button {
                            Task { await store.setSessionAgent(name) }
                        } label: {
                            Label(name, systemImage: effective == name ? "checkmark" : "person.crop.square")
                        }
                    }
                }
            }

            let excluded = Set(GrokAgentProfiles.builtInOptions.map(\.id) + store.discoveredAgents.map(\.name))
            let customSubagents = cachedCustomSubagentNames.filter { !excluded.contains($0) }
            if !customSubagents.isEmpty {
                Section("Run as custom role") {
                    ForEach(customSubagents, id: \.self) { name in
                        Button {
                            Task { await store.setSessionAgent(name) }
                        } label: {
                            Label(name, systemImage: effective == name ? "checkmark" : "person.2")
                        }
                    }
                }
            }

            Divider()

            Button {
                onOpenAgentSettings()
            } label: {
                Label("Open Agent Settings", systemImage: "gearshape")
            }
        } label: {
            Label(title, systemImage: "person.2.badge.gearshape")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.currentWorkspace == nil)
        .help(overriding
            ? "Session agent (overrides the default). Changing it restarts this session's grok."
            : "Session agent (follows the Settings default). Changing it restarts this session's grok.")
        .accessibilityLabel("Session agent")
    }

    private var showWorkflowsPill: Bool {
        workflowsEnabled
            || !store.workflowRuns.isEmpty
            || store.hasWorkflowCommand
            || store.hasDeepResearchCommand
    }

    private var workflowsStatusPill: some View {
        let runs = store.workflowRuns
        let count = runs.count
        let title = count > 0 ? "Workflows (\(count))" : "Workflows"

        return Menu {
            if runs.isEmpty {
                Button("No workflow runs") {}
                    .disabled(true)
            } else {
                Section("Runs") {
                    ForEach(runs) { run in
                        Menu(workflowMenuTitle(run)) {
                            if !run.phase.isEmpty {
                                Text("Phase: \(run.phase)")
                            }
                            if !run.progress.isEmpty {
                                Text(run.progress)
                            }
                            Text("Status: \(run.status)")
                            Divider()
                            if run.status.lowercased() != "paused" {
                                Button {
                                    Task { await store.pauseWorkflowRun(run.id) }
                                } label: {
                                    Label("Pause", systemImage: "pause.fill")
                                }
                            }
                            if run.status.lowercased() == "paused" {
                                Button {
                                    Task { await store.resumeWorkflowRun(run.id) }
                                } label: {
                                    Label("Resume", systemImage: "play.fill")
                                }
                            }
                            Button(role: .destructive) {
                                Task { await store.stopWorkflowRun(run.id) }
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                Task { await store.refreshWorkflowRuns() }
            } label: {
                Label("Refresh Runs", systemImage: "arrow.clockwise")
            }
            .disabled(store.isStreaming)

            Button {
                showSavedWorkflows = true
            } label: {
                Label("Saved Workflows…", systemImage: "doc.text")
            }

            if store.hasDeepResearchCommand {
                Button {
                    showDeepResearch = true
                } label: {
                    Label("Deep Research…", systemImage: "magnifyingglass")
                }
                .disabled(store.isStreaming)
            }

            Button {
                onOpenWorkflowSettings()
            } label: {
                Label("Open Workflow Settings", systemImage: "gearshape")
            }
        } label: {
            Label(title, systemImage: count > 0 ? "arrow.triangle.branch" : "arrow.triangle.branch")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.currentWorkspace == nil)
        .help("Background workflow runs for this session. Pause/stop via /workflow; saved scripts live in .grok/workflows.")
        .accessibilityLabel(title)
    }

    private func workflowMenuTitle(_ run: WorkflowRun) -> String {
        let status = run.status.isEmpty ? "run" : run.status
        let label = run.name.isEmpty ? run.id : run.name
        let short = label.count > 28 ? String(label.prefix(28)) + "…" : label
        return "\(short) · \(status)"
    }

    private static func parseWorkflowArgsJSON(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private var tasksStatusPill: some View {
        let activities = store.backgroundActivities
        let scheduled = activities.filter { $0.kind == .scheduled }
        let background = activities.filter { $0.kind == .backgroundCommand }
        let monitors = activities.filter { $0.kind == .monitor }
        let subagents = activities.filter { $0.kind == .subagent }
        let count = activities.count
        let available = store.hasLoopCommand
        let title = count > 0 ? "Tasks (\(count))" : "Tasks"

        return Menu {
            if activities.isEmpty {
                Button("No background tasks") {}
                    .disabled(true)
            } else {
                if !scheduled.isEmpty {
                    Section("Scheduled") {
                        ForEach(scheduled) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
                if !background.isEmpty {
                    Section("Background commands") {
                        ForEach(background) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
                if !monitors.isEmpty {
                    Section("Monitors") {
                        ForEach(monitors) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
                if !subagents.isEmpty {
                    Section("Subagents") {
                        ForEach(subagents) { activity in
                            backgroundActivityMenu(activity)
                        }
                    }
                }
            }

            Divider()

            Button {
                Task { await store.refreshScheduledTasks() }
            } label: {
                Label("Refresh Tasks", systemImage: "arrow.clockwise")
            }
            .disabled(store.isStreaming)

            Button("Type /loop <interval> <prompt> to schedule") {}
                .disabled(true)
        } label: {
            Label(title, systemImage: count > 0 ? "clock.badge.checkmark" : "clock")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.currentWorkspace == nil)
        .help(available
            ? "Background tasks observed in this session (scheduled, shells, monitors, subagents)."
            : "Background tasks mirror — refresh to query grok.")
        .accessibilityLabel("Background tasks")
    }

    @ViewBuilder
    private func backgroundActivityMenu(_ activity: BackgroundActivity) -> some View {
        if activity.kind == .scheduled, let task = activity.scheduledTask {
            Menu(taskMenuTitle(task)) {
                Text(task.prompt.isEmpty ? "(no prompt)" : task.prompt)
                if let next = task.nextFireAt {
                    Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                }
                Divider()
                Button(role: .destructive) {
                    Task { await store.cancelScheduledTask(task.id) }
                } label: {
                    Label("Cancel Task", systemImage: "trash")
                }
            }
        } else {
            Menu(backgroundActivityTitle(activity)) {
                if !activity.detail.isEmpty {
                    Text(activity.detail)
                }
                if !activity.status.isEmpty {
                    Text("Status: \(activity.status)")
                }
            }
        }
    }

    private func backgroundActivityTitle(_ activity: BackgroundActivity) -> String {
        let label = activity.title
        let short = label.count > 32 ? String(label.prefix(32)) + "…" : label
        return activity.status.isEmpty ? short : "\(short) · \(activity.status)"
    }

    private var promptQueueBar: some View {
        HStack(spacing: 8) {
            Label("Queue (\(store.promptQueue.count))", systemImage: "tray.full")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(Array(store.promptQueue.enumerated()), id: \.offset) { index, prompt in
                    Menu(prompt.count > 40 ? String(prompt.prefix(40)) + "…" : prompt) {
                        Button("Send now") {
                            Task { _ = await store.sendQueuedPromptNow(at: index) }
                        }
                        Button("Remove", role: .destructive) {
                            store.removeQueuedPrompt(at: index)
                        }
                    }
                }
            } label: {
                Text("Queued prompts")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var createSkillSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Skill")
                .font(.headline)
            TextField("Skill name", text: $createSkillName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showCreateSkill = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let name = createSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    showCreateSkill = false
                    Task { _ = await store.send("/create-skill \(name)") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(createSkillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var imagineSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Imagine")
                .font(.headline)
            TextField("Describe the image or video…", text: $imaginePrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            HStack {
                Spacer()
                Button("Cancel") { showImagine = false }
                    .keyboardShortcut(.cancelAction)
                Button("Send /imagine") {
                    let prompt = imaginePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !prompt.isEmpty else { return }
                    showImagine = false
                    Task { _ = await store.send("/imagine \(prompt)") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(imaginePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func taskMenuTitle(_ task: ScheduledTask) -> String {
        let interval = task.intervalHuman.isEmpty ? "task" : task.intervalHuman
        let prompt = task.prompt.isEmpty ? task.id : task.prompt
        let shortPrompt = prompt.count > 32 ? String(prompt.prefix(32)) + "…" : prompt
        return "\(interval): \(shortPrompt)"
    }

    // Only shown while cross-session memory is enabled (see `projectStatusRow`); the pill label
    // is just "Memory" — an off state isn't surfaced because the pill is hidden when disabled.
    private var memoryStatusPill: some View {
        Menu {
            Button {
                showMemoryBrowser = true
            } label: {
                Label("Browse Memory Files…", systemImage: "folder")
            }

            Button {
                memoryNoteText = ""
                showRememberPrompt = true
            } label: {
                Label("Remember…", systemImage: "text.badge.plus")
            }

            Divider()

            Button {
                onOpenMemorySettings()
            } label: {
                Label("Open Memory Settings", systemImage: "gearshape")
            }
        } label: {
            Label("Memory", systemImage: "brain.head.profile")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.currentWorkspace == nil)
        .help("Cross-session memory is on. Browse files, save a note, or open Memory settings.")
        .accessibilityLabel("Memory")
    }

    private var rememberPromptSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remember a Note")
                .font(.headline)
            Text("Saved to your global memory so Grok can recall it in future sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $memoryNoteText)
                .font(.body)
                .frame(minWidth: 380, minHeight: 120)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.large).stroke(Color(nsColor: .separatorColor)))
            HStack {
                Spacer()
                Button("Cancel") { showRememberPrompt = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    _ = store.remember(memoryNoteText)
                    showRememberPrompt = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(memoryNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    /// Filesystem-derived pill inputs, cached so the status row's render loop stops
    /// stat-ing helper paths on every body evaluation (they only change after an
    /// Apply, which restarts the connection and re-triggers the refresh task).
    struct ToolPillStatus {
        var browserIssue: String?
        var browserRuntimeMode: BrowserRuntimeMode = .managed
        var canChooseRuntime = false
        var computerUseIssue: String?
    }

    nonisolated static func computeToolPillStatus() -> ToolPillStatus {
        let browserSettings = BrowserSettingsStore.load()
        let browserBaseReady = AgentBrowserService.bridgeScriptURL() != nil
            && AgentBrowserService.executableURL() != nil
        let managedReady = AgentBrowserService.browserRuntimeConfigurationIssue(settings: browserSettings, mode: .managed) == nil
        let externalReady = AgentBrowserService.browserRuntimeConfigurationIssue(settings: browserSettings, mode: .external) == nil
        return ToolPillStatus(
            browserIssue: AgentBrowserService.browserToolsConfigurationIssue(settings: browserSettings),
            browserRuntimeMode: browserSettings.runtimeMode,
            canChooseRuntime: browserBaseReady && (managedReady || externalReady),
            computerUseIssue: ComputerUseService.configurationIssue(settings: ComputerUseSettingsStore.load())
        )
    }

    private func refreshToolPillStatus() async {
        let status = await Task.detached(priority: .utility) {
            ChatView.computeToolPillStatus()
        }.value
        toolPillStatus = status
    }

    private var browserStatusPill: some View {
        let configurationIssue = toolPillStatus.browserIssue
        let canChooseRuntime = toolPillStatus.canChooseRuntime
        let runtimeMode = toolPillStatus.browserRuntimeMode
        let isConfigured = configurationIssue == nil
        let needsSetup = browserToolsEnabled && !isConfigured
        let title = needsSetup ? "Browser Setup Needed" : "Browser Tools"
        let icon = browserToolsEnabled && isConfigured ? "globe.badge.chevron.backward" : "globe"
        return Menu {
            if browserToolsEnabled || isConfigured {
                Button(browserToolsEnabled ? "Turn Browser Tools Off" : "Turn Browser Tools On") {
                    onToggleBrowserTools()
                }
            }

            if canChooseRuntime {
                Divider()

                Button {
                    onSelectBrowserRuntime(.managed)
                } label: {
                    Label("Managed Browser Runtime", systemImage: runtimeMode == .managed ? "checkmark" : "shippingbox")
                }

                Button {
                    onSelectBrowserRuntime(.external)
                } label: {
                    Label("Existing Chromium Browser", systemImage: runtimeMode == .external ? "checkmark" : "globe")
                }
            }

            if let configurationIssue {
                Button(configurationIssue) {}
                    .disabled(true)
            }

            Divider()

            Button {
                onOpenBrowserSettings()
            } label: {
                Label("Open Browser Settings", systemImage: "gearshape")
            }
        } label: {
            Group {
                if needsSetup {
                    Label(title, systemImage: icon)
                } else {
                    Image(systemName: icon)
                        .accessibilityLabel(title)
                }
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .foregroundStyle(needsSetup ? Color.primary : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(browserStatusHelp(isConfigured: isConfigured, issue: configurationIssue))
    }

    private func browserStatusHelp(isConfigured: Bool, issue: String?) -> String {
        if !isConfigured {
            return issue ?? "Finish browser setup in Settings before using the quick toggle."
        }
        return browserToolsEnabled
            ? "Disable browser MCP tools and restart the Grok connection."
            : "Enable browser MCP tools and restart the Grok connection."
    }

    private var computerUseStatusPill: some View {
        let configurationIssue = toolPillStatus.computerUseIssue
        let isConfigured = configurationIssue == nil
        let needsSetup = computerUseEnabled && !isConfigured
        let title = needsSetup ? "Computer Use Setup Needed" : "Computer Use"
        let icon = computerUseEnabled && isConfigured ? "desktopcomputer.badge.checkmark" : "desktopcomputer"
        return Menu {
            if computerUseEnabled || isConfigured {
                Button(computerUseEnabled ? "Turn Computer Use Off" : "Turn Computer Use On") {
                    onToggleComputerUse()
                }
            }

            if let configurationIssue {
                Button(configurationIssue) {}
                    .disabled(true)
            } else if !computerUseEnabled {
                Button("Requires Accessibility permission") {}
                    .disabled(true)
            }

            Divider()

            Button {
                onOpenComputerUseSettings()
            } label: {
                Label("Open Computer Use Settings", systemImage: "gearshape")
            }
        } label: {
            Group {
                if needsSetup {
                    Label(title, systemImage: icon)
                } else {
                    Image(systemName: icon)
                        .accessibilityLabel(title)
                }
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .foregroundStyle(needsSetup ? Color.primary : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(computerUseStatusHelp(isConfigured: isConfigured, issue: configurationIssue))
    }

    private func computerUseStatusHelp(isConfigured: Bool, issue: String?) -> String {
        if !isConfigured {
            return issue ?? "Finish Computer Use setup in Settings before using the quick toggle."
        }
        return computerUseEnabled
            ? "Disable Computer Use MCP tools and restart the Grok connection."
            : "Enable Computer Use MCP tools if Accessibility permission is ready."
    }

    @ViewBuilder
    private var sessionActionButton: some View {
        if store.isStreaming {
            Button {
                store.stop()
            } label: {
                // An indeterminate ProgressView here invalidated the entire transcript's
                // LazyVStack every animation frame. A long web/tool wait could therefore
                // peg one CPU core and make every nearby control miss clicks.
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop session (⌘.)")
            .keyboardShortcut(".", modifiers: .command)
        } else {
            Button {
                Task { await submit() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .frame(width: ComposerControlMetrics.minimumHitTarget, height: ComposerControlMetrics.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.continuityBlocksSend
                ? "Send is blocked until conversation continuity is resolved."
                : "Send message")
            .accessibilityLabel(store.continuityBlocksSend
                ? "Send blocked by conversation continuity"
                : "Send message")
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.hasVisibleFileAttachments ||
                      store.currentWorkspace == nil ||
                      store.authRequiredMessage != nil ||
                      store.continuityBlocksSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    @ViewBuilder
    private var reviewControls: some View {
        if reviewFileCount > 0 {
            Button {
                onToggleReview()
            } label: {
                Label(
                    "\(reviewFileCount) Changed \(reviewFileCount == 1 ? "File" : "Files")",
                    systemImage: "doc.on.doc"
                )
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(isReviewVisible ? "Hide changed files" : "Show changed files")
        }
    }

    private var modeSelector: some View {
        Menu {
            ForEach(store.availableModes, id: \.rawValue) { mode in
                Button {
                    store.setMode(mode)
                } label: {
                    modeMenuRow(
                        icon: iconName(for: mode),
                        title: displayName(for: mode),
                        isSelected: store.currentMode == mode
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: iconName(for: store.currentMode))
                    .font(.caption.weight(.semibold))
                    .frame(width: 14)
                Text(displayName(for: store.currentMode))
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: ComposerControlMetrics.minimumHitTarget)
            .contentShape(Rectangle())
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Change agent mode")
        .accessibilityLabel("Agent mode")
        .accessibilityValue(displayName(for: store.currentMode))
        .accessibilityIdentifier("grok-mode-selector")
    }

    private func modeMenuRow(icon: String, title: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16, alignment: .center)
            Text(title)
            Spacer(minLength: 16)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
            }
        }
    }

    private func displayName(for mode: AgentMode) -> String {
        switch mode.rawValue {
        case "plan": return "Plan"
        case "yolo": return "YOLO"
        default: return "Agent"
        }
    }

    private func iconName(for mode: AgentMode) -> String {
        switch mode.rawValue {
        case "plan": return "list.bullet.indent"
        case "yolo": return "bolt.fill"
        default: return "infinity"
        }
    }

    private var modelSelector: some View {
        Menu {
            Section("Model") {
                ForEach(store.availableModels, id: \.self) { modelId in
                    Button {
                        store.setModel(modelId)
                    } label: {
                        HStack {
                            Text(store.modelDisplayName(modelId))
                            if store.currentModel == modelId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityIdentifier("grok-model-option-\(modelId)")
                    .disabled(store.isModelRequestPending)
                }
            }

            if store.currentModelSupportsReasoningEffort {
                Divider()
                Menu {
                    ForEach(ReasoningEffortLevel.menuCases) { level in
                        Toggle(
                            level.displayName,
                            isOn: Binding(
                                get: { store.currentReasoningEffort == level.rawValue },
                                set: { selected in
                                    if selected {
                                        requestReasoningEffortChange(to: level.rawValue)
                                    }
                                }
                            )
                        )
                        .disabled(store.isStreaming || store.currentWorkspace == nil)
                        .accessibilityIdentifier("grok-effort-option-\(level.rawValue)")
                    }
                } label: {
                    Text("Effort · \(currentReasoningEffortLabel)")
                }
            } else if store.isCurrentModelCustom {
                Text("Reasoning effort unavailable")
            }
        } label: {
            HStack(spacing: 4) {
                Text(modelSelectorLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 7)
            .frame(minHeight: ComposerControlMetrics.minimumHitTarget)
            .contentShape(Rectangle())
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Model and reasoning effort")
        .accessibilityValue(store.modelAccessibilityValue)
        .accessibilityIdentifier("grok-model-effort-selector")
        .help(modelSelectorHelp)
    }

    private var modelSelectorLabel: String {
        store.modelSelectorDisplayLabel
    }

    private var currentReasoningEffortLabel: String {
        ComposerModelMenuLayout.effortDisplayName(storedValue: store.currentReasoningEffort)
    }

    private var modelSelectorHelp: String {
        if store.isModelRequestPending {
            return "A model request is pending; other model choices are temporarily unavailable"
        }
        if store.isStreaming {
            return "Select model; wait for the current turn to finish before changing reasoning effort"
        }
        if !store.currentModelSupportsReasoningEffort {
            return "Model selector; reasoning effort is off for this custom model"
        }
        return "Model and reasoning effort"
    }

    private func requestReasoningEffortChange(to effort: String) {
        guard store.currentModelSupportsReasoningEffort else { return }
        guard effort != store.currentReasoningEffort else { return }
        guard store.currentWorkspace != nil, !store.isStreaming else { return }
        if store.needsReasoningEffortConfirmation(for: effort) {
            pendingReasoningEffortChange = effort
        } else {
            Task { await store.applyReasoningEffort(effort, strategy: .restart) }
        }
    }

    private func handleComposerChip(_ command: SlashCommand) async {
        switch command.name {
        case "imagine", "imagine-video":
            showImagine = true
        case "deep-research":
            showDeepResearch = true
        default:
            _ = await store.send("/\(command.name)")
            inputFocused = true
        }
    }

    private func submit() async {
        let submittedDraft = input
        let text = submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let accepted = await store.send(text)
        input = ComposerSubmissionPolicy.draftAfterSubmission(
            currentDraft: input,
            submittedDraft: submittedDraft,
            accepted: accepted
        )
        inputFocused = true
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = fileURL(from: item)
                guard let url else { return }
                Task { @MainActor in
                    appendDroppedFile(url)
                }
            }
        }
        return true
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Attach"
        if panel.runModal() == .OK {
            for url in panel.urls {
                appendDroppedFile(url)
            }
        }
    }

    private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

    @MainActor
    private func appendDroppedFile(_ url: URL) {
        store.addFileAttachment(path: url.path)
        inputFocused = true
    }

    private func pickSlashCommand(_ command: SlashCommand) {
        guard let match = slashMatch else { return }
        input = SlashAutocomplete.apply(command: command, to: input, matchRange: match.range)
        inputFocused = true
    }

    private func moveSlashSelection(by delta: Int) {
        let count = slashMenuEntries.count
        guard count > 0 else { return }
        slashActiveIndex = (slashActiveIndex + delta + count) % count
    }

    private func activateSlashEntry(at index: Int) {
        guard slashMenuEntries.indices.contains(index) else { return }
        switch slashMenuEntries[index] {
        case .command(let command):
            pickSlashCommand(command)
        case .showMoreSkills:
            slashSkillsExpanded = true
            clampSlashActiveIndex()
        case .showMoreCommands:
            slashCommandsExpanded = true
            clampSlashActiveIndex()
        }
    }

    private func clampSlashActiveIndex() {
        let count = slashMenuEntries.count
        guard count > 0 else {
            slashActiveIndex = 0
            return
        }
        slashActiveIndex = min(slashActiveIndex, count - 1)
    }

}

// MARK: - Quick Start

private struct QuickStartChip: View {
    let item: QuickStartPrompt
    var onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                isHovered ? AppTheme.Palette.surfaceHover : AppTheme.Palette.canvas,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                    .stroke(isHovered ? AppTheme.Palette.glassBorderStrong : AppTheme.Palette.glassBorder)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.prompt)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

}

// MARK: - Context Usage

private struct ContextUsageIndicator: View {
    let label: String
    let fraction: Double

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(0.04, fraction))
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }
}

// MARK: - Auth Banner

/// Shown when a streaming turn has produced no ACP events for two minutes. Nothing is
/// cancelled automatically — a long tool run and a wedged process look identical from
/// outside, so the user decides.
private struct TurnStalledBanner: View {
    let since: Date
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Grok hasn't sent anything since \(since.formatted(date: .omitted, time: .shortened)). It may be mid-tool-run, or stuck.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Stop turn", action: onStop)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.small).fill(AppTheme.Palette.glassTint))
        .padding(.horizontal, 20)
        .accessibilityLabel("Turn may be stalled")
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

private struct SessionContinuityBanner: View {
    let status: SessionContinuityStatus
    let headline: String
    let message: String
    let details: String
    let onContinueAsNew: () -> Void
    let onRelink: () -> Void

    @State private var showsDetails = false
    @State private var confirmsContinueAsNew = false

    private var color: Color {
        switch status {
        case .diverged, .compositeSuspected, .backendMissing, .verificationIncomplete:
            return .orange
        case .verifying:
            return .secondary
        case .localOnly, .backendOnly, .verified, .recoveryForked:
            return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: status == .verifying ? "checkmark.shield" : "exclamationmark.shield")
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.caption.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            DisclosureGroup("View redacted continuity details", isExpanded: $showsDetails) {
                Text(details)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            .font(.caption)
            if [.diverged, .compositeSuspected, .backendMissing, .verificationIncomplete].contains(status) {
                HStack(spacing: 8) {
                    Button("Continue as New") {
                        confirmsContinueAsNew = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityHint(
                        "Keeps the local transcript and creates a new backend only when you next send."
                    )
                    Button("Relink…", action: onRelink)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityHint(
                            "Reviews provenance-safe candidate histories before any binding changes."
                        )
                }
            }
        }
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .stroke(color.opacity(0.24), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headline)
        .accessibilityValue(message)
        .accessibilityHint("Send remains blocked when the saved backend cannot be verified. Your local transcript is unchanged.")
        .confirmationDialog(
            "Continue this transcript as a new conversation?",
            isPresented: $confirmsContinueAsNew,
            titleVisibility: .visible
        ) {
            Button("Continue as New", role: .destructive, action: onContinueAsNew)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Your local messages stay in this tab. The previous backend is preserved, and no new backend starts until you send."
            )
        }
    }
}

private struct SessionRecoveryReviewSheet: View {
    @Bindable var store: ChatStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review candidate histories")
                        .font(.title3.weight(.semibold))
                    Text("Candidates are read-only until you explicitly Relink a verified match.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }

            if store.isLoadingRecoveryCandidates {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking recent histories in this project…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.recoveryCandidateError {
                ContentUnavailableView(
                    "Candidate review unavailable",
                    systemImage: "exclamationmark.shield",
                    description: Text(error)
                )
                Button("Retry") {
                    Task { await store.reviewRecoveryCandidates() }
                }
            } else if store.recoveryCandidates.isEmpty {
                ContentUnavailableView(
                    "No provenance-safe candidates",
                    systemImage: "link.badge.plus",
                    description: Text(
                        "No recent history has enough evidence to verify this transcript. Continue as New remains the safe recovery."
                    )
                )
            } else {
                List(store.recoveryCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(candidate.redactedBackendID)
                                .font(.body.monospaced())
                            Text(candidate.isRelinkable ? "Verified candidate" : "Review only")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(candidate.isRelinkable ? .green : .orange)
                            Spacer()
                            Button("Relink") {
                                Task {
                                    if await store.relink(to: candidate) {
                                        onClose()
                                    }
                                }
                            }
                            .disabled(!candidate.isRelinkable)
                        }
                        Text(
                            "\(candidate.workspaceName) · \(candidate.modelID ?? "model unknown") · last active \(candidate.lastActivity.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(
                            "\(candidate.matchingTurnCount) matching turns · \(candidate.mismatchCount) mismatched rows · \(candidate.localMessageCount) local / \(candidate.backendMessageCount) backend rows"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if candidate.quarantinedRowCount > 0 {
                            Text("Mixed or unknown provenance is quarantined and cannot verify a binding.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if !candidate.isRelinkable {
                            Text("Shared prompts are evidence for review, not identity proof.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(
                        "Backend \(candidate.redactedBackendID), \(candidate.isRelinkable ? "verified candidate" : "review only")"
                    )
                    .accessibilityValue(
                        "\(candidate.matchingTurnCount) matching turns, \(candidate.mismatchCount) mismatched rows"
                    )
                }
            }
        }
        .padding(20)
        .frame(minWidth: 650, minHeight: 430)
        .accessibilityElement(children: .contain)
    }
}

private struct ModelSwitchBanner: View {
    let message: String
    var canStartNewSession: Bool = false
    var onStartNewSession: () -> Void = {}
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            if canStartNewSession {
                Button("Start New Session", action: onStartNewSession)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

struct AuthBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                Text("Authentication Required")
                    .font(.headline)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    openTerminalForLogin()
                } label: {
                    Label("Open Terminal & Run `grok login`", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    copyLoginCommand()
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                if let onRetry {
                    Button {
                        onRetry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func openTerminalForLogin() {
        // Use AppleScript to open Terminal and run the login command
        let script = """
        tell application "Terminal"
            activate
            do script "grok login"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                // Fallback: just open Terminal
                openTerminalApp()
            }
        } else {
            openTerminalApp()
        }
    }

    private func openTerminalApp() {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(terminalURL)
    }

    private func copyLoginCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("grok login", forType: .string)
    }
}

// MARK: - Permission Card with Diff Preview

struct PermissionCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let permission: PermissionRequest
    let effectivePermissionMode: GrokPermissionMode
    let onRespond: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: permission.toolCall.isEdit ? "doc.text" : "terminal")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tool approval required")
                        .font(.subheadline.weight(.semibold))
                    Text(permission.toolCall.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(permissionPolicyExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if permission.toolCall.isEdit, let path = permission.toolCall.filePath {
                HStack {
                    Text("\(path) — proposed edit")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("open diff preview →") {
                        openNativeDiffPreview(permission.toolCall)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } else if permission.toolCall.isExecute, let cmd = permission.toolCall.command {
                Text("Command: \(cmd)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                ForEach(permission.options) { option in
                    Button(option.name) {
                        onRespond(option.id)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .transition(.opacity)
        .animation(reduceMotion ? nil : .spring(response: 0.3), value: permission.id)
    }

    private var permissionPolicyExplanation: String {
        "Effective live process policy: \(effectivePermissionMode.displayName). This tool will not run until you choose an option; explicit deny rules still win."
    }

    private func openNativeDiffPreview(_ toolCall: ToolCall) {
        guard let path = toolCall.filePath,
              let proposed = toolCall.proposedContent else { return }
        // File writes + process spawn have no business on the main actor.
        Task.detached(priority: .userInitiated) {
            Self.launchNativeDiffPreview(path: path, proposed: proposed)
        }
    }

    private nonisolated static func launchNativeDiffPreview(path: String, proposed: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let oldURL = tempDir.appendingPathComponent("grok-old-\(UUID().uuidString).txt")
        let newURL = tempDir.appendingPathComponent("grok-new-\(UUID().uuidString).txt")

        do {
            // Try to get current content as "old"
            let oldContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            try oldContent.write(to: oldURL, atomically: true, encoding: .utf8)
            try proposed.write(to: newURL, atomically: true, encoding: .utf8)

            // Deeper: use opendiff (FileMerge) or Xcode for native diff
            let process = Process()
            if FileManager.default.fileExists(atPath: "/usr/bin/opendiff") {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/opendiff")
                process.arguments = [oldURL.path, newURL.path]
            } else {
                // Fallback to opening both or use VS Code if available
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Xcode", oldURL.path, newURL.path]
            }
            try process.run()
        } catch {
            // Silent fallback: the native diff is a convenience, not a required path.
        }
    }
}
