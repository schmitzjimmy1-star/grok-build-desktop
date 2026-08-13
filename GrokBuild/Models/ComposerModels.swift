import Foundation

struct SlashCommand: Identifiable, Hashable, Codable, Sendable {
    var id: String { name }
    let name: String
    let description: String
    let inputHint: String?
    let isSkill: Bool

    init(name: String, description: String = "", inputHint: String? = nil, isSkill: Bool = false) {
        self.name = name
        self.description = description
        self.inputHint = inputHint
        self.isSkill = isSkill
    }

    static func parse(from dict: [String: Any]) -> SlashCommand? {
        guard let name = dict["name"] as? String else { return nil }
        let description = dict["description"] as? String ?? ""
        let hint = (dict["input"] as? [String: Any])?["hint"] as? String
        let path = (dict["_meta"] as? [String: Any])?["path"] as? String ?? ""
        let isSkill = path.hasSuffix("SKILL.md") || path.contains("/skills/")
        return SlashCommand(name: name, description: description, inputHint: hint, isSkill: isSkill)
    }
}

/// Last known command inventory shared by lazy fresh tabs. A new tab deliberately does
/// not spawn grok until its first prompt, but its hammer menu should not become a dead
/// control while command discovery is unavailable.
enum GrokCommandCatalog {
    private static let cacheKey = "grokbuild.slashCommands.v1"

    static func cached(defaults: UserDefaults = .standard) -> [SlashCommand] {
        guard let data = defaults.data(forKey: cacheKey),
              let commands = try? JSONDecoder().decode([SlashCommand].self, from: data) else {
            return []
        }
        return commands
    }

    static func record(_ commands: [SlashCommand], defaults: UserDefaults = .standard) {
        guard !commands.isEmpty,
              let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}

enum SlashMenuEntry: Identifiable, Hashable {
    case command(SlashCommand)
    case showMoreSkills(count: Int)
    case showMoreCommands(count: Int)

    var id: String {
        switch self {
        case .command(let command): return "cmd:\(command.id)"
        case .showMoreSkills: return "more:skills"
        case .showMoreCommands: return "more:commands"
        }
    }
}

/// Curated skill slash commands shown as composer chips when advertised by the CLI.
enum SkillSlashCommands {
    static let curatedOrder = [
        "design",
        "implement",
        "execute-plan",
        "review",
        "pr-babysit",
        "code-review",
    ]

    /// Returns advertised commands in curated order; omits names the CLI did not expose.
    static func filter(_ available: [SlashCommand]) -> [SlashCommand] {
        var byName: [String: SlashCommand] = [:]
        for command in available where byName[command.name] == nil {
            byName[command.name] = command
        }
        return curatedOrder.compactMap { byName[$0] }
    }

    static func slashText(for command: SlashCommand) -> String {
        "/\(command.name)"
    }
}

/// Curated research slash commands shown as composer chips when advertised by the CLI.
enum ResearchSlashCommands {
    static let curatedOrder = [
        "deep-research",
        "create-workflow",
    ]

    static func filter(_ available: [SlashCommand]) -> [SlashCommand] {
        var byName: [String: SlashCommand] = [:]
        for command in available where byName[command.name] == nil {
            byName[command.name] = command
        }
        return curatedOrder.compactMap { byName[$0] }
    }

    static func slashText(for command: SlashCommand) -> String {
        "/\(command.name)"
    }
}

/// Curated imagine slash commands shown as composer chips when advertised by the CLI.
enum ImagineSlashCommands {
    static let curatedOrder = [
        "imagine",
        "imagine-video",
    ]

    static func filter(_ available: [SlashCommand]) -> [SlashCommand] {
        var byName: [String: SlashCommand] = [:]
        for command in available where byName[command.name] == nil {
            byName[command.name] = command
        }
        return curatedOrder.compactMap { byName[$0] }
    }

    static func slashText(for command: SlashCommand) -> String {
        "/\(command.name)"
    }
}

struct SessionGoalState: Equatable, Sendable {
    var objective: String
    var budget: Int?
    var isPaused: Bool = false

    var statusLabel: String {
        isPaused ? "Paused" : "Active"
    }

    var budgetLabel: String? {
        guard let budget else { return nil }
        return "Budget: \(budget)"
    }
}

enum GoalCommand: Equatable, Sendable {
    case set(objective: String, budget: Int?)
    case status
    case pause
    case resume
    case clear

    static func parse(from text: String) -> GoalCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/goal") else { return nil }
        let afterName = trimmed.dropFirst("/goal".count)
        if !afterName.isEmpty, let first = afterName.first, !first.isWhitespace {
            return nil
        }
        var rest = String(afterName.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !rest.isEmpty else { return nil }
        switch rest.lowercased() {
        case "status": return .status
        case "pause": return .pause
        case "resume": return .resume
        case "clear": return .clear
        default:
            var budget: Int?
            if let range = rest.range(of: #"--budget\s+(\d+)"#, options: .regularExpression) {
                let match = String(rest[range])
                if let value = match.split(separator: " ").last, let parsed = Int(value) {
                    budget = parsed
                }
                rest.removeSubrange(range)
                rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !rest.isEmpty else { return nil }
            return .set(objective: rest, budget: budget)
        }
    }

    var sendText: String {
        switch self {
        case .set(let objective, let budget):
            if let budget {
                return "/goal \(objective) --budget \(budget)"
            }
            return "/goal \(objective)"
        case .status: return "/goal status"
        case .pause: return "/goal pause"
        case .resume: return "/goal resume"
        case .clear: return "/goal clear"
        }
    }
}

enum SessionGoalStateMutation {
    static func apply(_ command: GoalCommand, to state: inout SessionGoalState?) {
        switch command {
        case .set(let objective, let budget):
            state = SessionGoalState(objective: objective, budget: budget, isPaused: false)
        case .pause:
            state?.isPaused = true
        case .resume:
            state?.isPaused = false
        case .clear:
            state = nil
        case .status:
            break
        }
    }
}

enum SlashAutocompleteGroups {
    static let previewLimit = 3
    private static let skillPriority = ["code-review", "review", "check-work"]

    static func split(_ commands: [SlashCommand]) -> (skills: [SlashCommand], commands: [SlashCommand]) {
        var skills: [SlashCommand] = []
        var cmds: [SlashCommand] = []
        for command in commands {
            if command.isSkill {
                skills.append(command)
            } else {
                cmds.append(command)
            }
        }
        return (sortSkills(skills), cmds)
    }

    private static func sortSkills(_ skills: [SlashCommand]) -> [SlashCommand] {
        skills.sorted { lhs, rhs in
            let left = skillPriority.firstIndex(of: lhs.name) ?? Int.max
            let right = skillPriority.firstIndex(of: rhs.name) ?? Int.max
            if left != right { return left < right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func visible(_ items: [SlashCommand], expanded: Bool, filtering: Bool = false) -> (visible: [SlashCommand], hiddenCount: Int) {
        guard !expanded, !filtering, items.count > previewLimit else {
            return (items, 0)
        }
        return (Array(items.prefix(previewLimit)), items.count - previewLimit)
    }

    static func navigableEntries(
        skills: [SlashCommand],
        commands: [SlashCommand],
        skillsExpanded: Bool,
        commandsExpanded: Bool,
        filtering: Bool = false
    ) -> [SlashMenuEntry] {
        var entries: [SlashMenuEntry] = []
        let skillSlice = visible(skills, expanded: skillsExpanded, filtering: filtering)
        entries += skillSlice.visible.map { .command($0) }
        if skillSlice.hiddenCount > 0 {
            entries.append(.showMoreSkills(count: skillSlice.hiddenCount))
        }

        let commandSlice = visible(commands, expanded: commandsExpanded, filtering: filtering)
        entries += commandSlice.visible.map { .command($0) }
        if commandSlice.hiddenCount > 0 {
            entries.append(.showMoreCommands(count: commandSlice.hiddenCount))
        }
        return entries
    }
}

/// A plain-language starting point shown before a session's first request. Selecting one
/// seeds an editable composer draft. It never sends a prompt by itself. On a fresh empty
/// tab, filling the draft warm-starts `grok agent stdio` in the background; Send is still
/// what talks to grok. Restored saved tasks do not warm-start from these starters.
struct WorkbenchIntent: Identifiable, Hashable, Sendable {
    var id: String { title }
    let icon: String
    let title: String
    let detail: String
    let prompt: String

    static let defaults: [WorkbenchIntent] = [
        WorkbenchIntent(
            icon: "questionmark.bubble",
            title: "Ask",
            detail: "Understand the project or get clear guidance.",
            prompt: "Help me understand this project. Start with what it does, how it is organized, and the best place to begin."
        ),
        WorkbenchIntent(
            icon: "hammer",
            title: "Build",
            detail: "Create, change, or fix something with a safe plan.",
            prompt: "Help me make a change in this project. Ask what outcome I want, then propose a safe plan before editing anything."
        ),
        WorkbenchIntent(
            icon: "checkmark.magnifyingglass",
            title: "Review",
            detail: "Check existing work and explain the best next step.",
            prompt: "Review the current project work without changing anything. Explain what looks good, what needs attention, and the best next step."
        ),
    ]
}

struct FileAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let path: String
    let relativePath: String
    var isHidden: Bool

    init(path: String, workspaceRoot: URL?, isHidden: Bool = false) {
        self.id = UUID()
        self.path = path
        self.isHidden = isHidden
        if let root = workspaceRoot {
            let rootPath = root.standardizedFileURL.path
            if path.hasPrefix(rootPath + "/") {
                relativePath = String(path.dropFirst(rootPath.count + 1))
            } else {
                relativePath = URL(fileURLWithPath: path).lastPathComponent
            }
        } else {
            relativePath = URL(fileURLWithPath: path).lastPathComponent
        }
    }

}

/// Secret-free connection metadata shown in the per-prompt MCP picker.
/// Selecting one requests its use for the next prompt; it does not claim that
/// a tool ran. Actual use is reported only from ACP tool-call receipts.
struct PromptMCPOption: Identifiable, Hashable, Codable, Sendable {
    let name: String
    let detail: String
    /// True only when the current Grok process owns a bounded startup receipt
    /// for this exact configured server. CLI inventory alone leaves this false.
    let isReady: Bool

    var id: String { name }
}

/// The Grok CLI exposes catalog lookup (`search_tool`) and MCP invocation
/// (`use_tool`) as different ACP tools. Keep that distinction on every receipt:
/// discovering a schema is not exercising the discovered capability.
enum MCPToolReceiptRole: String, Codable, Sendable, Hashable {
    case discovery
    case invocation
}

enum MCPQualifiedToolIdentity {
    private static let pattern = #"[A-Za-z0-9._-]+__[A-Za-z0-9._-]+"#

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^[A-Za-z0-9._-]+__[A-Za-z0-9._-]+$"#,
                            options: .regularExpression) != nil else {
            return nil
        }
        return String(trimmed.prefix(240))
    }

    static func names(in text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<String>()
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range)
            .compactMap { Range($0.range, in: text) }
            // A qualified name at the end of a sentence must not absorb prose
            // punctuation into the requested identity. Authoritative receipt
            // parsing remains strict and unchanged.
            .compactMap {
                normalized(String(text[$0]).trimmingCharacters(
                    in: CharacterSet(charactersIn: ".,;:!?")
                ))
            }
            .filter { seen.insert($0).inserted }
    }

    static func serverName(from qualifiedToolName: String?) -> String? {
        guard let qualified = normalized(qualifiedToolName),
              let separator = qualified.range(of: "__") else { return nil }
        return String(qualified[..<separator.lowerBound])
    }
}

enum PromptMCPInventoryCatalog {
    private static let cacheKey = "grokbuild.promptMCPInventory.v1"

    static func cached(defaults: UserDefaults = .standard) -> [PromptMCPOption] {
        guard let data = defaults.data(forKey: cacheKey),
              let options = try? JSONDecoder().decode([PromptMCPOption].self, from: data) else {
            return []
        }
        // A persisted inventory outlives every Grok process generation. Preserve
        // only configuration metadata; process readiness must be reacquired live.
        return options.map {
            PromptMCPOption(name: $0.name, detail: $0.detail, isReady: false)
        }
    }

    static func record(_ options: [PromptMCPOption], defaults: UserDefaults = .standard) {
        let configurationOnly = options.map {
            PromptMCPOption(name: $0.name, detail: $0.detail, isReady: false)
        }
        guard let data = try? JSONEncoder().encode(configurationOnly) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}

enum PromptMCPAttachmentPromptBuilder {
    static func build(from names: some Sequence<String>) -> String? {
        let safeNames = Array(Set(names.compactMap { normalizedName($0) })).sorted()
        guard !safeNames.isEmpty else { return nil }
        let list = safeNames.map { "- \($0)" }.joined(separator: "\n")
        return """
        Attached MCP connections requested for this turn:
        \(list)

        Use these MCP connections when they materially improve the answer. If no attached MCP tool is actually called, do not claim that an MCP was used.
        """
    }

    private static func normalizedName(_ value: String) -> String? {
        let singleLine = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return nil }
        return String(singleLine.prefix(120))
    }
}

enum MCPToolReceiptIdentity {
    static func serverName(
        explicitName: String?,
        qualifiedToolName: String?,
        knownServerNames: some Sequence<String>
    ) -> String? {
        if let explicitName {
            let value = normalized(explicitName)
            if !value.isEmpty { return value }
        }
        guard let qualifiedToolName else { return nil }
        let knownMatch = Set(knownServerNames.map(normalized).filter { !$0.isEmpty })
            .filter { qualifiedToolName.hasPrefix("\($0)__") }
            .max { $0.count < $1.count }
        if let knownMatch { return knownMatch }

        // Grok's MCP tool namespace is `<server>__<tool>`. The qualified tool
        // receipt remains authoritative even when discovery and the tool event
        // race, provided the namespace itself is a bounded safe name.
        guard let separator = qualifiedToolName.range(of: "__") else { return nil }
        let namespace = normalized(String(qualifiedToolName[..<separator.lowerBound]))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        guard !namespace.isEmpty,
              namespace.unicodeScalars.allSatisfy(allowed.contains) else {
            return nil
        }
        return namespace
    }

    private static func normalized(_ value: String) -> String {
        TranscriptTextPresentation.singleLine(value, maxLength: 120)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AttachmentPromptBuilder {
    /// Build attachment text for the user prompt. Uses plain paths — not `@` references,
    /// which tell grok to read the whole file (bad for large text and binaries).
    static func build(from attachments: [FileAttachment]) -> String? {
        let paths = attachments.filter { !$0.isHidden }.map(\.relativePath)
        guard !paths.isEmpty else { return nil }

        if paths.count == 1 {
            return "Attached file: \(paths[0])"
        }
        return "Attached files:\n" + paths.map { "- \($0)" }.joined(separator: "\n")
    }
}

struct ExitPlanRequest: Identifiable, Hashable, @unchecked Sendable {
    let id: AnyHashable
    let sessionId: String
    var planText: String
    var isResolved: Bool
    var verdict: PlanVerdict?

    enum PlanVerdict: String, Sendable {
        case approved, rejected, abandoned
    }

    /// Replayed frames for the same ACP request may fill in plan text after the
    /// request first arrives. They update that one card; a distinct request
    /// replaces it because the backend can block on only one plan approval at a
    /// time in a session.
    static func merging(_ incoming: ExitPlanRequest, into current: ExitPlanRequest?) -> ExitPlanRequest {
        guard let current,
              ACPInteractionRequestIdentity.matches(
                lhsID: current.id,
                lhsSessionID: current.sessionId,
                rhsID: incoming.id,
                rhsSessionID: incoming.sessionId
              ),
              incoming.planText.isEmpty else {
            return incoming
        }
        var merged = incoming
        merged.planText = current.planText
        return merged
    }
}

/// The JSON-RPC request id is meaningful only inside its backend session. This
/// policy is deliberately transport-shaped: visible interaction cards may be
/// rendered from these requests, but tool-call ids and transcript content never
/// become response authority.
enum ACPInteractionRequestIdentity {
    static func ownsActiveSession(_ requestSessionID: String, activeSessionID: String?) -> Bool {
        guard !requestSessionID.isEmpty, let activeSessionID else { return false }
        return requestSessionID == activeSessionID
    }

    static func matches(
        lhsID: AnyHashable,
        lhsSessionID: String,
        rhsID: AnyHashable,
        rhsSessionID: String
    ) -> Bool {
        lhsID == rhsID && lhsSessionID == rhsSessionID
    }
}

struct QuestionOption: Identifiable, Hashable, Sendable {
    let label: String
    let description: String?

    var id: String { label }
}

struct QuestionItem: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let options: [QuestionOption]
    let multiSelect: Bool

    static func parse(from dict: [String: Any]) -> QuestionItem? {
        let text = (dict["question"] as? String) ?? (dict["prompt"] as? String) ?? ""
        guard !text.isEmpty else { return nil }
        let options = (dict["options"] as? [[String: Any]] ?? []).compactMap { opt -> QuestionOption? in
            guard let label = opt["label"] as? String else { return nil }
            return QuestionOption(label: label, description: opt["description"] as? String)
        }
        return QuestionItem(
            id: text,
            text: text,
            options: options,
            multiSelect: dict["multiSelect"] as? Bool ?? false
        )
    }
}

struct QuestionRequest: Identifiable, Hashable, @unchecked Sendable {
    let id: AnyHashable
    let sessionId: String
    let questions: [QuestionItem]
    var isResolved: Bool
    var answerSummary: String?

    /// Only an authoritative `x.ai/ask_user_question` request enters this
    /// reducer. Tool activity remains visible as activity, never as a card that
    /// could answer with a tool-call id.
    static func merging(_ incoming: QuestionRequest, into existing: [QuestionRequest]) -> [QuestionRequest] {
        var merged = existing
        if let index = merged.firstIndex(where: {
            ACPInteractionRequestIdentity.matches(
                lhsID: $0.id,
                lhsSessionID: $0.sessionId,
                rhsID: incoming.id,
                rhsSessionID: incoming.sessionId
            )
        }) {
            merged[index] = incoming
            return merged
        }
        merged.append(incoming)
        return merged
    }
}

enum SessionNameStore {
    private static let key = "grokbuild.sessionNames.v1"

    /// In-memory mirror of the names dictionary. Title refreshes call `name(for:)`
    /// twice per session per pass; bridging the full UserDefaults dictionary out on
    /// every call made a 130-tab title refresh do hundreds of plist copies. The key
    /// is written only through `setName`, which keeps the mirror exact.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedMap: [String: String]?

    private static func loadMap() -> [String: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedMap { return cachedMap }
        let map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        cachedMap = map
        return map
    }

    static func name(for sessionId: String) -> String? {
        loadMap()[sessionId]
    }

    static func setName(_ name: String, for sessionId: String) {
        var map = loadMap()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            map.removeValue(forKey: sessionId)
        } else {
            map[sessionId] = trimmed
        }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        UserDefaults.standard.set(map, forKey: key)
        cachedMap = map
    }

    static func removeName(for sessionId: String) {
        setName("", for: sessionId)
    }

    /// Tests write the names key directly; give them an explicit reset.
    static func invalidateCacheForTesting() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cachedMap = nil
    }
}

enum SessionTitle {
    static let defaultTitle = "New chat"
    static let maxWords = 8

    static func auto(from messages: [Message]) -> String? {
        guard let raw = messages.first(where: { $0.role == .user })?.content else { return nil }
        // One pass collapses runs of any whitespace (spaces, newlines, tabs)
        // without compiling an ICU regex per call.
        let parts = raw.split(whereSeparator: \.isWhitespace)
        guard !parts.isEmpty else { return nil }

        let preview = parts.prefix(maxWords).joined(separator: " ")
        return parts.count > maxWords ? preview + "…" : preview
    }
}

enum ShareURLParser {
    static func firstURL(in text: String) -> String? {
        let pattern = #"https?://[^\s<>")\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }
}
