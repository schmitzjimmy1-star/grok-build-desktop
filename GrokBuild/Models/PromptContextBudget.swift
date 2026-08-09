import Foundation

/// Deterministic, provider-free accounting for the prompt/context bytes GrokBuild can
/// actually observe. The Grok CLI owns its base prompt and provider wrappers, so those
/// remain explicitly unmeasured instead of being reverse-engineered or guessed.
struct PromptContextContributor: Equatable, Sendable {
    enum Kind: String, Sendable {
        case projectInstructions
        case skillCatalog
        case mcpCatalog
        case requestedToolSchemas
        case deferredToolSchemas
        case sessionHistory
        case memory
        case providerWrapper
    }

    let kind: Kind
    let label: String
    let bytes: Int
    let isDeferred: Bool

    init(kind: Kind, label: String, bytes: Int, isDeferred: Bool = false) {
        self.kind = kind
        self.label = label
        self.bytes = max(0, bytes)
        self.isDeferred = isDeferred
    }
}

struct PromptContextBudgetReport: Equatable, Sendable {
    let contributors: [PromptContextContributor]

    var loadedBytes: Int {
        contributors.filter { !$0.isDeferred }.reduce(0) { $0 + $1.bytes }
    }

    var deferredBytes: Int {
        contributors.filter(\.isDeferred).reduce(0) { $0 + $1.bytes }
    }

    /// A comparison aid only. Live provider usage remains authoritative.
    var approximateLoadedTokens: Int { (loadedBytes + 3) / 4 }

    func bytes(for kind: PromptContextContributor.Kind) -> Int {
        contributors.filter { $0.kind == kind }.reduce(0) { $0 + $1.bytes }
    }
}

enum PromptContextBudget {
    static let legacyProjectInstructionBytes = 5_015
    static let minimumProjectInstructionReductionPercent = 25

    static func report(
        projectInstructions: Data,
        skillDescriptions: [String],
        mcpServerDescriptors: [String],
        requestedToolSchemas: [Data] = [],
        deferredToolSchemas: [Data] = [],
        sessionHistory: Data = Data(),
        memory: Data = Data(),
        providerWrapperBytes: Int? = nil
    ) -> PromptContextBudgetReport {
        var contributors = [
            PromptContextContributor(
                kind: .projectInstructions,
                label: "Project instructions",
                bytes: projectInstructions.count
            ),
            PromptContextContributor(
                kind: .skillCatalog,
                label: "Skill names and descriptions",
                bytes: skillDescriptions.reduce(0) { $0 + $1.utf8.count }
            ),
            PromptContextContributor(
                kind: .mcpCatalog,
                label: "Progressive MCP server catalog",
                bytes: mcpServerDescriptors.reduce(0) { $0 + $1.utf8.count }
            ),
            PromptContextContributor(
                kind: .requestedToolSchemas,
                label: "Explicitly requested MCP tool schemas",
                bytes: requestedToolSchemas.reduce(0) { $0 + $1.count }
            ),
            PromptContextContributor(
                kind: .deferredToolSchemas,
                label: "Unrequested MCP tool schemas",
                bytes: deferredToolSchemas.reduce(0) { $0 + $1.count },
                isDeferred: true
            ),
            PromptContextContributor(
                kind: .sessionHistory,
                label: "Session history",
                bytes: sessionHistory.count
            ),
            PromptContextContributor(
                kind: .memory,
                label: "Memory",
                bytes: memory.count
            ),
        ]
        contributors.append(PromptContextContributor(
            kind: .providerWrapper,
            label: providerWrapperBytes == nil
                ? "Provider wrapper (owned by Grok CLI; unmeasured)"
                : "Provider wrapper",
            bytes: providerWrapperBytes ?? 0
        ))
        return PromptContextBudgetReport(contributors: contributors)
    }

    static func reductionPercent(currentBytes: Int) -> Int {
        guard legacyProjectInstructionBytes > 0 else { return 0 }
        return max(0, (legacyProjectInstructionBytes - currentBytes) * 100 / legacyProjectInstructionBytes)
    }
}
