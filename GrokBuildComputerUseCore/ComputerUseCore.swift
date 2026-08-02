import Foundation

// Pure logic shared by the GrokBuildComputerUseMCP executable, the app, and
// the tests. The helper executable target cannot be imported by tests, so
// everything that defines the helper's contract — tool table, argv mapping,
// policy, error mapping, environment keys — lives here where it can be
// exercised directly.

/// The complete environment contract between GrokBuild and the helper.
public enum ComputerUseHelperEnvironment {
    public static let agentDesktopPath = "AGENT_DESKTOP_PATH"
    public static let policy = "GROKBUILD_COMPUTER_USE_POLICY"
    public static let timeout = "GROKBUILD_COMPUTER_USE_TIMEOUT"
    public static let screenshots = "GROKBUILD_COMPUTER_USE_SCREENSHOTS"

    public static let allKeys: Set<String> = [agentDesktopPath, policy, timeout, screenshots]
}

public struct MCPTool {
    public let name: String
    public let description: String
    public let inputSchema: [String: Any]

    public init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public var json: [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": inputSchema
        ]
    }
}

public enum HelperError: LocalizedError {
    case invalidArguments(String)
    case policyDenied(String)
    case commandFailed(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): return message
        case .policyDenied(let message): return message
        case .commandFailed(let message): return message
        case .timeout: return "agent-desktop command timed out."
        }
    }
}

public let computerUseTools: [MCPTool] = [
    MCPTool(
        name: "computer_snapshot",
        description: "Return an accessibility-tree snapshot with deterministic refs for desktop UI automation.",
        inputSchema: objectSchema(
            properties: [
                "app": stringSchema("Application name, for example Safari or Finder."),
                "window_id": stringSchema("Optional window id to snapshot."),
                "root": stringSchema("Optional ref to drill into, for example @e3."),
                "snapshot": stringSchema("Optional snapshot id to resolve root refs against."),
                "surface": stringSchema("Surface type: window, focused, menu, menubar, sheet, popover, or alert."),
                "interactive_only": boolSchema("Only include interactive elements."),
                "compact": boolSchema("Omit empty structural nodes. Defaults to true."),
                "skeleton": boolSchema("Return a shallow skeleton for dense apps."),
                "include_bounds": boolSchema("Include element bounds."),
                "max_depth": intSchema("Maximum accessibility tree depth.")
            ]
        )
    ),
    MCPTool(
        name: "computer_screenshot",
        description: "Capture a desktop screenshot through agent-desktop. Requires screenshots enabled in GrokBuild settings.",
        inputSchema: objectSchema(
            properties: [
                "app": stringSchema("Optional application name."),
                "window_id": stringSchema("Optional window id."),
                "save_path": stringSchema("Optional file path where agent-desktop should save the image.")
            ]
        )
    ),
    MCPTool(
        name: "computer_click",
        description: "Click an accessibility ref from a recent computer_snapshot.",
        inputSchema: objectSchema(
            properties: [
                "ref": stringSchema("Element ref, for example @e3."),
                "snapshot": stringSchema("Optional snapshot id.")
            ],
            required: ["ref"]
        )
    ),
    MCPTool(
        name: "computer_type",
        description: "Type text into an accessibility ref from a recent computer_snapshot.",
        inputSchema: objectSchema(
            properties: [
                "ref": stringSchema("Element ref, for example @e5."),
                "text": stringSchema("Text to type."),
                "snapshot": stringSchema("Optional snapshot id.")
            ],
            required: ["ref", "text"]
        )
    ),
    MCPTool(
        name: "computer_press",
        description: "Press a keyboard key or shortcut, for example cmd+s, escape, or return.",
        inputSchema: objectSchema(
            properties: [
                "combo": stringSchema("Key or shortcut to press.")
            ],
            required: ["combo"]
        )
    ),
    MCPTool(
        name: "computer_close_app",
        description: "Close one explicitly named application. Uses graceful quit by default. Set force only when the user explicitly accepts termination that may discard unsaved work.",
        inputSchema: objectSchema(
            properties: [
                "app": stringSchema("Exact application name to close."),
                "force": boolSchema("Explicitly terminate the app if graceful quit cannot complete. May discard unsaved work. Defaults to false.")
            ],
            required: ["app"]
        )
    ),
    MCPTool(
        name: "computer_get",
        description: "Read a property from an accessibility ref.",
        inputSchema: objectSchema(
            properties: [
                "ref": stringSchema("Element ref, for example @e3."),
                "property": stringSchema("Property to read, for example value."),
                "snapshot": stringSchema("Optional snapshot id.")
            ],
            required: ["ref", "property"]
        )
    ),
    MCPTool(
        name: "computer_wait",
        description: "Wait for time, element actionability, text, window, menu, or notification state.",
        inputSchema: objectSchema(
            properties: [
                "milliseconds": intSchema("Plain wait duration in milliseconds."),
                "element": stringSchema("Optional element ref to wait on."),
                "predicate": stringSchema("Optional predicate such as actionable or value."),
                "value": stringSchema("Optional expected predicate value."),
                "timeout": intSchema("Timeout in milliseconds."),
                "text": stringSchema("Optional text to wait for."),
                "app": stringSchema("Optional app name."),
                "window": stringSchema("Optional window title."),
                "menu": boolSchema("Wait for an open menu.")
            ]
        )
    ),
    MCPTool(
        name: "computer_list_apps",
        description: "List running GUI applications.",
        inputSchema: objectSchema()
    ),
    MCPTool(
        name: "computer_list_windows",
        description: "List visible windows, optionally for a specific app.",
        inputSchema: objectSchema(
            properties: [
                "app": stringSchema("Optional application name.")
            ]
        )
    ),
    MCPTool(
        name: "computer_permissions",
        description: "Report macOS permissions required by agent-desktop.",
        inputSchema: objectSchema()
    )
]

func objectSchema(properties: [String: Any] = [:], required: [String] = []) -> [String: Any] {
    var schema: [String: Any] = [
        "type": "object",
        "properties": properties
    ]
    if !required.isEmpty {
        schema["required"] = required
    }
    return schema
}

func stringSchema(_ description: String) -> [String: Any] {
    ["type": "string", "description": description]
}

func boolSchema(_ description: String) -> [String: Any] {
    ["type": "boolean", "description": description]
}

func intSchema(_ description: String) -> [String: Any] {
    ["type": "integer", "description": description]
}

/// Only "deny" blocks; anything else allows. Grok's own permission flow is
/// the approval surface — this is a local hard stop, not a prompt.
public func enforceActionPolicy(_ action: String, policy: String) throws {
    if policy == "deny" {
        throw HelperError.policyDenied("Computer Use action '\(action)' is blocked by GrokBuild's local policy.")
    }
}

public func buildSnapshotArgs(_ args: [String: Any]) throws -> [String] {
    var command = ["snapshot"]
    appendString(args, "app", flag: "--app", to: &command)
    appendString(args, "window_id", flag: "--window-id", to: &command)
    appendString(args, "root", flag: "--root", to: &command)
    appendString(args, "snapshot", flag: "--snapshot", to: &command)
    appendString(args, "surface", flag: "--surface", to: &command)
    appendBool(args, "interactive_only", flag: "-i", to: &command)
    appendBool(args, "compact", flag: "--compact", defaultValue: true, to: &command)
    appendBool(args, "skeleton", flag: "--skeleton", to: &command)
    appendBool(args, "include_bounds", flag: "--include-bounds", to: &command)
    appendInt(args, "max_depth", flag: "--max-depth", to: &command)
    return command
}

public func buildScreenshotArgs(_ args: [String: Any]) throws -> [String] {
    var command = ["screenshot"]
    appendString(args, "app", flag: "--app", to: &command)
    appendString(args, "window_id", flag: "--window-id", to: &command)
    if let savePath = args["save_path"] as? String,
       !savePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        command.append(savePath)
    }
    return command
}

public func buildRefCommand(_ commandName: String, args: [String: Any]) throws -> [String] {
    var command = [commandName, try requiredString(args, "ref")]
    appendString(args, "snapshot", flag: "--snapshot", to: &command)
    return command
}

public func buildTypeArgs(_ args: [String: Any]) throws -> [String] {
    var command = ["type", try requiredString(args, "ref"), try requiredString(args, "text")]
    appendString(args, "snapshot", flag: "--snapshot", to: &command)
    return command
}

public func buildPressArgs(_ args: [String: Any]) throws -> [String] {
    ["press", try requiredString(args, "combo")]
}

public func buildCloseAppArgs(_ args: [String: Any]) throws -> [String] {
    var command = ["close-app", try requiredString(args, "app")]
    appendBool(args, "force", flag: "--force", to: &command)
    return command
}

public func buildGetArgs(_ args: [String: Any]) throws -> [String] {
    var command = ["get", try requiredString(args, "ref"), "--property", try requiredString(args, "property")]
    appendString(args, "snapshot", flag: "--snapshot", to: &command)
    return command
}

public func buildWaitArgs(_ args: [String: Any]) throws -> [String] {
    if let milliseconds = args["milliseconds"] as? Int {
        return ["wait", String(milliseconds)]
    }
    var command = ["wait"]
    appendString(args, "element", flag: "--element", to: &command)
    appendString(args, "predicate", flag: "--predicate", to: &command)
    appendString(args, "value", flag: "--value", to: &command)
    appendInt(args, "timeout", flag: "--timeout", to: &command)
    appendString(args, "text", flag: "--text", to: &command)
    appendString(args, "app", flag: "--app", to: &command)
    appendString(args, "window", flag: "--window", to: &command)
    appendBool(args, "menu", flag: "--menu", to: &command)
    return command
}

public func buildListWindowsArgs(_ args: [String: Any]) throws -> [String] {
    var command = ["list-windows"]
    appendString(args, "app", flag: "--app", to: &command)
    return command
}

/// Selects the main visible standard window from agent-desktop's structured
/// `list-windows` result. The CLI can include hidden menu/helper windows before the
/// real app window, so wire order is never treated as priority.
public enum ComputerWindowSelector {
    private struct Candidate {
        let id: String
        let focused: Bool
        let area: Double
        let titleQuality: Int
    }

    public static func preferredWindowID(fromJSON text: String, appName: String) -> String? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["ok"] as? Bool) != false else { return nil }
        let payload = root["data"]
        let rows: [[String: Any]]
        if let array = payload as? [[String: Any]] {
            rows = array
        } else if let dictionary = payload as? [String: Any] {
            rows = dictionary["windows"] as? [[String: Any]] ?? []
        } else {
            rows = []
        }

        let candidates = rows.compactMap { row -> Candidate? in
            guard (row["visible"] as? Bool ?? row["is_visible"] as? Bool ?? true),
                  let id = nonEmptyString(row["id"] ?? row["window_id"]) else { return nil }
            let bounds = row["bounds"] as? [String: Any]
                ?? row["frame"] as? [String: Any]
                ?? [:]
            let width = number(bounds["width"] ?? row["width"])
            let height = number(bounds["height"] ?? row["height"])
            guard width > 0, height > 0 else { return nil }
            let title = nonEmptyString(row["title"] ?? row["name"]) ?? ""
            let quality: Int
            if title.caseInsensitiveCompare(appName) == .orderedSame {
                quality = 2
            } else if title.isEmpty || title.caseInsensitiveCompare("Window") == .orderedSame {
                quality = 0
            } else {
                quality = 1
            }
            return Candidate(
                id: id,
                focused: row["is_focused"] as? Bool ?? row["focused"] as? Bool ?? false,
                area: width * height,
                titleQuality: quality
            )
        }

        return candidates.sorted {
            if $0.focused != $1.focused { return $0.focused && !$1.focused }
            if $0.area != $1.area { return $0.area > $1.area }
            if $0.titleQuality != $1.titleQuality { return $0.titleQuality > $1.titleQuality }
            return $0.id < $1.id
        }.first?.id
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func number(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
    }
}

public func requiredString(_ args: [String: Any], _ key: String) throws -> String {
    guard let value = args[key] as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw HelperError.invalidArguments("Missing required argument: \(key)")
    }
    return value
}

func appendString(_ args: [String: Any], _ key: String, flag: String, to command: inout [String]) {
    guard let value = args[key] as? String,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    command += [flag, value]
}

func appendInt(_ args: [String: Any], _ key: String, flag: String, to command: inout [String]) {
    guard let value = args[key] as? Int else { return }
    command += [flag, String(value)]
}

func appendBool(_ args: [String: Any], _ key: String, flag: String, defaultValue: Bool = false, to command: inout [String]) {
    let value = args[key] as? Bool ?? defaultValue
    if value {
        command.append(flag)
    }
}

public func mappedStructuredFailure(from text: String) -> String? {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ok = json["ok"] as? Bool,
          ok == false else {
        return nil
    }
    return mappedError(from: text, fallback: 1)
}

public func mappedError(from text: String, fallback: Int32) -> String {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let error = json["error"] as? [String: Any] else {
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "agent-desktop exited with \(fallback)"
            : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let code = error["code"] as? String ?? "AGENT_DESKTOP_ERROR"
    let message = error["message"] as? String ?? "agent-desktop command failed."
    let suggestion = error["suggestion"] as? String
    return [code, message, suggestion].compactMap { $0 }.joined(separator: ": ")
}
