import XCTest
@testable import GrokBuild
@testable import GrokBuildComputerUseCore

/// Tests the helper's contract directly — the executable target itself cannot
/// be imported, which is why this logic lives in GrokBuildComputerUseCore.
final class ComputerUseCoreTests: XCTestCase {
    func testToolTableExposesAllTenTools() {
        XCTAssertEqual(computerUseTools.map(\.name), [
            "computer_snapshot",
            "computer_screenshot",
            "computer_click",
            "computer_type",
            "computer_press",
            "computer_get",
            "computer_wait",
            "computer_list_apps",
            "computer_list_windows",
            "computer_permissions",
        ])
    }

    /// The bundled skill must not advertise tools the helper does not
    /// implement — its guidance is the model's map of the surface.
    func testSkillAdvertisesOnlyImplementedTools() throws {
        let skillURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GrokBuildTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("GrokBuild/Resources/Skills/grokbuild-computer-use/SKILL.md")
        let text = try String(contentsOf: skillURL, encoding: .utf8)

        let regex = try NSRegularExpression(pattern: #"computer_[a-z_]+"#)
        let ns = text as NSString
        let mentioned = Set(regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) })
        let implemented = Set(computerUseTools.map(\.name))

        XCTAssertTrue(mentioned.isSubset(of: implemented),
                      "SKILL.md mentions unimplemented tools: \(mentioned.subtracting(implemented))")
        // And the skill should name the full surface somewhere.
        XCTAssertEqual(mentioned, implemented,
                       "SKILL.md is missing tools: \(implemented.subtracting(mentioned))")
    }

    func testEnvParityBetweenAppAndHelper() throws {
        let settings = ComputerUseSettings(
            enabled: true,
            backend: .agentDesktop,
            permissionPolicy: .auto,
            commandTimeoutSeconds: 30,
            includeScreenshots: true
        )
        let config = try XCTUnwrap(ComputerUseService.computerUseMCPConfig(
            settings: settings,
            helperOverride: URL(fileURLWithPath: "/tmp/GrokBuildComputerUseMCP"),
            agentDesktopOverride: URL(fileURLWithPath: "/tmp/agent-desktop")
        ))
        let env = try XCTUnwrap(config.jsonObject["env"] as? [[String: String]])
        XCTAssertEqual(Set(env.compactMap { $0["name"] }), ComputerUseHelperEnvironment.allKeys)
    }

    func testSnapshotArgsMapFlagsAndDefaultCompact() throws {
        XCTAssertEqual(try buildSnapshotArgs([:]), ["snapshot", "--compact"])
        XCTAssertEqual(
            try buildSnapshotArgs([
                "app": "Safari",
                "interactive_only": true,
                "compact": false,
                "include_bounds": true,
                "max_depth": 4,
            ]),
            ["snapshot", "--app", "Safari", "-i", "--include-bounds", "--max-depth", "4"]
        )
    }

    func testScreenshotArgsAppendSavePathPositionally() throws {
        XCTAssertEqual(
            try buildScreenshotArgs(["app": "Finder", "save_path": "/tmp/shot.png"]),
            ["screenshot", "--app", "Finder", "/tmp/shot.png"]
        )
    }

    func testRefTypeGetPressAndWaitArgs() throws {
        XCTAssertEqual(
            try buildRefCommand("click", args: ["ref": "@e3", "snapshot": "s1"]),
            ["click", "@e3", "--snapshot", "s1"]
        )
        XCTAssertEqual(
            try buildTypeArgs(["ref": "@e5", "text": "hello"]),
            ["type", "@e5", "hello"]
        )
        XCTAssertEqual(try buildPressArgs(["combo": "cmd+s"]), ["press", "cmd+s"])
        XCTAssertEqual(
            try buildGetArgs(["ref": "@e3", "property": "value"]),
            ["get", "@e3", "--property", "value"]
        )
        XCTAssertEqual(try buildWaitArgs(["milliseconds": 250]), ["wait", "250"])
        XCTAssertEqual(
            try buildWaitArgs(["element": "@e2", "predicate": "actionable", "timeout": 5000]),
            ["wait", "--element", "@e2", "--predicate", "actionable", "--timeout", "5000"]
        )
        XCTAssertThrowsError(try buildTypeArgs(["ref": "@e5"]))
        XCTAssertThrowsError(try buildRefCommand("click", args: [:]))
    }

    func testActionPolicyOnlyDenyBlocks() {
        XCTAssertNoThrow(try enforceActionPolicy("click", policy: "auto"))
        XCTAssertNoThrow(try enforceActionPolicy("click", policy: "ask"))
        XCTAssertThrowsError(try enforceActionPolicy("click", policy: "deny")) { error in
            XCTAssertTrue(error.localizedDescription.contains("blocked"))
        }
    }

    func testMappedErrorExtractsStructuredAgentDesktopErrors() {
        let mapped = mappedError(
            from: #"{"ok":false,"error":{"code":"AX_DENIED","message":"Accessibility is not granted.","suggestion":"Enable it in System Settings."}}"#,
            fallback: 1
        )
        XCTAssertEqual(mapped, "AX_DENIED: Accessibility is not granted.: Enable it in System Settings.")

        XCTAssertEqual(mappedError(from: "", fallback: 3), "agent-desktop exited with 3")
        XCTAssertNil(mappedStructuredFailure(from: #"{"ok":true,"data":{}}"#))
        XCTAssertNotNil(mappedStructuredFailure(from: #"{"ok":false,"error":{"message":"nope"}}"#))
    }
}

extension ComputerUseCoreTests {
    /// Requesting is pointless when screenshots are off or the permission is
    /// already granted; macOS only ever shows the prompt once per app.
    func testScreenRecordingRequestGating() {
        XCTAssertTrue(ComputerUseService.shouldRequestScreenRecording(includeScreenshots: true, granted: false))
        XCTAssertFalse(ComputerUseService.shouldRequestScreenRecording(includeScreenshots: true, granted: true))
        XCTAssertFalse(ComputerUseService.shouldRequestScreenRecording(includeScreenshots: false, granted: false))
        XCTAssertFalse(ComputerUseService.shouldRequestScreenRecording(includeScreenshots: false, granted: true))
    }
}
