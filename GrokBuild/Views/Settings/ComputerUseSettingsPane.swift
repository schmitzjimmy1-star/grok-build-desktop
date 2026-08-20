import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct ComputerUseSettingsPane: View {
    @Binding var valueState: SettingsValueState<ComputerUsePaneSettings>
    let liveReceipt: EffectiveSessionReceipt?
    let configurationStatusMessage: String?
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt

    @State private var backendStatus = ComputerUseBackendStatus.unavailable
    @State private var cursorInstallStatus = ComputerUseCursorInstallStatus.unavailable
    @State private var permissionStatus = ComputerUsePermissionStatus.unavailable
    @State private var permissionProbe: AccessibilityTrustProbe?
    @State private var grokBuildAXGranted = false
    @State private var grokBuildSRGranted = false
    @State private var isRunningEndToEndTest = false
    @State private var endToEndResult: ComputerUseService.EndToEndTestResult?
    @State private var isApplying = false
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
            await loadPersistedState()
            await refreshStatus()
            // Deliberately no Cursor config sync here: ~/.cursor/mcp.json is
            // the user's file, and merely opening Settings must not rewrite
            // it. Writes happen on explicit Install/Update/Apply only.
        }
        .onChange(of: liveReceipt) { _, receipt in
            let liveEnabled = receipt?.freshness == .live ? receipt?.computerUseEnabled : nil
            let live = liveEnabled.map { enabled in
                var settings = valueState.applied
                settings.settings.enabled = enabled
                return settings
            }
            valueState.refreshLive(live)
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
                    isOn: enabledBinding
                )
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
                        Text(endToEndResult.compactDetail)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        if let endToEndResult, !endToEndResult.diagnostic.isEmpty {
                            Text("Self-test receipt")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(endToEndResult.diagnostic)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                                .foregroundStyle(.secondary)
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
                    Label(showDiagnosticsLog ? "Hide diagnostics" : "Show diagnostics", systemImage: "doc.text.magnifyingglass")
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
        computerSettingsCard(title: "macOS Permissions", systemImage: permissionStatus.isReady(includeScreenshots: appliedSettings.includeScreenshots) ? "lock.open" : "lock.shield") {
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
                            help: ComputerUseService.usesBundledAgentDesktop(settings: appliedSettings)
                                ? "The acting binary. Bundled copies share the app's signing identity, so one grant covers all three."
                                : "The acting binary. External copies have their own identity — this grant is the one that matters."
                        )
                        if !ComputerUseService.usesBundledAgentDesktop(settings: appliedSettings),
                           let agentDesktopPath = ComputerUseService.executableURL(settings: appliedSettings)?.path {
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
                    Picker("", selection: permissionPolicyBinding) {
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
                    isOn: includeScreenshotsBinding
                )
                if appliedSettings.includeScreenshots,
                   !ComputerUseService.localScreenRecordingGranted() {
                    Button("Request Screen Recording") {
                        // macOS only receives a permission prompt from this explicit user
                        // action, never from opening the pane or editing a draft toggle.
                        ComputerUseService.requestScreenRecordingAccess()
                        Task { await refreshStatus() }
                    }
                }

                Stepper("Command timeout: \(currentSettings.commandTimeoutSeconds)s", value: commandTimeoutBinding, in: 5...180, step: 5)
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
                    isOn: cursorIntegrationBinding
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
        VStack(alignment: .leading, spacing: 10) {
            SettingsApplyBar(
                canApply: valueState.canApply,
                isApplying: isApplying,
                scopeText: "Saves Computer Use and Cursor integration settings, then restarts only the current live tab. macOS permissions are requested only by their explicit buttons.",
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

    private var currentSettings: ComputerUseSettings { valueState.draft.settings }
    private var appliedSettings: ComputerUseSettings { valueState.applied.settings }
    private var cursorIntegrationEnabled: Bool { valueState.draft.cursorIntegrationEnabled }
    private var appliedCursorIntegrationEnabled: Bool { valueState.applied.cursorIntegrationEnabled }

    private func mutateDraft(_ body: (inout ComputerUsePaneSettings) -> Void) {
        var draft = valueState.draft
        body(&draft)
        valueState.updateDraft(draft)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { valueState.draft.settings.enabled },
            set: { enabled in mutateDraft { $0.settings.enabled = enabled } }
        )
    }

    private var permissionPolicyBinding: Binding<String> {
        Binding(
            get: { valueState.draft.settings.permissionPolicy.rawValue },
            set: { raw in
                mutateDraft {
                    $0.settings.permissionPolicy = ComputerUsePermissionPolicy(rawValue: raw)
                        ?? ComputerUseSettings.defaults.permissionPolicy
                }
            }
        )
    }

    private var includeScreenshotsBinding: Binding<Bool> {
        Binding(
            get: { valueState.draft.settings.includeScreenshots },
            set: { enabled in mutateDraft { $0.settings.includeScreenshots = enabled } }
        )
    }

    private var commandTimeoutBinding: Binding<Int> {
        Binding(
            get: { valueState.draft.settings.commandTimeoutSeconds },
            set: { timeout in mutateDraft { $0.settings.commandTimeoutSeconds = timeout } }
        )
    }

    private var cursorIntegrationBinding: Binding<Bool> {
        Binding(
            get: { valueState.draft.cursorIntegrationEnabled },
            set: { enabled in mutateDraft { $0.cursorIntegrationEnabled = enabled } }
        )
    }

    @MainActor
    private func loadPersistedState() async {
        guard !valueState.isLoaded else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let loaded = await SettingsBackgroundLoader.run {
            (
                persisted: ComputerUsePaneSettings(
                    settings: ComputerUseSettingsStore.load(),
                    cursorIntegrationEnabled: UserDefaults.standard.bool(
                        forKey: ComputerUseSettingsKeys.cursorIntegrationEnabled
                    )
                ),
                applied: ComputerUsePaneSettings(
                    settings: ComputerUseSettingsStore.loadApplied(),
                    cursorIntegrationEnabled: UserDefaults.standard.bool(
                        forKey: ComputerUseSettingsKeys.appliedCursorIntegrationEnabled
                    )
                )
            )
        }
        guard !Task.isCancelled else { return }
        let persisted = loaded.persisted
        let applied = loaded.applied
        let liveEnabled = liveReceipt?.freshness == .live ? liveReceipt?.computerUseEnabled : nil
        let live = liveEnabled.map { enabled in
            var pane = applied
            pane.settings.enabled = enabled
            return pane
        }
        valueState.load(persisted: persisted, applied: applied, live: live)
    }

    private var hasPendingChanges: Bool {
        valueState.isDirty
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

    @MainActor
    private func applyChanges() async {
        guard valueState.canApply else { return }
        let draft = valueState.draft
        let priorCursorIntegrationEnabled = valueState.applied.cursorIntegrationEnabled
        let request = SettingsApplyRequest(
            configurationGeneration: valueState.configurationGeneration + 1,
            capability: .computerUse,
            persistenceOwner: .userDefaults,
            applyScope: .activeTabRestart,
            requiresProcessRestart: true,
            requiresPermissionOrTrust: false,
            redactedSummary: "Saved Computer Use launch settings; macOS permission state is checked separately."
        )
        ComputerUseSettingsStore.save(draft.settings)
        ComputerUseSettingsStore.saveApplied(draft.settings)
        UserDefaults.standard.set(
            draft.cursorIntegrationEnabled,
            forKey: ComputerUseSettingsKeys.cursorIntegrationEnabled
        )
        UserDefaults.standard.set(
            draft.cursorIntegrationEnabled,
            forKey: ComputerUseSettingsKeys.appliedCursorIntegrationEnabled
        )
        valueState.recordSaved(
            applied: draft,
            requiresRestart: liveReceipt?.freshness == .live,
            receipt: request.receipt
        )

        if draft.cursorIntegrationEnabled && !priorCursorIntegrationEnabled {
            await installForCursor(showErrorsOnly: false)
        } else if !draft.cursorIntegrationEnabled && priorCursorIntegrationEnabled {
            await removeCursorIntegration()
        } else {
            syncCursorConfiguration(showErrorsOnly: true)
        }

        isApplying = true
        let receipt = await onApply(request)
        isApplying = false
        guard !Task.isCancelled else { return }
        let live = receipt.effectiveSession?.freshness == .live
            ? receipt.effectiveSession.map { receipt in
                var pane = draft
                pane.settings.enabled = receipt.computerUseEnabled
                return pane
            }
            : nil
        valueState.complete(receipt: receipt, live: live)
        await refreshStatus()
    }

    private func syncCursorConfiguration(showErrorsOnly: Bool = false) {
        guard cursorInstallStatus.isInstalled else { return }
        do {
            if let message = try ComputerUseService.syncCursorIntegrationIfInstalled(settings: currentSettings) {
                if !showErrorsOnly {
                    cursorInstallOutput = message
                }
            }
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
        let settings = appliedSettings
        async let status = ComputerUseService.status(settings: settings)
        async let overview = ComputerUseService.permissionOverview(settings: settings)
        let resolvedStatus = await status
        let resolvedOverview = await overview
        guard !Task.isCancelled else { return }
        backendStatus = resolvedStatus
        permissionStatus = resolvedOverview.resolved
        permissionProbe = resolvedOverview.probe
        grokBuildAXGranted = resolvedOverview.grokBuildAccessibilityGranted
        grokBuildSRGranted = resolvedOverview.grokBuildScreenRecordingGranted
        cursorInstallStatus = ComputerUseCursorInstaller.status()
    }

    private func runEndToEndTest() async {
        isRunningEndToEndTest = true
        defer { isRunningEndToEndTest = false }
        endToEndResult = await ComputerUseService.runEndToEndTest(settings: appliedSettings)
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
            mutateDraft { $0.cursorIntegrationEnabled = false }
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
            permissionOutput = try await ComputerUseService.requestPermissions(settings: appliedSettings)
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
        .settingsSectionSurface()
    }
}
