import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct MarketplaceSettingsPane: View {
    @Binding var pluginsInventory: SettingsInventoryState<[GrokPluginInfo]>
    @Binding var sourcesInventory: SettingsInventoryState<[GrokMarketplaceSource]>
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt

    private let service = GrokCLIService()
    @State private var marketplaceSource = ""
    @State private var sourceTrustConfirmed = false
    @State private var availableFilter = ""
    @State private var isLoading = false
    @State private var trustedPluginIDs: Set<String> = []
    @State private var activeOperationID: String?
    @State private var operationTask: Task<Void, Never>?
    @State private var rowReceipts: [String: SettingsRowOperationReceipt] = [:]
    @State private var pendingUninstall: GrokPluginInfo?
    @State private var pendingSourceRemoval: GrokMarketplaceSource?

    private var availablePlugins: [GrokPluginInfo] {
        pluginsInventory.value.filter { $0.status == "available" }
    }

    private var installedPlugins: [GrokPluginInfo] {
        pluginsInventory.value.filter { $0.status != "available" }
    }

    private var marketplaceSources: [GrokMarketplaceSource] { sourcesInventory.value }

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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Marketplace Git URL or owner/repo", text: $marketplaceSource)
                    Button("Add Source") {
                        startAddMarketplace()
                    }
                    .disabled(
                        marketplaceSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !sourceTrustConfirmed
                            || activeOperationID != nil
                    )
                }
                Toggle("I reviewed and trust this marketplace source", isOn: $sourceTrustConfirmed)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                if let receipt = rowReceipts["add-source"] {
                    SettingsRowOperationReceiptView(receipt: receipt)
                }
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
                if pluginsInventory.value.isEmpty && !isLoading {
                    SettingsLoadStateView(
                        state: pluginsInventory.loadState,
                        retry: { Task { await refresh() } }
                    )
                }
            }

            if isLoading { ProgressView() }
            if !pluginsInventory.value.isEmpty, pluginsInventory.loadState != .content {
                SettingsLoadStateView(
                    state: pluginsInventory.loadState,
                    retry: { Task { await refresh() } }
                )
            }
            if !sourcesInventory.value.isEmpty, sourcesInventory.loadState != .content {
                SettingsLoadStateView(
                    state: sourcesInventory.loadState,
                    retry: { Task { await refresh() } }
                )
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
                    startPluginMutation(plugin, action: "Uninstall") {
                        try await service.uninstallPlugin(name: plugin.name, keepData: false)
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingUninstall = nil }
        } message: {
            Text("The Grok CLI may remove the plugin's persistent data. The affected row will report the actual result.")
        }
        .confirmationDialog(
            "Remove marketplace source?",
            isPresented: Binding(
                get: { pendingSourceRemoval != nil },
                set: { if !$0 { pendingSourceRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let source = pendingSourceRemoval {
                Button("Remove \(source.name)", role: .destructive) {
                    pendingSourceRemoval = nil
                    startSourceRemoval(source)
                }
            }
            Button("Cancel", role: .cancel) { pendingSourceRemoval = nil }
        } message: {
            Text("Available plugins from this source will disappear. Installed plugins are not represented as removed until the refreshed CLI inventory says so.")
        }
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
                        pendingSourceRemoval = source
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help("Remove source")
                }
                if let receipt = rowReceipts[source.id] {
                    SettingsRowOperationReceiptView(receipt: receipt)
                    .padding(.top, 5)
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
                    Text([plugin.marketplace, plugin.source, plugin.componentSummary].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if showInstall {
                    Button("Install") {
                        startInstallAvailablePlugin(plugin)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!trustedPluginIDs.contains(plugin.id) || activeOperationID != nil)
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

            if showInstall {
                Toggle(
                    "I reviewed and trust \(plugin.marketplace.isEmpty ? "this source" : plugin.marketplace)",
                    isOn: Binding(
                        get: { trustedPluginIDs.contains(plugin.id) },
                        set: { trusted in
                            if trusted { trustedPluginIDs.insert(plugin.id) }
                            else { trustedPluginIDs.remove(plugin.id) }
                        }
                    )
                )
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }

            if !showInstall {
                Menu {
                    Button(plugin.isEnabled ? "Disable" : "Enable") {
                        startPluginMutation(plugin, action: plugin.isEnabled ? "Disable" : "Enable") {
                            try await service.setPlugin(name: plugin.name, enabled: !plugin.isEnabled)
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
            }

            if let receipt = rowReceipts[plugin.id] {
                SettingsRowOperationReceiptView(receipt: receipt)
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
        isLoading = true
        pluginsInventory.beginRefresh(staleMessage: "Refreshing marketplace plugins…")
        sourcesInventory.beginRefresh(staleMessage: "Refreshing marketplace sources…")
        let interval = GrokBuildPerformance.begin(.settingsMarketplaceLoad)
        defer {
            interval.end()
            isLoading = false
        }
        do {
            let plugins = try await service.listPlugins(includeAvailable: true)
            guard !Task.isCancelled else { return }
            pluginsInventory.finish(
                plugins,
                isEmpty: plugins.isEmpty,
                emptyMessage: "No marketplace plugins are available. The source inventory loaded successfully."
            )
        } catch {
            guard !Task.isCancelled else { return }
            pluginsInventory.fail(error.localizedDescription)
        }

        do {
            let sources = try await service.listMarketplaceSources()
            guard !Task.isCancelled else { return }
            sourcesInventory.finish(
                sources,
                isEmpty: sources.isEmpty,
                emptyMessage: "No marketplace sources are configured."
            )
        } catch {
            guard !Task.isCancelled else { return }
            sourcesInventory.fail(error.localizedDescription)
        }
    }

    private func startInstallAvailablePlugin(_ plugin: GrokPluginInfo) {
        guard trustedPluginIDs.contains(plugin.id) else { return }
        startPluginMutation(plugin, action: "Install") {
            try await service.installPlugin(source: plugin.name, trust: true)
            trustedPluginIDs.remove(plugin.id)
        }
    }

    private func startPluginMutation(
        _ plugin: GrokPluginInfo,
        action: String,
        operation: @escaping () async throws -> Void
    ) {
        startOperation(rowID: plugin.id, action: action, operation: operation)
    }

    private func startAddMarketplace() {
        let source = marketplaceSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sourceTrustConfirmed else { return }
        startOperation(rowID: "add-source", action: "Add source") {
            try await service.addMarketplaceSource(source)
            marketplaceSource = ""
            sourceTrustConfirmed = false
        }
    }

    private func startSourceRemoval(_ source: GrokMarketplaceSource) {
        startOperation(rowID: source.id, action: "Remove source") {
            try await service.removeMarketplaceSource(source.location)
        }
    }

    private func startOperation(
        rowID: String,
        action: String,
        operation: @escaping () async throws -> Void
    ) {
        guard activeOperationID == nil else { return }
        activeOperationID = rowID
        rowReceipts[rowID] = .running(
            rowID: rowID,
            summary: "\(action) is running for this marketplace row.",
            scope: .activeTabRestart
        )
        operationTask = Task {
            do {
                try await operation()
                try Task.checkCancellation()
                let request = SettingsApplyRequest(
                    configurationGeneration: pluginsInventory.nextConfigurationGeneration(),
                    capability: .marketplace,
                    persistenceOwner: .externalIntegration,
                    applyScope: .activeTabRestart,
                    requiresProcessRestart: true,
                    requiresPermissionOrTrust: action == "Install" || action == "Add source",
                    redactedSummary: "Marketplace \(action.lowercased()) completed; restarting only the current live tab when eligible."
                )
                let applyReceipt = await onApply(request)
                try Task.checkCancellation()
                await refresh()
                rowReceipts[rowID] = .completed(
                    rowID: rowID,
                    status: applyReceipt.status == .failure ? .failure : .success,
                    summary: applyReceipt.summary,
                    scope: .activeTabRestart,
                    applyReceipt: applyReceipt
                )
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                rowReceipts[rowID] = .completed(
                    rowID: rowID,
                    status: cancelled ? .cancelled : .failure,
                    summary: cancelled
                        ? "Operation cancelled. Refresh to confirm the marketplace's current state."
                        : error.localizedDescription,
                    scope: .activeTabRestart
                )
            }
            activeOperationID = nil
            operationTask = nil
        }
    }

}

