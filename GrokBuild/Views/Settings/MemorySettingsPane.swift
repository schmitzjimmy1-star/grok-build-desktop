import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct MemorySettingsPane: View {
    @Binding var valueState: SettingsValueState<Bool>
    @Binding var loadState: SettingsLoadState
    let liveReceipt: EffectiveSessionReceipt?
    let configurationStatusMessage: String?
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt

    @State private var showBrowser = false
    @State private var showRemember = false
    @State private var rememberText = ""
    @State private var statusMessage: String?
    @State private var isApplying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SettingsLoadStateView(state: loadState) {
                    Task { await loadPersistedState(force: true) }
                }
                if valueState.isLoaded {
                    enableCard
                    SettingsApplyBar(
                        canApply: valueState.canApply,
                        isApplying: isApplying,
                        scopeText: "Saves for future sessions and restarts only the current live tab.",
                        validationMessage: valueState.validation.message,
                        receipt: valueState.lastOperationReceipt,
                        onRevert: { valueState.revert() },
                        onApply: { Task { await applyChanges() } }
                    )
                    SettingsReceiptDisclosure(receipt: valueState.lastOperationReceipt)
                    actionsCard
                }
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
        .task {
            await loadPersistedState(force: false)
        }
        .onChange(of: liveReceipt) { _, receipt in
            valueState.refreshLive(
                receipt?.freshness == .live ? receipt?.memoryEnabled : nil
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            settingsPaneHeader(
                "Memory",
                subtitle: "Let Grok recall useful context across sessions.",
                systemImage: SettingsTab.memory.systemImage
            )
            SettingsPaneStateHeader(status: valueState.status)
        }
    }

    private var enableCard: some View {
        settingsCard(title: "Cross-Session Memory", systemImage: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsFormRow(
                    "Use cross-session memory",
                    subtitle: "The draft stays local until Apply. Existing processes keep their recorded launch value until restart."
                ) {
                    Toggle("Use cross-session memory", isOn: memoryDraftBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Use cross-session memory")
                        .accessibilityValue(valueState.draft ? "Draft on" : "Draft off")
                }

                Text("Stored locally on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let configurationStatusMessage, isApplying {
                    Text(configurationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityValue(configurationStatusMessage)
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
                    .buttonStyle(GrokProminentButtonStyle())
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

    private var memoryDraftBinding: Binding<Bool> {
        Binding(
            get: { valueState.draft },
            set: { valueState.updateDraft($0) }
        )
    }

    @MainActor
    private func loadPersistedState(force: Bool) async {
        if valueState.isLoaded, !force {
            valueState.refreshLive(
                liveReceipt?.freshness == .live ? liveReceipt?.memoryEnabled : nil
            )
            loadState = .content
            return
        }
        loadState = .checking
        await Task.yield()
        guard !Task.isCancelled else { return }
        let saved = await SettingsBackgroundLoader.run {
            UserDefaults.standard.object(forKey: GrokSettingsKeys.memoryEnabled) as? Bool
                ?? GrokPermissionSettings.defaults.memoryEnabled
        }
        guard !Task.isCancelled else { return }
        valueState.load(
            persisted: saved,
            applied: saved,
            live: liveReceipt?.freshness == .live ? liveReceipt?.memoryEnabled : nil
        )
        loadState = .content
    }

    @MainActor
    private func applyChanges() async {
        guard valueState.canApply else { return }
        let newValue = valueState.draft
        let request = SettingsApplyRequest(
            configurationGeneration: valueState.configurationGeneration + 1,
            capability: .memory,
            persistenceOwner: .userDefaults,
            applyScope: .activeTabRestart,
            requiresProcessRestart: true,
            redactedSummary: "Saved the Memory launch setting; applying it to the current live tab when eligible."
        )

        // This is the sole persistence boundary. Editing the toggle above never writes
        // UserDefaults and can be reverted or discarded without changing a launch.
        UserDefaults.standard.set(newValue, forKey: GrokSettingsKeys.memoryEnabled)
        valueState.recordSaved(
            applied: newValue,
            requiresRestart: liveReceipt?.freshness == .live,
            receipt: request.receipt
        )
        isApplying = true
        let receipt = await onApply(request)
        isApplying = false
        let liveValue = receipt.effectiveSession?.freshness == .live
            ? receipt.effectiveSession?.memoryEnabled
            : nil
        valueState.complete(receipt: receipt, live: liveValue)
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
        .settingsSectionSurface()
    }
}
