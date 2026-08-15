import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct AgentsSettingsPane: View {
    let workspace: Workspace?
    @Binding var valueState: SettingsValueState<String>
    let liveReceipt: EffectiveSessionReceipt?
    let onApply: (SettingsApplyRequest) async -> SettingsApplyReceipt

    private let service = GrokCLIService()
    @State private var agents: [GrokAgentInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDiscoveredAgents = false

    @State private var roles: [SubagentRole] = []
    @State private var customModelIDs: [String] = []
    @State private var editingRole: SubagentRole?
    @State private var isAddingRole = false
    @State private var roleError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Agents",
                    subtitle: "Choose the agent used for new sessions and manage reusable roles.",
                    systemImage: SettingsTab.agents.systemImage
                )
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            discoveredAgentsSection

            sessionAgentCard

            customSubagentsSection

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .task(id: workspace?.path) {
            await loadPersistedState()
            await refresh()
        }
        .onChange(of: liveReceipt) { _, receipt in
            valueState.refreshLive(
                receipt?.freshness == .live ? receipt?.requestedAgentID : nil
            )
        }
    }

    private var discoveredAgentsSection: some View {
        DisclosureGroup(isExpanded: $showDiscoveredAgents) {
            List {
                ForEach(agents) { agent in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(agent.name)
                                .font(.headline)
                            Spacer()
                            Text(sourceLabel(for: agent))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        if !agent.description.isEmpty {
                            Text(agent.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                        if !agent.sourcePath.isEmpty {
                            Text(agent.sourcePath)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 220)
            .overlay {
                if agents.isEmpty && !isLoading {
                    ContentUnavailableView("No Agents", systemImage: "person.2.slash", description: Text("Grok did not report any agents for this project."))
                }
            }
            if isLoading { ProgressView() }
        } label: {
            HStack(spacing: 6) {
                Text("Discovered agents")
                    .font(.headline)
                if !agents.isEmpty {
                    Text("\(agents.count) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sessionAgentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Default agent for new sessions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: selectedAgentBinding) {
                    ForEach(GrokAgentProfiles.builtInOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                    if !discoveredAgentNames.isEmpty {
                        Section("Discovered") {
                            ForEach(discoveredAgentNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    if !customSubagentNames.isEmpty {
                        Section("Run as custom role") {
                            ForEach(customSubagentNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 240)
            }

            Text("Used for new sessions. You can override it per session from the composer. A custom role runs the whole session; ask in chat when you want Grok to delegate work to a subagent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Apply Default") { Task { await applyDefaultAgent() } }
                .buttonStyle(GrokProminentButtonStyle())
                .disabled(!valueState.canApply)
            }
            SettingsPaneStateHeader(status: valueState.status)
            SettingsReceiptDisclosure(receipt: valueState.lastOperationReceipt)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(valueState.isDirty ? AppTheme.Palette.surfaceHover : AppTheme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(
                    valueState.isDirty
                        ? AppTheme.Palette.glassBorderStrong
                        : AppTheme.Palette.glassBorder
                )
        )
    }

    private var customSubagentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Custom subagents")
                    .font(.headline)
                Spacer()
                Button {
                    editingRole = nil
                    isAddingRole = true
                } label: {
                    Label("Add Subagent", systemImage: "plus")
                }
                .disabled(roles.count >= SubagentRoleStore.maxRoles)
            }

            Text("Reusable roles with their own instructions and an optional model.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Ask for a role by name, or let the main agent delegate automatically. Each role works independently and reports back.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)

            if roles.isEmpty {
                Text("No custom subagents yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(roles) { role in
                        roleRow(role)
                        if role.id != roles.last?.id { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.medium).fill(Color.primary.opacity(0.03)))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.medium).stroke(Color.primary.opacity(0.08)))
            }

            if let roleError {
                Text(roleError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .sheet(isPresented: $isAddingRole) {
            SubagentRoleEditor(
                role: editingRole,
                existingNames: Set(roles.map(\.name)),
                modelOptions: modelOptions
            ) { saved in
                upsertRole(saved)
            }
        }
    }

    private func roleRow(_ role: SubagentRole) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(role.name)
                        .font(.subheadline.weight(.semibold))
                    Text(role.model.isEmpty ? "inherits model" : role.model)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                if !role.description.isEmpty {
                    Text(role.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(role.instruction)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                editingRole = role
                isAddingRole = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit subagent")
            .accessibilityLabel("Edit subagent")
            Button(role: .destructive) {
                removeRole(role)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove subagent")
            .accessibilityLabel("Remove subagent")
        }
        .padding(12)
    }

    /// Model ids available in the role editor picker (built-ins + custom models from config.toml).
    private var modelOptions: [String] {
        var options = ["grok-build"]
        for modelID in customModelIDs where !options.contains(modelID) {
            options.append(modelID)
        }
        return options
    }

    private func upsertRole(_ role: SubagentRole) {
        if let editing = editingRole, editing.name != role.name {
            roles.removeAll { $0.name == editing.name }
        }
        if let index = roles.firstIndex(where: { $0.name == role.name }) {
            roles[index] = role
        } else {
            roles.append(role)
        }
        persistRoles()
    }

    private func removeRole(_ role: SubagentRole) {
        roles.removeAll { $0.name == role.name }
        persistRoles()
    }

    private func persistRoles() {
        do {
            try SubagentRoleStore.save(roles)
            roleError = nil
            roles = SubagentRoleStore.load()
            NotificationCenter.default.post(name: .subagentRolesChanged, object: nil)
            Task {
                _ = await onApply(SettingsApplyRequest(
                    configurationGeneration: valueState.configurationGeneration,
                    capability: .agents,
                    persistenceOwner: .grokConfig,
                    applyScope: .futureSessions,
                    requiresProcessRestart: false,
                    redactedSummary: "Saved custom agent roles for future sessions."
                ))
            }
        } catch {
            roleError = "Could not save subagents: \(error.localizedDescription)"
        }
    }

    /// Discovered names that are not already surfaced as the built-in options.
    private var discoveredAgentNames: [String] {
        agents.map(\.name).filter { name in !GrokAgentProfiles.builtInOptions.contains { $0.id == name } }
    }

    /// Custom subagent roles that are not already present in built-in or discovered agent lists.
    private var customSubagentNames: [String] {
        let excluded = Set(GrokAgentProfiles.builtInOptions.map(\.id) + agents.map(\.name))
        return roles.map(\.name).filter { !excluded.contains($0) }
    }

    private func refresh() async {
        isLoading = true
        errorMessage = nil
        let loaded = await SettingsBackgroundLoader.run {
            (
                roles: SubagentRoleStore.load(),
                modelIDs: CustomModelStore.load().models.map(\.id)
            )
        }
        guard !Task.isCancelled else { return }
        roles = loaded.roles
        customModelIDs = loaded.modelIDs
        do {
            agents = try await service.listAgents(cwd: workspace?.path)
        } catch {
            agents = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func loadPersistedState() async {
        guard !valueState.isLoaded else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        let saved = await SettingsBackgroundLoader.run {
            UserDefaults.standard.string(forKey: GrokSettingsKeys.selectedAgent) ?? ""
        }
        guard !Task.isCancelled else { return }
        valueState.load(
            persisted: saved,
            applied: saved,
            live: liveReceipt?.freshness == .live ? liveReceipt?.requestedAgentID : nil
        )
    }

    private var selectedAgentBinding: Binding<String> {
        Binding(
            get: { valueState.draft },
            set: { valueState.updateDraft($0) }
        )
    }

    @MainActor
    private func applyDefaultAgent() async {
        guard valueState.canApply else { return }
        let selected = valueState.draft
        let request = SettingsApplyRequest(
            configurationGeneration: valueState.configurationGeneration + 1,
            capability: .agents,
            persistenceOwner: .userDefaults,
            applyScope: .futureSessions,
            requiresProcessRestart: false,
            redactedSummary: "Saved the default agent for future tabs; existing tab overrides were preserved."
        )
        UserDefaults.standard.set(selected, forKey: GrokSettingsKeys.selectedAgent)
        valueState.recordSaved(applied: selected, requiresRestart: false, receipt: request.receipt)
        let receipt = await onApply(request)
        guard !Task.isCancelled else { return }
        valueState.complete(
            receipt: receipt,
            live: liveReceipt?.freshness == .live ? liveReceipt?.requestedAgentID : nil
        )
    }

    private func sourceLabel(for agent: GrokAgentInfo) -> String {
        if !agent.pluginName.isEmpty { return "plugin: \(agent.pluginName)" }
        return agent.sourceType.isEmpty ? "unknown" : agent.sourceType
    }
}

/// Add/edit sheet for a custom subagent role (name, model, instruction, description).
private struct SubagentRoleEditor: View {
    let role: SubagentRole?
    let existingNames: Set<String>
    let modelOptions: [String]
    let onSave: (SubagentRole) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var model = ""
    @State private var description = ""
    @State private var instruction = ""

    private var isEditing: Bool { role != nil }

    private var validationError: String? {
        let candidate = SubagentRole(
            name: name.trimmingCharacters(in: .whitespaces),
            model: model,
            instruction: instruction,
            description: description
        )
        if let error = candidate.validationError { return error }
        let originalName = role?.name
        if name.trimmingCharacters(in: .whitespaces) != originalName,
           existingNames.contains(name.trimmingCharacters(in: .whitespaces)) {
            return "A subagent named \"\(name.trimmingCharacters(in: .whitespaces))\" already exists."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Edit Subagent" : "Add Subagent")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("e.g. researcher", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isEditing)
                    .onChange(of: name) { _, newValue in
                        if !isEditing {
                            name = SubagentRole.suggestedName(from: newValue)
                        }
                    }
                if isEditing {
                    Text("Name can't be changed after creation.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                // Provider-grouped so OpenRouter/custom routes are visible choices,
                // not a flat ID soup (agentic roadmap Slice 5).
                Picker("", selection: $model) {
                    Text("Inherit session model").tag("")
                    Section("Grok") {
                        ForEach(modelOptions.filter { $0 == "grok-build" }, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    let customOptions = modelOptions.filter { $0 != "grok-build" }
                    if !customOptions.isEmpty {
                        Section("Your models (config.toml)") {
                            ForEach(customOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    }
                }
                .labelsHidden()
                Text("Routed models come from your configured providers, including OpenRouter.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description (optional)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("Short summary", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Instruction").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextEditor(text: $instruction)
                    .font(.body)
                    .frame(minHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.medium).stroke(Color.primary.opacity(0.15)))
                Text("Saved to ~/.grok/prompts/\(name.isEmpty ? "<name>" : name).md")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let validationError {
                Text(validationError).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Save" : "Add") {
                    onSave(SubagentRole(
                        name: name.trimmingCharacters(in: .whitespaces),
                        model: model,
                        instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespaces),
                        extraFields: role?.extraFields ?? [:]
                    ))
                    dismiss()
                }
                .buttonStyle(GrokProminentButtonStyle())
                .disabled(validationError != nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if let role {
                name = role.name
                model = role.model
                description = role.description
                instruction = role.instruction
            }
        }
    }
}

