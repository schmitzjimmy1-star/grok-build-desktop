import Foundation
import Security

/// Non-secret authority for the future armed credential path. This shape is
/// intentionally unavailable to schema-2 acceptance packets: the value names
/// the one Keychain account that may be selected, but never contains a
/// credential, persistent reference, or a secret-derived fingerprint.
/// `expectedProvenanceSHA256` is the digest Swift expects the CLI-produced
/// canonical document to match. It is not live route/config provenance.
struct GrokArmedCredentialAuthorizationV3: Sendable, Equatable {
    static let schemaVersion = 3

    let schemaVersion: Int
    let managedProviderID: String
    let authScheme: String
    let expectedProvenanceSHA256: String

    var keychainAccount: String { managedProviderID }

    var authHeaderNames: [String] {
        HardBudgetProvenanceV3.canonicalAuthHeaderNames(authScheme) ?? []
    }

    /// No current packet parser constructs this foundation shape. A later
    /// canonical v3 producer must bind each non-secret field to the candidate's
    /// actual resolved provider route before this becomes reachable in product.
    init?(
        schemaVersion: Int = Self.schemaVersion,
        managedProviderID: String,
        authScheme: String,
        expectedProvenanceSHA256: String
    ) {
        let provider = managedProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = authScheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard schemaVersion == Self.schemaVersion,
              !provider.isEmpty,
              provider.utf8.count <= 255,
              !provider.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              HardBudgetProvenanceV3.canonicalAuthHeaderNames(scheme) != nil,
              expectedProvenanceSHA256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            return nil
        }
        self.schemaVersion = schemaVersion
        self.managedProviderID = provider
        self.authScheme = scheme
        self.expectedProvenanceSHA256 = expectedProvenanceSHA256
    }

    /// Cross-binds the authorization to an independently verified provenance
    /// document. Keychain success later proves only that local bytes exist.
    init?(
        provenance: HardBudgetProvenanceV3.Provenance,
        expectedProvenanceSHA256: String
    ) {
        guard provenance.configIdentity.sourceKind == "resolved-managed-provider",
              provenance.configIdentity.managedProviderID == provenance.route.providerID,
              (try? provenance.verifySHA256(expectedProvenanceSHA256)) != nil else {
            return nil
        }
        self.init(
            managedProviderID: provenance.route.providerID,
            authScheme: provenance.route.authScheme,
            expectedProvenanceSHA256: expectedProvenanceSHA256
        )
    }
}

/// A narrow injection seam. Production uses `SecItemCopyMatching`; tests may
/// inspect the query without reading a real Keychain item.
struct GrokArmedCredentialKeychainClient: @unchecked Sendable {
    typealias CopyMatching = (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus

    let copyMatching: CopyMatching

    static let live = Self(copyMatching: SecItemCopyMatching)
}

/// Pure launch admission used before any ordinary tool installer, browser
/// startup, or MCP catalog helper. Keeping it pure makes the no-detour rule
/// testable without touching settings, the Keychain, or a candidate process.
enum GrokArmedCredentialLaunchPreflight {
    static func refusalMessage(
        authorization: GrokArmedCredentialAuthorizationV3?,
        browserEnabled: Bool,
        computerUseEnabled: Bool,
        requestedMCPServerNames: Set<String>,
        authBoundary: ModelRouteContract.AuthBoundary
    ) -> String? {
        guard authorization != nil else { return nil }
        guard !browserEnabled,
              !computerUseEnabled,
              requestedMCPServerNames.isEmpty,
              authBoundary == .officialHelper else {
            return "Armed credential launch refuses Browser, Computer Use, MCP, and non-managed-provider detours."
        }
        return nil
    }
}

/// Dedicated materialization boundary for a future v3 armed packet. Production
/// `GrokProcess.start` must not call this. Do not use
/// `KeychainProviderCredentialStore`: it converts secret data into a String and
/// accepts the normal settings/auth-helper path, neither of which is valid here.
struct GrokArmedCredentialMaterializer: Sendable {
    static let keychainService = "com.grokbuild.provider-credential"
    static let maximumByteCount = 4_096

    enum MaterializationError: Error, Equatable {
        case itemNotFound
        case keychainReadFailed
        case multipleCredentials
        case invalidCredential
        case credentialTooLarge
    }

    let keychain: GrokArmedCredentialKeychainClient

    init(keychain: GrokArmedCredentialKeychainClient = .live) {
        self.keychain = keychain
    }

    func materialize(
        authorization: GrokArmedCredentialAuthorizationV3
    ) throws -> GrokArmedCredentialTransfer {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: authorization.keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var item: CFTypeRef?
        let status = keychain.copyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw MaterializationError.itemNotFound }
        guard status == errSecSuccess else { throw MaterializationError.keychainReadFailed }
        guard let matches = item as? [Data] else { throw MaterializationError.invalidCredential }
        guard matches.count == 1 else { throw MaterializationError.multipleCredentials }
        let bytes = [UInt8](matches[0])
        guard !bytes.isEmpty else { throw MaterializationError.invalidCredential }
        guard bytes.count <= Self.maximumByteCount else { throw MaterializationError.credentialTooLarge }
        return GrokArmedCredentialTransfer(bytes: bytes)
    }
}
