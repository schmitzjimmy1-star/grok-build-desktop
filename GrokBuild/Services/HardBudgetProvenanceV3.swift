import CryptoKit
import Foundation

/// Credential-free canonical policy and resolved-route provenance for the
/// dormant 4B.3 boundary. This file never reads configuration, resolves a
/// provider route, opens a credential, or starts a process. It only validates
/// a CLI-produced projection against the immutable authority supplied by a
/// later execution integration.
enum HardBudgetProvenanceV3 {
    static let campaignPolicySchemaVersion: UInt64 = 3
    static let provenanceSchemaVersion: UInt64 = 1
    static let serializerVersion: UInt64 = 1
    static let absoluteTokenCeiling: UInt64 = 20_000_000
    static let allocatableTokenCeiling: UInt64 = 19_000_000
    static let unreachableReserveTokens: UInt64 = 1_000_000

    enum ValidationError: Error, Equatable {
        case unsupportedPolicy
        case invalidPolicy
        case invalidProvenance
        case nonCanonicalJSON
        case digestMismatch
        case malformedJSON
    }

    struct CampaignPolicy: Equatable, Sendable {
        let schemaVersion: UInt64
        let absoluteTokenCeiling: UInt64
        let allocatableTokenCeiling: UInt64
        let unreachableReserveTokens: UInt64

        static let exact = CampaignPolicy(
            schemaVersion: campaignPolicySchemaVersion,
            absoluteTokenCeiling: HardBudgetProvenanceV3.absoluteTokenCeiling,
            allocatableTokenCeiling: HardBudgetProvenanceV3.allocatableTokenCeiling,
            unreachableReserveTokens: HardBudgetProvenanceV3.unreachableReserveTokens
        )

        func validate() throws {
            guard schemaVersion == campaignPolicySchemaVersion else {
                throw ValidationError.unsupportedPolicy
            }
            let (total, overflow) = allocatableTokenCeiling.addingReportingOverflow(unreachableReserveTokens)
            guard !overflow else { throw ValidationError.invalidPolicy }
            guard absoluteTokenCeiling == HardBudgetProvenanceV3.absoluteTokenCeiling,
                  allocatableTokenCeiling == HardBudgetProvenanceV3.allocatableTokenCeiling,
                  unreachableReserveTokens == HardBudgetProvenanceV3.unreachableReserveTokens,
                  total == absoluteTokenCeiling else {
                throw ValidationError.unsupportedPolicy
            }
        }

        func canonicalBytes() throws -> Data {
            try validate()
            return CanonicalJSON.data(object())
        }

        func sha256() throws -> String {
            try HardBudgetProvenanceV3.sha256(canonicalBytes())
        }

        fileprivate func object() -> [String: Any] {
            [
                "schemaVersion": schemaVersion,
                "absoluteTokenCeiling": absoluteTokenCeiling,
                "allocatableTokenCeiling": allocatableTokenCeiling,
                "unreachableReserveTokens": unreachableReserveTokens,
            ]
        }

        fileprivate static func parse(_ value: Any) throws -> CampaignPolicy {
            let object = try StrictJSON.object(value, keys: [
                "schemaVersion", "absoluteTokenCeiling", "allocatableTokenCeiling", "unreachableReserveTokens",
            ])
            let policy = CampaignPolicy(
                schemaVersion: try StrictJSON.uint64(object["schemaVersion"]),
                absoluteTokenCeiling: try StrictJSON.uint64(object["absoluteTokenCeiling"]),
                allocatableTokenCeiling: try StrictJSON.uint64(object["allocatableTokenCeiling"]),
                unreachableReserveTokens: try StrictJSON.uint64(object["unreachableReserveTokens"])
            )
            try policy.validate()
            return policy
        }
    }

    struct CandidateIdentity: Equatable, Sendable {
        let cliBuild: String
        let binarySHA256: String
        let sourceCommitSHA: String

        fileprivate func object() -> [String: Any] {
            ["cliBuild": cliBuild, "binarySha256": binarySHA256, "sourceCommitSha": sourceCommitSHA]
        }
    }

    struct ResolvedConfigIdentity: Equatable, Sendable {
        let sourceKind: String
        let generation: UInt64
        let managedProviderID: String
        let configProjectionSHA256: String

        fileprivate func object() -> [String: Any] {
            [
                "sourceKind": sourceKind,
                "generation": generation,
                "managedProviderId": managedProviderID,
                "configProjectionSha256": configProjectionSHA256,
            ]
        }
    }

    struct ToolIsolationContract: Equatable, Sendable {
        let authProviderHelpersDisabled: Bool
        let terminalDisabled: Bool
        let externalMCPDisabled: Bool
        let hooksDisabled: Bool
        let pluginsDisabled: Bool
        let lspDisabled: Bool
        let workflowsDisabled: Bool
        let schedulerDisabled: Bool
        let protectedAuthorityFS: Bool
        let workspaceFSConfined: Bool
        let samplerTransportRetriesDisabled: Bool
        let allowedToolIDs: [String]

        fileprivate func object() -> [String: Any] {
            [
                "authProviderHelpersDisabled": authProviderHelpersDisabled,
                "terminalDisabled": terminalDisabled,
                "externalMcpDisabled": externalMCPDisabled,
                "hooksDisabled": hooksDisabled,
                "pluginsDisabled": pluginsDisabled,
                "lspDisabled": lspDisabled,
                "workflowsDisabled": workflowsDisabled,
                "schedulerDisabled": schedulerDisabled,
                "protectedAuthorityFs": protectedAuthorityFS,
                "workspaceFsConfined": workspaceFSConfined,
                "samplerTransportRetriesDisabled": samplerTransportRetriesDisabled,
                "allowedToolIds": allowedToolIDs,
            ]
        }
    }

    struct ResolvedRouteBound: Equatable, Sendable {
        let routeID: String
        let providerID: String
        let providerFacingModel: String
        let endpointSHA256: String
        let apiBackend: String
        let credentialTransport: String
        let authScheme: String
        let maxFinalSerializedPayloadBytes: UInt64
        let maxOutputTokens: UInt64
        let conservativeRequestBoundTokens: UInt64
        let allocationTokenCeiling: UInt64
        let maxModelCalls: UInt64
        let textOnly: Bool
        let remoteContextForbidden: Bool
        let multimodalForbidden: Bool
        let redirectDisabled: Bool
        let retryDisabled: Bool
        let toolIsolation: ToolIsolationContract

        /// Header names are derived, never accepted as a mutable route field.
        var canonicalAuthHeaderNames: [String]? {
            HardBudgetProvenanceV3.canonicalAuthHeaderNames(authScheme)
        }

        fileprivate func object() -> [String: Any] {
            [
                "routeId": routeID,
                "providerId": providerID,
                "providerFacingModel": providerFacingModel,
                "endpointSha256": endpointSHA256,
                "apiBackend": apiBackend,
                "credentialTransport": credentialTransport,
                "authScheme": authScheme,
                "maxFinalSerializedPayloadBytes": maxFinalSerializedPayloadBytes,
                "maxOutputTokens": maxOutputTokens,
                "conservativeRequestBoundTokens": conservativeRequestBoundTokens,
                "allocationTokenCeiling": allocationTokenCeiling,
                "maxModelCalls": maxModelCalls,
                "textOnly": textOnly,
                "remoteContextForbidden": remoteContextForbidden,
                "multimodalForbidden": multimodalForbidden,
                "redirectDisabled": redirectDisabled,
                "retryDisabled": retryDisabled,
                "toolIsolation": toolIsolation.object(),
            ]
        }
    }

    struct Provenance: Equatable, Sendable {
        let schemaVersion: UInt64
        let serializerVersion: UInt64
        let campaignPolicy: CampaignPolicy
        let campaignID: String
        let allocationID: String
        let candidate: CandidateIdentity
        let configIdentity: ResolvedConfigIdentity
        let route: ResolvedRouteBound

        init(
            campaignID: String,
            allocationID: String,
            candidate: CandidateIdentity,
            configIdentity: ResolvedConfigIdentity,
            route: ResolvedRouteBound
        ) throws {
            self.init(
                schemaVersion: provenanceSchemaVersion,
                serializerVersion: HardBudgetProvenanceV3.serializerVersion,
                campaignPolicy: .exact,
                campaignID: campaignID,
                allocationID: allocationID,
                candidate: candidate,
                configIdentity: configIdentity,
                route: route
            )
            try validate()
        }

        private init(
            schemaVersion: UInt64,
            serializerVersion: UInt64,
            campaignPolicy: CampaignPolicy,
            campaignID: String,
            allocationID: String,
            candidate: CandidateIdentity,
            configIdentity: ResolvedConfigIdentity,
            route: ResolvedRouteBound
        ) {
            self.schemaVersion = schemaVersion
            self.serializerVersion = serializerVersion
            self.campaignPolicy = campaignPolicy
            self.campaignID = campaignID
            self.allocationID = allocationID
            self.candidate = candidate
            self.configIdentity = configIdentity
            self.route = route
        }

        func validate() throws {
            guard schemaVersion == provenanceSchemaVersion,
                  serializerVersion == HardBudgetProvenanceV3.serializerVersion else {
                throw ValidationError.invalidProvenance
            }
            try campaignPolicy.validate()
            try validateIdentifier(campaignID)
            try validateIdentifier(allocationID)
            try validateASCII(candidate.cliBuild, maximum: 256)
            try validateSHA256(candidate.binarySHA256)
            try validateCommitSHA(candidate.sourceCommitSHA)
            try validateASCII(configIdentity.sourceKind, maximum: 128)
            guard configIdentity.sourceKind == "resolved-managed-provider" else {
                throw ValidationError.invalidProvenance
            }
            guard configIdentity.generation > 0 else { throw ValidationError.invalidProvenance }
            try validateIdentifier(configIdentity.managedProviderID)
            guard configIdentity.managedProviderID == route.providerID else {
                throw ValidationError.invalidProvenance
            }
            try validateSHA256(configIdentity.configProjectionSHA256)
            try validateIdentifier(route.routeID)
            try validateIdentifier(route.providerID)
            try validateASCII(route.providerFacingModel, maximum: 256)
            try validateSHA256(route.endpointSHA256)
            guard ["chat_completions", "responses", "messages"].contains(route.apiBackend),
                  route.credentialTransport == "fd_v1",
                  route.maxFinalSerializedPayloadBytes > 0,
                  route.maxOutputTokens > 0,
                  route.maxModelCalls > 0,
                  route.allocationTokenCeiling > 0,
                  route.textOnly,
                  route.remoteContextForbidden,
                  route.multimodalForbidden,
                  route.redirectDisabled,
                  route.retryDisabled else {
                throw ValidationError.invalidProvenance
            }
            let (lowerBound, overflow) = route.maxFinalSerializedPayloadBytes.addingReportingOverflow(route.maxOutputTokens)
            guard !overflow,
                  lowerBound <= route.conservativeRequestBoundTokens,
                  route.conservativeRequestBoundTokens <= route.allocationTokenCeiling,
                  route.allocationTokenCeiling <= allocatableTokenCeiling else {
                throw ValidationError.invalidProvenance
            }
            guard route.canonicalAuthHeaderNames != nil else { throw ValidationError.invalidProvenance }
            try validateToolIsolation(route.toolIsolation)
        }

        func canonicalBytes() throws -> Data {
            try validate()
            return CanonicalJSON.data(object())
        }

        func sha256() throws -> String {
            try HardBudgetProvenanceV3.sha256(canonicalBytes())
        }

        func verifySHA256(_ expected: String) throws {
            try validateSHA256(expected)
            guard try sha256() == expected else { throw ValidationError.digestMismatch }
        }

        static func fromCanonicalJSON(_ data: Data) throws -> Provenance {
            guard !data.isEmpty, data.allSatisfy({ $0 < 0x80 }),
                  let object = try? JSONSerialization.jsonObject(with: data, options: []),
                  let provenance = try? parse(object) else {
                throw ValidationError.malformedJSON
            }
            guard try provenance.canonicalBytes() == data else { throw ValidationError.nonCanonicalJSON }
            return provenance
        }

        fileprivate func object() -> [String: Any] {
            [
                "schemaVersion": schemaVersion,
                "serializerVersion": serializerVersion,
                "campaignPolicy": campaignPolicy.object(),
                "campaignId": campaignID,
                "allocationId": allocationID,
                "candidate": candidate.object(),
                "configIdentity": configIdentity.object(),
                "route": route.object(),
            ]
        }

        fileprivate static func parse(_ value: Any) throws -> Provenance {
            let object = try StrictJSON.object(value, keys: [
                "schemaVersion", "serializerVersion", "campaignPolicy", "campaignId", "allocationId", "candidate", "configIdentity", "route",
            ])
            let candidate = try StrictJSON.object(object["candidate"], keys: ["cliBuild", "binarySha256", "sourceCommitSha"])
            let config = try StrictJSON.object(object["configIdentity"], keys: ["sourceKind", "generation", "managedProviderId", "configProjectionSha256"])
            let route = try StrictJSON.object(object["route"], keys: [
                "routeId", "providerId", "providerFacingModel", "endpointSha256", "apiBackend", "credentialTransport", "authScheme", "maxFinalSerializedPayloadBytes", "maxOutputTokens", "conservativeRequestBoundTokens", "allocationTokenCeiling", "maxModelCalls", "textOnly", "remoteContextForbidden", "multimodalForbidden", "redirectDisabled", "retryDisabled", "toolIsolation",
            ])
            let isolation = try StrictJSON.object(route["toolIsolation"], keys: [
                "authProviderHelpersDisabled", "terminalDisabled", "externalMcpDisabled", "hooksDisabled", "pluginsDisabled", "lspDisabled", "workflowsDisabled", "schedulerDisabled", "protectedAuthorityFs", "workspaceFsConfined", "samplerTransportRetriesDisabled", "allowedToolIds",
            ])
            let parsed = Provenance(
                schemaVersion: try StrictJSON.uint64(object["schemaVersion"]),
                serializerVersion: try StrictJSON.uint64(object["serializerVersion"]),
                campaignPolicy: try CampaignPolicy.parse(try StrictJSON.required(object["campaignPolicy"])),
                campaignID: try StrictJSON.string(object["campaignId"]),
                allocationID: try StrictJSON.string(object["allocationId"]),
                candidate: CandidateIdentity(
                    cliBuild: try StrictJSON.string(candidate["cliBuild"]),
                    binarySHA256: try StrictJSON.string(candidate["binarySha256"]),
                    sourceCommitSHA: try StrictJSON.string(candidate["sourceCommitSha"])
                ),
                configIdentity: ResolvedConfigIdentity(
                    sourceKind: try StrictJSON.string(config["sourceKind"]),
                    generation: try StrictJSON.uint64(config["generation"]),
                    managedProviderID: try StrictJSON.string(config["managedProviderId"]),
                    configProjectionSHA256: try StrictJSON.string(config["configProjectionSha256"])
                ),
                route: ResolvedRouteBound(
                    routeID: try StrictJSON.string(route["routeId"]),
                    providerID: try StrictJSON.string(route["providerId"]),
                    providerFacingModel: try StrictJSON.string(route["providerFacingModel"]),
                    endpointSHA256: try StrictJSON.string(route["endpointSha256"]),
                    apiBackend: try StrictJSON.string(route["apiBackend"]),
                    credentialTransport: try StrictJSON.string(route["credentialTransport"]),
                    authScheme: try StrictJSON.string(route["authScheme"]),
                    maxFinalSerializedPayloadBytes: try StrictJSON.uint64(route["maxFinalSerializedPayloadBytes"]),
                    maxOutputTokens: try StrictJSON.uint64(route["maxOutputTokens"]),
                    conservativeRequestBoundTokens: try StrictJSON.uint64(route["conservativeRequestBoundTokens"]),
                    allocationTokenCeiling: try StrictJSON.uint64(route["allocationTokenCeiling"]),
                    maxModelCalls: try StrictJSON.uint64(route["maxModelCalls"]),
                    textOnly: try StrictJSON.bool(route["textOnly"]),
                    remoteContextForbidden: try StrictJSON.bool(route["remoteContextForbidden"]),
                    multimodalForbidden: try StrictJSON.bool(route["multimodalForbidden"]),
                    redirectDisabled: try StrictJSON.bool(route["redirectDisabled"]),
                    retryDisabled: try StrictJSON.bool(route["retryDisabled"]),
                    toolIsolation: ToolIsolationContract(
                        authProviderHelpersDisabled: try StrictJSON.bool(isolation["authProviderHelpersDisabled"]),
                        terminalDisabled: try StrictJSON.bool(isolation["terminalDisabled"]),
                        externalMCPDisabled: try StrictJSON.bool(isolation["externalMcpDisabled"]),
                        hooksDisabled: try StrictJSON.bool(isolation["hooksDisabled"]),
                        pluginsDisabled: try StrictJSON.bool(isolation["pluginsDisabled"]),
                        lspDisabled: try StrictJSON.bool(isolation["lspDisabled"]),
                        workflowsDisabled: try StrictJSON.bool(isolation["workflowsDisabled"]),
                        schedulerDisabled: try StrictJSON.bool(isolation["schedulerDisabled"]),
                        protectedAuthorityFS: try StrictJSON.bool(isolation["protectedAuthorityFs"]),
                        workspaceFSConfined: try StrictJSON.bool(isolation["workspaceFsConfined"]),
                        samplerTransportRetriesDisabled: try StrictJSON.bool(isolation["samplerTransportRetriesDisabled"]),
                        allowedToolIDs: try StrictJSON.stringArray(isolation["allowedToolIds"])
                    )
                )
            )
            try parsed.validate()
            return parsed
        }
    }

    /// This is the only pre-Keychain comparison set. It intentionally has no
    /// configuration identity or provenance digest: those must be constructed
    /// by the one candidate process from the live resolved configuration.
    struct ExecutionExpectation: Equatable, Sendable {
        let campaignID: String
        let allocationID: String
        let candidate: CandidateIdentity
        let route: ResolvedRouteBound

        func matches(_ provenance: Provenance) -> Bool {
            provenance.campaignPolicy == .exact
                && provenance.campaignID == campaignID
                && provenance.allocationID == allocationID
                && provenance.candidate == candidate
                && provenance.route == route
        }
    }

    /// This parser is deliberately unreferenced by execution. The CLI capability
    /// is a broad operational object plus a strict nested `v3Authority`. Swift
    /// re-canonicalizes the typed provenance and derives auth headers from the
    /// scheme. Historical v2 `isEnforcing` stays untouched.
    struct ExecutionCapability: Equatable, Sendable {
        static let version: UInt64 = 3
        static let authorityVersion: UInt64 = 3

        let provenance: Provenance

        var authHeaderNames: [String] {
            provenance.route.canonicalAuthHeaderNames ?? []
        }

        static func parse(
            _ value: Any?,
            expectation: ExecutionExpectation
        ) -> ExecutionCapability? {
            guard let object = value as? [String: Any],
                  (try? StrictJSON.uint64(object["capabilityVersion"])) == version,
                  let authority = try? StrictJSON.object(object["v3Authority"], keys: [
                    "authorityVersion", "provenance", "provenanceSha256",
                  ]),
                  (try? StrictJSON.uint64(authority["authorityVersion"])) == authorityVersion,
                  let provenance = try? Provenance.parse(try StrictJSON.required(authority["provenance"])),
                  let digest = try? StrictJSON.string(authority["provenanceSha256"]),
                  expectation.matches(provenance),
                  (try? provenance.verifySHA256(digest)) != nil,
                  provenance.configIdentity.sourceKind == "resolved-managed-provider",
                  provenance.configIdentity.managedProviderID == provenance.route.providerID,
                  provenance.route.canonicalAuthHeaderNames != nil else {
                return nil
            }
            return ExecutionCapability(provenance: provenance)
        }

        /// Nested `v3Authority` plus digest check only. Dispatch compares the
        /// Swift-observable subset; it does not invent a live `ResolvedRouteBound`.
        static func parseInitializeProvenance(_ value: Any?) -> Provenance? {
            guard let object = value as? [String: Any],
                  (try? StrictJSON.uint64(object["capabilityVersion"])) == version,
                  let authority = try? StrictJSON.object(object["v3Authority"], keys: [
                    "authorityVersion", "provenance", "provenanceSha256",
                  ]),
                  (try? StrictJSON.uint64(authority["authorityVersion"])) == authorityVersion,
                  let provenance = try? Provenance.parse(try StrictJSON.required(authority["provenance"])),
                  let digest = try? StrictJSON.string(authority["provenanceSha256"]),
                  (try? provenance.verifySHA256(digest)) != nil,
                  provenance.configIdentity.sourceKind == "resolved-managed-provider",
                  provenance.configIdentity.managedProviderID == provenance.route.providerID,
                  provenance.route.canonicalAuthHeaderNames != nil else {
                return nil
            }
            return provenance
        }
    }

    static func canonicalAuthHeaderNames(_ scheme: String) -> [String]? {
        switch scheme {
        case "bearer": return ["authorization"]
        case "x_api_key": return ["x-api-key"]
        case "bearer_and_x_api_key": return ["authorization", "x-api-key"]
        default: return nil
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validateIdentifier(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= 128,
              value.utf8.allSatisfy({ isIdentifierByte($0) }) else {
            throw ValidationError.invalidProvenance
        }
    }

    private static func validateASCII(_ value: String, maximum: Int) throws {
        guard !value.isEmpty, value.utf8.count <= maximum,
              value.utf8.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }) else {
            throw ValidationError.invalidProvenance
        }
    }

    private static func validateCommitSHA(_ value: String) throws {
        guard value.utf8.count == 40,
              value.utf8.allSatisfy({ isLowerHexByte($0) }) else {
            throw ValidationError.invalidProvenance
        }
    }

    private static func validateSHA256(_ value: String) throws {
        guard value.utf8.count == 64,
              value.utf8.allSatisfy({ isLowerHexByte($0) }) else {
            throw ValidationError.invalidProvenance
        }
    }

    private static func validateToolIsolation(_ value: ToolIsolationContract) throws {
        guard value.authProviderHelpersDisabled,
              value.terminalDisabled,
              value.externalMCPDisabled,
              value.hooksDisabled,
              value.pluginsDisabled,
              value.lspDisabled,
              value.workflowsDisabled,
              value.schedulerDisabled,
              value.protectedAuthorityFS,
              value.workspaceFSConfined,
              value.samplerTransportRetriesDisabled,
              !value.allowedToolIDs.isEmpty,
              value.allowedToolIDs == value.allowedToolIDs.sorted(),
              Set(value.allowedToolIDs).count == value.allowedToolIDs.count,
              value.allowedToolIDs.allSatisfy({ id in
                  id.utf8.count > "GrokBuild:".utf8.count
                      && id.utf8.count <= 256
                      && id.hasPrefix("GrokBuild:")
                      && id.utf8.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e })
              }) else {
            throw ValidationError.invalidProvenance
        }
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57)
            || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || byte == 45 || byte == 95 || byte == 46
    }

    private static func isLowerHexByte(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
    }
}

private enum StrictJSON {
    static func required(_ value: Any?) throws -> Any {
        guard let value else { throw HardBudgetProvenanceV3.ValidationError.malformedJSON }
        return value
    }

    static func object(_ value: Any?, keys: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any], Set(object.keys) == keys else {
            throw HardBudgetProvenanceV3.ValidationError.malformedJSON
        }
        return object
    }

    static func string(_ value: Any?) throws -> String {
        guard let value = value as? String else { throw HardBudgetProvenanceV3.ValidationError.malformedJSON }
        return value
    }

    static func bool(_ value: Any?) throws -> Bool {
        guard let value = value as? Bool else { throw HardBudgetProvenanceV3.ValidationError.malformedJSON }
        return value
    }

    static func uint64(_ value: Any?) throws -> UInt64 {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.stringValue.range(of: "^[0-9]+$", options: .regularExpression) != nil,
              let result = UInt64(number.stringValue) else {
            throw HardBudgetProvenanceV3.ValidationError.malformedJSON
        }
        return result
    }

    static func stringArray(_ value: Any?) throws -> [String] {
        guard let values = value as? [Any] else { throw HardBudgetProvenanceV3.ValidationError.malformedJSON }
        return try values.map(string)
    }
}

private enum CanonicalJSON {
    static func data(_ value: Any) -> Data {
        Data(write(value).utf8)
    }

    private static func write(_ value: Any) -> String {
        if let value = value as? Bool { return value ? "true" : "false" }
        if let value = value as? UInt64 { return String(value) }
        if let value = value as? String { return quoted(value) }
        if let values = value as? [String] { return "[" + values.map { quoted($0) }.joined(separator: ",") + "]" }
        if let values = value as? [Any] { return "[" + values.map(write).joined(separator: ",") + "]" }
        if let object = value as? [String: Any] {
            return "{" + object.keys.sorted().map { quoted($0) + ":" + write(object[$0]!) }.joined(separator: ",") + "}"
        }
        preconditionFailure("unsupported canonical JSON value")
    }

    private static func quoted(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: output += "\\\""
            case 0x5c: output += "\\\\"
            case 0x08: output += "\\b"
            case 0x0c: output += "\\f"
            case 0x0a: output += "\\n"
            case 0x0d: output += "\\r"
            case 0x09: output += "\\t"
            case 0..<0x20: output += String(format: "\\u%04x", scalar.value)
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}
