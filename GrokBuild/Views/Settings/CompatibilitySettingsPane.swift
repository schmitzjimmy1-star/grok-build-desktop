import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct CompatibilitySettingsPane: View {
    @Binding var valueState: SettingsValueState<CompatibilitySettingsDraft>
    @Binding var inventory: SettingsInventoryState<[GrokExternalCompatInfo]>
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt

    private let service = GrokCLIService()
    @State private var isLoading = false
    @State private var isApplying = false

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
                        compatToggle("Cursor", binding: draftBinding(\.cursorEnabled))
                        compatToggle("Claude Code", binding: draftBinding(\.claudeEnabled))
                        compatToggle("Codex", binding: draftBinding(\.codexEnabled))
                        Text("Live means this app launched an exact newer process after the atomic config write. CLI inspection reports supported cells, not the active process's imported state.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        SettingsPaneStateHeader(status: valueState.status)
                    }
                }

                SettingsApplyBar(
                    canApply: valueState.canApply,
                    isApplying: isApplying,
                    scopeText: "Writes supported Grok compatibility cells atomically and restarts only the current live tab.",
                    validationMessage: valueState.validation.message,
                    receipt: valueState.lastOperationReceipt,
                    onRevert: { valueState.revert() },
                    onApply: { Task { await applyCompat() } }
                )
                SettingsReceiptDisclosure(receipt: valueState.lastOperationReceipt)

                SettingsLoadStateView(
                    state: inventory.loadState,
                    retry: { Task { await loadExternalCompat() } }
                )

                if !inventory.value.isEmpty {
                    settingsCard(title: "Detected Sources", systemImage: "magnifyingglass") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(inventory.value) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.name)
                                            .font(.callout.weight(.medium))
                                        Spacer()
                                        Text(item.isEnabled ? "All supported capabilities on" : "Partial or off")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !item.cells.isEmpty {
                                        Text(item.cells.map { "\($0.surface): \($0.isEnabled ? "on" : "off")" }.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            Text("Codex currently exposes sessions only; the UI does not imply skills, rules, agents, MCPs, or hooks parity.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
        .task {
            await loadPersistedState()
            await loadExternalCompat()
        }
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

    private func draftBinding(_ keyPath: WritableKeyPath<CompatibilitySettingsDraft, Bool>) -> Binding<Bool> {
        Binding(
            get: { valueState.draft[keyPath: keyPath] },
            set: { enabled in
                var draft = valueState.draft
                draft[keyPath: keyPath] = enabled
                valueState.updateDraft(draft)
            }
        )
    }

    @MainActor
    private func loadPersistedState() async {
        guard !valueState.isLoaded else { return }
        let saved = await SettingsBackgroundLoader.run { CompatConfigStore.loadDraft() }
        guard !Task.isCancelled else { return }
        valueState.load(persisted: saved, applied: saved, live: nil)
    }

    @MainActor
    private func applyCompat() async {
        guard valueState.canApply else { return }
        let draft = valueState.draft
        let request = SettingsApplyRequest(
            configurationGeneration: valueState.configurationGeneration + 1,
            capability: .compatibility,
            persistenceOwner: .grokConfig,
            applyScope: .activeTabRestart,
            requiresProcessRestart: true,
            redactedSummary: "Saved supported compatibility capability cells; restarting only the current live tab when eligible."
        )
        do {
            try await SettingsBackgroundLoader.runThrowing { try CompatConfigStore.setEnabled(draft) }
        } catch {
            valueState.lastOperationReceipt = .completed(
                request: request,
                status: .failure,
                summary: error.localizedDescription
            )
            return
        }
        guard !Task.isCancelled else { return }
        valueState.recordSaved(applied: draft, requiresRestart: true, receipt: request.receipt)
        isApplying = true
        let receipt = await onApply(request)
        isApplying = false
        guard !Task.isCancelled else { return }
        let inferredLive = receipt.status == .success && receipt.effectiveSession != nil ? draft : nil
        valueState.complete(receipt: receipt, live: inferredLive)
        await loadExternalCompat()
    }

    private func loadExternalCompat() async {
        isLoading = true
        inventory.beginRefresh(staleMessage: "Refreshing Grok's compatibility capability cells…")
        do {
            let items = try await service.listExternalCompat()
            guard !Task.isCancelled else { return }
            inventory.finish(
                items,
                isEmpty: items.isEmpty,
                emptyMessage: "Grok reported no compatibility sources."
            )
        } catch {
            guard !Task.isCancelled else { return }
            inventory.fail(error.localizedDescription)
        }
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

