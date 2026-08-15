import SwiftUI

/// Workbench header chrome. ChatView still owns Tasks / Review / Run inspector
/// state; this view only lays out the shared controls and project menu.
struct ChatTopBar<TasksStatus: View, ReviewToggle: View, InspectorToggle: View>: View {
    @Bindable var store: ChatStore
    let sessionTitle: String
    let isSidebarVisible: Bool
    var onToggleSidebar: () -> Void
    var onBrowseSessions: () -> Void
    var onOpenDashboard: () -> Void
    var onForkSession: () -> Void
    var onSwitchBranch: () -> Void
    var onOpenProjectIn: (ProjectOpenTarget) -> Void
    var onOpenSettings: () -> Void
    @Binding var showSetGoal: Bool
    @Binding var createSkillName: String
    @Binding var showCreateSkill: Bool
    let tasksStatus: TasksStatus
    let reviewToggle: ReviewToggle
    let inspectorToggle: InspectorToggle

    init(
        store: ChatStore,
        sessionTitle: String,
        isSidebarVisible: Bool,
        onToggleSidebar: @escaping () -> Void,
        onBrowseSessions: @escaping () -> Void,
        onOpenDashboard: @escaping () -> Void,
        onForkSession: @escaping () -> Void,
        onSwitchBranch: @escaping () -> Void,
        onOpenProjectIn: @escaping (ProjectOpenTarget) -> Void,
        onOpenSettings: @escaping () -> Void,
        showSetGoal: Binding<Bool>,
        createSkillName: Binding<String>,
        showCreateSkill: Binding<Bool>,
        @ViewBuilder tasksStatus: () -> TasksStatus,
        @ViewBuilder reviewToggle: () -> ReviewToggle,
        @ViewBuilder inspectorToggle: () -> InspectorToggle
    ) {
        self.store = store
        self.sessionTitle = sessionTitle
        self.isSidebarVisible = isSidebarVisible
        self.onToggleSidebar = onToggleSidebar
        self.onBrowseSessions = onBrowseSessions
        self.onOpenDashboard = onOpenDashboard
        self.onForkSession = onForkSession
        self.onSwitchBranch = onSwitchBranch
        self.onOpenProjectIn = onOpenProjectIn
        self.onOpenSettings = onOpenSettings
        self._showSetGoal = showSetGoal
        self._createSkillName = createSkillName
        self._showCreateSkill = showCreateSkill
        self.tasksStatus = tasksStatus()
        self.reviewToggle = reviewToggle()
        self.inspectorToggle = inspectorToggle()
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(GrokChromeButtonStyle())
            .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")
            .accessibilityLabel(isSidebarVisible ? "Hide sidebar" : "Show sidebar")

            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(sessionTitle)
                .font(AppTheme.Typography.captionStrong)
                .lineLimit(1)

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

                    // Branch/worktree switching relocated here from the deleted
                    // composer project-status row (Codex parity Slice 4).
                    Button("Branches & Worktrees…", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                        onSwitchBranch()
                    }

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

            tasksStatus

            Spacer()

            reviewToggle

            inspectorToggle

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(GrokChromeButtonStyle())
            .help("Settings")
            .accessibilityLabel("Open Settings")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(AppTheme.Palette.canvas)
        .overlay(alignment: .bottom) { Divider() }
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workbench controls")
        .accessibilitySortPriority(4)
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
}
