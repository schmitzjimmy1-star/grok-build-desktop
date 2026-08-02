import Foundation

enum ComputerUseBackendID: String, CaseIterable, Identifiable {
    case agentDesktop = "agent-desktop"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .agentDesktop: return "agent-desktop"
        }
    }
}

/// Local action policy enforced by the MCP helper. `auto` allows actions
/// (grok's own permission flow still governs tool approval); `deny` blocks
/// click/type/press at the helper regardless of what grok requests.
///
/// A legacy stored "ask" value fails `init(rawValue:)` and falls back to
/// `.auto`, which is what "ask" always effectively was — the helper never
/// implemented an ask path.
enum ComputerUsePermissionPolicy: String, CaseIterable, Identifiable {
    case auto
    case deny

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Allow"
        case .deny: return "Block All"
        }
    }
}

struct ComputerUseSettings: Sendable, Equatable {
    var enabled: Bool
    var backend: ComputerUseBackendID
    var permissionPolicy: ComputerUsePermissionPolicy
    var commandTimeoutSeconds: Int
    var includeScreenshots: Bool

    init(
        enabled: Bool,
        backend: ComputerUseBackendID,
        permissionPolicy: ComputerUsePermissionPolicy,
        commandTimeoutSeconds: Int,
        includeScreenshots: Bool
    ) {
        self.enabled = enabled
        self.backend = backend
        self.permissionPolicy = permissionPolicy
        self.commandTimeoutSeconds = commandTimeoutSeconds
        self.includeScreenshots = includeScreenshots
    }

    static let defaults = ComputerUseSettings(
        enabled: false,
        backend: .agentDesktop,
        permissionPolicy: .auto,
        commandTimeoutSeconds: 60,
        includeScreenshots: false
    )
}

enum ComputerUseSettingsKeys {
    static let enabled = "grokbuild.computerUse.enabled"
    static let backend = "grokbuild.computerUse.backend"
    static let permissionPolicy = "grokbuild.computerUse.permissionPolicy"
    static let commandTimeoutSeconds = "grokbuild.computerUse.commandTimeoutSeconds"
    static let includeScreenshots = "grokbuild.computerUse.includeScreenshots"
    static let cursorIntegrationEnabled = "grokbuild.computerUse.cursorIntegration.enabled"

    static let appliedEnabled = "grokbuild.computerUse.applied.enabled"
    static let appliedBackend = "grokbuild.computerUse.applied.backend"
    static let appliedPermissionPolicy = "grokbuild.computerUse.applied.permissionPolicy"
    static let appliedCommandTimeoutSeconds = "grokbuild.computerUse.applied.commandTimeoutSeconds"
    static let appliedIncludeScreenshots = "grokbuild.computerUse.applied.includeScreenshots"
    static let appliedCursorIntegrationEnabled = "grokbuild.computerUse.applied.cursorIntegration.enabled"
}

enum ComputerUseSettingsStore {
    static func load() -> ComputerUseSettings {
        load(prefix: .current)
    }

    static func save(_ settings: ComputerUseSettings) {
        save(settings, prefix: .current)
    }

    static func loadApplied() -> ComputerUseSettings {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: ComputerUseSettingsKeys.appliedEnabled) != nil else {
            return load()
        }
        return load(prefix: .applied)
    }

    static func saveApplied(_ settings: ComputerUseSettings) {
        save(settings, prefix: .applied)
    }

    /// Persists Cursor MCP environment fields without requiring a full Apply + Grok restart.
    static func saveAppliedCursorEnvironment(from settings: ComputerUseSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.permissionPolicy.rawValue, forKey: ComputerUseSettingsKeys.appliedPermissionPolicy)
        defaults.set(settings.commandTimeoutSeconds, forKey: ComputerUseSettingsKeys.appliedCommandTimeoutSeconds)
        defaults.set(settings.includeScreenshots, forKey: ComputerUseSettingsKeys.appliedIncludeScreenshots)
    }

    private enum KeyPrefix {
        case current
        case applied
    }

    private static func load(prefix: KeyPrefix) -> ComputerUseSettings {
        let defaults = UserDefaults.standard
        let backendRaw = defaults.string(forKey: key(.backend, prefix: prefix))
            ?? ComputerUseSettings.defaults.backend.rawValue
        let policyRaw = defaults.string(forKey: key(.permissionPolicy, prefix: prefix))
            ?? ComputerUseSettings.defaults.permissionPolicy.rawValue

        return ComputerUseSettings(
            enabled: defaults.object(forKey: key(.enabled, prefix: prefix)) as? Bool
                ?? ComputerUseSettings.defaults.enabled,
            backend: ComputerUseBackendID(rawValue: backendRaw) ?? ComputerUseSettings.defaults.backend,
            permissionPolicy: ComputerUsePermissionPolicy(rawValue: policyRaw)
                ?? ComputerUseSettings.defaults.permissionPolicy,
            commandTimeoutSeconds: defaults.object(forKey: key(.commandTimeoutSeconds, prefix: prefix)) as? Int
                ?? ComputerUseSettings.defaults.commandTimeoutSeconds,
            includeScreenshots: defaults.object(forKey: key(.includeScreenshots, prefix: prefix)) as? Bool
                ?? ComputerUseSettings.defaults.includeScreenshots
        )
    }

    private static func save(_ settings: ComputerUseSettings, prefix: KeyPrefix) {
        let defaults = UserDefaults.standard
        defaults.set(settings.enabled, forKey: key(.enabled, prefix: prefix))
        defaults.set(settings.backend.rawValue, forKey: key(.backend, prefix: prefix))
        defaults.set(settings.permissionPolicy.rawValue, forKey: key(.permissionPolicy, prefix: prefix))
        defaults.set(settings.commandTimeoutSeconds, forKey: key(.commandTimeoutSeconds, prefix: prefix))
        defaults.set(settings.includeScreenshots, forKey: key(.includeScreenshots, prefix: prefix))
    }

    private enum KeyKind {
        case enabled
        case backend
        case permissionPolicy
        case commandTimeoutSeconds
        case includeScreenshots
    }

    private static func key(_ kind: KeyKind, prefix: KeyPrefix) -> String {
        switch (kind, prefix) {
        case (.enabled, .current): return ComputerUseSettingsKeys.enabled
        case (.backend, .current): return ComputerUseSettingsKeys.backend
        case (.permissionPolicy, .current): return ComputerUseSettingsKeys.permissionPolicy
        case (.commandTimeoutSeconds, .current): return ComputerUseSettingsKeys.commandTimeoutSeconds
        case (.includeScreenshots, .current): return ComputerUseSettingsKeys.includeScreenshots
        case (.enabled, .applied): return ComputerUseSettingsKeys.appliedEnabled
        case (.backend, .applied): return ComputerUseSettingsKeys.appliedBackend
        case (.permissionPolicy, .applied): return ComputerUseSettingsKeys.appliedPermissionPolicy
        case (.commandTimeoutSeconds, .applied): return ComputerUseSettingsKeys.appliedCommandTimeoutSeconds
        case (.includeScreenshots, .applied): return ComputerUseSettingsKeys.appliedIncludeScreenshots
        }
    }
}
