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
