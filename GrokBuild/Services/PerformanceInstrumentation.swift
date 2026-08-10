import Foundation
import os

/// Redacted performance lanes for the coherence repair plan.
///
/// Interval metadata is deliberately limited to non-content state such as pane names,
/// counts, and outcome codes. Callers must never attach prompts, rendered content,
/// credentials, environment values, headers, rules, URLs, or private file paths.
enum GrokBuildPerformanceLane: String, CaseIterable, Sendable {
    case appLaunchToWindow
    case layoutLoad
    case restoreDecision
    case selectedTranscriptLoad
    case continuityVerification
    case processSpawnToACPReady
    case firstSendToFirstChunk
    case finalChunkToSettledRender
    case tabSwitchToInteractive
    case settingsPaneLoad
    case settingsSkillsInspect
    case settingsMarketplaceLoad
    case modelCatalogLoad
    case providerCredentialMetadataLoad
    case richMessageParse
    case mermaidRender
    case transcriptWrite

    var signpostName: StaticString {
        switch self {
        case .appLaunchToWindow: return "appLaunchToWindow"
        case .layoutLoad: return "layoutLoad"
        case .restoreDecision: return "restoreDecision"
        case .selectedTranscriptLoad: return "selectedTranscriptLoad"
        case .continuityVerification: return "continuityVerification"
        case .processSpawnToACPReady: return "processSpawnToACPReady"
        case .firstSendToFirstChunk: return "firstSendToFirstChunk"
        case .finalChunkToSettledRender: return "finalChunkToSettledRender"
        case .tabSwitchToInteractive: return "tabSwitchToInteractive"
        case .settingsPaneLoad: return "settingsPaneLoad"
        case .settingsSkillsInspect: return "settingsSkillsInspect"
        case .settingsMarketplaceLoad: return "settingsMarketplaceLoad"
        case .modelCatalogLoad: return "modelCatalogLoad"
        case .providerCredentialMetadataLoad: return "providerCredentialMetadataLoad"
        case .richMessageParse: return "richMessageParse"
        case .mermaidRender: return "mermaidRender"
        case .transcriptWrite: return "transcriptWrite"
        }
    }
}

enum GrokBuildPerformanceStage: String, CaseIterable, Sendable {
    case appLaunch
    case firstWindow
    case layoutLoaded
    case restoreCompleted
    case transcriptLoaded
    case processSpawned
    case acpReady
    case sessionReady
    case modelConfirmed
    case selectedMCPReady
    case submitIntent
    case dispatch
    case firstChunk
    case settled
}

/// Release acceptance budgets derived from the measured Slice 7 cold/warm ranges
/// and the Slice 6 minimal-terminal baseline. They are test/acceptance thresholds,
/// not a second runtime scheduler: Grok CLI/ACP still owns dispatch and tokens.
enum ThreadNativeReleaseBudgets {
    static let maximumColdFirstWindowMilliseconds = 750.0
    static let maximumColdFirstIntentReadyMilliseconds = 10_000.0
    static let maximumColdDispatchToFirstChunkMilliseconds = 8_000.0
    static let maximumWarmDispatchToFirstChunkMilliseconds = 3_000.0
    static let maximumIdleOwnedProcessCount = 0
    static let maximumMinimalTerminalTurnTokens = 40_000

    static func accepts(
        coldFirstWindowMilliseconds: Double,
        coldFirstIntentReadyMilliseconds: Double,
        coldDispatchToFirstChunkMilliseconds: Double,
        warmDispatchToFirstChunkMilliseconds: Double,
        idleOwnedProcessCount: Int,
        minimalTerminalTurnTokens: Int
    ) -> Bool {
        coldFirstWindowMilliseconds <= maximumColdFirstWindowMilliseconds
            && coldFirstIntentReadyMilliseconds <= maximumColdFirstIntentReadyMilliseconds
            && coldDispatchToFirstChunkMilliseconds <= maximumColdDispatchToFirstChunkMilliseconds
            && warmDispatchToFirstChunkMilliseconds <= maximumWarmDispatchToFirstChunkMilliseconds
            && idleOwnedProcessCount <= maximumIdleOwnedProcessCount
            && minimalTerminalTurnTokens <= maximumMinimalTerminalTurnTokens
    }
}

final class GrokBuildPerformanceInterval: @unchecked Sendable {
    fileprivate let lane: GrokBuildPerformanceLane
    fileprivate let state: OSSignpostIntervalState
    private let lock = NSLock()
    private var didEnd = false

    fileprivate init(lane: GrokBuildPerformanceLane, state: OSSignpostIntervalState) {
        self.lane = lane
        self.state = state
    }

    /// Ending twice is harmless. This matters when a render is superseded or a turn fails
    /// before its first text chunk.
    func end() {
        lock.lock()
        defer { lock.unlock() }
        guard !didEnd else { return }
        didEnd = true
        GrokBuildPerformance.signposter.endInterval(lane.signpostName, state)
    }
}

enum GrokBuildPerformance {
    fileprivate static let signposter = OSSignposter(
        subsystem: "com.grokbuild.app",
        category: "Performance"
    )

    static func begin(_ lane: GrokBuildPerformanceLane) -> GrokBuildPerformanceInterval {
        GrokBuildPerformanceInterval(
            lane: lane,
            state: signposter.beginInterval(lane.signpostName)
        )
    }

    /// Optional, repository-driven JSONL receipt. It is enabled only when the
    /// performance command supplies a destination path. Rows contain a stage,
    /// monotonic offset, wall time, and PID—never prompt text, model credentials,
    /// environment contents, URLs, or file arguments.
    static func mark(_ stage: GrokBuildPerformanceStage) {
        PerformanceStageLedger.shared.mark(stage)
    }

    static func markOnce(_ stage: GrokBuildPerformanceStage) {
        PerformanceStageLedger.shared.markOnce(stage)
    }

    static func measure<Value>(
        _ lane: GrokBuildPerformanceLane,
        operation: () throws -> Value
    ) rethrows -> Value {
        let interval = begin(lane)
        defer { interval.end() }
        return try operation()
    }

    static func measure<Value: Sendable>(
        _ lane: GrokBuildPerformanceLane,
        operation: () async throws -> Value
    ) async rethrows -> Value {
        let interval = begin(lane)
        defer { interval.end() }
        return try await operation()
    }
}

private final class PerformanceStageLedger: @unchecked Sendable {
    static let shared = PerformanceStageLedger()

    private let lock = NSLock()
    private let started = ContinuousClock.now
    private let destination: URL?
    private var uniqueStages: Set<GrokBuildPerformanceStage> = []

    private init() {
        guard let path = ProcessInfo.processInfo.environment["GROKBUILD_PERFORMANCE_LEDGER"],
              path.hasPrefix("/") else {
            destination = nil
            return
        }
        destination = URL(fileURLWithPath: path)
    }

    func mark(_ stage: GrokBuildPerformanceStage) {
        guard let destination else { return }
        let elapsed = started.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        let row: [String: Any] = [
            "stage": stage.rawValue,
            "elapsed_ms": milliseconds,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "pid": ProcessInfo.processInfo.processIdentifier,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: destination.path) {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: destination) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            return
        }
    }

    func markOnce(_ stage: GrokBuildPerformanceStage) {
        lock.lock()
        let inserted = uniqueStages.insert(stage).inserted
        lock.unlock()
        guard inserted else { return }
        mark(stage)
    }
}
