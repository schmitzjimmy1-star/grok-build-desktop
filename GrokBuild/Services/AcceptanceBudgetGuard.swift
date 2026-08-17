import CryptoKit
import Foundation

struct AcceptanceTurnBudget: Codable, Equatable, Sendable {
    let marker: String
    let promptHash: String
    let tokenAllocation: Int
    let maxModelCalls: Int

    var isValid: Bool {
        !marker.isEmpty
            && promptHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
            && tokenAllocation > 0
            && maxModelCalls > 0
    }
}

struct AcceptanceBudgetManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let runID: String
    let campaignTokenCeiling: Int
    let emergencyReserveTokens: Int
    let packets: [AcceptanceTurnBudget]

    var isValid: Bool {
        let plannedAllocation = packets.reduce(into: 0) { partial, packet in
            let (sum, overflow) = partial.addingReportingOverflow(packet.tokenAllocation)
            partial = overflow ? Int.max : sum
        }
        return schemaVersion == 1
            && !runID.isEmpty
            && campaignTokenCeiling == 4_000_000
            && emergencyReserveTokens >= 1_000_000
            && !packets.isEmpty
            && packets.allSatisfy(\.isValid)
            && Set(packets.map(\.marker)).count == packets.count
            && plannedAllocation <= campaignTokenCeiling - emergencyReserveTokens
    }

    func budget(for prompt: String) -> AcceptanceTurnBudget? {
        let matches = packets.filter { prompt.components(separatedBy: $0.marker).count == 2 }
        guard matches.count == 1 else { return nil }
        let digest = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        return digest == matches[0].promptHash ? matches[0] : nil
    }
}

enum AcceptanceBudgetResolution: Equatable, Sendable {
    case inactive
    case budget(AcceptanceTurnBudget)
    case blocked
}

enum AcceptanceBudgetGuard {
    static let argumentPrefix = "--grokbuild-acceptance-budget-file="

    static func resolve(
        prompt: String,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AcceptanceBudgetResolution {
        let paths = arguments.compactMap { argument -> String? in
            guard argument.hasPrefix(argumentPrefix) else { return nil }
            return String(argument.dropFirst(argumentPrefix.count))
        }
        guard !paths.isEmpty else { return .inactive }
        guard paths.count == 1,
              !paths[0].isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: paths[0])),
              let manifest = try? JSONDecoder().decode(AcceptanceBudgetManifest.self, from: data),
              manifest.isValid else {
            return .blocked
        }
        guard let budget = manifest.budget(for: prompt) else { return .blocked }
        return .budget(budget)
    }
}
