import Foundation

/// Credential-free routing truth for the selected model.
///
/// ACP can confirm the effective model, but it does not expose a downstream serving-provider
/// receipt for brokered endpoints such as OpenRouter. Keep those two claims separate so the UI
/// never upgrades a configured route into provider proof.
struct ModelRouteContract: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case nativeXAI
        case directProvider
        case brokeredOpenRouter
        case localEndpoint
    }

    let kind: Kind
    let providerName: String
    let endpointHost: String?
    let endpointRouteIdentity: String?
    let providerModelID: String
    let modelIsPinned: Bool
    let servingProviderIsProven: Bool

    init(
        kind: Kind,
        providerName: String,
        endpointHost: String?,
        endpointRouteIdentity: String? = nil,
        providerModelID: String,
        modelIsPinned: Bool,
        servingProviderIsProven: Bool
    ) {
        self.kind = kind
        self.providerName = providerName
        self.endpointHost = endpointHost
        self.endpointRouteIdentity = endpointRouteIdentity
        self.providerModelID = providerModelID
        self.modelIsPinned = modelIsPinned
        self.servingProviderIsProven = servingProviderIsProven
    }

    static func resolve(selectedModelID: String, customModel: CustomModel?) -> ModelRouteContract {
        guard let customModel else {
            return ModelRouteContract(
                kind: .nativeXAI,
                providerName: "xAI",
                endpointHost: nil,
                providerModelID: selectedModelID,
                modelIsPinned: true,
                servingProviderIsProven: true
            )
        }

        let host = URL(string: customModel.baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased()
        let endpointRouteIdentity = sanitizedEndpointIdentity(customModel.baseURL)
        let providerID = customModel.providerID?.lowercased()
        let isOpenRouter = providerID == ProviderPreset.openrouter.id
            || host == "openrouter.ai"
            || host?.hasSuffix(".openrouter.ai") == true
        let providerModelID = customModel.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayProvider = providerDisplayName(providerID: providerID, host: host)

        if customModel.isLocalEndpoint {
            return ModelRouteContract(
                kind: .localEndpoint,
                providerName: displayProvider,
                endpointHost: host,
                endpointRouteIdentity: endpointRouteIdentity,
                providerModelID: providerModelID,
                modelIsPinned: !providerModelID.isEmpty,
                servingProviderIsProven: true
            )
        }

        if isOpenRouter {
            return ModelRouteContract(
                kind: .brokeredOpenRouter,
                providerName: "OpenRouter",
                endpointHost: host,
                endpointRouteIdentity: endpointRouteIdentity,
                providerModelID: providerModelID,
                modelIsPinned: !providerModelID.isEmpty && providerModelID != "openrouter/auto",
                // ACP confirms the model id, not OpenRouter's downstream provider choice.
                servingProviderIsProven: false
            )
        }

        return ModelRouteContract(
            kind: .directProvider,
            providerName: displayProvider,
            endpointHost: host,
            endpointRouteIdentity: endpointRouteIdentity,
            providerModelID: providerModelID,
            modelIsPinned: !providerModelID.isEmpty,
            servingProviderIsProven: true
        )
    }

    var compactLabel: String {
        switch kind {
        case .nativeXAI: return "Direct xAI"
        case .directProvider: return "Direct \(providerName)"
        case .brokeredOpenRouter: return modelIsPinned ? "OpenRouter · model pinned" : "OpenRouter · auto route"
        case .localEndpoint: return "Local endpoint"
        }
    }

    var systemImage: String {
        switch kind {
        case .nativeXAI, .directProvider: return "arrow.right.circle"
        case .brokeredOpenRouter: return "arrow.triangle.branch"
        case .localEndpoint: return "desktopcomputer"
        }
    }

    var detailLines: [String] {
        let endpoint = endpointHost.map { " Endpoint: \($0)." } ?? ""
        switch kind {
        case .nativeXAI:
            return [
                "Route: native xAI through the Grok CLI.",
                "Fallback: GrokBuild adds no alternate provider route."
            ]
        case .directProvider:
            return [
                "Route: direct \(providerName).\(endpoint)",
                "Provider model: \(providerModelID.isEmpty ? "not configured" : providerModelID). GrokBuild adds no provider fallback."
            ]
        case .localEndpoint:
            return [
                "Route: local endpoint.\(endpoint)",
                "Provider model: \(providerModelID.isEmpty ? "not configured" : providerModelID). GrokBuild adds no remote fallback."
            ]
        case .brokeredOpenRouter:
            let modelClaim = modelIsPinned
                ? "Model pinned to \(providerModelID)."
                : "Model routing is automatic (openrouter/auto)."
            return [
                "Route: brokered by OpenRouter.\(endpoint)",
                "\(modelClaim) Downstream serving provider is not exposed by ACP and is not claimed as proven.",
                "Fallback: GrokBuild adds no alternate provider route; OpenRouter controls downstream routing."
            ]
        }
    }

    var accessibilityValue: String {
        ([compactLabel] + detailLines).joined(separator: " ")
    }

    private static func providerDisplayName(providerID: String?, host: String?) -> String {
        if let providerID,
           let preset = ProviderPreset.allCases.first(where: { $0.id == providerID }) {
            return preset.displayName
        }
        if let providerID, !providerID.isEmpty { return providerID }
        return host ?? "custom provider"
    }

    private static func sanitizedEndpointIdentity(_ rawValue: String) -> String? {
        guard var components = URLComponents(
            string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        ), let host = components.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        components.scheme = components.scheme?.lowercased()
        components.host = host
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        let path = components.percentEncodedPath == "/" ? "" : components.percentEncodedPath
        components.percentEncodedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        return components.string
    }
}
