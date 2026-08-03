import Foundation
import XCTest
@testable import GrokBuild

final class SettingsExtensionContractTests: XCTestCase {
    func testCurrentExternalCompatFixtureDecodesAllThirteenCells() throws {
        let inspect = try fixtureJSONObject("inspect-external-compat-0.2.118.json")
        let items = try GrokExternalCompatDecoder.decode(inspect: inspect)

        XCTAssertEqual(items.map(\.id), ["cursor", "claude", "codex"])
        XCTAssertEqual(items.flatMap(\.cells).count, 13)
        XCTAssertEqual(items.first(where: { $0.id == "cursor" })?.cells.count, 6)
        XCTAssertEqual(items.first(where: { $0.id == "claude" })?.cells.count, 6)
        XCTAssertEqual(items.first(where: { $0.id == "codex" })?.cells.map(\.surface), ["sessions"])
        XCTAssertTrue(items.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(items.allSatisfy { $0.schema == "externalCompat.cells" })
    }

    func testExternalCompatLegacyArraysRemainSupported() throws {
        let items = try GrokExternalCompatDecoder.decode(inspect: [
            "external_compat": [
                ["name": "Cursor", "enabled": true],
                ["name": "Codex", "is_enabled": false],
            ],
        ])
        XCTAssertEqual(items.map(\.name), ["Cursor", "Codex"])
        XCTAssertEqual(items.map(\.isEnabled), [true, false])
        XCTAssertTrue(items.allSatisfy { $0.schema == "legacy" })
    }

    func testExternalCompatMalformedCurrentSchemaIsNotEmptySuccess() {
        XCTAssertThrowsError(
            try GrokExternalCompatDecoder.decode(inspect: [
                "externalCompat": ["cells": "not-an-array"],
            ])
        )
        XCTAssertThrowsError(
            try GrokExternalCompatDecoder.decode(inspect: [
                "externalCompat": ["cells": [["vendor": "cursor"]]],
            ])
        )
    }

    func testMCPStdioArgumentsPreserveExactBoundariesAndRedactSecrets() throws {
        let fixture = try fixtureJSONObject("mcp-serialization-0.2.118.json")
        let stdio = try XCTUnwrap(fixture["stdio"] as? [String: Any])
        let expectedArgs = try XCTUnwrap(stdio["args"] as? [String])
        let environmentNames = try XCTUnwrap(stdio["environmentNames"] as? [String])

        var draft = GrokMCPServerDraft()
        draft.name = try XCTUnwrap(stdio["name"] as? String)
        draft.transport = .stdio
        draft.scope = .project
        draft.executable = try XCTUnwrap(stdio["command"] as? String)
        draft.arguments = expectedArgs.map { GrokMCPArgumentDraft(value: $0) }
        draft.environment = [
            GrokMCPSecretDraft(name: environmentNames[0], value: "literal-one"),
            GrokMCPSecretDraft(name: environmentNames[1], value: ""),
        ]

        XCTAssertEqual(draft.validation, .valid)
        let args = GrokCLIService.mcpAddArguments(for: draft, redacted: false)
        let separator = try XCTUnwrap(args.firstIndex(of: "--"))
        XCTAssertEqual(Array(args[(separator + 1)...]), [draft.executable] + expectedArgs)
        XCTAssertTrue(args.contains("SYNTHETIC_MODE=literal-one"))
        XCTAssertTrue(args.contains("EMPTY_VALUE="))
        XCTAssertTrue(args.contains("synthetic server"))
        XCTAssertTrue(args.contains("--empty="))

        let redacted = GrokCLIService.mcpAddArguments(for: draft, redacted: true)
        XCTAssertFalse(redacted.joined(separator: " ").contains("literal-one"))
        XCTAssertTrue(redacted.contains("SYNTHETIC_MODE=<redacted>"))
        XCTAssertTrue(redacted.contains("EMPTY_VALUE=<redacted>"))
    }

    func testMCPRemoteArgumentsKeepHeadersSeparateAndRequireHTTPURL() throws {
        let fixture = try fixtureJSONObject("mcp-serialization-0.2.118.json")
        let http = try XCTUnwrap(fixture["http"] as? [String: Any])
        let headerNames = try XCTUnwrap(http["headerNames"] as? [String])

        var draft = GrokMCPServerDraft()
        draft.name = try XCTUnwrap(http["name"] as? String)
        draft.transport = .http
        draft.scope = .user
        draft.url = try XCTUnwrap(http["url"] as? String)
        draft.headers = [
            GrokMCPSecretDraft(name: headerNames[0], value: "Bearer secret-token"),
            GrokMCPSecretDraft(name: headerNames[1], value: "trace value"),
        ]
        XCTAssertEqual(draft.validation, .valid)

        let args = GrokCLIService.mcpAddArguments(for: draft, redacted: false)
        XCTAssertEqual(args.filter { $0 == "--header" }.count, 2)
        XCTAssertTrue(args.contains("Authorization: Bearer secret-token"))
        XCTAssertEqual(args.last, draft.url)

        draft.url = "file:///tmp/not-http"
        XCTAssertFalse(draft.validation.isValid)
    }

    func testMCPInventoryKeepsOnlySecretNamesAndRedactedTarget() {
        let info = GrokMCPServerInfo(dictionary: [
            "name": "synthetic",
            "scope": "user",
            "command": "/usr/bin/env",
            "args": ["node", "server with spaces"],
            "env": ["API_TOKEN": "literal-secret", "EMPTY": ""],
            "headers": ["Authorization": "Bearer literal-secret"],
            "enabled": true,
        ])
        XCTAssertEqual(info.transport, "stdio")
        XCTAssertEqual(info.argumentCount, 2)
        XCTAssertEqual(info.environmentNames, ["API_TOKEN", "EMPTY"])
        XCTAssertEqual(info.headerNames, ["Authorization"])
        XCTAssertFalse(String(describing: info).contains("literal-secret"))

        let remote = GrokMCPServerInfo(dictionary: [
            "name": "remote",
            "url": "https://user:password@example.invalid/mcp",
        ])
        XCTAssertFalse(remote.target.contains("password"))
    }

    func testMCPDiagnosticRedactionMasksKnownAndPatternSecrets() {
        let output = GrokMCPRedactor.redact(
            "Authorization: Bearer abc123 API_KEY=xyz password=hunter2",
            secretValues: ["hunter2"]
        )
        XCTAssertFalse(output.contains("abc123"))
        XCTAssertFalse(output.contains("xyz"))
        XCTAssertFalse(output.contains("hunter2"))
        XCTAssertTrue(output.contains("<redacted>"))
    }

    func testMCPDiagnosticRedactionMasksQuotedCredentialPrefixes() {
        let keyPrefix = "synthetic-key-prefix-should-not-escape"
        let accessToken = "synthetic-access-token-should-not-escape"
        let refreshToken = "synthetic-refresh-token-should-not-escape"
        let output = GrokMCPRedactor.redact(
            "{\"key_prefix\":\"\(keyPrefix)\",\"access_token\":\"\(accessToken)\",\"refresh_token\":\"\(refreshToken)\"}"
        )

        XCTAssertFalse(output.contains(keyPrefix))
        XCTAssertFalse(output.contains(accessToken))
        XCTAssertFalse(output.contains(refreshToken))
        XCTAssertEqual(output.components(separatedBy: "<redacted>").count - 1, 3)
    }

    func testInventoryStatePreservesLastSuccessAsStaleOnFailure() {
        var state = SettingsInventoryState<[String]>(empty: [])
        state.beginRefresh(staleMessage: "Refreshing")
        XCTAssertEqual(state.loadState, .checking)
        state.finish(["one"], isEmpty: false, emptyMessage: "Empty")
        XCTAssertEqual(state.loadState, .content)
        state.beginRefresh(staleMessage: "Refreshing")
        XCTAssertEqual(state.loadState, .stale("Refreshing"))
        state.fail("Offline")
        XCTAssertEqual(state.value, ["one"])
        XCTAssertEqual(state.loadState, .stale("Showing the last successful result. Offline"))
        XCTAssertEqual(state.nextConfigurationGeneration(), 1)
    }

    private func fixtureJSONObject(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CoherenceRepair")
        let data = try Data(contentsOf: root.appendingPathComponent(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
