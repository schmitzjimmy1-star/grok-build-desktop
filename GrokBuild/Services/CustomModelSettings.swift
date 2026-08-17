import Foundation
import GrokBuildProviderAuthCore
import TOML

/// Post-write validation through the CLI that will actually consume the file.
/// Output is bounded and only typed warning targets are retained; reasons and raw
/// stderr never enter a receipt because they may contain user-authored config text.
enum GrokConfigCandidateInspector {
    enum InspectionError: LocalizedError {
        case cliUnavailable
        case timedOut
        case failed
        case invalidResponse
        case appOwnedWarning

        var errorDescription: String? {
            switch self {
            case .cliUnavailable: "The Grok CLI is unavailable, so the candidate configuration was rolled back."
            case .timedOut: "The Grok CLI configuration check timed out, so the candidate was rolled back."
            case .failed: "The Grok CLI rejected the candidate configuration, so it was rolled back."
            case .invalidResponse: "The Grok CLI returned an unreadable configuration receipt, so the candidate was rolled back."
            case .appOwnedWarning: "The Grok CLI reported a warning for GrokBuild-owned model configuration, so the candidate was rolled back."
            }
        }
    }

    static func validate(modelIDs: Set<String>, officialProviderIDs: Set<String>) throws {
        guard let cli = GrokCLIService.locateGrokCLI() else { throw InspectionError.cliUnavailable }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["inspect", "--json"]
        process.environment = ProcessInfo.processInfo.environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let output = LockedData(maxBytes: 1_048_576)
        let errors = LockedData(maxBytes: 65_536)
        stdout.fileHandleForReading.readabilityHandler = { output.append($0.availableData) }
        stderr.fileHandleForReading.readabilityHandler = { errors.append($0.availableData) }
        let timedOut = LockedFlag()
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw InspectionError.failed
        }
        ProcessKillSchedule.schedule(process: process, after: 10, flag: timedOut)
        process.waitUntilExit()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        output.append(stdout.fileHandleForReading.readDataToEndOfFile())
        errors.append(stderr.fileHandleForReading.readDataToEndOfFile())
        guard !timedOut.isSet else { throw InspectionError.timedOut }
        guard process.terminationStatus == 0 else { throw InspectionError.failed }
        guard !output.wasTruncated,
              let object = try? JSONSerialization.jsonObject(with: output.snapshot()) as? [String: Any] else {
            throw InspectionError.invalidResponse
        }
        let warnings = object["configWarnings"] as? [[String: Any]] ?? []
        let hasOwnedWarning = warnings.contains { warning in
            switch warning["target"] as? String {
            case "model":
                guard let key = warning["key"] as? String else { return false }
                return modelIDs.contains(key)
            case "modelProvider":
                guard let id = warning["id"] as? String else { return false }
                return officialProviderIDs.contains(id)
            default:
                return false
            }
        }
        guard !hasOwnedWarning else { throw InspectionError.appOwnedWarning }
    }
}

enum ModelAPIBackend: String, CaseIterable, Codable, Sendable {
    case chatCompletions = "chat_completions"
    case responses
    case messages

    var displayName: String {
        switch self {
        case .chatCompletions: return "Standard chat (OpenAI-compatible)"
        case .responses: return "OpenAI Responses"
        case .messages: return "Anthropic Messages"
        }
    }
}

/// A user-defined OpenAI-compatible model entry for `~/.grok/config.toml`.
///
/// Maps to a `[model.<id>]` table, e.g.
/// ```toml
/// [model.zai-glm]
/// model = "glm-5.2"
/// base_url = "https://api.z.ai/api/coding/paas/v4"
/// name = "Z.ai GLM-5.2"
/// model_provider = "grokbuild.saved.zai"
/// ```
///
/// GrokBuild projects linked providers through the CLI's official
/// `[model_providers.*]` contract. Remote keyless flat entries are refused so a
/// custom endpoint can never inherit the signed-in xAI session token.
struct CustomModel: Identifiable, Hashable, Sendable {
    /// The TOML table key (`[model.<id>]`). Used with `/model <id>` and `grok -m <id>`.
    var id: String
    /// The provider model name (e.g. `glm-5.2`, `minimax-m2.5`).
    var model: String
    /// OpenAI-compatible base URL.
    var baseURL: String
    /// Human-friendly display name. Optional.
    var name: String
    /// Transient editor or legacy-import credential. Managed linked providers keep the
    /// secret in Keychain and project only an official CLI auth-helper reference.
    var apiKey: String
    /// Optional context-window size GrokBuild uses when the CLI does not advertise one.
    var contextTokens: Int?
    /// Whether GrokBuild should expose the reasoning-effort control for this model.
    /// Opt-out: defaults to `true` so the control keeps showing unless the user explicitly
    /// disables it in GrokBuild's non-secret model metadata sidecar.
    var supportsReasoningEffort: Bool
    /// Whether the provider model can accept image inputs.
    var supportsVision: Bool
    /// Whether GrokBuild should expect/display model thinking blocks for this model.
    var supportsThinkingDisplay: Bool
    /// Grok's native request protocol for this model.
    var apiBackend: ModelAPIBackend
    /// Optional link to a saved `Provider`. GrokBuild projects the model through the
    /// CLI's official `model_provider` reference and auth-helper contract.
    var providerID: String?

    init(
        id: String,
        model: String,
        baseURL: String,
        name: String = "",
        apiKey: String = "",
        contextTokens: Int? = nil,
        supportsReasoningEffort: Bool = true,
        supportsVision: Bool = false,
        supportsThinkingDisplay: Bool = false,
        apiBackend: ModelAPIBackend = .chatCompletions,
        providerID: String? = nil
    ) {
        self.id = id
        self.model = model
        self.baseURL = baseURL
        self.name = name
        self.apiKey = apiKey
        self.contextTokens = contextTokens
        self.supportsReasoningEffort = supportsReasoningEffort
        self.supportsVision = supportsVision
        self.supportsThinkingDisplay = supportsThinkingDisplay
        self.apiBackend = apiBackend
        self.providerID = providerID
    }

    /// `true` when this is a local/self-hosted endpoint that needs no API key.
    /// Decided from the URL's exact host, not substring matching.
    var isLocalEndpoint: Bool {
        ProviderEndpointPolicy.isLocal(baseURL: baseURL)
    }

    /// `true` when an inline API key is stored in config.toml.
    var hasInlineKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A short, redacted preview of the inline key for display (e.g. `sk-1…ab9f`).
    var maskedKeyPreview: String {
        Self.mask(apiKey)
    }

    /// Redacts a secret, keeping a few leading/trailing characters for recognizability.
    static func mask(_ secret: String) -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 8 { return String(repeating: "•", count: trimmed.count) }
        let prefix = trimmed.prefix(4)
        let suffix = trimmed.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    /// Derives a valid `[model.<id>]` table key from a provider model name.
    /// Characters outside letters, numbers, dots, dashes, and underscores become dashes.
    static func suggestedID(from modelName: String) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        var result = ""
        var lastWasSeparator = false
        for char in trimmed {
            if char.isLetter || char.isNumber || char == "." || char == "_" || char == "-" {
                result.append(char)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-.")).lowercased()
    }

    /// A validation error message, or nil when the entry is well-formed.
    var validationError: String? {
        let trimmedID = id.trimmingCharacters(in: .whitespaces)
        if trimmedID.isEmpty { return "Model id is required." }
        if trimmedID.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) == nil {
            return "Model id may only contain letters, numbers, dots, dashes, and underscores."
        }
        if model.trimmingCharacters(in: .whitespaces).isEmpty { return "Model name is required." }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespaces)
        if trimmedURL.isEmpty { return "Base URL is required." }
        if !(trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://")) {
            return "Base URL must start with http:// or https://."
        }
        if let transportIssue = ProviderEndpointPolicy.transportIssue(forBaseURL: trimmedURL) {
            return transportIssue
        }
        if let contextTokens, contextTokens <= 0 {
            return "Context window must be greater than zero."
        }
        return nil
    }

    /// Returns a copy with endpoint/credential state filled in from a linked provider.
    /// A linked provider is authoritative even when its credential is empty. Keeping an old
    /// model-level key after Disconnect would make disconnect reversible only in the UI and let
    /// legacy migration silently resurrect the credential.
    func resolved(using providers: [Provider]) -> CustomModel {
        guard let providerID,
              let provider = providers.first(where: { $0.id == providerID }) else {
            return self
        }
        var copy = self
        copy.baseURL = provider.baseURL
        copy.apiKey = provider.apiKey
        return copy
    }
}

/// A reusable OpenAI-compatible provider: a base URL plus a shared credential.
///
/// Providers are a GrokBuild-side convenience so several models can share one endpoint and
/// API key (e.g. `glm-5.2` and `glm-4.7` both via Z.ai). Non-secret metadata is persisted in
/// `UserDefaults`; the credential stays in Keychain. Managed models use the CLI's official
/// `[model_providers.*]` plus `auth.command` projection, so config.toml contains no linked
/// credential copy.
struct Provider: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    var baseURL: String
    var apiKey: String
    /// A suggested default model id for this provider (used when adding a model from the provider).
    var suggestedModel: String
    /// Authentication headers used by this provider's OpenAI-compatible endpoint.
    var authScheme: ProviderAuthScheme
    /// Safe-to-persist provenance only. The credential remains solely in Keychain (plus the
    /// owner-readable CLI projection required by grok).
    var credentialMetadata: ProviderCredentialMetadata
    /// Explicit advanced opt-in for a cleartext remote endpoint (trusted-LAN model
    /// servers). Off by default; the UI keeps a persistent warning while it is on.
    var allowInsecureHTTP: Bool

    init(
        id: String,
        name: String,
        baseURL: String,
        apiKey: String = "",
        suggestedModel: String = "",
        authScheme: ProviderAuthScheme = .bearer,
        credentialMetadata: ProviderCredentialMetadata? = nil,
        allowInsecureHTTP: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.suggestedModel = suggestedModel
        self.authScheme = authScheme
        self.credentialMetadata = credentialMetadata
            ?? (!apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && authScheme != .none
                ? .migratedAPIKey
                : .none)
        self.allowInsecureHTTP = allowInsecureHTTP
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, suggestedModel, authScheme, credentialMetadata, allowInsecureHTTP
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        // Read the legacy field once so ProviderStore can migrate it to Keychain.
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        suggestedModel = try container.decodeIfPresent(String.self, forKey: .suggestedModel) ?? ""
        authScheme = try container.decodeIfPresent(ProviderAuthScheme.self, forKey: .authScheme) ?? .bearer
        credentialMetadata = try container.decodeIfPresent(
            ProviderCredentialMetadata.self,
            forKey: .credentialMetadata
        ) ?? .none
        allowInsecureHTTP = try container.decodeIfPresent(Bool.self, forKey: .allowInsecureHTTP) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(suggestedModel, forKey: .suggestedModel)
        try container.encode(authScheme, forKey: .authScheme)
        try container.encode(credentialMetadata, forKey: .credentialMetadata)
        try container.encode(allowInsecureHTTP, forKey: .allowInsecureHTTP)
    }

    var isLocalEndpoint: Bool {
        ProviderEndpointPolicy.isLocal(baseURL: baseURL)
    }

    var hasInlineKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var maskedKeyPreview: String { CustomModel.mask(apiKey) }

    var credentialMethodLabel: String {
        switch credentialMetadata.kind {
        case .none: return authScheme == .none ? "No credential" : "Not connected"
        case .apiKey: return "API key"
        case .oauthIssuedKey: return "OpenRouter OAuth"
        }
    }

    var validationError: String? {
        if id.trimmingCharacters(in: .whitespaces).isEmpty { return "Provider id is required." }
        if !ProviderAuthContract.isValidProviderID(id) {
            return "Provider id may only contain letters, numbers, dots, dashes, and underscores."
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Provider name is required." }
        let url = baseURL.trimmingCharacters(in: .whitespaces)
        if url.isEmpty { return "Base URL is required." }
        if !(url.hasPrefix("http://") || url.hasPrefix("https://")) {
            return "Base URL must start with http:// or https://."
        }
        if let transportIssue = ProviderEndpointPolicy.transportIssue(
            forBaseURL: url,
            allowingInsecureHTTP: allowInsecureHTTP
        ) {
            return transportIssue
        }
        return nil
    }
}

/// Built-in provider presets for popular OpenAI-compatible endpoints.
enum ProviderPreset: String, CaseIterable, Identifiable {
    case openai
    case openrouter
    case zai
    case minimax
    case kimi
    case qwen
    case xiaomiMiMo
    case deepseek
    case ollama
    case clinePass

    var id: String { rawValue }

    /// Finds the built-in preset whose provider id matches an installed provider.
    static func matching(provider: Provider) -> ProviderPreset? {
        allCases.first { $0.provider.id == provider.id }
    }

    var displayName: String {
        switch self {
        case .openai: return "ChatGPT (OpenAI)"
        case .openrouter: return "OpenRouter"
        case .zai: return "Z.ai (GLM)"
        case .minimax: return "MiniMax"
        case .kimi: return "Kimi (Moonshot)"
        case .qwen: return "Qwen (DashScope)"
        case .xiaomiMiMo: return "Xiaomi MiMo"
        case .deepseek: return "DeepSeek"
        case .ollama: return "Ollama (local)"
        case .clinePass: return "Cline Pass"
        }
    }

    var connectionMethodLabel: String {
        switch self {
        case .openrouter: return "OAuth or API key"
        case .ollama: return "No credential"
        default: return "API key"
        }
    }

    var supportsBrowserOAuth: Bool { self == .openrouter }

    /// Whether GrokBuild can discover models via `GET {base_url}/models`.
    var supportsModelListingFetch: Bool {
        switch self {
        case .clinePass: return false
        default: return true
        }
    }

    /// Whether GrokBuild fetches this provider's models from Cline's public recommended-models
    /// feed (no API key required) instead of `{base_url}/models`.
    var supportsLiveCatalogRefresh: Bool {
        switch self {
        case .clinePass: return true
        default: return false
        }
    }

    var catalogDocumentationURL: URL? {
        switch self {
        case .clinePass:
            return ClinePassCatalog.documentationURL
        case .openrouter:
            return URL(string: "https://openrouter.ai/models")
        default:
            return nil
        }
    }

    /// Protocol used for newly-added models from this preset.
    var defaultAPIBackend: ModelAPIBackend {
        switch self {
        case .openai: return .responses
        default: return .chatCompletions
        }
    }

    var provider: Provider {
        switch self {
        case .openai:
            return Provider(
                id: "openai",
                name: "ChatGPT (OpenAI)",
                baseURL: "https://api.openai.com/v1",
                suggestedModel: "gpt-4o"
            )
        case .openrouter:
            // One OpenRouter key fronts models from many labs. It is OpenAI Chat
            // Completions-compatible, so it rides the existing provider/catalog/Keychain
            // machinery. `openrouter/auto` is the always-available auto-router default;
            // fetch the catalog to pin a specific model like `openai/gpt-4o`.
            return Provider(
                id: "openrouter",
                name: "OpenRouter",
                baseURL: "https://openrouter.ai/api/v1",
                suggestedModel: "openrouter/auto"
            )
        case .zai:
            return Provider(
                id: "zai",
                name: "Z.ai (GLM)",
                baseURL: "https://api.z.ai/api/coding/paas/v4",
                suggestedModel: "glm-5.2"
            )
        case .minimax:
            return Provider(
                id: "minimax",
                name: "MiniMax",
                baseURL: "https://api.minimax.io/v1",
                suggestedModel: "minimax-m2.5"
            )
        case .kimi:
            return Provider(
                id: "kimi",
                name: "Kimi (Moonshot)",
                baseURL: "https://api.moonshot.ai/v1",
                suggestedModel: "kimi-k2.6"
            )
        case .qwen:
            return Provider(
                id: "qwen",
                name: "Qwen (DashScope)",
                baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                suggestedModel: "qwen3.7-plus"
            )
        case .xiaomiMiMo:
            return Provider(
                id: "xiaomi-mimo",
                name: "Xiaomi MiMo",
                baseURL: "https://api.xiaomimimo.com/v1",
                suggestedModel: "mimo-v2.5-pro",
                authScheme: .bearerAndAPIKey
            )
        case .deepseek:
            return Provider(
                id: "deepseek",
                name: "DeepSeek",
                baseURL: "https://api.deepseek.com",
                suggestedModel: "deepseek-v4-pro"
            )
        case .ollama:
            // Ollama ignores the key, but its OpenAI-compatible endpoint expects a
            // non-empty value; "ollama" is the conventional placeholder.
            return Provider(
                id: "ollama",
                name: "Ollama (local)",
                baseURL: "http://localhost:11434/v1",
                apiKey: "ollama",
                suggestedModel: "llama3.2",
                authScheme: .none
            )
        case .clinePass:
            return Provider(
                id: "clinepass",
                name: "Cline Pass",
                baseURL: "https://api.cline.bot/api/v1",
                suggestedModel: "cline-pass/glm-5.2"
            )
        }
    }
}

/// Helpers for Cline Pass model listing (live feed + display labels).
///
/// Docs: [ClinePass — Models](https://docs.cline.bot/getting-started/clinepass#models).
enum ClinePassCatalog {
    static let documentationURL = URL(string: "https://docs.cline.bot/getting-started/clinepass#models")!

    /// Public Cline recommended-models feed (includes a `clinePass` array; no API key required).
    static let recommendedModelsURL = URL(
        string: "https://api.cline.bot/api/v1/ai/cline/recommended-models"
    )!

    /// Human-readable label derived from a Cline Pass model id slug.
    static func displayLabel(for modelID: String) -> String {
        let slug = modelID.split(separator: "/").last.map(String.init) ?? modelID
        let acronyms: Set<String> = ["glm", "gpt"]
        return slug
            .split(separator: "-")
            .map { part -> String in
                let token = String(part)
                if token.allSatisfy({ $0.isNumber || $0 == "." }) { return token }
                let lower = token.lowercased()
                if acronyms.contains(lower) { return lower.uppercased() }
                return token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Display name written to config.toml `name` (e.g. "Cline Kimi K2.7 Code").
    static func displayName(for catalogName: String) -> String {
        let trimmed = catalogName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasPrefix("cline ") { return trimmed }
        return "Cline \(trimmed)"
    }

    /// Sorts models A–Z by display label (falls back to id), so related names stay adjacent.
    static func sortedAlphabetically(_ models: [FetchedModel]) -> [FetchedModel] {
        models.sorted { lhs, rhs in
            let left = (lhs.ownedBy?.isEmpty == false ? lhs.ownedBy! : lhs.id)
            let right = (rhs.ownedBy?.isEmpty == false ? rhs.ownedBy! : rhs.id)
            let labelOrder = left.localizedCaseInsensitiveCompare(right)
            if labelOrder != .orderedSame { return labelOrder == .orderedAscending }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }
}

extension Provider {
    var matchingPreset: ProviderPreset? { ProviderPreset.matching(provider: self) }

    var supportsModelListingFetch: Bool {
        matchingPreset?.supportsModelListingFetch ?? true
    }

    var catalogDocumentationURL: URL? {
        matchingPreset?.catalogDocumentationURL
    }

    var supportsLiveCatalogRefresh: Bool {
        matchingPreset?.supportsLiveCatalogRefresh ?? false
    }
}

/// A single entry returned by a provider's `/v1/models` listing.
struct FetchedModel: Identifiable, Hashable, Sendable {
    var id: String
    var ownedBy: String?
    /// Per-token USD rates when the catalog advertises them (OpenRouter does; most
    /// OpenAI-style providers omit pricing and these stay nil). Used only for
    /// display-side usage estimates — never for billing decisions.
    var promptPricePerToken: Double?
    var completionPricePerToken: Double?
}

enum ProviderValidationStatus: String, Sendable, Equatable {
    case connected
    case unauthorized
    case rateLimited
    case endpointMissing
    case providerUnavailable
    case incompatibleResponse
    case timeoutOrOffline
    case emptyCatalog
    case modelUnavailable
    case insecureEndpoint
    case redirectBlocked
}

struct ProviderValidationResult: Sendable, Equatable {
    var status: ProviderValidationStatus
    var models: [FetchedModel]
    var missingModelIDs: [String]
    var message: String
    var checkedAt: Date

    var isConnected: Bool { status == .connected }

    /// A static snapshot label. SwiftUI's `.relative` date style installs a repeating timer;
    /// rebuilding the full Models scroll surface every second cost double-digit idle CPU after
    /// several providers were validated.
    var checkedAtLabel: String {
        DateFormatter.localizedString(from: checkedAt, dateStyle: .none, timeStyle: .medium)
    }
}

/// Fetches the list of available models from an OpenAI-compatible provider.
///
/// Calls `GET {base_url}/models` with `Authorization: Bearer <key>` and decodes the
/// standard OpenAI response shape `{ "object": "list", "data": [{ "id": ... }] }`.
/// The base URL already carries any version suffix (e.g. `/v1`,
/// `/compatible-mode/v1`, or none for DeepSeek), so we only trim a trailing slash
/// before appending `/models`.
enum ProviderModelFetcher {
    enum FetchError: LocalizedError {
        case invalidURL
        case unauthorized
        case rateLimited
        case endpointMissing
        case providerUnavailable(Int)
        case http(Int)
        case empty
        case transport(String)
        case decode
        case insecureEndpoint
        case redirectBlocked

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "The base URL is not a valid endpoint."
            case .unauthorized: return "Unauthorized — check the API key for this provider."
            case .rateLimited: return "The provider rate-limited this check. Try again shortly."
            case .endpointMissing: return "The provider does not expose a model catalog at this URL."
            case .providerUnavailable(let code): return "The provider is unavailable (HTTP \(code))."
            case .http(let code): return "The provider returned HTTP \(code)."
            case .empty: return "The provider returned no models."
            case .transport(let message): return message
            case .decode: return "Could not read the model list from the provider."
            case .insecureEndpoint:
                return "This remote endpoint uses http:// — GrokBuild will not send a credential over an unencrypted connection. Switch the base URL to https:// (http is allowed only for local servers)."
            case .redirectBlocked:
                return "The provider redirected this request to a different origin or an insecure URL, so GrokBuild stopped the check without following it."
            }
        }
    }

    /// Builds the `/models` URL from a base URL, preserving any existing version path.
    static func modelsURL(for baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: normalized + "/models")
    }

    /// Case-insensitive substring match on a fetched model's id and its owner label —
    /// used to filter large catalogs (OpenRouter returns ~300+) in the picker.
    static func filterModels(_ models: [FetchedModel], query rawQuery: String) -> [FetchedModel] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.id.lowercased().contains(query) || ($0.ownedBy?.lowercased().contains(query) ?? false)
        }
    }

    /// Resolves the effective inline API key for a fetch, or nil when none is set.
    static func resolveKey(apiKey: String) -> String? {
        let inline = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return inline.isEmpty ? nil : inline
    }

    /// Parses an OpenAI-style `/models` payload into a sorted, de-duplicated list.
    static func parse(_ data: Data) -> [FetchedModel]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        // Accept either { "data": [...] } or a bare top-level array.
        let rawList: [Any]
        if let dict = object as? [String: Any], let list = dict["data"] as? [Any] {
            rawList = list
        } else if let list = object as? [Any] {
            rawList = list
        } else {
            return nil
        }

        var seen = Set<String>()
        var models: [FetchedModel] = []
        for item in rawList {
            guard let entry = item as? [String: Any] else { continue }
            // Most providers use "id"; a few echo "model".
            let identifier = (entry["id"] as? String) ?? (entry["model"] as? String)
            guard let id = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { continue }
            guard seen.insert(id).inserted else { continue }
            let pricing = entry["pricing"] as? [String: Any]
            models.append(FetchedModel(
                id: id,
                ownedBy: entry["owned_by"] as? String,
                promptPricePerToken: pricePerToken(pricing?["prompt"]),
                completionPricePerToken: pricePerToken(pricing?["completion"])
            ))
        }
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    /// OpenRouter serializes per-token USD rates as strings ("0.00000014"); tolerate
    /// numbers too. Zero and negative rates are treated as absent, not as free.
    static func pricePerToken(_ raw: Any?) -> Double? {
        let value: Double?
        if let string = raw as? String {
            value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let number = raw as? NSNumber {
            value = number.doubleValue
        } else {
            value = nil
        }
        guard let value, value > 0, value.isFinite else { return nil }
        return value
    }

    static func request(for provider: Provider) throws -> URLRequest {
        guard let url = modelsURL(for: provider.baseURL) else { throw FetchError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !provider.isLocalEndpoint, provider.authScheme != .none,
           let key = resolveKey(apiKey: provider.apiKey) {
            // A credential never rides a cleartext remote connection — unless the user
            // explicitly opted this provider into trusted-LAN http.
            guard ProviderEndpointPolicy.isHTTPS(provider.baseURL) || provider.allowInsecureHTTP else {
                throw FetchError.insecureEndpoint
            }
            switch provider.authScheme {
            case .bearer:
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            case .apiKeyHeader:
                request.setValue(key, forHTTPHeaderField: "api-key")
            case .bearerAndAPIKey:
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.setValue(key, forHTTPHeaderField: "api-key")
            case .none:
                break
            }
        }
        return request
    }

    /// Fetches and parses the model list using this provider's explicit auth scheme.
    static func fetch(
        for provider: Provider,
        session: URLSession = .shared
    ) async throws -> [FetchedModel] {
        if provider.supportsLiveCatalogRefresh {
            return try await fetchClinePassRecommended(session: session)
        }
        let request = try request(for: provider)

        let data: Data
        let response: URLResponse
        do {
            // The policy delegate follows redirects only within the original origin;
            // a refused hop surfaces here as the raw 30x response.
            (data, response) = try await session.data(
                for: request,
                delegate: ProviderRedirectPolicyDelegate()
            )
        } catch {
            throw FetchError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if (300..<400).contains(http.statusCode) { throw FetchError.redirectBlocked }
            if http.statusCode == 401 || http.statusCode == 403 { throw FetchError.unauthorized }
            if http.statusCode == 404 { throw FetchError.endpointMissing }
            if http.statusCode == 429 { throw FetchError.rateLimited }
            if http.statusCode >= 500 { throw FetchError.providerUnavailable(http.statusCode) }
            guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
        }

        guard let models = parse(data) else { throw FetchError.decode }
        guard !models.isEmpty else { throw FetchError.empty }
        return models
    }

    /// Fetches Cline Pass models from the public recommended-models feed (no API key).
    static func fetchClinePassRecommended(
        url: URL = ClinePassCatalog.recommendedModelsURL,
        session: URLSession = .shared
    ) async throws -> [FetchedModel] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(
                for: request,
                delegate: ProviderRedirectPolicyDelegate()
            )
        } catch {
            throw FetchError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if (300..<400).contains(http.statusCode) { throw FetchError.redirectBlocked }
            guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
        }

        guard let models = parseClinePassRecommended(data) else { throw FetchError.decode }
        guard !models.isEmpty else { throw FetchError.empty }
        return models
    }

    /// Parses `{ "clinePass": [{ "id": "cline-pass/…", "name": "…" }] }` from Cline's feed.
    static func parseClinePassRecommended(_ data: Data) -> [FetchedModel]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["clinePass"] as? [Any] else {
            return nil
        }

        var seen = Set<String>()
        var models: [FetchedModel] = []
        for item in list {
            guard let entry = item as? [String: Any] else { continue }
            let identifier = (entry["id"] as? String) ?? (entry["model"] as? String)
            guard let id = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  id.hasPrefix("cline-pass/") else { continue }
            guard seen.insert(id).inserted else { continue }
            models.append(FetchedModel(id: id, ownedBy: ClinePassCatalog.displayLabel(for: id)))
        }
        // Alphabetical by display label (related names stay adjacent).
        return ClinePassCatalog.sortedAlphabetically(models)
    }

    static func validate(
        provider: Provider,
        configuredModelIDs: [String],
        session: URLSession = .shared,
        now: Date = Date()
    ) async -> ProviderValidationResult {
        do {
            let models = try await fetch(for: provider, session: session)
            let available = Set(models.map(\.id))
            let missing = configuredModelIDs.filter { !available.contains($0) }.sorted()
            if !missing.isEmpty {
                return ProviderValidationResult(
                    status: .modelUnavailable,
                    models: models,
                    missingModelIDs: missing,
                    message: "Connected, but the configured model is not available to this credential.",
                    checkedAt: now
                )
            }
            return ProviderValidationResult(
                status: .connected,
                models: models,
                missingModelIDs: [],
                message: "Connected — \(models.count) model\(models.count == 1 ? "" : "s") available.",
                checkedAt: now
            )
        } catch let error as FetchError {
            let status: ProviderValidationStatus
            switch error {
            case .unauthorized: status = .unauthorized
            case .rateLimited: status = .rateLimited
            case .endpointMissing, .invalidURL: status = .endpointMissing
            case .providerUnavailable: status = .providerUnavailable
            case .decode: status = .incompatibleResponse
            case .transport: status = .timeoutOrOffline
            case .empty: status = .emptyCatalog
            case .http: status = .providerUnavailable
            case .insecureEndpoint: status = .insecureEndpoint
            case .redirectBlocked: status = .redirectBlocked
            }
            return ProviderValidationResult(
                status: status,
                models: [],
                missingModelIDs: [],
                message: error.localizedDescription,
                checkedAt: now
            )
        } catch {
            return ProviderValidationResult(
                status: .timeoutOrOffline,
                models: [],
                missingModelIDs: [],
                message: error.localizedDescription,
                checkedAt: now
            )
        }
    }
}

/// Persists provider metadata in UserDefaults and provider credentials in macOS Keychain.
enum ProviderStore {
    private static let key = "grokbuild.customModelProviders"

    struct LoadResult: Sendable {
        var providers: [Provider]
        var migrationIssues: [ProviderCredentialMigrationIssue]
    }

    static func load() -> [Provider] {
        loadResult().providers
    }

    static func loadResult(
        defaults: UserDefaults = .standard,
        credentialStore: any ProviderCredentialStoring = KeychainProviderCredentialStore(),
        migrationModels: [CustomModel]? = nil,
        enforceConfigPermissions: Bool = true,
        allowCredentialMigration: Bool = true
    ) -> LoadResult {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Provider].self, from: data) else {
            if enforceConfigPermissions {
                try? GrokConfigRepository.shared.enforceSecurePermissionsIfPresent()
            }
            return LoadResult(providers: [], migrationIssues: [])
        }

        let normalized = decoded.map { provider -> Provider in
            var copy = provider
            if let preset = ProviderPreset.matching(provider: provider) {
                copy.authScheme = preset.provider.authScheme
            } else if provider.isLocalEndpoint {
                copy.authScheme = .none
            }
            return copy
        }
        if !allowCredentialMigration {
            var hydrated = normalized
            var issues: [ProviderCredentialMigrationIssue] = []
            for index in hydrated.indices {
                do {
                    hydrated[index].apiKey = try credentialStore.credential(for: hydrated[index].id) ?? ""
                } catch {
                    issues.append(ProviderCredentialMigrationIssue(
                        kind: .storage,
                        providerID: hydrated[index].id,
                        message: error.localizedDescription
                    ))
                }
            }
            if enforceConfigPermissions {
                try? GrokConfigRepository.shared.enforceSecurePermissionsIfPresent()
            }
            return LoadResult(providers: hydrated, migrationIssues: issues)
        }
        let migration = ProviderCredentialMigrator.migrate(
            providers: normalized,
            models: migrationModels ?? CustomModelStore.load().models,
            credentialStore: credentialStore
        )

        var issues = migration.issues
        if !migration.storageFailed {
            do {
                if enforceConfigPermissions {
                    try GrokConfigRepository.shared.enforceSecurePermissionsIfPresent()
                }
                try saveMetadata(migration.providers, defaults: defaults)
            } catch {
                for providerID in migration.createdProviderIDs {
                    try? credentialStore.removeCredential(for: providerID)
                }
                issues.append(ProviderCredentialMigrationIssue(
                    kind: .storage,
                    providerID: "provider-metadata",
                    message: error.localizedDescription
                ))
                return LoadResult(providers: normalized, migrationIssues: issues)
            }
        }
        return LoadResult(providers: migration.providers, migrationIssues: issues)
    }

    static func save(
        _ providers: [Provider],
        defaults: UserDefaults = .standard,
        credentialStore: any ProviderCredentialStoring = KeychainProviderCredentialStore()
    ) throws {
        let priorProviders: [Provider]
        if let data = defaults.data(forKey: key) {
            priorProviders = (try? JSONDecoder().decode([Provider].self, from: data)) ?? []
        } else {
            priorProviders = []
        }

        let providerIDs = Set(priorProviders.map(\.id)).union(providers.map(\.id))
        var priorCredentials: [String: String?] = [:]
        for providerID in providerIDs {
            priorCredentials[providerID] = try credentialStore.credential(for: providerID)
        }

        do {
            for provider in providers {
                let credential = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if credential.isEmpty {
                    try credentialStore.removeCredential(for: provider.id)
                } else {
                    try credentialStore.setCredential(credential, for: provider.id)
                    guard try credentialStore.credential(for: provider.id) == credential else {
                        throw ProviderCredentialError.verificationFailed
                    }
                }
            }
            for removedID in Set(priorProviders.map(\.id)).subtracting(providers.map(\.id)) {
                try credentialStore.removeCredential(for: removedID)
            }
            try saveMetadata(providers, defaults: defaults)
        } catch {
            for (providerID, previousCredential) in priorCredentials {
                if let previousCredential {
                    try? credentialStore.setCredential(previousCredential, for: providerID)
                } else {
                    try? credentialStore.removeCredential(for: providerID)
                }
            }
            throw error
        }
    }

    private static func saveMetadata(_ providers: [Provider], defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(providers), forKey: key)
    }
}

/// Reads and writes custom model entries in `~/.grok/config.toml`.
///
/// The store manages only flat `[model.<id>]` tables and the `default` key inside `[models]`.
/// Advanced model/provider structures belong to the Grok CLI; writes fail closed when those
/// structures are present because this text editor cannot preserve their TOML semantics.
enum CustomModelStore {
    /// Maximum number of custom models GrokBuild will manage in `~/.grok/config.toml`.
    static let maxModels = 28
    private static let managedModelKeys: Set<String> = [
        "model", "base_url", "name", "api_key", "model_provider", "api_backend", "context_window",
        "grokbuild_context_tokens", "grokbuild_supports_reasoning_effort",
        "grokbuild_supports_vision", "grokbuild_supports_thinking", "grokbuild_provider_id",
    ]
    private static let managedProviderKeys: Set<String> = ["base_url"]
    private static let managedProviderAuthKeys: Set<String> = [
        "command", "args", "token_ttl_secs", "timeout_secs",
    ]

    static var configURL: URL {
        GrokConfigRepository.shared.configURL
    }

    struct RemovalPlan: Equatable {
        var models: [CustomModel]
        var defaultModelID: String?
    }

    struct ConfigMutationReceipt: Equatable, Sendable {
        let previousConfig: String
        let committedConfig: String
    }

    static func removalPlan(
        removing modelID: String,
        from models: [CustomModel],
        defaultModelID: String?
    ) -> RemovalPlan {
        RemovalPlan(
            models: models.filter { $0.id != modelID },
            defaultModelID: defaultModelID == modelID ? nil : defaultModelID
        )
    }

    // MARK: - Loading

    struct WriteSafety: Sendable, Equatable {
        enum Blocker: String, CaseIterable, Sendable {
            case invalidTOML
            case nestedModelTables
            case modelProviderTables
            case modelProviderReferences
            case unrecognizedModelTable
            case unsupportedModelFields
            case unsafeKeylessRemoteModel
            case unsafeFlatCredentialModel

            var label: String {
                switch self {
                case .invalidTOML:
                    "invalid TOML syntax"
                case .nestedModelTables:
                    "nested [model.<id>.*] tables"
                case .modelProviderTables:
                    "[model_providers.*] tables"
                case .modelProviderReferences:
                    "model_provider references"
                case .unrecognizedModelTable:
                    "unrecognized model table headers"
                case .unsupportedModelFields:
                    "partial or unsupported model fields"
                case .unsafeKeylessRemoteModel:
                    "remote custom endpoints without an explicit provider credential boundary"
                case .unsafeFlatCredentialModel:
                    "inline credentials without an exact GrokBuild provider link"
                }
            }
        }

        var blockers: [Blocker]

        static let writable = WriteSafety(blockers: [])

        /// A legacy remote keyless flat model may be rewritten only through a validated
        /// provider projection. Every other unsupported shape remains a hard lock.
        var canWrite: Bool {
            blockers.allSatisfy { $0 == .unsafeKeylessRemoteModel }
        }

        /// The locked file shape may be converted only when the app-owned metadata
        /// proves every affected model already has an exact provider link. The final
        /// locked save repeats this check against the latest bytes and staged models.
        var containsOnlyLegacyProjectionBlockers: Bool {
            !blockers.isEmpty && blockers.allSatisfy {
                $0 == .unsafeKeylessRemoteModel || $0 == .unsafeFlatCredentialModel
            }
        }

        var blockingMessage: String? {
            guard !blockers.isEmpty else { return nil }
            let details = blockers.map(\.label).joined(separator: ", ")
            return "GrokBuild left config.toml unchanged because it uses Grok CLI-owned advanced model configuration (\(details)). Manage these entries with the Grok CLI or edit config.toml directly."
        }
    }

    enum SaveError: LocalizedError, Equatable {
        case advancedConfiguration(WriteSafety)
        case invalidProjection(String)
        case candidateRejected(String)
        case candidateRollbackFailed

        var errorDescription: String? {
            switch self {
            case .advancedConfiguration(let safety):
                safety.blockingMessage
            case .invalidProjection(let message):
                message
            case .candidateRejected(let message):
                message
            case .candidateRollbackFailed:
                "The Grok CLI rejected the candidate, but config.toml changed before GrokBuild could restore its previous bytes. Reload Models before making another change."
            }
        }
    }

    /// Loaded custom models plus the configured default model id (which may reference a built-in).
    struct Snapshot: Sendable {
        var models: [CustomModel]
        var defaultModelID: String?
        var writeSafety: WriteSafety
        var usesOfficialProviderProjection: Bool
        var officiallyProjectedModelIDs: Set<String>
        /// Flat custom endpoints have no provider boundary and may inherit the
        /// signed-in xAI bearer. This is a dispatch quarantine, not catalog ownership.
        var unsafeFlatModelIDs: Set<String>
    }

    static func load(
        repository: GrokConfigRepository = .shared,
        defaults: UserDefaults = .standard
    ) -> Snapshot {
        let contents = repository.read()
        guard !contents.isEmpty else {
            return Snapshot(
                models: [],
                defaultModelID: nil,
                writeSafety: .writable,
                usesOfficialProviderProjection: false,
                officiallyProjectedModelIDs: [],
                unsafeFlatModelIDs: []
            )
        }
        var snapshot = parse(contents)
        snapshot.models = CustomModelMetadataStore.apply(to: snapshot.models, defaults: defaults)
        if snapshot.writeSafety.containsOnlyLegacyProjectionBlockers,
           legacyProjectionIsExact(models: snapshot.models) {
            snapshot.writeSafety = .writable
        }
        return snapshot
    }

    static func parse(_ contents: String) -> Snapshot {
        var tableFields: [[String]: [String: String]] = [:]
        var currentTablePath: [String]?
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentTablePath = tablePath(from: line)
                continue
            }

            guard let currentTablePath,
                  let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq].trimmingCharacters(in: .whitespaces))
            let value = unquote(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces))
            tableFields[currentTablePath, default: [:]][key] = value
        }

        let providerBaseURLs = tableFields.reduce(into: [String: String]()) { result, entry in
            let (path, fields) = entry
            guard path.count == 2,
                  path[0] == "model_providers",
                  ProviderAuthContract.isManagedOfficialProviderID(path[1]),
                  let baseURL = fields["base_url"] else { return }
            result[path[1]] = baseURL
        }

        let models = tableFields.compactMap { path, fields -> CustomModel? in
            guard path.count == 2, path[0] == "model" else { return nil }
            let officialProviderID = fields["model_provider"]
            let providerID = officialProviderID.flatMap(ProviderAuthContract.appProviderID(from:))
                ?? fields["grokbuild_provider_id"].flatMap { legacyID in
                    ProviderAuthContract.isValidProviderID(legacyID) ? legacyID : nil
                }
            return CustomModel(
                id: path[1],
                model: fields["model"] ?? "",
                baseURL: fields["base_url"]
                    ?? officialProviderID.flatMap { providerBaseURLs[$0] }
                    ?? "",
                name: fields["name"] ?? "",
                apiKey: fields["api_key"] ?? "",
                contextTokens: parseInt(fields["context_window"])
                    ?? parseInt(fields["grokbuild_context_tokens"]),
                supportsReasoningEffort: parseBool(fields["grokbuild_supports_reasoning_effort"]) ?? true,
                supportsVision: parseBool(fields["grokbuild_supports_vision"]) ?? false,
                supportsThinkingDisplay: parseBool(fields["grokbuild_supports_thinking"]) ?? false,
                apiBackend: ModelAPIBackend(rawValue: fields["api_backend"] ?? "") ?? .chatCompletions,
                providerID: providerID
            )
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }

        let officiallyProjectedModelIDs = Set(tableFields.compactMap { path, fields -> String? in
            guard path.count == 2,
                  path[0] == "model",
                  let reference = fields["model_provider"],
                  ProviderAuthContract.isManagedOfficialProviderID(reference) else { return nil }
            return path[1]
        })
        let providerBoundModelIDs = Set(tableFields.compactMap { path, fields -> String? in
            guard path.count == 2,
                  path[0] == "model",
                  fields["model_provider"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            return path[1]
        })
        let allModelIDs = Set(models.map(\.id))
        return Snapshot(
            models: models,
            defaultModelID: tableFields[["models"]]?["default"],
            writeSafety: writeSafety(for: contents),
            usesOfficialProviderProjection: !officiallyProjectedModelIDs.isEmpty,
            officiallyProjectedModelIDs: officiallyProjectedModelIDs,
            unsafeFlatModelIDs: allModelIDs.subtracting(providerBoundModelIDs)
        )
    }

    static func runtimeEligibleModels(from snapshot: Snapshot) -> [CustomModel] {
        snapshot.models.filter { snapshot.officiallyProjectedModelIDs.contains($0.id) }
    }

    static func quarantinedRuntimeModelIDs(from snapshot: Snapshot) -> Set<String> {
        snapshot.unsafeFlatModelIDs
    }

    // MARK: - Saving

    /// Persists `models` and `defaultModelID` into the config file, preserving unrelated content.
    @discardableResult
    static func save(
        models: [CustomModel],
        defaultModelID: String?,
        providers: [Provider] = [],
        repository: GrokConfigRepository = .shared,
        defaults: UserDefaults = .standard,
        persistMetadata: Bool = true,
        candidateValidator: ((Set<String>, Set<String>) throws -> Void)? = nil
    ) throws -> ConfigMutationReceipt {
        var previousConfig = ""
        var committedConfig = ""
        try repository.update { existing in
            previousConfig = existing
            let safety = writeSafety(for: existing)
            let exactLegacyMigration = safety.containsOnlyLegacyProjectionBlockers
                && legacyProjectionIsExact(models: models)
            guard safety.canWrite || exactLegacyMigration else {
                throw SaveError.advancedConfiguration(safety)
            }
            try validateProjection(models: models, providers: providers)
            let candidate = rewrite(
                existing,
                models: models,
                defaultModelID: defaultModelID,
                providers: providers
            )
            committedConfig = candidate
            return candidate
        }

        let isLiveConfig = repository.configURL.standardizedFileURL
            == GrokConfigRepository.shared.configURL.standardizedFileURL
        if candidateValidator != nil || isLiveConfig {
            let validator = candidateValidator ?? GrokConfigCandidateInspector.validate
            let modelIDs = Set(models.map(\.id))
            let providerIDs = Set(providerProjections(models: models, providers: providers).map(\.officialID))
            do {
                try validator(modelIDs, providerIDs)
            } catch {
                do {
                    try repository.update { current in
                        guard current == committedConfig else {
                            throw GrokConfigRepository.UpdateError.changedDuringUpdate
                        }
                        return previousConfig
                    }
                } catch {
                    throw SaveError.candidateRollbackFailed
                }
                throw SaveError.candidateRejected(error.localizedDescription)
            }
        }
        if persistMetadata {
            CustomModelMetadataStore.save(models: models, defaults: defaults)
        }
        return ConfigMutationReceipt(
            previousConfig: previousConfig,
            committedConfig: committedConfig
        )
    }

    static func requireWriteSafety(repository: GrokConfigRepository = .shared) throws {
        let safety = writeSafety(for: repository.read())
        guard safety.canWrite else {
            throw SaveError.advancedConfiguration(safety)
        }
    }

    /// Produces a new config string: drops all existing `[model.*]` tables and the `[models].default`
    /// key, then appends fresh versions while keeping every other section intact.
    static func rewrite(
        _ contents: String,
        models: [CustomModel],
        defaultModelID: String?,
        providers: [Provider] = []
    ) -> String {
        var preservedModelLines: [String: [String]] = [:]
        var preservingModelID: String?
        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                preservingModelID = header.hasPrefix("model.")
                    ? unquote(String(header.dropFirst("model.".count)))
                    : nil
                continue
            }
            guard let preservingModelID else { continue }
            if let key = trimmed.split(separator: "=", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces),
               Self.managedModelKeys.contains(key) {
                continue
            }
            if !trimmed.isEmpty {
                preservedModelLines[preservingModelID, default: []].append(rawLine)
            }
        }

        var output: [String] = []
        var skippingModelTable = false
        var skippingManagedProviderTable = false
        var inModelsTable = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let path = tablePath(from: trimmed)
                skippingModelTable = path?.count == 2 && path?.first == "model"
                skippingManagedProviderTable = path?.first == "model_providers"
                    && path.map { $0.count >= 2 && ProviderAuthContract.isManagedOfficialProviderID($0[1]) } == true
                inModelsTable = (path == ["models"])
                if skippingModelTable || skippingManagedProviderTable { continue }
                output.append(rawLine)
                continue
            }

            if skippingModelTable || skippingManagedProviderTable { continue }

            // Drop only the managed `default` key inside [models]; keep other [models] keys.
            if inModelsTable {
                if let eq = trimmed.firstIndex(of: "="),
                   trimmed[..<eq].trimmingCharacters(in: .whitespaces) == "default" {
                    continue
                }
            }

            output.append(rawLine)
        }

        // Trim trailing blank lines for a tidy append.
        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }

        var result = output.joined(separator: "\n")

        let projections = providerProjections(models: models, providers: providers)
        for projection in projections {
            result += "\n\n[model_providers.\(quoteKeyIfNeeded(projection.officialID))]\n"
            result += "base_url = \(quote(projection.baseURL))\n"
            if let helperProviderID = projection.helperProviderID {
                result += "\n[model_providers.\(quoteKeyIfNeeded(projection.officialID)).auth]\n"
                result += "command = \(quote(ProviderAuthContract.installedHelperPath))\n"
                result += "args = [\(quote(helperProviderID))]\n"
                result += "token_ttl_secs = 300\n"
                result += "timeout_secs = 10\n"
            }
        }

        // Append model tables.
        for model in models {
            result += "\n\n[model.\(quoteKeyIfNeeded(model.id))]\n"
            result += "model = \(quote(model.model))\n"
            if let projection = projection(for: model, providers: providers) {
                result += "model_provider = \(quote(projection.officialID))\n"
            } else {
                result += "base_url = \(quote(model.baseURL))\n"
            }
            if !model.name.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "name = \(quote(model.name))\n"
            }
            if projection(for: model, providers: providers) == nil,
               !model.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "api_key = \(quote(model.apiKey))\n"
            }
            result += "api_backend = \(quote(model.apiBackend.rawValue))\n"
            if let contextTokens = model.contextTokens {
                result += "context_window = \(contextTokens)\n"
            }
            if let preserved = preservedModelLines[model.id], !preserved.isEmpty {
                result += preserved.joined(separator: "\n") + "\n"
            }
        }

        // Re-establish [models].default. Reuse an existing [models] table if present.
        if let defaultModelID, !defaultModelID.trimmingCharacters(in: .whitespaces).isEmpty {
            if result.range(of: #"(?m)^\s*\[models\]\s*$"#, options: .regularExpression) != nil {
                result = result.replacingOccurrences(
                    of: #"(?m)^(\s*\[models\]\s*\n)"#,
                    with: "$1default = \(quote(defaultModelID))\n",
                    options: .regularExpression
                )
            } else {
                result += "\n\n[models]\ndefault = \(quote(defaultModelID))\n"
            }
        }

        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    private struct ProviderProjection: Equatable {
        var officialID: String
        var baseURL: String
        var helperProviderID: String?
    }

    private static func projection(for model: CustomModel, providers: [Provider]) -> ProviderProjection? {
        if let providerID = model.providerID,
           let provider = providers.first(where: { $0.id == providerID }),
           let officialID = ProviderAuthContract.officialProviderID(for: providerID) {
            return ProviderProjection(
                officialID: officialID,
                baseURL: provider.baseURL,
                helperProviderID: provider.authScheme == .bearer ? providerID : nil
            )
        }
        guard model.isLocalEndpoint,
              model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let officialID = ProviderAuthContract.officialLocalProviderID(for: model.id) else {
            return nil
        }
        return ProviderProjection(officialID: officialID, baseURL: model.baseURL, helperProviderID: nil)
    }

    private static func providerProjections(
        models: [CustomModel],
        providers: [Provider]
    ) -> [ProviderProjection] {
        var seen = Set<String>()
        return models.compactMap { projection(for: $0, providers: providers) }
            .filter { seen.insert($0.officialID).inserted }
            .sorted { $0.officialID.localizedStandardCompare($1.officialID) == .orderedAscending }
    }

    private static func validateProjection(models: [CustomModel], providers: [Provider]) throws {
        for model in models {
            if let providerID = model.providerID {
                guard let provider = providers.first(where: { $0.id == providerID }) else {
                    throw SaveError.invalidProjection(
                        "Model \(model.id) references a provider that is no longer available."
                    )
                }
                guard ProviderAuthContract.isValidProviderID(providerID) else {
                    throw SaveError.invalidProjection("Provider \(providerID) has an invalid id.")
                }
                switch provider.authScheme {
                case .bearer:
                    break
                case .none:
                    guard provider.isLocalEndpoint else {
                        throw SaveError.invalidProjection(
                            "Remote provider \(provider.name) cannot use No credential. Add a credential or use a local endpoint."
                        )
                    }
                case .apiKeyHeader, .bearerAndAPIKey:
                    throw SaveError.invalidProjection(
                        "Provider \(provider.name) uses an authentication shape the official Grok provider helper does not support yet. Its configuration was left unchanged."
                    )
                }
                continue
            }

            if model.isLocalEndpoint {
                guard model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw SaveError.invalidProjection(
                        "Local model \(model.id) has an inline credential but no exact provider link. Attach it to a provider before saving."
                    )
                }
                guard projection(for: model, providers: providers) != nil else {
                    throw SaveError.invalidProjection(
                        "Local model \(model.id) cannot be represented by the official provider boundary. Shorten its id before saving."
                    )
                }
            } else {
                throw SaveError.invalidProjection(
                    "Remote model \(model.id) has no exact provider link. Attach it to a provider before saving."
                )
            }
        }
    }

    /// True only for a legacy file whose credential-bearing or remote rows all
    /// carry an app-owned, exact sidecar link. Endpoint guessing is deliberately
    /// excluded: a same-looking URL is not ownership proof.
    private static func legacyProjectionIsExact(models: [CustomModel]) -> Bool {
        models.allSatisfy { $0.providerID != nil }
    }

    // MARK: - TOML helpers

    private static func stripComment(_ line: String) -> String {
        TOMLLineParsing.stripComment(line)
    }

    private static func unquote(_ value: String) -> String {
        TOMLLineParsing.unquote(value)
    }

    private static func quote(_ value: String) -> String {
        TOMLLineParsing.quote(value)
    }

    /// Detects model structures that this flat-table editor cannot preserve. Detection is
    /// intentionally conservative: a structure we do not understand blocks writes instead of
    /// gambling with the CLI's configuration.
    static func writeSafety(for contents: String) -> WriteSafety {
        var found: Set<WriteSafety.Blocker> = []
        var currentTablePath: [String]?
        var fieldsByModel: [String: [String: String]] = [:]

        if !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (try? TOMLDecoder().decode(TOMLValidationDocument.self, from: contents)) == nil {
            found.insert(.invalidTOML)
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                guard let path = tablePath(from: line) else {
                    currentTablePath = nil
                    if looksLikeModelConfigurationHeader(line) {
                        found.insert(.unrecognizedModelTable)
                    }
                    continue
                }
                currentTablePath = path
                if path.first == "model", path.count != 2 {
                    found.insert(.nestedModelTables)
                }
                if path.first == "model", path.count == 2,
                   !isCanonicalFlatModelHeader(line, modelID: path[1]) {
                    found.insert(.unrecognizedModelTable)
                }
                if path == ["models"], line != "[models]" {
                    found.insert(.unrecognizedModelTable)
                }
                if path.first == "model_providers" {
                    let officialID = path.count >= 2 ? path[1] : ""
                    let isManaged = ProviderAuthContract.isManagedOfficialProviderID(officialID)
                    let canonicalProvider = path.count == 2
                        && line == "[model_providers.\(quoteKeyIfNeeded(officialID))]"
                    let canonicalAuth = path.count == 3
                        && path[2] == "auth"
                        && line == "[model_providers.\(quoteKeyIfNeeded(officialID)).auth]"
                    if !isManaged || (!canonicalProvider && !canonicalAuth) {
                        found.insert(.modelProviderTables)
                    }
                }
                continue
            }

            guard let equals = line.firstIndex(of: "=") else { continue }
            let rawKey = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            if currentTablePath == nil {
                if let path = tablePath(from: "[\(rawKey)]") {
                    if path.first == "model" {
                        found.insert(.unrecognizedModelTable)
                    } else if path.first == "models" {
                        found.insert(.unrecognizedModelTable)
                    } else if path.first == "model_providers" {
                        found.insert(.modelProviderTables)
                    }
                } else {
                    let compactKey = rawKey.filter { !$0.isWhitespace }
                    if compactKey.hasPrefix("model.")
                        || compactKey.hasPrefix("\"model\".")
                        || compactKey.hasPrefix("'model'.") {
                        found.insert(.unrecognizedModelTable)
                    }
                }
            }

            if currentTablePath == ["models"] {
                guard let keyPath = tablePath(from: "[\(rawKey)]"), keyPath.count == 1 else {
                    found.insert(.unrecognizedModelTable)
                    continue
                }
                if keyPath[0] == "default", rawKey != "default" {
                    found.insert(.unrecognizedModelTable)
                }
            }

            if let path = currentTablePath,
               path.first == "model_providers" {
                guard path.count == 2 || (path.count == 3 && path[2] == "auth"),
                      ProviderAuthContract.isManagedOfficialProviderID(path[1]),
                      let keyPath = tablePath(from: "[\(rawKey)]"), keyPath.count == 1,
                      rawKey == keyPath[0] else {
                    found.insert(.modelProviderTables)
                    continue
                }
                let allowed = path.count == 2 ? managedProviderKeys : managedProviderAuthKeys
                if !allowed.contains(keyPath[0]) {
                    found.insert(.modelProviderTables)
                }
                continue
            }

            guard currentTablePath?.count == 2,
                  currentTablePath?.first == "model",
                  let modelID = currentTablePath?[1] else { continue }
            guard let keyPath = tablePath(from: "[\(rawKey)]"), keyPath.count == 1 else {
                found.insert(.unrecognizedModelTable)
                continue
            }
            let key = keyPath[0]
            if Self.managedModelKeys.contains(key), rawKey != key {
                found.insert(.unrecognizedModelTable)
            }
            if !Self.managedModelKeys.contains(key) {
                found.insert(.unsupportedModelFields)
            }
            fieldsByModel[modelID, default: [:]][key] = unquote(
                line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            )
            if key == "model_provider" {
                let reference = fieldsByModel[modelID]?[key] ?? ""
                if !ProviderAuthContract.isManagedOfficialProviderID(reference) {
                    found.insert(.modelProviderReferences)
                }
            }
        }

        let hasStructuralModelBlocker = found.contains(.nestedModelTables)
            || found.contains(.unrecognizedModelTable)
            || found.contains(.modelProviderReferences)
        for fields in fieldsByModel.values where !hasStructuralModelBlocker {
            if fields["model"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                found.insert(.unsupportedModelFields)
            }
            let hasManagedProvider = fields["model_provider"]
                .map(ProviderAuthContract.isManagedOfficialProviderID) == true
            let baseURL = fields["base_url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !hasManagedProvider, baseURL.isEmpty {
                found.insert(.unsupportedModelFields)
            }
            let hasExactLegacyProvider = fields["grokbuild_provider_id"].map {
                ProviderAuthContract.isValidProviderID($0)
            } == true
            if !hasManagedProvider,
               !hasExactLegacyProvider,
               !baseURL.isEmpty,
               !ProviderEndpointPolicy.isLocal(baseURL: baseURL) {
                if fields["api_key"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    found.insert(.unsafeFlatCredentialModel)
                } else {
                    found.insert(.unsafeKeylessRemoteModel)
                }
            }
            if !hasManagedProvider,
               !hasExactLegacyProvider,
               ProviderEndpointPolicy.isLocal(baseURL: baseURL),
               fields["api_key"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                found.insert(.unsafeFlatCredentialModel)
            }
        }

        let ordered = WriteSafety.Blocker.allCases.filter(found.contains)
        return WriteSafety(blockers: ordered)
    }

    private struct TOMLValidationDocument: Decodable {
        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
            init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
        }

        init(from decoder: Decoder) throws {
            _ = try decoder.container(keyedBy: Key.self)
        }
    }

    /// Parses a TOML table path only far enough to distinguish dotted path segments from dots
    /// inside quoted keys. This is detection, not a TOML rewriter; malformed/array headers return
    /// nil so the caller can fail closed.
    private static func tablePath(from line: String) -> [String]? {
        guard line.hasPrefix("["), line.hasSuffix("]"),
              !line.hasPrefix("[["), !line.hasSuffix("]]"), line.count >= 2 else { return nil }
        let body = line.dropFirst().dropLast()
        var components: [String] = []
        var component = ""
        var quote: Character?
        var escaped = false

        func appendComponent() -> Bool {
            let value = component.trimmingCharacters(in: .whitespaces)
            guard let decoded = decodeTablePathComponent(value) else { return false }
            components.append(decoded)
            component = ""
            return true
        }

        for character in body {
            if let activeQuote = quote {
                component.append(character)
                if activeQuote == "\"" {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == activeQuote {
                        quote = nil
                    }
                } else if character == activeQuote {
                    quote = nil
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                component.append(character)
            } else if character == "." {
                guard appendComponent() else { return nil }
            } else {
                component.append(character)
            }
        }

        guard quote == nil, appendComponent() else { return nil }
        return components
    }

    private static func decodeTablePathComponent(_ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        guard let first = value.first else { return nil }

        if first == "'" {
            guard value.count >= 2, value.last == "'" else { return nil }
            let inner = value.dropFirst().dropLast()
            guard !inner.contains("'") else { return nil }
            return String(inner)
        }

        if first == "\"" {
            guard value.count >= 2, value.last == "\"" else { return nil }
            let inner = value.dropFirst().dropLast()
            var decoded = ""
            var iterator = inner.makeIterator()
            while let character = iterator.next() {
                guard character == "\\" else {
                    guard character != "\"" else { return nil }
                    decoded.append(character)
                    continue
                }
                guard let escaped = iterator.next(), escaped == "\\" || escaped == "\"" else {
                    // Exotic TOML escapes may be valid, but this flat editor does not decode
                    // them. Refusing the write is safer than changing the model identity.
                    return nil
                }
                decoded.append(escaped)
            }
            return decoded
        }

        guard value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private static func looksLikeModelConfigurationHeader(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        return compact.hasPrefix("[model.")
            || compact.hasPrefix("[[model.")
            || compact.hasPrefix("[\"model\".")
            || compact.hasPrefix("['model'.")
            || compact.hasPrefix("[model_providers")
            || compact.hasPrefix("[[model_providers")
            || compact.hasPrefix("[\"model_providers\"")
            || compact.hasPrefix("['model_providers'")
    }

    private static func isCanonicalFlatModelHeader(_ line: String, modelID: String) -> Bool {
        let bare = modelID.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
        let expectedID = bare ? modelID : quote(modelID)
        return line == "[model.\(expectedID)]"
    }

    private static func parseBool(_ value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    private static func parseInt(_ value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Returns a TOML table-key segment for `[model.<key>]`.
    ///
    /// A *bare* TOML key may only contain `A-Za-z0-9_-`. A dot is a table-path separator, so an
    /// id like `minimax-m2.5` MUST be quoted (`"minimax-m2.5"`) — otherwise TOML reads it as the
    /// nested table `model.minimax-m2."5"` and the model id becomes `minimax-m2`.
    private static func quoteKeyIfNeeded(_ key: String) -> String {
        if key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
            return key
        }
        return quote(key)
    }
}

/// Coordinates provider credentials/metadata with the CLI model projection. Ordinary changes
/// publish a fail-closed provider projection before metadata; endpoint changes revoke the stable
/// helper credential first so a crash can never pair an old secret with a new destination.
enum ProviderModelConfigurationTransaction {
    enum TransactionError: LocalizedError {
        case configRollbackFailed
        case credentialRollbackFailed

        var errorDescription: String? {
            switch self {
            case .configRollbackFailed:
                "Provider state was not committed, but config.toml changed before GrokBuild could restore its previous bytes. Reload Models before making another change."
            case .credentialRollbackFailed:
                "The provider change was not committed, but GrokBuild could not restore the prior credential state. Reconnect the provider before sending another task."
            }
        }
    }

    static func save(
        previousProviders: [Provider],
        updatedProviders: [Provider],
        models: [CustomModel],
        defaultModelID: String?,
        repository: GrokConfigRepository = .shared,
        providerDefaults: UserDefaults = .standard,
        modelDefaults: UserDefaults = .standard,
        credentialStore: any ProviderCredentialStoring = KeychainProviderCredentialStore(),
        beforeConfigSave: () throws -> Void = {}
    ) throws {
        try beforeConfigSave()
        let priorByID = Dictionary(uniqueKeysWithValues: previousProviders.map { ($0.id, $0) })
        let updatedByID = Dictionary(uniqueKeysWithValues: updatedProviders.map { ($0.id, $0) })
        let priorIDs = Set(priorByID.keys)
        let updatedIDs = Set(updatedByID.keys)
        let changedProviderIDs = priorIDs.intersection(updatedIDs).filter { id in
            guard let prior = priorByID[id], let updated = updatedByID[id] else { return false }
            return prior.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                != updated.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                || prior.authScheme != updated.authScheme
        }
        // Stable Keychain accounts must not survive a destination/auth-boundary transition.
        // Added IDs are included to clear credentials orphaned by a prior crashed deletion.
        let preRevokedProviderIDs = priorIDs
            .symmetricDifference(updatedIDs)
            .union(changedProviderIDs)
        var preRevokedCredentials: [String: String?] = [:]
        for providerID in preRevokedProviderIDs {
            preRevokedCredentials[providerID] = try credentialStore.credential(for: providerID)
        }
        func restorePreRevokedCredentials() throws {
            for (providerID, credential) in preRevokedCredentials {
                if let credential {
                    try credentialStore.setCredential(credential, for: providerID)
                    guard try credentialStore.credential(for: providerID) == credential else {
                        throw ProviderCredentialError.verificationFailed
                    }
                } else {
                    try credentialStore.removeCredential(for: providerID)
                    guard try credentialStore.credential(for: providerID) == nil else {
                        throw ProviderCredentialError.verificationFailed
                    }
                }
            }
        }

        // A stable helper account must never bridge an old secret to a new endpoint.
        // Revoke first: every crash boundary is then old-pair, no-credential, or new-pair.
        do {
            for providerID in preRevokedProviderIDs {
                try credentialStore.removeCredential(for: providerID)
                guard try credentialStore.credential(for: providerID) == nil else {
                    throw ProviderCredentialError.verificationFailed
                }
            }
        } catch {
            try? restorePreRevokedCredentials()
            throw error
        }

        let configReceipt: CustomModelStore.ConfigMutationReceipt
        do {
            configReceipt = try CustomModelStore.save(
                models: models,
                defaultModelID: defaultModelID,
                providers: updatedProviders,
                repository: repository,
                defaults: modelDefaults,
                persistMetadata: false
            )
        } catch {
            do {
                try ProviderStore.save(
                    previousProviders,
                    defaults: providerDefaults,
                    credentialStore: credentialStore
                )
                try restorePreRevokedCredentials()
            } catch {
                throw TransactionError.credentialRollbackFailed
            }
            throw error
        }
        do {
            try ProviderStore.save(
                updatedProviders,
                defaults: providerDefaults,
                credentialStore: credentialStore
            )
        } catch {
            do {
                try repository.update { current in
                    guard current == configReceipt.committedConfig else {
                        throw GrokConfigRepository.UpdateError.changedDuringUpdate
                    }
                    return configReceipt.previousConfig
                }
            } catch {
                throw TransactionError.configRollbackFailed
            }
            do {
                try ProviderStore.save(
                    previousProviders,
                    defaults: providerDefaults,
                    credentialStore: credentialStore
                )
                try restorePreRevokedCredentials()
            } catch {
                throw TransactionError.credentialRollbackFailed
            }
            throw error
        }
        CustomModelMetadataStore.save(models: models, defaults: modelDefaults)
    }
}

/// A user-defined subagent **role** for grok's `[subagents.roles.<name>]` in `~/.grok/config.toml`.
///
/// Maps to a role table plus a prompt file holding the instruction, e.g.
/// ```toml
/// [subagents.roles.researcher]
/// description = "Deep research agent"
/// model = "grok-build"
/// prompt_file = "/Users/me/.grok/prompts/researcher.md"
/// ```
///
/// grok owns how roles are spawned; GrokBuild only edits the definition. An empty `model`
/// means the subagent inherits the parent session's model (grok's default behavior).
struct SubagentRole: Identifiable, Hashable, Sendable {
    /// The role name — the TOML table key `[subagents.roles.<name>]` and how the role is spawned.
    var name: String
    /// The model this role runs on. Empty = inherit the parent session's model.
    var model: String
    /// The role's system instruction, stored in a prompt file and referenced via `prompt_file`.
    var instruction: String
    /// Optional short description shown in `grok inspect` and the editor.
    var description: String
    /// Role keys GrokBuild does not edit directly (for example `default_capability_mode`).
    /// Values are preserved as TOML literals so saving from the UI does not erase valid grok config.
    var extraFields: [String: String]

    var id: String { name }

    init(
        name: String,
        model: String = "",
        instruction: String = "",
        description: String = "",
        extraFields: [String: String] = [:]
    ) {
        self.name = name
        self.model = model
        self.instruction = instruction
        self.description = description
        self.extraFields = extraFields
    }

    /// Derives a valid role name from free text (letters, numbers, dashes, underscores).
    static func suggestedName(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        var result = ""
        var lastWasSeparator = false
        for char in trimmed {
            if char.isLetter || char.isNumber || char == "_" || char == "-" {
                result.append(char)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-_")).lowercased()
    }

    /// Names reserved by grok's built-in subagents; a custom role may not shadow them.
    static let reservedNames: Set<String> = [
        "general", "general-purpose", "explore", "plan", "vision", "verify", "computer"
    ]

    /// A validation error message, or nil when the entry is well-formed.
    var validationError: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return "Name is required." }
        if trimmedName.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) == nil {
            return "Name may only contain letters, numbers, dashes, and underscores."
        }
        if SubagentRole.reservedNames.contains(trimmedName.lowercased()) {
            return "\"\(trimmedName)\" is reserved by a built-in subagent."
        }
        if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Instruction is required."
        }
        return nil
    }
}

/// Reads and writes custom subagent roles in `~/.grok/config.toml` (`[subagents.roles.*]`).
///
/// Mirrors `CustomModelStore`: it performs minimal, targeted edits — managing only
/// `[subagents.roles.<name>]` tables while preserving every other section (models, other
/// `[subagents.*]` tables, etc.). Each role's instruction lives in `~/.grok/prompts/<name>.md`
/// and is referenced from the role table via `prompt_file`.
enum SubagentRoleStore {
    /// Maximum number of custom roles GrokBuild will manage.
    static let maxRoles = 24

    static var configURL: URL {
        GrokConfigRepository.shared.configURL
    }

    static var promptsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/prompts")
    }

    static func promptURL(for name: String) -> URL {
        promptsDirectory.appendingPathComponent("\(name).md")
    }

    // MARK: - Loading

    static func load() -> [SubagentRole] {
        let contents = GrokConfigRepository.shared.read()
        guard !contents.isEmpty else { return [] }
        return parse(contents)
    }

    /// Parses `[subagents.roles.<name>]` tables, reading each instruction from its `prompt_file`.
    static func parse(
        _ contents: String,
        relativePromptBaseURL: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> [SubagentRole] {
        var roles: [SubagentRole] = []
        var currentName: String?
        var fields: [String: String] = [:]
        var rawFields: [String: String] = [:]

        func flush() {
            guard let name = currentName else { return }
            let instruction: String
            if let path = fields["prompt_file"], !path.isEmpty,
               let text = try? String(contentsOfFile: resolvePath(path, relativeTo: relativePromptBaseURL), encoding: .utf8) {
                instruction = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                instruction = ""
            }
            roles.append(SubagentRole(
                name: name,
                model: fields["model"] ?? "",
                instruction: instruction,
                description: fields["description"] ?? "",
                extraFields: rawFields.filter { !Self.managedRoleFields.contains($0.key) }
            ))
            currentName = nil
            fields = [:]
            rawFields = [:]
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush()
                let header = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if header.hasPrefix("subagents.roles.") {
                    currentName = unquote(String(header.dropFirst("subagents.roles.".count)))
                }
                continue
            }

            guard currentName != nil, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let value = unquote(rawValue)
            fields[key] = value
            rawFields[key] = String(rawValue)
        }
        flush()

        return roles
    }

    // MARK: - Saving

    /// Persists `roles` into config.toml (preserving unrelated content) and writes each
    /// instruction to its prompt file. Prompt files for removed roles are deleted only when
    /// the role's `prompt_file` in config.toml pointed to the GrokBuild-managed path.
    static func save(_ roles: [SubagentRole]) throws {
        let existing = GrokConfigRepository.shared.read()
        // Capture prompt_file paths before overwriting, so we can check which files are safe to delete.
        let previousPromptFiles = parsePromptFilePaths(existing)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: promptsDirectory, withIntermediateDirectories: true)

        for role in roles {
            try role.instruction.write(to: promptURL(for: role.name), atomically: true, encoding: .utf8)
        }

        // Remove prompt files only for roles that no longer exist and whose prompt_file
        // resolved to the GrokBuild-managed path (to avoid deleting user-maintained files).
        let keptNames = Set(roles.map(\.name))
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        for (name, rawPath) in previousPromptFiles where !keptNames.contains(name) {
            let managedURL = promptURL(for: name).standardized
            let resolvedURL = URL(fileURLWithPath: resolvePath(rawPath, relativeTo: homeURL)).standardized
            if resolvedURL == managedURL {
                try? FileManager.default.removeItem(at: managedURL)
            }
        }

        try GrokConfigRepository.shared.update { latest in
            rewrite(latest, roles: roles)
        }
    }

    /// Returns a map of role name → raw `prompt_file` value for every `[subagents.roles.*]` table.
    private static func parsePromptFilePaths(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentName: String?
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let header = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentName = header.hasPrefix("subagents.roles.")
                    ? unquote(String(header.dropFirst("subagents.roles.".count)))
                    : nil
                continue
            }
            guard let name = currentName, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard key == "prompt_file" else { continue }
            let rawValue = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            result[name] = unquote(rawValue)
        }
        return result
    }

    /// Drops all existing `[subagents.roles.*]` tables, then appends fresh ones, keeping every
    /// other section intact.
    static func rewrite(_ contents: String, roles: [SubagentRole]) -> String {
        var output: [String] = []
        var skipping = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                skipping = header.hasPrefix("subagents.roles.")
                if skipping { continue }
                output.append(rawLine)
                continue
            }
            if skipping { continue }
            output.append(rawLine)
        }

        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }

        var result = output.joined(separator: "\n")

        for role in roles {
            result += "\n\n[subagents.roles.\(role.name)]\n"
            if !role.description.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "description = \(quote(role.description))\n"
            }
            if !role.model.trimmingCharacters(in: .whitespaces).isEmpty {
                result += "model = \(quote(role.model))\n"
            }
            for key in role.extraFields.keys.sorted() {
                guard let rawValue = role.extraFields[key],
                      !Self.managedRoleFields.contains(key) else { continue }
                result += "\(key) = \(rawValue)\n"
            }
            result += "prompt_file = \(quote(promptURL(for: role.name).path))\n"
        }

        if !result.hasSuffix("\n") { result += "\n" }
        return result
    }

    // MARK: - TOML helpers

    private static let managedRoleFields: Set<String> = ["description", "model", "prompt_file"]

    private static func resolvePath(_ path: String, relativeTo baseURL: URL) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        if path.hasPrefix("/") {
            return path
        }
        return baseURL.appendingPathComponent(path).path
    }

    static func resolvedPromptPath(_ path: String) -> String {
        resolvePath(path, relativeTo: URL(fileURLWithPath: NSHomeDirectory()))
    }

    private static func stripComment(_ line: String) -> String {
        TOMLLineParsing.stripComment(line)
    }

    private static func unquote(_ value: String) -> String {
        TOMLLineParsing.unquote(value)
    }

    private static func quote(_ value: String) -> String {
        TOMLLineParsing.quote(value)
    }
}
