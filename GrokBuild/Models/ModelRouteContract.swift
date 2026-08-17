import Foundation
import GrokBuildProviderAuthCore

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
        case unavailable
    }

    enum AuthBoundary: String, Equatable, Sendable {
        case nativeSession
        case officialHelper
        case none
        case unavailable
    }

    let kind: Kind
    let selectedModelID: String
    let providerName: String
    let appProviderID: String?
    let officialProviderID: String?
    let endpointHost: String?
    let endpointRouteIdentity: String?
    let providerModelID: String
    let apiBackend: String?
    let authBoundary: AuthBoundary
    let modelIsPinned: Bool
    let servingProviderIsProven: Bool

    init(
        kind: Kind,
        selectedModelID: String = "",
        providerName: String,
        appProviderID: String? = nil,
        officialProviderID: String? = nil,
        endpointHost: String?,
        endpointRouteIdentity: String? = nil,
        providerModelID: String,
        apiBackend: String? = nil,
        authBoundary: AuthBoundary = .unavailable,
        modelIsPinned: Bool,
        servingProviderIsProven: Bool
    ) {
        self.kind = kind
        self.selectedModelID = selectedModelID
        self.providerName = providerName
        self.appProviderID = appProviderID
        self.officialProviderID = officialProviderID
        self.endpointHost = endpointHost
        self.endpointRouteIdentity = endpointRouteIdentity
        self.providerModelID = providerModelID
        self.apiBackend = apiBackend
        self.authBoundary = authBoundary
        self.modelIsPinned = modelIsPinned
        self.servingProviderIsProven = servingProviderIsProven
    }

    static func resolve(
        selectedModelID: String,
        customModel: CustomModel?,
        isKnownNativeModel: Bool = true
    ) -> ModelRouteContract {
        guard let customModel else {
            guard isKnownNativeModel else {
                return ModelRouteContract(
                    kind: .unavailable,
                    selectedModelID: selectedModelID,
                    providerName: "Provider detail unavailable",
                    endpointHost: nil,
                    providerModelID: selectedModelID,
                    authBoundary: .unavailable,
                    modelIsPinned: false,
                    servingProviderIsProven: false
                )
            }
            return ModelRouteContract(
                kind: .nativeXAI,
                selectedModelID: selectedModelID,
                providerName: "xAI",
                endpointHost: nil,
                providerModelID: selectedModelID,
                authBoundary: .nativeSession,
                modelIsPinned: true,
                servingProviderIsProven: true
            )
        }

        let host = URL(string: customModel.baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased()
        let endpointRouteIdentity = sanitizedEndpointIdentity(customModel.baseURL)
        let providerID = customModel.providerID?.lowercased()
        let officialProviderID = providerID.flatMap(ProviderAuthContract.officialProviderID(for:))
            ?? (customModel.isLocalEndpoint
                ? ProviderAuthContract.officialLocalProviderID(for: customModel.id)
                : nil)
        let authBoundary: AuthBoundary = if customModel.providerID != nil && !customModel.isLocalEndpoint {
            .officialHelper
        } else if customModel.providerID == nil && customModel.isLocalEndpoint && !customModel.hasInlineKey {
            .none
        } else {
            .unavailable
        }
        let isOpenRouter = providerID == ProviderPreset.openrouter.id
            || host == "openrouter.ai"
            || host?.hasSuffix(".openrouter.ai") == true
        let providerModelID = customModel.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayProvider = providerDisplayName(providerID: providerID, host: host)

        if customModel.isLocalEndpoint {
            return ModelRouteContract(
                kind: .localEndpoint,
                selectedModelID: selectedModelID,
                providerName: displayProvider,
                appProviderID: providerID,
                officialProviderID: officialProviderID,
                endpointHost: host,
                endpointRouteIdentity: endpointRouteIdentity,
                providerModelID: providerModelID,
                apiBackend: customModel.apiBackend.rawValue,
                authBoundary: authBoundary,
                modelIsPinned: !providerModelID.isEmpty,
                servingProviderIsProven: true
            )
        }

        if isOpenRouter {
            return ModelRouteContract(
                kind: .brokeredOpenRouter,
                selectedModelID: selectedModelID,
                providerName: "OpenRouter",
                appProviderID: providerID,
                officialProviderID: officialProviderID,
                endpointHost: host,
                endpointRouteIdentity: endpointRouteIdentity,
                providerModelID: providerModelID,
                apiBackend: customModel.apiBackend.rawValue,
                authBoundary: authBoundary,
                modelIsPinned: !providerModelID.isEmpty && providerModelID != "openrouter/auto",
                // ACP confirms the model id, not OpenRouter's downstream provider choice.
                servingProviderIsProven: false
            )
        }

        return ModelRouteContract(
            kind: .directProvider,
            selectedModelID: selectedModelID,
            providerName: displayProvider,
            appProviderID: providerID,
            officialProviderID: officialProviderID,
            endpointHost: host,
            endpointRouteIdentity: endpointRouteIdentity,
            providerModelID: providerModelID,
            apiBackend: customModel.apiBackend.rawValue,
            authBoundary: authBoundary,
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
        case .unavailable: return "Provider detail unavailable"
        }
    }

    var systemImage: String {
        switch kind {
        case .nativeXAI, .directProvider: return "arrow.right.circle"
        case .brokeredOpenRouter: return "arrow.triangle.branch"
        case .localEndpoint: return "desktopcomputer"
        case .unavailable: return "questionmark.circle"
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
        case .unavailable:
            return [
                "Route: provider detail was not exposed through the app-owned configuration.",
                "GrokBuild does not label this CLI-advertised model as native xAI or claim a serving provider."
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
