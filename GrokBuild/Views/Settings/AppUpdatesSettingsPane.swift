import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct AppUpdatesSettingsPane: View {
    @Binding var valueState: SettingsValueState<AppSettingsDraft>
    let liveReceipt: EffectiveSessionReceipt?
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt
    @State private var updateRevision = 0
    @State private var isApplying = false

    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { valueState.draft.autoCheckEnabled },
            set: {
                var draft = valueState.draft
                draft.autoCheckEnabled = $0
                valueState.updateDraft(draft)
            }
        )
    }

    private var appearanceBinding: Binding<GrokBuildAppearance> {
        Binding(
            get: { valueState.draft.appearance },
            set: {
                var draft = valueState.draft
                draft.appearance = $0
                valueState.updateDraft(draft)
            }
        )
    }

    private var appearanceOptions: some View {
        HStack(spacing: 6) {
            ForEach(GrokBuildAppearance.allCases) { option in
                appearanceOptionButton(option)
            }
        }
        .frame(minWidth: 220, maxWidth: 300, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App appearance")
        .accessibilityValue(valueState.draft.appearance.accessibilityValue)
        .accessibilityHint("Choose System, Light, or Dark, then Apply to save.")
    }

    private func appearanceOptionButton(_ option: GrokBuildAppearance) -> some View {
        let isSelected = valueState.draft.appearance == option
        return Button {
            appearanceBinding.wrappedValue = option
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                }
                Text(option.title)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? AppTheme.Palette.accent : .secondary)
        .accessibilityLabel(option.title)
        .accessibilityValue(
            isSelected
                ? "Selected. " + option.accessibilityValue
                : option.accessibilityValue
        )
        .accessibilityHint(
            isSelected
                ? "Selected appearance."
                : "Select " + option.title + " appearance."
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("grok-appearance-" + option.rawValue)
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
                SettingsPaneStateHeader(status: valueState.status)

                updatesCard(title: "Installed Version", systemImage: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppVersion.display)
                            .font(.body)
                        Text(AppVersion.buildIdentity.summary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if let sourceURL = URL(string: AppVersion.buildIdentity.repositoryURL) {
                            Link(AppVersion.buildIdentity.repositoryURL, destination: sourceURL)
                                .font(.caption)
                        }
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
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsToggleRow(
                            "Automatically check for updates",
                            subtitle: "Draft only until Apply. Checks on launch and about once per day while GrokBuild is running.",
                            isOn: autoCheckBinding
                        )
                        Text("Scope: GrokBuild update scheduling only. No session restart and no provider request.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                updatesCard(title: "Appearance", systemImage: "circle.lefthalf.filled") {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsFormRow(
                            "App appearance",
                            subtitle: "System follows macOS. Light and Dark stay fixed. Draft only until Apply."
                        ) {
                            appearanceOptions
                        }
                        Text("Contrast-aware borders, light/dark surfaces, and rich-content colors update with the selected appearance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsApplyBar(
                    canApply: valueState.canApply,
                    isApplying: isApplying,
                    scopeText: "Saves update checks and appearance locally; no Grok process or tab restarts.",
                    validationMessage: valueState.validation.message,
                    receipt: valueState.lastOperationReceipt,
                    onRevert: { valueState.revert() },
                    onApply: { Task { await applyAppSettings() } }
                )
                SettingsReceiptDisclosure(receipt: valueState.lastOperationReceipt)

                updatesCard(title: "Active Session Identity", systemImage: "bolt.horizontal.circle") {
                    VStack(alignment: .leading, spacing: 5) {
                        if let liveReceipt {
                            Text(liveReceipt.freshness == .live ? "Live process receipt" : "Historical process receipt")
                                .font(.callout.weight(.medium))
                            Text("Tab \(shortID(liveReceipt.localTabID?.uuidString)) · backend \(shortID(liveReceipt.backendSessionID)) · generation \(liveReceipt.processGeneration)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text("Unknown — no active process receipt for this tab.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Text("The installed app/update receipt is independent from this session receipt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .task {
            await loadPersistedState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .grokBuildUpdateStateChanged)) { _ in
            updateRevision &+= 1
        }
    }

    @MainActor
    private func loadPersistedState() async {
        guard !valueState.isLoaded else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let saved = await SettingsBackgroundLoader.run { AppSettingsDraft.load() }
        guard !Task.isCancelled else { return }
        valueState.load(persisted: saved, applied: saved, live: nil)
    }

    @MainActor
    private func applyAppSettings() async {
        guard valueState.canApply else { return }
        let draft = valueState.draft
        let request = SettingsApplyRequest(
            configurationGeneration: valueState.configurationGeneration + 1,
            capability: .app,
            persistenceOwner: .userDefaults,
            applyScope: .externalConfigOnly,
            requiresProcessRestart: false,
            redactedSummary: "Saved GrokBuild update checks and appearance; no session restart was requested."
        )
        draft.save()
        GrokBuildAppearance.apply(draft.appearance)
        valueState.recordSaved(applied: draft, requiresRestart: false, receipt: request.receipt)
        isApplying = true
        let receipt = await onApply(request)
        isApplying = false
        guard !Task.isCancelled else { return }
        valueState.complete(receipt: receipt, live: nil)
    }

    private func shortID(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        return value.count > 8 ? "…\(value.suffix(8))" : value
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

