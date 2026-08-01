import CryptoKit
import Foundation
import OSLog
import Security

/// Shared keyed-integrity primitive for lifecycle snapshots and future transcript
/// verification. The key remains in Keychain; exported diagnostics never include it or
/// the opaque tags it produces.
enum VersionedOpaqueTag {
    static let transcriptNormalizationVersion = 1

    static func authenticationCode(
        key: Data,
        domain: String,
        schemaVersion: Int,
        payload: Data
    ) -> String {
        var authenticated = Data("\(domain)\u{1F}v\(schemaVersion)\u{1F}".utf8)
        authenticated.append(payload)
        let code = HMAC<SHA256>.authenticationCode(
            for: authenticated,
            using: SymmetricKey(data: key)
        )
        return code.map { String(format: "%02x", $0) }.joined()
    }

    static func transcriptMessagePayload(
        role: String,
        ordinal: Int,
        content: String
    ) -> Data {
        let normalizedRole = role
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedContent = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Data("\(normalizedRole)\u{1F}\(ordinal)\u{1F}\(normalizedContent)".utf8)
    }

    static func transcriptMessageTag(
        key: Data,
        role: String,
        ordinal: Int,
        content: String
    ) -> String {
        authenticationCode(
            key: key,
            domain: "transcript-message",
            schemaVersion: transcriptNormalizationVersion,
            payload: transcriptMessagePayload(role: role, ordinal: ordinal, content: content)
        )
    }
}

protocol SessionLifecycleIntegrityKeyProviding {
    func existingKey() throws -> Data?
    func existingOrCreateKey() throws -> Data
}

struct KeychainSessionLifecycleIntegrityKeyProvider: SessionLifecycleIntegrityKeyProviding {
    private static let logger = Logger(
        subsystem: "com.grokbuild.app",
        category: "SessionLifecycleIntegrity"
    )
    private static let service = "com.grokbuild.session-lifecycle-integrity"
    private static let account = "v1"
    private static let keyByteCount = 32
    private static let cacheLock = NSLock()
    private static var cachedKey: Data?

    func existingKey() throws -> Data? {
        if let cached = Self.withCacheLock({ Self.cachedKey }) {
            return cached
        }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              data.count == Self.keyByteCount else {
            Self.logger.error(
                "Lifecycle Keychain read failed with OSStatus \(status, privacy: .public)"
            )
            throw SessionLifecycleIntegrityError.keychain(status)
        }
        Self.withCacheLock { Self.cachedKey = data }
        return data
    }

    func existingOrCreateKey() throws -> Data {
        if let existing = try existingKey() { return existing }
        var bytes = [UInt8](repeating: 0, count: Self.keyByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SessionLifecycleIntegrityError.randomGeneration
        }
        let data = Data(bytes)
        var query = baseQuery
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try existingKey() {
            return existing
        }
        guard status == errSecSuccess else {
            Self.logger.error(
                "Lifecycle Keychain create failed with OSStatus \(status, privacy: .public)"
            )
            throw SessionLifecycleIntegrityError.keychain(status)
        }
        Self.withCacheLock { Self.cachedKey = data }
        return data
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }

    private static func withCacheLock<Value>(_ operation: () -> Value) -> Value {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return operation()
    }
}

enum SessionLifecycleIntegrityError: Error, Equatable {
    case keychain(OSStatus)
    case randomGeneration
}
