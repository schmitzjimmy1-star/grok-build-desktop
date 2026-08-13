import Foundation

/// One lightweight source of truth for model choices before an ACP session exists.
/// ACP remains authoritative after connection; this catalog prevents fresh tabs and
/// Settings from falling back to model IDs that disappeared from the installed CLI.
actor GrokModelCatalog {
    static let shared = GrokModelCatalog()

    private static let cacheKey = "grokbuild.builtInModelCatalog.v1"
    private static let refreshInterval: TimeInterval = 60
    private static let fallbackModels = [
        GrokModelInfo(id: "grok-4.6", name: "Grok 4.6", isDefault: true),
        GrokModelInfo(id: "grok-4.5", name: "Grok 4.5", isDefault: false)
    ]

    private var inMemory: [GrokModelInfo]?
    private var refreshedAt: Date?

    static func cachedOrFallback(defaults: UserDefaults = .standard) -> [GrokModelInfo] {
        guard let data = defaults.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([GrokModelInfo].self, from: data),
              !cached.isEmpty else {
            return fallbackModels
        }
        return normalized(cached)
    }

    func models(forceRefresh: Bool = false) async -> [GrokModelInfo] {
        await GrokBuildPerformance.measure(.modelCatalogLoad) {
            if !forceRefresh,
               let inMemory,
               let refreshedAt,
               Date().timeIntervalSince(refreshedAt) < Self.refreshInterval {
                return inMemory
            }

            do {
                let live = Self.normalized(try await GrokCLIService().listModels())
                guard !live.isEmpty else { return cachedFallback() }
                inMemory = live
                refreshedAt = Date()
                if let data = try? JSONEncoder().encode(live) {
                    UserDefaults.standard.set(data, forKey: Self.cacheKey)
                }
                return live
            } catch {
                return cachedFallback()
            }
        }
    }

    nonisolated static func displayName(for modelID: String) -> String {
        if modelID == "grok-4.6" { return "Grok 4.6" }
        if modelID == "grok-4.5" { return "Grok 4.5" }
        var components = modelID.split(separator: "-").map(String.init)
        if components.count > 1,
           components[0].localizedCaseInsensitiveCompare(components[1]) == .orderedSame {
            components.removeFirst()
        }
        return components.map { component in
            switch component.lowercased() {
            case "gpt": return "GPT"
            case "grok": return "Grok"
            case "kimi": return "Kimi"
            case "deepseek": return "DeepSeek"
            case "terra": return "Terra"
            case "flash": return "Flash"
            default: return component.uppercased() == component ? component : component.capitalized
            }
        }.joined(separator: " ")
    }

    private func cachedFallback() -> [GrokModelInfo] {
        let cached = Self.cachedOrFallback()
        inMemory = cached
        refreshedAt = Date()
        return cached
    }

    private nonisolated static func normalized(_ models: [GrokModelInfo]) -> [GrokModelInfo] {
        var seen = Set<String>()
        return models.compactMap { model in
            let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            let suppliedName = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return GrokModelInfo(
                id: id,
                name: suppliedName.isEmpty || suppliedName == id ? displayName(for: id) : suppliedName,
                isDefault: model.isDefault
            )
        }
    }
}
