import Foundation

/// One row in the sidebar's Agents hub.
///
/// The hub is a pure read-model over agent surfaces the app already owns: grok's built-in
/// default, agents discovered via `grok inspect --json`, and custom subagent roles from
/// `[subagents.roles.*]`. Selecting a row starts a new session with that agent — the same
/// `--agent` launch path the composer pill uses; the hub adds no new backend behavior.
struct AgentHubEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case builtInDefault
        case discovered
        case customRole
    }

    /// Namespaced so a discovered agent and a role sharing a name can never collide.
    let id: String
    let kind: Kind
    /// The selection value passed to the `--agent` launch path ("" = grok default).
    let agentSelection: String
    let displayName: String
    /// Secondary line: role model hint or agent description. Empty hides the line.
    let subtitle: String
    /// True when this entry is the Settings default for new sessions.
    let isSessionDefault: Bool

    var systemImageName: String {
        switch kind {
        case .builtInDefault: return "person"
        case .discovered: return "person.text.rectangle"
        case .customRole: return "person.badge.shield.checkmark"
        }
    }

    var accessibilityLabel: String {
        let kindName: String
        switch kind {
        case .builtInDefault: kindName = "Built-in agent"
        case .discovered: kindName = "Discovered agent"
        case .customRole: kindName = "Custom role"
        }
        var label = "\(kindName): \(displayName)"
        if !subtitle.isEmpty { label += ", \(subtitle)" }
        if isSessionDefault { label += ", default for new sessions" }
        return label
    }
}

enum AgentHubProjection {
    /// Builds the hub list: Default first, then custom roles (the user's own creations),
    /// then discovered agents. Roles win name collisions with discovered agents because
    /// the role row carries the user's model routing.
    static func entries(
        discovered: [GrokAgentInfo],
        roles: [SubagentRole],
        defaultSelection: String
    ) -> [AgentHubEntry] {
        let trimmedDefault = defaultSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries: [AgentHubEntry] = []

        for option in GrokAgentProfiles.builtInOptions {
            entries.append(AgentHubEntry(
                id: "builtin/\(option.id)",
                kind: .builtInDefault,
                agentSelection: option.id,
                displayName: option.title,
                subtitle: option.subtitle,
                isSessionDefault: trimmedDefault == option.id
            ))
        }

        var claimedNames = Set<String>()
        for role in roles.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let name = role.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            claimedNames.insert(name.lowercased())
            let modelHint = role.model.trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(AgentHubEntry(
                id: "role/\(name)",
                kind: .customRole,
                agentSelection: name,
                displayName: name,
                subtitle: modelHint.isEmpty ? "Inherits session model" : modelHint,
                isSessionDefault: trimmedDefault == name
            ))
        }

        for agent in discovered.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let name = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !claimedNames.contains(name.lowercased()) else { continue }
            entries.append(AgentHubEntry(
                id: "discovered/\(name)",
                kind: .discovered,
                agentSelection: name,
                displayName: name,
                subtitle: agent.description,
                isSessionDefault: trimmedDefault == name
            ))
        }

        return entries
    }
}
