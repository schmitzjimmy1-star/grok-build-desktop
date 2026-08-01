import Foundation

struct GrokCLIResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var combinedOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let value = data
        lock.unlock()
        return value
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Shared bounded-kill for one-shot helper subprocesses: SIGTERM at the deadline,
/// SIGKILL two seconds later if the child ignored it. Keeps a hung `grok`, `git`,
/// or `agent-browser` invocation from wedging its caller forever.
enum ProcessKillSchedule {
    static func schedule(process: Process, after timeout: TimeInterval, flag: LockedFlag) {
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak process] in
            guard let process, process.isRunning else { return }
            flag.set()
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak process] in
                guard let process, process.isRunning else { return }
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

/// The one deadlock-safe subprocess runner. Every one-shot helper (`grok`, `git`,
/// `agent-browser`, updater `codesign`/`ditto`) drains through here so the
/// >64KiB-pipe-buffer deadlock, the SIGTERM→SIGKILL timeout, and task-cancellation
/// teardown live in exactly one place. Configure the process (executable, args, cwd,
/// env) and assign the pipes to its standard streams before calling; for a merged
/// stream, assign one pipe to both `standardOutput` and `standardError` and pass it as
/// `stdout` with `stderr` nil.
enum BoundedProcess {
    struct Result: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data
        let timedOut: Bool
    }

    static func run(
        _ process: Process,
        stdout: Pipe? = nil,
        stderr: Pipe? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Result {
        let outData = LockedData()
        let errData = LockedData()
        let timedOut = LockedFlag()
        stdout?.fileHandleForReading.readabilityHandler = { outData.append($0.availableData) }
        stderr?.fileHandleForReading.readabilityHandler = { errData.append($0.availableData) }

        func clearHandlers() {
            stdout?.fileHandleForReading.readabilityHandler = nil
            stderr?.fileHandleForReading.readabilityHandler = nil
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in
                    if let stdout {
                        stdout.fileHandleForReading.readabilityHandler = nil
                        outData.append(stdout.fileHandleForReading.readDataToEndOfFile())
                    }
                    if let stderr {
                        stderr.fileHandleForReading.readabilityHandler = nil
                        errData.append(stderr.fileHandleForReading.readDataToEndOfFile())
                    }
                    continuation.resume()
                }
                do {
                    try process.run()
                } catch {
                    clearHandlers()
                    continuation.resume(throwing: error)
                    return
                }
                if let timeout {
                    ProcessKillSchedule.schedule(process: process, after: timeout, flag: timedOut)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }

        return Result(
            status: process.terminationStatus,
            stdout: outData.snapshot(),
            stderr: errData.snapshot(),
            timedOut: timedOut.isSet
        )
    }
}

struct GrokPluginInfo: Identifiable, Hashable, Sendable {
    let id: String
    let status: String
    let name: String
    let version: String
    let scope: String
    let source: String
    let marketplace: String
    let isEnabled: Bool
    let description: String
    let componentSummary: String

    init(dictionary: [String: Any]) {
        let name = Self.stringValue(dictionary, keys: ["name", "plugin_name", "id"]) ?? "Unknown"
        self.id = Self.stringValue(dictionary, keys: ["id"]) ?? name
        self.status = Self.stringValue(dictionary, keys: ["status"]) ?? ""
        self.name = name
        self.version = Self.stringValue(dictionary, keys: ["version"]) ?? ""
        self.scope = Self.stringValue(dictionary, keys: ["scope", "location", "kind"]) ?? ""
        self.source = Self.stringValue(dictionary, keys: ["source", "path", "url"]) ?? ""
        self.marketplace = Self.stringValue(dictionary, keys: ["marketplace"]) ?? ""
        self.isEnabled = Self.boolValue(dictionary, keys: ["enabled", "is_enabled"]) ?? true
        self.description = Self.stringValue(dictionary, keys: ["description"]) ?? ""

        let components = dictionary["components"] as? [String: Any] ?? dictionary
        let componentKeys = ["skills", "commands", "agents", "hooks", "mcp_servers", "mcps", "lsp_servers"]
        let parts = componentKeys.compactMap { key -> String? in
            let countKey: String
            switch key {
            case "mcp_servers", "mcps": countKey = "mcp_count"
            case "lsp_servers": countKey = "lsp_count"
            default: countKey = "\(key)_count"
            }
            let directCount = dictionary[countKey]
            let value = components[key] ?? dictionary[key] ?? directCount
            guard let value else { return nil }
            if let array = value as? [Any], !array.isEmpty {
                return "\(key.replacingOccurrences(of: "_", with: " ")): \(array.count)"
            }
            if let count = value as? Int, count > 0 {
                return "\(key.replacingOccurrences(of: "_", with: " ")): \(count)"
            }
            return nil
        }
        self.componentSummary = parts.joined(separator: " · ")
    }

    private static func stringValue(_ dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
            if dictionary[key] is NSNull { continue }
            if let value = dictionary[key] { return "\(value)" }
        }
        return nil
    }

    private static func boolValue(_ dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool { return value }
            if let value = dictionary[key] as? String { return ["true", "yes", "enabled"].contains(value.lowercased()) }
        }
        return nil
    }
}

struct GrokMarketplaceSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: String
    let location: String

    init(dictionary: [String: Any]) {
        name = dictionary["name"] as? String ?? "Unknown"
        kind = dictionary["kind"] as? String ?? ""
        if let source = dictionary["source"] as? [String: Any] {
            location = source["url"] as? String ?? source["path"] as? String ?? ""
        } else {
            location = dictionary["url"] as? String ?? dictionary["path"] as? String ?? ""
        }
        id = "\(name)-\(location)"
    }
}

struct GrokHookInfo: Identifiable, Hashable, Sendable {
    let id: String
    let event: String
    let hookType: String
    let target: String
    let matcher: String
    let sourceType: String
    let sourcePath: String
    let pluginName: String
    let vendor: String

    init(dictionary: [String: Any]) {
        event = dictionary["event"] as? String ?? ""
        hookType = dictionary["hookType"] as? String ?? dictionary["hook_type"] as? String ?? ""
        target = dictionary["target"] as? String ?? ""
        matcher = dictionary["matcher"] as? String ?? ""
        vendor = dictionary["vendor"] as? String ?? ""

        let source = dictionary["source"] as? [String: Any] ?? [:]
        sourceType = source["type"] as? String ?? ""
        sourcePath = source["path"] as? String ?? ""
        pluginName = source["plugin_name"] as? String ?? source["pluginName"] as? String ?? ""
        id = [event, hookType, target, sourcePath, pluginName].joined(separator: "|")
    }
}

struct GrokSkillInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let sourceType: String
    let sourcePath: String
    let pluginName: String
    let userInvocable: Bool

    init(dictionary: [String: Any]) {
        name = dictionary["name"] as? String ?? "Unknown"
        description = dictionary["description"] as? String ?? ""
        userInvocable = dictionary["userInvocable"] as? Bool ?? dictionary["user_invocable"] as? Bool ?? false

        let source = dictionary["source"] as? [String: Any] ?? [:]
        sourceType = source["type"] as? String ?? ""
        sourcePath = source["path"] as? String ?? ""
        pluginName = source["plugin_name"] as? String ?? source["pluginName"] as? String ?? ""
        id = [name, sourcePath, pluginName].joined(separator: "|")
    }
}

struct GrokAgentInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let sourceType: String
    let sourcePath: String
    let pluginName: String

    init(dictionary: [String: Any]) {
        name = dictionary["name"] as? String ?? "Unknown"
        description = dictionary["description"] as? String ?? ""

        let source = dictionary["source"] as? [String: Any] ?? [:]
        sourceType = source["type"] as? String ?? ""
        sourcePath = source["path"] as? String ?? ""
        pluginName = source["plugin_name"] as? String ?? source["pluginName"] as? String ?? ""
        id = [name, sourceType, pluginName, sourcePath].joined(separator: "|")
    }
}

struct GrokMCPServerInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let transport: String
    let target: String
    let source: String
    let isEnabled: Bool?

    init(dictionary: [String: Any]) {
        name = dictionary["name"] as? String ?? "Unknown"
        id = dictionary["id"] as? String ?? name
        transport = dictionary["transport"] as? String ?? dictionary["type"] as? String ?? ""
        target = dictionary["target"] as? String ?? dictionary["url"] as? String ?? dictionary["command"] as? String ?? ""
        source = dictionary["source"] as? String ?? dictionary["scope"] as? String ?? ""
        isEnabled = dictionary["enabled"] as? Bool
    }
}

struct GrokMCPDoctorReport: Sendable {
    struct Server: Identifiable, Hashable, Sendable {
        struct Check: Hashable, Sendable {
            let label: String
            let passed: Bool
            let detail: String
            let hint: String
        }

        let id: String
        let name: String
        let transport: String
        let target: String
        let source: String
        let healthy: Bool
        let checks: [Check]
    }

    let healthyCount: Int
    let failingCount: Int
    let servers: [Server]

    init(dictionary: [String: Any]) {
        healthyCount = dictionary["healthy_count"] as? Int ?? 0
        failingCount = dictionary["failing_count"] as? Int ?? 0
        servers = (dictionary["servers"] as? [[String: Any]] ?? []).map { server in
            Server(
                id: server["name"] as? String ?? UUID().uuidString,
                name: server["name"] as? String ?? "Unknown",
                transport: server["transport"] as? String ?? "",
                target: server["target"] as? String ?? "",
                source: server["source"] as? String ?? "",
                healthy: server["healthy"] as? Bool ?? false,
                checks: (server["checks"] as? [[String: Any]] ?? []).map { check in
                    Server.Check(
                        label: check["label"] as? String ?? "",
                        passed: check["passed"] as? Bool ?? false,
                        detail: check["detail"] as? String ?? "",
                        hint: check["hint"] as? String ?? ""
                    )
                }
            )
        }
    }
}

struct GrokModelInfo: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let isDefault: Bool
}

struct GrokSessionInfo: Identifiable, Hashable, Sendable {
    let id: String
    let created: String
    let updated: String
    let status: String
    let summary: String

    static func parseListOutput(_ output: String) -> [GrokSessionInfo] {
        output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 36 else { return nil }
            let sessionID = String(trimmed.prefix(36))
            guard sessionID.range(of: #"^[0-9a-fA-F-]{36}$"#, options: .regularExpression) != nil else { return nil }

            let rest = trimmed.dropFirst(36).trimmingCharacters(in: .whitespaces)
            let pieces = rest.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard pieces.count >= 3 else { return nil }
            // The CLI prints a literal "(no summary)" placeholder; normalize it to empty so
            // callers can treat "has a summary" as a simple non-empty check.
            let rawSummary = pieces.count > 3 ? String(pieces[3]).trimmingCharacters(in: .whitespaces) : ""
            let summary = rawSummary.caseInsensitiveCompare("(no summary)") == .orderedSame ? "" : rawSummary
            return GrokSessionInfo(
                id: sessionID,
                created: String(pieces[0]),
                updated: String(pieces[1]),
                status: String(pieces[2]),
                summary: summary
            )
        }
    }
}

struct GrokPermissionSettings: Sendable {
    var permissionMode: String
    var sandboxProfile: String
    var reasoningEffort: String
    var disableWebSearch: Bool
    var noSubagents: Bool
    var allowRules: String
    var denyRules: String
    /// Session agent selection passed to `grok --agent`. Empty = grok's default agent;
    /// any other value is a discovered agent name (see `GrokAgentProfiles`).
    var selectedAgent: String
    /// Opt-in cross-session memory (experimental). `true` → `--experimental-memory`,
    /// `false` → `--no-memory` (memory is disabled by default; see `MemoryStore`).
    var memoryEnabled: Bool

    static let defaults = GrokPermissionSettings(
        permissionMode: "default",
        sandboxProfile: "",
        reasoningEffort: "",
        disableWebSearch: false,
        noSubagents: false,
        allowRules: "",
        denyRules: "",
        selectedAgent: "",
        memoryEnabled: false
    )
}

/// User-facing permission choices for an interactive GrokBuild work session.
///
/// The grok CLI also exposes `dontAsk`, but its documented behavior is to silently
/// deny unmatched tools for headless/CI runs. Calling that mode "Don't ask" in an
/// interactive desktop app implied the opposite — that work would continue without
/// interruptions. Keep the raw CLI value available, but label it honestly and route
/// the interactive always-approve choice through the dedicated `--always-approve`
/// flag.
enum GrokPermissionMode: String, CaseIterable, Identifiable, Sendable {
    case ask = "default"
    case auto
    case alwaysApprove
    case acceptEdits
    case denyUnapproved = "dontAsk"
    case plan

    var id: String { rawValue }

    static let interactiveChoices: [GrokPermissionMode] = [.ask, .auto, .alwaysApprove]
    static let advancedChoices: [GrokPermissionMode] = [.acceptEdits, .denyUnapproved, .plan]

    static func normalizedStoredValue(_ value: String) -> String {
        value == "bypassPermissions" ? GrokPermissionMode.alwaysApprove.rawValue : value
    }

    init(storedValue: String) {
        self = GrokPermissionMode(rawValue: Self.normalizedStoredValue(storedValue)) ?? .ask
    }

    var displayName: String {
        switch self {
        case .ask: return "Ask"
        case .auto: return "Auto"
        case .alwaysApprove: return "Always approve"
        case .acceptEdits: return "Accept edits"
        case .denyUnapproved: return "Deny unapproved (CI)"
        case .plan: return "Plan"
        }
    }

    var explanation: String {
        switch self {
        case .ask:
            return "Prompt for tool calls that are not already covered by an allow rule."
        case .auto:
            return "Let Grok classify safe tools automatically; dangerous actions may still ask."
        case .alwaysApprove:
            return "Run tool calls without approval prompts. Deny rules, hooks, and the sandbox still apply."
        case .acceptEdits:
            return "Approve file edits automatically but continue prompting for shell commands."
        case .denyUnapproved:
            return "Silently deny tools without an explicit allow rule. Intended for headless or CI work."
        case .plan:
            return "Keep the session in planning-first permission behavior until the plan is approved."
        }
    }
}

enum GrokPermissionLaunchArguments {
    static func arguments(for storedMode: String?) -> [String] {
        guard let storedMode, !storedMode.isEmpty else { return [] }
        let mode = GrokPermissionMode(storedValue: storedMode)
        switch mode {
        case .ask:
            return []
        case .alwaysApprove:
            return ["--always-approve"]
        default:
            return ["--permission-mode", mode.rawValue]
        }
    }
}

/// Reasoning depth passed to `grok agent --reasoning-effort` (reasoning-capable models only).
enum ReasoningEffortLevel: String, CaseIterable, Identifiable, Sendable {
    case `default` = ""
    case none = "none"
    case minimal = "minimal"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case xhigh = "xhigh"
    case max = "max"

    var id: String { rawValue }

    init(storedValue: String) {
        self = ReasoningEffortLevel(rawValue: storedValue) ?? .default
    }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .none: return "None"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "XHigh"
        case .max: return "Max"
        }
    }

    static let menuCases: [ReasoningEffortLevel] = allCases.filter { $0 != .none }

    /// Filled-dot count for compact composer UI (0 = default/none).
    var dotLevel: Int {
        switch self {
        case .default, .none: return 0
        case .minimal: return 1
        case .low: return 2
        case .medium: return 3
        case .high: return 4
        case .xhigh: return 5
        case .max: return 6
        }
    }

    static let dotPickerLevels: [ReasoningEffortLevel] = [.none, .minimal, .low, .medium, .high, .xhigh]
}

enum ReasoningEffortRestartStrategy: Sendable {
    case restart
    case summarizeAndRestart
}

enum GrokSettingsKeys {
    static let permissionMode = "grokbuild.permissionMode"
    static let sandboxProfile = "grokbuild.sandboxProfile"
    static let reasoningEffort = "grokbuild.reasoningEffort"
    /// Legacy key superseded by `memoryEnabled`; read once by
    /// `LegacySettingsMigration`, never written.
    static let noMemory = "grokbuild.noMemory"
    static let disableWebSearch = "grokbuild.disableWebSearch"
    static let noSubagents = "grokbuild.noSubagents"
    static let allowRules = "grokbuild.allowRules"
    static let denyRules = "grokbuild.denyRules"
    static let selectedAgent = "grokbuild.selectedAgent"
    static let memoryEnabled = "grokbuild.memoryEnabled"
}

final class GrokCLIService {
    enum CLIError: LocalizedError {
        case notFound
        case failed(args: [String], result: GrokCLIResult)
        case invalidJSON(String)
        case timedOut(args: [String], seconds: Int)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Could not locate the `grok` CLI. Set GROK_CLI_PATH or install grok."
            case .failed(let args, let result):
                let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                return "`grok \(args.joined(separator: " "))` failed with exit code \(result.exitCode).\n\(output)"
            case .invalidJSON(let output):
                return "The grok CLI returned output that was not valid JSON.\n\(output)"
            case .timedOut(let args, let seconds):
                return "`grok \(args.joined(separator: " "))` did not finish within \(seconds)s and was terminated."
            }
        }
    }

    func run(
        _ args: [String],
        cwd: URL? = nil,
        allowFailure: Bool = false,
        timeout: TimeInterval? = 300
    ) async throws -> GrokCLIResult {
        guard let cli = Self.locateGrokCLI() else { throw CLIError.notFound }

        let process = Process()
        process.executableURL = cli
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // A hung invocation must not wedge the update scheduler, a Settings pane, or
        // launch restore forever — BoundedProcess owns the drain + timeout + cancellation.
        let outcome = try await BoundedProcess.run(process, stdout: stdout, stderr: stderr, timeout: timeout)

        if outcome.timedOut {
            throw CLIError.timedOut(args: args, seconds: Int(timeout ?? 0))
        }
        let out = String(decoding: outcome.stdout, as: UTF8.self)
        let err = String(decoding: outcome.stderr, as: UTF8.self)
        let result = GrokCLIResult(stdout: out, stderr: err, exitCode: outcome.status)
        if outcome.status != 0 && !allowFailure {
            throw CLIError.failed(args: args, result: result)
        }
        return result
    }

    func listPlugins(includeAvailable: Bool = false) async throws -> [GrokPluginInfo] {
        var args = ["plugin", "list", "--json"]
        if includeAvailable { args.append("--available") }
        let json = try await jsonValue(args)
        return (json as? [[String: Any]] ?? []).map(GrokPluginInfo.init(dictionary:))
    }

    func listMarketplaceSources() async throws -> [GrokMarketplaceSource] {
        let json = try await jsonValue(["plugin", "marketplace", "list", "--json"])
        return (json as? [[String: Any]] ?? []).map(GrokMarketplaceSource.init(dictionary:))
    }

    func listHooks(cwd: URL? = nil) async throws -> [GrokHookInfo] {
        let json = try await jsonValue(["inspect", "--json"], cwd: cwd)
        let dictionary = json as? [String: Any] ?? [:]
        return (dictionary["hooks"] as? [[String: Any]] ?? []).map(GrokHookInfo.init(dictionary:))
    }

    func listSkills(cwd: URL? = nil) async throws -> [GrokSkillInfo] {
        let json = try await jsonValue(["inspect", "--json"], cwd: cwd)
        let dictionary = json as? [String: Any] ?? [:]
        return (dictionary["skills"] as? [[String: Any]] ?? []).map(GrokSkillInfo.init(dictionary:))
    }

    func listAgents(cwd: URL? = nil) async throws -> [GrokAgentInfo] {
        let json = try await jsonValue(["inspect", "--json"], cwd: cwd)
        let dictionary = json as? [String: Any] ?? [:]
        return (dictionary["agents"] as? [[String: Any]] ?? []).map(GrokAgentInfo.init(dictionary:))
    }

    func listExternalCompat(cwd: URL? = nil) async throws -> [GrokExternalCompatInfo] {
        let json = try await jsonValue(["inspect", "--json"], cwd: cwd)
        let dictionary = json as? [String: Any] ?? [:]
        if let compat = dictionary["compat"] as? [[String: Any]] {
            return compat.map(GrokExternalCompatInfo.init(dictionary:))
        }
        if let compat = dictionary["external_compat"] as? [[String: Any]] {
            return compat.map(GrokExternalCompatInfo.init(dictionary:))
        }
        return (dictionary["compat_layers"] as? [[String: Any]] ?? []).map(GrokExternalCompatInfo.init(dictionary:))
    }

    func listAvailablePlugins() async throws -> [GrokPluginInfo] {
        try await listPlugins(includeAvailable: true).filter { $0.status == "available" }
    }

    func pluginDetails(name: String) async throws -> String {
        try await run(["plugin", "details", name]).combinedOutput
    }

    func installPlugin(source: String, trust: Bool) async throws {
        var args = ["plugin", "install", source]
        if trust { args.append("--trust") }
        _ = try await run(args)
    }

    func uninstallPlugin(name: String, keepData: Bool) async throws {
        var args = ["plugin", "uninstall", name, "--confirm"]
        if keepData { args.append("--keep-data") }
        _ = try await run(args)
    }

    func setPlugin(name: String, enabled: Bool) async throws {
        _ = try await run(["plugin", enabled ? "enable" : "disable", name])
    }

    func updatePlugin(name: String?) async throws {
        var args = ["plugin", "update"]
        if let name, !name.isEmpty { args.append(name) }
        _ = try await run(args)
    }

    func addMarketplaceSource(_ source: String) async throws {
        _ = try await run(["plugin", "marketplace", "add", source])
    }

    func removeMarketplaceSource(_ source: String) async throws {
        _ = try await run(["plugin", "marketplace", "remove", source])
    }

    func updateGrokCLI() async throws -> GrokCLIResult {
        // A CLI self-update legitimately downloads; give it a longer bounded window.
        try await run(["update"], allowFailure: true, timeout: 600)
    }

    func listMCPServers() async throws -> [GrokMCPServerInfo] {
        let json = try await jsonValue(["mcp", "list", "--json"])
        return (json as? [[String: Any]] ?? []).map(GrokMCPServerInfo.init(dictionary:))
    }

    func mcpDoctor(name: String? = nil) async throws -> GrokMCPDoctorReport {
        var args = ["mcp", "doctor", "--json"]
        if let name, !name.isEmpty { args.append(name) }
        let json = try await jsonValue(args, allowFailure: true)
        return GrokMCPDoctorReport(dictionary: json as? [String: Any] ?? [:])
    }

    func addMCPServer(name: String, transport: String, target: String, scope: String) async throws {
        var args = ["mcp", "add", "--transport", transport, "--scope", scope, name]
        args += target.split(separator: " ").map(String.init)
        _ = try await run(args)
    }

    func removeMCPServer(name: String) async throws {
        _ = try await run(["mcp", "remove", name])
    }

    func listModels() async throws -> [GrokModelInfo] {
        let result = try await run(["models"])
        var models: [GrokModelInfo] = []
        for line in result.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { continue }
            let isDefault = trimmed.hasPrefix("* ")
            let raw = String(trimmed.dropFirst(2))
            let id = raw.replacingOccurrences(of: " (default)", with: "")
            models.append(GrokModelInfo(id: id, name: id, isDefault: isDefault))
        }
        return models
    }

    func listSessions(limit: Int = 30, cwd: URL? = nil) async throws -> [GrokSessionInfo] {
        let result = try await run(["sessions", "list", "--limit", "\(limit)"], cwd: cwd)
        return GrokSessionInfo.parseListOutput(result.stdout)
    }

    func searchSessions(query: String, limit: Int = 30, cwd: URL? = nil) async throws -> [GrokSessionInfo] {
        let result = try await run(["sessions", "search", "--limit", "\(limit)", query], cwd: cwd)
        return GrokSessionInfo.parseListOutput(result.stdout)
    }

    func deleteSession(id: String, cwd: URL? = nil) async throws {
        _ = try await run(["sessions", "delete", id], cwd: cwd)
    }

    private func jsonValue(_ args: [String], cwd: URL? = nil, allowFailure: Bool = false) async throws -> Any {
        let result = try await run(args, cwd: cwd, allowFailure: allowFailure)
        let output = sanitizedJSONOutput(result.stdout)
        guard let data = output.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            throw CLIError.invalidJSON(result.combinedOutput)
        }
        return value
    }

    private func sanitizedJSONOutput(_ output: String) -> String {
        let ansiPattern = #"\u{001B}\[[0-?]*[ -/]*[@-~]"#
        let noANSI = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        let trimmed = noANSI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return trimmed }
        return String(trimmed[first...])
    }

    /// Test seam: lets fixtures point `run` at a scripted executable.
    static var cliOverrideForTests: URL?

    static func locateGrokCLI() -> URL? {
        if let override = cliOverrideForTests { return override }
        if let path = ProcessInfo.processInfo.environment["GROK_CLI_PATH"], !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        for candidate in [
            "\(NSHomeDirectory())/.grok/bin/grok",
            "\(NSHomeDirectory())/bin/grok",
            "/opt/homebrew/bin/grok",
            "/usr/local/bin/grok"
        ] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("grok").path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        return nil
    }

    /// Short display string from `grok --version` (e.g. `0.2.60 [stable]`).
    static func formatVersionOutput(_ output: String) -> String {
        let withoutName = output.replacingOccurrences(
            of: #"^grok\s+"#,
            with: "",
            options: .regularExpression
        )
        return withoutName.replacingOccurrences(
            of: #"\s+\([^)]+\)"#,
            with: "",
            options: .regularExpression
        )
    }

    static func versionDisplayLine() async -> String {
        do {
            let output = try await GrokCLIService()
                .run(["--version"])
                .stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return "grok CLI: version unavailable"
            }
            return "grok CLI: \(formatVersionOutput(output))"
        } catch {
            return "grok CLI: not found"
        }
    }
}


/// One-shot upgrades for renamed/superseded UserDefaults keys.
enum LegacySettingsMigration {
    /// `grokbuild.noMemory` predates the Memory pane's `memoryEnabled`.
    /// Nothing read the old key anymore, so an upgrading user's explicit
    /// memory choice was silently lost; honor it once, then clear it.
    static func run(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: GrokSettingsKeys.memoryEnabled) == nil,
           let legacyNoMemory = defaults.object(forKey: GrokSettingsKeys.noMemory) as? Bool {
            defaults.set(!legacyNoMemory, forKey: GrokSettingsKeys.memoryEnabled)
        }
        defaults.removeObject(forKey: GrokSettingsKeys.noMemory)
    }
}
