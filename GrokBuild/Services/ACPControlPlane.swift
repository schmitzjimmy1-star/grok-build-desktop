import Foundation

/// Semantic version reported by the exact `grok agent stdio` process in
/// `initialize._meta.agentVersion`. Prerelease/build suffixes do not change the
/// feature floor: `1.0.5-alpha.2` is still a 1.0.5-family wire implementation.
struct ACPAgentVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let rawValue: String

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionToken = trimmed.split { character in
            !(character.isNumber || character == ".")
        }.first { token in
            token.split(separator: ".").count >= 3
        }
        guard let components = versionToken?.split(separator: "."),
              components.count >= 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.rawValue = trimmed
    }

    static func < (lhs: ACPAgentVersion, rhs: ACPAgentVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { rawValue }
}

enum ACPControlMethod: String, CaseIterable, Sendable {
    case models = "x.ai/models/list"
    case sessionUsage = "x.ai/session/usage"
    case sessionInfo = "x.ai/session/info"
    case sessionUpdates = "x.ai/session/updates"

    /// Method-specific floors pinned to official source. `x.ai/models/list` is
    /// already the implementation behind `grok models` in 1.0.4; the persisted
    /// session controls remain gated to the audited 1.0.5 family.
    var officialExtensionFloor: ACPAgentVersion {
        switch self {
        case .models:
            ACPAgentVersion("1.0.4")!
        case .sessionUsage, .sessionInfo, .sessionUpdates:
            ACPAgentVersion("1.0.5")!
        }
    }
}

enum ACPControlCapabilityState: Sendable, Equatable {
    case unknown
    case supported
    case unsupported
}

/// Per-process-generation capability cache. xAI extension methods are not
/// advertised in standard ACP capabilities, so the exact agent version prevents
/// missing/known-old calls and one real response/method-not-found probe settles
/// each method for the rest of that process generation.
final class ACPControlCapabilityRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64?
    private var agentVersion: ACPAgentVersion?
    private var states: [ACPControlMethod: ACPControlCapabilityState] = [:]

    func reset(generation: UInt64, agentVersion: ACPAgentVersion?) {
        lock.lock()
        self.generation = generation
        self.agentVersion = agentVersion
        states.removeAll()
        lock.unlock()
    }

    func shouldAttempt(_ method: ACPControlMethod, generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.generation == generation else { return false }
        if states[method] == .unsupported { return false }
        guard let agentVersion else {
            states[method] = .unsupported
            return false
        }
        if agentVersion < method.officialExtensionFloor {
            states[method] = .unsupported
            return false
        }
        return true
    }

    func record(_ state: ACPControlCapabilityState, for method: ACPControlMethod, generation: UInt64) {
        lock.lock()
        if self.generation == generation {
            states[method] = state
        }
        lock.unlock()
    }

    func state(for method: ACPControlMethod, generation: UInt64) -> ACPControlCapabilityState {
        lock.lock()
        defer { lock.unlock() }
        guard self.generation == generation else { return .unsupported }
        if let state = states[method] { return state }
        guard let agentVersion else { return .unsupported }
        if agentVersion < method.officialExtensionFloor {
            return .unsupported
        }
        return .unknown
    }
}

enum ACPControlError: LocalizedError, Equatable {
    case unavailable(method: ACPControlMethod, agentVersion: String?)
    case noActiveConnection
    case staleConnection
    case invalidRequest(String)
    case invalidResponse(method: ACPControlMethod, reason: String)
    case invalidStandardResponse(method: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let method, let version):
            let suffix = version.map { " for grok \($0)" } ?? ""
            return "\(method.rawValue) is unavailable\(suffix)."
        case .noActiveConnection:
            return "No active Grok ACP connection."
        case .staleConnection:
            return "The Grok ACP connection changed while the control request was running."
        case .invalidRequest(let reason):
            return "Invalid ACP control request: \(reason)"
        case .invalidResponse(let method, let reason):
            return "Invalid \(method.rawValue) response: \(reason)"
        case .invalidStandardResponse(let method, let reason):
            return "Invalid \(method) response: \(reason)"
        }
    }
}

/// Credential-safe JSON used only where the official update envelope deliberately
/// carries extensible payloads. Public control-plane models remain typed; callers
/// must opt back into Foundation objects at the existing ACP parsing boundary.
enum ACPJSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([ACPJSONValue])
    case object([String: ACPJSONValue])

    init?(foundation value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if value.doubleValue.rounded(.towardZero) == value.doubleValue,
                      let integer = Int(exactly: value.int64Value) {
                self = .integer(integer)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            var result: [ACPJSONValue] = []
            result.reserveCapacity(value.count)
            for item in value {
                guard let converted = ACPJSONValue(foundation: item) else { return nil }
                result.append(converted)
            }
            self = .array(result)
        case let value as [String: Any]:
            var result: [String: ACPJSONValue] = [:]
            result.reserveCapacity(value.count)
            for (key, item) in value {
                guard let converted = ACPJSONValue(foundation: item) else { return nil }
                result[key] = converted
            }
            self = .object(result)
        default:
            return nil
        }
    }

    var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .integer(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.foundationObject)
        case .object(let values): values.mapValues(\.foundationObject)
        }
    }

    var objectValue: [String: ACPJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

struct ACPControlModel: Sendable, Equatable {
    let id: String
    let name: String
    let contextTokens: Int?
}

struct ACPControlModelCatalog: Sendable, Equatable {
    let currentModelID: String?
    let availableModels: [ACPControlModel]

    static func parse(_ value: Any?) throws -> ACPControlModelCatalog {
        let payload = try ACPControlParsing.extensionPayload(value, method: .models)
        guard let object = payload as? [String: Any] else {
            throw ACPControlError.invalidResponse(method: .models, reason: "expected an object")
        }
        guard let rawModels = object["availableModels"] as? [Any] else {
            throw ACPControlError.invalidResponse(method: .models, reason: "missing availableModels array")
        }
        var models: [ACPControlModel] = []
        models.reserveCapacity(rawModels.count)
        for rawModel in rawModels {
            guard let item = rawModel as? [String: Any],
                  let id = ACPControlParsing.nonemptyString(item["modelId"]) else {
                throw ACPControlError.invalidResponse(method: .models, reason: "malformed model entry")
            }
            let metadata = item["_meta"] as? [String: Any]
            models.append(ACPControlModel(
                id: id,
                name: ACPControlParsing.nonemptyString(item["name"]) ?? id,
                contextTokens: ACPControlParsing.integer(metadata?["totalContextTokens"])
            ))
        }
        return ACPControlModelCatalog(
            currentModelID: ACPControlParsing.nonemptyString(object["currentModelId"]),
            availableModels: models
        )
    }
}

struct ACPControlModelUsage: Sendable, Equatable {
    let modelID: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cachedReadTokens: Int?
    let cacheCreationTokens: Int?
    let reasoningTokens: Int?
    let modelCalls: Int?
    let apiDurationMilliseconds: Int?
    let costUsdTicks: Int?
}

struct ACPControlSessionUsage: Sendable, Equatable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cachedReadTokens: Int?
    let cacheCreationTokens: Int?
    let reasoningTokens: Int?
    let modelCalls: Int?
    let apiDurationMilliseconds: Int?
    let costUsdTicks: Int?
    let costIsPartial: Bool?
    let turnCount: Int?
    let modelUsage: [ACPControlModelUsage]

    static func parse(_ value: Any?) throws -> ACPControlSessionUsage {
        guard let object = value as? [String: Any],
              let usage = object["usage"] as? [String: Any] else {
            throw ACPControlError.invalidResponse(method: .sessionUsage, reason: "missing usage object")
        }
        let rawModelUsage: [String: Any]
        if let raw = usage["modelUsage"] {
            guard let decoded = raw as? [String: Any] else {
                throw ACPControlError.invalidResponse(method: .sessionUsage, reason: "malformed modelUsage object")
            }
            rawModelUsage = decoded
        } else {
            rawModelUsage = [:]
        }
        var models: [ACPControlModelUsage] = []
        models.reserveCapacity(rawModelUsage.count)
        for (modelID, raw) in rawModelUsage {
            guard let item = raw as? [String: Any],
                  let normalized = ACPControlParsing.nonemptyString(modelID) else {
                throw ACPControlError.invalidResponse(method: .sessionUsage, reason: "malformed modelUsage entry")
            }
            models.append(ACPControlModelUsage(
                modelID: normalized,
                inputTokens: ACPControlParsing.integer(item["inputTokens"]),
                outputTokens: ACPControlParsing.integer(item["outputTokens"]),
                totalTokens: ACPControlParsing.integer(item["totalTokens"]),
                cachedReadTokens: ACPControlParsing.integer(item["cachedReadTokens"]),
                cacheCreationTokens: ACPControlParsing.integer(item["cacheCreationTokens"]),
                reasoningTokens: ACPControlParsing.integer(item["reasoningTokens"]),
                modelCalls: ACPControlParsing.integer(item["modelCalls"]),
                apiDurationMilliseconds: ACPControlParsing.integer(item["apiDurationMs"]),
                costUsdTicks: ACPControlParsing.integer(item["costUsdTicks"])
            ))
        }
        models.sort { $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending }
        return ACPControlSessionUsage(
            inputTokens: ACPControlParsing.integer(usage["inputTokens"]),
            outputTokens: ACPControlParsing.integer(usage["outputTokens"]),
            totalTokens: ACPControlParsing.integer(usage["totalTokens"]),
            cachedReadTokens: ACPControlParsing.integer(usage["cachedReadTokens"]),
            cacheCreationTokens: ACPControlParsing.integer(usage["cacheCreationTokens"]),
            reasoningTokens: ACPControlParsing.integer(usage["reasoningTokens"]),
            modelCalls: ACPControlParsing.integer(usage["modelCalls"]),
            apiDurationMilliseconds: ACPControlParsing.integer(usage["apiDurationMs"]),
            costUsdTicks: ACPControlParsing.integer(usage["costUsdTicks"]),
            costIsPartial: usage["costIsPartial"] as? Bool,
            turnCount: ACPControlParsing.integer(usage["numTurns"]),
            modelUsage: models
        )
    }
}

struct ACPControlSessionMetadata: Sendable, Equatable {
    let sessionID: String
    let cwd: String
    let agentName: String?
    let modelID: String?
    let modelDisplayName: String?
    let resolvedModelID: String?
    let modelFingerprint: String?
    let apiBackend: String?
    let conversationID: String?
    let turns: Int?
    let turnIndex: Int?
    let contextUsedTokens: Int?
    let contextTotalTokens: Int?
    let contextUsagePercent: Int?

    static func parse(_ value: Any?) throws -> ACPControlSessionMetadata {
        let payload = try ACPControlParsing.extensionPayload(value, method: .sessionInfo)
        guard let object = payload as? [String: Any],
              let sessionID = ACPControlParsing.nonemptyString(object["sessionId"]),
              let cwd = ACPControlParsing.nonemptyString(object["cwd"]) else {
            throw ACPControlError.invalidResponse(method: .sessionInfo, reason: "missing sessionId or cwd")
        }
        let context = object["context"] as? [String: Any]
        return ACPControlSessionMetadata(
            sessionID: sessionID,
            cwd: cwd,
            agentName: ACPControlParsing.nonemptyString(object["agentName"]),
            modelID: ACPControlParsing.nonemptyString(object["model"]),
            modelDisplayName: ACPControlParsing.nonemptyString(object["modelDisplayName"]),
            resolvedModelID: ACPControlParsing.nonemptyString(object["resolvedModelId"]),
            modelFingerprint: ACPControlParsing.nonemptyString(object["modelFingerprint"]),
            apiBackend: ACPControlParsing.nonemptyString(object["apiBackend"]),
            conversationID: ACPControlParsing.nonemptyString(object["conversationId"]),
            turns: ACPControlParsing.integer(object["turns"]),
            turnIndex: ACPControlParsing.integer(object["turnIndex"]),
            contextUsedTokens: ACPControlParsing.integer(context?["used"]),
            contextTotalTokens: ACPControlParsing.integer(context?["total"]),
            contextUsagePercent: ACPControlParsing.integer(context?["usagePct"])
        )
    }
}

struct ACPStandardSessionListEntry: Sendable, Equatable {
    let sessionID: String
    let cwd: String?
    let title: String?
    let modelID: String?
    let updatedAt: Date?
}

struct ACPStandardSessionListPage: Sendable, Equatable {
    let sessions: [ACPStandardSessionListEntry]
    let nextCursor: String?

    static func parse(_ value: Any?) throws -> ACPStandardSessionListPage {
        guard let object = value as? [String: Any],
              let rawSessions = object["sessions"] as? [Any] else {
            throw ACPControlError.invalidStandardResponse(
                method: "session/list",
                reason: "missing sessions array"
            )
        }
        var sessions: [ACPStandardSessionListEntry] = []
        sessions.reserveCapacity(rawSessions.count)
        for raw in rawSessions {
            guard let item = raw as? [String: Any],
                  let sessionID = ACPControlParsing.nonemptyString(item["sessionId"])
                    ?? ACPControlParsing.nonemptyString(item["session_id"])
                    ?? ACPControlParsing.nonemptyString(item["id"]) else {
                throw ACPControlError.invalidStandardResponse(
                    method: "session/list",
                    reason: "malformed session entry"
                )
            }
            let metadata = item["_meta"] as? [String: Any]
            let updatedText = ACPControlParsing.nonemptyString(item["updatedAt"])
                ?? ACPControlParsing.nonemptyString(item["updated_at"])
                ?? ACPControlParsing.nonemptyString(metadata?["updatedAt"])
            sessions.append(ACPStandardSessionListEntry(
                sessionID: sessionID,
                cwd: ACPControlParsing.nonemptyString(item["cwd"]),
                title: ACPControlParsing.nonemptyString(item["title"])
                    ?? ACPControlParsing.nonemptyString(item["name"]),
                modelID: ACPControlParsing.nonemptyString(item["modelId"])
                    ?? ACPControlParsing.nonemptyString(metadata?["modelId"]),
                updatedAt: updatedText.flatMap(ACPControlParsing.date)
            ))
        }
        return ACPStandardSessionListPage(
            sessions: sessions,
            nextCursor: ACPControlParsing.nonemptyString(object["nextCursor"])
                ?? ACPControlParsing.nonemptyString(object["next_cursor"])
        )
    }
}

struct ACPStoredUpdateEnvelope: Sendable, Equatable {
    let timestamp: Double?
    let method: String
    let sessionID: String?
    let update: ACPJSONValue?
    let metadata: ACPJSONValue?

    init?(foundation value: Any) {
        guard let object = value as? [String: Any],
              let method = ACPControlParsing.nonemptyString(object["method"]),
              let params = object["params"] as? [String: Any] else { return nil }
        self.timestamp = (object["timestamp"] as? NSNumber)?.doubleValue
        self.method = method
        sessionID = ACPControlParsing.nonemptyString(params["sessionId"])
            ?? ACPControlParsing.nonemptyString(params["session_id"])
        update = params["update"].flatMap { ACPJSONValue(foundation: $0) }
        metadata = params["_meta"].flatMap { ACPJSONValue(foundation: $0) }
    }

    var foundationUpdate: [String: Any]? {
        update?.objectValue?.mapValues(\.foundationObject)
    }
}

struct ACPControlSessionUpdatePage: Sendable, Equatable {
    static let maximumLimit = 512

    let updates: [ACPStoredUpdateEnvelope]
    let totalCount: Int
    let hasMore: Bool
    let lastEventID: String?
    let promptStarts: [Int]

    static func parse(_ value: Any?) throws -> ACPControlSessionUpdatePage {
        guard let object = value as? [String: Any],
              let rawUpdates = object["updates"] as? [Any],
              let totalCount = ACPControlParsing.integer(object["totalCount"]),
              let hasMore = object["hasMore"] as? Bool else {
            throw ACPControlError.invalidResponse(method: .sessionUpdates, reason: "missing bounded page fields")
        }
        guard rawUpdates.count <= maximumLimit else {
            throw ACPControlError.invalidResponse(method: .sessionUpdates, reason: "page exceeded 512 updates")
        }
        var updates: [ACPStoredUpdateEnvelope] = []
        updates.reserveCapacity(rawUpdates.count)
        for raw in rawUpdates {
            guard let envelope = ACPStoredUpdateEnvelope(foundation: raw) else {
                throw ACPControlError.invalidResponse(method: .sessionUpdates, reason: "malformed update envelope")
            }
            updates.append(envelope)
        }
        return ACPControlSessionUpdatePage(
            updates: updates,
            totalCount: max(0, totalCount),
            hasMore: hasMore,
            lastEventID: ACPControlParsing.nonemptyString(object["lastEventId"]),
            promptStarts: (object["promptStarts"] as? [Any] ?? []).compactMap(ACPControlParsing.integer)
        )
    }
}

enum ACPControlParsing {
    private static let internetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateFormatterWithoutFractions = ISO8601DateFormatter()

    static func extensionPayload(_ value: Any?, method: ACPControlMethod) throws -> Any {
        guard let object = value as? [String: Any] else {
            throw ACPControlError.invalidResponse(method: method, reason: "expected an extension result object")
        }
        if object.keys.contains("result") {
            if let error = object["error"], !(error is NSNull) {
                throw ACPControlError.invalidResponse(method: method, reason: "extension returned \(error)")
            }
            guard let result = object["result"], !(result is NSNull) else {
                throw ACPControlError.invalidResponse(method: method, reason: "extension result was null")
            }
            return result
        }
        return object
    }

    static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func date(_ value: String) -> Date? {
        internetDateFormatter.date(from: value)
            ?? internetDateFormatterWithoutFractions.date(from: value)
    }

    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(number.stringValue)
    }
}
