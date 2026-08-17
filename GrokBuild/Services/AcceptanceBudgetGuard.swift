import CryptoKit
import Darwin
import Foundation

struct AcceptanceTurnBudget: Codable, Equatable, Sendable {
    let packetID: String
    let allocationID: String
    let marker: String
    let promptHash: String
    let tokenAllocation: Int
    let maxModelCalls: Int
    let route: AcceptanceHardBudgetRoute

    var isValid: Bool {
        !packetID.isEmpty
            && !allocationID.isEmpty
            && !marker.isEmpty
            && promptHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
            && tokenAllocation > 0
            && maxModelCalls > 0
            && route.isValid
    }
}

struct AcceptanceHardBudgetRoute: Codable, Equatable, Sendable {
    let model: String
    let endpointSHA256: String
    let apiBackend: String
    let requestBoundTokens: Int
    let maxPayloadBytes: Int
    let maxOutputTokens: Int
    let boundProvenanceSHA256: String

    var isValid: Bool {
        let shaPattern = #"^[0-9a-f]{64}$"#
        let (conservativeBound, overflow) = maxPayloadBytes.addingReportingOverflow(maxOutputTokens)
        return !model.isEmpty
            && endpointSHA256.range(of: shaPattern, options: .regularExpression) != nil
            && !apiBackend.isEmpty
            && requestBoundTokens > 0
            && maxPayloadBytes > 0
            && maxOutputTokens > 0
            && !overflow
            && conservativeBound <= requestBoundTokens
            && boundProvenanceSHA256.range(of: shaPattern, options: .regularExpression) != nil
    }
}

struct AcceptanceBudgetManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let runID: String
    let campaignTokenCeiling: Int
    let emergencyReserveTokens: Int
    let hardBudgetManifestSHA256: String
    let expectedCLIBuild: String
    let packets: [AcceptanceTurnBudget]

    var spendableTokenCeiling: Int? {
        let (value, overflow) = campaignTokenCeiling.subtractingReportingOverflow(emergencyReserveTokens)
        return overflow || value <= 0 ? nil : value
    }

    var isValid: Bool {
        let plannedAllocation = packets.reduce(into: 0) { partial, packet in
            let (sum, overflow) = partial.addingReportingOverflow(packet.tokenAllocation)
            partial = overflow ? Int.max : sum
        }
        return schemaVersion == 2
            && !runID.isEmpty
            && campaignTokenCeiling == 4_000_000
            && emergencyReserveTokens == 1_000_000
            && spendableTokenCeiling != nil
            && hardBudgetManifestSHA256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            ) != nil
            && !expectedCLIBuild.isEmpty
            && !packets.isEmpty
            && packets.allSatisfy(\.isValid)
            && Set(packets.map(\.marker)).count == packets.count
            && Set(packets.map(\.packetID)).count == packets.count
            && Set(packets.map(\.allocationID)).count == packets.count
            && plannedAllocation <= (spendableTokenCeiling ?? 0)
    }

    func budget(for prompt: String) -> AcceptanceTurnBudget? {
        let matches = packets.filter { prompt.components(separatedBy: $0.marker).count == 2 }
        guard matches.count == 1 else { return nil }
        let digest = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        return digest == matches[0].promptHash ? matches[0] : nil
    }
}

struct AcceptanceBudgetAuthorization: Equatable, Sendable {
    let runID: String
    let campaignTokenCeiling: Int
    let emergencyReserveTokens: Int
    let hardBudgetManifestSHA256: String
    let expectedCLIBuild: String
    let budget: AcceptanceTurnBudget
    /// Swift's private schema-2 authorization sidecar; never passed to the CLI.
    let authorizationManifestPath: String
    /// The independently validated CLI HardTokenCampaignManifest used by the sampler.
    let hardBudgetCLIManifestPath: String
    let hardBudgetLedgerPath: String

    var spendableTokenCeiling: Int? {
        let (value, overflow) = campaignTokenCeiling.subtractingReportingOverflow(emergencyReserveTokens)
        return overflow || value <= 0 ? nil : value
    }
}

enum AcceptanceBudgetResolution: Equatable, Sendable {
    case inactive
    case budget(AcceptanceBudgetAuthorization)
    case blocked
}

enum AcceptanceBudgetGuard {
    static let argumentPrefix = "--grokbuild-acceptance-budget-file="
    static let cliManifestArgumentPrefix = "--grokbuild-acceptance-cli-manifest-file="
    static let ledgerArgumentPrefix = "--grokbuild-acceptance-budget-ledger-file="

    static func isConfigured(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains { $0.hasPrefix(argumentPrefix) }
    }

    static func resolve(
        prompt: String,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AcceptanceBudgetResolution {
        let manifestPaths = arguments.compactMap { argument -> String? in
            guard argument.hasPrefix(argumentPrefix) else { return nil }
            return String(argument.dropFirst(argumentPrefix.count))
        }
        guard !manifestPaths.isEmpty else { return .inactive }
        let ledgerPaths = arguments.compactMap { argument -> String? in
            guard argument.hasPrefix(ledgerArgumentPrefix) else { return nil }
            return String(argument.dropFirst(ledgerArgumentPrefix.count))
        }
        let cliManifestPaths = arguments.compactMap { argument -> String? in
            guard argument.hasPrefix(cliManifestArgumentPrefix) else { return nil }
            return String(argument.dropFirst(cliManifestArgumentPrefix.count))
        }
        guard manifestPaths.count == 1,
              cliManifestPaths.count == 1,
              ledgerPaths.count == 1,
              !manifestPaths[0].isEmpty,
              let data = secureRead(path: manifestPaths[0]),
              let cliManifest = secureRead(path: cliManifestPaths[0]),
              securePrivateRegularPath(ledgerPaths[0]),
              let manifest = try? JSONDecoder().decode(AcceptanceBudgetManifest.self, from: data),
              sha256(cliManifest) == manifest.hardBudgetManifestSHA256,
              manifest.isValid else {
            return .blocked
        }
        guard let budget = manifest.budget(for: prompt) else { return .blocked }
        return .budget(AcceptanceBudgetAuthorization(
            runID: manifest.runID,
            campaignTokenCeiling: manifest.campaignTokenCeiling,
            emergencyReserveTokens: manifest.emergencyReserveTokens,
            hardBudgetManifestSHA256: manifest.hardBudgetManifestSHA256,
            expectedCLIBuild: manifest.expectedCLIBuild,
            budget: budget,
            authorizationManifestPath: manifestPaths[0],
            hardBudgetCLIManifestPath: cliManifestPaths[0],
            hardBudgetLedgerPath: ledgerPaths[0]
        ))
    }

    private static func secureRead(path: String) -> Data? {
        guard NSString(string: path).isAbsolutePath else { return nil }
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_mode & mode_t(S_IRWXG | S_IRWXO) == 0,
              metadata.st_size >= 0,
              metadata.st_size <= 1_048_576 else { return nil }
        let expectedSize = Int(metadata.st_size)
        guard let data = try? handle.read(upToCount: expectedSize + 1),
              data.count == expectedSize else { return nil }
        var afterRead = stat()
        guard fstat(descriptor, &afterRead) == 0,
              afterRead.st_dev == metadata.st_dev,
              afterRead.st_ino == metadata.st_ino,
              afterRead.st_size == metadata.st_size else { return nil }
        return data
    }

    private static func securePrivateRegularPath(_ path: String) -> Bool {
        guard NSString(string: path).isAbsolutePath else { return false }
        var metadata = stat()
        return lstat(path, &metadata) == 0
            && metadata.st_uid == getuid()
            && metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            && metadata.st_mode & mode_t(S_IRWXG | S_IRWXO) == 0
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
