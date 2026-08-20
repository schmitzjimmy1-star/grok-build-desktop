import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct BrowserSettingsPane: View {
    @Binding var valueState: SettingsValueState<BrowserSettings>
    let liveReceipt: EffectiveSessionReceipt?
    let configurationStatusMessage: String?
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt

    @State private var probeState = BrowserBackendProbeState()
    @State private var externalStatus = ExternalBrowserStatus.unavailable(endpoint: "http://127.0.0.1:9222")
    @State private var statusProbeTask: Task<Void, Never>?
    @State private var isInstallingRuntime = false
    @State private var isStartingExternalBrowser = false
    @State private var installOutput: String?
    @State private var externalBrowserOutput: String?
    @State private var showBrowserSessionOptions = false
    @State private var showQuickPresets = false
    @State private var showDiagnosticsLog = false
    @State private var showRuntimeUninstallConfirmation = false
    @State private var isApplying = false

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
            await loadPersistedState()
            normalizeExternalBrowserSelection()
            guard !Task.isCancelled else { return }
            startStatusRefresh()
        }
        .onChange(of: valueState.configurationGeneration) { _, _ in
            startStatusRefresh()
        }
        .onChange(of: liveReceipt) { _, receipt in
            let liveEnabled = receipt?.freshness == .live ? receipt?.browserEnabled : nil
            let liveSettings = liveEnabled.map { enabled in
                var settings = valueState.applied
                settings.enabled = enabled
                return settings
            }
            valueState.refreshLive(liveSettings)
        }
        .onDisappear {
            statusProbeTask?.cancel()
            statusProbeTask = nil
            probeState.cancel()
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
                    isOn: enabledBinding
                )
            }
        }
    }

    private var statusCard: some View {
        settingsCard(title: "Browser Support", systemImage: status?.isReady == true ? "checkmark.circle" : "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(browserStatusTitle, systemImage: browserStatusIcon)
                        .foregroundStyle(browserStatusColor)
                        .font(.headline)
                    Spacer()
                    if probeState.isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Checking browser support")
                    }
                    Button(probeState.isChecking ? "Checking..." : "Run Diagnostics") {
                        startStatusRefresh()
                    }
                    .disabled(probeState.isChecking)
                }

                if let status, status.isReady {
                    Text("Browser support is ready. Choose a managed browser or connect an existing Chromium app below.")
                        .foregroundStyle(.secondary)

                } else if let status, status.isInstalled {
                    Text("Browser support is installed. Add the managed runtime below for the recommended setup.")
                        .foregroundStyle(.secondary)

                } else if status != nil {
                    Text("Install browser support before enabling this feature.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        installCommandRow(title: "Homebrew", command: "brew install agent-browser")
                        installCommandRow(title: "npm", command: "npm install -g agent-browser")
                    }
                } else if let errorMessage = probeState.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Button("Retry") {
                        startStatusRefresh()
                    }
                } else {
                    Text("Checking browser support…")
                        .foregroundStyle(.secondary)
                }

                if status != nil, let errorMessage = probeState.errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        Spacer()
                        Button("Retry") {
                            startStatusRefresh()
                        }
                    }
                }

                if probeState.canShowSetupControls,
                   let installOutput, !installOutput.isEmpty {
                    Text(installOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                        .foregroundStyle(.secondary)
                }

                if let path = status?.executablePath {
                    infoLine("Path", path)
                }
                if let version = status?.version, !version.isEmpty {
                    infoLine("Version", version)
                }

                if let status {
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
        valueState.updateDraft(applied)
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
                        Label(managedRuntimeStatusText, systemImage: status?.isReady == true ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)

                        SettingsToggleRow(
                            "Show browser window while agents work",
                            subtitle: "Opens the managed automation browser visibly instead of keeping it headless. Apply and restart Grok after changing this.",
                            isOn: showBrowserWindowBinding
                        )

                        HStack {
                            Button("Use Managed Runtime") {
                                mutateDraft { $0.runtimeMode = .managed }
                            }
                            .disabled(selectedRuntimeMode == .managed)

                            if let status, status.isReady {
                                Button(isInstallingRuntime ? "Repairing..." : "Reinstall / Repair Runtime") {
                                    Task { await installBrowserRuntime() }
                                }
                                .disabled(!status.isInstalled || isInstallingRuntime)

                                Button("Uninstall Runtime...", role: .destructive) {
                                    showRuntimeUninstallConfirmation = true
                                }
                                .disabled(!AgentBrowserService.hasManagedRuntimeDirectory())
                            } else if let status {
                                Button(isInstallingRuntime ? "Installing..." : "Install Managed Runtime") {
                                    Task { await installBrowserRuntime() }
                                }
                                .disabled(!status.isInstalled || isInstallingRuntime)
                            }

                            if probeState.canShowSetupControls {
                                Button("Copy Install Command") {
                                    copyToPasteboard("agent-browser install")
                                }
                            }
                        }

                        if let status, !status.isInstalled {
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
                            Picker("", selection: externalBrowserAppIDBinding) {
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
                                    TextField("Path to Chromium .app", text: externalBrowserAppPathBinding)
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
                            isOn: autoStartExternalBrowserBinding
                        )

                        settingRow("CDP URL") {
                            TextField("For the command below: http://127.0.0.1:9222", text: cdpURLBinding)
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
                                mutateDraft {
                                    $0.runtimeMode = .external
                                    $0.cdpURL = defaultCDPURL
                                    $0.autoStartExternalBrowser = true
                                }
                            }

                            Button(isStartingExternalBrowser ? "Starting..." : "Start Browser Now") {
                                Task { await startExternalBrowser() }
                            }
                            .disabled(
                                isStartingExternalBrowser
                                    || valueState.isDirty
                                    || appliedSettings.runtimeMode != .external
                            )

                            Button("Check Status") {
                                startStatusRefresh()
                            }
                            .disabled(probeState.isChecking)

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
                            TextField("Optional named browser session", text: profileNameBinding)
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
        VStack(alignment: .leading, spacing: 10) {
            SettingsApplyBar(
                canApply: valueState.canApply,
                isApplying: isApplying,
                scopeText: "Saves Browser settings and restarts only the current live tab. Diagnostics remain read-only.",
                validationMessage: valueState.validation.message,
                receipt: valueState.lastOperationReceipt,
                onRevert: { valueState.revert() },
                onApply: { Task { await applyChanges() } }
            )
            SettingsReceiptDisclosure(receipt: valueState.lastOperationReceipt)
            if let configurationStatusMessage, isApplying {
                Text(configurationStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func refreshStatus() async {
        let configurationGeneration = valueState.configurationGeneration
        let request = probeState.begin(configurationGeneration: configurationGeneration)
        async let browserStatus = AgentBrowserService.status()
        async let browserExternalStatus = AgentBrowserService.externalBrowserStatus(settings: appliedSettings)
        do {
            let resolvedStatus = try await browserStatus
            let resolvedExternalStatus = await browserExternalStatus
            try Task.checkCancellation()
            if probeState.resolve(
                resolvedStatus,
                request: request,
                currentConfigurationGeneration: valueState.configurationGeneration
            ) {
                externalStatus = resolvedExternalStatus
            }
        } catch is CancellationError {
            return
        } catch {
            _ = probeState.fail(
                error,
                request: request,
                currentConfigurationGeneration: valueState.configurationGeneration
            )
        }
    }

    @MainActor
    private func startStatusRefresh() {
        statusProbeTask?.cancel()
        statusProbeTask = Task { @MainActor in
            await refreshStatus()
        }
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
        isStartingExternalBrowser = true
        externalBrowserOutput = "Starting \(selectedExternalBrowserApp.displayName) with a separate GrokBuild automation profile..."
        defer { isStartingExternalBrowser = false }

        do {
            externalStatus = try await AgentBrowserService.launchExternalBrowser(settings: appliedSettings)
            externalBrowserOutput = externalStatus.diagnostic
        } catch {
            externalBrowserOutput = error.localizedDescription
            externalStatus = await AgentBrowserService.externalBrowserStatus(settings: appliedSettings)
        }
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
            mutateDraft {
                $0.externalBrowserAppID = .custom
                $0.externalBrowserAppPath = url.path
            }
        }
    }

    private var statusBadge: some View {
        let text: String
        if !appliedSettings.enabled {
            text = "Disabled"
        } else if let status {
            text = status.isReady ? "Ready" : "Setup needed"
        } else if probeState.errorMessage != nil {
            text = "Check failed"
        } else {
            text = "Checking"
        }

        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var selectedExternalBrowserApp: ExternalBrowserAppID {
        currentSettings.externalBrowserAppID
    }

    private var selectedRuntimeMode: BrowserRuntimeMode {
        currentSettings.runtimeMode
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
        mutateDraft { $0.externalBrowserAppID = installedKnownExternalBrowsers.first ?? .custom }
    }

    private var externalBrowserLaunchCommand: String {
        AgentBrowserService.externalBrowserLaunchCommand(settings: currentSettings)
    }

    private var externalBrowserStatusText: String {
        if externalStatus.isReachable {
            return externalStatus.browserName.map { "External browser running: \($0)" }
                ?? "External browser running at \(externalStatus.endpoint)"
        }
        if selectedExternalBrowserApp == .custom && currentSettings.externalBrowserAppPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a Chromium app to start automatically"
        }
        return "External browser not running yet"
    }

    private var defaultCDPURL: String {
        "http://127.0.0.1:9222"
    }

    private var managedRuntimeStatusText: String {
        guard let status else { return "Checking browser support…" }
        if status.isReady {
            return "Managed runtime installed and ready"
        }
        if status.isInstalled {
            return "Managed runtime not ready or not installed"
        }
        return "Install agent-browser CLI first"
    }

    private var currentSettings: BrowserSettings { valueState.draft }
    private var appliedSettings: BrowserSettings { valueState.applied }
    private var status: BrowserBackendStatus? { probeState.settledStatus }

    private func mutateDraft(_ body: (inout BrowserSettings) -> Void) {
        var draft = valueState.draft
        body(&draft)
        valueState.updateDraft(draft)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<BrowserSettings, Value>) -> Binding<Value> {
        Binding(
            get: { valueState.draft[keyPath: keyPath] },
            set: { newValue in
                mutateDraft { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var enabledBinding: Binding<Bool> { binding(\.enabled) }
    private var cdpURLBinding: Binding<String> { binding(\.cdpURL) }
    private var profileNameBinding: Binding<String> { binding(\.profileName) }
    private var showBrowserWindowBinding: Binding<Bool> { binding(\.showBrowserWindow) }
    private var externalBrowserAppIDBinding: Binding<String> {
        Binding(
            get: { valueState.draft.externalBrowserAppID.rawValue },
            set: { raw in
                mutateDraft {
                    $0.externalBrowserAppID = ExternalBrowserAppID(rawValue: raw)
                        ?? BrowserSettings.defaults.externalBrowserAppID
                }
            }
        )
    }
    private var externalBrowserAppPathBinding: Binding<String> { binding(\.externalBrowserAppPath) }
    private var autoStartExternalBrowserBinding: Binding<Bool> { binding(\.autoStartExternalBrowser) }

    @MainActor
    private func loadPersistedState() async {
        guard !valueState.isLoaded else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let loaded = await SettingsBackgroundLoader.run {
            (saved: BrowserSettingsStore.load(), applied: BrowserSettingsStore.loadApplied())
        }
        guard !Task.isCancelled else { return }
        let saved = loaded.saved
        let applied = loaded.applied
        let liveEnabled = liveReceipt?.freshness == .live ? liveReceipt?.browserEnabled : nil
        let live = liveEnabled.map { enabled in
            var settings = applied
            settings.enabled = enabled
            return settings
        }
        valueState.load(persisted: saved, applied: applied, live: live)
    }

    @MainActor
    private func applyChanges() async {
        guard valueState.canApply else { return }
        let draft = valueState.draft
        let request = SettingsApplyRequest(
            configurationGeneration: valueState.configurationGeneration + 1,
            capability: .browser,
            persistenceOwner: .userDefaults,
            applyScope: .activeTabRestart,
            requiresProcessRestart: true,
            redactedSummary: "Saved Browser settings; applying them to the current live tab when eligible."
        )
        BrowserSettingsStore.save(draft)
        BrowserSettingsStore.saveApplied(draft)
        valueState.recordSaved(
            applied: draft,
            requiresRestart: liveReceipt?.freshness == .live,
            receipt: request.receipt
        )
        isApplying = true
        let receipt = await onApply(request)
        isApplying = false
        guard !Task.isCancelled else { return }
        let live = receipt.effectiveSession?.freshness == .live
            ? receipt.effectiveSession.map { receipt in
                var settings = draft
                settings.enabled = receipt.browserEnabled
                return settings
            }
            : nil
        valueState.complete(receipt: receipt, live: live)
    }

    private var hasPendingBrowserChanges: Bool {
        valueState.isDirty
    }

    private var browserStatusTitle: String {
        guard let status else {
            return probeState.errorMessage == nil ? "Checking browser support…" : "Browser support check failed"
        }
        if status.isReady { return "agent-browser ready" }
        if status.isInstalled { return "agent-browser setup needed" }
        return "agent-browser not installed"
    }

    private var browserStatusIcon: String {
        guard let status else {
            return probeState.errorMessage == nil ? "hourglass" : "exclamationmark.triangle"
        }
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
        .settingsSectionSurface()
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
