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

    var accessibilityIdentifier: String {
        "grok-settings-tab-\(rawValue)"
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
    var onSettingsApplyRequest: (SettingsApplyRequest) async -> SettingsApplyReceipt = {
        $0.receipt
    }

    /// Shared pane state lives above the selected view tree. Hidden panes unmount and
    /// cancel their `.task`s without discarding an explicit draft.
    @State private var memoryValueState = SettingsValueState<Bool>.unloaded(
        default: GrokPermissionSettings.defaults.memoryEnabled
    )
    @State private var memoryLoadState = SettingsLoadState.checking
    @State private var agentValueState = SettingsValueState<String>.unloaded(default: "")
    @State private var modelValueState = SettingsValueState<String>.unloaded(default: "")
    /// The Models pane's loaded catalog and provider state outlive the selected view tree.
    /// Its view can unmount when another pane is selected without discarding expensive state.
    @State private var retainedCustomModelsViewModel = CustomModelsSettingsViewModel()
    @State private var permissionValueState = SettingsValueState<PermissionSettingsDraft>.unloaded(
        default: .defaults
    )
    @State private var browserValueState = SettingsValueState<BrowserSettings>.unloaded(
        default: .defaults
    )
    @State private var computerUseValueState = SettingsValueState<ComputerUsePaneSettings>.unloaded(
        default: .defaults
    )
    @State private var workflowsValueState = SettingsValueState<Bool>.unloaded(default: true)
    @State private var compatibilityValueState = SettingsValueState<CompatibilitySettingsDraft>.unloaded(
        default: .defaults
    )
    @State private var appValueState = SettingsValueState<AppSettingsDraft>.unloaded(default: .defaults)
    @AccessibilityFocusState private var settingsPaneFocus: SettingsTab?
    @State private var mcpDraft = GrokMCPServerDraft()
    @State private var mcpAcknowledgedLiteralStorage = false
    @State private var mcpInventory = SettingsInventoryState<[GrokMCPServerInfo]>(empty: [])
    @State private var skillsInventory = SettingsInventoryState<[GrokSkillInfo]>(empty: [])
    @State private var pluginsInventory = SettingsInventoryState<[GrokPluginInfo]>(empty: [])
    @State private var marketplacePluginsInventory = SettingsInventoryState<[GrokPluginInfo]>(empty: [])
    @State private var marketplaceSourcesInventory = SettingsInventoryState<[GrokMarketplaceSource]>(empty: [])
    @State private var hooksInventory = SettingsInventoryState<[GrokHookInfo]>(empty: [])
    @State private var compatibilityInventory = SettingsInventoryState<[GrokExternalCompatInfo]>(empty: [])
    @State private var paneLoadInterval: GrokBuildPerformanceInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    onBackToChat()
                } label: {
                    HStack(spacing: 4) {
                        TitlebarGlyph(systemName: "chevron.left", pointSize: 12)
                        Text("Back")
                    }
                }
                .buttonStyle(GrokChromeButtonStyle())
                .foregroundStyle(AppTheme.Palette.titlebarControl)
                .keyboardShortcut(.cancelAction)

                Text("Settings")
                    .font(AppTheme.Typography.heading)

                Menu {
                    ForEach(SettingsSection.allCases) { section in
                        Section(section.title) {
                            ForEach(section.tabs) { tab in
                                Button {
                                    selectedTab = tab
                                } label: {
                                    Label(tab.title, systemImage: tab.systemImage)
                                }
                                .accessibilityIdentifier(tab.accessibilityIdentifier)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selectedTab.systemImage)
                        Text(selectedTab.title)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Choose a settings pane")
                .accessibilityLabel("Settings navigation")
                .accessibilityValue(selectedTab.title)
                Spacer()
            }
            .padding(.leading, TitlebarMetrics.trafficLightLeading)
            .padding(.trailing, 18)
            .padding(.top, TitlebarMetrics.contentTopInset)
            .frame(height: TitlebarMetrics.overlayTopInset)
            .background(AppTheme.Palette.chrome)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.Palette.divider)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings header")

            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(AppTheme.Palette.canvas)
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(AppTheme.Palette.canvas)
        .onAppear {
            measureSelectedPaneLoad()
            settingsPaneFocus = selectedTab
        }
        .onChange(of: selectedTab) { _, tab in
            measureSelectedPaneLoad()
            Task { @MainActor in
                await Task.yield()
                settingsPaneFocus = tab
            }
        }
        .onExitCommand(perform: onBackToChat)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }

    private func measureSelectedPaneLoad() {
        paneLoadInterval?.end()
        let interval = GrokBuildPerformance.begin(.settingsPaneLoad)
        paneLoadInterval = interval
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            interval.end()
            if paneLoadInterval === interval {
                paneLoadInterval = nil
            }
        }
    }

    /// Only the selected pane owns a view/task tree. Shared pane value state stays in
    /// SettingsView, while hidden diagnostics, polling, and subprocess tasks cancel.
    private var settingsContent: some View {
        settingsPane(for: selectedTab)
            .id(selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityFocused($settingsPaneFocus, equals: selectedTab)
            .accessibilityLabel("\(selectedTab.title) settings")
            .accessibilitySortPriority(1)
    }

    @ViewBuilder
    private func settingsPane(for tab: SettingsTab) -> some View {
        switch tab {
        case .agents:
            AgentsSettingsPane(
                workspace: store.currentWorkspace,
                valueState: $agentValueState,
                liveReceipt: store.effectiveSessionReceipt,
                onApply: onSettingsApplyRequest
            )
            .settingsPaneColumn()

        case .models:
            CustomModelsSettingsPane(
                valueState: $modelValueState,
                viewModel: retainedCustomModelsViewModel,
                liveReceipt: store.effectiveSessionReceipt,
                onApply: onSettingsApplyRequest,
                onConfigurationChanged: onConfigurationChanged
            )

        case .permissions:
            PermissionsSettingsPane(
                valueState: $permissionValueState,
                liveReceipt: store.effectiveSessionReceipt,
                configurationStatusMessage: store.configurationStatusMessage,
                onApply: onSettingsApplyRequest
            )

        case .memory:
            MemorySettingsPane(
                valueState: $memoryValueState,
                loadState: $memoryLoadState,
                liveReceipt: store.effectiveSessionReceipt,
                configurationStatusMessage: store.configurationStatusMessage,
                onApply: onSettingsApplyRequest
            )

        case .workflows:
            WorkflowsSettingsPane(
                valueState: $workflowsValueState,
                liveReceipt: store.effectiveSessionReceipt,
                configurationStatusMessage: store.configurationStatusMessage,
                onApply: onSettingsApplyRequest
            )

        case .browser:
            BrowserSettingsPane(
                valueState: $browserValueState,
                liveReceipt: store.effectiveSessionReceipt,
                configurationStatusMessage: store.configurationStatusMessage,
                onApply: onSettingsApplyRequest
            )

        case .computerUse:
            ComputerUseSettingsPane(
                valueState: $computerUseValueState,
                liveReceipt: store.effectiveSessionReceipt,
                configurationStatusMessage: store.configurationStatusMessage,
                onApply: onSettingsApplyRequest
            )

        case .mcpServers:
            MCPSettingsPane(
                workspace: store.currentWorkspace,
                inventory: $mcpInventory,
                draft: $mcpDraft,
                acknowledgedLiteralStorage: $mcpAcknowledgedLiteralStorage,
                onApply: onSettingsApplyRequest
            )
            .settingsPaneColumn()

        case .skills:
            SkillsSettingsPane(
                workspace: store.currentWorkspace,
                inventory: $skillsInventory
            )
                .settingsPaneColumn()

        case .plugins:
            PluginsSettingsPane(
                inventory: $pluginsInventory,
                onApply: onSettingsApplyRequest
            )
            .settingsPaneColumn()

        case .marketplace:
            MarketplaceSettingsPane(
                pluginsInventory: $marketplacePluginsInventory,
                sourcesInventory: $marketplaceSourcesInventory,
                onApply: onSettingsApplyRequest
            )
            .settingsPaneColumn()

        case .compatibility:
            CompatibilitySettingsPane(
                valueState: $compatibilityValueState,
                inventory: $compatibilityInventory,
                onApply: onSettingsApplyRequest
            )

        case .hooks:
            HooksSettingsPane(
                workspace: store.currentWorkspace,
                inventory: $hooksInventory
            )
                .settingsPaneColumn()

        case .app:
            AppUpdatesSettingsPane(
                valueState: $appValueState,
                liveReceipt: store.effectiveSessionReceipt,
                onApply: onSettingsApplyRequest
            )
        }
    }
}

/// Hidden panes are absent from the view tree, so SwiftUI cancels their `.task`s.
enum SettingsPaneLifecycle {
    static func shouldMount(_ tab: SettingsTab, selected: SettingsTab) -> Bool {
        tab == selected
    }
}

func openPath(_ path: String) {
    let expanded = (path as NSString).expandingTildeInPath
    NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
}

struct SettingsPaneHeader: View {
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

func settingsPaneHeader(_ title: String, subtitle: String, systemImage: String) -> SettingsPaneHeader {
    SettingsPaneHeader(title: title, subtitle: subtitle, systemImage: systemImage)
}

struct SettingsPaneStateHeader: View {
    let status: SettingsValueStatus

    private var icon: String {
        switch status {
        case .draft: return "pencil"
        case .saved: return "checkmark"
        case .restartRequired: return "arrow.clockwise"
        case .live: return "checkmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var body: some View {
        Label(status.rawValue, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Settings state")
            .accessibilityValue(status.accessibilityValue)
            .accessibilityHint("Draft, saved, applied, and live process state are reported separately.")
    }
}

struct SettingsLoadStateView: View {
    let state: SettingsLoadState
    var retry: (() -> Void)? = nil

    var body: some View {
        switch state {
        case .content:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking saved and live settings…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue("Checking")
        case .empty(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel(message)
        case .stale(let message), .error(let message):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let retry {
                    Button("Retry", action: retry)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

struct SettingsFormRow<Control: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String?
    let control: () -> Control

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.control = control
    }

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalRow
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalRow
                verticalRow
            }
        }
    }

    private var horizontalRow: some View {
        HStack(alignment: .center, spacing: 14) {
            copy
                .frame(maxWidth: 420, alignment: .leading)
                .layoutPriority(1)
            Spacer(minLength: 12)
            control()
                .frame(minHeight: 44, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            copy
            control()
                .frame(minHeight: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copy: some View {
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
    }
}

struct SettingsApplyBar: View {
    let canApply: Bool
    let isApplying: Bool
    let scopeText: String
    let validationMessage: String?
    let receipt: SettingsApplyReceipt?
    let onRevert: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isApplying ? "Applying saved changes…" : "Apply changes")
                        .font(.headline)
                    Text(validationMessage ?? receipt?.summary ?? scopeText)
                        .font(.caption)
                        .foregroundStyle(validationMessage == nil ? .secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Revert", action: onRevert)
                    .disabled(!canApply || isApplying)
                Button(isApplying ? "Applying…" : "Apply", action: onApply)
                    .buttonStyle(GrokProminentButtonStyle())
                    .disabled(!canApply || isApplying)
            }

            if isApplying {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Applying Settings")
            }
        }
        .settingsSectionSurface(emphasized: canApply || isApplying)
        .accessibilityElement(children: .contain)
        .accessibilityValue(receipt?.accessibilityValue ?? scopeText)
    }
}

struct SettingsReceiptDisclosure: View {
    let receipt: SettingsApplyReceipt?

    var body: some View {
        if let receipt {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Configuration generation \(receipt.configurationGeneration)")
                    if let target = receipt.target {
                        Text("Requested tab \(shortID(target.localTabID?.uuidString)); backend \(shortID(target.backendSessionID)); process \(target.processGeneration.map(String.init) ?? "none")")
                    }
                    if let live = receipt.effectiveSession {
                        Text("Result tab \(shortID(live.localTabID?.uuidString)); backend \(shortID(live.backendSessionID)); process \(live.processGeneration)")
                        Text("Reconnect outcome: \(live.launchOutcome.rawValue); receipt: \(live.freshness.rawValue)")
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 6)
            } label: {
                Label("Apply receipt", systemImage: "doc.text.magnifyingglass")
                    .font(.caption.weight(.medium))
            }
            .accessibilityValue(receipt.accessibilityValue)
        }
    }

    private func shortID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        return value.count > 8 ? "…\(value.suffix(8))" : value
    }
}

struct SettingsDestructiveActionRow: View {
    let title: String
    let consequence: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        SettingsFormRow(title, subtitle: consequence) {
            Button(buttonTitle, role: .destructive, action: action)
        }
        .accessibilityHint(consequence)
    }
}

struct SettingsRowOperationReceiptView: View {
    let receipt: SettingsRowOperationReceipt
    var onCancel: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if receipt.status == .running {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
            Text(receipt.summary)
                .font(.caption)
                .foregroundStyle(receipt.status == .failure ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if receipt.status == .running, let onCancel {
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(receipt.accessibilityValue)
    }

    private var icon: String {
        switch receipt.status {
        case .running: return "clock"
        case .success: return "checkmark.circle"
        case .failure: return "xmark.circle"
        case .cancelled: return "slash.circle"
        }
    }
}

/// A full-width macOS settings row with a small, consistently aligned switch.
///
/// SwiftUI's default switch hugs the intrinsic width of its label, which made
/// controls drift through the middle of otherwise identical cards. Giving the
/// copy a flexible column keeps every switch on one quiet trailing axis.
struct SettingsToggleRow: View {
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

extension View {
    /// Routine Settings groups use one continuous document surface. Warnings,
    /// credentials, and receipts keep their own explicit containment.
    func settingsSectionSurface(emphasized: Bool = false) -> some View {
        self
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(emphasized ? AppTheme.Palette.glassBorderStrong : AppTheme.Palette.divider)
                    .frame(height: emphasized ? 2 : 1)
            }
    }

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
