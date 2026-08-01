import ApplicationServices
import Foundation
import GrokBuildComputerUseCore

// Stdio MCP server bridging grok to the agent-desktop CLI. The tool table,
// argv mapping, policy, and error mapping live in GrokBuildComputerUseCore so
// they stay under test; this file owns process I/O and the JSON-RPC loop.

// The complete environment contract with the app (ComputerUseService builds
// exactly this set; an env-parity test keeps the two in sync).
let agentDesktop = ProcessInfo.processInfo.environment[ComputerUseHelperEnvironment.agentDesktopPath] ?? "agent-desktop"
let permissionPolicy = ProcessInfo.processInfo.environment[ComputerUseHelperEnvironment.policy] ?? "auto"
let commandTimeout = TimeInterval(Int(ProcessInfo.processInfo.environment[ComputerUseHelperEnvironment.timeout] ?? "60") ?? 60)
let includeScreenshots = ProcessInfo.processInfo.environment[ComputerUseHelperEnvironment.screenshots] == "true"

func respond(id: Any?, result: Any? = nil, error: Error? = nil) {
    var message: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id ?? NSNull()
    ]
    if let error {
        message["error"] = [
            "code": -32000,
            "message": error.localizedDescription
        ]
    } else {
        message["result"] = result ?? [:]
    }
    writeJSON(message)
}

func textResult(_ text: String) -> [String: Any] {
    ["content": [["type": "text", "text": text.isEmpty ? "(no output)" : text]]]
}

func writeJSON(_ value: Any) {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let line = String(data: data, encoding: .utf8) else {
        return
    }
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func handle(_ request: [String: Any]) {
    let id = request["id"]
    let method = request["method"] as? String
    let params = request["params"] as? [String: Any] ?? [:]

    do {
        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                "serverInfo": ["name": "grokbuild-computer-use", "version": "0.1.1"],
                "capabilities": ["tools": [:]]
            ])
        case "notifications/initialized":
            return
        case "ping":
            respond(id: id, result: [:])
        case "tools/list":
            respond(id: id, result: ["tools": computerUseTools.map(\.json)])
        case "tools/call":
            let name = params["name"] as? String
            let args = params["arguments"] as? [String: Any] ?? [:]
            respond(id: id, result: try callTool(name: name, args: args))
        default:
            throw HelperError.invalidArguments("Unsupported MCP method: \(method ?? "(nil)")")
        }
    } catch {
        respond(id: id, error: error)
    }
}

func callTool(name: String?, args: [String: Any]) throws -> [String: Any] {
    switch name {
    case "computer_snapshot":
        return textResult(try runAgentDesktop(buildAnchoredSnapshotArgs(args)))
    case "computer_screenshot":
        guard includeScreenshots else {
            throw HelperError.policyDenied("Screenshots are disabled in GrokBuild Computer Use settings.")
        }
        return textResult(try runAgentDesktop(buildScreenshotArgs(args)))
    case "computer_click":
        try enforceActionPolicy("click", policy: permissionPolicy)
        return textResult(try runAgentDesktop(buildRefCommand("click", args: args)))
    case "computer_type":
        try enforceActionPolicy("type", policy: permissionPolicy)
        return textResult(try runAgentDesktop(buildTypeArgs(args)))
    case "computer_press":
        try enforceActionPolicy("press", policy: permissionPolicy)
        return textResult(try runAgentDesktop(buildPressArgs(args)))
    case "computer_close_app":
        try enforceActionPolicy("close-app", policy: permissionPolicy)
        return textResult(try runAgentDesktop(buildCloseAppArgs(args)))
    case "computer_get":
        return textResult(try runAgentDesktop(buildGetArgs(args)))
    case "computer_wait":
        return textResult(try runAgentDesktop(buildWaitArgs(args)))
    case "computer_list_apps":
        return textResult(try runAgentDesktop(["list-apps"]))
    case "computer_list_windows":
        return textResult(try runAgentDesktop(buildListWindowsArgs(args)))
    case "computer_permissions":
        return textResult(try runAgentDesktop(["permissions"]))
    default:
        throw HelperError.invalidArguments("Unknown Computer Use tool: \(name ?? "(nil)")")
    }
}

func buildAnchoredSnapshotArgs(_ args: [String: Any]) throws -> [String] {
    var resolved = args
    let hasWindowID = (args["window_id"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    if !hasWindowID,
       let app = args["app"] as? String,
       !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let windows = try? runAgentDesktop(buildListWindowsArgs(["app": app])),
       let windowID = ComputerWindowSelector.preferredWindowID(fromJSON: windows, appName: app) {
        resolved["window_id"] = windowID
    }
    return try buildSnapshotArgs(resolved)
}

func runAgentDesktop(_ args: [String]) throws -> String {
    let process = Process()
    if agentDesktop.contains("/") {
        process.executableURL = URL(fileURLWithPath: agentDesktop)
        process.arguments = args
    } else {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [agentDesktop] + args
    }

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    // Drain both pipes WHILE the child runs. Accessibility snapshots of dense
    // apps exceed the ~64 KiB pipe buffer; with nobody reading until exit,
    // agent-desktop blocked in write(2) forever and every large snapshot
    // surfaced as a bogus "timed out" error.
    final class OutputBox: @unchecked Sendable {
        var data = Data()
    }
    let outBox = OutputBox()
    let errBox = OutputBox()
    let drainGroup = DispatchGroup()
    drainGroup.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        outBox.data = stdout.fileHandleForReading.readDataToEndOfFile()
        drainGroup.leave()
    }
    drainGroup.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
        drainGroup.leave()
    }

    do {
        try process.run()
    } catch {
        throw HelperError.commandFailed("Failed to launch agent-desktop: \(error.localizedDescription)")
    }

    let deadline = Date().addingTimeInterval(commandTimeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()
        // SIGTERM can be ignored; escalate so no agent-desktop orphan
        // survives a timeout.
        let killDeadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < killDeadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        _ = drainGroup.wait(timeout: .now() + 2)
        throw HelperError.timeout
    }
    process.waitUntilExit()
    _ = drainGroup.wait(timeout: .now() + 5)

    let output = String(decoding: outBox.data, as: UTF8.self)
    let error = String(decoding: errBox.data, as: UTF8.self)
    let text = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? error : output

    if process.terminationStatus != 0 {
        throw HelperError.commandFailed(mappedError(from: text, fallback: process.terminationStatus))
    }
    if let mapped = mappedStructuredFailure(from: text) {
        throw HelperError.commandFailed(mapped)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func printPermissionsProbe() {
    var agentDesktopOutput = ""
    var agentDesktopGranted = false
    do {
        agentDesktopOutput = try runAgentDesktop(["permissions"])
        if let data = agentDesktopOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let payload = (json["data"] as? [String: Any]) ?? json
            if let granted = payload["granted"] as? Bool {
                agentDesktopGranted = granted
            } else if let accessibility = payload["accessibility"] as? [String: Any],
                      let state = accessibility["state"] as? String {
                agentDesktopGranted = state.lowercased() == "granted"
            }
        }
    } catch {
        agentDesktopOutput = error.localizedDescription
    }

    let payload: [String: Any] = [
        "ok": true,
        "helper_accessibility_granted": AXIsProcessTrusted(),
        "helper_executable": ProcessInfo.processInfo.arguments[0],
        "agent_desktop_granted": agentDesktopGranted,
        "agent_desktop_output": agentDesktopOutput
    ]

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
          let text = String(data: data, encoding: .utf8) else {
        fputs("{\"ok\":false,\"error\":\"Failed to encode permissions probe.\"}\n", stderr)
        exit(1)
    }
    print(text)
}

func requestPermissionsProbe() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)

    var agentDesktopOutput = ""
    do {
        agentDesktopOutput = try runAgentDesktop(["permissions", "--request"])
    } catch {
        agentDesktopOutput = error.localizedDescription
    }

    let payload: [String: Any] = [
        "ok": true,
        "helper_accessibility_granted": AXIsProcessTrusted(),
        "helper_executable": ProcessInfo.processInfo.arguments[0],
        "agent_desktop_output": agentDesktopOutput
    ]

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
          let text = String(data: data, encoding: .utf8) else {
        fputs("{\"ok\":false,\"error\":\"Failed to encode permissions request.\"}\n", stderr)
        exit(1)
    }
    print(text)
}

func main() {
    if CommandLine.arguments.contains("--check-permissions") {
        printPermissionsProbe()
        return
    }
    if CommandLine.arguments.contains("--request-permissions") {
        requestPermissionsProbe()
        return
    }

    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        do {
            guard let data = trimmed.data(using: .utf8),
                  let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HelperError.invalidArguments("Invalid JSON-RPC request.")
            }
            handle(request)
        } catch {
            respond(id: nil, error: error)
        }
    }
}

main()
