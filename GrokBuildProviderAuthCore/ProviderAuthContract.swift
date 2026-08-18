import Foundation
import Security

public enum ProviderAuthContract {
    public static let keychainService = "com.grokbuild.provider-credential"
    public static let helperExecutableName = "GrokBuildProviderAuthHelper"
    public static let installedHelperPath = "/Applications/GrokBuild.app/Contents/MacOS/\(helperExecutableName)"
    public static let officialProviderPrefix = "grokbuild.saved."
    public static let officialLocalProviderPrefix = "grokbuild.local."

    public static func isValidProviderID(_ providerID: String) -> Bool {
        !providerID.isEmpty
            && providerID.count <= 128
            && providerID.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    public static func officialProviderID(for providerID: String) -> String? {
        guard isValidProviderID(providerID) else { return nil }
        return officialProviderPrefix + providerID
    }

    public static func officialLocalProviderID(for modelID: String) -> String? {
        guard isValidProviderID(modelID) else { return nil }
        return officialLocalProviderPrefix + modelID
    }

    public static func appProviderID(from officialProviderID: String) -> String? {
        guard officialProviderID.hasPrefix(officialProviderPrefix) else { return nil }
        let providerID = String(officialProviderID.dropFirst(officialProviderPrefix.count))
        return isValidProviderID(providerID) ? providerID : nil
    }

    public static func localModelID(from officialProviderID: String) -> String? {
        guard officialProviderID.hasPrefix(officialLocalProviderPrefix) else { return nil }
        let modelID = String(officialProviderID.dropFirst(officialLocalProviderPrefix.count))
        return isValidProviderID(modelID) ? modelID : nil
    }

    public static func isManagedOfficialProviderID(_ officialProviderID: String) -> Bool {
        appProviderID(from: officialProviderID) != nil || localModelID(from: officialProviderID) != nil
    }
}

public enum ProviderAuthHelperError: Error, Equatable {
    case invalidArguments
    case credentialUnavailable
    case keychain(OSStatus)
}

public enum ProviderAuthHelperContract {
    public static func providerID(arguments: [String]) throws -> String {
        guard arguments.count == 2,
              ProviderAuthContract.isValidProviderID(arguments[1]) else {
            throw ProviderAuthHelperError.invalidArguments
        }
        return arguments[1]
    }

    public static func loadCredential(
        providerID: String,
        lookup: (String) throws -> String?
    ) throws -> String {
        guard ProviderAuthContract.isValidProviderID(providerID),
              let raw = try lookup(providerID) else {
            throw ProviderAuthHelperError.credentialUnavailable
        }
        let credential = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else { throw ProviderAuthHelperError.credentialUnavailable }
        return credential
    }
}

public struct KeychainProviderCredentialReader {
    public init() {}

    public func credential(for providerID: String) throws -> String? {
        guard ProviderAuthContract.isValidProviderID(providerID) else {
            throw ProviderAuthHelperError.invalidArguments
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ProviderAuthContract.keychainService,
            kSecAttrAccount as String: providerID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ProviderAuthHelperError.keychain(status) }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw ProviderAuthHelperError.credentialUnavailable
        }
        return value
    }
}
