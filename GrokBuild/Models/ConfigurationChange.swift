import Foundation

enum ConfigurationChangeImpact: Sendable, Equatable {
    case futureSessionsOnly
    case modelRuntime
}

struct ConfigurationChange: Sendable, Equatable {
    var impact: ConfigurationChangeImpact
    var affectedModelIDs: Set<String>

    static let defaultModel = ConfigurationChange(
        impact: .futureSessionsOnly,
        affectedModelIDs: []
    )

    static func models(_ ids: some Sequence<String>) -> ConfigurationChange {
        ConfigurationChange(impact: .modelRuntime, affectedModelIDs: Set(ids))
    }
}
