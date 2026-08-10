import Foundation

/// Deterministic, provider-free accounting for the prompt/context bytes GrokBuild can
/// actually observe. The Grok CLI owns its base prompt and provider wrappers, so those
/// remain explicitly unmeasured instead of being reverse-engineered or guessed.
struct PromptContextContributor: Equatable, Sendable {
    enum Kind: String, Sendable {
        case systemInstructions
        case projectInstructions
        case projectContext
        case skillCatalog
        case mcpCatalog
        case requestedToolSchemas
        case deferredToolSchemas
        case sessionHistory
        case userContent
        case memory
        case providerWrapper
    }

    let kind: Kind
    let label: String
    let bytes: Int
    let isDeferred: Bool
    let isMeasured: Bool

    init(
        kind: Kind,
        label: String,
        bytes: Int,
        isDeferred: Bool = false,
        isMeasured: Bool = true
    ) {
        self.kind = kind
        self.label = label
        self.bytes = max(0, bytes)
        self.isDeferred = isDeferred
        self.isMeasured = isMeasured
    }
}

struct PromptContextBudgetReport: Equatable, Sendable {
    let contributors: [PromptContextContributor]

    var loadedBytes: Int {
        contributors.filter { !$0.isDeferred && $0.isMeasured }.reduce(0) { $0 + $1.bytes }
    }

    var deferredBytes: Int {
        contributors.filter { $0.isDeferred && $0.isMeasured }.reduce(0) { $0 + $1.bytes }
    }

    var unmeasuredLabels: [String] {
        contributors.filter { !$0.isMeasured }.map(\.label)
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
        providerWrapperBytes: Int? = nil,
        systemInstructionsBytes: Int? = nil,
        projectContext: Data = Data(),
        userContent: Data = Data()
    ) -> PromptContextBudgetReport {
        var contributors = [
            PromptContextContributor(
                kind: .systemInstructions,
                label: systemInstructionsBytes == nil
                    ? "Grok CLI system instructions (not exposed; unmeasured)"
                    : "Grok CLI system instructions",
                bytes: systemInstructionsBytes ?? 0,
                isMeasured: systemInstructionsBytes != nil
            ),
            PromptContextContributor(
                kind: .projectInstructions,
                label: "Project instructions",
                bytes: projectInstructions.count
            ),
            PromptContextContributor(
                kind: .projectContext,
                label: "Selected project context",
                bytes: projectContext.count
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
                label: "Observable transcript history",
                bytes: sessionHistory.count
            ),
            PromptContextContributor(
                kind: .userContent,
                label: "Current user content",
                bytes: userContent.count
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
            bytes: providerWrapperBytes ?? 0,
            isMeasured: providerWrapperBytes != nil
        ))
        return PromptContextBudgetReport(contributors: contributors)
    }

    static func reductionPercent(currentBytes: Int) -> Int {
        guard legacyProjectInstructionBytes > 0 else { return 0 }
        return max(0, (legacyProjectInstructionBytes - currentBytes) * 100 / legacyProjectInstructionBytes)
    }
}
