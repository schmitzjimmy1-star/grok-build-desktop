import Foundation
import Security

enum ProviderAuthScheme: String, Codable, CaseIterable, Sendable {
    case bearer
    case apiKeyHeader = "api-key"
    case bearerAndAPIKey = "bearer-and-api-key"
    case none
}

/// Non-secret provenance for a provider credential. The credential value itself is kept in
/// Keychain; this metadata is safe to persist in UserDefaults and copy into diagnostics.
enum ProviderCredentialKind: String, Codable, CaseIterable, Sendable {
    case none
    case apiKey = "api-key"
    case oauthIssuedKey = "oauth-issued-key"
}

struct ProviderCredentialMetadata: Codable, Hashable, Sendable {
    var kind: ProviderCredentialKind
    var issuer: String? = nil
    var connectedAt: Date? = nil
    var updatedAt: Date? = nil
    var lastValidatedAt: Date? = nil

    static let none = ProviderCredentialMetadata(kind: .none)

    static func apiKey(at date: Date = Date()) -> ProviderCredentialMetadata {
        ProviderCredentialMetadata(kind: .apiKey, connectedAt: date, updatedAt: date)
    }

    static func openRouterOAuth(at date: Date = Date()) -> ProviderCredentialMetadata {
        ProviderCredentialMetadata(
            kind: .oauthIssuedKey,
            issuer: "https://openrouter.ai",
            connectedAt: date,
            updatedAt: date
        )
    }

    /// Used only when adopting a pre-Slice-12 Keychain entry. Nil dates avoid inventing a
    /// historical connection time and make the migration stable across every subsequent load.
    static let migratedAPIKey = ProviderCredentialMetadata(kind: .apiKey)
}

protocol ProviderCredentialStoring: Sendable {
    func credential(for providerID: String) throws -> String?
    func setCredential(_ credential: String, for providerID: String) throws
    func removeCredential(for providerID: String) throws
}

struct KeychainProviderCredentialStore: ProviderCredentialStoring {
    static let service = "com.grokbuild.provider-credential"

    func credential(for providerID: String) throws -> String? {
        var query = baseQuery(providerID: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ProviderCredentialError.keychain(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw ProviderCredentialError.invalidStoredCredential
        }
        return value
    }

    func setCredential(_ credential: String, for providerID: String) throws {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try removeCredential(for: providerID)
            return
        }
        let data = Data(trimmed.utf8)
        let query = baseQuery(providerID: providerID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ProviderCredentialError.keychain(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw ProviderCredentialError.keychain(addStatus) }
    }

    func removeCredential(for providerID: String) throws {
        let status = SecItemDelete(baseQuery(providerID: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderCredentialError.keychain(status)
        }
    }

    private func baseQuery(providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: providerID
        ]
    }
}

enum ProviderCredentialError: LocalizedError, Equatable {
    case keychain(OSStatus)
    case invalidStoredCredential
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain could not save the provider credential: \(detail)"
        case .invalidStoredCredential:
            return "The provider credential in Keychain could not be read."
        case .verificationFailed:
            return "Keychain did not return the credential after saving it."
        }
    }
}

struct ProviderCredentialMigrationIssue: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case conflict
        case storage
    }

    let kind: Kind
    let providerID: String
    let message: String
    var id: String { "\(kind.rawValue):\(providerID)" }
}

struct ProviderCredentialMigrationResult: Sendable {
    var providers: [Provider]
    var issues: [ProviderCredentialMigrationIssue]
    var didMigrate: Bool
    var storageFailed: Bool
    var createdProviderIDs: [String]
}

enum ProviderCredentialMigrator {
    /// Moves legacy UserDefaults/model credentials into Keychain without printing them.
    /// Newly created entries are removed if any Keychain operation fails.
    static func migrate(
        providers: [Provider],
        models: [CustomModel],
        credentialStore: any ProviderCredentialStoring
    ) -> ProviderCredentialMigrationResult {
        var hydrated = providers
        var issues: [ProviderCredentialMigrationIssue] = []
        var createdProviderIDs: [String] = []
        var didMigrate = false

        do {
            for index in hydrated.indices {
                let provider = hydrated[index]
                if let existing = try credentialStore.credential(for: provider.id), !existing.isEmpty {
                    hydrated[index].apiKey = existing
                    if provider.authScheme != .none,
                       hydrated[index].credentialMetadata.kind == .none {
                        hydrated[index].credentialMetadata = .migratedAPIKey
                        didMigrate = true
                    }
                    continue
                }

                let legacyProviderKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchingModelKeys = Set(
                    models
                        .filter { $0.baseURL == provider.baseURL }
                        .map { $0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )

                let candidate: String?
                if !legacyProviderKey.isEmpty {
                    candidate = legacyProviderKey
                } else if matchingModelKeys.count == 1 {
                    candidate = matchingModelKeys.first
                } else if matchingModelKeys.count > 1 {
                    issues.append(ProviderCredentialMigrationIssue(
                        kind: .conflict,
                        providerID: provider.id,
                        message: "Multiple different model credentials use this provider. Re-enter the provider key to resolve the conflict."
                    ))
                    candidate = nil
                } else {
                    candidate = nil
                }

                guard let candidate else {
                    hydrated[index].apiKey = ""
                    continue
                }

                try credentialStore.setCredential(candidate, for: provider.id)
                guard try credentialStore.credential(for: provider.id) == candidate else {
                    throw ProviderCredentialError.verificationFailed
                }
                createdProviderIDs.append(provider.id)
                hydrated[index].apiKey = candidate
                if hydrated[index].authScheme != .none,
                   hydrated[index].credentialMetadata.kind == .none {
                    hydrated[index].credentialMetadata = .migratedAPIKey
                }
                didMigrate = true
            }
        } catch {
            for providerID in createdProviderIDs {
                try? credentialStore.removeCredential(for: providerID)
            }
            issues.append(ProviderCredentialMigrationIssue(
                kind: .storage,
                providerID: "keychain",
                message: error.localizedDescription
            ))
            return ProviderCredentialMigrationResult(
                providers: providers,
                issues: issues,
                didMigrate: false,
                storageFailed: true,
                createdProviderIDs: []
            )
        }

        return ProviderCredentialMigrationResult(
            providers: hydrated,
            issues: issues,
            didMigrate: didMigrate,
            storageFailed: false,
            createdProviderIDs: createdProviderIDs
        )
    }
}
