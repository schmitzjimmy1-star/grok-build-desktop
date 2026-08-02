import Foundation

struct AppBuildIdentity: Equatable, Sendable {
    static let canonicalRepositoryURL = "https://github.com/schmitzjimmy1-star/grok-build-desktop"
    static let canonicalChannel = "personal"

    let repositoryURL: String
    let branch: String
    let commit: String
    let isDirty: Bool
    let channel: String

    init(infoDictionary: [String: Any]) {
        repositoryURL = Self.nonEmptyString(
            infoDictionary["GrokBuildSourceRepository"]
        ) ?? Self.canonicalRepositoryURL
        branch = Self.nonEmptyString(infoDictionary["GrokBuildSourceBranch"]) ?? "unknown"
        commit = Self.nonEmptyString(infoDictionary["GrokBuildSourceCommit"]) ?? "unknown"
        isDirty = Self.bool(infoDictionary["GrokBuildSourceDirty"])
        channel = Self.nonEmptyString(infoDictionary["GrokBuildBuildChannel"]) ?? Self.canonicalChannel
    }

    var isStamped: Bool {
        branch != "unknown" && commit.range(of: #"^[0-9a-fA-F]{7,40}$"#, options: .regularExpression) != nil
    }

    var shortCommit: String {
        isStamped ? String(commit.prefix(8)) : "unknown"
    }

    var channelDisplayName: String {
        channel
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var summary: String {
        guard isStamped else {
            return "\(channelDisplayName) • unstamped source build"
        }
        return "\(channelDisplayName) • \(branch) @ \(shortCommit)\(isDirty ? " (dirty)" : "")"
    }

    var commitURL: URL? {
        guard isStamped else { return nil }
        let base = repositoryURL.hasSuffix(".git") ? String(repositoryURL.dropLast(4)) : repositoryURL
        return URL(string: "\(base)/commit/\(commit)")
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return value.caseInsensitiveCompare("true") == .orderedSame }
        return false
    }
}
