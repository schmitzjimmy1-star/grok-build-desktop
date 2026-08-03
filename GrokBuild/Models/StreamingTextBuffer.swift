import Foundation

/// Coalesces tiny ACP message chunks and breaks unusually large chunks into a bounded
/// sequence of display-sized batches. Grok can deliver a complete answer as one ACP
/// chunk; applying that directly makes the UI look frozen and then snap.
struct StreamingTextBuffer: Sendable {
    static let minimumBatchCharacters = 48
    static let targetRevealFrames = 14
    static let displayCadenceMilliseconds = 32

    private(set) var pending = ""
    private var preferredBatchCharacters: Int?

    var isEmpty: Bool { pending.isEmpty }

    mutating func append(_ text: String) {
        pending += text
        let proportional = Int(ceil(Double(pending.count) / Double(Self.targetRevealFrames)))
        preferredBatchCharacters = max(
            preferredBatchCharacters ?? 0,
            Self.minimumBatchCharacters,
            proportional
        )
    }

    mutating func popNextBatch() -> String {
        guard !pending.isEmpty else { return "" }
        let batchCount = min(
            pending.count,
            preferredBatchCharacters ?? Self.minimumBatchCharacters
        )
        let end = pending.index(pending.startIndex, offsetBy: batchCount)
        let batch = String(pending[..<end])
        pending.removeSubrange(..<end)
        if pending.isEmpty { preferredBatchCharacters = nil }
        return batch
    }

    mutating func drain() -> String {
        defer {
            pending = ""
            preferredBatchCharacters = nil
        }
        return pending
    }

    mutating func clear() {
        pending = ""
        preferredBatchCharacters = nil
    }
}
