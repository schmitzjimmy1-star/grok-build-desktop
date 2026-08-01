import XCTest
@testable import GrokBuild
@testable import GrokBuildComputerUseCore

/// Tests the helper's contract directly — the executable target itself cannot
/// be imported, which is why this logic lives in GrokBuildComputerUseCore.
final class ComputerUseCoreTests: XCTestCase {
    func testToolTableExposesAllElevenTools() {
        XCTAssertEqual(computerUseTools.map(\.name), [
            "computer_snapshot",
            "computer_screenshot",
            "computer_click",
            "computer_type",
            "computer_press",
            "computer_close_app",
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
        XCTAssertEqual(try buildCloseAppArgs(["app": "Calculator"]), ["close-app", "Calculator"])
        XCTAssertEqual(
            try buildCloseAppArgs(["app": "Calculator", "force": true]),
            ["close-app", "Calculator", "--force"]
        )
        XCTAssertThrowsError(try buildCloseAppArgs(["app": "  "]))
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

    func testWindowSelectorRejectsHiddenAndHelperWindowsForCalculator() {
        let json = #"""
        {"ok":true,"data":{"windows":[
          {"id":"w-9169","title":"Calculator","visible":false,"bounds":{"width":1440,"height":30}},
          {"id":"w-9168","title":"Calculator","visible":false,"bounds":{"width":1440,"height":30}},
          {"id":"w-9167","title":"Calculator","visible":false,"bounds":{"width":1440,"height":30}},
          {"id":"w-9166","title":"Calculator","visible":false,"bounds":{"width":1440,"height":30}},
          {"id":"w-9164","title":"Window","visible":true,"bounds":{"width":66,"height":20}},
          {"id":"w-9162","title":"Calculator","visible":true,"bounds":{"width":230,"height":408}}
        ]}}
        """#

        XCTAssertEqual(
            ComputerWindowSelector.preferredWindowID(fromJSON: json, appName: "Calculator"),
            "w-9162"
        )
    }

    func testWindowSelectorPrefersFocusedThenAreaAndHasStableTieBreak() {
        let focused = #"{"ok":true,"data":{"windows":[{"id":"large","title":"Editor","visible":true,"bounds":{"width":900,"height":700}},{"id":"focused","title":"Window","visible":true,"is_focused":true,"bounds":{"width":200,"height":100}}]}}"#
        XCTAssertEqual(
            ComputerWindowSelector.preferredWindowID(fromJSON: focused, appName: "Editor"),
            "focused"
        )

        let tied = #"{"ok":true,"data":{"windows":[{"id":"b","title":"Editor","visible":true,"bounds":{"width":100,"height":100}},{"id":"a","title":"Editor","visible":true,"bounds":{"width":100,"height":100}}]}}"#
        XCTAssertEqual(
            ComputerWindowSelector.preferredWindowID(fromJSON: tied, appName: "Editor"),
            "a"
        )

        let hidden = #"{"ok":true,"data":{"windows":[{"id":"zero","visible":true,"bounds":{"width":0,"height":20}},{"id":"hidden","visible":false,"bounds":{"width":200,"height":200}}]}}"#
        XCTAssertNil(ComputerWindowSelector.preferredWindowID(fromJSON: hidden, appName: "Editor"))
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
