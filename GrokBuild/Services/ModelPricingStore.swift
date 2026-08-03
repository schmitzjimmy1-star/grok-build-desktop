import Foundation

/// Per-token USD rates for one model, captured from a provider catalog fetch.
struct ModelPricing: Codable, Equatable, Sendable {
    let promptPerToken: Double
    let completionPerToken: Double
}

/// Non-secret sidecar of known model pricing (UserDefaults, keyed by model ID).
///
/// Populated only when a provider catalog advertises rates (OpenRouter does) during the
/// existing **Test connection** flow — no new network calls. Consumers use it purely for
/// display-side usage *estimates*; absent pricing means "show tokens only", never $0.
enum ModelPricingStore {
    static let defaultsKey = "grokbuild.modelPricing.v1"

    /// Small process-local cache so per-render estimate lookups do not re-decode
    /// UserDefaults JSON. Invalidated on every record().
    private static var cache: [String: ModelPricing]?
    private static var cacheDefaults: UserDefaults?

    static func record(_ models: [FetchedModel], defaults: UserDefaults = .standard) {
        let priced = models.compactMap { model -> (String, ModelPricing)? in
            guard let prompt = model.promptPricePerToken,
                  let completion = model.completionPricePerToken else { return nil }
            return (model.id, ModelPricing(promptPerToken: prompt, completionPerToken: completion))
        }
        guard !priced.isEmpty else { return }
        var all = self.all(defaults: defaults)
        for (id, pricing) in priced { all[id] = pricing }
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: defaultsKey)
        cache = all
        cacheDefaults = defaults
    }

    static func all(defaults: UserDefaults = .standard) -> [String: ModelPricing] {
        if let cache, cacheDefaults === defaults { return cache }
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: ModelPricing].self, from: data) else {
            cache = [:]
            cacheDefaults = defaults
            return [:]
        }
        cache = decoded
        cacheDefaults = defaults
        return decoded
    }

    static func pricing(for modelID: String, defaults: UserDefaults = .standard) -> ModelPricing? {
        all(defaults: defaults)[modelID]
    }

    /// Test-only: drop the process cache so suite-scoped defaults do not leak.
    static func resetCacheForTests() {
        cache = nil
        cacheDefaults = nil
    }
}
