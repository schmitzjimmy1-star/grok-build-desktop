import XCTest
@testable import GrokBuild

final class GrokConfigLegacyMigrationTests: XCTestCase {
    func testMigrationRemovesOnlyInvalidFieldsAndPreservesIntent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-config-migration-\(UUID().uuidString)")
        let configURL = directory.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "GrokBuildTests.configMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        let original = """
        [compat.cursor]
        enabled = false

        [compat.claude]
        enabled = true

        [compat.codex]
        enabled = false

        [plugins]
        enabled = ["brightdata"]
        disabled_mcp_servers = [
          "tinyfish",
          "postman",
        ]
        disabled = ["tinyfish"]

        [mcp_servers.keep-me]
        command = "safe-command"

        [model.openai]
        model = "gpt-5.6-terra"
        base_url = "https://api.openai.com/v1"
        api_key = "secret-that-must-survive"
        grokbuild_context_tokens = 400000
        grokbuild_supports_reasoning_effort = false
        grokbuild_supports_vision = true
        grokbuild_supports_thinking = true
        """
        try original.write(to: configURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)
        let repository = GrokConfigRepository(configURL: configURL)

        try GrokConfigLegacyMigration.run(repository: repository, defaults: defaults)
        let migrated = repository.read()

        XCTAssertFalse(migrated.contains("grokbuild_"))
        XCTAssertFalse(migrated.contains("disabled_mcp_servers"))
        XCTAssertFalse(migrated.contains("enabled = false"))
        XCTAssertTrue(migrated.contains("skills = false"))
        XCTAssertTrue(migrated.contains("hooks = true"))
        XCTAssertTrue(migrated.contains("sessions = false"))
        XCTAssertTrue(migrated.contains("enabled = [\"brightdata\"]"))
        XCTAssertTrue(migrated.contains("disabled = [\"tinyfish\"]"))
        XCTAssertTrue(migrated.contains("[mcp_servers.keep-me]"))
        XCTAssertTrue(migrated.contains("api_key = \"secret-that-must-survive\""))
        XCTAssertTrue(migrated.contains("api_backend = \"responses\""))
        XCTAssertTrue(migrated.contains("context_window = 400000"))

        let metadata = CustomModelMetadataStore.load(defaults: defaults)["openai"]
        XCTAssertEqual(metadata?.contextTokens, 400_000)
        XCTAssertEqual(metadata?.supportsReasoningEffort, false)
        XCTAssertEqual(metadata?.supportsVision, true)
        XCTAssertEqual(metadata?.supportsThinkingDisplay, true)
        XCTAssertTrue(
            defaults.string(forKey: GrokConfigLegacyMigration.removedPluginSettingBackupKey)?
                .contains("postman") == true
        )

        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        try GrokConfigLegacyMigration.run(repository: repository, defaults: defaults)
        XCTAssertEqual(repository.read(), migrated, "migration must be idempotent")
    }
}
