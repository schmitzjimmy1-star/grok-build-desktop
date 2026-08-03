import Foundation

/// Removes GrokBuild fields that older app builds placed in the Grok CLI's schema-owned TOML.
/// The migration is idempotent and preserves every unrelated section verbatim.
enum GrokConfigLegacyMigration {
    static let removedPluginSettingBackupKey = "grokbuild.legacyDisabledMCPServersBackup.v1"

    static func run(
        repository: GrokConfigRepository = .shared,
        defaults: UserDefaults = .standard
    ) throws {
        let existing = repository.read()

        if containsLegacyModelMetadata(existing) {
            CustomModelMetadataStore.mergeLegacy(
                models: CustomModelStore.parse(existing).models,
                defaults: defaults
            )
        }

        let sanitized = sanitize(existing, defaults: defaults)
        if sanitized != existing {
            try repository.update { latest in
                sanitize(latest, defaults: defaults)
            }
        } else {
            try repository.enforceSecurePermissionsIfPresent()
        }
    }

    static func sanitize(_ contents: String, defaults: UserDefaults? = nil) -> String {
        var migrated = contents
        for flavor in CompatFlavor.allCases {
            if let enabled = CompatConfigStore.legacyEnabled(flavor, contents: migrated) {
                migrated = CompatConfigStore.rewrite(migrated, flavor: flavor, enabled: enabled)
            }
        }

        let pluginCleanup = removingLegacyPluginSetting(from: migrated)
        if let defaults,
           !pluginCleanup.removed.isEmpty,
           defaults.object(forKey: removedPluginSettingBackupKey) == nil {
            defaults.set(pluginCleanup.removed.joined(separator: "\n"), forKey: removedPluginSettingBackupKey)
        }
        let withoutLegacyMetadata = removingLegacyModelMetadata(from: pluginCleanup.contents)
        return projectingNativeModelFields(into: withoutLegacyMetadata, defaults: defaults)
    }

    private static func containsLegacyModelMetadata(_ contents: String) -> Bool {
        contents.contains("grokbuild_context_tokens")
            || contents.contains("grokbuild_supports_reasoning_effort")
            || contents.contains("grokbuild_supports_vision")
            || contents.contains("grokbuild_supports_thinking")
    }

    private static func removingLegacyModelMetadata(from contents: String) -> String {
        let legacyKeys: Set<String> = [
            "grokbuild_context_tokens",
            "grokbuild_supports_reasoning_effort",
            "grokbuild_supports_vision",
            "grokbuild_supports_thinking",
            "grokbuild_provider_id",
        ]
        var inModel = false
        let lines = contents.components(separatedBy: .newlines).filter { rawLine in
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                inModel = header.hasPrefix("model.")
                return true
            }
            guard inModel,
                  let key = trimmed.split(separator: "=", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased() else {
                return true
            }
            return !legacyKeys.contains(key)
        }
        return lines.joined(separator: "\n")
    }

    private static func removingLegacyPluginSetting(
        from contents: String
    ) -> (contents: String, removed: [String]) {
        var output: [String] = []
        var removed: [String] = []
        var inPlugins = false
        var skippingArray = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if skippingArray {
                removed.append(rawLine)
                if trimmed.contains("]") { skippingArray = false }
                continue
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                inPlugins = header == "plugins"
                output.append(rawLine)
                continue
            }
            if inPlugins,
               let key = trimmed.split(separator: "=", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces)
                .lowercased(),
               key == "disabled_mcp_servers" {
                removed.append(rawLine)
                let value = trimmed.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
                skippingArray = value.contains("[") && !value.contains("]")
                continue
            }
            output.append(rawLine)
        }
        return (output.joined(separator: "\n"), removed)
    }

    /// Restores values that older GrokBuild stored under unknown names and selects Grok's
    /// Responses backend for the known OpenAI model that rejects the default chat endpoint.
    private static func projectingNativeModelFields(
        into contents: String,
        defaults: UserDefaults?
    ) -> String {
        let metadata = defaults.map { CustomModelMetadataStore.load(defaults: $0) } ?? [:]
        var output: [String] = []
        var currentModelID: String?
        var fields: [String: String] = [:]

        func flushNativeFields() {
            guard let id = currentModelID else { return }
            if fields["api_backend"] == nil,
               fields["base_url"]?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                == "https://api.openai.com/v1",
               fields["model"] == "gpt-5.6-terra" {
                output.append("api_backend = \"responses\"")
            }
            if fields["context_window"] == nil,
               let contextTokens = metadata[id]?.contextTokens {
                output.append("context_window = \(contextTokens)")
            }
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                flushNativeFields()
                let header = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if header.hasPrefix("model.") {
                    currentModelID = unquote(String(header.dropFirst("model.".count)))
                } else {
                    currentModelID = nil
                }
                fields = [:]
                output.append(rawLine)
                continue
            }
            if currentModelID != nil,
               let separator = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: separator)...]
                    .trimmingCharacters(in: .whitespaces)
                fields[key] = unquote(value)
            }
            output.append(rawLine)
        }
        flushNativeFields()
        return output.joined(separator: "\n")
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func stripComment(_ line: String) -> String {
        TOMLLineParsing.stripComment(line)
    }
}
