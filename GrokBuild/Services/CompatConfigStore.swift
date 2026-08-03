import Foundation

enum CompatFlavor: String, CaseIterable, Sendable {
    case cursor
    case claude
    case codex

    var tomlKey: String { rawValue }

    /// Capability cells currently understood by Grok's compatibility loader.
    var supportedCapabilities: [String] {
        switch self {
        case .cursor, .claude:
            return ["skills", "rules", "agents", "mcps", "hooks", "sessions"]
        case .codex:
            // The other Codex cells are reserved by Grok and currently inert.
            return ["sessions"]
        }
    }
}

/// Presents each compatibility source as one switch while reading/writing Grok's supported
/// per-capability cells in `~/.grok/config.toml`.
enum CompatConfigStore {
    static var configURL: URL {
        CustomModelStore.configURL
    }

    static func loadEnabled(_ flavor: CompatFlavor) -> Bool {
        isEnabled(flavor)
    }

    static func isEnabled(_ flavor: CompatFlavor, contents: String? = nil) -> Bool {
        let text: String
        if let contents {
            text = contents
        } else {
            text = GrokConfigRepository.shared.read()
            if text.isEmpty { return true }
        }
        return parseEnabled(flavor: flavor, from: text) ?? true
    }

    static func setEnabled(_ flavor: CompatFlavor, _ enabled: Bool) throws {
        try GrokConfigRepository.shared.update { existing in
            rewrite(existing, flavor: flavor, enabled: enabled)
        }
    }

    static func loadDraft() -> CompatibilitySettingsDraft {
        CompatibilitySettingsDraft(
            cursorEnabled: loadEnabled(.cursor),
            claudeEnabled: loadEnabled(.claude),
            codexEnabled: loadEnabled(.codex)
        )
    }

    /// One locked config mutation for the three aggregate switches. A write cannot
    /// leave Cursor updated while Claude/Codex still reflect the prior pane draft.
    static func setEnabled(_ draft: CompatibilitySettingsDraft) throws {
        try GrokConfigRepository.shared.update { existing in
            var rewritten = rewrite(existing, flavor: .cursor, enabled: draft.cursorEnabled)
            rewritten = rewrite(rewritten, flavor: .claude, enabled: draft.claudeEnabled)
            rewritten = rewrite(rewritten, flavor: .codex, enabled: draft.codexEnabled)
            return rewritten
        }
    }

    static func rewrite(_ contents: String, flavor: CompatFlavor, enabled: Bool) -> String {
        let sectionName = "compat.\(flavor.tomlKey)"
        let managedKeys = Set(flavor.supportedCapabilities + ["enabled"])
        var output: [String] = []
        var inSection = false
        var hasSection = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inSection {
                    appendCapabilities(flavor, enabled: enabled, to: &output)
                }
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                inSection = header == sectionName
                if inSection { hasSection = true }
                output.append(rawLine)
                continue
            }

            if inSection {
                let key = trimmed.split(separator: "=", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                if let key, managedKeys.contains(key) {
                    continue
                }
            }

            output.append(rawLine)
        }

        if inSection {
            appendCapabilities(flavor, enabled: enabled, to: &output)
        }

        while let last = output.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            output.removeLast()
        }

        var result = output.joined(separator: "\n")
        if !hasSection {
            if !result.isEmpty { result += "\n" }
            result += "\n[\(sectionName)]\n"
            result += capabilityLines(flavor, enabled: enabled).joined(separator: "\n")
            result += "\n"
        } else if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    /// Reads the unsupported blanket field used by older GrokBuild versions.
    static func legacyEnabled(_ flavor: CompatFlavor, contents: String) -> Bool? {
        parseValues(flavor: flavor, from: contents).legacyEnabled
    }

    private static func parseEnabled(flavor: CompatFlavor, from contents: String) -> Bool? {
        let parsed = parseValues(flavor: flavor, from: contents)
        if let legacy = parsed.legacyEnabled { return legacy }
        guard parsed.sawSection else { return nil }
        return flavor.supportedCapabilities.allSatisfy { parsed.capabilities[$0] ?? true }
    }

    private static func parseValues(
        flavor: CompatFlavor,
        from contents: String
    ) -> (sawSection: Bool, legacyEnabled: Bool?, capabilities: [String: Bool]) {
        let sectionName = "compat.\(flavor.tomlKey)"
        var inSection = false
        var sawSection = false
        var legacyEnabled: Bool?
        var capabilities: [String: Bool] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                inSection = header == sectionName
                if inSection { sawSection = true }
                continue
            }
            guard inSection else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            let parsed: Bool?
            switch value {
            case "true", "yes", "1": parsed = true
            case "false", "no", "0": parsed = false
            default: parsed = nil
            }
            guard let parsed else { continue }
            if key == "enabled" {
                legacyEnabled = parsed
            } else if flavor.supportedCapabilities.contains(key) {
                capabilities[key] = parsed
            }
        }
        return (sawSection, legacyEnabled, capabilities)
    }

    private static func capabilityLines(_ flavor: CompatFlavor, enabled: Bool) -> [String] {
        flavor.supportedCapabilities.map { "\($0) = \(enabled)" }
    }

    private static func appendCapabilities(
        _ flavor: CompatFlavor,
        enabled: Bool,
        to output: inout [String]
    ) {
        output.append(contentsOf: capabilityLines(flavor, enabled: enabled))
    }

    private static func stripComment(_ line: String) -> String {
        TOMLLineParsing.stripComment(line)
    }
}

struct GrokExternalCompatCell: Identifiable, Hashable, Sendable {
    let vendor: String
    let surface: String
    let isEnabled: Bool
    let source: String

    var id: String { "\(vendor)|\(surface)" }
}

struct GrokExternalCompatInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isEnabled: Bool
    let cells: [GrokExternalCompatCell]
    let schema: String

    init(
        id: String,
        name: String,
        isEnabled: Bool,
        cells: [GrokExternalCompatCell],
        schema: String
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.cells = cells
        self.schema = schema
    }

    init(dictionary: [String: Any]) {
        let rawName = dictionary["name"] as? String ?? dictionary["id"] as? String ?? "Unknown"
        id = rawName.lowercased()
        name = rawName
        isEnabled = dictionary["enabled"] as? Bool
            ?? (dictionary["is_enabled"] as? Bool)
            ?? false
        cells = []
        schema = "legacy"
    }
}

enum GrokExternalCompatDecoder {
    enum DecodeError: LocalizedError {
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let detail):
                return "Grok returned an unsupported external compatibility schema (\(detail))."
            }
        }
    }

    /// Supports Grok 0.2.118's `externalCompat.cells` object plus the three
    /// historical array fields. A present-but-malformed current field is an error,
    /// never a successful empty inventory.
    static func decode(inspect: [String: Any]) throws -> [GrokExternalCompatInfo] {
        if let raw = inspect["externalCompat"] {
            guard let object = raw as? [String: Any],
                  let rows = object["cells"] as? [[String: Any]] else {
                throw DecodeError.unsupported("externalCompat.cells is not an array")
            }
            var grouped: [String: [GrokExternalCompatCell]] = [:]
            for row in rows {
                guard let vendor = row["vendor"] as? String, !vendor.isEmpty,
                      let surface = row["surface"] as? String, !surface.isEmpty,
                      let enabled = row["enabled"] as? Bool else {
                    throw DecodeError.unsupported("a capability cell is missing vendor, surface, or enabled")
                }
                grouped[vendor, default: []].append(
                    GrokExternalCompatCell(
                        vendor: vendor,
                        surface: surface,
                        isEnabled: enabled,
                        source: row["source"] as? String ?? "unknown"
                    )
                )
            }
            let preferredOrder = ["cursor", "claude", "codex"]
            return grouped.keys.sorted { lhs, rhs in
                let left = preferredOrder.firstIndex(of: lhs) ?? preferredOrder.count
                let right = preferredOrder.firstIndex(of: rhs) ?? preferredOrder.count
                return left == right ? lhs < rhs : left < right
            }.map { vendor in
                let cells = (grouped[vendor] ?? []).sorted { $0.surface < $1.surface }
                return GrokExternalCompatInfo(
                    id: vendor,
                    name: displayName(for: vendor),
                    isEnabled: !cells.isEmpty && cells.allSatisfy(\.isEnabled),
                    cells: cells,
                    schema: "externalCompat.cells"
                )
            }
        }

        for key in ["compat", "external_compat", "compat_layers"] {
            if let raw = inspect[key] {
                guard let rows = raw as? [[String: Any]] else {
                    throw DecodeError.unsupported("\(key) is not an array")
                }
                return rows.map(GrokExternalCompatInfo.init(dictionary:))
            }
        }
        return []
    }

    private static func displayName(for vendor: String) -> String {
        switch vendor.lowercased() {
        case "cursor": return "Cursor"
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        default: return vendor
        }
    }
}
