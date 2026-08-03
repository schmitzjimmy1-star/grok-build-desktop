import SwiftUI
import AppKit

// Extracted verbatim from SettingsView.swift (Slice 10 decomposition). Same module,
// same behavior; only the access level of the pane changed from file-private to
// internal because the SettingsView shell now instantiates it across files.

struct SkillsSettingsPane: View {
    let workspace: Workspace?
    @Binding var inventory: SettingsInventoryState<[GrokSkillInfo]>

    private let service = GrokCLIService()
    @State private var filter = ""
    @State private var isLoading = false

    private var filteredSkills: [GrokSkillInfo] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return inventory.value }
        return inventory.value.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            $0.description.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourceType.localizedCaseInsensitiveContains(trimmed) ||
            $0.sourcePath.localizedCaseInsensitiveContains(trimmed) ||
            $0.pluginName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                settingsPaneHeader(
                    "Skills",
                    subtitle: "Review the skills available to Grok in this project.",
                    systemImage: SettingsTab.skills.systemImage
                )
                Button("Refresh") {
                    Task { await refresh() }
                }
            }

            TextField("Search skills", text: $filter)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(filteredSkills) { skill in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(skill.name)
                                .font(.headline)
                            if skill.userInvocable {
                                Text("/\(skill.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(sourceLabel(for: skill))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if !skill.description.isEmpty {
                            Text(skill.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }

                        if !skill.sourcePath.isEmpty {
                            HStack {
                                Spacer()
                                Button("Open source") {
                                    openPath(skill.sourcePath)
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

            Text("Sources refresh automatically from this Mac and the current project.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: workspace?.path) { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        inventory.beginRefresh(staleMessage: "Refreshing skills for the selected project…")
        do {
            let skills = try await GrokBuildPerformance.measure(.settingsSkillsInspect) {
                try await service.listSkills(cwd: workspace?.path)
            }
            guard !Task.isCancelled else { return }
            inventory.finish(
                skills,
                isEmpty: skills.isEmpty,
                emptyMessage: "No skills are available. Grok completed inspection successfully."
            )
        } catch {
            guard !Task.isCancelled else { return }
            inventory.fail(error.localizedDescription)
        }
        isLoading = false
    }

    private func sourceLabel(for skill: GrokSkillInfo) -> String {
        if !skill.pluginName.isEmpty { return "plugin: \(skill.pluginName)" }
        return skill.sourceType.isEmpty ? "unknown" : skill.sourceType
    }
}

