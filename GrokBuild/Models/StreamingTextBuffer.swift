import Foundation

/// Coalesces tiny ACP message chunks and breaks unusually large chunks into a handful
/// of display-sized batches. Grok's web-search lane can deliver the final answer as one
/// multi-kilobyte chunk; applying that directly makes the UI look frozen and then snap.
struct StreamingTextBuffer: Sendable {
    static let minimumBatchCharacters = 128
    static let targetDrainFrames = 6

    private(set) var pending = ""

    var isEmpty: Bool { pending.isEmpty }

    mutating func append(_ text: String) {
        pending += text
    }

    mutating func popNextBatch() -> String {
        guard !pending.isEmpty else { return "" }
        let pendingCount = pending.count
        let proportional = Int(ceil(Double(pendingCount) / Double(Self.targetDrainFrames)))
        let batchCount = min(pendingCount, max(Self.minimumBatchCharacters, proportional))
        let end = pending.index(pending.startIndex, offsetBy: batchCount)
        let batch = String(pending[..<end])
        pending.removeSubrange(..<end)
        return batch
    }

    mutating func drain() -> String {
        defer { pending = "" }
        return pending
    }

    mutating func clear() {
        pending = ""
    }
}
