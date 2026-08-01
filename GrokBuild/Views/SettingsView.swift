import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum SettingsTab: String, Hashable, CaseIterable, Identifiable {
    case agents
    case models
    case memory
    case workflows
    case browser
    case computerUse
    case mcpServers
    case skills
    case plugins
    case marketplace
    case hooks
    case compatibility
    case permissions
    case app

    var id: Self { self }

    var title: String {
        switch self {
        case .agents: return "Agents"
        case .models: return "Models"
        case .permissions: return "Permissions"
        case .memory: return "Memory"
        case .workflows: return "Workflows"
        case .browser: return "Browser"
        case .computerUse: return "Computer Use"
        case .mcpServers: return "MCP Servers"
        case .skills: return "Skills"
        case .plugins: return "Plugins"
        case .marketplace: return "Marketplace"
        case .compatibility: return "Compatibility"
        case .hooks: return "Hooks"
        case .app: return "App"
        }
    }

    var systemImage: String {
        switch self {
        case .agents: return "person.2"
        case .models: return "cpu"
        case .permissions: return "lock.shield"
        case .memory: return "brain"
        case .workflows: return "arrow.triangle.branch"
        case .browser: return "globe"
        case .computerUse: return "display"
        case .mcpServers: return "network"
        case .skills: return "hammer"
        case .plugins: return "shippingbox"
        case .marketplace: return "storefront"
        case .compatibility: return "square.stack.3d.up"
        case .hooks: return "link"
        case .app: return "gearshape"
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case grok
    case tools
    case extensions
    case controls
    case application

    var id: Self { self }

    var title: String {
        switch self {
        case .grok: return "Grok"
        case .tools: return "Tools"
        case .extensions: return "Extensions"
        case .controls: return "Controls"
        case .application: return "Application"
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .grok:
            return [.agents, .models, .memory]
        case .tools:
            return [.workflows, .browser, .computerUse]
        case .extensions:
            return [.mcpServers, .skills, .plugins, .marketplace, .hooks, .compatibility]
        case .controls:
            return [.permissions]
        case .application:
            return [.app]
        }
    }
}

struct SettingsView: View {
    @Bindable var store: ChatStore
    @Binding var selectedTab: SettingsTab
    var onBackToChat: () -> Void = {}
    var onConfigurationChanged: (ConfigurationChange) -> Void = { _ in }

    /// Tabs opened at least once stay mounted so pane `@State` / `.task` survive revisits.
    @State private var loadedTabs: Set<SettingsTab> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    onBackToChat()
                } label: {
                    Label("Session", systemImage: "chevron.left")
                }
                .buttonStyle(GrokChromeButtonStyle())
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

                Text("Settings")
                    .font(AppTheme.Typography.heading)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(AppTheme.Palette.chrome)

            HStack(spacing: 0) {
                settingsSidebar

                settingsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(AppTheme.Palette.canvas)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(AppTheme.Palette.canvas)
        .onAppear {
            SettingsTabKeepAlive.recordVisit(selectedTab, loaded: &loadedTabs)
        }
        .onChange(of: selectedTab) { _, tab in
            SettingsTabKeepAlive.recordVisit(tab, loaded: &loadedTabs)
        }
        .onExitCommand(perform: onBackToChat)
    }

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(SettingsSection.allCases) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title.uppercased())
                            .font(AppTheme.Typography.badge)
                            .tracking(0.7)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 2)

                        ForEach(section.tabs) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: tab.systemImage)
                                    .font(AppTheme.Typography.label)
                                    .frame(width: 16)
                                Text(tab.title)
                                    .font(selectedTab == tab ? AppTheme.Typography.captionStrong : AppTheme.Typography.caption)
                                Spacer(minLength: 0)
                            }
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                .fill(selectedTab == tab ? AppTheme.Palette.accentSoft : Color.clear)
                        )
                        .overlay {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                                    .stroke(AppTheme.Palette.glassBorder)
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .frame(width: AppTheme.Layout.settingsSidebarWidth)
        .background(AppTheme.Palette.sidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings navigation")
    }

    /// Keeps visited panes in the hierarchy (hidden when inactive) so state is not reset on tab change.
    private var settingsContent: some View {
        ZStack(alignment: .topLeading) {
            ForEach(SettingsTab.allCases) { tab in
                if SettingsTabKeepAlive.shouldMount(tab, selected: selectedTab, loaded: loadedTabs) {
                    settingsPane(for: tab)
                        .opacity(selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(selectedTab == tab)
                        .accessibilityHidden(selectedTab != tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    @ViewBuilder
    private func settingsPane(for tab: SettingsTab) -> some View {
        switch tab {
        case .agents:
            AgentsSettingsPane(workspace: store.currentWorkspace) {
                Task { await store.reloadConfiguration() }
            }
            .settingsPaneColumn()

        case .models:
            CustomModelsSettingsPane(onConfigurationChanged: onConfigurationChanged)

        case .permissions:
            PermissionsSettingsPane {
                Task { await store.reloadConfiguration() }
            }

        case .memory:
            MemorySettingsPane {
                Task { await store.reloadConfiguration() }
            }

        case .workflows:
            WorkflowsSettingsPane {
                Task { await store.reloadConfiguration() }
            }

        case .browser:
            BrowserSettingsPane {
                Task { await store.reloadConfiguration() }
            }

        case .computerUse:
            ComputerUseSettingsPane {
                Task { await store.reloadConfiguration() }
            }

        case .mcpServers:
            MCPSettingsPane {
                Task { await store.reloadConfiguration() }
            }
            .settingsPaneColumn()

        case .skills:
            SkillsSettingsPane(workspace: store.currentWorkspace)
                .settingsPaneColumn()

        case .plugins:
            PluginsSettingsPane {
                Task { await store.reloadConfiguration() }
            }
            .settingsPaneColumn()

        case .marketplace:
            MarketplaceSettingsPane {
                Task { await store.reloadConfiguration() }
            }
            .settingsPaneColumn()

        case .compatibility:
            CompatibilitySettingsPane {
                Task { await store.reloadConfiguration() }
            }

        case .hooks:
            HooksSettingsPane(workspace: store.currentWorkspace)
                .settingsPaneColumn()

        case .app:
            AppUpdatesSettingsPane()
        }
    }
}

/// Pure helpers for Settings pane keep-alive (lazy mount + retain visited tabs).
enum SettingsTabKeepAlive {
    static func recordVisit(_ tab: SettingsTab, loaded: inout Set<SettingsTab>) {
        loaded.insert(tab)
    }

    static func shouldMount(_ tab: SettingsTab, selected: SettingsTab, loaded: Set<SettingsTab>) -> Bool {
        tab == selected || loaded.contains(tab)
    }
}

private func openPath(_ path: String) {
    let expanded = (path as NSString).expandingTildeInPath
    NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
}

private struct SettingsPaneHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.Typography.heading)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private func settingsPaneHeader(_ title: String, subtitle: String, systemImage: String) -> SettingsPaneHeader {
    SettingsPaneHeader(title: title, subtitle: subtitle, systemImage: systemImage)
}

/// A full-width macOS settings row with a small, consistently aligned switch.
///
/// SwiftUI's default switch hugs the intrinsic width of its label, which made
/// controls drift through the middle of otherwise identical cards. Giving the
/// copy a flexible column keeps every switch on one quiet trailing axis.
private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// Bounds and centers Settings content within the available detail area.
    /// Keeping one readable column prevents full-screen windows from turning
    /// every control into a stretched dashboard row.
    func centeredSettingsColumn() -> some View {
        self
            .frame(maxWidth: AppTheme.Layout.settingsContentMaxWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Gives list-based panes the same centered content column as the
    /// scroll-based Browser / Computer Use / Models panes.
    func settingsPaneColumn() -> some View {
        self
            .scrollContentBackground(.hidden)
            .centeredSettingsColumn()
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppTheme.Palette.canvas)
    }
}

private struct BrowserSettingsPane: View {
    let onConfigurationChanged: () -> Void

    @AppStorage(BrowserSettingsKeys.enabled) private var enabled = BrowserSettings.defaults.enabled
    @AppStorage(BrowserSettingsKeys.runtimeMode) private var runtimeMode = BrowserSettings.defaults.runtimeMode.rawValue
    @AppStorage(BrowserSettingsKeys.cdpURL) private var cdpURL = BrowserSettings.defaults.cdpURL
    @AppStorage(BrowserSettingsKeys.profileName) private var profileName = BrowserSettings.defaults.profileName
    @AppStorage(BrowserSettingsKeys.showBrowserWindow) private var showBrowserWindow = BrowserSettings.defaults.showBrowserWindow
    @AppStorage(BrowserSettingsKeys.externalBrowserAppID) private var externalBrowserAppID = BrowserSettings.defaults.externalBrowserAppID.rawValue
    @AppStorage(BrowserSettingsKeys.externalBrowserAppPath) private var externalBrowserAppPath = BrowserSettings.defaults.externalBrowserAppPath
    @AppStorage(BrowserSettingsKeys.autoStartExternalBrowser) private var autoStartExternalBrowser = BrowserSettings.defaults.autoStartExternalBrowser

    @State private var status = BrowserBackendStatus.unavailable
    @State private var externalStatus = ExternalBrowserStatus.unavailable(endpoint: "http://127.0.0.1:9222")
    @State private var isChecking = false
    @State private var isInstallingRuntime = false
    @State private var isStartingExternalBrowser = false
    @State private var installOutput: String?
    @State private var externalBrowserOutput: String?
    @State private var showBrowserSessionOptions = false
    @State private var showQuickPresets = false
    @State private var showDiagnosticsLog = false
    @State private var showRuntimeUninstallConfirmation = false
    @State private var appliedSettings = BrowserSettingsStore.loadApplied()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                browserToolsCard
                statusCard
                browserPresetsCard
                browserRuntimeCard
                applyCard
            }
            .centeredSettingsColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Palette.canvas)
        .task {
            normalizeExternalBrowserSelection()
            await refreshStatus()
        }
        .alert("Uninstall Managed Browser Runtime?", isPresented: $showRuntimeUninstallConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall Runtime", role: .destructive) {
                uninstallManagedRuntime()
            }
        } message: {
            Text("This removes the Chrome/Chromium runtime downloaded by `agent-browser install` from `~/.agent-browser/browsers`. The agent-browser CLI and saved settings are kept.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            settingsPaneHeader(
                "Browser Control",
                subtitle: "Let Grok work in a managed browser or an existing Chromium app.",
                systemImage: SettingsTab.browser.systemImage
            )
            statusBadge
        }
    }

    private var browserToolsCard: some View {
        settingsCard(title: "Browser Tools", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(
                    "Allow browser control",
                    subtitle: "Available in new and resumed sessions.",
                    isOn: $enabled
                )
            }
        }
    }

    private var statusCard: some View {
        settingsCard(title: "Browser Support", systemImage: status.isReady ? "checkmark.circle" : "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(browserStatusTitle, systemImage: browserStatusIcon)
                        .foregroundStyle(browserStatusColor)
                        .font(.headline)
                    Spacer()
                    Button(isChecking ? "Checking..." : "Run Diagnostics") {
                        Task { await refreshStatus() }
                    }
                    .disabled(isChecking)
                }

                if status.isReady {
                    Text("Browser support is ready. Choose a managed browser or connect an existing Chromium app below.")
                        .foregroundStyle(.secondary)

                } else if status.isInstalled {
                    Text("Browser support is installed. Add the managed runtime below for the recommended setup.")
                        .foregroundStyle(.secondary)

                } else {
                    Text("Install browser support before enabling this feature.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        installCommandRow(title: "Homebrew", command: "brew install agent-browser")
                        installCommandRow(title: "npm", command: "npm install -g agent-browser")
                    }

                }

                if let installOutput, !installOutput.isEmpty {
                    Text(installOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                }

                if let path = status.executablePath {
                    infoLine("Path", path)
                }
                if let version = status.version, !version.isEmpty {
                    infoLine("Version", version)
                }

                DisclosureGroup(isExpanded: $showDiagnosticsLog) {
                    Text(status.diagnostic.isEmpty ? "No diagnostics yet." : status.diagnostic)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } label: {
                    Label(showDiagnosticsLog ? "Hide diagnostics log" : "Show diagnostics log", systemImage: "doc.text.magnifyingglass")
                        .font(.callout.weight(.medium))
                }

                Button {
                    NSWorkspace.shared.open(URL(string: "https://agent-browser.dev")!)
                } label: {
                    Label("Open Browser Setup Guide", systemImage: "questionmark.circle")
                }
            }
        }
    }

    private var browserPresetsCard: some View {
        DisclosureGroup(isExpanded: $showQuickPresets) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose a starting configuration, then review and apply it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(BrowserPreset.allCases) { preset in
                    presetRow(preset)
                    if preset.id != BrowserPreset.allCases.last?.id { Divider() }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Presets", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }

    private func presetRow(_ preset: BrowserPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(preset.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Apply Preset") {
                    applyBrowserPreset(preset)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            Text(preset.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func applyBrowserPreset(_ preset: BrowserPreset) {
        let applied = preset.applied(to: currentSettings)
        runtimeMode = applied.runtimeMode.rawValue
        externalBrowserAppID = applied.externalBrowserAppID.rawValue
        externalBrowserAppPath = applied.externalBrowserAppPath
        cdpURL = applied.cdpURL
        profileName = applied.profileName
        showBrowserWindow = applied.showBrowserWindow
        autoStartExternalBrowser = applied.autoStartExternalBrowser
        normalizeExternalBrowserSelection()
    }

    private var browserRuntimeCard: some View {
        settingsCard(title: "Browser Runtime", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose where browser automation runs. Most users should use the managed browser runtime.")
                    .foregroundStyle(.secondary)

                browserRuntimeOption(
                    title: "Managed browser runtime",
                    subtitle: "Recommended. Uses a separate automation browser and leaves your normal profile alone.",
                    systemImage: "shippingbox.circle",
                    isSelected: selectedRuntimeMode == .managed
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(managedRuntimeStatusText, systemImage: status.isReady ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)

                        SettingsToggleRow(
                            "Show browser window while agents work",
                            subtitle: "Opens the managed automation browser visibly instead of keeping it headless. Apply and restart Grok after changing this.",
                            isOn: $showBrowserWindow
                        )

                        HStack {
                            Button("Use Managed Runtime") {
                                runtimeMode = BrowserRuntimeMode.managed.rawValue
                            }
                            .disabled(selectedRuntimeMode == .managed)

                            if status.isReady {
                                Button(isInstallingRuntime ? "Repairing..." : "Reinstall / Repair Runtime") {
                                    Task { await installBrowserRuntime() }
                                }
                                .disabled(!status.isInstalled || isInstallingRuntime)

                                Button("Uninstall Runtime...", role: .destructive) {
                                    showRuntimeUninstallConfirmation = true
                                }
                                .disabled(!AgentBrowserService.hasManagedRuntimeDirectory())
                            } else {
                                Button(isInstallingRuntime ? "Installing..." : "Install Managed Runtime") {
                                    Task { await installBrowserRuntime() }
                                }
                                .disabled(!status.isInstalled || isInstallingRuntime)
                            }

                            Button("Copy Install Command") {
                                copyToPasteboard("agent-browser install")
                            }
                        }

                        if !status.isInstalled {
                            Text("Install browser support before adding the managed runtime.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                browserRuntimeOption(
                    title: "Existing Chromium browser",
                    subtitle: "Optional. Use any Chromium-based browser you start yourself with remote debugging enabled, such as Chrome, Chromium, Brave, Edge, or Arc.",
                    systemImage: "macwindow.badge.plus",
                    isSelected: selectedRuntimeMode == .external
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GrokBuild can start a separate automation profile in the selected browser.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(externalBrowserStatusText, systemImage: externalStatus.isReachable ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)

                        settingRow("Browser app") {
                            Picker("", selection: $externalBrowserAppID) {
                                ForEach(externalBrowserChoices) { app in
                                    Text(app.displayName).tag(app.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: AppTheme.Layout.settingsControlWidth)
                        }

                        if installedKnownExternalBrowsers.isEmpty {
                            Text("No supported Chromium apps were found. Choose a custom app if one is installed elsewhere.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if selectedExternalBrowserApp == .custom {
                            settingRow("Custom app") {
                                HStack {
                                    TextField("Path to Chromium .app", text: $externalBrowserAppPath)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Choose...") {
                                        chooseExternalBrowserApp()
                                    }
                                }
                            }
                        }

                        SettingsToggleRow(
                            "Start this browser automatically when Grok starts",
                            subtitle: "Uses a separate GrokBuild profile, not your normal logged-in browser profile.",
                            isOn: $autoStartExternalBrowser
                        )

                        settingRow("CDP URL") {
                            TextField("For the command below: http://127.0.0.1:9222", text: $cdpURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text(externalBrowserLaunchCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))

                        if let externalBrowserOutput, !externalBrowserOutput.isEmpty {
                            Text(externalBrowserOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button("Use Existing Browser") {
                                runtimeMode = BrowserRuntimeMode.external.rawValue
                                cdpURL = defaultCDPURL
                                autoStartExternalBrowser = true
                            }

                            Button(isStartingExternalBrowser ? "Starting..." : "Start Browser Now") {
                                Task { await startExternalBrowser() }
                            }
                            .disabled(isStartingExternalBrowser)

                            Button("Check Status") {
                                Task { await refreshExternalBrowserStatus() }
                            }
                            .disabled(isChecking)

                            Button {
                                copyToPasteboard(externalBrowserLaunchCommand)
                            } label: {
                                Label("Copy Launch Command", systemImage: "doc.on.doc")
                            }

                            Button {
                                NSWorkspace.shared.open(URL(string: "https://developer.chrome.com/docs/devtools/remote-debugging/")!)
                            } label: {
                                Label("Open Setup Docs", systemImage: "questionmark.circle")
                            }
                        }
                    }
                }

                DisclosureGroup(isExpanded: $showBrowserSessionOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Use a named session only when you want browser state to persist separately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        settingRow("Session name") {
                            TextField("Optional named browser session", text: $profileName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Session Storage", systemImage: "slider.horizontal.3")
                        .font(.callout.weight(.medium))
                }
            }
        }
    }

    private var applyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apply changes")
                    .font(.headline)
                Text(hasPendingBrowserChanges ? "Restarts the active Grok connection." : "Browser settings are current.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply Changes") {
                appliedSettings = currentSettings
                BrowserSettingsStore.saveApplied(currentSettings)
                onConfigurationChanged()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasPendingBrowserChanges)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(hasPendingBrowserChanges ? AppTheme.Palette.surfaceHover : AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(hasPendingBrowserChanges ? AppTheme.Palette.glassBorderStrong : AppTheme.Palette.glassBorder)
        )
    }

    @MainActor
    private func refreshStatus() async {
        isChecking = true
        defer { isChecking = false }
        status = await AgentBrowserService.status()
        externalStatus = await AgentBrowserService.externalBrowserStatus(settings: currentSettings)
    }

    @MainActor
    private func installBrowserRuntime() async {
        isInstallingRuntime = true
        installOutput = "Running `agent-browser install`..."
        defer { isInstallingRuntime = false }

        do {
            let output = try await AgentBrowserService.installBrowserRuntime()
            installOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            await refreshStatus()
        } catch {
            installOutput = error.localizedDescription
        }
    }

    @MainActor private func uninstallManagedRuntime() {
        do {
            installOutput = try AgentBrowserService.uninstallManagedRuntime()
            Task { await refreshStatus() }
        } catch {
            installOutput = error.localizedDescription
        }
    }

    @MainActor
    private func startExternalBrowser() async {
        runtimeMode = BrowserRuntimeMode.external.rawValue
        if cdpURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cdpURL = defaultCDPURL
        }
        isStartingExternalBrowser = true
        externalBrowserOutput = "Starting \(selectedExternalBrowserApp.displayName) with a separate GrokBuild automation profile..."
        defer { isStartingExternalBrowser = false }

        do {
            externalStatus = try await AgentBrowserService.launchExternalBrowser(settings: currentSettings)
            externalBrowserOutput = externalStatus.diagnostic
        } catch {
            externalBrowserOutput = error.localizedDescription
            externalStatus = await AgentBrowserService.externalBrowserStatus(settings: currentSettings)
        }
    }

    @MainActor
    private func refreshExternalBrowserStatus() async {
        isChecking = true
        defer { isChecking = false }
        externalStatus = await AgentBrowserService.externalBrowserStatus(settings: currentSettings)
    }

    private func chooseExternalBrowserApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose Chromium Browser"
        panel.message = "Choose a Chromium-based browser app that supports Chrome DevTools Protocol."
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            externalBrowserAppID = ExternalBrowserAppID.custom.rawValue
            externalBrowserAppPath = url.path
        }
    }

    private var statusBadge: some View {
        let text = enabled ? (status.isReady ? "Ready" : "Setup needed") : "Disabled"

        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var selectedExternalBrowserApp: ExternalBrowserAppID {
        ExternalBrowserAppID(rawValue: externalBrowserAppID) ?? BrowserSettings.defaults.externalBrowserAppID
    }

    private var selectedRuntimeMode: BrowserRuntimeMode {
        BrowserRuntimeMode(rawValue: runtimeMode) ?? BrowserSettings.defaults.runtimeMode
    }

    private var installedKnownExternalBrowsers: [ExternalBrowserAppID] {
        ExternalBrowserAppID.allCases.filter { app in
            app != .custom && app.defaultAppURL != nil
        }
    }

    private var externalBrowserChoices: [ExternalBrowserAppID] {
        installedKnownExternalBrowsers + [.custom]
    }

    private func normalizeExternalBrowserSelection() {
        guard !externalBrowserChoices.contains(selectedExternalBrowserApp) else { return }
        externalBrowserAppID = installedKnownExternalBrowsers.first?.rawValue ?? ExternalBrowserAppID.custom.rawValue
    }

    private var externalBrowserLaunchCommand: String {
        AgentBrowserService.externalBrowserLaunchCommand(settings: currentSettings)
    }

    private var externalBrowserStatusText: String {
        if externalStatus.isReachable {
            return externalStatus.browserName.map { "External browser running: \($0)" }
                ?? "External browser running at \(externalStatus.endpoint)"
        }
        if selectedExternalBrowserApp == .custom && externalBrowserAppPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a Chromium app to start automatically"
        }
        return "External browser not running yet"
    }

    private var defaultCDPURL: String {
        "http://127.0.0.1:9222"
    }

    private var managedRuntimeStatusText: String {
        if status.isReady {
            return "Managed runtime installed and ready"
        }
        if status.isInstalled {
            return "Managed runtime not ready or not installed"
        }
        return "Install agent-browser CLI first"
    }

    private var currentSettings: BrowserSettings {
        BrowserSettings(
            enabled: enabled,
            runtimeMode: selectedRuntimeMode,
            cdpURL: cdpURL,
            profileName: profileName,
            showBrowserWindow: showBrowserWindow,
            externalBrowserAppID: ExternalBrowserAppID(rawValue: externalBrowserAppID)
                ?? BrowserSettings.defaults.externalBrowserAppID,
            externalBrowserAppPath: externalBrowserAppPath,
            autoStartExternalBrowser: autoStartExternalBrowser
        )
    }

    private var hasPendingBrowserChanges: Bool {
        currentSettings != appliedSettings
    }

    private var browserStatusTitle: String {
        if status.isReady { return "agent-browser ready" }
        if status.isInstalled { return "agent-browser setup needed" }
        return "agent-browser not installed"
    }

    private var browserStatusIcon: String {
        if status.isReady { return "checkmark.circle.fill" }
        if status.isInstalled { return "exclamationmark.triangle.fill" }
        return "xmark.circle.fill"
    }

    private var browserStatusColor: Color {
        .secondary
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }

    private func browserRuntimeOption<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(isSelected ? "Selected" : "Optional")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            content()
                .padding(.leading, 36)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(isSelected ? AppTheme.Palette.surfaceHover : AppTheme.Palette.glassTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(isSelected ? AppTheme.Palette.glassBorderStrong : AppTheme.Palette.glassBorder)
        )
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.caption)
    }

    private func installCommandRow(title: String, command: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                copyToPasteboard(command)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
    }
}

private struct PluginsSettingsPane: View {
    let onConfigurationChanged: () -> Void

    private let service = GrokCLIService()
    @State private var plugins: [GrokPluginInfo] = []
    @State private var installSource = ""
    @State private var trustInstall = false
    @State private var selectedDetails: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Plugins",
                    subtitle: "Manage installed plugins or add one from a trusted source.",
                    systemImage: SettingsTab.plugins.systemImage
                )
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            HStack {
                TextField("GitHub repo, Git URL, or local path", text: $installSource)
                Toggle("Trust", isOn: $trustInstall)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                Button("Install") {
                    Task { await installPlugin() }
                }
                .disabled(installSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            List {
                ForEach(plugins) { plugin in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.name)
                                    .font(.headline)
                                Text([plugin.version, plugin.scope, plugin.source].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(plugin.isEnabled ? "Enabled" : "Disabled")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if !plugin.description.isEmpty {
                            Text(plugin.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !plugin.componentSummary.isEmpty {
                            Text(plugin.componentSummary)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Menu {
                            Button(plugin.isEnabled ? "Disable" : "Enable") {
                                Task { await setPlugin(plugin, enabled: !plugin.isEnabled) }
                            }
                            Button("Details") {
                                Task { await loadDetails(plugin) }
                            }
                            Button("Update") {
                                Task { await updatePlugin(plugin) }
                            }
                            Button("Uninstall", role: .destructive) {
                                Task { await uninstallPlugin(plugin) }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 20, height: 20)
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                        .fixedSize()
                        .help("Plugin actions")
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if plugins.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Plugins",
                        systemImage: SettingsTab.plugins.systemImage,
                        description: Text("Install a plugin here or from Marketplace.")
                    )
                }
            }

            if let selectedDetails {
                Divider()
                Text("Details")
                    .font(.headline)
                ScrollView {
                    Text(selectedDetails)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
            }
        }
        .overlay(alignment: .bottom) {
            statusOverlay
        }
        .task { await refresh() }
    }

    private var statusOverlay: some View {
        VStack {
            if isLoading {
                ProgressView()
                    .padding(8)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            }
        }
    }

    private func header(_ text: String, systemImage: String) -> some View {
        HStack {
            Label(text, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    private func refresh() async {
        await perform {
            plugins = try await service.listPlugins()
        }
    }

    private func installPlugin() async {
        let source = installSource.trimmingCharacters(in: .whitespacesAndNewlines)
        await perform {
            try await service.installPlugin(source: source, trust: trustInstall)
            installSource = ""
            try await refreshAfterMutation()
        }
    }

    private func uninstallPlugin(_ plugin: GrokPluginInfo) async {
        await perform {
            try await service.uninstallPlugin(name: plugin.name, keepData: false)
            try await refreshAfterMutation()
        }
    }

    private func setPlugin(_ plugin: GrokPluginInfo, enabled: Bool) async {
        await perform {
            try await service.setPlugin(name: plugin.name, enabled: enabled)
            try await refreshAfterMutation()
        }
    }

    private func updatePlugin(_ plugin: GrokPluginInfo) async {
        await perform {
            try await service.updatePlugin(name: plugin.name)
            try await refreshAfterMutation()
        }
    }

    private func loadDetails(_ plugin: GrokPluginInfo) async {
        await perform {
            selectedDetails = try await service.pluginDetails(name: plugin.name)
        }
    }

    private func refreshAfterMutation() async throws {
        plugins = try await service.listPlugins()
        onConfigurationChanged()
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        // Rapid re-taps must not stack concurrent CLI mutations.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct HooksSettingsPane: View {
    let workspace: Workspace?

    private let service = GrokCLIService()
    @State private var hooks: [GrokHookInfo] = []
    @State private var filter = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredHooks: [GrokHookInfo] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return hooks }
        return hooks.filter {
            $0.event.localizedCaseInsensitiveContains(trimmed) ||
            $0.target.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourceType.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourcePath.localizedCaseInsensitiveContains(trimmed) ||
            $0.pluginName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Hooks",
                    subtitle: "Review the hooks available to this project.",
                    systemImage: SettingsTab.hooks.systemImage
                )
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            TextField("Search hooks", text: $filter)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(filteredHooks) { hook in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(hook.event.isEmpty ? "Unknown event" : hook.event)
                                .font(.headline)
                            if !hook.matcher.isEmpty {
                                Text(hook.matcher)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(sourceLabel(for: hook))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Text([hook.hookType, hook.vendor].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(hook.target)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        if !hook.sourcePath.isEmpty {
                            HStack {
                                Text(hook.sourcePath)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Open Source") {
                                    openPath(hook.sourcePath)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if hooks.isEmpty && !isLoading {
                    ContentUnavailableView("No Hooks", systemImage: "curlybraces", description: Text("Grok did not report any hooks for this project."))
                }
            }

            if isLoading { ProgressView() }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Text("Sources refresh automatically from Grok, Cursor, Claude, plugins, and the current project.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // Keyed to the workspace: a kept-alive pane must refetch after a project switch
        // instead of showing the old workspace's data until a manual Refresh.
        .task(id: workspace?.path) { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            hooks = try await service.listHooks(cwd: workspace?.path)
        } catch {
            // Clear so the empty/error state shows instead of a stale list
            // with a red caption under it.
            hooks = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func sourceLabel(for hook: GrokHookInfo) -> String {
        if !hook.pluginName.isEmpty { return "plugin: \(hook.pluginName)" }
        return hook.sourceType.isEmpty ? "unknown" : hook.sourceType
    }
}

private struct MarketplaceSettingsPane: View {
    let onConfigurationChanged: () -> Void

    private let service = GrokCLIService()
    @State private var availablePlugins: [GrokPluginInfo] = []
    @State private var installedPlugins: [GrokPluginInfo] = []
    @State private var marketplaceSources: [GrokMarketplaceSource] = []
    @State private var marketplaceSource = ""
    @State private var availableFilter = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredAvailablePlugins: [GrokPluginInfo] {
        let filter = availableFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return availablePlugins }
        return availablePlugins.filter {
            $0.name.localizedCaseInsensitiveContains(filter) ||
            $0.description.localizedCaseInsensitiveContains(filter) ||
            $0.marketplace.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Marketplace",
                    subtitle: "Browse and install plugins from trusted sources.",
                    systemImage: SettingsTab.marketplace.systemImage
                )
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            HStack {
                TextField("Marketplace Git URL or owner/repo", text: $marketplaceSource)
                Button("Add Source") {
                    Task { await addMarketplace() }
                }
                .disabled(marketplaceSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("Search available plugins", text: $availableFilter)
                .textFieldStyle(.roundedBorder)

            if !marketplaceSources.isEmpty {
                marketplaceSourcesCard
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !installedPlugins.isEmpty {
                        marketplaceSectionHeader("Installed", count: installedPlugins.count)
                        ForEach(Array(installedPlugins.enumerated()), id: \.element.id) { index, plugin in
                            marketplacePluginRow(plugin, showInstall: false)
                            if index < installedPlugins.count - 1 {
                                Divider()
                            }
                        }
                    }

                    marketplaceSectionHeader("Available", count: filteredAvailablePlugins.count)
                        .padding(.top, installedPlugins.isEmpty ? 0 : 16)
                    ForEach(Array(filteredAvailablePlugins.enumerated()), id: \.element.id) { index, plugin in
                        marketplacePluginRow(plugin, showInstall: true)
                        if index < filteredAvailablePlugins.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .overlay {
                if availablePlugins.isEmpty && installedPlugins.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Plugins",
                        systemImage: SettingsTab.marketplace.systemImage,
                        description: Text("Refresh the marketplace or add a trusted source.")
                    )
                }
            }

            if isLoading { ProgressView() }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .task { await refresh() }
    }

    private var marketplaceSourcesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Sources", systemImage: "square.stack.3d.up")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(marketplaceSources.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 8)

            ForEach(Array(marketplaceSources.enumerated()), id: \.element.id) { index, source in
                if index > 0 {
                    Divider()
                        .padding(.vertical, 7)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .font(.callout.weight(.medium))
                        Text(source.location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await removeMarketplace(source) }
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Remove source")
                }
            }
        }
        .padding(12)
        .grokGlassSurface()
    }

    @ViewBuilder
    private func marketplacePluginRow(_ plugin: GrokPluginInfo, showInstall: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.headline)
                    Text([plugin.marketplace, plugin.componentSummary].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if showInstall {
                    Button("Install") {
                        Task { await installAvailablePlugin(plugin) }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                } else {
                    Text(plugin.isEnabled ? "Enabled" : "Disabled")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !plugin.description.isEmpty {
                Text(plugin.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if !showInstall {
                Menu {
                    Button(plugin.isEnabled ? "Disable" : "Enable") {
                        Task { await setInstalledPlugin(plugin, enabled: !plugin.isEnabled) }
                    }
                    Button("Uninstall", role: .destructive) {
                        Task { await uninstallInstalledPlugin(plugin) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .help("Plugin actions")
            }
        }
        .padding(.vertical, 10)
    }

    private func marketplaceSectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    private func refresh() async {
        await perform {
            let allPlugins = try await service.listPlugins(includeAvailable: true)
            async let sources = service.listMarketplaceSources()
            availablePlugins = allPlugins.filter { $0.status == "available" }
            installedPlugins = allPlugins.filter { $0.status != "available" }
            marketplaceSources = try await sources
        }
    }

    private func setInstalledPlugin(_ plugin: GrokPluginInfo, enabled: Bool) async {
        await perform {
            try await service.setPlugin(name: plugin.name, enabled: enabled)
            try await refreshAfterMutation()
        }
    }

    private func uninstallInstalledPlugin(_ plugin: GrokPluginInfo) async {
        await perform {
            try await service.uninstallPlugin(name: plugin.name, keepData: false)
            try await refreshAfterMutation()
        }
    }

    private func installAvailablePlugin(_ plugin: GrokPluginInfo) async {
        await perform {
            try await service.installPlugin(source: plugin.name, trust: true)
            try await refreshAfterMutation()
        }
    }

    private func addMarketplace() async {
        let source = marketplaceSource.trimmingCharacters(in: .whitespacesAndNewlines)
        await perform {
            try await service.addMarketplaceSource(source)
            marketplaceSource = ""
            try await refreshAfterMutation()
        }
    }

    private func removeMarketplace(_ source: GrokMarketplaceSource) async {
        await perform {
            try await service.removeMarketplaceSource(source.location)
            try await refreshAfterMutation()
        }
    }

    private func refreshAfterMutation() async throws {
        let allPlugins = try await service.listPlugins(includeAvailable: true)
        availablePlugins = allPlugins.filter { $0.status == "available" }
        installedPlugins = allPlugins.filter { $0.status != "available" }
        marketplaceSources = try await service.listMarketplaceSources()
        onConfigurationChanged()
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        // Rapid re-taps must not stack concurrent CLI mutations.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct SkillsSettingsPane: View {
    let workspace: Workspace?

    private let service = GrokCLIService()
    @State private var skills: [GrokSkillInfo] = []
    @State private var filter = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filteredSkills: [GrokSkillInfo] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return skills }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.description.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourceType.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourcePath.localizedCaseInsensitiveContains(trimmed) ||
            $0.pluginName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Skills",
                    subtitle: "Review the skills available to Grok in this project.",
                    systemImage: SettingsTab.skills.systemImage
                )
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            TextField("Search skills", text: $filter)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(filteredSkills) { skill in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(skill.name)
                                .font(.headline)
                            if skill.userInvocable {
                                Text("/\(skill.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(sourceLabel(for: skill))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if !skill.description.isEmpty {
                            Text(skill.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }

                        if !skill.sourcePath.isEmpty {
                            HStack {
                                Spacer()
                                Button("Open source") {
                                    openPath(skill.sourcePath)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if skills.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Skills",
                        systemImage: SettingsTab.skills.systemImage,
                        description: Text("No skills are available for this project.")
                    )
                }
            }

            if isLoading { ProgressView() }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Text("Sources refresh automatically from this Mac and the current project.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: workspace?.path) { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            skills = try await service.listSkills(cwd: workspace?.path)
        } catch {
            skills = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func sourceLabel(for skill: GrokSkillInfo) -> String {
        if !skill.pluginName.isEmpty { return "plugin: \(skill.pluginName)" }
        return skill.sourceType.isEmpty ? "unknown" : skill.sourceType
    }
}

private struct AgentsSettingsPane: View {
    let workspace: Workspace?
    let onConfigurationChanged: () -> Void

    private let service = GrokCLIService()
    @AppStorage(GrokSettingsKeys.selectedAgent) private var selectedAgent = ""
    @State private var appliedAgent = UserDefaults.standard.string(forKey: GrokSettingsKeys.selectedAgent) ?? ""
    @State private var agents: [GrokAgentInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDiscoveredAgents = false

    @State private var roles: [SubagentRole] = []
    @State private var editingRole: SubagentRole?
    @State private var isAddingRole = false
    @State private var roleError: String?

    private var hasPendingChanges: Bool { selectedAgent != appliedAgent }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Agents",
                    subtitle: "Choose the agent used for new sessions and manage reusable roles.",
                    systemImage: SettingsTab.agents.systemImage
                )
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            discoveredAgentsSection

            sessionAgentCard

            customSubagentsSection

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .task(id: workspace?.path) { await refresh() }
    }

    private var discoveredAgentsSection: some View {
        DisclosureGroup(isExpanded: $showDiscoveredAgents) {
            List {
                ForEach(agents) { agent in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(agent.name)
                                .font(.headline)
                            Spacer()
                            Text(sourceLabel(for: agent))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        if !agent.description.isEmpty {
                            Text(agent.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                        if !agent.sourcePath.isEmpty {
                            Text(agent.sourcePath)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 220)
            .overlay {
                if agents.isEmpty && !isLoading {
                    ContentUnavailableView("No Agents", systemImage: "person.2.slash", description: Text("Grok did not report any agents for this project."))
                }
            }
            if isLoading { ProgressView() }
        } label: {
            HStack(spacing: 6) {
                Text("Discovered agents")
                    .font(.headline)
                if !agents.isEmpty {
                    Text("\(agents.count) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sessionAgentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Default agent for new sessions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $selectedAgent) {
                    ForEach(GrokAgentProfiles.builtInOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                    if !discoveredAgentNames.isEmpty {
                        Section("Discovered") {
                            ForEach(discoveredAgentNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    if !customSubagentNames.isEmpty {
                        Section("Run as custom role") {
                            ForEach(customSubagentNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }

            Text("Used for new sessions. You can override it per session from the composer. A custom role runs the whole session; ask in chat when you want Grok to delegate work to a subagent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Save Default") {
                    appliedAgent = selectedAgent
                    onConfigurationChanged()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasPendingChanges)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(hasPendingChanges ? AppTheme.Palette.surfaceHover : AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(
                    hasPendingChanges
                        ? AppTheme.Palette.glassBorderStrong
                        : AppTheme.Palette.glassBorder
                )
        )
    }

    private var customSubagentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Custom subagents")
                    .font(.headline)
                Spacer()
                Button {
                    editingRole = nil
                    isAddingRole = true
                } label: {
                    Label("Add Subagent", systemImage: "plus")
                }
                .disabled(roles.count >= SubagentRoleStore.maxRoles)
            }

            Text("Reusable roles with their own instructions and an optional model.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ask for a role by name, or let the main agent delegate automatically. Each role works independently and reports back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)

            if roles.isEmpty {
                Text("No custom subagents yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(roles) { role in
                        roleRow(role)
                        if role.id != roles.last?.id { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.medium).fill(Color.primary.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.medium).stroke(Color.primary.opacity(0.08)))
            }

            if let roleError {
                Text(roleError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .sheet(isPresented: $isAddingRole) {
            SubagentRoleEditor(
                role: editingRole,
                existingNames: Set(roles.map(\.name)),
                modelOptions: modelOptions
            ) { saved in
                upsertRole(saved)
            }
        }
    }

    private func roleRow(_ role: SubagentRole) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(role.name)
                        .font(.subheadline.weight(.semibold))
                    Text(role.model.isEmpty ? "inherits model" : role.model)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if !role.description.isEmpty {
                    Text(role.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(role.instruction)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                editingRole = role
                isAddingRole = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit subagent")
            Button(role: .destructive) {
                removeRole(role)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove subagent")
        }
        .padding(12)
    }

    /// Model ids available in the role editor picker (built-ins + custom models from config.toml).
    private var modelOptions: [String] {
        var options = ["grok-build"]
        for model in CustomModelStore.load().models where !options.contains(model.id) {
            options.append(model.id)
        }
        return options
    }

    private func upsertRole(_ role: SubagentRole) {
        if let editing = editingRole, editing.name != role.name {
            roles.removeAll { $0.name == editing.name }
        }
        if let index = roles.firstIndex(where: { $0.name == role.name }) {
            roles[index] = role
        } else {
            roles.append(role)
        }
        persistRoles()
    }

    private func removeRole(_ role: SubagentRole) {
        roles.removeAll { $0.name == role.name }
        persistRoles()
    }

    private func persistRoles() {
        do {
            try SubagentRoleStore.save(roles)
            roleError = nil
            roles = SubagentRoleStore.load()
            NotificationCenter.default.post(name: .subagentRolesChanged, object: nil)
            onConfigurationChanged()
        } catch {
            roleError = "Could not save subagents: \(error.localizedDescription)"
        }
    }

    /// Discovered names that are not already surfaced as the built-in options.
    private var discoveredAgentNames: [String] {
        agents.map(\.name).filter { name in !GrokAgentProfiles.builtInOptions.contains { $0.id == name } }
    }

    /// Custom subagent roles that are not already present in built-in or discovered agent lists.
    private var customSubagentNames: [String] {
        let excluded = Set(GrokAgentProfiles.builtInOptions.map(\.id) + agents.map(\.name))
        return roles.map(\.name).filter { !excluded.contains($0) }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        roles = SubagentRoleStore.load()
        do {
            agents = try await service.listAgents(cwd: workspace?.path)
        } catch {
            agents = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func sourceLabel(for agent: GrokAgentInfo) -> String {
        if !agent.pluginName.isEmpty { return "plugin: \(agent.pluginName)" }
        return agent.sourceType.isEmpty ? "unknown" : agent.sourceType
    }
}

/// Add/edit sheet for a custom subagent role (name, model, instruction, description).
private struct SubagentRoleEditor: View {
    let role: SubagentRole?
    let existingNames: Set<String>
    let modelOptions: [String]
    let onSave: (SubagentRole) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var model = ""
    @State private var description = ""
    @State private var instruction = ""

    private var isEditing: Bool { role != nil }

    private var validationError: String? {
        let candidate = SubagentRole(
            name: name.trimmingCharacters(in: .whitespaces),
            model: model,
            instruction: instruction,
            description: description
        )
        if let error = candidate.validationError { return error }
        let originalName = role?.name
        if name.trimmingCharacters(in: .whitespaces) != originalName,
           existingNames.contains(name.trimmingCharacters(in: .whitespaces)) {
            return "A subagent named \"\(name.trimmingCharacters(in: .whitespaces))\" already exists."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Edit Subagent" : "Add Subagent")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("e.g. researcher", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isEditing)
                    .onChange(of: name) { _, newValue in
                        if !isEditing {
                            name = SubagentRole.suggestedName(from: newValue)
                        }
                    }
                if isEditing {
                    Text("Name can't be changed after creation.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Picker("", selection: $model) {
                    Text("Inherit session model").tag("")
                    ForEach(modelOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description (optional)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("Short summary", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Instruction").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextEditor(text: $instruction)
                    .font(.body)
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.medium).stroke(Color.primary.opacity(0.15)))
                Text("Saved to ~/.grok/prompts/\(name.isEmpty ? "<name>" : name).md")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let validationError {
                Text(validationError).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Save" : "Add") {
                    onSave(SubagentRole(
                        name: name.trimmingCharacters(in: .whitespaces),
                        model: model,
                        instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespaces),
                        extraFields: role?.extraFields ?? [:]
                    ))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationError != nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if let role {
                name = role.name
                model = role.model
                description = role.description
                instruction = role.instruction
            }
        }
    }
}

private struct ComputerUseSettingsPane: View {
    let onConfigurationChanged: () -> Void

    @AppStorage(ComputerUseSettingsKeys.enabled) private var enabled = ComputerUseSettings.defaults.enabled
    @AppStorage(ComputerUseSettingsKeys.backend) private var backend = ComputerUseSettings.defaults.backend.rawValue
    @AppStorage(ComputerUseSettingsKeys.permissionPolicy) private var permissionPolicy = ComputerUseSettings.defaults.permissionPolicy.rawValue
    @AppStorage(ComputerUseSettingsKeys.commandTimeoutSeconds) private var commandTimeoutSeconds = ComputerUseSettings.defaults.commandTimeoutSeconds
    @AppStorage(ComputerUseSettingsKeys.includeScreenshots) private var includeScreenshots = ComputerUseSettings.defaults.includeScreenshots
    @AppStorage(ComputerUseSettingsKeys.cursorIntegrationEnabled) private var cursorIntegrationEnabled = false
    @AppStorage(ComputerUseSettingsKeys.appliedCursorIntegrationEnabled) private var appliedCursorIntegrationEnabled = false

    @State private var backendStatus = ComputerUseBackendStatus.unavailable
    @State private var cursorInstallStatus = ComputerUseCursorInstallStatus.unavailable
    @State private var permissionStatus = ComputerUsePermissionStatus.unavailable
    @State private var permissionProbe: AccessibilityTrustProbe?
    @State private var grokBuildAXGranted = false
    @State private var grokBuildSRGranted = false
    @State private var isRunningEndToEndTest = false
    @State private var endToEndResult: ComputerUseService.EndToEndTestResult?
    @State private var appliedSettings = ComputerUseSettingsStore.loadApplied()
    @State private var isChecking = false
    @State private var isRequestingPermissions = false
    @State private var permissionOutput: String?
    @State private var showDiagnosticsLog = false
    @State private var showPermissionDiagnostics = false
    @State private var showAdvancedOptions = false
    @State private var isInstallingForCursor = false
    @State private var isRemovingCursorIntegration = false
    @State private var cursorInstallOutput: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                enableCard
                statusCard
                permissionsCard
                safetyCard
                cursorIntegrationCard
                applyCard
            }
            .centeredSettingsColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Palette.canvas)
        .task {
            appliedSettings = ComputerUseSettingsStore.loadApplied()
            await refreshStatus()
            // Deliberately no Cursor config sync here: ~/.cursor/mcp.json is
            // the user's file, and merely opening Settings must not rewrite
            // it. Writes happen on explicit Install/Update/Apply only.
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            settingsPaneHeader(
                "Computer Use",
                subtitle: "Let Grok interact with native macOS apps using Accessibility.",
                systemImage: SettingsTab.computerUse.systemImage
            )
            statusBadge
        }
    }

    private var enableCard: some View {
        computerSettingsCard(title: "Computer Use", systemImage: SettingsTab.computerUse.systemImage) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(
                    "Allow computer control",
                    subtitle: "Available in new and resumed sessions.",
                    isOn: $enabled
                )
                .onChange(of: enabled) { _, newValue in
                    guard newValue != appliedSettings.enabled else { return }
                    Task { await applyEnabledChange(to: newValue) }
                }
            }
        }
    }

    private var statusCard: some View {
        computerSettingsCard(title: "Built-in Support", systemImage: backendStatus.isInstalled ? "checkmark.circle" : "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(backendStatusTitle, systemImage: backendStatusIcon)
                        .foregroundStyle(backendStatusColor)
                        .font(.headline)
                    Spacer()
                    Button(isChecking ? "Checking..." : "Run Diagnostics") {
                        Task { await refreshStatus() }
                    }
                    .disabled(isChecking)
                }

                if backendStatus.isInstalled {
                    Text("Built-in computer support is ready. Grant macOS permissions below, then allow computer control.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("This build has no agent-desktop. Install it with `npm install -g agent-desktop` and rebuild (`make run`), or use a notarized GrokBuild release, which bundles it.")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 10) {
                    Button(isRunningEndToEndTest ? "Testing…" : "Test Computer Use") {
                        Task { await runEndToEndTest() }
                    }
                    .disabled(!backendStatus.isInstalled || isRunningEndToEndTest)
                    .help("Runs initialize + computer_list_apps through the real helper and agent-desktop — the same path grok uses.")

                    if isRunningEndToEndTest {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let endToEndResult {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(endToEndResult.summary, systemImage: endToEndResult.success ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(endToEndResult.success ? .green : .red)
                        Text(endToEndResult.detail)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                            .foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup(isExpanded: $showDiagnosticsLog) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let path = backendStatus.executablePath {
                            infoLine("Path", path)
                        }
                        if let version = backendStatus.version, !version.isEmpty {
                            infoLine("Version", version)
                        }
                        Text(backendStatus.diagnostic.isEmpty ? "No diagnostics yet." : backendStatus.diagnostic)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } label: {
                    Label(showDiagnosticsLog ? "Hide diagnostics log" : "Show diagnostics log", systemImage: "doc.text.magnifyingglass")
                        .font(.callout.weight(.medium))
                }

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/lahfir/agent-desktop")!)
                } label: {
                    Label("Open Computer Use Setup Guide", systemImage: "questionmark.circle")
                }
            }
        }
    }

    private var permissionsCard: some View {
        computerSettingsCard(title: "macOS Permissions", systemImage: permissionStatus.isReady(includeScreenshots: includeScreenshots) ? "lock.open" : "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Accessibility is required for UI actions. Screen Recording is needed only for screenshots.")
                    .foregroundStyle(.secondary)

                permissionRow(
                    title: "Accessibility",
                    state: permissionStatus.accessibility,
                    help: "Effective status for UI actions, resolved across the binaries below."
                )
                permissionRow(
                    title: "Screen Recording",
                    state: permissionStatus.screenRecording,
                    help: "Required only when the screenshot tool is enabled."
                )

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        permissionRow(
                            title: "GrokBuild",
                            state: grokBuildAXGranted ? "granted" : "denied",
                            help: "This app's own Accessibility trust."
                        )
                        permissionRow(
                            title: "MCP helper",
                            state: permissionProbe.map { $0.helperGranted ? "granted" : "denied" } ?? "unknown",
                            help: "GrokBuildComputerUseMCP; diagnostic only — it performs no UI actions itself."
                        )
                        permissionRow(
                            title: "agent-desktop",
                            state: permissionProbe.map { $0.agentDesktopGranted ? "granted" : "denied" } ?? "unknown",
                            help: ComputerUseService.usesBundledAgentDesktop(settings: currentSettings)
                                ? "The acting binary. Bundled copies share the app's signing identity, so one grant covers all three."
                                : "The acting binary. External copies have their own identity — this grant is the one that matters."
                        )
                        if !ComputerUseService.usesBundledAgentDesktop(settings: currentSettings),
                           let agentDesktopPath = ComputerUseService.executableURL(settings: currentSettings)?.path {
                            Text("agent-desktop path: \(agentDesktopPath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Per-binary Accessibility status", systemImage: "list.bullet.rectangle")
                        .font(.callout.weight(.medium))
                }

                if let guidance = permissionStatus.guidance {
                    Text(guidance)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Open Accessibility Settings") {
                            Task { @MainActor in
                                ComputerUseService.openAccessibilitySettings()
                            }
                        }
                        Button("Show App in Finder") {
                            ComputerUseService.revealAppInFinder()
                        }
                    }
                }

                HStack {
                    Button(isRequestingPermissions ? "Requesting..." : "Request Permissions") {
                        Task { await requestPermissions() }
                    }
                    .disabled(!backendStatus.isInstalled || isRequestingPermissions)

                    Button("Refresh") {
                        Task { await refreshStatus() }
                    }
                    .disabled(isChecking)

                    Button(showPermissionDiagnostics ? "Hide Diagnostics" : "Show Diagnostics") {
                        showPermissionDiagnostics.toggle()
                    }
                    Spacer()
                }

                if showPermissionDiagnostics {
                    Text(permissionDiagnosticsText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var safetyCard: some View {
        computerSettingsCard(title: "Safety", systemImage: "hand.raised") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tool approval is governed by grok's permission flow (Settings → Permissions). Block All additionally stops clicks, typing, and key presses at the helper.")
                    .foregroundStyle(.secondary)

                settingRow("Actions") {
                    Picker("", selection: $permissionPolicy) {
                        ForEach(ComputerUsePermissionPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                SettingsToggleRow(
                    "Allow screenshot tool",
                    subtitle: "Use screenshots only when Accessibility snapshots are not enough. Requires Screen Recording permission.",
                    isOn: $includeScreenshots
                )
                .onChange(of: includeScreenshots) { _, isEnabled in
                    // Enabling the tool is the moment Screen Recording starts
                    // mattering, and asking is the only way GrokBuild ever
                    // appears in that Privacy pane.
                    guard ComputerUseService.shouldRequestScreenRecording(
                        includeScreenshots: isEnabled,
                        granted: ComputerUseService.localScreenRecordingGranted()
                    ) else { return }
                    Task {
                        ComputerUseService.requestScreenRecordingAccess()
                        await refreshStatus()
                    }
                }

                Stepper("Command timeout: \(commandTimeoutSeconds)s", value: $commandTimeoutSeconds, in: 5...180, step: 5)
            }
        }
    }

    private var cursorIntegrationCard: some View {
        computerSettingsCard(
            title: "Cursor Integration",
            systemImage: "cursorarrow"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsToggleRow(
                    "Use Computer Control in Cursor",
                    subtitle: "Adds GrokBuild's computer tools to Cursor Agent across projects.",
                    isOn: $cursorIntegrationEnabled
                )

                if cursorInstallStatus.isInstalled {
                    Label("Ready in Cursor after MCP reload.", systemImage: "checkmark.circle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Install once for Cursor Agent across projects.")
                        .foregroundStyle(.secondary)
                }

                if let helperPath = cursorInstallStatus.helperPath {
                    infoLine("Helper", helperPath)
                }
                if let agentDesktopPath = cursorInstallStatus.agentDesktopPath {
                    infoLine("agent-desktop", agentDesktopPath)
                }
                infoLine("MCP config", cursorInstallStatus.mcpConfigPath)

                HStack {
                    Button(isInstallingForCursor ? "Installing..." : (cursorInstallStatus.isInstalled ? "Update for Cursor" : "Install for Cursor")) {
                        Task { await installForCursor() }
                    }
                    .disabled(!backendStatus.isInstalled || isInstallingForCursor || isRemovingCursorIntegration)

                    if cursorInstallStatus.isInstalled {
                        Button(isRemovingCursorIntegration ? "Removing..." : "Remove from Cursor", role: .destructive) {
                            Task { await removeCursorIntegration() }
                        }
                        .disabled(isInstallingForCursor || isRemovingCursorIntegration)
                    }

                    Button("Reveal MCP Config") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            URL(fileURLWithPath: cursorInstallStatus.mcpConfigPath)
                        ])
                    }
                }

                if let cursorInstallOutput, !cursorInstallOutput.isEmpty {
                    Text(cursorInstallOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var applyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apply changes")
                    .font(.headline)
                Text(hasPendingChanges
                    ? "Restarts the active Grok connection."
                    : "Computer Use settings are current.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply Changes") {
                apply()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasPendingChanges)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(hasPendingChanges ? AppTheme.Palette.surfaceHover : AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(hasPendingChanges ? AppTheme.Palette.glassBorderStrong : AppTheme.Palette.glassBorder)
        )
    }

    private var currentSettings: ComputerUseSettings {
        ComputerUseSettings(
            enabled: enabled,
            backend: ComputerUseBackendID(rawValue: backend) ?? ComputerUseSettings.defaults.backend,
            permissionPolicy: ComputerUsePermissionPolicy(rawValue: permissionPolicy)
                ?? ComputerUseSettings.defaults.permissionPolicy,
            commandTimeoutSeconds: commandTimeoutSeconds,
            includeScreenshots: includeScreenshots
        )
    }

    private var hasPendingChanges: Bool {
        currentSettings != appliedSettings || cursorIntegrationEnabled != appliedCursorIntegrationEnabled
    }

    private var statusBadge: some View {
        let isEnabled = appliedSettings.enabled
        let ready = permissionStatus.isReady(includeScreenshots: appliedSettings.includeScreenshots)
        let text = isEnabled ? (ready ? "Ready" : "Setup needed") : "Disabled"
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var backendStatusTitle: String {
        if backendStatus.isInstalled {
            return backendStatus.version.map { "agent-desktop ready (\($0))" } ?? "agent-desktop ready"
        }
        return "agent-desktop not installed"
    }

    private var backendStatusIcon: String {
        backendStatus.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var backendStatusColor: Color {
        .secondary
    }

    private var permissionDiagnosticsText: String {
        var parts: [String] = []
        if let guidance = permissionStatus.guidance {
            parts.append(guidance)
        }
        parts.append(
            permissionStatus.diagnostic.isEmpty
                ? "No permission diagnostics yet."
                : permissionStatus.diagnostic
        )
        if let permissionOutput, !permissionOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Last request:\n\(permissionOutput)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func apply() {
        let settings = currentSettings
        let shouldInstallCursor = cursorIntegrationEnabled
        let shouldUninstallCursor = appliedCursorIntegrationEnabled && !cursorIntegrationEnabled

        ComputerUseSettingsStore.save(settings)
        ComputerUseSettingsStore.saveApplied(settings)
        appliedSettings = settings
        appliedCursorIntegrationEnabled = cursorIntegrationEnabled
        syncCursorConfiguration(showErrorsOnly: true)

        if shouldInstallCursor {
            Task {
                await installForCursor(showErrorsOnly: false)
                onConfigurationChanged()
            }
        } else if shouldUninstallCursor {
            Task {
                await removeCursorIntegration()
                onConfigurationChanged()
            }
        } else {
            onConfigurationChanged()
        }
    }

    private func applyEnabledChange(to newValue: Bool) async {
        let result = await ComputerUseService.applyEnabled(newValue, settings: currentSettings) {
            onConfigurationChanged()
        }
        if case .needsSetup = result {
            enabled = appliedSettings.enabled
        } else {
            appliedSettings = ComputerUseSettingsStore.loadApplied()
            await refreshStatus()
        }
    }

    private func syncCursorConfiguration(showErrorsOnly: Bool = false) {
        guard cursorInstallStatus.isInstalled else { return }
        do {
            if let message = try ComputerUseService.syncCursorIntegrationIfInstalled(settings: currentSettings) {
                if !showErrorsOnly {
                    cursorInstallOutput = message
                }
            }
            appliedSettings = ComputerUseSettingsStore.loadApplied()
            cursorInstallStatus = ComputerUseCursorInstaller.status()
        } catch {
            if !showErrorsOnly {
                cursorInstallOutput = error.localizedDescription
            }
        }
    }

    private func refreshStatus() async {
        isChecking = true
        defer { isChecking = false }
        let settings = currentSettings
        async let status = ComputerUseService.status(settings: settings)
        async let overview = ComputerUseService.permissionOverview(settings: settings)
        backendStatus = await status
        let resolvedOverview = await overview
        permissionStatus = resolvedOverview.resolved
        permissionProbe = resolvedOverview.probe
        grokBuildAXGranted = resolvedOverview.grokBuildAccessibilityGranted
        grokBuildSRGranted = resolvedOverview.grokBuildScreenRecordingGranted
        cursorInstallStatus = ComputerUseCursorInstaller.status()
    }

    private func runEndToEndTest() async {
        isRunningEndToEndTest = true
        defer { isRunningEndToEndTest = false }
        endToEndResult = await ComputerUseService.runEndToEndTest(settings: currentSettings)
    }

    private func installForCursor(showErrorsOnly: Bool = true) async {
        isInstallingForCursor = true
        if !showErrorsOnly {
            cursorInstallOutput = "Installing Computer Use for Cursor..."
        }
        defer { isInstallingForCursor = false }

        do {
            cursorInstallOutput = try ComputerUseCursorInstaller.install(settings: currentSettings)
            cursorInstallStatus = ComputerUseCursorInstaller.status()
        } catch {
            cursorInstallOutput = error.localizedDescription
        }
    }

    private func removeCursorIntegration() async {
        isRemovingCursorIntegration = true
        cursorInstallOutput = "Removing Computer Use from Cursor..."
        defer { isRemovingCursorIntegration = false }

        do {
            cursorInstallOutput = try ComputerUseCursorInstaller.uninstall()
            cursorIntegrationEnabled = false
            appliedCursorIntegrationEnabled = false
            cursorInstallStatus = ComputerUseCursorInstaller.status()
        } catch {
            cursorInstallOutput = error.localizedDescription
        }
    }

    private func requestPermissions() async {
        isRequestingPermissions = true
        permissionOutput = "Requesting Accessibility permission for GrokBuild..."
        defer { isRequestingPermissions = false }

        do {
            permissionOutput = try await ComputerUseService.requestPermissions(settings: currentSettings)
            await refreshStatus()
        } catch {
            permissionOutput = error.localizedDescription
        }
    }

    private func permissionRow(title: String, state: String, help: String) -> some View {
        let normalized = state.lowercased()
        let isGranted = normalized == "granted"
        let isNeutral = normalized == "unknown" || normalized == "not reported"
        // Permission state is exactly the place semantic color earns its keep:
        // a denied row must not render in the same gray as a granted one.
        let color: Color = isGranted ? .green : (isNeutral ? .secondary : .red)
        let icon = isGranted
            ? "checkmark.circle.fill"
            : (isNeutral ? "minus.circle" : "exclamationmark.triangle.fill")
        let label = normalized == "not reported" ? "Not reported" : state.capitalized
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: 120, alignment: .leading)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func infoLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func installCommandRow(title: String, command: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                copyToPasteboard(command)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
    }

    private func computerSettingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }
}

private struct CustomModelsSettingsPane: View {
    let onConfigurationChanged: (ConfigurationChange) -> Void

    @State private var viewModel = CustomModelsSettingsViewModel()
    @State private var editingID: String?
    @State private var draft = CustomModel(id: "", model: "", baseURL: "")
    @State private var revealKey = false
    @State private var allowUnverifiedCustomModel = false
    @State private var editingProviderID: String?
    @State private var providerDraft = Provider(id: "", name: "", baseURL: "")
    @State private var revealProviderKey = false
    @State private var modelFilterText = ""

    private enum ProviderEditorField: Hashable { case id, name, url, key }
    @FocusState private var providerEditorFocus: ProviderEditorField?

    /// See the comment at the provider-editor fields: present only while the field is
    /// unfocused, so the first click lands here and forcibly moves focus.
    @ViewBuilder
    private func focusClickCatcher(for field: ProviderEditorField) -> some View {
        if providerEditorFocus != field {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { providerEditorFocus = field }
        }
    }
    // Drives programmatic scrolling to an editor when a card opens it.
    @State private var scrollTarget: String?
    // True while the provider editor holds a not-yet-saved template (so we lock the id and
    // prompt for the key). Cleared once the provider is saved or the draft is reset.
    @State private var providerDraftFromPreset = false
    // The editor cards are hidden until the user explicitly opens them via Install / Add /
    // Edit, keeping the default view a clean list.
    @State private var showingProviderEditor = false
    @State private var showingModelEditor = false
    // The provider-template catalog is collapsed by default so "Add Provider" stays compact.
    @State private var showingProviderTemplates = false
    @State private var showModelRemovalConfirmation = false
    @State private var modelPendingRemoval: CustomModel?
    @State private var showProviderRemovalConfirmation = false
    @State private var providerPendingRemoval: Provider?

    private var providers: [Provider] {
        get { viewModel.providers }
        nonmutating set { viewModel.providers = newValue }
    }
    private var models: [CustomModel] {
        get { viewModel.models }
        nonmutating set { viewModel.models = newValue }
    }
    private var defaultModelID: String {
        get { viewModel.defaultModelID }
        nonmutating set { viewModel.defaultModelID = newValue }
    }
    private var persistedDefaultModelID: String {
        get { viewModel.persistedDefaultModelID }
        nonmutating set { viewModel.persistedDefaultModelID = newValue }
    }
    private var errorMessage: String? {
        get { viewModel.errorMessage }
        nonmutating set { viewModel.errorMessage = newValue }
    }
    private var statusMessage: String? {
        get { viewModel.statusMessage }
        nonmutating set { viewModel.statusMessage = newValue }
    }
    private var migrationIssues: [ProviderCredentialMigrationIssue] {
        get { viewModel.migrationIssues }
        nonmutating set { viewModel.migrationIssues = newValue }
    }
    private var validationResults: [String: ProviderValidationResult] {
        get { viewModel.validationResults }
        nonmutating set { viewModel.validationResults = newValue }
    }
    private var fetchedModels: [String: [FetchedModel]] {
        get { viewModel.fetchedModels }
        nonmutating set { viewModel.fetchedModels = newValue }
    }
    private var fetchingProviderID: String? {
        get { viewModel.fetchingProviderID }
        nonmutating set { viewModel.fetchingProviderID = newValue }
    }
    private var fetchErrorProviderID: String? {
        get { viewModel.fetchErrorProviderID }
        nonmutating set { viewModel.fetchErrorProviderID = newValue }
    }
    private var fetchErrorMessage: String? {
        get { viewModel.fetchErrorMessage }
        nonmutating set { viewModel.fetchErrorMessage = newValue }
    }

    private struct DefaultModelOption: Identifiable {
        var id: String
        var label: String
    }

    private struct ContextTokenPreset: Identifiable {
        var label: String
        var value: Int
        var id: Int { value }
    }

    @State private var builtInModels = GrokModelCatalog.cachedOrFallback()

    private var builtInDefaultModels: [DefaultModelOption] {
        [DefaultModelOption(id: "", label: "No default override")]
            + builtInModels.map { DefaultModelOption(id: $0.id, label: $0.name) }
    }

    private let contextTokenPresets: [ContextTokenPreset] = [
        ContextTokenPreset(label: "128K", value: 128_000),
        ContextTokenPreset(label: "200K", value: 200_000),
        ContextTokenPreset(label: "512K", value: 512_000),
        ContextTokenPreset(label: "1M", value: 1_000_000)
    ]

    private var isEditing: Bool { editingID != nil }
    private var isEditingProvider: Bool { editingProviderID != nil }
    /// While any editor (provider or model) is open we lock the list cards so the user
    /// finishes or cancels the current edit before starting another action.
    private var isAnyEditorOpen: Bool { showingProviderEditor || showingModelEditor }
    private var isAtModelLimit: Bool { models.count >= CustomModelStore.maxModels }
    private var isDefaultModelDirty: Bool { defaultModelID != persistedDefaultModelID }

    private var defaultModelOptions: [DefaultModelOption] {
        var options = builtInDefaultModels
        for model in models {
            let label = model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? model.id
                : "\(model.name) (\(model.id))"
            if !options.contains(where: { $0.id == model.id }) {
                options.append(DefaultModelOption(id: model.id, label: label))
            }
        }
        if !defaultModelID.isEmpty, !options.contains(where: { $0.id == defaultModelID }) {
            options.append(DefaultModelOption(id: defaultModelID, label: "\(defaultModelID) (current)"))
        }
        return options
    }

    private var contextTokensBinding: Binding<String> {
        Binding(
            get: {
                draft.contextTokens.map(String.init) ?? ""
            },
            set: { value in
                let digits = value.filter(\.isNumber)
                draft.contextTokens = digits.isEmpty ? nil : Int(digits)
            }
        )
    }

    private func selectableModels(for provider: Provider) -> [FetchedModel] {
        fetchedModels[provider.id] ?? []
    }

    /// True when a provider has a non-empty fetched-model list ready for "Add model".
    private func hasFetchedModels(for provider: Provider) -> Bool {
        !(fetchedModels[provider.id]?.isEmpty ?? true)
    }

    private func addModelDisabledReason(for provider: Provider) -> String? {
        if isAtModelLimit {
            return "Maximum of \(CustomModelStore.maxModels) custom models reached. Remove a model first."
        }
        if !hasFetchedModels(for: provider) {
            return "Fetch models from this provider first."
        }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if !migrationIssues.isEmpty {
                        migrationIssueCard
                    }
                    defaultModelCard
                    providerTemplatesCard
                    if showingProviderEditor {
                        providerEditorCard
                            .id(providerEditorAnchor)
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    yourProvidersCard
                    if showingModelEditor {
                        editorCard
                            .id(modelEditorAnchor)
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    modelListCard
                }
                .animation(.easeInOut(duration: 0.2), value: showingProviderEditor)
                .animation(.easeInOut(duration: 0.2), value: showingModelEditor)
                .animation(.easeInOut(duration: 0.2), value: showingProviderTemplates)
                .centeredSettingsColumn()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppTheme.Palette.canvas)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                // The editor/provider card this targets is only inserted into the
                // hierarchy by the `showingModelEditor`/`showingProviderEditor` toggle
                // that triggers this same change, so scrolling in this tick would race
                // its layout and silently no-op. Defer one runloop turn so the card
                // exists before `scrollTo` looks it up.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
                scrollTarget = nil
            }
        }
        .task {
            await reload()
            builtInModels = await GrokModelCatalog.shared.models()
        }
        .alert("Remove Model?", isPresented: $showModelRemovalConfirmation) {
            Button("Cancel", role: .cancel) {
                modelPendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                if let model = modelPendingRemoval {
                    remove(model)
                }
                modelPendingRemoval = nil
            }
        } message: {
            if let model = modelPendingRemoval {
                let label = model.name.isEmpty ? model.id : model.name
                Text("Remove \(label) from ~/.grok/config.toml? You won't be able to use /model \(model.id) until you add it again.")
            }
        }
        .alert("Remove Provider?", isPresented: $showProviderRemovalConfirmation) {
            Button("Cancel", role: .cancel) {
                providerPendingRemoval = nil
            }
            Button("Remove", role: .destructive) {
                if let provider = providerPendingRemoval {
                    removeProvider(provider)
                }
                providerPendingRemoval = nil
            }
        } message: {
            if let provider = providerPendingRemoval {
                Text("Remove \(provider.name) from your providers? This cannot be undone.")
            }
        }
    }

    private let providerEditorAnchor = "provider-editor"
    private let modelEditorAnchor = "model-editor"

    private var header: some View {
        settingsPaneHeader(
            "Models",
            subtitle: "Add OpenAI-compatible providers and choose the models available to Grok.",
            systemImage: SettingsTab.models.systemImage
        )
    }

    private var migrationIssueCard: some View {
        settingsCard(title: "Credential migration needs attention", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(migrationIssues) { issue in
                    Text("\(issue.providerID): \(issue.message)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var defaultModelCard: some View {
        settingsCard(title: "Default Model", systemImage: "checkmark.circle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Used when you start a new session. Existing sessions keep their current model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Picker("Default model", selection: Binding(
                        get: { defaultModelID },
                        set: { defaultModelID = $0 }
                    )) {
                        ForEach(defaultModelOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)

                    Spacer()

                    Button("Save Default") {
                        persist(change: .defaultModel)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isDefaultModelDirty)
                }
            }
        }
    }

    // MARK: - Provider templates (catalog)

    /// `true` when a preset has already been installed as one of `providers`.
    private func isPresetInstalled(_ preset: ProviderPreset) -> Bool {
        providers.contains { $0.id == preset.provider.id }
    }

    private var providerTemplatesCard: some View {
        settingsCard(title: "Add Provider", systemImage: "plus") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingProviderTemplates.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showingProviderTemplates ? 90 : 0))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Provider Templates")
                                .font(.subheadline.weight(.semibold))
                            Text("Popular OpenAI-compatible providers. Install one to add it to “Your Providers”, then enter its API key.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Group {
                    if showingProviderTemplates {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(ProviderPreset.allCases) { preset in
                                providerTemplateTile(preset)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Divider()

                    Button {
                        beginNewProvider()
                    } label: {
                        Label("Create custom provider…", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                .disabled(isAnyEditorOpen)
                .opacity(isAnyEditorOpen ? 0.45 : 1)
            }
        }
    }

    private func providerTemplateTile(_ preset: ProviderPreset) -> some View {
        let template = preset.provider
        let installed = isPresetInstalled(preset)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(preset.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if installed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text(template.baseURL)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !template.suggestedModel.isEmpty {
                Text("e.g. \(template.suggestedModel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(installed ? "Configure" : "Install") { addProviderPreset(preset) }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.large)
                .stroke(installed ? AppTheme.Palette.glassBorderStrong : AppTheme.Palette.glassBorder)
        )
    }

    // MARK: - Your providers (installed)

    private var yourProvidersCard: some View {
        settingsCard(title: "Providers", systemImage: "server.rack") {
            VStack(alignment: .leading, spacing: 12) {
                if providers.isEmpty {
                    Text("No providers installed yet. Install one from a template above, or create a custom provider.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("A provider holds a base URL and a shared API key. Multiple models can reuse the same provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(providers) { provider in
                        providerRow(provider)
                        if provider.id != providers.last?.id { Divider() }
                    }
                }
            }
            .disabled(isAnyEditorOpen)
            .opacity(isAnyEditorOpen ? 0.45 : 1)
        }
    }

    private func providerRow(_ provider: Provider) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(provider.name)
                        .font(.headline)
                    providerKeyBadge(for: provider)
                    if provider.allowInsecureHTTP {
                        badge("Insecure HTTP", systemImage: "lock.open")
                    }
                    providerValidationBadge(for: provider)
                    let count = models.filter { $0.providerID == provider.id }.count
                    if count > 0 {
                        Text("\(count) model\(count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let fetched = fetchedModels[provider.id] {
                        if fetched.isEmpty {
                            Text("0 available")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(fetched.count) available")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text(provider.baseURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if fetchErrorProviderID == provider.id, let message = fetchErrorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let result = validationResults[provider.id] {
                    HStack(spacing: 6) {
                        Text(result.message)
                        Text("·")
                        Text(result.checkedAt, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    let addModelDisabled = addModelDisabledReason(for: provider) != nil
                    Button("Add model") { beginNewModel(forProvider: provider) }
                        .controlSize(.small)
                        .disabled(addModelDisabled)
                        .help(addModelDisabledReason(for: provider)
                            ?? "Add a model from the fetched list.")
                    Button("Edit") { beginEditingProvider(provider) }
                        .controlSize(.small)
                    let inUse = modelsUsing(provider).count
                    Button("Remove", role: .destructive) {
                        providerPendingRemoval = provider
                        showProviderRemovalConfirmation = true
                    }
                        .controlSize(.small)
                        .disabled(inUse > 0)
                        .help(inUse > 0
                            ? "Remove its \(inUse) model\(inUse == 1 ? "" : "s") first before removing this provider."
                            : "Remove this provider.")
                }
                let canFetchProvider = canFetch(
                    baseURL: provider.baseURL,
                    apiKey: provider.apiKey,
                    authScheme: provider.authScheme,
                    providerID: provider.id
                )
                let highlightFetch = !hasFetchedModels(for: provider) && canFetchProvider
                Group {
                    if highlightFetch {
                        Button {
                            fetchModels(for: provider)
                        } label: {
                            if fetchingProviderID == provider.id {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Label("Test connection", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            fetchModels(for: provider)
                        } label: {
                            if fetchingProviderID == provider.id {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.small)
                                    Text("Checking…")
                                }
                            } else {
                                Label("Test connection", systemImage: "checkmark.circle")
                            }
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                    }
                }
                .disabled(
                    fetchingProviderID == provider.id
                    || !canFetchProvider
                )
                .help(fetchHelp(for: provider, highlight: highlightFetch))

                if let result = validationResults[provider.id] {
                    Button("Copy diagnostics") {
                        copyToPasteboard(providerDiagnostics(provider: provider, result: result))
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                    .help("Copy endpoint, auth mode, and redacted connection status.")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func fetchHelp(for provider: Provider, highlight: Bool) -> String {
        if provider.supportsLiveCatalogRefresh {
            return highlight
                ? "Fetch the Cline Pass model list before adding a model (no API key required)."
                : "Refresh the Cline Pass model list (no API key required)."
        }
        return highlight
            ? "Fetch the provider's model list before adding a model."
            : "Refresh the provider's model list."
    }

    private func providerDiagnostics(provider: Provider, result: ProviderValidationResult) -> String {
        let missing = result.missingModelIDs.isEmpty ? "none" : result.missingModelIDs.joined(separator: ", ")
        return """
        Provider: \(provider.name) (\(provider.id))
        Endpoint: \(ProviderEndpointPolicy.redactedDisplay(urlString: provider.baseURL))
        Authentication: \(provider.authScheme.rawValue)
        Credential present: \(provider.hasInlineKey ? "yes" : "no")
        Status: \(result.status.rawValue)
        Models returned: \(result.models.count)
        Missing configured models: \(missing)
        Checked: \(result.checkedAt.formatted(.iso8601))
        """
    }

    @ViewBuilder
    private func providerKeyBadge(for provider: Provider) -> some View {
        if provider.hasInlineKey {
            badge("Key saved", systemImage: "key.fill")
        } else if provider.isLocalEndpoint {
            badge("Local", systemImage: "desktopcomputer")
        } else {
            badge("No key", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private func providerValidationBadge(for provider: Provider) -> some View {
        if fetchingProviderID == provider.id {
            badge("Checking", systemImage: "arrow.triangle.2.circlepath")
        } else if let result = validationResults[provider.id] {
            switch result.status {
            case .connected:
                badge("Connected", systemImage: "checkmark.circle.fill")
            case .modelUnavailable:
                badge("Model missing", systemImage: "exclamationmark.triangle.fill")
            case .unauthorized:
                badge("Unauthorized", systemImage: "key.slash")
            case .rateLimited:
                badge("Rate limited", systemImage: "clock")
            case .endpointMissing:
                badge("Endpoint missing", systemImage: "link.badge.plus")
            case .providerUnavailable, .timeoutOrOffline:
                badge("Offline", systemImage: "wifi.slash")
            case .incompatibleResponse, .emptyCatalog:
                badge("Catalog issue", systemImage: "exclamationmark.circle")
            case .insecureEndpoint:
                badge("Insecure URL", systemImage: "lock.slash")
            case .redirectBlocked:
                badge("Redirect blocked", systemImage: "arrow.uturn.right.circle")
            }
        } else {
            badge("Not tested", systemImage: "questionmark.circle")
        }
    }

    private var providerEditorTitle: String {
        if isEditingProvider { return "Edit Provider" }
        if providerDraftFromPreset { return "Install \(providerDraft.name)" }
        return "Add New Provider"
    }

    /// True when the provider needs a key but none is set yet (drives the "enter your key" prompt).
    private var providerNeedsKey: Bool {
        !providerDraft.isLocalEndpoint
            && providerDraft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var providerEditorCard: some View {
        settingsCard(title: providerEditorTitle, systemImage: "plus.square.on.square") {
            VStack(alignment: .leading, spacing: 12) {
                if providerDraftFromPreset && providerNeedsKey {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                        Text("Enter your \(providerDraft.name) API key, then tap **Add Provider** to install it. Nothing is saved until you do.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppTheme.Radius.small).fill(AppTheme.Palette.glassTint))
                }

                // Pointer clicks between these fields do not reliably move AppKit's
                // first responder: the draft binds through the view model's computed
                // properties and the pane re-renders per keystroke, and NSTextField
                // swallows mousedowns before SwiftUI gestures see them (stable ids and
                // tap gestures both failed in live testing). The focusClickCatcher
                // overlay exists only while its field is unfocused — it takes the
                // first click, drives FocusState, then vanishes so native editing and
                // selection work untouched.
                settingRow("Provider id") {
                    TextField("openai", text: $providerDraft.id)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isEditingProvider || providerDraftFromPreset)
                        .frame(maxWidth: 280)
                        .id("provider-editor-id")
                        .focused($providerEditorFocus, equals: .id)
                        .overlay(focusClickCatcher(for: .id))
                }
                settingRow("Name") {
                    TextField("ChatGPT (OpenAI)", text: $providerDraft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .id("provider-editor-name")
                        .focused($providerEditorFocus, equals: .name)
                        .overlay(focusClickCatcher(for: .name))
                }
                settingRow("Base URL") {
                    TextField("https://api.openai.com/v1", text: $providerDraft.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .id("provider-editor-url")
                        .focused($providerEditorFocus, equals: .url)
                        .overlay(focusClickCatcher(for: .url))
                }
                if ProviderEndpointPolicy.locality(ofBaseURL: providerDraft.baseURL) == .remote,
                   !ProviderEndpointPolicy.isHTTPS(providerDraft.baseURL) {
                    settingRow("Insecure HTTP") {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Allow http:// for this trusted LAN endpoint", isOn: $providerDraft.allowInsecureHTTP)
                                .toggleStyle(.checkbox)
                            Text("Requests — including any API key — travel unencrypted. Only for model servers on hardware you control.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                settingRow("Authentication") {
                    Picker("Authentication", selection: $providerDraft.authScheme) {
                        Text("Bearer token").tag(ProviderAuthScheme.bearer)
                        Text("API key header").tag(ProviderAuthScheme.apiKeyHeader)
                        Text("Bearer + API key").tag(ProviderAuthScheme.bearerAndAPIKey)
                        Text("None / local").tag(ProviderAuthScheme.none)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    .disabled(providerDraftFromPreset)
                }
                settingRow("API key") {
                    HStack(spacing: 8) {
                        Group {
                            if revealProviderKey {
                                TextField("sk-… (leave empty for local servers)", text: $providerDraft.apiKey)
                            } else {
                                SecureField("sk-… (leave empty for local servers)", text: $providerDraft.apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .focused($providerEditorFocus, equals: .key)
                        .overlay(focusClickCatcher(for: .key))
                        Button {
                            revealProviderKey.toggle()
                        } label: {
                            Image(systemName: revealProviderKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Text("The API key is stored in macOS Keychain. GrokBuild projects only the CLI-required copy into the owner-only ~/.grok/config.toml file. Local/open servers don't need a key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                providerFetchRow

                HStack(spacing: 10) {
                    Button(isEditingProvider ? "Save Provider" : "Add Provider") { saveProviderDraft() }
                        .buttonStyle(.borderedProminent)
                        .disabled(providerDraft.validationError != nil)
                    Button("Cancel") { resetProviderDraft() }
                    Spacer()
                    if let error = providerDraft.validationError, !providerDraft.id.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// "Fetch models" control + result/error summary inside the provider editor.
    @ViewBuilder
    private var providerFetchRow: some View {
        providerModelFetchRow
    }

    @ViewBuilder
    private var providerModelFetchRow: some View {
        let draftKey = providerDraft.id.isEmpty ? "__draft__" : providerDraft.id
        let isFetching = fetchingProviderID == draftKey
        let fetched = fetchedModels[draftKey] ?? []
        let canFetchNow = canFetch(
            baseURL: providerDraft.baseURL,
            apiKey: providerDraft.apiKey,
            authScheme: providerDraft.authScheme,
            providerID: providerDraft.id
        )
        let usesLiveCatalog = providerDraft.supportsLiveCatalogRefresh
            || ProviderPreset.matching(provider: providerDraft)?.supportsLiveCatalogRefresh == true

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    fetchModelsForDraft()
                } label: {
                    if isFetching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Fetching…")
                        }
                    } else {
                        Label("Test connection", systemImage: "checkmark.circle")
                    }
                }
                .controlSize(.small)
                .disabled(!canFetchNow || isFetching)

                if !fetched.isEmpty {
                    Text("\(fetched.count) model\(fetched.count == 1 ? "" : "s") available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let docsURL = ProviderPreset.matching(provider: providerDraft)?.catalogDocumentationURL {
                    Link("Documentation", destination: docsURL)
                        .font(.caption)
                }
            }

            Text(usesLiveCatalog
                 ? "Fetches the live Cline Pass catalog (no API key required)."
                 : "Queries \(ProviderModelFetcher.modelsURL(for: providerDraft.baseURL)?.absoluteString ?? "the provider")/… to list available models. Enter the API key first (local servers need none).")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if fetchErrorProviderID == draftKey, let message = fetchErrorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !fetched.isEmpty {
                Text("Tip: Save this provider, then use “Add model” to pick from the fetched list.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Model list

    private var modelListCard: some View {
        settingsCard(title: "Models", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(models.count)/\(CustomModelStore.maxModels) custom models")
                    .font(.caption)
                    .foregroundStyle(isAtModelLimit ? .orange : .secondary)

                Group {
                    if models.isEmpty {
                        Text("No models yet. Use “Add model” on a provider above.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(models) { model in
                            modelRow(model)
                            if model.id != models.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .disabled(isAnyEditorOpen)
                .opacity(isAnyEditorOpen ? 0.45 : 1)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func modelRow(_ model: CustomModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name.isEmpty ? model.id : model.name)
                    .font(.headline)
                Text("/model \(model.id)  ·  \(model.model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.baseURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(modelMetadataSummary(model))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Button("Edit") { beginEditing(model) }
                    .controlSize(.small)
                Button("Remove", role: .destructive) {
                    modelPendingRemoval = model
                    showModelRemovalConfirmation = true
                }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func modelMetadataSummary(_ model: CustomModel) -> String {
        var pieces: [String] = [model.apiBackend.displayName]
        if let tokens = model.contextTokens {
            pieces.append("\(compactTokenCount(tokens)) context")
        } else {
            pieces.append("context unknown")
        }
        pieces.append(model.supportsReasoningEffort ? "reasoning effort on" : "reasoning effort off")
        if model.supportsVision {
            pieces.append("vision")
        }
        if model.supportsThinkingDisplay {
            pieces.append("thinking")
        }
        return pieces.joined(separator: " · ")
    }

    private func compactTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M"
        }
        if tokens >= 1_000 {
            return "\(tokens / 1_000)K"
        }
        return "\(tokens)"
    }

    private func badge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    // MARK: - Editor

    private var editorCard: some View {
        settingsCard(title: isEditing ? "Edit Model" : "Add Model", systemImage: "plus.rectangle.on.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                settingRow("Provider") {
                    Picker("", selection: providerSelection) {
                        Text("None (advanced manual endpoint)").tag("")
                        ForEach(providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    .disabled(providers.isEmpty)
                }

                if let provider = providers.first(where: { $0.id == draft.providerID }) {
                    settingRow("") {
                        HStack(spacing: 8) {
                            Button {
                                fetchModels(for: provider)
                            } label: {
                                if fetchingProviderID == provider.id {
                                    HStack(spacing: 5) {
                                        ProgressView().controlSize(.small)
                                        Text("Checking…")
                                    }
                                } else {
                                    Label("Fetch models from \(provider.name)", systemImage: "arrow.down.circle")
                                }
                            }
                            .controlSize(.small)
                            .disabled(
                                fetchingProviderID == provider.id
                                || !canFetch(
                                    baseURL: provider.baseURL,
                                    apiKey: provider.apiKey,
                                    authScheme: provider.authScheme,
                                    providerID: provider.id
                                )
                            )
                            if let docsURL = provider.catalogDocumentationURL {
                                Link("Documentation", destination: docsURL)
                                    .font(.caption)
                            }
                            if fetchErrorProviderID == provider.id, let message = fetchErrorMessage {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    settingRow("Choose model") {
                        VStack(alignment: .leading, spacing: 6) {
                            // Large catalogs (OpenRouter returns ~300+) are unusable as a
                            // bare dropdown; a filter field narrows it as you type.
                            if selectableModelsForDraft.count > 12 {
                                TextField(
                                    "Filter \(selectableModelsForDraft.count) models (e.g. anthropic/)…",
                                    text: $modelFilterText
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                            }
                            HStack(spacing: 8) {
                                Picker("", selection: fetchedModelSelection) {
                                    Text(modelPickerPlaceholder(for: provider)).tag("")
                                    ForEach(filteredSelectableModels) { fetched in
                                        Text(modelPickerLabel(fetched)).tag(fetched.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 280)
                                .disabled(selectableModelsForDraft.isEmpty)
                                if !selectableModelsForDraft.isEmpty {
                                    Text(filteredCountLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onChange(of: draft.providerID) { _, _ in modelFilterText = "" }
                    }
                }

                if let provider = draftProvider,
                   ProviderPreset.matching(provider: provider) == nil {
                    Toggle("Advanced: allow an unverified model ID", isOn: $allowUnverifiedCustomModel)
                        .font(.caption)
                    Text("Use this only when a custom or local provider does not expose a complete model catalog.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                settingRow("Model id") {
                    TextField(modelIDPlaceholder, text: $draft.id)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                        .frame(maxWidth: 280)
                }
                settingRow("Model") {
                    TextField(modelNamePlaceholder, text: $draft.model)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onChange(of: draft.model) { _, newValue in
                            guard !isEditing else { return }
                            syncModelID(from: newValue)
                        }
                }
                settingRow("Display name") {
                    TextField(displayNamePlaceholder, text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                settingRow("API protocol") {
                    Picker("API protocol", selection: $draft.apiBackend) {
                        ForEach(ModelAPIBackend.allCases, id: \.self) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }

                if draft.providerID == nil {
                    // Manual endpoint + credential when not linked to a provider.
                    settingRow("Base URL") {
                        TextField("https://api.example.com/v1", text: $draft.baseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    settingRow("API key") {
                        HStack(spacing: 8) {
                            Group {
                                if revealKey {
                                    TextField("sk-… (leave empty for local servers)", text: $draft.apiKey)
                                } else {
                                    SecureField("sk-… (leave empty for local servers)", text: $draft.apiKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                            Button {
                                revealKey.toggle()
                            } label: {
                                Image(systemName: revealKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .help(revealKey ? "Hide API key" : "Show API key")
                        }
                    }
                    Text("Advanced manual models write the CLI-required api_key only to the owner-readable ~/.grok/config.toml file. Prefer a saved provider so its credential is also backed by Keychain. Local/open servers don't need a key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let provider = providers.first(where: { $0.id == draft.providerID }) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        Text("Endpoint and key come from \(provider.name) (\(provider.baseURL)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Divider()

                Text("Model metadata")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                settingRow("Context window") {
                    HStack(spacing: 8) {
                        TextField("Unknown", text: contextTokensBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                        Text("tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(contextTokenPresets) { preset in
                            Button(preset.label) {
                                draft.contextTokens = preset.value
                            }
                            .controlSize(.small)
                        }
                        Button("Clear") {
                            draft.contextTokens = nil
                        }
                        .controlSize(.small)
                    }
                }

                settingRow("Capabilities") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Supports reasoning effort", isOn: $draft.supportsReasoningEffort)
                        Toggle("Supports image input", isOn: $draft.supportsVision)
                        Toggle("Shows thinking blocks", isOn: $draft.supportsThinkingDisplay)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .frame(maxWidth: 280, alignment: .leading)
                }

                Text("API protocol and context window are native Grok settings. The capability checkboxes are GrokBuild-only UI hints kept outside config.toml.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(isEditing ? "Save Changes" : "Add Model") { saveDraft() }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftSaveBlockedReason != nil)
                    Button("Cancel") { resetDraft() }
                    Spacer()
                    if let error = draftSaveBlockedReason, !draft.model.isEmpty || !draft.id.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The draft with provider endpoint/credentials applied, used for validation and preview.
    private var resolvedDraft: CustomModel {
        draft.resolved(using: providers)
    }

    /// Binding for the fetched-model picker. Selecting an id fills the model name and derives
    /// the config.toml model id from it.
    private var fetchedModelSelection: Binding<String> {
        Binding(
            get: {
                let current = draft.model.trimmingCharacters(in: .whitespaces)
                return selectableModelsForDraft.contains(where: { $0.id == current }) ? current : ""
            },
            set: { newValue in
                guard !isEditing else {
                    if !newValue.isEmpty { draft.model = newValue }
                    return
                }
                if newValue.isEmpty {
                    draft.model = ""
                    draft.id = ""
                    draft.name = ""
                    return
                }
                draft.model = newValue
                syncModelID(from: newValue)
                if let picked = selectableModelsForDraft.first(where: { $0.id == newValue }),
                   let displayName = picked.ownedBy,
                   !displayName.isEmpty {
                    if draftProvider?.supportsLiveCatalogRefresh == true {
                        draft.name = ClinePassCatalog.displayName(for: displayName)
                    } else {
                        draft.name = displayName
                    }
                }
            }
        )
    }

    private func modelPickerLabel(_ model: FetchedModel) -> String {
        if let name = model.ownedBy, !name.isEmpty {
            return "\(name) — \(model.id)"
        }
        return model.id
    }

    /// Derives `draft.id` from a provider model name, uniquifying against existing models.
    private func syncModelID(from modelName: String) {
        let base = CustomModel.suggestedID(from: modelName)
        draft.id = uniquifiedModelID(base)
    }

    /// Returns a model id that does not collide with an existing entry (unless editing that entry).
    private func uniquifiedModelID(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        var candidate = trimmed
        var suffix = 2
        while models.contains(where: { $0.id == candidate && $0.id != editingID }) {
            candidate = "\(trimmed)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    /// Validation for the save button, including duplicate-id checks when adding a new model.
    private var draftSaveBlockedReason: String? {
        if let error = resolvedDraft.validationError { return error }
        if let provider = draftProvider {
            let appearsInCatalog = selectableModelsForDraft.contains { $0.id == draft.model }
            if ProviderPreset.matching(provider: provider) != nil, !appearsInCatalog {
                return "Test the connection and choose a model returned by this provider."
            }
            if ProviderPreset.matching(provider: provider) == nil,
               !appearsInCatalog,
               !allowUnverifiedCustomModel {
                return "Choose a fetched model, or explicitly allow an unverified custom model ID."
            }
        }
        if !isEditing, models.count >= CustomModelStore.maxModels {
            return "GrokBuild supports up to \(CustomModelStore.maxModels) custom models."
        }
        if !isEditing, models.contains(where: { $0.id == draft.id }) {
            return "A model with this id already exists."
        }
        return nil
    }

    /// Binding that maps the model's optional providerID to the picker's string tag.
    private var providerSelection: Binding<String> {
        Binding(
            get: { draft.providerID ?? "" },
            set: { newValue in
                allowUnverifiedCustomModel = false
                if newValue.isEmpty {
                    draft.providerID = nil
                } else {
                    draft.providerID = newValue
                    if let provider = providers.first(where: { $0.id == newValue }),
                       let preset = ProviderPreset.matching(provider: provider) {
                        draft.apiBackend = preset.defaultAPIBackend
                    }
                    if !isEditing {
                        draft.model = ""
                        draft.id = ""
                        draft.name = ""
                    }
                }
            }
        )
    }

    // MARK: - Actions

    private func reload() async {
        // Keychain reads can wait on securityd. Running them synchronously in this
        // SwiftUI task freezes every click and even the accessibility server.
        let loaded = await SettingsBackgroundLoader.run {
            (ProviderStore.loadResult(), CustomModelStore.load())
        }
        let providerLoad = loaded.0
        let snapshot = loaded.1
        providers = providerLoad.providers
        migrationIssues = providerLoad.migrationIssues
        defaultModelID = snapshot.defaultModelID ?? ""
        persistedDefaultModelID = defaultModelID
        // Repair a missing sidecar provider link only when the endpoint identifies exactly one
        // provider. Then re-resolve the
        // endpoint/credential from the provider so a model reflects a key added to its provider
        // even if its own config.toml table predates that key.
        let resolvedModels = snapshot.models.map { model in
            var m = model
            if m.providerID == nil {
                let matches = providers.filter { $0.baseURL == model.baseURL }
                if matches.count == 1 {
                    m.providerID = matches[0].id
                }
            }
            return m.resolved(using: providers)
        }
        models = resolvedModels

        let inferredProviderLinks = zip(snapshot.models, resolvedModels).contains { original, resolved in
            original.providerID != resolved.providerID
        }
        let needsCredentialProjection = zip(snapshot.models, resolvedModels).contains { original, resolved in
            original.apiKey != resolved.apiKey || original.baseURL != resolved.baseURL
        }
        if needsCredentialProjection && !providerLoad.migrationIssues.contains(where: { $0.kind == .storage }) {
            do {
                try CustomModelStore.save(
                    models: resolvedModels,
                    defaultModelID: snapshot.defaultModelID
                )
                statusMessage = "Provider credentials migrated to Keychain; secured CLI configuration."
            } catch {
                errorMessage = "Credential migration could not update config.toml: \(error.localizedDescription)"
            }
        } else if inferredProviderLinks {
            CustomModelMetadataStore.save(models: resolvedModels)
        }
    }

    // MARK: - Provider actions

    /// Installing a template stages it in the editor (key empty) instead of persisting it
    /// immediately — the provider is only saved once the user enters a key and taps Save.
    /// If the preset is already installed, jump to editing the existing one.
    private func addProviderPreset(_ preset: ProviderPreset) {
        if let existing = providers.first(where: { $0.id == preset.provider.id }) {
            beginEditingProvider(existing)
            return
        }
        providerDraft = preset.provider
        editingProviderID = nil
        providerDraftFromPreset = true
        revealProviderKey = false
        showingProviderEditor = true
        showingModelEditor = false
        scrollTarget = providerEditorAnchor
    }

    private func beginNewProvider() {
        providerDraft = Provider(id: "", name: "", baseURL: "")
        editingProviderID = nil
        providerDraftFromPreset = false
        revealProviderKey = false
        showingProviderEditor = true
        showingModelEditor = false
        scrollTarget = providerEditorAnchor
    }

    private func beginEditingProvider(_ provider: Provider) {
        providerDraft = provider
        editingProviderID = provider.id
        providerDraftFromPreset = false
        revealProviderKey = false
        showingProviderEditor = true
        showingModelEditor = false
        scrollTarget = providerEditorAnchor
    }

    private func resetProviderDraft() {
        providerDraft = Provider(id: "", name: "", baseURL: "")
        editingProviderID = nil
        providerDraftFromPreset = false
        revealProviderKey = false
        showingProviderEditor = false
    }

    private func saveProviderDraft() {
        guard providerDraft.validationError == nil else { return }
        let affectedModelIDs = Set(modelsUsingProviderID(editingProviderID ?? providerDraft.id).map(\.id))
        if let editingProviderID, let index = providers.firstIndex(where: { $0.id == editingProviderID }) {
            providers[index] = providerDraft
            // Propagate endpoint/credential changes to models linked to this provider.
            models = models.map { $0.providerID == editingProviderID ? $0.resolved(using: providers) : $0 }
        } else if let index = providers.firstIndex(where: { $0.id == providerDraft.id }) {
            providers[index] = providerDraft
        } else {
            providers.append(providerDraft)
        }
        do {
            try ProviderStore.save(providers)
            resetProviderDraft()
            persist(change: .models(affectedModelIDs))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Models currently attached to (in use by) the given provider.
    private func modelsUsing(_ provider: Provider) -> [CustomModel] {
        models.filter { $0.providerID == provider.id }
    }

    private func modelsUsingProviderID(_ providerID: String) -> [CustomModel] {
        models.filter { $0.providerID == providerID }
    }

    private func removeProvider(_ provider: Provider) {
        // A provider can only be removed once none of its models reference it, so the
        // user explicitly removes the models first and we never orphan config.toml tables.
        guard modelsUsing(provider).isEmpty else { return }
        providers.removeAll { $0.id == provider.id }
        do {
            try ProviderStore.save(providers)
            if editingProviderID == provider.id { resetProviderDraft() }
            fetchedModels[provider.id] = nil
            validationResults[provider.id] = nil
            persist(change: .models([]))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Fetch models

    /// Fetches the model catalog for the provider draft currently being edited/created.
    private func fetchModelsForDraft() {
        let draftSnapshot = providerDraft
        guard !draftSnapshot.baseURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        validateProvider(draftSnapshot)
    }

    /// Fetches the model catalog for an already-installed provider.
    private func fetchModels(for provider: Provider) {
        validateProvider(provider)
    }

    private func validateProvider(_ provider: Provider) {
        let key = provider.id.isEmpty ? "__draft__" : provider.id
        fetchingProviderID = key
        fetchErrorProviderID = nil
        fetchErrorMessage = nil
        let configuredModelIDs = models
            .filter { $0.providerID == provider.id || ($0.providerID == nil && $0.baseURL == provider.baseURL) }
            .map(\.model)
        Task {
            let result = await ProviderModelFetcher.validate(
                provider: provider,
                configuredModelIDs: configuredModelIDs
            )
            await MainActor.run {
                // Only clear the busy marker if it is still ours — a second provider's
                // check may have started while this one was in flight.
                if fetchingProviderID == key { fetchingProviderID = nil }
                // Never resurrect state for a provider removed mid-check.
                guard key == "__draft__" || providers.contains(where: { $0.id == key }) else { return }
                fetchedModels[key] = result.models
                validationResults[key] = result
                if result.status != .connected {
                    fetchErrorProviderID = key
                    fetchErrorMessage = result.message
                }
            }
        }
    }

    /// Models available for the provider linked to the current model draft (fetched or catalog).
    private var filteredSelectableModels: [FetchedModel] {
        ProviderModelFetcher.filterModels(selectableModelsForDraft, query: modelFilterText)
    }

    private var filteredCountLabel: String {
        let total = selectableModelsForDraft.count
        let shown = filteredSelectableModels.count
        return shown == total ? "\(total)" : "\(shown)/\(total)"
    }

    private var selectableModelsForDraft: [FetchedModel] {
        guard let id = draft.providerID,
              let provider = providers.first(where: { $0.id == id }) else { return [] }
        return selectableModels(for: provider)
    }

    private func modelPickerPlaceholder(for provider: Provider) -> String {
        hasFetchedModels(for: provider) ? "Pick a fetched model…" : "Fetch models first…"
    }

    private func canFetch(
        baseURL: String,
        apiKey: String,
        authScheme: ProviderAuthScheme,
        providerID: String = ""
    ) -> Bool {
        // The caller's real auth scheme must survive this reconstruction: omitting it
        // would apply the `.bearer` default and permanently disable "Test connection"
        // for keyless remote providers that explicitly chose `.none`.
        let provider = Provider(
            id: providerID,
            name: "",
            baseURL: baseURL,
            apiKey: apiKey,
            authScheme: authScheme
        )
        // Cline Pass uses the public recommended-models feed — no API key required.
        if provider.supportsLiveCatalogRefresh {
            return true
        }
        guard ProviderModelFetcher.modelsURL(for: baseURL) != nil else { return false }
        // Local servers accept no key; keyless (`.none`) providers never need one.
        if provider.isLocalEndpoint || provider.authScheme == .none { return true }
        return ProviderModelFetcher.resolveKey(apiKey: apiKey) != nil
    }

    // MARK: - Model actions

    private func beginNewModel(forProvider provider: Provider) {
        guard addModelDisabledReason(for: provider) == nil else { return }
        draft = CustomModel(
            id: "",
            model: "",
            baseURL: "",
            apiBackend: ProviderPreset.matching(provider: provider)?.defaultAPIBackend
                ?? .chatCompletions,
            providerID: provider.id
        )
        editingID = nil
        revealKey = false
        allowUnverifiedCustomModel = false
        errorMessage = nil
        showingModelEditor = true
        showingProviderEditor = false
        scrollTarget = modelEditorAnchor
    }

    /// Opens the model editor for a brand-new manual model (no provider preselected).
    private func beginNewModel() {
        draft = freshModelDraft()
        editingID = nil
        revealKey = false
        allowUnverifiedCustomModel = false
        errorMessage = nil
        showingModelEditor = true
        showingProviderEditor = false
        scrollTarget = modelEditorAnchor
    }

    private func beginEditing(_ model: CustomModel) {
        draft = model
        editingID = model.id
        revealKey = false
        allowUnverifiedCustomModel = false
        errorMessage = nil
        showingModelEditor = true
        showingProviderEditor = false
        scrollTarget = modelEditorAnchor
    }

    private func resetDraft() {
        draft = freshModelDraft()
        editingID = nil
        revealKey = false
        allowUnverifiedCustomModel = false
        showingModelEditor = false
    }

    /// A blank model draft that defaults to the first provider (if any) so the endpoint is
    /// inherited and the manual base_url/key fields stay hidden. Prefills the provider's
    /// suggested starting model.
    private func freshModelDraft() -> CustomModel {
        if let provider = providers.first {
            return CustomModel(
                id: "",
                model: "",
                baseURL: "",
                apiBackend: ProviderPreset.matching(provider: provider)?.defaultAPIBackend
                    ?? .chatCompletions,
                providerID: provider.id
            )
        }
        return CustomModel(id: "", model: "", baseURL: "")
    }

    /// The provider currently linked to the model draft, if any.
    private var draftProvider: Provider? {
        guard let id = draft.providerID else { return nil }
        return providers.first { $0.id == id }
    }

    private var modelIDPlaceholder: String {
        let trimmed = draft.model.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return CustomModel.suggestedID(from: trimmed)
        }
        return "my-model-id"
    }

    private var modelNamePlaceholder: String {
        if draftProvider != nil {
            return "Pick a model above"
        }
        return "provider-model-name"
    }

    private var displayNamePlaceholder: String {
        let trimmed = draft.model.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            return "\(trimmed) (optional)"
        }
        return "Display name (optional)"
    }

    private func saveDraft() {
        guard draftSaveBlockedReason == nil else { return }
        let changedModelIDs = Set([draft.id] + (editingID.map { [$0] } ?? []))
        var updated = models
        if let editingID, let index = updated.firstIndex(where: { $0.id == editingID }) {
            updated[index] = draft
        } else {
            updated.append(draft)
        }
        models = updated
        resetDraft()
        persist(change: .models(changedModelIDs))
    }

    private func remove(_ model: CustomModel) {
        models.removeAll { $0.id == model.id }
        if defaultModelID == model.id {
            defaultModelID = ""
        }
        if editingID == model.id { resetDraft() }
        persist(change: .models([model.id]))
    }

    private func persist(change: ConfigurationChange) {
        do {
            let resolvedModels = models.map { $0.resolved(using: providers) }
            let selectedDefault = defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            try CustomModelStore.save(
                models: resolvedModels,
                defaultModelID: selectedDefault.isEmpty ? nil : selectedDefault
            )
            statusMessage = "Saved to ~/.grok/config.toml."
            errorMessage = nil
            persistedDefaultModelID = defaultModelID
            onConfigurationChanged(change)
        } catch {
            errorMessage = "Failed to save config.toml: \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    // MARK: - Card / row helpers

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct MCPSettingsPane: View {
    let onConfigurationChanged: () -> Void

    private let service = GrokCLIService()
    @State private var servers: [GrokMCPServerInfo] = []
    @State private var doctorReport: GrokMCPDoctorReport?
    @State private var name = ""
    @State private var transport = "stdio"
    @State private var target = ""
    @State private var scope = "user"
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "MCP Servers",
                    subtitle: "Connect external tools and check their status.",
                    systemImage: SettingsTab.mcpServers.systemImage
                )
                Button("Run Doctor") {
                    Task { await runDoctor() }
                }
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    TextField("Name", text: $name)
                    Picker("Transport", selection: $transport) {
                        Text("stdio").tag("stdio")
                        Text("http").tag("http")
                        Text("sse").tag("sse")
                    }
                    .labelsHidden()
                    Picker("Scope", selection: $scope) {
                        Text("User").tag("user")
                        Text("Project").tag("project")
                    }
                    .labelsHidden()
                }
                GridRow {
                    TextField(transport == "stdio" ? "Command and args" : "URL", text: $target)
                        .gridCellColumns(2)
                    Button("Add / Update") {
                        Task { await addServer() }
                    }
                    .disabled(name.isEmpty || target.isEmpty)
                }
            }

            List {
                ForEach(servers) { server in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(server.name)
                                .font(.headline)
                            Text([server.transport, server.source].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !server.target.isEmpty {
                                Text(server.target)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                        Button("Check") {
                            Task { await runDoctor(name: server.name) }
                        }
                        Button("Remove", role: .destructive) {
                            Task { await removeServer(server) }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .overlay {
                if servers.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No MCP Servers",
                        systemImage: SettingsTab.mcpServers.systemImage,
                        description: Text("Add a server or refresh this list.")
                    )
                }
            }

            if let doctorReport {
                Divider()
                Text("Check Results: \(doctorReport.healthyCount) healthy, \(doctorReport.failingCount) failing")
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(doctorReport.servers) { server in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Circle()
                                        .fill(server.healthy ? .green : .red)
                                        .frame(width: 8, height: 8)
                                    Text(server.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(server.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(server.checks, id: \.self) { check in
                                    HStack(alignment: .top) {
                                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(check.passed ? .green : .red)
                                        VStack(alignment: .leading) {
                                            Text(check.label)
                                            if !check.detail.isEmpty {
                                                Text(check.detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !check.hint.isEmpty {
                                                Text(check.hint)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.large))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            if isLoading { ProgressView() }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .task { await refresh() }
    }

    private func header(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
    }

    private func refresh() async {
        await perform {
            servers = try await service.listMCPServers()
        }
    }

    private func runDoctor(name: String? = nil) async {
        await perform {
            doctorReport = try await service.mcpDoctor(name: name)
        }
    }

    private func addServer() async {
        await perform {
            try await service.addMCPServer(name: name, transport: transport, target: target, scope: scope)
            name = ""
            target = ""
            servers = try await service.listMCPServers()
            onConfigurationChanged()
        }
    }

    private func removeServer(_ server: GrokMCPServerInfo) async {
        await perform {
            try await service.removeMCPServer(name: server.name)
            servers = try await service.listMCPServers()
            onConfigurationChanged()
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        // Rapid re-taps must not stack concurrent CLI mutations.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct PermissionsSettingsPane: View {
    let onConfigurationChanged: () -> Void

    @AppStorage(GrokSettingsKeys.permissionMode) private var permissionMode = GrokPermissionSettings.defaults.permissionMode
    @AppStorage(GrokSettingsKeys.sandboxProfile) private var sandboxProfile = GrokPermissionSettings.defaults.sandboxProfile
    @AppStorage(GrokSettingsKeys.reasoningEffort) private var reasoningEffort = GrokPermissionSettings.defaults.reasoningEffort
    @AppStorage(GrokSettingsKeys.disableWebSearch) private var disableWebSearch = GrokPermissionSettings.defaults.disableWebSearch
    @AppStorage(GrokSettingsKeys.noSubagents) private var noSubagents = GrokPermissionSettings.defaults.noSubagents
    @AppStorage(GrokSettingsKeys.allowRules) private var allowRules = GrokPermissionSettings.defaults.allowRules
    @AppStorage(GrokSettingsKeys.denyRules) private var denyRules = GrokPermissionSettings.defaults.denyRules

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                launchFlagsCard
                safetyTogglesCard
                permissionRulesCard
                applyCard
            }
            .centeredSettingsColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Palette.canvas)
        .onAppear {
            permissionMode = GrokPermissionMode.normalizedStoredValue(permissionMode)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            settingsPaneHeader(
                "Permissions",
                subtitle: "Control how Grok asks for approval and accesses your project.",
                systemImage: SettingsTab.permissions.systemImage
            )
            Text(permissionModeChoice.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var launchFlagsCard: some View {
        settingsCard(title: "Launch Behavior", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                settingRow("Permission mode", description: permissionModeChoice.explanation) {
                    Picker("", selection: $permissionMode) {
                        Section("Interactive") {
                            ForEach(GrokPermissionMode.interactiveChoices) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        Section("Advanced") {
                            ForEach(GrokPermissionMode.advancedChoices) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: AppTheme.Layout.settingsControlWidth)
                }

                if permissionModeChoice == .alwaysApprove {
                    Label(
                        "Tool prompts are skipped, but deny rules, hooks, and the selected sandbox remain enforced.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                } else if permissionModeChoice == .denyUnapproved {
                    Label(
                        "This is a deny-by-default automation policy, not a low-interruption interactive mode.",
                        systemImage: "nosign"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                settingRow("Sandbox", description: "Limits file system and command access for Grok.") {
                    Picker("", selection: $sandboxProfile) {
                        Text("Default").tag("")
                        Text("Workspace").tag("workspace")
                        Text("Read-only").tag("read-only")
                        Text("Strict").tag("strict")
                        Text("Devbox").tag("devbox")
                    }
                    .labelsHidden()
                    .frame(width: AppTheme.Layout.settingsControlWidth)
                }

                settingRow("Default reasoning effort", description: "Reasoning budget for new projects. Each project keeps its own effort — change the current chat from the composer's model menu.") {
                    Picker("", selection: $reasoningEffort) {
                        ForEach(ReasoningEffortLevel.menuCases) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: AppTheme.Layout.settingsControlWidth)
                }
            }
        }
    }

    private var safetyTogglesCard: some View {
        settingsCard(title: "Session Capabilities", systemImage: "switch.2") {
            VStack(alignment: .leading, spacing: 12) {
                permissionToggle("Disable web search tools", subtitle: "Prevent Grok from using web search in new sessions.", isOn: $disableWebSearch)
                Divider()
                permissionToggle("Disable subagents", subtitle: "Keep work inside the main Grok agent only.", isOn: $noSubagents)
            }
        }
    }

    private var permissionRulesCard: some View {
        settingsCard(title: "Permission Rules", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enter one `--allow` or `--deny` rule per line, for example `Bash(npm*)` or `Edit(/etc/**)`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 14) {
                    ruleEditor(title: "Allow Rules", text: $allowRules)
                    ruleEditor(title: "Deny Rules", text: $denyRules)
                }
            }
        }
    }

    private var applyCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apply changes")
                    .font(.headline)
                Text("Restarts the active Grok connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply Changes") {
                onConfigurationChanged()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }

    private var permissionModeChoice: GrokPermissionMode {
        GrokPermissionMode(storedValue: permissionMode)
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }

    private func settingRow<Content: View>(
        _ title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360, alignment: .leading)
            .layoutPriority(1)

            Spacer()
            content()
        }
    }

    private func permissionToggle(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        SettingsToggleRow(title, subtitle: subtitle, isOn: isOn)
    }

    private func ruleEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.medium))
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: AppTheme.Layout.settingsRuleEditorHeight)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.large).stroke(AppTheme.Palette.glassBorder))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MemorySettingsPane: View {
    let onConfigurationChanged: () -> Void

    @AppStorage(GrokSettingsKeys.memoryEnabled) private var memoryEnabled = GrokPermissionSettings.defaults.memoryEnabled
    @State private var appliedMemoryEnabled = UserDefaults.standard.bool(forKey: GrokSettingsKeys.memoryEnabled)
    @State private var showBrowser = false
    @State private var showRemember = false
    @State private var rememberText = ""
    @State private var statusMessage: String?

    private var hasPendingChanges: Bool { memoryEnabled != appliedMemoryEnabled }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                enableCard
                actionsCard
            }
            .centeredSettingsColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Palette.canvas)
        .sheet(isPresented: $showBrowser) {
            MemoryBrowserPanel()
        }
        .sheet(isPresented: $showRemember) {
            rememberSheet
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            settingsPaneHeader(
                "Memory",
                subtitle: "Let Grok recall useful context across sessions.",
                systemImage: SettingsTab.memory.systemImage
            )
            Text(memoryEnabled ? "On" : "Off")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var enableCard: some View {
        settingsCard(title: "Cross-Session Memory", systemImage: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(
                    "Use cross-session memory",
                    subtitle: "Applies to new and restarted sessions.",
                    isOn: $memoryEnabled
                )

                Text("Stored locally on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Apply Changes") {
                        appliedMemoryEnabled = memoryEnabled
                        onConfigurationChanged()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasPendingChanges)
                }
            }
        }
    }

    private var actionsCard: some View {
        settingsCard(title: "Manage Memory", systemImage: "tray.full") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        showBrowser = true
                    } label: {
                        Label("Browse Memory Files…", systemImage: "folder")
                    }
                    Button {
                        rememberText = ""
                        showRemember = true
                    } label: {
                        Label("Remember…", systemImage: "text.badge.plus")
                    }
                    .disabled(!memoryEnabled)
                    Spacer()
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text("Remember saves a note that becomes searchable in future sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rememberSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remember a Note")
                .font(.headline)
            Text("Saved to your global memory (`\(MemoryStore.globalMemoryURL.path)`).")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $rememberText)
                .font(.body)
                .frame(minWidth: 380, minHeight: 120)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.large).stroke(Color(nsColor: .separatorColor)))
            HStack {
                Spacer()
                Button("Cancel") { showRemember = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveRemember() }
                    .buttonStyle(.borderedProminent)
                    .disabled(rememberText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func saveRemember() {
        let text = rememberText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            let url = try MemoryStore.appendGlobalNote(text)
            statusMessage = "Saved to \(url.path)."
        } catch {
            statusMessage = error.localizedDescription
        }
        showRemember = false
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }
}

private struct WorkflowsSettingsPane: View {
    let onConfigurationChanged: () -> Void

    @State private var workflowsEnabled = WorkflowsConfigStore.loadEnabled()
    @State private var appliedEnabled = WorkflowsConfigStore.loadEnabled()
    @State private var statusMessage: String?

    private var hasPendingChanges: Bool { workflowsEnabled != appliedEnabled }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                enableCard
                infoCard
            }
            .centeredSettingsColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Palette.canvas)
        .onReceive(NotificationCenter.default.publisher(for: .workflowsConfigChanged)) { _ in
            let enabled = WorkflowsConfigStore.loadEnabled()
            workflowsEnabled = enabled
            appliedEnabled = enabled
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            settingsPaneHeader(
                "Workflows",
                subtitle: "Run project workflows in the background.",
                systemImage: SettingsTab.workflows.systemImage
            )
            Text(workflowsEnabled ? "On" : "Off")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var enableCard: some View {
        settingsCard(title: "Background Workflows", systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(
                    "Enable workflows",
                    subtitle: "Shared with Grok Build CLI sessions.",
                    isOn: $workflowsEnabled
                )

                Text("Skills remain available separately from the composer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Apply Changes") {
                        do {
                            try WorkflowsConfigStore.setEnabled(workflowsEnabled)
                            appliedEnabled = workflowsEnabled
                            statusMessage = "Saved. Restarting sessions…"
                            onConfigurationChanged()
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasPendingChanges)
                }
            }
        }
    }

    private var infoCard: some View {
        settingsCard(title: "Saved Workflows", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Project workflows appear in Session controls, where you can start, pause, or stop them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open config.toml") {
                    openPath(WorkflowsConfigStore.configURL.path)
                }
                .controlSize(.small)
            }
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }
}

private struct CompatibilitySettingsPane: View {
    let onConfigurationChanged: () -> Void

    private let service = GrokCLIService()
    @State private var cursorEnabled = CompatConfigStore.loadEnabled(.cursor)
    @State private var claudeEnabled = CompatConfigStore.loadEnabled(.claude)
    @State private var codexEnabled = CompatConfigStore.loadEnabled(.codex)
    @State private var appliedCursor = CompatConfigStore.loadEnabled(.cursor)
    @State private var appliedClaude = CompatConfigStore.loadEnabled(.claude)
    @State private var appliedCodex = CompatConfigStore.loadEnabled(.codex)
    @State private var externalCompat: [GrokExternalCompatInfo] = []
    @State private var statusMessage: String?
    @State private var isLoading = false

    private var hasPendingChanges: Bool {
        cursorEnabled != appliedCursor || claudeEnabled != appliedClaude || codexEnabled != appliedCodex
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    settingsPaneHeader(
                        "Compatibility",
                        subtitle: "Import the capability groups Grok supports from other coding agents.",
                        systemImage: SettingsTab.compatibility.systemImage
                    )
                    Button("Refresh") {
                        Task { await loadExternalCompat() }
                    }
                    .controlSize(.small)
                }

                settingsCard(title: "Import From", systemImage: SettingsTab.compatibility.systemImage) {
                    VStack(alignment: .leading, spacing: 12) {
                        compatToggle("Cursor", binding: $cursorEnabled)
                        compatToggle("Claude Code", binding: $claudeEnabled)
                        compatToggle("Codex", binding: $codexEnabled)

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Spacer()
                            Button("Apply Changes") {
                                applyCompat()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasPendingChanges)
                        }
                    }
                }

                if !externalCompat.isEmpty {
                    settingsCard(title: "Detected Sources", systemImage: "magnifyingglass") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(externalCompat) { item in
                                HStack {
                                    Text(item.name)
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                    Text(item.isEnabled ? "On" : "Off")
                                        .font(.caption)
                                        .foregroundStyle(item.isEnabled ? .green : .secondary)
                                }
                            }
                        }
                    }
                }

                if isLoading {
                    ProgressView()
                }
            }
            .centeredSettingsColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Palette.canvas)
        .task { await loadExternalCompat() }
    }

    private func compatToggle(_ title: String, binding: Binding<Bool>) -> some View {
        SettingsToggleRow(
            title,
            subtitle: title == "Codex"
                ? "Use compatible \(title) sessions in GrokBuild."
                : "Use compatible \(title) skills, rules, agents, MCPs, hooks, and sessions.",
            isOn: binding
        )
    }

    private func applyCompat() {
        do {
            try CompatConfigStore.setEnabled(.cursor, cursorEnabled)
            try CompatConfigStore.setEnabled(.claude, claudeEnabled)
            try CompatConfigStore.setEnabled(.codex, codexEnabled)
            appliedCursor = cursorEnabled
            appliedClaude = claudeEnabled
            appliedCodex = codexEnabled
            statusMessage = "Saved. Restarting sessions…"
            onConfigurationChanged()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadExternalCompat() async {
        isLoading = true
        externalCompat = (try? await service.listExternalCompat()) ?? []
        isLoading = false
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }
}

private struct AppUpdatesSettingsPane: View {
    @State private var updateRevision = 0

    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { UpdateSettingsStore.autoCheckEnabled },
            set: { UpdateSettingsStore.autoCheckEnabled = $0 }
        )
    }

    var body: some View {
        // UpdateScheduler stores its receipts statically rather than through an
        // observable model. Reading this revision ties the kept-alive App pane to
        // the update-state notification so a just-updated CLI version cannot stay
        // visually stale until the user leaves and reopens Settings.
        let _ = updateRevision
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPaneHeader(
                    title: "App Updates",
                    subtitle: "Keep GrokBuild and the Grok CLI current.",
                    systemImage: SettingsTab.app.systemImage
                )

                updatesCard(title: "Installed Version", systemImage: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppVersion.display)
                            .font(.body)
                        if let lastCheck = UpdateSettingsStore.lastCheckDate {
                            Text("Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not checked yet this session.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                updatesCard(title: "Automatic Checks", systemImage: "clock.arrow.circlepath") {
                    SettingsToggleRow(
                        "Automatically check for updates",
                        subtitle: "Checks on launch and about once per day while GrokBuild is running.",
                        isOn: autoCheckBinding
                    )
                }

                updatesCard(title: "grok CLI", systemImage: "terminal") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let cli = UpdateScheduler.cachedCLIStatus {
                            switch cli.state {
                            case .upToDate(let info), .updateAvailable(let info):
                                Text("Installed: \(info.current)")
                                    .font(.body)
                                Text("Latest: \(info.latest)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let channel = info.channel, !channel.isEmpty {
                                    Text("Channel: \(channel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            case .notInstalled:
                                Text("Not installed")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            case .checkFailed(let message):
                                Text("Could not check: \(message)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Not checked yet this session.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if UpdateScheduler.hasActionableCLIUpdate,
                           let latest = UpdateScheduler.cachedCLIStatus?.latestVersion {
                            Text("grok CLI \(latest) is ready to update.")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                updatesCard(title: "Check Now", systemImage: "arrow.down.circle") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Check for app and CLI updates.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Check for Updates…") {
                            Task { @MainActor in
                                await UpdateUI.presentUpdatePanel(refresh: true)
                            }
                        }
                        if UpdateScheduler.hasActionableAppUpdate,
                           let release = UpdateScheduler.cachedAppRelease {
                            Text("GrokBuild \(release.latestVersion) is ready to install.")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .centeredSettingsColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Palette.canvas)
        .onReceive(NotificationCenter.default.publisher(for: .grokBuildUpdateStateChanged)) { _ in
            updateRevision &+= 1
        }
    }

    private func updatesCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(AppTheme.Palette.glassBorder)
        )
    }
}
