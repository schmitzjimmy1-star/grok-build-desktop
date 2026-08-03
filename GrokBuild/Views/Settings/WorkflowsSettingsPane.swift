import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct WorkflowsSettingsPane: View {
    @Binding var valueState: SettingsValueState<Bool>
    let liveReceipt: EffectiveSessionReceipt?
    let configurationStatusMessage: String?
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt
    @State private var loadState = SettingsLoadState.checking
    @State private var isApplying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SettingsLoadStateView(
                    state: loadState,
                    retry: { Task { await loadPersistedState(force: true) } }
                )
                enableCard
                infoCard
                SettingsApplyBar(
                    canApply: valueState.canApply,
                    isApplying: isApplying,
                    scopeText: "Writes the shared Grok config and restarts only the current live tab. Streaming work queues one restart after the turn.",
                    validationMessage: valueState.validation.message,
                    receipt: valueState.lastOperationReceipt,
                    onRevert: { valueState.revert() },
                    onApply: { Task { await applyChanges() } }
                )
                SettingsReceiptDisclosure(receipt: valueState.lastOperationReceipt)
            }
            .centeredSettingsColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Palette.canvas)
        .task {
            await loadPersistedState(force: false)
        }
        .onChange(of: liveReceipt) { _, receipt in
            valueState.refreshLive(receipt?.freshness == .live ? valueState.applied : nil)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            settingsPaneHeader(
                "Workflows",
                subtitle: "Run project workflows in the background.",
                systemImage: SettingsTab.workflows.systemImage
            )
            SettingsPaneStateHeader(status: valueState.status)
        }
    }

    private var enableCard: some View {
        settingsCard(title: "Background Workflows", systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow(
                    "Enable workflows",
                    subtitle: "Draft only until Apply. The setting is shared with Grok CLI/TUI through config.toml.",
                    isOn: Binding(
                        get: { valueState.draft },
                        set: { valueState.updateDraft($0) }
                    )
                )

                Text("Skills remain available separately from the composer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Live means this app launched an exact newer process after the saved write. Grok CLI does not independently report the effective workflow toggle.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let configurationStatusMessage, isApplying {
                    Text(configurationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func loadPersistedState(force: Bool) async {
        if valueState.isLoaded, !force {
            loadState = .content
            return
        }
        loadState = .checking
        let enabled = await SettingsBackgroundLoader.run { WorkflowsConfigStore.loadEnabled() }
        guard !Task.isCancelled else { return }
        valueState.load(persisted: enabled, applied: enabled, live: nil)
        loadState = .content
    }

    @MainActor
    private func applyChanges() async {
        guard valueState.canApply else { return }
        let enabled = valueState.draft
        let request = SettingsApplyRequest(
            configurationGeneration: valueState.configurationGeneration + 1,
            capability: .workflows,
            persistenceOwner: .grokConfig,
            applyScope: .activeTabRestart,
            requiresProcessRestart: true,
            redactedSummary: "Saved the shared workflow setting; restarting only the current live tab when eligible."
        )
        do {
            try await SettingsBackgroundLoader.runThrowing {
                try WorkflowsConfigStore.setEnabled(enabled)
            }
        } catch {
            valueState.lastOperationReceipt = .completed(
                request: request,
                status: .failure,
                summary: error.localizedDescription
            )
            return
        }
        guard !Task.isCancelled else { return }
        valueState.recordSaved(
            applied: enabled,
            requiresRestart: liveReceipt?.freshness == .live,
            receipt: request.receipt
        )
        isApplying = true
        let receipt = await onApply(request)
        isApplying = false
        guard !Task.isCancelled else { return }
        let inferredLive = receipt.status == .success && receipt.effectiveSession != nil ? enabled : nil
        valueState.complete(receipt: receipt, live: inferredLive)
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

