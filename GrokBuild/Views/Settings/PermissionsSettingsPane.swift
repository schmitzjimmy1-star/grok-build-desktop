import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct PermissionsSettingsPane: View {
    @Binding var valueState: SettingsValueState<PermissionSettingsDraft>
    let liveReceipt: EffectiveSessionReceipt?
    let configurationStatusMessage: String?
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt
    @State private var isApplying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                launchFlagsCard
                safetyTogglesCard
                permissionRulesCard
                applyCard
            }
            .centeredSettingsColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Palette.canvas)
        .task {
            await loadPersistedState()
        }
        .onChange(of: liveReceipt) { _, receipt in
            valueState.refreshLive(nil)
            _ = receipt
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            settingsPaneHeader(
                "Permissions",
                subtitle: "Control how Grok asks for approval and accesses your project.",
                systemImage: SettingsTab.permissions.systemImage
            )
            SettingsPaneStateHeader(status: valueState.status)
        }
    }

    private var launchFlagsCard: some View {
        settingsCard(title: "Launch Behavior", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                settingRow("Permission mode", description: permissionModeChoice.explanation) {
                    Picker("", selection: permissionModeBinding) {
                        Section("Interactive") {
                            ForEach(GrokPermissionMode.interactiveChoices) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                        Section("Advanced") {
                            ForEach(GrokPermissionMode.advancedChoices) { mode in
                                Text(mode.displayName).tag(mode.rawValue)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: AppTheme.Layout.settingsControlWidth)
                }

                if permissionModeChoice == .alwaysApprove {
                    Label(
                        "Tool prompts are skipped, but deny rules, hooks, and the selected sandbox remain enforced.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                } else if permissionModeChoice == .denyUnapproved {
                    Label(
                        "This is a deny-by-default automation policy, not a low-interruption interactive mode.",
                        systemImage: "nosign"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                settingRow("Sandbox", description: "Limits file system and command access for Grok.") {
                    Picker("", selection: sandboxProfileBinding) {
                        Text("Default").tag("")
                        Text("Workspace").tag("workspace")
                        Text("Read-only").tag("read-only")
                        Text("Strict").tag("strict")
                        Text("Devbox").tag("devbox")
                    }
                    .labelsHidden()
                    .frame(width: AppTheme.Layout.settingsControlWidth)
                }

                settingRow("Default reasoning effort", description: "Reasoning budget for new projects. Each project keeps its own effort — change the current chat from the composer's model menu.") {
                    Picker("", selection: reasoningEffortBinding) {
                        ForEach(ReasoningEffortLevel.menuCases) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: AppTheme.Layout.settingsControlWidth)
                }
            }
        }
    }

    private var safetyTogglesCard: some View {
        settingsCard(title: "Session Capabilities", systemImage: "switch.2") {
            VStack(alignment: .leading, spacing: 12) {
                permissionToggle("Disable web search tools", subtitle: "Prevent Grok from using web search in new sessions.", isOn: disableWebSearchBinding)
                Divider()
                permissionToggle("Disable subagents", subtitle: "Keep work inside the main Grok agent only.", isOn: noSubagentsBinding)
            }
        }
    }

    private var permissionRulesCard: some View {
        settingsCard(title: "Permission Rules", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enter one `--allow` or `--deny` rule per line, for example `Bash(npm*)` or `Edit(/etc/**)`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 14) {
                    ruleEditor(title: "Allow Rules", text: allowRulesBinding)
                    ruleEditor(title: "Deny Rules", text: denyRulesBinding)
                }
            }
        }
    }

    private var applyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsApplyBar(
                canApply: valueState.canApply,
                isApplying: isApplying,
                scopeText: "Saves the launch policy and restarts only the current live tab. Permission cards keep the old launch receipt until that restart succeeds.",
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

    private var permissionModeChoice: GrokPermissionMode {
        GrokPermissionMode(storedValue: valueState.draft.permissionMode)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PermissionSettingsDraft, Value>) -> Binding<Value> {
        Binding(
            get: { valueState.draft[keyPath: keyPath] },
            set: { newValue in
                var draft = valueState.draft
                draft[keyPath: keyPath] = newValue
                valueState.updateDraft(draft, validation: draft.validation)
            }
        )
    }

    private var permissionModeBinding: Binding<String> { binding(\.permissionMode) }
    private var sandboxProfileBinding: Binding<String> { binding(\.sandboxProfile) }
    private var reasoningEffortBinding: Binding<String> { binding(\.reasoningEffort) }
    private var disableWebSearchBinding: Binding<Bool> { binding(\.disableWebSearch) }
    private var noSubagentsBinding: Binding<Bool> { binding(\.noSubagents) }
    private var allowRulesBinding: Binding<String> { binding(\.allowRules) }
    private var denyRulesBinding: Binding<String> { binding(\.denyRules) }

    @MainActor
    private func loadPersistedState() async {
        guard !valueState.isLoaded else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let saved = await SettingsBackgroundLoader.run { PermissionSettingsDraft.load() }
        guard !Task.isCancelled else { return }
        valueState.load(persisted: saved, applied: saved, live: nil)
    }

    @MainActor
    private func applyChanges() async {
        guard valueState.canApply else { return }
        let draft = valueState.draft
        let request = SettingsApplyRequest(
            configurationGeneration: valueState.configurationGeneration + 1,
            capability: .permissions,
            persistenceOwner: .userDefaults,
            applyScope: .activeTabRestart,
            requiresProcessRestart: true,
            redactedSummary: "Saved the permission launch policy; rules remain local and are excluded from receipts."
        )
        draft.save()
        valueState.recordSaved(
            applied: draft,
            requiresRestart: liveReceipt?.freshness == .live,
            receipt: request.receipt
        )
        isApplying = true
        let receipt = await onApply(request)
        isApplying = false
        guard !Task.isCancelled else { return }
        valueState.complete(receipt: receipt, live: nil)
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

    private func settingRow<Content: View>(
        _ title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360, alignment: .leading)
            .layoutPriority(1)

            Spacer()
            content()
        }
    }

    private func permissionToggle(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        SettingsToggleRow(title, subtitle: subtitle, isOn: isOn)
    }

    private func ruleEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.medium))
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: AppTheme.Layout.settingsRuleEditorHeight)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.large).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.large).stroke(AppTheme.Palette.glassBorder))
        }
        .frame(maxWidth: .infinity)
    }
}
