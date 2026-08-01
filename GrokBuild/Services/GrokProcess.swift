import Foundation
import Observation

enum GrokProcessState: Sendable, Equatable {
    case idle
    case starting
    case ready
    case busy
    case failed(String)

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

}

struct GrokLaunchOptions: Sendable {
    var localTabID: UUID? = nil
    var agent: String? = nil  // advanced: for custom --agent profiles only (built-in personas removed)
    var extraArgs: [String] = []
    var noMemory: Bool = false
    var experimentalMemory: Bool = false  // maps to `--experimental-memory` (mutually exclusive with noMemory)
    var permissionMode: String? = nil
    var reasoningEffort: String? = nil   // passed to `grok agent --reasoning-effort X stdio`
    var model: String? = nil             // e.g. model name like "gpt-5.5-extra-high" or grok variant
    var sandboxProfile: String? = nil
    var disableWebSearch: Bool = false
    var noSubagents: Bool = false
    var allowRules: [String] = []
    var denyRules: [String] = []
    var resumeSessionID: String? = nil
    var forkSession: Bool = false
    var newSessionID: String? = nil
    var mcpServers: [MCPServerConfig] = []
}

enum GrokLaunchOutcome: String, Sendable, Equatable {
    case starting
    case loaded
    case new
    case recoveryForked
    case failed
    case stopped
}

/// Credential-free receipt for the exact launched CLI generation. It deliberately
/// excludes environment variables, MCP env, allow/deny rule contents, URLs, and
/// provider credentials.
struct GrokLaunchReceipt: Sendable, Equatable {
    let localTabID: UUID?
    let workspaceID: UUID?
    let processIdentifier: Int32?
    let processGeneration: UInt64
    var backendSessionID: String?
    var outcome: GrokLaunchOutcome
    let requestedModelID: String?
    let requestedAgentID: String?
    let requestedReasoningEffort: String?
    let permissionMode: GrokPermissionMode
    let permissionArguments: [String]
    let sandboxProfile: String
    let memoryEnabled: Bool
    let webSearchEnabled: Bool
    let subagentsEnabled: Bool
    let resumeSessionID: String?
    let browserEnabled: Bool
    let computerUseEnabled: Bool
    let mcpServerNames: [String]
    let startedAt: Date

    init(
        options: GrokLaunchOptions,
        workspaceID: UUID? = nil,
        processIdentifier: Int32? = nil,
        processGeneration: UInt64 = 0,
        startedAt: Date = Date()
    ) {
        localTabID = options.localTabID
        self.workspaceID = workspaceID
        self.processIdentifier = processIdentifier
        self.processGeneration = processGeneration
        backendSessionID = options.resumeSessionID
        outcome = .starting
        requestedModelID = options.model
        requestedAgentID = options.agent
        requestedReasoningEffort = options.reasoningEffort
        permissionMode = GrokPermissionMode(storedValue: options.permissionMode ?? "default")
        permissionArguments = GrokPermissionLaunchArguments.arguments(for: options.permissionMode)
        sandboxProfile = options.sandboxProfile?.isEmpty == false ? options.sandboxProfile! : "default"
        memoryEnabled = options.experimentalMemory && !options.noMemory
        webSearchEnabled = !options.disableWebSearch
        subagentsEnabled = !options.noSubagents
        resumeSessionID = options.resumeSessionID
        mcpServerNames = options.mcpServers.map(\.name).sorted()
        browserEnabled = mcpServerNames.contains("grokbuild-browser")
        computerUseEnabled = mcpServerNames.contains("grokbuild-computer-use")
        self.startedAt = startedAt
    }
}

struct ModelSwitchHandle {
    let identity: ModelRequestIdentity
    let result: Task<ModelExecutionState, Never>
}

/// Resolves grok's mutually-exclusive memory launch flag. `--no-memory` has absolute priority
/// (matches grok's own precedence); `--experimental-memory` enables cross-session memory;
/// `nil` leaves memory at grok's default.
enum GrokMemoryFlag {
    static func argument(noMemory: Bool, experimentalMemory: Bool) -> String? {
        if noMemory { return "--no-memory" }
        if experimentalMemory { return "--experimental-memory" }
        return nil
    }
}

/// Detects ACP `session/update` events replayed during `session/load`.
enum GrokSessionReplay {
    static func isReplaySessionUpdate(params: [String: Any], update: [String: Any]? = nil) -> Bool {
        if let meta = params["_meta"] as? [String: Any],
           meta["isReplay"] as? Bool == true {
            return true
        }
        let updateDict = update ?? params["update"] as? [String: Any]
        if let updateDict,
           let meta = updateDict["_meta"] as? [String: Any],
           meta["isReplay"] as? Bool == true {
            return true
        }
        return false
    }
}

/// Classifies ACP `session/load` failures from the grok CLI.
enum GrokSessionLoadError {
    /// On-disk grok session data is missing (cleared, moved project, or never fully written).
    static func isStaleSessionMissing(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.userInfo["acpErrorCode"] as? String == "FS_NOT_FOUND" { return true }
        return ns.localizedDescription.localizedCaseInsensitiveContains("path not found")
    }
}

// MARK: - Typed ACP Models

struct AgentMode: RawRepresentable, Sendable, Hashable, Equatable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }

    // Grok CLI modes for the bottom selector (Agent / Plan / Yolo)
    static let agent = AgentMode(rawValue: "agent")
    static let plan  = AgentMode(rawValue: "plan")
    static let yolo  = AgentMode(rawValue: "yolo")
}

struct ToolCall: @unchecked Sendable, Identifiable, Hashable {
    let id: String          // toolCallId
    let kind: String
    let title: String
    let rawInput: [String: Any]?
    let status: String?
    let detail: String?

    init(
        id: String,
        kind: String,
        title: String,
        rawInput: [String: Any]?,
        status: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rawInput = rawInput
        self.status = status
        self.detail = detail
    }

    var identifier: String { id }

    // Improved specifics
    var isEdit: Bool {
        let k = kind.lowercased()
        return k == "edit" || k == "write" || k == "write_file" || k.contains("edit")
    }

    var isExecute: Bool {
        let k = kind.lowercased()
        return k == "execute" || k == "terminal" || k == "run" || k.contains("exec")
    }

    var filePath: String? {
        if let path = rawInput?["path"] as? String { return path }
        if let file = rawInput?["file"] as? String { return file }
        if let args = rawInput?["args"] as? [String], let first = args.first, first.hasPrefix("/") || first.contains(".") {
            return first
        }
        return nil
    }

    var proposedContent: String? {
        if let content = rawInput?["content"] as? String { return content }
        if let newText = rawInput?["newText"] as? String { return newText }
        if let text = rawInput?["text"] as? String { return text }
        if let patch = rawInput?["patch"] as? String { return patch }
        return nil
    }

    var oldContent: String? {
        if let old = rawInput?["oldContent"] as? String { return old }
        if let original = rawInput?["original"] as? String { return original }
        return nil
    }

    var command: String? {
        if let cmd = rawInput?["command"] as? String { return cmd }
        if let cmd = rawInput?["cmd"] as? String { return cmd }
        if let args = rawInput?["args"] as? [String] { return args.joined(separator: " ") }
        return nil
    }

    // More specific kinds
    var editFilePath: String? { filePath }
    var executeCommand: String? { command }

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PermissionOption: Sendable, Identifiable, Hashable {
    let id: String          // optionId
    let kind: String        // "allow_always", "allow_once", "reject_once", etc.
    let name: String

    var identifier: String { id }
}

struct PermissionRequest: @unchecked Sendable, Identifiable, Hashable {
    let id: AnyHashable     // request id from protocol (can be Int or String)
    let sessionId: String
    let toolCall: ToolCall
    let options: [PermissionOption]

    var identifier: AnyHashable { id }
}

// MARK: - Structured ACP Events

enum AcpEvent: @unchecked Sendable {
    case messageChunk(text: String)
    case thoughtChunk(text: String)
    case toolCall(ToolCall)
    case toolCallUpdate(ToolCall)   // simplified
    case plan(payload: [String: Any])
    case planFileContent(String)
    case exitPlanRequest(ExitPlanRequest)
    case questionRequest(QuestionRequest)
    case permissionRequest(PermissionRequest)
    case modeChanged(mode: AgentMode)
    case contextUsage(totalTokens: Int)
    case availableCommands([SlashCommand])
    /// A grok `scheduler_*` tool-call `session/update`, forwarded raw for the scheduled-tasks panel.
    case schedulerActivity(payload: [String: Any])
    /// A grok `workflow` tool-call or workflow session update, forwarded raw for workflow runs.
    case workflowActivity(payload: [String: Any])
    /// Background shells, monitors, subagents, and scheduler tools (richer Tasks pill).
    case backgroundActivity(payload: [String: Any])
    /// Explicit queue barrier for one prompt turn. ChatStore acknowledges this only
    /// after every earlier streamed event has been consumed and persisted/reconciled.
    case turnCompleted
    case rawLine(String)
    case error(String)
}

/// Newline-delimited framing over raw pipe bytes. Buffering as `Data` (not
/// `String`) keeps the split linear — no grapheme walking, one front removal
/// per drain — and makes chunk boundaries safe: a multi-byte UTF-8 codepoint
/// split across two reads stays in the buffer until its line completes, where
/// the old per-chunk `String(data:encoding:)` decode silently dropped the
/// whole chunk.
enum AcpLineBuffer {
    /// Appends `chunk`, removes every complete `\n`-terminated line from the
    /// front of `buffer`, and returns them decoded as UTF-8 (without the
    /// newline). Incomplete trailing bytes remain in `buffer`.
    static func drainLines(buffer: inout Data, appending chunk: Data) -> [String] {
        buffer.append(chunk)
        var lines: [String] = []
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[start..<newline], as: UTF8.self))
            start = buffer.index(after: newline)
        }
        if start != buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<start)
        }
        return lines
    }
}

/// ACP client for `grok agent stdio`.
/// Replaces the old TUI scraping approach with proper JSON-RPC.
@Observable
final class GrokProcess: @unchecked Sendable {
    private let ioLock = NSLock()
    private let writeLock = NSLock()
    private let turnCompletionLock = NSLock()
    private let terminalManager = ACPClientTerminalManager()
    private(set) var state: GrokProcessState = .idle
    private(set) var currentWorkspace: Workspace?

    var needsAuthentication: Bool {
        if case .failed(let message) = state {
            let m = message.lowercased()
            return m.contains("login") || m.contains("auth") || m.contains("not authenticated")
        }
        return false
    }

    /// Preferred: structured ACP events.
    var acpEventStream: AsyncStream<AcpEvent> { _acpEventStream }
    private let _acpEventStream: AsyncStream<AcpEvent>
    private var acpEventContinuation: AsyncStream<AcpEvent>.Continuation?

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: Pipe?
    private var stderr: Pipe?
    private var readerTask: Task<Void, Never>?
    private var stdoutBuffer = Data()
    private var startupStderr = ""
    /// Startup diagnostics only — the earliest stderr bytes explain a launch
    /// failure; capping prevents a chatty long-lived CLI from growing memory.
    private static let startupStderrLimit = 64 * 1024

    /// Kept test-visible so capability claims cannot drift away from request handlers again.
    static let clientCapabilities: [String: Any] = [
        "fs": ["readTextFile": true, "writeTextFile": true],
        "terminal": true
    ]

    private var nextRequestId = 1
    private struct PendingRequest {
        let continuation: CheckedContinuation<Any?, Error>
        let timeoutTask: Task<Void, Never>?
    }
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var turnCompletionContinuation: CheckedContinuation<Void, Never>?
    private var turnCompletionTimeoutTask: Task<Void, Never>?
    private var didReceiveTurnCompletion = false
    private(set) var sessionId: String?
    private(set) var launchReceipt: GrokLaunchReceipt?
    /// Monotonic launch identity. `activeProcessGeneration == nil` means the most
    /// recent receipt is historical rather than a live-process claim.
    private(set) var processGeneration: UInt64 = 0
    private(set) var activeProcessGeneration: UInt64?
    /// Set when `session/load` failed with missing on-disk data and `session/new` was used instead.
    private(set) var sessionLoadStartedFreshFallback = false
    private(set) var staleResumeSessionID: String?
    private(set) var currentMode: AgentMode = .agent
    private(set) var availableModes: [AgentMode] = [.agent, .plan, .yolo]
    private(set) var currentModelId: String?
    private(set) var modelExecutionState: ModelExecutionState = .unknown
    /// Set when a model switch fails or times out; the UI can surface and then clear it.
    var modelSwitchError: String?
    /// Set when the failed switch is recoverable by starting a new session (the agent
    /// returned `MODEL_SWITCH_INCOMPATIBLE_AGENT` / suggested `start_new_session`).
    var modelSwitchNeedsNewSession = false
    /// True only for a request owned by the active process generation.
    var modelSwitchPending: Bool {
        modelExecutionState.isPending
            && modelExecutionState.identity?.processGeneration == activeProcessGeneration
    }

    // Populated from initialize modelState so we use real models from grok CLI
    private(set) var availableModelsInfo: [(id: String, name: String, contextTokens: Int?)] = []
    private(set) var availableSlashCommands: [SlashCommand] = []
    private var latestPlanFileContent = ""

    // MARK: - Parsing helpers (instance for access to state if needed)

    /// Internal for contract tests: tool status/output must survive ACP parsing into the UI model.
    func parseToolCall(from payload: [String: Any]) -> ToolCall? {
        // Support multiple wire shapes from grok agent stdio
        let tool = payload["toolCall"] as? [String: Any]
            ?? payload["tool_call"] as? [String: Any]
            ?? payload // direct in some updates

        let tcid = (tool["toolCallId"] as? String)
            ?? (tool["tool_call_id"] as? String)
            ?? (tool["id"] as? String)
            ?? UUID().uuidString

        var raw = tool["rawInput"] as? [String: Any]
            ?? tool["raw_input"] as? [String: Any]
            ?? tool["input"] as? [String: Any]
            ?? tool["arguments"] as? [String: Any]
            ?? tool["args"] as? [String: Any]
            ?? [:]

        if let toolName = tool["toolName"] as? String ?? tool["tool_name"] as? String {
            raw["toolName"] = toolName
        }
        if let serverName = tool["serverName"] as? String ?? tool["server_name"] as? String {
            raw["serverName"] = serverName
        }

        let rawToolName = raw["toolName"] as? String
            ?? raw["tool_name"] as? String
            ?? raw["name"] as? String
            ?? raw["tool"] as? String

        let kind = (tool["kind"] as? String)
            ?? (tool["type"] as? String)
            ?? rawToolName.map { toolKind(for: $0) }
            ?? "unknown"

        let title = (tool["title"] as? String)
            ?? (tool["name"] as? String)
            ?? rawToolName.map { displayToolName($0) }
            ?? (kind == "unknown" ? "Tool call" : kind)

        // More parsing for specific kinds (edit, execute, etc.)
        if let path = tool["path"] as? String { raw["path"] = path }
        if let content = tool["content"] as? String { raw["content"] = content }
        if let cmd = tool["command"] as? String { raw["command"] = cmd }
        if let newText = tool["newText"] as? String { raw["newText"] = newText }

        let status = tool["status"] as? String
        let contentDetail = Self.toolContentText(tool["content"])
        let rawOutputDetail = Self.toolRawOutputText(tool["rawOutput"] ?? tool["raw_output"])

        return ToolCall(
            id: tcid,
            kind: kind,
            title: title,
            rawInput: raw.isEmpty ? nil : raw,
            status: status,
            detail: rawOutputDetail ?? contentDetail
        )
    }

    private static func toolContentText(_ value: Any?) -> String? {
        guard let entries = value as? [Any] else { return nil }
        let texts = entries.compactMap { entry -> String? in
            guard let item = entry as? [String: Any] else { return nil }
            if let text = item["text"] as? String { return text }
            if let nested = item["content"] as? [String: Any] {
                return nested["text"] as? String
            }
            if item["type"] as? String == "terminal", let id = item["terminalId"] as? String {
                return "Terminal \(id)"
            }
            return nil
        }
        let combined = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return combined.isEmpty ? nil : combined
    }

    private static func toolRawOutputText(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let dictionary = value as? [String: Any] {
            if let message = dictionary["message"] as? String, !message.isEmpty { return message }
            if let error = dictionary["error"] as? String, !error.isEmpty { return error }
            guard JSONSerialization.isValidJSONObject(dictionary),
                  let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        }
        return nil
    }

    private func toolKind(for toolName: String) -> String {
        if toolName.hasPrefix("browser_") { return "browser" }
        if toolName.localizedCaseInsensitiveContains("read") { return "read" }
        if toolName.localizedCaseInsensitiveContains("write") || toolName.localizedCaseInsensitiveContains("edit") {
            return "edit"
        }
        return "tool"
    }

    private func displayToolName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private func parsePermissionRequest(id: Any?, params: [String: Any]) -> PermissionRequest? {
        guard let sid = params["sessionId"] as? String ?? params["session_id"] as? String,
              let toolDict = params["toolCall"] as? [String: Any] ?? params["tool_call"] as? [String: Any],
              let tool = parseToolCall(from: ["toolCall": toolDict]) else { return nil }

        let optionsArray = (params["options"] as? [[String: Any]]) ?? []
        let options = optionsArray.compactMap { opt -> PermissionOption? in
            guard let oid = opt["optionId"] as? String ?? opt["option_id"] as? String,
                  let okind = opt["kind"] as? String else { return nil }
            let oname = opt["name"] as? String ?? okind
            return PermissionOption(id: oid, kind: okind, name: oname)
        }

        let reqId: AnyHashable = (id as? Int).map { AnyHashable($0) } ?? AnyHashable(id as? String ?? UUID().uuidString)
        return PermissionRequest(id: reqId, sessionId: sid, toolCall: tool, options: options)
    }

    init() {
        var acpC: AsyncStream<AcpEvent>.Continuation!
        _acpEventStream = AsyncStream(bufferingPolicy: .unbounded) { acpC = $0 }
        acpEventContinuation = acpC
    }

    // MARK: - Lifecycle

    func start(workspace: Workspace, options: GrokLaunchOptions = .init()) async {
        await cleanupProcess(setIdle: true)

        processGeneration &+= 1
        let launchGeneration = processGeneration
        activeProcessGeneration = launchGeneration
        let launchIdentity = ModelRequestIdentity(
            localTabID: options.localTabID,
            backendSessionID: options.resumeSessionID,
            processGeneration: launchGeneration,
            requestID: UUID()
        )

        state = .starting
        currentWorkspace = workspace
        sessionId = nil
        launchReceipt = nil
        sessionLoadStartedFreshFallback = false
        staleResumeSessionID = nil
        currentModelId = nil
        modelExecutionState = ModelExecutionReducer.launch(
            requestedModelID: options.model,
            identity: launchIdentity
        )
        availableModelsInfo.removeAll()

        guard let cli = Self.locateGrokCLI() else {
            var receipt = GrokLaunchReceipt(
                options: options,
                workspaceID: workspace.id,
                processGeneration: launchGeneration
            )
            receipt.outcome = .failed
            launchReceipt = receipt
            rejectLaunchModelReceipt(identity: launchIdentity)
            activeProcessGeneration = nil
            state = .failed("Could not locate the `grok` CLI. Run `grok login` or set GROK_CLI_PATH.")
            return
        }

        let proc = Process()
        proc.executableURL = cli
        proc.currentDirectoryURL = workspace.path
        proc.environment = ProcessInfo.processInfo.environment

        // ACP: grok [top-level flags] agent [agent flags] stdio
        var args: [String] = []
        if let a = options.agent, !a.isEmpty { args += ["--agent", a] }
        if let memoryFlag = GrokMemoryFlag.argument(
            noMemory: options.noMemory,
            experimentalMemory: options.experimentalMemory
        ) {
            args.append(memoryFlag)
        }
        args += GrokPermissionLaunchArguments.arguments(for: options.permissionMode)
        if let sandbox = options.sandboxProfile, !sandbox.isEmpty {
            args += ["--sandbox", sandbox]
        }
        if options.disableWebSearch { args.append("--disable-web-search") }
        if options.noSubagents { args.append("--no-subagents") }
        for rule in options.allowRules where !rule.isEmpty {
            args += ["--allow", rule]
        }
        for rule in options.denyRules where !rule.isEmpty {
            args += ["--deny", rule]
        }
        if options.forkSession {
            args.append("--fork-session")
        }
        if let sessionID = options.newSessionID, !sessionID.isEmpty {
            args += ["--session-id", sessionID]
        }

        args.append("agent")
        if let e = options.reasoningEffort, !e.isEmpty {
            args += ["--reasoning-effort", e]
        }
        if let m = options.model, !m.isEmpty {
            args += ["--model", m]
        }
        args.append("stdio")
        args += options.extraArgs

        proc.arguments = args

        let i = Pipe(), o = Pipe(), e = Pipe()
        proc.standardInput = i
        proc.standardOutput = o
        proc.standardError = e

        do { try proc.run() } catch {
            var receipt = GrokLaunchReceipt(
                options: options,
                workspaceID: workspace.id,
                processGeneration: launchGeneration
            )
            receipt.outcome = .failed
            launchReceipt = receipt
            rejectLaunchModelReceipt(identity: launchIdentity)
            activeProcessGeneration = nil
            state = .failed("Failed to launch: \(error.localizedDescription)")
            return
        }

        launchReceipt = GrokLaunchReceipt(
            options: options,
            workspaceID: workspace.id,
            processIdentifier: proc.processIdentifier,
            processGeneration: launchGeneration
        )

        self.process = proc
        self.stdin = i.fileHandleForWriting
        self.stdout = o
        self.stderr = e
        self.stdoutBuffer = Data()
        self.startupStderr = ""

        setupReaders(stdout: o, stderr: e)

        do {
            try await initializeACP()
            guard activeProcessGeneration == launchGeneration else { return }
            let launchOutcome: GrokLaunchOutcome
            if let resumeSessionID = options.resumeSessionID, !resumeSessionID.isEmpty {
                do {
                    try await loadSession(
                        id: resumeSessionID,
                        workspace: workspace,
                        mcpServers: options.mcpServers
                    )
                    launchOutcome = .loaded
                } catch {
                    guard GrokSessionLoadError.isStaleSessionMissing(error) else { throw error }
                    staleResumeSessionID = resumeSessionID
                    try await createSession(workspace: workspace, mcpServers: options.mcpServers)
                    sessionLoadStartedFreshFallback = true
                    launchOutcome = .recoveryForked
                }
            } else {
                try await createSession(workspace: workspace, mcpServers: options.mcpServers)
                launchOutcome = .new
            }
            guard activeProcessGeneration == launchGeneration else { return }
            settleLaunchModelReceipt(identity: launchIdentity)
            updateLaunchReceipt(outcome: launchOutcome, backendSessionID: sessionId)
            state = .ready
        } catch {
            guard activeProcessGeneration == launchGeneration else { return }
            let stderrDetails = startupStderrSnapshot()
            let suffix = stderrDetails.isEmpty ? "" : "\n\(stderrDetails)"
            state = .failed("ACP initialize failed: \(error.localizedDescription)\(suffix)")
            await cleanupProcess(setIdle: false)
            rejectLaunchModelReceipt(identity: launchIdentity)
            updateLaunchReceipt(outcome: .failed, backendSessionID: nil)
        }
    }

    func stop() async {
        await cleanupProcess(setIdle: true)
    }

    /// Terminal teardown: stops the process AND finishes the ACP event stream so the
    /// owning ChatStore's consume loop ends and the store/process pair can deallocate.
    /// `stop()` deliberately leaves the stream open because the same instance restarts
    /// after LRU eviction or a configuration reload; call this only when the session's
    /// tab closes for good or the app is quitting.
    func shutdown() async {
        await cleanupProcess(setIdle: false)
        acpEventContinuation?.finish()
        acpEventContinuation = nil
    }

    private func cleanupProcess(setIdle: Bool) async {
        if modelExecutionState.isPending,
           let identity = modelExecutionState.identity,
           identity.processGeneration == activeProcessGeneration {
            _ = ModelExecutionReducer.reject(
                failure: .processStopped,
                identity: identity,
                state: &modelExecutionState
            )
        }
        activeProcessGeneration = nil
        readerTask?.cancel()
        readerTask = nil
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        terminalManager.releaseAll()
        finishTurnCompletionWait()

        if let sid = sessionId {
            _ = writeJson(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": sid]])
        }
        try? stdin?.close()

        if let p = process, p.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
            if p.isRunning { p.terminate() }
        }

        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        sessionId = nil
        if launchReceipt?.outcome != .failed {
            updateLaunchReceipt(outcome: .stopped, backendSessionID: launchReceipt?.backendSessionID)
        }
        drainPendingRequests(with: NSError(
            domain: "ACP",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Grok process stopped."]
        ))

        acpEventContinuation?.yield(.rawLine("[process stopped]"))
        if setIdle {
            state = .idle
        }
        currentWorkspace = nil
    }

    private func updateLaunchReceipt(
        outcome: GrokLaunchOutcome,
        backendSessionID: String?
    ) {
        guard var receipt = launchReceipt else { return }
        receipt.outcome = outcome
        receipt.backendSessionID = backendSessionID
        launchReceipt = receipt
    }

    private func settleLaunchModelReceipt(identity: ModelRequestIdentity) {
        guard let rebound = ModelExecutionReducer.rebindBackend(
            sessionId,
            identity: identity,
            state: &modelExecutionState
        ) else { return }
        if let currentModelId {
            _ = ModelExecutionReducer.confirm(
                effectiveModelID: currentModelId,
                identity: rebound,
                state: &modelExecutionState
            )
        } else {
            _ = ModelExecutionReducer.acceptWithoutEffectiveModel(
                identity: rebound,
                state: &modelExecutionState
            )
        }
    }

    private func rejectLaunchModelReceipt(identity: ModelRequestIdentity) {
        guard modelExecutionState.requestedModelID != nil else { return }
        _ = ModelExecutionReducer.reject(
            failure: .unknown,
            identity: modelExecutionState.identity ?? identity,
            state: &modelExecutionState
        )
    }

    // MARK: - Public API

    @discardableResult
    func send(_ text: String) async -> Bool {
        guard let sid = sessionId, state == .ready || state == .busy else { return false }
        state = .busy
        beginTurnCompletionWait()

        do {
            _ = try await sendRequest(method: "session/prompt", params: [
                "sessionId": sid,
                "prompt": [["type": "text", "text": text]]
            ])
            // Some grok CLI builds resolve `session/prompt` just before their final text
            // notification. Honor the explicit completion event (with a short fallback)
            // so ChatStore does not clear its streaming message mid-word.
            await awaitTurnCompletion()
            state = .ready
            return true
        } catch {
            finishTurnCompletionWait()
            state = .failed("Prompt error: \(error.localizedDescription)")
            return false
        }
    }

    func interrupt() {
        guard let sid = sessionId else { return }
        _ = writeJson(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": sid]])
    }

    // MARK: - Responding to agent requests

    func respondToPermission(_ request: PermissionRequest, with optionId: String) {
        _ = writeJson([
            "jsonrpc": "2.0",
            "id": request.id.base as Any,
            "result": ["outcome": ["outcome": "selected", "optionId": optionId]]
        ])
    }

    func rejectPermission(_ request: PermissionRequest, reason: String) {
        _ = writeJson([
            "jsonrpc": "2.0",
            "id": request.id.base as Any,
            "error": ["code": -32000, "message": reason]
        ])
    }

    func respondToExitPlan(_ planRequestId: Any, verdict: ExitPlanRequest.PlanVerdict) {
        switch verdict {
        case .approved:
            _ = writeJson(["jsonrpc": "2.0", "id": planRequestId, "result": ["outcome": "approved"]])
        case .rejected:
            _ = writeJson(["jsonrpc": "2.0", "id": planRequestId, "error": ["code": -32000, "message": "User rejected the plan"]])
        case .abandoned:
            _ = writeJson(["jsonrpc": "2.0", "id": planRequestId, "error": ["code": -32000, "message": "User abandoned the plan"]])
        }
    }

    func respondToQuestion(_ requestId: Any, answers: [String: String]) {
        _ = writeJson([
            "jsonrpc": "2.0",
            "id": requestId,
            "result": ["outcome": "accepted", "answers": answers, "annotations": [:] as [String: Any]]
        ])
    }

    func respondToQuestionCancelled(_ requestId: Any) {
        _ = writeJson(["jsonrpc": "2.0", "id": requestId, "result": ["outcome": "cancelled"]])
    }

    // MARK: - Mode switching

    func setMode(_ mode: AgentMode) {
        guard let sid = sessionId else { return }
        Task {
            _ = try? await sendRequest(method: "session/set_mode", params: [
                "sessionId": sid,
                "modeId": mode.rawValue
            ])
        }
    }

    func setMode(_ modeId: String) {
        setMode(AgentMode(rawValue: modeId))
    }

    @discardableResult
    func setModel(_ modelId: String) -> ModelSwitchHandle? {
        guard let sid = sessionId,
              let generation = activeProcessGeneration else { return nil }
        let identity = ModelRequestIdentity(
            localTabID: launchReceipt?.localTabID,
            backendSessionID: sid,
            processGeneration: generation,
            requestID: UUID()
        )
        modelSwitchError = nil
        modelSwitchNeedsNewSession = false
        modelExecutionState = ModelExecutionReducer.beginRequest(
            modelID: modelId,
            identity: identity,
            preserving: modelExecutionState
        )

        let task = Task { [weak self] () -> ModelExecutionState in
            guard let self else { return .unknown }
            do {
                // Switching is a control op and should be fast — bound it so a stalled
                // set_model can never leave the UI stuck.
                let result = try await self.sendRequestWithTimeout(
                    method: "session/set_model",
                    params: ["sessionId": sid, "modelId": modelId],
                    seconds: 12
                ) as? [String: Any]
                guard self.activeProcessGeneration == generation,
                      self.modelExecutionState.identity == identity else {
                    return self.modelExecutionState
                }
                if let effective = Self.effectiveModelID(from: result) {
                    if ModelExecutionReducer.confirm(
                        effectiveModelID: effective,
                        identity: identity,
                        state: &self.modelExecutionState
                    ) {
                        self.currentModelId = effective
                    }
                } else {
                    _ = ModelExecutionReducer.acceptWithoutEffectiveModel(
                        identity: identity,
                        state: &self.modelExecutionState
                    )
                }
            } catch {
                guard self.activeProcessGeneration == generation,
                      self.modelExecutionState.identity == identity else {
                    return self.modelExecutionState
                }
                let ns = error as NSError
                let code = ns.userInfo["acpErrorCode"] as? String
                let suggestion = ns.userInfo["acpSuggestion"] as? String
                let incompatible = code == "MODEL_SWITCH_INCOMPATIBLE_AGENT"
                    || suggestion == "start_new_session"
                let failure: ModelExecutionFailure
                if incompatible {
                    failure = .incompatibleAgent
                    self.modelSwitchError = ns.localizedDescription
                    self.modelSwitchNeedsNewSession = true
                } else if ns.code == -2 {
                    failure = .timedOut
                    self.modelSwitchError = "Couldn't switch to \(modelId): timed out waiting for grok."
                    self.modelSwitchNeedsNewSession = false
                } else if ns.domain == "ACP" {
                    failure = .rejected
                    self.modelSwitchError = "Couldn't switch to \(modelId): \(ns.localizedDescription)"
                    self.modelSwitchNeedsNewSession = false
                } else {
                    failure = .unknown
                    self.modelSwitchError = "Couldn't switch to \(modelId): \(ns.localizedDescription)"
                    self.modelSwitchNeedsNewSession = false
                }
                _ = ModelExecutionReducer.reject(
                    failure: failure,
                    identity: identity,
                    state: &self.modelExecutionState
                )
            }
            return self.modelExecutionState
        }
        return ModelSwitchHandle(identity: identity, result: task)
    }

    static func effectiveModelID(from result: [String: Any]?) -> String? {
        if let meta = result?["_meta"] as? [String: Any],
           let model = meta["model"] as? [String: Any],
           let selected = model["Ok"] as? String {
            return selected
        }
        if let selected = result?["currentModelId"] as? String {
            return selected
        }
        for key in ["modelState", "models"] {
            if let state = result?[key] as? [String: Any],
               let selected = state["currentModelId"] as? String {
                return selected
            }
        }
        return nil
    }

    // MARK: - ACP Implementation

    private func writeJson(_ obj: [String: Any]) -> Bool {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard let h = stdin else { return false }
        let data: Data
        if #available(macOS 12.0, *) {
            guard let encoded = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.withoutEscapingSlashes]
            ) else { return false }
            data = encoded
        } else {
            guard let encoded = try? JSONSerialization.data(withJSONObject: obj) else { return false }
            data = encoded
        }
        var line = data
        line.append("\n".data(using: .utf8)!)
        do { try h.write(contentsOf: line); return true } catch { return false }
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> Any? {
        let id: Int = {
            ioLock.lock()
            defer { ioLock.unlock() }
            let current = nextRequestId
            nextRequestId += 1
            return current
        }()
        let req: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]

        return try await withCheckedThrowingContinuation { c in
            ioLock.lock()
            pendingRequests[id] = PendingRequest(continuation: c, timeoutTask: nil)
            ioLock.unlock()
            if !writeJson(req) {
                ioLock.lock()
                pendingRequests.removeValue(forKey: id)
                ioLock.unlock()
                c.resume(throwing: NSError(domain: "ACP", code: -1))
            }
        }
    }

    private func sendRequestWithTimeout(method: String, params: [String: Any], seconds: Double = 15) async throws -> Any? {
        let id: Int = {
            ioLock.lock()
            defer { ioLock.unlock() }
            let current = nextRequestId
            nextRequestId += 1
            return current
        }()
        let req: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]

        return try await withCheckedThrowingContinuation { c in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.timeoutPendingRequest(id: id)
            }
            ioLock.lock()
            pendingRequests[id] = PendingRequest(continuation: c, timeoutTask: timeoutTask)
            ioLock.unlock()
            if !writeJson(req) {
                timeoutTask.cancel()
                ioLock.lock()
                pendingRequests.removeValue(forKey: id)
                ioLock.unlock()
                c.resume(throwing: NSError(domain: "ACP", code: -1))
            }
        }
    }

    private func timeoutPendingRequest(id: Int) {
        ioLock.lock()
        guard let pending = pendingRequests.removeValue(forKey: id) else {
            ioLock.unlock()
            return
        }
        ioLock.unlock()
        pending.continuation.resume(throwing: NSError(
            domain: "ACP",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for grok."]
        ))
    }

    private func beginTurnCompletionWait() {
        turnCompletionLock.lock()
        let staleContinuation = turnCompletionContinuation
        let staleTimeout = turnCompletionTimeoutTask
        turnCompletionContinuation = nil
        turnCompletionTimeoutTask = nil
        didReceiveTurnCompletion = false
        turnCompletionLock.unlock()
        staleTimeout?.cancel()
        staleContinuation?.resume()
    }

    private func awaitTurnCompletion() async {
        await withCheckedContinuation { continuation in
            turnCompletionLock.lock()
            if didReceiveTurnCompletion {
                didReceiveTurnCompletion = false
                turnCompletionLock.unlock()
                continuation.resume()
                return
            }
            turnCompletionContinuation = continuation
            turnCompletionTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                // Compatibility fallback for older CLIs that resolve session/prompt
                // without emitting turn_completed. Still cross the same ChatStore event
                // queue barrier; never resume `send` directly from this timer.
                self?.acpEventContinuation?.yield(.turnCompleted)
            }
            turnCompletionLock.unlock()
        }
    }

    /// Called by ChatStore after it consumes the `.turnCompleted` event. This keeps
    /// prompt completion serialized behind all earlier text/tool events.
    func acknowledgeTurnCompleted() {
        turnCompletionLock.lock()
        didReceiveTurnCompletion = true
        let continuation = turnCompletionContinuation
        let timeout = turnCompletionTimeoutTask
        turnCompletionContinuation = nil
        turnCompletionTimeoutTask = nil
        turnCompletionLock.unlock()
        timeout?.cancel()
        continuation?.resume()
    }

    private func finishTurnCompletionWait() {
        turnCompletionLock.lock()
        let continuation = turnCompletionContinuation
        let timeout = turnCompletionTimeoutTask
        turnCompletionContinuation = nil
        turnCompletionTimeoutTask = nil
        didReceiveTurnCompletion = false
        turnCompletionLock.unlock()
        timeout?.cancel()
        continuation?.resume()
    }

    private func drainPendingRequests(with error: Error) {
        ioLock.lock()
        let pending = Array(pendingRequests.values)
        pendingRequests.removeAll()
        ioLock.unlock()
        for item in pending {
            item.timeoutTask?.cancel()
            item.continuation.resume(throwing: error)
        }
    }

    private func startupStderrSnapshot() -> String {
        ioLock.lock()
        defer { ioLock.unlock() }
        return startupStderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func initializeACP() async throws {
        let res = try await sendRequestWithTimeout(method: "initialize", params: [
            "protocolVersion": 1,
            "clientCapabilities": Self.clientCapabilities
        ]) as? [String: Any]

        // Parse real models from modelState (do not make up)
        let meta = res?["_meta"] as? [String: Any]
        if let ms = (res?["modelState"] as? [String: Any]) ?? (meta?["modelState"] as? [String: Any]),
           let models = ms["availableModels"] as? [[String: Any]] {
            availableModelsInfo = models.compactMap { m in
                guard let id = m["modelId"] as? String else { return nil }
                let name = m["name"] as? String ?? id
                let meta = m["_meta"] as? [String: Any]
                return (id: id, name: name, contextTokens: meta?["totalContextTokens"] as? Int)
            }
        }
    }

    private func createSession(workspace: Workspace, mcpServers: [MCPServerConfig]) async throws {
        let res = try await sendRequestWithTimeout(method: "session/new", params: [
            "cwd": workspace.path.path,
            "mcpServers": mcpServers.map(\.jsonObject)
        ]) as? [String: Any]
        sessionId = res?["sessionId"] as? String
        updateModels(from: res?["models"] as? [String: Any])

        if let mode = res?["currentModeId"] as? String ?? res?["mode"] as? String {
            currentMode = AgentMode(rawValue: mode)
        }

        // Expose available modes if provided by the CLI
        if let modes = res?["modes"] as? [String] {
            availableModes = modes.map { AgentMode(rawValue: $0) }
        } else if let modeInfos = res?["availableModes"] as? [[String: Any]] {
            availableModes = modeInfos.compactMap { $0["id"] as? String }.map { AgentMode(rawValue: $0) }
        }
    }

    private func loadSession(id: String, workspace: Workspace, mcpServers: [MCPServerConfig]) async throws {
        let res = try await sendRequestWithTimeout(method: "session/load", params: [
            "sessionId": id,
            "cwd": workspace.path.path,
            "mcpServers": mcpServers.map(\.jsonObject)
        ]) as? [String: Any]
        sessionId = id
        updateModels(from: res?["models"] as? [String: Any])
        if let mode = res?["currentModeId"] as? String ?? res?["mode"] as? String {
            currentMode = AgentMode(rawValue: mode)
        }
    }

    private func updateModels(from modelState: [String: Any]?) {
        guard let modelState else { return }
        currentModelId = modelState["currentModelId"] as? String ?? currentModelId
        if let models = modelState["availableModels"] as? [[String: Any]] {
            availableModelsInfo = models.compactMap { m in
                guard let id = m["modelId"] as? String else { return nil }
                let name = m["name"] as? String ?? id
                let meta = m["_meta"] as? [String: Any]
                return (id: id, name: name, contextTokens: meta?["totalContextTokens"] as? Int)
            }
        }
    }

    private func setupReaders(stdout: Pipe, stderr: Pipe) {
        // Process pipe I/O synchronously on the reader thread. Dispatching to
        // MainActor here deadlocks because start() awaits ACP responses on MainActor.
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.handleStdoutData(data)
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.handleStderrData(data)
        }
    }

    private func handleStdoutData(_ data: Data) {
        ioLock.lock()
        let lines = AcpLineBuffer.drainLines(buffer: &stdoutBuffer, appending: data)
        ioLock.unlock()

        for rawLine in lines {
            handleAcpRawLine(rawLine)
        }
    }

    private func handleStderrData(_ data: Data) {
        ioLock.lock()
        if startupStderr.count < Self.startupStderrLimit,
           let chunk = String(data: data, encoding: .utf8) {
            startupStderr += chunk
            if startupStderr.count > Self.startupStderrLimit {
                startupStderr = String(startupStderr.prefix(Self.startupStderrLimit))
            }
        }
        ioLock.unlock()
    }

    private func handleAcpRawLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        handleJsonLine(line)
    }

    private func handleJsonLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            acpEventContinuation?.yield(.rawLine(line))
            return
        }

        if let method = j["method"] as? String {
            let params = j["params"] as? [String: Any] ?? [:]
            let rid = j["id"]

            if method == "session/update" || method == "_x.ai/session/update" {
                let update = params["update"] as? [String: Any]
                if let total = totalTokens(from: params) {
                    acpEventContinuation?.yield(.contextUsage(totalTokens: total))
                }
                if update?["sessionUpdate"] as? String == "turn_completed" {
                    // Replay completion belongs to the historical load stream, not the
                    // live turn currently owned by ChatStore.
                    guard !GrokSessionReplay.isReplaySessionUpdate(params: params, update: update) else {
                        return
                    }
                    acpEventContinuation?.yield(.turnCompleted)
                    return
                }
                if !GrokSessionReplay.isReplaySessionUpdate(params: params, update: update),
                   let u = update {
                    routeUpdate(u)
                }
                return
            }

            if method == "session/request_permission" {
                if let req = parsePermissionRequest(id: rid, params: params) {
                    acpEventContinuation?.yield(.permissionRequest(req))
                }
                // UI will respond via respondToPermission
                return
            }

            if method == "x.ai/exit_plan_mode" || method == "session/exit_plan_mode"
                || method == "_x.ai/exit_plan_mode" {
                let planText = exitPlanText(from: params)
                let req = ExitPlanRequest(
                    id: requestIdHash(rid),
                    sessionId: params["sessionId"] as? String ?? sessionId ?? "",
                    planText: planText.isEmpty ? latestPlanFileContent : planText,
                    isResolved: false,
                    verdict: nil
                )
                acpEventContinuation?.yield(.exitPlanRequest(req))
                return
            }

            if method == "x.ai/ask_user_question" || method == "_x.ai/ask_user_question" {
                let questions = (params["questions"] as? [[String: Any]] ?? [])
                    .compactMap { QuestionItem.parse(from: $0) }
                let req = QuestionRequest(
                    id: requestIdHash(rid),
                    sessionId: params["sessionId"] as? String ?? sessionId ?? "",
                    questions: questions,
                    isResolved: false,
                    answerSummary: nil
                )
                acpEventContinuation?.yield(.questionRequest(req))
                return
            }

            switch method {
            case "fs/read_text_file":
                if let p = params["path"] as? String { handleFsRead(rid: rid, path: p) }
            case "fs/write_text_file":
                if let p = params["path"] as? String, let c = params["content"] as? String {
                    handleFsWrite(rid: rid, path: p, content: c)
                }
            case "terminal/create":
                handleTerminalCreate(rid: rid, params: params)
            case "terminal/output":
                handleTerminalOutput(rid: rid, params: params)
            case "terminal/wait_for_exit":
                handleTerminalWaitForExit(rid: rid, params: params)
            case "terminal/kill":
                handleTerminalKill(rid: rid, params: params)
            case "terminal/release":
                handleTerminalRelease(rid: rid, params: params)
            default:
                if let r = rid { _ = writeJson(["jsonrpc": "2.0", "id": r, "result": [:]]) }
            }
            return
        }

        if let id = jsonRequestId(from: j) {
            ioLock.lock()
            let pending = pendingRequests.removeValue(forKey: id)
            ioLock.unlock()
            if let pending {
                pending.timeoutTask?.cancel()
                if let err = j["error"] {
                    var info: [String: Any] = [:]
                    if let dict = err as? [String: Any] {
                        // Prefer the agent's human-readable message over dumping the raw error object.
                        info[NSLocalizedDescriptionKey] = (dict["message"] as? String) ?? "\(err)"
                        if let data = dict["data"] as? [String: Any] {
                            if let code = data["code"] as? String { info["acpErrorCode"] = code }
                            if let suggestion = data["suggestion"] as? String { info["acpSuggestion"] = suggestion }
                        }
                    } else {
                        info[NSLocalizedDescriptionKey] = "\(err)"
                    }
                    pending.continuation.resume(throwing: NSError(domain: "ACP", code: -1, userInfo: info))
                } else {
                    pending.continuation.resume(returning: j["result"])
                }
            }
            return
        }
    }

    private func jsonRequestId(from json: [String: Any]) -> Int? {
        if let id = json["id"] as? Int { return id }
        if let id = json["id"] as? NSNumber { return id.intValue }
        if let id = json["id"] as? String, let parsed = Int(id) { return parsed }
        return nil
    }

    private func totalTokens(from params: [String: Any]) -> Int? {
        if let meta = params["_meta"] as? [String: Any],
           let total = meta["totalTokens"] as? Int {
            return total
        }
        if let update = params["update"] as? [String: Any],
           let meta = update["_meta"] as? [String: Any],
           let total = meta["totalTokens"] as? Int {
            return total
        }
        return nil
    }

    private func routeUpdate(_ u: [String: Any]) {
        guard let k = u["sessionUpdate"] as? String else { return }
        switch k {
        case "agent_message_chunk":
            let t = (u["content"] as? [String: Any])?["text"] as? String ?? ""
            acpEventContinuation?.yield(.messageChunk(text: t))
        case "agent_thought_chunk":
            let t = (u["content"] as? [String: Any])?["text"] as? String ?? ""
            acpEventContinuation?.yield(.thoughtChunk(text: t))
        case "tool_call":
            if let tc = parseToolCall(from: u) {
                acpEventContinuation?.yield(.toolCall(tc))
            } else {
                acpEventContinuation?.yield(.toolCall(ToolCall(id: UUID().uuidString, kind: "unknown", title: "Tool call", rawInput: nil)))
            }
            if SchedulerToolParsing.schedulerName(inUpdate: u) != nil {
                acpEventContinuation?.yield(.schedulerActivity(payload: u))
            }
            if WorkflowToolParsing.workflowName(inUpdate: u) != nil {
                acpEventContinuation?.yield(.workflowActivity(payload: u))
            }
            if BackgroundToolParsing.backgroundToolName(inUpdate: u) != nil {
                acpEventContinuation?.yield(.backgroundActivity(payload: u))
            }
        case "tool_call_update":
            if let tc = parseToolCall(from: u) {
                acpEventContinuation?.yield(.toolCallUpdate(tc))
            }
            if SchedulerToolParsing.schedulerName(inUpdate: u) != nil {
                acpEventContinuation?.yield(.schedulerActivity(payload: u))
            }
            if WorkflowToolParsing.workflowName(inUpdate: u) != nil {
                acpEventContinuation?.yield(.workflowActivity(payload: u))
            }
            if BackgroundToolParsing.backgroundToolName(inUpdate: u) != nil {
                acpEventContinuation?.yield(.backgroundActivity(payload: u))
            }
        case "plan":
            acpEventContinuation?.yield(.plan(payload: u))
        case "available_commands_update":
            let commands = (u["availableCommands"] as? [[String: Any]] ?? [])
                .compactMap { SlashCommand.parse(from: $0) }
            availableSlashCommands = commands
            acpEventContinuation?.yield(.availableCommands(commands))
        case "current_mode_update":
            if let m = u["currentModeId"] as? String {
                currentMode = AgentMode(rawValue: m)
                acpEventContinuation?.yield(.modeChanged(mode: currentMode))
            }
        default:
            if WorkflowToolParsing.isWorkflowSessionUpdate(k) {
                acpEventContinuation?.yield(.workflowActivity(payload: u))
            }
        }
    }

    private func requestIdHash(_ id: Any?) -> AnyHashable {
        if let intId = id as? Int { return AnyHashable(intId) }
        if let strId = id as? String { return AnyHashable(strId) }
        return AnyHashable(UUID().uuidString)
    }

    private func respond(rid: Any?, result: Any = [:]) {
        guard let id = rid else { return }
        _ = writeJson(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func respond(rid: Any?, error: Error, code: Int = -32001) {
        guard let id = rid else { return }
        _ = writeJson([
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": error.localizedDescription]
        ])
    }

    private func handleFsRead(rid: Any?, path: String) {
        do {
            let c = try String(contentsOf: resolvedProjectURL(path), encoding: .utf8)
            respond(rid: rid, result: ["content": c])
        } catch {
            _ = writeJson(["jsonrpc": "2.0", "id": rid as Any, "error": ["code": -32001, "message": error.localizedDescription]])
        }
    }

    private func handleFsWrite(rid: Any?, path: String, content: String) {
        if isPlanFileWrite(path) {
            latestPlanFileContent = content
            acpEventContinuation?.yield(.planFileContent(content))
        }
        do {
            let url = resolvedProjectURL(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            respond(rid: rid)
        } catch {
            _ = writeJson(["jsonrpc": "2.0", "id": rid as Any, "error": ["code": -32001, "message": error.localizedDescription]])
        }
    }

    private func handleTerminalCreate(rid: Any?, params: [String: Any]) {
        do {
            guard let command = params["command"] as? String else {
                throw ACPClientTerminalManager.TerminalError.invalidCommand
            }
            let arguments = params["args"] as? [String] ?? []
            let environment = (params["env"] as? [[String: Any]] ?? []).reduce(into: [String: String]()) {
                result, entry in
                if let name = entry["name"] as? String,
                   let value = entry["value"] as? String,
                   !name.isEmpty {
                    result[name] = value
                }
            }
            let requestedLimit = (params["outputByteLimit"] as? NSNumber)?.intValue
            let terminalID = try terminalManager.create(
                command: command,
                arguments: arguments,
                environment: environment,
                workingDirectory: params["cwd"] as? String ?? currentWorkspace?.path.path,
                outputByteLimit: requestedLimit
            )
            respond(rid: rid, result: ["terminalId": terminalID])
        } catch {
            respond(rid: rid, error: error)
        }
    }

    private func handleTerminalOutput(rid: Any?, params: [String: Any]) {
        do {
            let terminalID = try terminalID(from: params)
            respond(rid: rid, result: try terminalManager.snapshot(terminalID: terminalID).jsonObject)
        } catch {
            respond(rid: rid, error: error)
        }
    }

    private func handleTerminalWaitForExit(rid: Any?, params: [String: Any]) {
        do {
            let terminalID = try terminalID(from: params)
            Task { [weak self] in
                guard let self else { return }
                do {
                    let status = try await self.terminalManager.waitForExit(terminalID: terminalID)
                    self.respond(rid: rid, result: status.jsonObject)
                } catch {
                    self.respond(rid: rid, error: error)
                }
            }
        } catch {
            respond(rid: rid, error: error)
        }
    }

    private func handleTerminalKill(rid: Any?, params: [String: Any]) {
        do {
            try terminalManager.kill(terminalID: try terminalID(from: params))
            respond(rid: rid)
        } catch {
            respond(rid: rid, error: error)
        }
    }

    private func handleTerminalRelease(rid: Any?, params: [String: Any]) {
        do {
            try terminalManager.release(terminalID: try terminalID(from: params))
            respond(rid: rid)
        } catch {
            respond(rid: rid, error: error)
        }
    }

    private func terminalID(from params: [String: Any]) throws -> String {
        guard let terminalID = params["terminalId"] as? String, !terminalID.isEmpty else {
            throw ACPClientTerminalManager.TerminalError.unknownTerminal("missing terminalId")
        }
        return terminalID
    }

    private func isPlanFileWrite(_ path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        return normalized.hasSuffix("/plan.md") || normalized.contains("/sessions/") && normalized.hasSuffix("plan.md")
    }

    private func exitPlanText(from params: [String: Any]) -> String {
        if let plan = params["planContent"] as? String, !plan.isEmpty { return plan }
        if let plan = params["plan"] as? String, !plan.isEmpty { return plan }
        if let input = params["input"] as? [String: Any], let plan = input["plan"] as? String { return plan }
        return ""
    }

    private func resolvedProjectURL(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return (currentWorkspace?.path ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .appendingPathComponent(path)
            .standardizedFileURL
    }

    // MARK: - Utils

    static var cliOverrideForTests: URL?

    private static func locateGrokCLI() -> URL? {
        if let cliOverrideForTests { return cliOverrideForTests }
        if let p = ProcessInfo.processInfo.environment["GROK_CLI_PATH"], !p.isEmpty {
            let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }
        for c in ["\(NSHomeDirectory())/.grok/bin/grok",
                  "\(NSHomeDirectory())/bin/grok",
                  "/opt/homebrew/bin/grok",
                  "/usr/local/bin/grok"] {
            if FileManager.default.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for d in path.split(separator: ":") {
                let f = URL(fileURLWithPath: String(d)).appendingPathComponent("grok").path
                if FileManager.default.isExecutableFile(atPath: f) { return URL(fileURLWithPath: f) }
            }
        }
        return nil
    }

}

extension FileHandle {
    func bytesStream() -> AsyncStream<Data> {
        AsyncStream { c in
            self.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty {
                    c.finish()
                    h.readabilityHandler = nil
                } else {
                    c.yield(d)
                }
            }
            c.onTermination = { _ in self.readabilityHandler = nil }
        }
    }
}
