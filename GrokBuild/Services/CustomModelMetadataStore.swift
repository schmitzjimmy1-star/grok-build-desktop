import Foundation

/// GrokBuild-only presentation hints for a CLI model.
///
/// These values are deliberately kept out of `~/.grok/config.toml`: Grok's config parser
/// rejects unknown model fields, while none of these values are required by the CLI.
struct CustomModelMetadata: Codable, Equatable, Sendable {
    var contextTokens: Int?
    var supportsReasoningEffort: Bool
    var supportsVision: Bool
    var supportsThinkingDisplay: Bool
    var providerID: String?

    init(model: CustomModel) {
        contextTokens = model.contextTokens
        supportsReasoningEffort = model.supportsReasoningEffort
        supportsVision = model.supportsVision
        supportsThinkingDisplay = model.supportsThinkingDisplay
        providerID = model.providerID
    }

    func applying(to model: CustomModel) -> CustomModel {
        var result = model
        // `context_window` is native Grok config now. Keep the sidecar value only as a
        // migration fallback for configs written by older GrokBuild versions.
        if result.contextTokens == nil {
            result.contextTokens = contextTokens
        }
        result.supportsReasoningEffort = supportsReasoningEffort
        result.supportsVision = supportsVision
        result.supportsThinkingDisplay = supportsThinkingDisplay
        result.providerID = providerID
        return result
    }
}

/// Non-secret sidecar storage for model UI metadata, keyed by the stable Grok model id.
enum CustomModelMetadataStore {
    static let defaultsKey = "grokbuild.customModelMetadata.v1"

    static func load(defaults: UserDefaults = .standard) -> [String: CustomModelMetadata] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: CustomModelMetadata].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func apply(
        to models: [CustomModel],
        defaults: UserDefaults = .standard
    ) -> [CustomModel] {
        let metadata = load(defaults: defaults)
        return models.map { model in
            metadata[model.id]?.applying(to: model) ?? model
        }
    }

    static func save(
        models: [CustomModel],
        defaults: UserDefaults = .standard
    ) {
        let metadata = Dictionary(uniqueKeysWithValues: models.map { ($0.id, CustomModelMetadata(model: $0)) })
        save(metadata: metadata, defaults: defaults)
    }

    static func save(
        metadata: [String: CustomModelMetadata],
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func mergingLegacy(
        models: [CustomModel],
        into existing: [String: CustomModelMetadata]
    ) -> [String: CustomModelMetadata] {
        var metadata = existing
        for model in models where metadata[model.id] == nil {
            metadata[model.id] = CustomModelMetadata(model: model)
        }
        return metadata
    }

    /// Imports legacy TOML hints once without overwriting newer sidecar values.
    static func mergeLegacy(
        models: [CustomModel],
        defaults: UserDefaults = .standard
    ) {
        let existing = load(defaults: defaults)
        let metadata = mergingLegacy(models: models, into: existing)
        guard metadata != existing else { return }
        save(metadata: metadata, defaults: defaults)
    }
}
