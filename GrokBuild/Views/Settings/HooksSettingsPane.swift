import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct HooksSettingsPane: View {
    let workspace: Workspace?
    @Binding var inventory: SettingsInventoryState<[GrokHookInfo]>

    private let service = GrokCLIService()
    @State private var filter = ""
    @State private var isLoading = false

    private var filteredHooks: [GrokHookInfo] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return inventory.value }
        return inventory.value.filter {
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
                if inventory.value.isEmpty && !isLoading {
                    SettingsLoadStateView(
                        state: inventory.loadState,
                        retry: { Task { await refresh() } }
                    )
                }
            }

            if isLoading { ProgressView() }
            if !inventory.value.isEmpty, inventory.loadState != .content {
                SettingsLoadStateView(
                    state: inventory.loadState,
                    retry: { Task { await refresh() } }
                )
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
        inventory.beginRefresh(staleMessage: "Refreshing hooks for the selected project…")
        do {
            let hooks = try await service.listHooks(cwd: workspace?.path)
            guard !Task.isCancelled else { return }
            inventory.finish(
                hooks,
                isEmpty: hooks.isEmpty,
                emptyMessage: "No hooks configured. Grok completed inspection successfully."
            )
        } catch {
            guard !Task.isCancelled else { return }
            inventory.fail(error.localizedDescription)
        }
        isLoading = false
    }

    private func sourceLabel(for hook: GrokHookInfo) -> String {
        if !hook.pluginName.isEmpty { return "plugin: \(hook.pluginName)" }
        return hook.sourceType.isEmpty ? "unknown" : hook.sourceType
    }
}

