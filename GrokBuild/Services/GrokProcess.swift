import CryptoKit
import Darwin
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

/// Explicit, credential-free authority for one armed CLI process. Ambient
/// hard-budget state is intentionally never inherited by a child process.
struct HardBudgetLaunchContract: Sendable, Equatable {
    let manifestPath: String
    let ledgerPath: String
    let allocationID: String
    let expectedManifestSHA256: String
    private let manifestIdentity: HardBudgetAuthorityFileIdentity
    private let ledgerIdentity: HardBudgetAuthorityFileIdentity

    init?(
        manifestPath: String,
        ledgerPath: String,
        allocationID: String,
        expectedManifestSHA256: String
    ) {
        guard NSString(string: manifestPath).isAbsolutePath,
              NSString(string: ledgerPath).isAbsolutePath,
              !allocationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expectedManifestSHA256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
              ) != nil,
              let manifestIdentity = HardBudgetAuthorityFileIdentity.capture(
                path: manifestPath,
                expectedSHA256: expectedManifestSHA256
              ),
              let ledgerIdentity = HardBudgetAuthorityFileIdentity.capture(path: ledgerPath) else { return nil }
        self.manifestPath = manifestPath
        self.ledgerPath = ledgerPath
        self.allocationID = allocationID
        self.expectedManifestSHA256 = expectedManifestSHA256
        self.manifestIdentity = manifestIdentity
        self.ledgerIdentity = ledgerIdentity
    }

    var filesRemainValid: Bool {
        HardBudgetAuthorityFileIdentity.capture(
            path: manifestPath,
            expectedSHA256: expectedManifestSHA256
        ) == manifestIdentity
            && HardBudgetAuthorityFileIdentity.capture(path: ledgerPath) == ledgerIdentity
    }
}

private struct HardBudgetAuthorityFileIdentity: Sendable, Equatable {
    let device: UInt64
    let inode: UInt64
    let size: Int64

    static func capture(path: String, expectedSHA256: String? = nil) -> Self? {
        guard NSString(string: path).isAbsolutePath else { return nil }
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_mode & mode_t(S_IRWXG | S_IRWXO) == 0,
              metadata.st_size >= 0,
              metadata.st_size <= 1_048_576 else { return nil }
        if let expectedSHA256 {
            let expectedSize = Int(metadata.st_size)
            guard let data = try? handle.read(upToCount: expectedSize + 1),
                  data.count == expectedSize,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
                    == expectedSHA256 else { return nil }
        }
        var afterRead = stat()
        guard fstat(descriptor, &afterRead) == 0,
              afterRead.st_dev == metadata.st_dev,
              afterRead.st_ino == metadata.st_ino,
              afterRead.st_size == metadata.st_size else { return nil }
        return Self(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            size: Int64(metadata.st_size)
        )
    }
}

enum GrokProcessLaunchEnvironment {
    static let hardBudgetKeys = [
        "GROK_HARD_TOKEN_BUDGET_LEDGER",
        "GROK_HARD_TOKEN_BUDGET_MANIFEST",
        "GROK_HARD_TOKEN_BUDGET_ALLOCATION",
    ]

    static func resolved(
        base: [String: String],
        hardBudget contract: HardBudgetLaunchContract?
    ) -> [String: String] {
        var environment = base
        hardBudgetKeys.forEach { environment.removeValue(forKey: $0) }
        if let contract {
            environment[hardBudgetKeys[0]] = contract.ledgerPath
            environment[hardBudgetKeys[1]] = contract.manifestPath
            environment[hardBudgetKeys[2]] = contract.allocationID
        }
        return environment
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
    var model: String? = nil             // launch hint plus exact ACP confirmation before ready
    /// The provider-facing model ID Grok may report for a custom `[model.<id>]`
    /// table. `model` remains the config-table selector sent to Grok; this value
    /// only defines the exact alternate readback that is allowed to satisfy the
    /// pre-send confirmation gate.
    var expectedEffectiveModelID: String? = nil
    var sandboxProfile: String? = nil
    var disableWebSearch: Bool = false
    var noSubagents: Bool = false
    var allowRules: [String] = []
    var denyRules: [String] = []
    var resumeSessionID: String? = nil
    var forkSession: Bool = false
    var newSessionID: String? = nil
    var mcpServers: [MCPServerConfig] = []
    /// Exact MCP server identities selected for this process generation. The
    /// gateway Boolean is only the coarse launch state; CLI deny rules and ACP
    /// permission responses enforce this server set individually.
    var allowedMCPServerNames: Set<String> = []
    /// Fresh `grok mcp list` catalog captured before an MCP-enabled launch.
    /// Used only to add CLI-native denies for configured servers the thread did
    /// not select; Grok CLI remains the permission authority.
    var knownConfiguredMCPServerNames: Set<String> = []
    /// Whether an explicit thread/turn selection lets this generation omit the
    /// app's default catch-all MCP deny rule. Grok and user-supplied deny rules
    /// remain authoritative, and the app never mutates global MCP configuration.
    var mcpGatewayEnabled: Bool = false
    var hardBudgetLaunchContract: HardBudgetLaunchContract? = nil
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
    let mcpGatewayEnabled: Bool
    let allowedMCPServerNames: [String]
    var observedCLIConfiguredMCPServerNames: [String]
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
        mcpGatewayEnabled = options.mcpGatewayEnabled
        allowedMCPServerNames = options.allowedMCPServerNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        observedCLIConfiguredMCPServerNames = []
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

enum GrokMCPGatewayLaunchPolicy {
    /// Grok's MCP permission matcher evaluates the full `server__tool` name.
    /// Live CLI 1.0.0 acceptance proved `MCPTool(*)` does not cross that separator;
    /// both halves must be globbed to cover the configured catalog.
    static let catchAllDenyRule = "MCPTool(*__*)"

    static func denyRules(
        userRules: [String],
        gatewayEnabled: Bool,
        allowedServerNames: Set<String> = [],
        knownConfiguredServerNames: Set<String> = []
    ) -> [String] {
        var rules = userRules.filter { !$0.isEmpty }
        if !gatewayEnabled,
           !rules.contains(where: {
               $0.trimmingCharacters(in: .whitespacesAndNewlines) == catchAllDenyRule
           }) {
            rules.append(catchAllDenyRule)
        } else if gatewayEnabled {
            let allowed = Set(allowedServerNames.map(normalizedServerName))
            for server in knownConfiguredServerNames.sorted(by: {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }) {
                let normalized = normalizedServerName(server)
                guard !normalized.isEmpty, !allowed.contains(normalized) else { continue }
                let rule = "MCPTool(\(server)__*)"
                if !rules.contains(rule) { rules.append(rule) }
            }
        }
        return rules
    }

    private static func normalizedServerName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isSafeServerName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty
            && normalized.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
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

    static func transcript(
        backendSessionID: String,
        processGeneration: UInt64,
        envelopes: [ACPStoredUpdateEnvelope]
    ) -> ACPSessionReplayTranscript {
        var accumulator = ACPSessionReplayAccumulator(
            backendSessionID: backendSessionID,
            processGeneration: processGeneration
        )
        for envelope in envelopes {
            guard ["session/update", "x.ai/session/update", "_x.ai/session/update"]
                    .contains(envelope.method),
                  envelope.sessionID == backendSessionID,
                  let update = envelope.foundationUpdate else { continue }
            accumulator.consume(update: update)
        }
        return accumulator.snapshot()
    }
}

/// A bounded, presentation-only transcript captured from the typed replay that
/// `session/load` delivers before its response. It is never routed through the
/// live event stream, so historical tool/thinking/completion events cannot
/// re-drive ChatStore state.
struct ACPSessionReplayTranscript: Sendable, Equatable {
    let backendSessionID: String
    let processGeneration: UInt64
    let messages: [Message]
    let replayEventCount: Int
}

private struct ACPSessionReplayAccumulator {
    let backendSessionID: String
    let processGeneration: UInt64
    private(set) var messages: [Message] = []
    private(set) var replayEventCount = 0
    private var lastUpdateWasUserChunk = false
    private var currentUserPromptIndex: Int?

    init(backendSessionID: String, processGeneration: UInt64) {
        self.backendSessionID = backendSessionID
        self.processGeneration = processGeneration
    }

    mutating func consume(update: [String: Any]) {
        replayEventCount += 1
        guard let kind = update["sessionUpdate"] as? String else { return }
        switch kind {
        case "user_message_chunk":
            guard !Self.isHostTurn(update), let text = Self.text(update), !text.isEmpty else {
                lastUpdateWasUserChunk = false
                return
            }
            let promptIndex = Self.promptIndex(update)
            let opensNewPrompt = !lastUpdateWasUserChunk
                || (promptIndex != nil && promptIndex != currentUserPromptIndex)
            append(text: text, role: .user, forceNewMessage: opensNewPrompt)
            lastUpdateWasUserChunk = true
            currentUserPromptIndex = opensNewPrompt
                ? promptIndex
                : (promptIndex ?? currentUserPromptIndex)
        case "agent_message_chunk":
            guard !Self.isHostTurn(update), let text = Self.text(update), !text.isEmpty else {
                lastUpdateWasUserChunk = false
                return
            }
            append(text: text, role: .assistant)
            lastUpdateWasUserChunk = false
            currentUserPromptIndex = nil
        default:
            lastUpdateWasUserChunk = false
            return
        }
    }

    func snapshot() -> ACPSessionReplayTranscript {
        ACPSessionReplayTranscript(
            backendSessionID: backendSessionID,
            processGeneration: processGeneration,
            messages: messages.filter {
                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            replayEventCount: replayEventCount
        )
    }

    private mutating func append(
        text: String,
        role: MessageRole,
        forceNewMessage: Bool = false
    ) {
        if !forceNewMessage,
           let last = messages.indices.last,
           messages[last].role == role {
            messages[last].content += text
            return
        }
        messages.append(Message(
            role: role,
            content: text,
            provenance: TranscriptMessageProvenance(
                source: .backendRoot,
                backendSessionID: backendSessionID,
                rowIndex: messages.count,
                agent: "root",
                opaqueContentTag: nil
            )
        ))
    }

    private static func text(_ update: [String: Any]) -> String? {
        (update["content"] as? [String: Any])?["text"] as? String
    }

    private static func isHostTurn(_ update: [String: Any]) -> Bool {
        let contentMeta = ((update["content"] as? [String: Any])?["_meta"] as? [String: Any])
        let updateMeta = update["_meta"] as? [String: Any]
        return contentMeta?["hostTurn"] as? Bool == true
            || updateMeta?["hostTurn"] as? Bool == true
    }

    private static func promptIndex(_ update: [String: Any]) -> Int? {
        let contentMeta = (update["content"] as? [String: Any])?["_meta"] as? [String: Any]
        let updateMeta = update["_meta"] as? [String: Any]
        return strictInteger(contentMeta?["promptIndex"] ?? updateMeta?["promptIndex"])
    }

    private static func strictInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(number.stringValue)
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

    // Known ACP session-mode ids. The menu only lists what the CLI advertised;
    // GrokBuild does not invent a Chat row when the backend omits it.
    static let chat  = AgentMode(rawValue: "chat")
    static let agent = AgentMode(rawValue: "agent")
    static let plan  = AgentMode(rawValue: "plan")
    static let yolo  = AgentMode(rawValue: "yolo")

    /// Known ids get stable labels. Unknown ids keep the CLI name and are never
    /// silently renamed Agent.
    var displayName: String {
        switch rawValue {
        case "chat": return "Chat"
        case "agent": return "Agent"
        case "plan": return "Plan"
        case "yolo": return "YOLO"
        default:
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Agent" : trimmed
        }
    }
}

/// Parses ACP session-mode advertisements. Spec-nested
/// `modes: { currentModeId, availableModes }` and top-level `modes` /
/// `availableModes` / `currentModeId` are accepted. `_meta` effort options
/// (`category: "mode"`) are not session modes.
enum AgentSessionModeParsing {
    struct Snapshot: Equatable {
        var current: AgentMode?
        var available: [AgentMode]?
    }

    static func parse(from result: [String: Any]?) -> Snapshot {
        guard let result else { return Snapshot() }

        var current: AgentMode?
        var available: [AgentMode]?

        if let nested = result["modes"] as? [String: Any] {
            current = modeID(from: nested)
            available = modeList(from: nested["availableModes"]) ?? modeList(from: nested["modes"])
        }

        if available == nil {
            available = modeList(from: result["availableModes"]) ?? modeList(from: result["modes"])
        }
        if current == nil {
            current = modeID(from: result)
        }

        return Snapshot(current: current, available: available)
    }

    private static func modeID(from object: [String: Any]) -> AgentMode? {
        let raw = (object["currentModeId"] as? String) ?? (object["mode"] as? String)
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : AgentMode(rawValue: trimmed)
    }

    private static func modeList(from value: Any?) -> [AgentMode]? {
        if let ids = value as? [String] {
            let modes = ids
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { AgentMode(rawValue: $0) }
            return modes.isEmpty ? nil : modes
        }
        if let infos = value as? [[String: Any]] {
            let modes = infos.compactMap { info -> AgentMode? in
                let raw = (info["id"] as? String) ?? (info["modeId"] as? String)
                let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : AgentMode(rawValue: trimmed)
            }
            return modes.isEmpty ? nil : modes
        }
        return nil
    }
}

enum ToolCallTerminalStatus: String, Codable, Sendable, Hashable {
    case succeeded
    case failed
    case cancelled
    case stale
    case unknown

    static func from(rawStatus: String?) -> ToolCallTerminalStatus? {
        guard let rawStatus else { return nil }
        switch rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed", "complete", "success", "succeeded": return .succeeded
        case "failed", "error", "rejected": return .failed
        case "cancelled", "canceled", "cancel": return .cancelled
        case "stale", "superseded": return .stale
        case "running", "in_progress", "pending", "queued", "": return nil
        default: return .unknown
        }
    }
}

struct ToolCall: @unchecked Sendable, Identifiable, Hashable {
    let id: String          // toolCallId
    let kind: String
    let title: String
    let rawInput: [String: Any]?
    let status: String?
    let detail: String?
    let diagnosticDetail: String?
    let target: String?
    /// Typed ACP evidence for catalog discovery versus an actual MCP call.
    let mcpReceiptRole: MCPToolReceiptRole?
    /// Exact provider-qualified capability, e.g. `chrome-devtools__list_pages`.
    let qualifiedToolName: String?
    /// Qualified names returned by this discovery receipt. Schemas and secrets
    /// are deliberately discarded at the transport boundary.
    let discoveredQualifiedToolNames: [String]
    /// Only backend-supplied metadata may link one invocation to the call it retried.
    let retryOfToolCallID: String?
    /// Provider/ACP-reported elapsed time. The client does not fabricate one.
    let durationMilliseconds: Int?

    init(
        id: String,
        kind: String,
        title: String,
        rawInput: [String: Any]?,
        status: String? = nil,
        detail: String? = nil,
        diagnosticDetail: String? = nil,
        target: String? = nil,
        mcpReceiptRole: MCPToolReceiptRole? = nil,
        qualifiedToolName: String? = nil,
        discoveredQualifiedToolNames: [String] = [],
        retryOfToolCallID: String? = nil,
        durationMilliseconds: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rawInput = rawInput
        self.status = status
        self.detail = detail
        self.diagnosticDetail = diagnosticDetail
        self.target = target
        self.mcpReceiptRole = mcpReceiptRole
        self.qualifiedToolName = qualifiedToolName
        self.discoveredQualifiedToolNames = discoveredQualifiedToolNames
        self.retryOfToolCallID = retryOfToolCallID
        self.durationMilliseconds = durationMilliseconds
    }

    var terminalStatus: ToolCallTerminalStatus? {
        ToolCallTerminalStatus.from(rawStatus: status)
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
        if let path = rawInput?["file_path"] as? String { return path }
        if let file = rawInput?["file"] as? String { return file }
        if let args = rawInput?["args"] as? [String], let first = args.first, first.hasPrefix("/") || first.contains(".") {
            return first
        }
        return nil
    }

    /// A successful terminal invocation can author a durable file without using
    /// ACP's dedicated write tool. Admit only an explicit shell redirection target;
    /// prose, command arguments, and terminal capture logs are not artifacts.
    var writtenFilePath: String? {
        if isEdit { return filePath }
        guard let command else { return nil }
        return ShellRedirectionReceipt.outputPath(in: command)
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

enum ShellRedirectionReceipt {
    private static let outputPattern = try! NSRegularExpression(
        pattern: #"(?:^|[\s;&|])>{1,2}\s*(?:'([^']+)'|\"([^\"]+)\"|([^\s;&|]+))"#
    )

    static func outputPath(in command: String) -> String? {
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        let matches = outputPattern.matches(in: command, range: range)
        for match in matches.reversed() {
            for group in 1...3 where match.range(at: group).location != NSNotFound {
                guard let groupRange = Range(match.range(at: group), in: command) else { continue }
                let value = String(command[groupRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty,
                      value != "/dev/null",
                      !value.hasPrefix("&"),
                      !value.hasPrefix("~"),
                      !value.contains("$"),
                      !value.contains("`") else { continue }
                return value
            }
        }
        return nil
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

struct ACPEventIdentity: Sendable, Hashable {
    let localTabID: UUID?
    let backendSessionID: String
    let processGeneration: UInt64
    let backendEventID: String?
}

struct SubagentSpawnedEvent: Sendable, Hashable {
    let identity: ACPEventIdentity
    let childID: String
    let parentPromptID: String?
    let subagentType: String?
    let modelID: String?
    let description: String?

    var deduplicationKey: String {
        "spawn|\(identity.backendSessionID)|\(identity.processGeneration)|\(childID)"
    }
}

struct SubagentFinishedEvent: Sendable, Hashable {
    let identity: ACPEventIdentity
    let childID: String
    let status: String
    let durationMilliseconds: Int?
    let turns: Int?
    let toolCallCount: Int?
    let tokenCount: Int?
    let redactedError: String?
    /// Terminal tool receipts imported from this exact child's backend session.
    /// `nil` means the receipt source was unavailable; an empty array means the
    /// source was read and contained no terminal tool calls.
    var childToolReceipts: [ChildToolReceipt]? = nil

    var deduplicationKey: String {
        "finish|\(identity.backendSessionID)|\(identity.processGeneration)|\(childID)"
    }
}

struct ChildToolReceipt: Codable, Sendable, Hashable {
    let id: String
    let title: String
    let status: ToolCallTerminalStatus
    let mcpReceiptRole: MCPToolReceiptRole?
    let qualifiedToolName: String?
    let discoveredQualifiedToolNames: [String]
}

enum SubagentLifecycleEventPolicy {
    static func ownsActiveSession(
        _ identity: ACPEventIdentity,
        localTabID: UUID?,
        backendSessionID: String?,
        processGeneration: UInt64?
    ) -> Bool {
        guard let localTabID, let backendSessionID, let processGeneration else { return false }
        return identity.localTabID == localTabID
            && identity.backendSessionID == backendSessionID
            && identity.processGeneration == processGeneration
    }
}

// MARK: - Structured ACP Events

enum AcpEvent: @unchecked Sendable {
    case messageChunk(text: String)
    case thoughtChunk(text: String)
    case toolCall(ToolCall)
    case toolCallUpdate(ToolCall)   // simplified
    case subagentSpawned(SubagentSpawnedEvent)
    case subagentFinished(SubagentFinishedEvent)
    case plan(payload: [String: Any])
    case exitPlanRequest(ExitPlanRequest)
    case questionRequest(QuestionRequest)
    case permissionRequest(PermissionRequest)
    case modeChanged(mode: AgentMode)
    /// Complete effective-model catalog replacement from the exact live CLI
    /// generation. This is membership authority, not a provider discovery hint.
    case modelCatalogChanged(ACPModelCatalogEvent)
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
    case turnCompleted(TurnCompletionReceipt)
    /// The prompt RPC returned, but the current CLI never supplied its typed ACP
    /// completion receipt. This crosses the same ordered event queue so the UI can
    /// preserve partial evidence and fail closed; it is never treated as success.
    case turnCompletionReceiptMissing(TurnCompletionBridgeFailure)
    /// Non-ACP stdout. This is retained as a diagnostic event, but is not
    /// transcript content: child-process chatter and provider logs can arrive
    /// here interleaved with structured parent-session updates.
    case rawLine(String)
    case error(String)
}

struct ACPModelCatalogEvent: Sendable, Equatable {
    struct Model: Sendable, Equatable {
        let id: String
        let name: String
        let contextTokens: Int?
    }

    let processGeneration: UInt64
    let currentModelID: String?
    let models: [Model]

    static func parse(_ raw: [String: Any], processGeneration: UInt64) -> ACPModelCatalogEvent? {
        let state = raw["modelState"] as? [String: Any] ?? raw
        guard let available = state["availableModels"] as? [[String: Any]] else { return nil }
        var seen = Set<String>()
        let models = available.compactMap { item -> Model? in
            guard let rawID = item["modelId"] as? String else { return nil }
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let meta = item["_meta"] as? [String: Any]
            return Model(
                id: id,
                name: name?.isEmpty == false ? name! : id,
                contextTokens: meta?["totalContextTokens"] as? Int
            )
        }
        // A malformed row cannot silently shrink the official complete catalog.
        guard models.count == available.count else { return nil }
        return ACPModelCatalogEvent(
            processGeneration: processGeneration,
            currentModelID: state["currentModelId"] as? String,
            models: models
        )
    }
}

/// The terminal parent-turn receipt emitted by ACP. This is deliberately small
/// and credential-free: only final outcome metadata needed by the run-evidence
/// projection crosses the process boundary.
struct ModelUsageReceipt: Sendable, Equatable, Hashable {
    let modelID: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cachedReadTokens: Int?
    let cacheCreationTokens: Int?
    let reasoningTokens: Int?
    let modelCalls: Int?
    let apiDurationMilliseconds: Int?
    let costUsdTicks: Int?

    init(
        modelID: String,
        inputTokens: Int?,
        outputTokens: Int?,
        totalTokens: Int?,
        cachedReadTokens: Int?,
        cacheCreationTokens: Int? = nil,
        reasoningTokens: Int?,
        modelCalls: Int?,
        apiDurationMilliseconds: Int?,
        costUsdTicks: Int?
    ) {
        self.modelID = modelID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.cachedReadTokens = cachedReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reasoningTokens = reasoningTokens
        self.modelCalls = modelCalls
        self.apiDurationMilliseconds = apiDurationMilliseconds
        self.costUsdTicks = costUsdTicks
    }
}

struct TurnCompletionReceipt: Sendable, Equatable {
    let identity: ACPEventIdentity
    let promptID: String?
    let stopReason: String?
    let redactedError: String?
    let totalTokens: Int?
    let modelCalls: Int?
    let turnCount: Int?
    /// Zero-based user prompt index emitted by the backend's authoritative
    /// `user_message_chunk`. Unlike usage `numTurns`, this counts conversation
    /// prompts rather than internal model/tool cycles.
    let backendPromptIndex: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let cachedReadTokens: Int?
    let cacheCreationTokens: Int?
    let reasoningTokens: Int?
    let apiDurationMilliseconds: Int?
    let costUsdTicks: Int?
    let costIsPartial: Bool?
    let modelUsage: [ModelUsageReceipt]

    init(
        identity: ACPEventIdentity,
        promptID: String?,
        stopReason: String?,
        redactedError: String?,
        totalTokens: Int?,
        modelCalls: Int?,
        turnCount: Int?,
        backendPromptIndex: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cachedReadTokens: Int? = nil,
        cacheCreationTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        apiDurationMilliseconds: Int? = nil,
        costUsdTicks: Int? = nil,
        costIsPartial: Bool? = nil,
        modelUsage: [ModelUsageReceipt] = []
    ) {
        self.identity = identity
        self.promptID = promptID
        self.stopReason = stopReason
        self.redactedError = redactedError
        self.totalTokens = totalTokens
        self.modelCalls = modelCalls
        self.turnCount = turnCount
        self.backendPromptIndex = backendPromptIndex
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedReadTokens = cachedReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reasoningTokens = reasoningTokens
        self.apiDurationMilliseconds = apiDurationMilliseconds
        self.costUsdTicks = costUsdTicks
        self.costIsPartial = costIsPartial
        self.modelUsage = modelUsage
    }

    private var normalizedStopReason: String? {
        stopReason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isSuccessful: Bool {
        normalizedStopReason == "end_turn" && redactedError == nil
    }

    var isCancelled: Bool {
        normalizedStopReason == "cancelled" && redactedError == nil
    }

    var isFailure: Bool {
        !isSuccessful && !isCancelled
    }

    /// Stable only when ACP supplies a provider prompt or backend event identity.
    /// The process generation keeps a replay from an older CLI instance from
    /// colliding with a legitimately reused backend identifier.
    var deduplicationKey: String? {
        let stableReceiptID = promptID?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? identity.backendEventID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stableReceiptID, !stableReceiptID.isEmpty else { return nil }
        return "turn|\(identity.backendSessionID)|\(identity.processGeneration)|\(stableReceiptID)"
    }
}

struct TurnCompletionBridgeFailure: Sendable, Equatable {
    let identity: ACPEventIdentity
    let reason: String
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
    /// A transport watchdog for a contract-breaking CLI which returns from
    /// `session/prompt` without ever emitting the ACP completion receipt. It never
    /// manufactures completion: expiry emits a typed bridge failure and the run
    /// remains visibly incomplete.
    private static let turnCompletionReceiptWatchdog: Duration = .seconds(180)
    /// A cancellation is advisory; receipt delivery gets one short chance before
    /// hard teardown. This is deliberately not a completion wait or provider retry.
    private static let stopReceiptDrainWindow: Duration = .milliseconds(150)
    private let ioLock = NSLock()
    private let writeLock = NSLock()
    private let turnCompletionLock = NSLock()
    private let replayLock = NSLock()
    private let cancellationWriteQueue = DispatchQueue(label: "com.grokbuild.acp-cancellation-write")
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

    /// GrokBuild is a same-host ACP client. The Grok CLI must retain filesystem and terminal
    /// execution so its process sandbox, deny rules, and hooks surround the actual operation.
    /// Kept test-visible so the wire claim cannot drift back toward client-side execution.
    static let clientCapabilities: [String: Any] = [
        "fs": ["readTextFile": false, "writeTextFile": false],
        "terminal": false
    ]

    private var nextRequestId = 1
    private struct PendingRequest {
        let continuation: CheckedContinuation<Any?, Error>
        let timeoutTask: Task<Void, Never>?
    }
    private var pendingRequests: [Int: PendingRequest] = [:]
    /// `session/prompt` is lifecycle-owned by `turn_completed`. Grok CLI 1.0 can
    /// omit the matching JSON-RPC response after a rejected tool permission, so
    /// the authoritative completion acknowledgement must also release this one
    /// pending request. A late response is then ignored by normal request lookup.
    private var activePromptRequestID: Int?
    private var turnCompletionContinuation: CheckedContinuation<Bool, Never>?
    private var turnCompletionTimeoutTask: Task<Void, Never>?
    private var turnCompletionResult: Bool?
    private var turnCompletionObservedAtProcessBoundary = false
    private var turnCompletionFailureReason: String?
    /// Latest zero-based prompt index for the active backend generation. This is
    /// captured from a live user-message receipt and consumed by turn completion;
    /// replayed load events never populate it.
    private var activeBackendPromptIndex: Int?
    private var activeSessionReplay: ACPSessionReplayAccumulator?
    private var completedSessionReplay: ACPSessionReplayTranscript?
    private(set) var sessionId: String?
    private(set) var launchReceipt: GrokLaunchReceipt?
    private(set) var mcpServerStatuses: [MCPServerStatus] = []
    private(set) var observedCLIConfiguredMCPServerNames: [String] = []
    private var configuredMCPServerNames: [String] = []
    /// Monotonic launch identity. `activeProcessGeneration == nil` means the most
    /// recent receipt is historical rather than a live-process claim.
    private(set) var processGeneration: UInt64 = 0
    private(set) var activeProcessGeneration: UInt64?
    /// Version and extension capability truth belong to the exact live ACP
    /// process generation. They are never inferred from the app bundle or an
    /// updater catalog.
    private(set) var acpAgentVersion: ACPAgentVersion?
    /// Exact downstream hard-budget authority advertised by the live CLI fork.
    /// An official xAI version number alone never satisfies this capability.
    private(set) var hardTokenBudgetCapability: GrokBuildHardTokenBudgetCapability?
    private let acpControlCapabilities = ACPControlCapabilityRegistry()
    /// True only while Stop is allowing the captured process generation to deliver
    /// final ACP receipts before identity invalidation and hard teardown.
    private(set) var isStopDraining = false
    /// Exact root/descendant evidence for this generation. Teardown signals only
    /// fingerprints captured from this root; it never searches by executable name.
    private(set) var ownedProcessLedger = OwnedProcessLedger()
    /// Set when `session/load` failed with missing on-disk data and `session/new` was used instead.
    private(set) var sessionLoadStartedFreshFallback = false
    private(set) var staleResumeSessionID: String?
    private(set) var currentMode: AgentMode = .agent
    private(set) var availableModes: [AgentMode] = []
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
    private(set) var hasAuthoritativeModelCatalog = false
    private(set) var availableSlashCommands: [SlashCommand] = []
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
        let metadataName = ((tool["_meta"] as? [String: Any])?["x.ai/tool"] as? [String: Any])?["name"] as? String
        if raw["toolName"] == nil, let metadataName {
            raw["toolName"] = metadataName
        }

        // Grok emits terminal tool updates in two equivalent wire shapes. The
        // initial fixture shape keeps `rawOutput` at the update root, while live
        // provider routes place it beside a nested content block in the update's
        // `content` array. Normalize both before deriving typed MCP evidence.
        let rawOutput = Self.rawOutput(from: tool)
        if let output = rawOutput as? [String: Any],
           let server = output["server_name"] as? String,
           let toolName = output["tool_name"] as? String {
            raw["serverName"] = raw["serverName"] ?? server
            if raw["tool_name"] == nil, raw["toolName"] == nil {
                raw["toolName"] = toolName.contains("__") ? toolName : "\(server)__\(toolName)"
            }
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

        let mcpReceiptRole = Self.mcpReceiptRole(
            metadataName: metadataName,
            rawInput: raw,
            rawOutput: rawOutput
        )
        let qualifiedToolName = Self.qualifiedToolName(rawInput: raw, rawOutput: rawOutput, title: title)
        let discoveredQualifiedToolNames = Self.discoveredQualifiedToolNames(rawOutput)
        let status = Self.authoritativeToolStatus(
            backendStatus: tool["status"] as? String,
            rawOutput: rawOutput
        )
        let contentDetail = Self.toolContentText(tool["content"])
        let rawOutputDetail = Self.toolRawOutputText(rawOutput)
        let commandOutputDetail = Self.toolCommandOutputText(rawOutput, kind: kind)
        let terminalFailure = Self.terminalFailureDetail(rawOutput)
        let outputObject = rawOutput as? [String: Any]
        let durationMilliseconds = Self.integer(
            tool["duration_ms"] ?? tool["durationMs"] ?? tool["elapsed_ms"]
                ?? tool["elapsedMs"] ?? outputObject?["duration_ms"]
                ?? outputObject?["durationMs"] ?? outputObject?["elapsed_ms"]
                ?? outputObject?["elapsedMs"]
        )

        return ToolCall(
            id: tcid,
            kind: kind,
            title: title,
            rawInput: raw.isEmpty ? nil : raw,
            status: status,
            detail: Self.redactedToolText(
                terminalFailure ?? commandOutputDetail ?? rawOutputDetail ?? contentDetail,
                limit: 280
            ),
            diagnosticDetail: Self.toolDiagnosticText(rawOutput),
            target: Self.toolTarget(from: raw),
            mcpReceiptRole: mcpReceiptRole,
            qualifiedToolName: qualifiedToolName,
            discoveredQualifiedToolNames: discoveredQualifiedToolNames,
            retryOfToolCallID: Self.retryOfToolCallID(from: tool, rawInput: raw),
            durationMilliseconds: durationMilliseconds
        )
    }

    private static func mcpReceiptRole(
        metadataName: String?,
        rawInput: [String: Any],
        rawOutput: Any?
    ) -> MCPToolReceiptRole? {
        let variant = (rawInput["variant"] as? String)?.lowercased()
        let outputType = ((rawOutput as? [String: Any])?["type"] as? String)?.lowercased()
        let operation = metadataName?.lowercased()
            ?? (rawInput["toolName"] as? String)?.lowercased()
            ?? (rawInput["tool_name"] as? String)?.lowercased()
        if operation == "search_tool" || variant == "searchtool" || outputType == "searchtool" {
            return .discovery
        }
        if operation == "use_tool" || variant == "usetool" || outputType == "mcp" {
            return .invocation
        }
        return nil
    }

    private static func rawOutput(from tool: [String: Any]) -> Any? {
        if let direct = tool["rawOutput"] ?? tool["raw_output"] {
            return direct
        }
        guard let entries = tool["content"] as? [Any] else { return nil }
        for entry in entries {
            guard let item = entry as? [String: Any] else { continue }
            if let nested = item["rawOutput"] ?? item["raw_output"] {
                return nested
            }
        }
        return nil
    }

    private static func qualifiedToolName(
        rawInput: [String: Any],
        rawOutput: Any?,
        title: String
    ) -> String? {
        let candidates = [
            rawInput["tool_name"] as? String,
            rawInput["toolName"] as? String,
            rawInput["name"] as? String,
            title
        ]
        if let qualified = candidates.compactMap(MCPQualifiedToolIdentity.normalized).first {
            return qualified
        }
        let splitServer = (rawInput["serverName"] as? String)
            ?? (rawInput["server_name"] as? String)
        let splitTool = (rawInput["toolName"] as? String)
            ?? (rawInput["tool_name"] as? String)
            ?? (rawInput["name"] as? String)
        if let composed = MCPQualifiedToolIdentity.composed(
            serverName: splitServer,
            toolName: splitTool
        ) {
            return composed
        }
        guard let output = rawOutput as? [String: Any],
              let server = output["server_name"] as? String,
              let tool = output["tool_name"] as? String else { return nil }
        return MCPQualifiedToolIdentity.composed(serverName: server, toolName: tool)
    }

    private static func discoveredQualifiedToolNames(_ rawOutput: Any?) -> [String] {
        guard let output = rawOutput as? [String: Any],
              (output["type"] as? String)?.lowercased() == "searchtool",
              let content = output["content"] as? String,
              let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultGroups = object["results"] as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        return resultGroups.flatMap { ($0["tools"] as? [[String: Any]]) ?? [] }
            .compactMap { MCPQualifiedToolIdentity.normalized($0["tool_name"] as? String) }
            .filter { seen.insert($0).inserted }
            .prefix(64)
            .map { $0 }
    }

    private static func authoritativeToolStatus(
        backendStatus: String?,
        rawOutput: Any?
    ) -> String? {
        guard let output = rawOutput as? [String: Any] else { return backendStatus }
        if integer(output["exit_code"]) != nil,
           integer(output["exit_code"]) != 0 {
            return "failed"
        }
        if output["timed_out"] as? Bool == true { return "failed" }
        if let signal = output["signal"] as? String,
           !signal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "failed"
        }
        return backendStatus
    }

    private static func terminalFailureDetail(_ rawOutput: Any?) -> String? {
        guard let output = rawOutput as? [String: Any] else { return nil }
        if let exitCode = integer(output["exit_code"]), exitCode != 0 {
            return "Command exited with status \(exitCode)."
        }
        if output["timed_out"] as? Bool == true { return "Command timed out." }
        if let signal = output["signal"] as? String,
           !signal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Command ended from signal \(signal)."
        }
        return nil
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

    private static func toolCommandOutputText(_ value: Any?, kind _: String) -> String? {
        let dictionary: [String: Any]?
        if let value = value as? [String: Any] {
            dictionary = value
        } else if let text = value as? String,
                  let data = text.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dictionary = decoded
        } else {
            dictionary = nil
        }
        guard let dictionary else { return nil }
        guard dictionary["command"] != nil || dictionary["exit_code"] != nil else { return nil }

        if let output = dictionary["output"] as? String {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let values = dictionary["output"] as? [Any] {
            let bytes = values.compactMap { value -> UInt8? in
                guard let number = value as? NSNumber,
                      number.intValue >= 0,
                      number.intValue <= 255 else { return nil }
                return UInt8(number.intValue)
            }
            guard bytes.count == values.count else { return nil }
            let decoded = String(decoding: bytes, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }

    private static func toolDiagnosticText(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text: String?
        if let string = value as? String {
            text = string
        } else if JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) {
            text = json
        } else {
            text = nil
        }
        return redactedToolText(text, limit: 2_000)
    }

    private static func toolTarget(from rawInput: [String: Any]) -> String? {
        let target = (rawInput["url"] as? String)
            ?? (rawInput["file_path"] as? String)
            ?? (rawInput["path"] as? String)
            ?? (rawInput["command"] as? String)
            ?? (rawInput["cmd"] as? String)
        return redactedToolText(target, limit: 280)
    }

    private static func retryOfToolCallID(
        from tool: [String: Any],
        rawInput: [String: Any]
    ) -> String? {
        let keys = [
            "retryOfToolCallId", "retry_of_tool_call_id", "retryOf", "retry_of",
            "parentToolCallId", "parent_tool_call_id", "parentId", "parent_id",
        ]
        for key in keys {
            if let id = tool[key] as? String ?? rawInput[key] as? String {
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func redactedToolText(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let redacted = GrokMCPRedactor.redact(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !redacted.isEmpty else { return nil }
        return String(redacted.prefix(limit))
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
        acpAgentVersion = nil
        hardTokenBudgetCapability = nil
        acpControlCapabilities.reset(generation: launchGeneration, agentVersion: nil)
        configuredMCPServerNames = options.mcpServers.map(\.name)
        observedCLIConfiguredMCPServerNames = []
        mcpServerStatuses = MCPReadinessPolicy.connectingStatuses(for: options.mcpServers)
        let launchIdentity = ModelRequestIdentity(
            localTabID: options.localTabID,
            backendSessionID: options.resumeSessionID,
            processGeneration: launchGeneration,
            requestID: UUID()
        )

        state = .starting
        currentWorkspace = workspace
        sessionId = nil
        activeBackendPromptIndex = nil
        resetSessionReplayCapture()
        launchReceipt = nil
        sessionLoadStartedFreshFallback = false
        staleResumeSessionID = nil
        currentMode = .agent
        availableModes = []
        currentModelId = nil
        modelExecutionState = ModelExecutionReducer.launch(
            requestedModelID: options.model,
            identity: launchIdentity
        )
        availableModelsInfo.removeAll()
        hasAuthoritativeModelCatalog = false

        guard options.hardBudgetLaunchContract?.filesRemainValid != false else {
            var receipt = GrokLaunchReceipt(
                options: options,
                workspaceID: workspace.id,
                processGeneration: launchGeneration
            )
            receipt.outcome = .failed
            launchReceipt = receipt
            rejectLaunchModelReceipt(identity: launchIdentity)
            activeProcessGeneration = nil
            mcpServerStatuses = MCPReadinessPolicy.failedStatuses(for: options.mcpServers)
            state = .failed("Acceptance authority changed after authorization. No Grok process was launched.")
            return
        }

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
            mcpServerStatuses = MCPReadinessPolicy.failedStatuses(for: options.mcpServers)
            state = .failed("Could not locate the `grok` CLI. Run `grok login` or set GROK_CLI_PATH.")
            return
        }

        let proc = Process()
        proc.executableURL = cli
        proc.currentDirectoryURL = workspace.path
        proc.environment = GrokProcessLaunchEnvironment.resolved(
            base: ProcessInfo.processInfo.environment,
            hardBudget: options.hardBudgetLaunchContract
        )

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
        for rule in GrokMCPGatewayLaunchPolicy.denyRules(
            userRules: options.denyRules,
            gatewayEnabled: options.mcpGatewayEnabled,
            allowedServerNames: options.allowedMCPServerNames,
            knownConfiguredServerNames: options.knownConfiguredMCPServerNames
        ) {
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
            mcpServerStatuses = MCPReadinessPolicy.failedStatuses(for: options.mcpServers)
            state = .failed("Failed to launch: \(error.localizedDescription)")
            return
        }
        GrokBuildPerformance.mark(.processSpawned)

        launchReceipt = GrokLaunchReceipt(
            options: options,
            workspaceID: workspace.id,
            processIdentifier: proc.processIdentifier,
            processGeneration: launchGeneration
        )
        ownedProcessLedger.begin(OwnedProcessIdentity(
            localTabID: options.localTabID,
            backendSessionID: nil,
            processGeneration: launchGeneration,
            rootPID: proc.processIdentifier
        ))

        self.process = proc
        self.stdin = i.fileHandleForWriting
        self.stdout = o
        self.stderr = e
        self.stdoutBuffer = Data()
        self.startupStderr = ""

        setupReaders(stdout: o, stderr: e, processGeneration: launchGeneration)

        do {
            try await initializeACP()
            GrokBuildPerformance.mark(.acpReady)
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
            GrokBuildPerformance.mark(.sessionReady)
            ownedProcessLedger.rebindBackend(sessionId)
            guard activeProcessGeneration == launchGeneration else { return }
            try await confirmRequestedLaunchModel(
                options.model,
                expectedEffectiveModelID: options.expectedEffectiveModelID,
                processGeneration: launchGeneration
            )
            GrokBuildPerformance.mark(.modelConfirmed)
            guard activeProcessGeneration == launchGeneration else { return }
            // `session/new` can resolve before Grok's stdio MCP children finish
            // their initialize/tools-list handshake. Keep the process non-ready
            // until the bounded barrier has elapsed so the first billable turn
            // cannot race tool discovery.
            try await MCPReadinessPolicy.waitForInitialMCPSet(options.mcpServers)
            GrokBuildPerformance.mark(.selectedMCPReady)
            guard activeProcessGeneration == launchGeneration else { return }
            mcpServerStatuses = MCPReadinessPolicy.readyStatuses(for: options.mcpServers)
            settleLaunchModelReceipt(identity: launchIdentity)
            updateLaunchReceipt(outcome: launchOutcome, backendSessionID: sessionId)
            state = .ready
        } catch {
            guard activeProcessGeneration == launchGeneration else { return }
            let stderrDetails = Self.redactedStartupStderr(startupStderrSnapshot())
            let suffix = stderrDetails.isEmpty ? "" : "\n\(stderrDetails)"
            state = .failed("ACP startup failed: \(error.localizedDescription)\(suffix)")
            await cleanupProcess(setIdle: false)
            mcpServerStatuses = MCPReadinessPolicy.failedStatuses(for: options.mcpServers)
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
        // Quit does not need an acknowledgement: closing stdin immediately tells
        // Grok to exit and avoids retaining a process solely for a courtesy drain.
        await cleanupProcess(setIdle: false, sendCancel: false)
        acpEventContinuation?.finish()
        acpEventContinuation = nil
    }

    private func cleanupProcess(setIdle: Bool, sendCancel: Bool = true) async {
        if modelExecutionState.isPending,
           let identity = modelExecutionState.identity,
           identity.processGeneration == activeProcessGeneration {
            _ = ModelExecutionReducer.reject(
                failure: .processStopped,
                identity: identity,
                state: &modelExecutionState
            )
        }
        let closingGeneration = activeProcessGeneration
        let closingBackendID = sessionId ?? launchReceipt?.backendSessionID
        let closingTabID = launchReceipt?.localTabID
        if let rootPID = process?.processIdentifier {
            ownedProcessLedger.record(OwnedProcessTree.fingerprints(
                of: OwnedProcessTree.descendants(of: rootPID)
            ))
        }
        let ownedChildren = ownedProcessLedger.children.filter {
            guard let closingGeneration else { return false }
            return ownedProcessLedger.owns(
                localTabID: closingTabID,
                backendSessionID: closingBackendID,
                processGeneration: closingGeneration,
                child: $0
            )
        }
        let closingStdin = stdin
        let shouldDrainStopReceipts = sendCancel && closingGeneration != nil && closingStdin != nil
        if shouldDrainStopReceipts, let sid = sessionId, let closingStdin {
            // Keep this exact generation and its readers alive briefly so a terminal
            // completion already in flight can cross ACP before teardown. The write
            // occurs on a dedicated queue and targets this captured old handle: a
            // blocked CLI stdin must never pin the SwiftUI/MainActor path or a later
            // process generation.
            isStopDraining = true
            writeCancellationAsynchronously(sessionID: sid, to: closingStdin)
            try? await Task.sleep(for: Self.stopReceiptDrainWindow)
        }

        activeProcessGeneration = nil
        isStopDraining = false
        readerTask?.cancel()
        readerTask = nil
        stdout?.fileHandleForReading.readabilityHandler = nil
        stderr?.fileHandleForReading.readabilityHandler = nil
        finishTurnCompletionWait()
        try? closingStdin?.close()

        if let p = process, p.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
            if p.isRunning { p.terminate() }
            // SIGTERM alone can lose the race with a busy child, and grok's MCP helper
            // children (browser, computer use) exit only when their stdin pipes close —
            // which happens exactly when grok dies. Escalate so quit can never strand
            // the whole process tree past the app's own exit.
            if p.isRunning {
                try? await Task.sleep(for: .milliseconds(300))
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
        }
        // A helper can outlive its parent after reparenting, so a post-parent tree
        // search is too late. Signal only the pre-close fingerprints that still match
        // their original executable and process start time.
        OwnedProcessTree.signal(SIGTERM, to: ownedChildren)
        if ownedChildren.contains(where: OwnedProcessTree.stillMatches) {
            try? await Task.sleep(for: .milliseconds(300))
            OwnedProcessTree.signal(SIGKILL, to: ownedChildren)
        }

        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        sessionId = nil
        activeBackendPromptIndex = nil
        if launchReceipt?.outcome != .failed {
            updateLaunchReceipt(outcome: .stopped, backendSessionID: launchReceipt?.backendSessionID)
        }
        if setIdle {
            mcpServerStatuses = MCPReadinessPolicy.stoppedStatuses(for: configuredMCPServerNames)
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

    /// grok 0.2.118 accepts `--model` for `agent stdio`, but `session/new` can still
    /// report and use the default Grok model. Reassert an explicit launch selection over
    /// ACP and require an exact readback before the process becomes sendable. This keeps a
    /// custom-provider tab from silently billing the default provider.
    private func confirmRequestedLaunchModel(
        _ requestedModelID: String?,
        expectedEffectiveModelID: String?,
        processGeneration: UInt64
    ) async throws {
        let requested = requestedModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expected = expectedEffectiveModelID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requested.isEmpty else { return }
        var acceptedReadbacks: Set<String> = [requested]
        if let expected, !expected.isEmpty {
            acceptedReadbacks.insert(expected)
        }
        guard !acceptedReadbacks.contains(currentModelId ?? "") else { return }
        guard let sid = sessionId else {
            throw NSError(
                domain: "ACP",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Grok did not create a session for the requested model."]
            )
        }

        let result = try await sendRequestWithTimeout(
            method: "session/set_model",
            params: ["sessionId": sid, "modelId": requested],
            seconds: 12
        ) as? [String: Any]
        guard activeProcessGeneration == processGeneration else { return }
        guard let effective = Self.effectiveModelID(from: result) else {
            currentModelId = nil
            throw NSError(
                domain: "ACP",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Grok accepted the model request without confirming the live model."]
            )
        }
        guard acceptedReadbacks.contains(effective) else {
            currentModelId = effective
            throw NSError(
                domain: "ACP",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Grok confirmed \(effective) instead of the requested model \(requested)."]
            )
        }
        currentModelId = effective
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
        guard let sid = sessionId,
              let generation = activeProcessGeneration,
              state == .ready || state == .busy else { return false }
        state = .busy
        beginTurnCompletionWait()

        do {
            _ = try await sendRequest(method: "session/prompt", params: [
                "sessionId": sid,
                "prompt": [["type": "text", "text": text]]
            ])
            // `session/prompt` may resolve before the final text/lifecycle updates.
            // Only the typed ACP completion receipt may produce a successful turn;
            // the watchdog reports a broken bridge without impersonating completion.
            let completionWasAuthoritative = await awaitTurnCompletion(
                identity: ACPEventIdentity(
                    localTabID: launchReceipt?.localTabID,
                    backendSessionID: sid,
                    processGeneration: generation,
                    backendEventID: nil
                )
            )
            guard completionWasAuthoritative else {
                let reason = completionWatchdogFailureReason()
                state = .failed(reason)
                updateLaunchReceipt(outcome: .failed, backendSessionID: sid)
                mcpServerStatuses = MCPReadinessPolicy.failedStatuses(
                    for: configuredMCPServerNames,
                    reason: "The ACP completion bridge failed."
                )
                await cleanupProcess(setIdle: false)
                state = .failed(reason)
                return false
            }
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
        guard availableModes.contains(mode) else { return }
        Task {
            await confirmSetMode(mode, sessionId: sid)
        }
    }

    /// Sends `session/set_mode` only for an advertised id. Empty success is not
    /// confirmation; persist only from `currentModeId` on the result or a later
    /// `current_mode_update`.
    private func confirmSetMode(_ mode: AgentMode, sessionId: String) async {
        let result = try? await sendRequestWithTimeout(method: "session/set_mode", params: [
            "sessionId": sessionId,
            "modeId": mode.rawValue
        ])
        applyAuthoritativeModeResult(result)
    }

    private func applyAuthoritativeModeResult(_ result: Any?) {
        guard let dict = result as? [String: Any] else { return }
        let snapshot = AgentSessionModeParsing.parse(from: dict)
        guard let current = snapshot.current else { return }
        currentMode = current
        acpEventContinuation?.yield(.modeChanged(mode: current))
    }

    func setMode(_ modeId: String) {
        setMode(AgentMode(rawValue: modeId))
    }

    @discardableResult
    func setModel(
        _ modelId: String,
        expectedEffectiveModelID: String? = nil
    ) -> ModelSwitchHandle? {
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
                    let expected = expectedEffectiveModelID?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    var acceptedReadbacks: Set<String> = [modelId]
                    if let expected, !expected.isEmpty {
                        acceptedReadbacks.insert(expected)
                    }
                    guard acceptedReadbacks.contains(effective) else {
                        self.currentModelId = effective
                        self.modelSwitchError = "Grok confirmed \(effective) instead of the requested model \(modelId). Start a new session before sending another prompt."
                        self.modelSwitchNeedsNewSession = true
                        _ = ModelExecutionReducer.reject(
                            failure: .rejected,
                            identity: identity,
                            state: &self.modelExecutionState
                        )
                        self.state = .failed(self.modelSwitchError ?? "Grok confirmed an unexpected model.")
                        return self.modelExecutionState
                    }
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
        guard let line = Self.jsonLine(obj) else { return false }
        return writeLine(line, to: stdin)
    }

    private func writeCancellationAsynchronously(sessionID: String, to handle: FileHandle) {
        guard let line = Self.jsonLine([
            "jsonrpc": "2.0",
            "method": "session/cancel",
            "params": ["sessionId": sessionID]
        ]) else { return }
        cancellationWriteQueue.async {
            // This deliberately does not take `writeLock`: if the old CLI stdin is
            // full, its stuck courtesy cancellation must not lock future writes to a
            // newly launched process generation.
            try? handle.write(contentsOf: line)
        }
    }

    private static func jsonLine(_ obj: [String: Any]) -> Data? {
        let data: Data
        if #available(macOS 12.0, *) {
            guard let encoded = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.withoutEscapingSlashes]
            ) else { return nil }
            data = encoded
        } else {
            guard let encoded = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            data = encoded
        }
        var line = data
        line.append("\n".data(using: .utf8)!)
        return line
    }

    private func writeLine(_ line: Data, to handle: FileHandle?) -> Bool {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard let handle else { return false }
        do { try handle.write(contentsOf: line); return true } catch { return false }
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
            if method == "session/prompt" {
                activePromptRequestID = id
            }
            ioLock.unlock()
            if !writeJson(req) {
                ioLock.lock()
                pendingRequests.removeValue(forKey: id)
                if activePromptRequestID == id { activePromptRequestID = nil }
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

    // MARK: - Typed ACP control plane

    /// Test-visible capability state for the exact live process generation.
    func acpControlCapabilityState(for method: ACPControlMethod) -> ACPControlCapabilityState {
        guard let generation = activeProcessGeneration else { return .unsupported }
        return acpControlCapabilities.state(for: method, generation: generation)
    }

    func fetchACPModelCatalog() async throws -> ACPControlModelCatalog {
        try ACPControlModelCatalog.parse(
            try await sendACPControlRequest(.models, params: [:], seconds: 5)
        )
    }

    func fetchACPSessionUsage() async throws -> ACPControlSessionUsage {
        guard let sessionId else { throw ACPControlError.noActiveConnection }
        return try ACPControlSessionUsage.parse(
            try await sendACPControlRequest(
                .sessionUsage,
                params: ["sessionId": sessionId],
                seconds: 3
            )
        )
    }

    func fetchHardTokenBudgetCapability() async throws -> GrokBuildHardTokenBudgetCapability {
        guard let generation = activeProcessGeneration,
              hardTokenBudgetCapability != nil else {
            throw ACPControlError.invalidStandardResponse(
                method: GrokBuildHardTokenBudgetCapability.statusMethod,
                reason: "the live CLI did not advertise the GrokBuild hard-budget capability"
            )
        }
        let raw = try await sendRequestWithTimeout(
            method: GrokBuildHardTokenBudgetCapability.statusMethod,
            params: [:],
            seconds: 3
        )
        guard activeProcessGeneration == generation else {
            throw ACPControlError.staleConnection
        }
        guard let capability = GrokBuildHardTokenBudgetCapability.parse(raw) else {
            throw ACPControlError.invalidStandardResponse(
                method: GrokBuildHardTokenBudgetCapability.statusMethod,
                reason: "malformed capability receipt"
            )
        }
        hardTokenBudgetCapability = capability
        return capability
    }

    func fetchACPSessionMetadata() async throws -> ACPControlSessionMetadata {
        guard let sessionId else { throw ACPControlError.noActiveConnection }
        return try ACPControlSessionMetadata.parse(
            try await sendACPControlRequest(
                .sessionInfo,
                params: ["sessionId": sessionId],
                seconds: 3
            )
        )
    }

    func fetchACPSessionUpdates(
        sessionID: String,
        offset: Int,
        limit: Int
    ) async throws -> ACPControlSessionUpdatePage {
        guard !sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ACPControlError.invalidRequest("sessionID is empty")
        }
        guard (1...ACPControlSessionUpdatePage.maximumLimit).contains(limit) else {
            throw ACPControlError.invalidRequest(
                "limit must be 1...\(ACPControlSessionUpdatePage.maximumLimit)"
            )
        }
        guard let cwd = currentWorkspace?.path.path else {
            throw ACPControlError.noActiveConnection
        }
        let page = try ACPControlSessionUpdatePage.parse(
            try await sendACPControlRequest(
                .sessionUpdates,
                params: [
                    "sessionId": sessionID,
                    "cwd": cwd,
                    "offset": offset,
                    "limit": limit,
                    "stream": false,
                ],
                seconds: 3
            )
        )
        guard page.updates.count <= limit else {
            throw ACPControlError.invalidResponse(
                method: .sessionUpdates,
                reason: "page exceeded requested limit"
            )
        }
        return page
    }

    func fetchACPStandardSessionList(
        cwd: URL,
        cursor: String? = nil
    ) async throws -> ACPStandardSessionListPage {
        guard let generation = activeProcessGeneration else {
            throw ACPControlError.noActiveConnection
        }
        var params: [String: Any] = [
            "cwd": cwd.path,
            "additionalDirectories": [],
        ]
        if let cursor, !cursor.isEmpty { params["cursor"] = cursor }
        let page = try ACPStandardSessionListPage.parse(
            try await sendRequestWithTimeout(
                method: "session/list",
                params: params,
                seconds: 3
            )
        )
        guard activeProcessGeneration == generation else {
            throw ACPControlError.staleConnection
        }
        return page
    }

    /// Bounded official history for recovery review/relink. The xAI extension
    /// filters rewound branches before returning envelopes. Oversized histories
    /// fail closed instead of returning a misleading prefix.
    func fetchOfficialSessionReplayTranscript(
        sessionID: String,
        maximumUpdates: Int = 4_096
    ) async throws -> ACPSessionReplayTranscript {
        guard let generation = activeProcessGeneration else {
            throw ACPControlError.noActiveConnection
        }
        let pageLimit = ACPControlSessionUpdatePage.maximumLimit
        var offset = 0
        var envelopes: [ACPStoredUpdateEnvelope] = []
        var hasMore = true
        while offset < maximumUpdates {
            let page = try await fetchACPSessionUpdates(
                sessionID: sessionID,
                offset: offset,
                limit: min(pageLimit, maximumUpdates - offset)
            )
            envelopes.append(contentsOf: page.updates)
            offset += page.updates.count
            hasMore = page.hasMore
            if !hasMore || page.updates.isEmpty { break }
        }
        guard activeProcessGeneration == generation else {
            throw ACPControlError.staleConnection
        }
        guard !hasMore else {
            throw ACPControlError.invalidResponse(
                method: .sessionUpdates,
                reason: "recovery history exceeded the 4096-update safety bound"
            )
        }
        return GrokSessionReplay.transcript(
            backendSessionID: sessionID,
            processGeneration: generation,
            envelopes: envelopes
        )
    }

    private func sendACPControlRequest(
        _ method: ACPControlMethod,
        params: [String: Any],
        seconds: Double
    ) async throws -> Any? {
        guard let generation = activeProcessGeneration else {
            throw ACPControlError.noActiveConnection
        }
        guard acpControlCapabilities.shouldAttempt(method, generation: generation) else {
            throw ACPControlError.unavailable(
                method: method,
                agentVersion: acpAgentVersion?.rawValue
            )
        }
        do {
            let result = try await sendRequestWithTimeout(
                method: method.rawValue,
                params: params,
                seconds: seconds
            )
            guard activeProcessGeneration == generation else {
                throw ACPControlError.staleConnection
            }
            acpControlCapabilities.record(.supported, for: method, generation: generation)
            return result
        } catch {
            let nsError = error as NSError
            if (nsError.userInfo["jsonRPCCode"] as? Int) == -32601 {
                acpControlCapabilities.record(.unsupported, for: method, generation: generation)
                throw ACPControlError.unavailable(
                    method: method,
                    agentVersion: acpAgentVersion?.rawValue
                )
            }
            throw error
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
        turnCompletionResult = nil
        turnCompletionObservedAtProcessBoundary = false
        turnCompletionFailureReason = nil
        turnCompletionLock.unlock()
        staleTimeout?.cancel()
        staleContinuation?.resume(returning: false)
    }

    private func awaitTurnCompletion(identity: ACPEventIdentity) async -> Bool {
        await withCheckedContinuation { continuation in
            turnCompletionLock.lock()
            if let result = turnCompletionResult {
                turnCompletionResult = nil
                turnCompletionLock.unlock()
                continuation.resume(returning: result)
                return
            }
            turnCompletionContinuation = continuation
            turnCompletionTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.turnCompletionReceiptWatchdog)
                guard !Task.isCancelled else { return }
                let reason = self?.completionWatchdogFailureReason()
                    ?? "The prompt RPC returned without an authoritative ACP completion receipt."
                self?.acpEventContinuation?.yield(.turnCompletionReceiptMissing(
                    TurnCompletionBridgeFailure(
                        identity: identity,
                        reason: reason
                    )
                ))
            }
            turnCompletionLock.unlock()
        }
    }

    /// Called by ChatStore after it consumes the `.turnCompleted` event. This keeps
    /// prompt completion serialized behind all earlier text/tool events.
    func acknowledgeTurnCompletionBridge(authoritative: Bool) {
        turnCompletionLock.lock()
        turnCompletionResult = authoritative
        let continuation = turnCompletionContinuation
        let timeout = turnCompletionTimeoutTask
        turnCompletionContinuation = nil
        turnCompletionTimeoutTask = nil
        turnCompletionLock.unlock()
        timeout?.cancel()
        continuation?.resume(returning: authoritative)
        if authoritative {
            releasePendingPromptRequestAfterAuthoritativeCompletion()
        }
    }

    private func releasePendingPromptRequestAfterAuthoritativeCompletion() {
        ioLock.lock()
        let promptID = activePromptRequestID
        activePromptRequestID = nil
        let pending = promptID.flatMap { pendingRequests.removeValue(forKey: $0) }
        ioLock.unlock()
        pending?.timeoutTask?.cancel()
        pending?.continuation.resume(returning: nil)
    }

    /// Records an exact ownership rejection instead of silently waiting for the
    /// transport watchdog. This remains a failed bridge receipt; it cannot settle
    /// usage, continuity, workers, or the visible turn as successful.
    func rejectTurnCompletionBridge(reason: String) {
        turnCompletionLock.lock()
        turnCompletionFailureReason = reason
        turnCompletionLock.unlock()
        acknowledgeTurnCompletionBridge(authoritative: false)
    }

    private func recordTurnCompletionObservedAtProcessBoundary() {
        turnCompletionLock.lock()
        turnCompletionObservedAtProcessBoundary = true
        turnCompletionLock.unlock()
    }

    private func completionWatchdogFailureReason() -> String {
        turnCompletionLock.lock()
        let observed = turnCompletionObservedAtProcessBoundary
        let explicitReason = turnCompletionFailureReason
        turnCompletionLock.unlock()
        if let explicitReason { return explicitReason }
        if observed {
            return "ACP turn_completed passed transport and process identity validation, but the active ChatStore turn did not acknowledge it."
        }
        return "The prompt RPC returned, but the ACP transport did not report an authoritative turn_completed receipt."
    }

    private func finishTurnCompletionWait() {
        turnCompletionLock.lock()
        let continuation = turnCompletionContinuation
        let timeout = turnCompletionTimeoutTask
        turnCompletionContinuation = nil
        turnCompletionTimeoutTask = nil
        turnCompletionResult = nil
        turnCompletionLock.unlock()
        timeout?.cancel()
        continuation?.resume(returning: false)
    }

    private func drainPendingRequests(with error: Error) {
        ioLock.lock()
        let pending = Array(pendingRequests.values)
        pendingRequests.removeAll()
        activePromptRequestID = nil
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

    static func redactedStartupStderr(_ text: String) -> String {
        let redacted = GrokMCPRedactor.redact(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(redacted.prefix(2_000))
    }

    private func initializeACP() async throws {
        let res = try await sendRequestWithTimeout(method: "initialize", params: [
            "protocolVersion": 1,
            "clientCapabilities": Self.clientCapabilities
        ]) as? [String: Any]

        // Parse real models from modelState (do not make up)
        let meta = res?["_meta"] as? [String: Any]
        acpAgentVersion = (meta?["agentVersion"] as? String).flatMap(ACPAgentVersion.init)
        hardTokenBudgetCapability = GrokBuildHardTokenBudgetCapability.parse(
            meta?[GrokBuildHardTokenBudgetCapability.metadataKey]
        )
        if let generation = activeProcessGeneration {
            acpControlCapabilities.reset(generation: generation, agentVersion: acpAgentVersion)
        }
        if let ms = (res?["modelState"] as? [String: Any]) ?? (meta?["modelState"] as? [String: Any]),
           let event = ACPModelCatalogEvent.parse(ms, processGeneration: activeProcessGeneration ?? 0) {
            applyModelCatalog(event)
        }
        // Official 1.0.5 waits for the first real catalog on this extension.
        // Use it only when initialize did not already provide models, and never
        // make launch depend on a non-standard method.
        if !hasAuthoritativeModelCatalog,
           let acpAgentVersion,
           acpAgentVersion >= ACPControlMethod.models.officialExtensionFloor,
           let catalog = try? await fetchACPModelCatalog() {
            currentModelId = catalog.currentModelID ?? currentModelId
            availableModelsInfo = catalog.availableModels.map {
                (id: $0.id, name: $0.name, contextTokens: $0.contextTokens)
            }
            hasAuthoritativeModelCatalog = true
        }
    }

    private func createSession(workspace: Workspace, mcpServers: [MCPServerConfig]) async throws {
        let res = try await sendRequestWithTimeout(method: "session/new", params: [
            "cwd": workspace.path.path,
            "mcpServers": mcpServers.map(\.jsonObject)
        ]) as? [String: Any]
        sessionId = res?["sessionId"] as? String
        updateModels(from: res?["models"] as? [String: Any])
        applySessionModes(from: res)
    }

    private func loadSession(id: String, workspace: Workspace, mcpServers: [MCPServerConfig]) async throws {
        sessionId = id
        guard let generation = activeProcessGeneration else {
            throw ACPControlError.noActiveConnection
        }
        beginSessionReplayCapture(backendSessionID: id, processGeneration: generation)
        let res: [String: Any]?
        do {
            res = try await sendRequestWithTimeout(method: "session/load", params: [
                "sessionId": id,
                "cwd": workspace.path.path,
                "mcpServers": mcpServers.map(\.jsonObject)
            ]) as? [String: Any]
        } catch {
            cancelSessionReplayCapture(backendSessionID: id, processGeneration: generation)
            sessionId = nil
            throw error
        }
        finishSessionReplayCapture(backendSessionID: id, processGeneration: generation)
        updateModels(from: res?["models"] as? [String: Any])
        applySessionModes(from: res)
    }

    private func beginSessionReplayCapture(backendSessionID: String, processGeneration: UInt64) {
        replayLock.lock()
        completedSessionReplay = nil
        activeSessionReplay = ACPSessionReplayAccumulator(
            backendSessionID: backendSessionID,
            processGeneration: processGeneration
        )
        replayLock.unlock()
    }

    private func resetSessionReplayCapture() {
        replayLock.lock()
        activeSessionReplay = nil
        completedSessionReplay = nil
        replayLock.unlock()
    }

    private func recordSessionReplay(
        update: [String: Any],
        eventSessionID: String?,
        processGeneration: UInt64
    ) {
        replayLock.lock()
        defer { replayLock.unlock() }
        guard var capture = activeSessionReplay,
              capture.processGeneration == processGeneration,
              eventSessionID == capture.backendSessionID else { return }
        capture.consume(update: update)
        activeSessionReplay = capture
    }

    private func finishSessionReplayCapture(backendSessionID: String, processGeneration: UInt64) {
        replayLock.lock()
        defer { replayLock.unlock() }
        guard let capture = activeSessionReplay,
              capture.backendSessionID == backendSessionID,
              capture.processGeneration == processGeneration else { return }
        completedSessionReplay = capture.snapshot()
        activeSessionReplay = nil
    }

    private func cancelSessionReplayCapture(backendSessionID: String, processGeneration: UInt64) {
        replayLock.lock()
        if activeSessionReplay?.backendSessionID == backendSessionID,
           activeSessionReplay?.processGeneration == processGeneration {
            activeSessionReplay = nil
        }
        completedSessionReplay = nil
        replayLock.unlock()
    }

    /// Consumes only the replay captured for this exact loaded backend and live
    /// process generation. A stale tab/process can never borrow another load's
    /// transcript candidate.
    func takeLoadedSessionReplay(
        backendSessionID: String,
        processGeneration: UInt64
    ) -> ACPSessionReplayTranscript? {
        replayLock.lock()
        defer { replayLock.unlock() }
        guard let replay = completedSessionReplay,
              replay.backendSessionID == backendSessionID,
              replay.processGeneration == processGeneration else { return nil }
        completedSessionReplay = nil
        return replay
    }

    private func applySessionModes(from result: [String: Any]?) {
        let snapshot = AgentSessionModeParsing.parse(from: result)
        if let available = snapshot.available {
            availableModes = available
        } else {
            availableModes = []
        }
        if let current = snapshot.current {
            currentMode = current
        } else {
            currentMode = .agent
        }
    }

    private func updateModels(from modelState: [String: Any]?) {
        guard let modelState else { return }
        guard let generation = activeProcessGeneration,
              let event = ACPModelCatalogEvent.parse(modelState, processGeneration: generation) else {
            currentModelId = modelState["currentModelId"] as? String ?? currentModelId
            return
        }
        applyModelCatalog(event)
    }

    private func applyModelCatalog(_ event: ACPModelCatalogEvent) {
        guard activeProcessGeneration == event.processGeneration else { return }
        currentModelId = event.currentModelID ?? currentModelId
        availableModelsInfo = event.models.map {
            (id: $0.id, name: $0.name, contextTokens: $0.contextTokens)
        }
        hasAuthoritativeModelCatalog = true
    }

    private func setupReaders(stdout: Pipe, stderr: Pipe, processGeneration: UInt64) {
        // Process pipe I/O synchronously on the reader thread. Dispatching to
        // MainActor here deadlocks because start() awaits ACP responses on MainActor.
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.handleStdoutData(data, processGeneration: processGeneration)
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

    private func handleStdoutData(_ data: Data, processGeneration: UInt64) {
        guard activeProcessGeneration == processGeneration else { return }
        ioLock.lock()
        let lines = AcpLineBuffer.drainLines(buffer: &stdoutBuffer, appending: data)
        ioLock.unlock()

        for rawLine in lines {
            handleAcpRawLine(rawLine, processGeneration: processGeneration)
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

    private func handleAcpRawLine(_ rawLine: String, processGeneration: UInt64) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        handleJsonLine(line, processGeneration: processGeneration)
    }

    private func handleJsonLine(_ line: String, processGeneration: UInt64) {
        guard activeProcessGeneration == processGeneration else { return }
        guard let data = line.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            acpEventContinuation?.yield(.rawLine(line))
            return
        }

        if let method = j["method"] as? String {
            let params = j["params"] as? [String: Any] ?? [:]
            let rid = j["id"]

            if method == "_x.ai/mcp/servers_updated" {
                observedCLIConfiguredMCPServerNames = Self.mcpServerNames(from: params)
                launchReceipt?.observedCLIConfiguredMCPServerNames = observedCLIConfiguredMCPServerNames
                return
            }

            if method == "x.ai/models/update" || method == "_x.ai/models/update" {
                guard let event = ACPModelCatalogEvent.parse(
                    params,
                    processGeneration: processGeneration
                ) else { return }
                applyModelCatalog(event)
                acpEventContinuation?.yield(.modelCatalogChanged(event))
                return
            }

            if method == "session/update"
                || method == "x.ai/session/update"
                || method == "_x.ai/session/update"
                || method == "x.ai/session_notification"
                || method == "_x.ai/session_notification" {
                let update = params["update"] as? [String: Any]
                let updateSessionID = Self.eventSessionID(from: params, update: update)
                let belongsToCurrentSession = Self.eventBelongsToSession(
                    updateSessionID,
                    currentSessionID: sessionId
                )
                let isReplay = GrokSessionReplay.isReplaySessionUpdate(params: params, update: update)
                if isReplay, let update {
                    recordSessionReplay(
                        update: update,
                        eventSessionID: updateSessionID,
                        processGeneration: processGeneration
                    )
                }
                if let promptIndex = Self.backendPromptIndex(
                    eventSessionID: updateSessionID,
                    currentSessionID: sessionId,
                    isReplay: isReplay,
                    update: update
                ) {
                    activeBackendPromptIndex = promptIndex
                }
                if belongsToCurrentSession, let total = totalTokens(from: params) {
                    acpEventContinuation?.yield(.contextUsage(totalTokens: total))
                }
                if update?["sessionUpdate"] as? String == "turn_completed" {
                    guard belongsToCurrentSession,
                          let receipt = turnCompletionReceipt(
                              from: update ?? [:],
                              sessionID: updateSessionID,
                              backendEventID: Self.backendEventID(from: params),
                              processGeneration: processGeneration
                          ) else { return }
                    // Replay completion belongs to the historical load stream, not the
                    // live turn currently owned by ChatStore.
                    guard !isReplay else {
                        return
                    }
                    recordTurnCompletionObservedAtProcessBoundary()
                    acpEventContinuation?.yield(.turnCompleted(receipt))
                    activeBackendPromptIndex = nil
                    return
                }
                if !isReplay,
                   let u = update {
                    routeUpdate(
                        u,
                        sessionID: updateSessionID,
                        backendEventID: Self.backendEventID(from: params),
                        processGeneration: processGeneration
                    )
                }
                return
            }

            if method == "session/request_permission" {
                if let req = parsePermissionRequest(id: rid, params: params) {
                    guard Self.eventBelongsToSession(req.sessionId, currentSessionID: sessionId) else {
                        rejectMismatchedInteractionRequest(rid: rid, sessionID: req.sessionId)
                        return
                    }
                    acpEventContinuation?.yield(.permissionRequest(req))
                }
                // UI will respond via respondToPermission
                return
            }

            if method == "x.ai/exit_plan_mode" || method == "session/exit_plan_mode"
                || method == "_x.ai/exit_plan_mode" {
                let planText = exitPlanText(from: params)
                let requestSessionID = params["sessionId"] as? String ?? sessionId ?? ""
                guard Self.eventBelongsToSession(requestSessionID, currentSessionID: sessionId) else {
                    rejectMismatchedInteractionRequest(rid: rid, sessionID: requestSessionID)
                    return
                }
                let req = ExitPlanRequest(
                    id: requestIdHash(rid),
                    sessionId: requestSessionID,
                    planText: planText,
                    isResolved: false,
                    verdict: nil
                )
                acpEventContinuation?.yield(.exitPlanRequest(req))
                return
            }

            if method == "x.ai/ask_user_question" || method == "_x.ai/ask_user_question" {
                let requestSessionID = params["sessionId"] as? String ?? sessionId ?? ""
                guard Self.eventBelongsToSession(requestSessionID, currentSessionID: sessionId) else {
                    rejectMismatchedInteractionRequest(rid: rid, sessionID: requestSessionID)
                    return
                }
                let questions = (params["questions"] as? [[String: Any]] ?? [])
                    .compactMap { QuestionItem.parse(from: $0) }
                let req = QuestionRequest(
                    id: requestIdHash(rid),
                    sessionId: requestSessionID,
                    questions: questions,
                    isResolved: false,
                    answerSummary: nil
                )
                acpEventContinuation?.yield(.questionRequest(req))
                return
            }

            rejectUnsupportedClientMethod(rid: rid, method: method)
            return
        }

        if let id = jsonRequestId(from: j) {
            ioLock.lock()
            let pending = pendingRequests.removeValue(forKey: id)
            if activePromptRequestID == id { activePromptRequestID = nil }
            ioLock.unlock()
            if let pending {
                pending.timeoutTask?.cancel()
                if let err = j["error"] {
                    var info: [String: Any] = [:]
                    if let dict = err as? [String: Any] {
                        // Prefer the agent's human-readable message over dumping the raw error object.
                        info[NSLocalizedDescriptionKey] = (dict["message"] as? String) ?? "\(err)"
                        if let code = dict["code"] as? NSNumber {
                            info["jsonRPCCode"] = code.intValue
                        }
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

    private func turnCompletionReceipt(
        from update: [String: Any],
        sessionID: String?,
        backendEventID: String?,
        processGeneration: UInt64
    ) -> TurnCompletionReceipt? {
        // Completion is stronger than ordinary best-effort session updates: an
        // absent or mismatched backend ID cannot settle the visible active turn.
        guard let sessionID,
              sessionID == self.sessionId,
              activeProcessGeneration == processGeneration else { return nil }
        let usage = update["usage"] as? [String: Any] ?? [:]
        let stopReason = update["stop_reason"] as? String ?? update["stopReason"] as? String
        let rawError: String? = if stopReason?.lowercased() == "error" {
            update["agent_result"] as? String
                ?? update["agentResult"] as? String
                ?? update["error"] as? String
        } else {
            update["error"] as? String
        }
        return TurnCompletionReceipt(
            identity: ACPEventIdentity(
                localTabID: launchReceipt?.localTabID,
                backendSessionID: sessionID,
                processGeneration: processGeneration,
                backendEventID: backendEventID
            ),
            promptID: update["prompt_id"] as? String ?? update["promptId"] as? String,
            stopReason: stopReason,
            redactedError: Self.redactedLifecycleText(rawError),
            totalTokens: Self.integer(usage["totalTokens"]),
            modelCalls: Self.integer(usage["modelCalls"]),
            turnCount: Self.integer(usage["numTurns"]),
            backendPromptIndex: activeBackendPromptIndex,
            inputTokens: Self.integer(usage["inputTokens"]),
            outputTokens: Self.integer(usage["outputTokens"]),
            cachedReadTokens: Self.integer(usage["cachedReadTokens"]),
            cacheCreationTokens: Self.integer(usage["cacheCreationTokens"]),
            reasoningTokens: Self.integer(usage["reasoningTokens"]),
            apiDurationMilliseconds: Self.integer(usage["apiDurationMs"]),
            costUsdTicks: Self.integer(usage["costUsdTicks"]),
            costIsPartial: usage["costIsPartial"] as? Bool,
            modelUsage: Self.modelUsageReceipts(from: usage["modelUsage"])
        )
    }

    static func modelUsageReceipts(from value: Any?) -> [ModelUsageReceipt] {
        guard let raw = value as? [String: Any] else { return [] }
        return raw.compactMap { modelID, value -> ModelUsageReceipt? in
            guard let usage = value as? [String: Any] else { return nil }
            let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            return ModelUsageReceipt(
                modelID: normalized,
                inputTokens: integer(usage["inputTokens"]),
                outputTokens: integer(usage["outputTokens"]),
                totalTokens: integer(usage["totalTokens"]),
                cachedReadTokens: integer(usage["cachedReadTokens"]),
                cacheCreationTokens: integer(usage["cacheCreationTokens"]),
                reasoningTokens: integer(usage["reasoningTokens"]),
                modelCalls: integer(usage["modelCalls"]),
                apiDurationMilliseconds: integer(usage["apiDurationMs"]),
                costUsdTicks: integer(usage["costUsdTicks"])
            )
        }.sorted { $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending }
    }

    static func eventSessionID(from params: [String: Any], update: [String: Any]?) -> String? {
        params["sessionId"] as? String
            ?? params["session_id"] as? String
            ?? update?["sessionId"] as? String
            ?? update?["session_id"] as? String
    }

    static func eventBelongsToSession(
        _ eventSessionID: String?,
        currentSessionID: String?
    ) -> Bool {
        guard let eventSessionID, let currentSessionID else { return true }
        return eventSessionID == currentSessionID
    }

    static func mcpServerNames(from params: [String: Any]) -> [String] {
        let servers = params["mcpServers"] as? [[String: Any]]
            ?? params["mcp_servers"] as? [[String: Any]]
            ?? params["servers"] as? [[String: Any]]
            ?? []
        return Array(Set(servers.compactMap {
            ($0["name"] as? String ?? $0["serverName"] as? String ?? $0["server_name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }

    private func routeUpdate(
        _ u: [String: Any],
        sessionID: String?,
        backendEventID: String?,
        processGeneration: UInt64
    ) {
        guard activeProcessGeneration == processGeneration else { return }
        guard let k = u["sessionUpdate"] as? String else { return }
        let belongsToCurrentSession = Self.eventBelongsToSession(
            sessionID,
            currentSessionID: self.sessionId
        )
        switch k {
        case "agent_message_chunk":
            guard belongsToCurrentSession else { return }
            let t = (u["content"] as? [String: Any])?["text"] as? String ?? ""
            acpEventContinuation?.yield(.messageChunk(text: t))
        case "agent_thought_chunk":
            guard belongsToCurrentSession else { return }
            let t = (u["content"] as? [String: Any])?["text"] as? String ?? ""
            acpEventContinuation?.yield(.thoughtChunk(text: t))
        case "tool_call":
            if belongsToCurrentSession {
                if let tc = parseToolCall(from: u) {
                    acpEventContinuation?.yield(.toolCall(tc))
                } else {
                    acpEventContinuation?.yield(.toolCall(ToolCall(id: UUID().uuidString, kind: "unknown", title: "Tool call", rawInput: nil)))
                }
                if Self.isPlanToolUpdate(u) {
                    acpEventContinuation?.yield(.plan(payload: u))
                }
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
            if belongsToCurrentSession, let tc = parseToolCall(from: u) {
                acpEventContinuation?.yield(.toolCallUpdate(tc))
            }
            if belongsToCurrentSession, Self.isPlanToolUpdate(u) {
                acpEventContinuation?.yield(.plan(payload: u))
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
        case "subagent_spawned":
            guard belongsToCurrentSession,
                  let event = parseSubagentSpawned(
                      from: u,
                      sessionID: sessionID,
                      backendEventID: backendEventID,
                      processGeneration: processGeneration
                  ) else { return }
            acpEventContinuation?.yield(.subagentSpawned(event))
        case "subagent_finished":
            guard belongsToCurrentSession,
                  let event = parseSubagentFinished(
                      from: u,
                      sessionID: sessionID,
                      backendEventID: backendEventID,
                      processGeneration: processGeneration
                  ) else { return }
            acpEventContinuation?.yield(.subagentFinished(event))
        case "plan":
            guard belongsToCurrentSession else { return }
            acpEventContinuation?.yield(.plan(payload: u))
        case "available_commands_update":
            guard belongsToCurrentSession else { return }
            let commands = (u["availableCommands"] as? [[String: Any]] ?? [])
                .compactMap { SlashCommand.parse(from: $0) }
            availableSlashCommands = commands
            acpEventContinuation?.yield(.availableCommands(commands))
        case "current_mode_update":
            guard belongsToCurrentSession else { return }
            if let m = u["currentModeId"] as? String {
                currentMode = AgentMode(rawValue: m)
                acpEventContinuation?.yield(.modeChanged(mode: currentMode))
            }
        default:
            if belongsToCurrentSession, WorkflowToolParsing.isWorkflowSessionUpdate(k) {
                acpEventContinuation?.yield(.workflowActivity(payload: u))
            }
        }
    }

    nonisolated static func isPlanToolUpdate(_ update: [String: Any]) -> Bool {
        let metadataName = ((update["_meta"] as? [String: Any])?["x.ai/tool"] as? [String: Any])?["name"] as? String
        let variant = (update["rawInput"] as? [String: Any])?["variant"] as? String
        return metadataName == "todo_write" || variant?.lowercased() == "todowrite"
    }

    private static func backendEventID(from params: [String: Any]) -> String? {
        (params["_meta"] as? [String: Any])?["eventId"] as? String
    }

    private func lifecycleIdentity(
        update: [String: Any],
        sessionID: String?,
        backendEventID: String?,
        processGeneration: UInt64
    ) -> ACPEventIdentity? {
        let parentBackendID = update["parent_session_id"] as? String ?? sessionID
        guard let parentBackendID,
              parentBackendID == self.sessionId,
              activeProcessGeneration == processGeneration else { return nil }
        return ACPEventIdentity(
            localTabID: launchReceipt?.localTabID,
            backendSessionID: parentBackendID,
            processGeneration: processGeneration,
            backendEventID: backendEventID
        )
    }

    private func parseSubagentSpawned(
        from update: [String: Any],
        sessionID: String?,
        backendEventID: String?,
        processGeneration: UInt64
    ) -> SubagentSpawnedEvent? {
        guard let identity = lifecycleIdentity(
            update: update,
            sessionID: sessionID,
            backendEventID: backendEventID,
            processGeneration: processGeneration
        ), let childID = Self.childID(from: update) else { return nil }
        return SubagentSpawnedEvent(
            identity: identity,
            childID: childID,
            parentPromptID: update["parent_prompt_id"] as? String,
            subagentType: update["subagent_type"] as? String,
            modelID: update["model"] as? String,
            description: Self.redactedLifecycleText(update["description"] as? String)
        )
    }

    private func parseSubagentFinished(
        from update: [String: Any],
        sessionID: String?,
        backendEventID: String?,
        processGeneration: UInt64
    ) -> SubagentFinishedEvent? {
        guard let identity = lifecycleIdentity(
            update: update,
            sessionID: sessionID,
            backendEventID: backendEventID,
            processGeneration: processGeneration
        ), let childID = Self.childID(from: update),
           let status = update["status"] as? String else { return nil }
        return SubagentFinishedEvent(
            identity: identity,
            childID: childID,
            status: status,
            durationMilliseconds: Self.integer(update["duration_ms"]),
            turns: Self.integer(update["turns"]),
            toolCallCount: Self.integer(update["tool_calls"]),
            tokenCount: Self.integer(update["tokens_used"]),
            redactedError: Self.lifecycleError(from: update),
            // The async official update-page lookup runs at the ordered parent
            // completion barrier. Never block the ACP reader on disk or a
            // nested JSON-RPC request while routing this lifecycle event.
            childToolReceipts: nil
        )
    }

    /// Fetches terminal child tool receipts through the official 1.0.5
    /// `x.ai/session/updates` extension on this exact per-tab ACP connection.
    /// The walk is capped at four 256-row pages. Known-old/method-not-found or
    /// malformed transport returns unavailable instead of scraping the CLI's
    /// private session directory.
    func fetchChildToolReceipts(
        childID: String,
        expectedToolCallCount: Int? = nil
    ) async -> [ChildToolReceipt]? {
        guard childID.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let requestedGeneration = activeProcessGeneration
        let pageLimit = 256
        let maximumPages = 4
        var pages: [[ACPStoredUpdateEnvelope]] = []
        do {
            for pageIndex in 1...maximumPages {
                let page = try await fetchACPSessionUpdates(
                    sessionID: childID,
                    offset: -(pageIndex * pageLimit),
                    limit: pageLimit
                )
                pages.append(page.updates)
                let receipts = childToolReceipts(
                    from: pages.reversed().flatMap { $0 },
                    childID: childID
                )
                if let expectedToolCallCount,
                   receipts.count >= expectedToolCallCount {
                    return receipts
                }
                if page.totalCount <= pageIndex * pageLimit || page.updates.isEmpty {
                    return receipts
                }
            }
            return childToolReceipts(
                from: pages.reversed().flatMap { $0 },
                childID: childID
            )
        } catch {
            // Never attach evidence after this tab has crossed into a different
            // ACP process generation. Unsupported official history is honestly
            // unavailable; GrokBuild does not reach around ACP into CLI storage.
            guard activeProcessGeneration == requestedGeneration else { return nil }
            return nil
        }
    }

    private func childToolReceipts(
        from envelopes: [ACPStoredUpdateEnvelope],
        childID: String
    ) -> [ChildToolReceipt] {
        var order: [String] = []
        var receipts: [String: ChildToolReceipt] = [:]
        for envelope in envelopes {
            guard envelope.method == "session/update" || envelope.method == "_x.ai/session/update",
                  envelope.sessionID == childID,
                  let update = envelope.foundationUpdate,
                  update["sessionUpdate"] as? String == "tool_call_update",
                  let tool = parseToolCall(from: update),
                  let status = tool.terminalStatus else { continue }
            if receipts[tool.id] == nil { order.append(tool.id) }
            receipts[tool.id] = ChildToolReceipt(
                id: tool.id,
                title: tool.title,
                status: status,
                mcpReceiptRole: tool.mcpReceiptRole,
                qualifiedToolName: tool.qualifiedToolName,
                discoveredQualifiedToolNames: tool.discoveredQualifiedToolNames
            )
        }
        return order.compactMap { receipts[$0] }
    }

    private static func childID(from update: [String: Any]) -> String? {
        update["child_session_id"] as? String ?? update["subagent_id"] as? String
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }

    static func backendPromptIndex(
        eventSessionID: String?,
        currentSessionID: String?,
        isReplay: Bool,
        update: [String: Any]?
    ) -> Int? {
        guard !isReplay,
              let eventSessionID,
              let currentSessionID,
              eventSessionID == currentSessionID,
              update?["sessionUpdate"] as? String == "user_message_chunk",
              let updateMeta = update?["_meta"] as? [String: Any],
              let promptIndex = strictInteger(updateMeta["promptIndex"]),
              promptIndex >= 0,
              promptIndex < Int.max else { return nil }
        return promptIndex
    }

    private static func strictInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return Int(number.stringValue)
    }

    private static func lifecycleError(from update: [String: Any]) -> String? {
        if let error = update["error"] as? String { return redactedLifecycleText(error) }
        if let error = update["error"] as? [String: Any] {
            return redactedLifecycleText(error["message"] as? String ?? error["code"] as? String)
        }
        return redactedLifecycleText(update["message"] as? String)
    }

    static func redactedLifecycleText(_ text: String?) -> String? {
        guard let text else { return nil }
        let redacted = GrokMCPRedactor.redact(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !redacted.isEmpty else { return nil }
        return String(redacted.prefix(280))
    }

    /// Test seam for deterministic fixture routing. Production pipe readers supply
    /// the generation captured when their process launched through the same path.
    func routeSessionUpdateForTests(
        _ update: [String: Any],
        sessionID: String,
        backendEventID: String?,
        processGeneration: UInt64
    ) {
        if update["sessionUpdate"] as? String == "turn_completed" {
            guard let receipt = turnCompletionReceipt(
                from: update,
                sessionID: sessionID,
                backendEventID: backendEventID,
                processGeneration: processGeneration
            ) else { return }
            acpEventContinuation?.yield(.turnCompleted(receipt))
            return
        }
        routeUpdate(
            update,
            sessionID: sessionID,
            backendEventID: backendEventID,
            processGeneration: processGeneration
        )
    }

    func routeTurnCompletionReceiptMissingForTests(
        sessionID: String,
        processGeneration: UInt64
    ) {
        guard sessionID == self.sessionId,
              activeProcessGeneration == processGeneration else { return }
        acpEventContinuation?.yield(.turnCompletionReceiptMissing(
            TurnCompletionBridgeFailure(
                identity: ACPEventIdentity(
                    localTabID: launchReceipt?.localTabID,
                    backendSessionID: sessionID,
                    processGeneration: processGeneration,
                    backendEventID: nil
                ),
                reason: "Synthetic missing completion receipt."
            )
        ))
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

    private func rejectMismatchedInteractionRequest(rid: Any?, sessionID: String) {
        respond(
            rid: rid,
            error: NSError(
                domain: "GrokBuild.ACPInteraction",
                code: -32002,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Interaction request for backend session \(sessionID) does not belong to this live process."
                ]
            ),
            code: -32002
        )
    }

    private func rejectUnsupportedClientMethod(rid: Any?, method: String) {
        respond(
            rid: rid,
            error: NSError(
                domain: "GrokBuild.ACPClient",
                code: -32601,
                userInfo: [NSLocalizedDescriptionKey: "Method not found: \(method)"]
            ),
            code: -32601
        )
    }

    private func exitPlanText(from params: [String: Any]) -> String {
        if let plan = params["planContent"] as? String, !plan.isEmpty { return plan }
        if let plan = params["plan"] as? String, !plan.isEmpty { return plan }
        if let input = params["input"] as? [String: Any], let plan = input["plan"] as? String { return plan }
        return ""
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
