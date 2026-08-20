import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct PluginsSettingsPane: View {
    @Binding var inventory: SettingsInventoryState<[GrokPluginInfo]>
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt

    private let service = GrokCLIService()
    @State private var installSource = ""
    @State private var trustInstall = false
    @State private var selectedDetails: String?
    @State private var isLoading = false
    @State private var activeOperationID: String?
    @State private var activeOperationIsCancellable = false
    @State private var operationTask: Task<Void, Never>?
    @State private var rowReceipts: [String: SettingsRowOperationReceipt] = [:]
    @State private var pendingUninstall: GrokPluginInfo?

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

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("GitHub repo, Git URL, or local path", text: $installSource)
                    Button("Install") {
                        startInstall()
                    }
                    .disabled(
                        installSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !trustInstall
                            || activeOperationID != nil
                    )
                }

                Toggle("I reviewed and trust this source", isOn: $trustInstall)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                Text("Install is a direct CLI action. GrokBuild requires an explicit trust decision, then restarts only the current live tab; plugin data may remain after uninstall unless the CLI removes it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let receipt = rowReceipts["install"] {
                SettingsRowOperationReceiptView(receipt: receipt)
            }

            List {
                ForEach(inventory.value) { plugin in
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
                            Text(pluginStatus(plugin))
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
                                startMutation(plugin, action: plugin.isEnabled ? "Disable" : "Enable") {
                                    try await service.setPlugin(name: plugin.name, enabled: !plugin.isEnabled)
                                }
                            }
                            Button("Details") {
                                startDetails(plugin)
                            }
                            Button("Update") {
                                startMutation(plugin, action: "Update") {
                                    try await service.updatePlugin(name: plugin.name)
                                }
                            }
                            Button("Uninstall", role: .destructive) {
                                pendingUninstall = plugin
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 20, height: 20)
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.small)
                        .fixedSize()
                        .help("Plugin actions")
                        .accessibilityLabel("Plugin actions")

                        if let receipt = rowReceipts[plugin.id] {
                            SettingsRowOperationReceiptView(
                                receipt: receipt,
                                onCancel: activeOperationID == plugin.id && activeOperationIsCancellable
                                    ? { cancelOperation(plugin.id) }
                                    : nil
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if inventory.value.isEmpty && !isLoading {
                    SettingsLoadStateView(
                        state: inventory.loadState,
                        retry: { Task { await refresh() } }
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
        .task { await refresh() }
        .onDisappear {
            operationTask?.cancel()
            operationTask = nil
        }
        .confirmationDialog(
            "Uninstall \(pendingUninstall?.name ?? "plugin")?",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let plugin = pendingUninstall {
                Button("Uninstall \(plugin.name)", role: .destructive) {
                    pendingUninstall = nil
                    startMutation(plugin, action: "Uninstall") {
                        try await service.uninstallPlugin(name: plugin.name, keepData: false)
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingUninstall = nil }
        } message: {
            Text("The plugin is removed through the Grok CLI. Its persistent data may also be removed; this action cannot be represented as a harmless Apply toggle.")
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
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.plain)
            .help("Refresh plugins")
            .accessibilityLabel("Refresh plugins")
        }
    }

    private func refresh() async {
        isLoading = true
        inventory.beginRefresh(staleMessage: "Refreshing installed plugins…")
        do {
            let plugins = try await service.listPlugins()
            guard !Task.isCancelled else { return }
            inventory.finish(
                plugins,
                isEmpty: plugins.isEmpty,
                emptyMessage: "No plugins are installed. Grok completed the inventory successfully."
            )
        } catch {
            guard !Task.isCancelled else { return }
            inventory.fail(error.localizedDescription)
        }
        isLoading = false
    }

    private func startInstall() {
        let source = installSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let rowID = "install"
        startOperation(rowID: rowID, action: "Install", mutatesConfiguration: true, cancellable: false) {
            try await service.installPlugin(source: source, trust: true)
            installSource = ""
            trustInstall = false
        }
    }

    private func startDetails(_ plugin: GrokPluginInfo) {
        startOperation(rowID: plugin.id, action: "Load details", mutatesConfiguration: false, cancellable: true) {
            selectedDetails = try await service.pluginDetails(name: plugin.name)
        }
    }

    private func startMutation(
        _ plugin: GrokPluginInfo,
        action: String,
        operation: @escaping () async throws -> Void
    ) {
        startOperation(
            rowID: plugin.id,
            action: action,
            mutatesConfiguration: true,
            cancellable: false,
            operation: operation
        )
    }

    private func startOperation(
        rowID: String,
        action: String,
        mutatesConfiguration: Bool,
        cancellable: Bool,
        operation: @escaping () async throws -> Void
    ) {
        guard activeOperationID == nil else { return }
        activeOperationID = rowID
        activeOperationIsCancellable = cancellable
        rowReceipts[rowID] = .running(
            rowID: rowID,
            summary: "\(action) is running for this plugin.",
            scope: mutatesConfiguration ? .activeTabRestart : .externalConfigOnly
        )
        operationTask = Task {
            do {
                try await operation()
                try Task.checkCancellation()
                var applyReceipt: SettingsApplyReceipt?
                if mutatesConfiguration {
                    let request = SettingsApplyRequest(
                        configurationGeneration: inventory.nextConfigurationGeneration(),
                        capability: .plugins,
                        persistenceOwner: .externalIntegration,
                        applyScope: .activeTabRestart,
                        requiresProcessRestart: true,
                        requiresPermissionOrTrust: action == "Install",
                        redactedSummary: "Plugin \(action.lowercased()) completed; restarting only the current live tab when eligible."
                    )
                    applyReceipt = await onApply(request)
                    try Task.checkCancellation()
                    await refresh()
                }
                rowReceipts[rowID] = .completed(
                    rowID: rowID,
                    status: applyReceipt?.status == .failure ? .failure : .success,
                    summary: applyReceipt?.summary ?? "\(action) completed.",
                    scope: mutatesConfiguration ? .activeTabRestart : .externalConfigOnly,
                    applyReceipt: applyReceipt
                )
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                rowReceipts[rowID] = .completed(
                    rowID: rowID,
                    status: cancelled ? .cancelled : .failure,
                    summary: cancelled
                        ? "Operation cancelled. Refresh to confirm the plugin's current state."
                        : error.localizedDescription,
                    scope: mutatesConfiguration ? .activeTabRestart : .externalConfigOnly
                )
            }
            activeOperationID = nil
            activeOperationIsCancellable = false
            operationTask = nil
        }
    }

    private func cancelOperation(_ rowID: String) {
        guard activeOperationID == rowID, activeOperationIsCancellable else { return }
        operationTask?.cancel()
    }

    private func pluginStatus(_ plugin: GrokPluginInfo) -> String {
        if plugin.status.localizedCaseInsensitiveContains("update") { return "Update available" }
        if plugin.status.localizedCaseInsensitiveContains("fail") { return "Failed" }
        return plugin.isEnabled ? "Enabled" : "Disabled"
    }
}
