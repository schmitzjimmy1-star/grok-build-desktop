import AppKit

enum GrokBuildAppearance: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .system: return "Follows macOS appearance"
        case .light: return "Always light"
        case .dark: return "Always dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let raw = defaults.string(forKey: GrokSettingsKeys.appearance),
              let value = Self(rawValue: raw) else {
            return .light
        }
        return value
    }

    static func apply(_ value: Self, application: NSApplication = NSApplication.shared) {
        application.appearance = value.nsAppearance
        for window in application.windows {
            window.appearance = value.nsAppearance
        }
    }
}

/// Existing installs were deliberately dark and keep that choice. New installs
/// begin in the frontend rebuild's light-authority appearance; System and Dark
/// remain explicit options in Settings.
enum AppAppearanceMigration {
    static func run(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: GrokSettingsKeys.appearance) == nil else { return }

        let hasExistingGrokBuildState = defaults.dictionaryRepresentation().keys
            .contains { $0.hasPrefix("grokbuild.") }

        defaults.set(
            hasExistingGrokBuildState ? GrokBuildAppearance.dark.rawValue : GrokBuildAppearance.light.rawValue,
            forKey: GrokSettingsKeys.appearance
        )
    }
}

struct AppSettingsDraft: Codable, Equatable, Sendable {
    var autoCheckEnabled: Bool
    var appearance: GrokBuildAppearance

    static let defaults = AppSettingsDraft(
        autoCheckEnabled: true,
        appearance: .light
    )

    static func load(defaults: UserDefaults = .standard) -> Self {
        AppSettingsDraft(
            autoCheckEnabled: defaults.object(forKey: UpdateSettingsKeys.autoCheckEnabled) as? Bool ?? true,
            appearance: GrokBuildAppearance.load(defaults: defaults)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(autoCheckEnabled, forKey: UpdateSettingsKeys.autoCheckEnabled)
        defaults.set(appearance.rawValue, forKey: GrokSettingsKeys.appearance)
    }
}
