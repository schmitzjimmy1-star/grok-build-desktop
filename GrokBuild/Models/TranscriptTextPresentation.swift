import Foundation

/// Small, loss-aware cleanup for text arriving from ACP.
///
/// ACP message chunks are already ordered and may contain Markdown, so this
/// deliberately does not collapse ordinary whitespace or rewrite punctuation.
/// It only removes transport/control noise and makes line endings and common
/// non-breaking spaces display consistently.
enum TranscriptTextPresentation {
    static func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        let lineNormalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2007}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")

        let cleaned = lineNormalized.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x0000...0x0008, 0x000B...0x000C, 0x000E...0x001F, 0x007F...0x009F:
                return false
            case 0x200B, 0x2060, 0xFEFF, 0x202A...0x202E, 0x2066...0x2069:
                return false
            default:
                return true
            }
        }
        return String(String.UnicodeScalarView(cleaned))
    }

    /// Presentation-only one-line text for compact activity rows and menus.
    static func singleLine(_ text: String, maxLength: Int) -> String {
        let collapsed = normalize(text)
            .split { $0 == " " || $0 == "\t" || $0 == "\n" }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxLength, maxLength > 1 else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength - 1)
        return String(collapsed[..<end]) + "…"
    }
}

/// Keeps a streaming transcript legible without pretending an unfinished Markdown
/// construct is final. The complete message remains the transcript authority; this
/// is only a short-lived display split used while ACP is still producing chunks.
struct StreamingMarkdownPresentation: Equatable {
    enum WithheldConstruct: Equatable {
        case codeFence
        case table

        var displayLabel: String {
            switch self {
            case .codeFence: return "Formatting code…"
            case .table: return "Formatting table…"
            }
        }
    }

    let visibleText: String
    let withheldConstruct: WithheldConstruct?

    static func make(_ text: String) -> Self {
        let normalized = TranscriptTextPresentation.normalize(text)
        guard !normalized.isEmpty else {
            return Self(visibleText: "", withheldConstruct: nil)
        }

        if let start = unfinishedFenceStart(in: normalized) {
            return Self(visibleText: String(normalized[..<start]), withheldConstruct: .codeFence)
        }
        if let start = unfinishedTableStart(in: normalized) {
            return Self(visibleText: String(normalized[..<start]), withheldConstruct: .table)
        }
        return Self(visibleText: normalized, withheldConstruct: nil)
    }

    private static func unfinishedFenceStart(in text: String) -> String.Index? {
        var fenceStart: String.Index?
        var searchStart = text.startIndex
        while searchStart < text.endIndex {
            let lineEnd = text[searchStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[searchStart..<lineEnd].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                fenceStart = fenceStart == nil ? searchStart : nil
            }
            guard lineEnd < text.endIndex else { break }
            searchStart = text.index(after: lineEnd)
        }
        return fenceStart
    }

    private static func unfinishedTableStart(in text: String) -> String.Index? {
        // Tables are stable only after a non-table boundary. While the final row
        // is still arriving, withhold it rather than making columns jump with every
        // token or showing raw pipes as if the result were final.
        let lines = lineRanges(in: text)
        for index in lines.indices {
            guard index + 1 < lines.count,
                  looksLikeTableRow(String(text[lines[index]])),
                  looksLikeTableSeparator(String(text[lines[index + 1]])) else {
                continue
            }
            var cursor = index + 2
            while cursor < lines.count, looksLikeTableRow(String(text[lines[cursor]])) {
                cursor += 1
            }
            if cursor == lines.count, index + 2 < lines.count {
                return lines[index].lowerBound
            }
        }
        return nil
    }

    private static func lineRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
            ranges.append(start..<end)
            guard end < text.endIndex else { break }
            start = text.index(after: end)
        }
        return ranges
    }

    static func looksLikeTableRow(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).contains("|")
    }

    static func looksLikeTableSeparator(_ line: String) -> Bool {
        let cells = line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: ":", with: "")
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }
}

/// Incrementally maintains `StreamingMarkdownPresentation` for one growing streaming
/// message.
///
/// `StreamingMarkdownPresentation.make` re-normalizes and re-scans the full accumulated
/// string; called from the display flush every ~32 ms that made a long streaming answer
/// O(n²) on the main actor. This accumulator does O(appended) work per flush: it
/// normalizes only the new chunk (with a one-character carry so a CRLF split across
/// chunks still collapses), folds completed lines into fence-parity and table state
/// machines, and re-evaluates only the current partial line when producing the
/// presentation. Chunk-by-chunk equivalence with `make` is pinned by property tests;
/// `ChatStore` falls back to one full rebuild on any identity or length desync.
struct StreamingMarkdownAccumulator: Equatable {
    private(set) var normalized: String = ""
    /// Total raw (pre-normalization) UTF-8 bytes consumed, including a carried "\r".
    /// `ChatStore` compares this against the message content to detect desyncs.
    private(set) var consumedRawUTF8Count = 0

    private var normalizedUTF8Count = 0
    /// A chunk ending in "\r" already emitted its "\n"; if the next chunk starts with
    /// "\n" (a CRLF split across chunks), that leading byte must not emit a second one.
    private var suppressLeadingNewlineAfterCR = false
    private var currentLineText = ""
    private var currentLineStartUTF8 = 0

    // Fence parity over completed lines: start offset of the currently open fence line.
    private var openFenceStartUTF8: Int?

    // Table state over completed lines, mirroring the batch scanner's earliest
    // header/separator pair whose row run reaches the end of the text.
    private var tableAnchorUTF8: Int?
    private var tableBodyCount = 0
    private var previousLineWasRowish = false
    private var previousLineStartUTF8 = 0

    // A withheld prefix is stable while its cut offset is; cache the slice.
    private var cachedWithheldPrefixOffset: Int?
    private var cachedWithheldPrefix = ""

    mutating func reset() {
        self = StreamingMarkdownAccumulator()
    }

    mutating func append(_ raw: String) {
        guard !raw.isEmpty else { return }
        consumedRawUTF8Count += raw.utf8.count

        var piece = raw
        if suppressLeadingNewlineAfterCR {
            suppressLeadingNewlineAfterCR = false
            if piece.hasPrefix("\n") { piece.removeFirst() }
        }
        if piece.hasSuffix("\r") { suppressLeadingNewlineAfterCR = true }
        guard !piece.isEmpty else { return }
        let cleaned = TranscriptTextPresentation.normalize(piece)
        guard !cleaned.isEmpty else { return }

        normalized += cleaned
        for scalar in cleaned.unicodeScalars {
            normalizedUTF8Count += Int(UTF8.width(scalar))
            if scalar == "\n" {
                foldCompletedLine()
            } else {
                currentLineText.unicodeScalars.append(scalar)
            }
        }
    }

    /// Mutating only for the withheld-prefix cache; state is otherwise untouched.
    mutating func makePresentation() -> StreamingMarkdownPresentation {
        guard !normalized.isEmpty else {
            return StreamingMarkdownPresentation(visibleText: "", withheldConstruct: nil)
        }

        // Fence first, exactly like the batch scanner. The partial line toggles parity.
        let partialOpensFence = currentLineText
            .trimmingCharacters(in: .whitespaces)
            .hasPrefix("```")
        let effectiveFenceStart: Int? = partialOpensFence
            ? (openFenceStartUTF8 == nil ? currentLineStartUTF8 : nil)
            : openFenceStartUTF8
        if let fenceStart = effectiveFenceStart {
            return withheld(.codeFence, prefixUTF8: fenceStart)
        }

        // Table: simulate the partial line as the final line, then apply the batch
        // scanner's rule (anchored pair + at least one body line + run reaches EOF).
        var anchor = tableAnchorUTF8
        var body = tableBodyCount
        if !currentLineText.isEmpty {
            let rowish = StreamingMarkdownPresentation.looksLikeTableRow(currentLineText)
            if anchor != nil {
                if rowish {
                    body += 1
                } else {
                    anchor = nil
                    body = 0
                }
            }
            if anchor == nil,
               previousLineWasRowish,
               StreamingMarkdownPresentation.looksLikeTableSeparator(currentLineText) {
                anchor = previousLineStartUTF8
                body = 0
            }
        }
        if let anchor, body >= 1 {
            return withheld(.table, prefixUTF8: anchor)
        }

        cachedWithheldPrefixOffset = nil
        cachedWithheldPrefix = ""
        return StreamingMarkdownPresentation(visibleText: normalized, withheldConstruct: nil)
    }

    private mutating func foldCompletedLine() {
        let line = currentLineText
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            openFenceStartUTF8 = openFenceStartUTF8 == nil ? currentLineStartUTF8 : nil
        }

        let rowish = StreamingMarkdownPresentation.looksLikeTableRow(line)
        if tableAnchorUTF8 != nil {
            if rowish {
                tableBodyCount += 1
            } else {
                tableAnchorUTF8 = nil
                tableBodyCount = 0
            }
        }
        if tableAnchorUTF8 == nil,
           previousLineWasRowish,
           StreamingMarkdownPresentation.looksLikeTableSeparator(line) {
            tableAnchorUTF8 = previousLineStartUTF8
            tableBodyCount = 0
        }
        previousLineWasRowish = rowish
        previousLineStartUTF8 = currentLineStartUTF8

        currentLineText = ""
        currentLineStartUTF8 = normalizedUTF8Count
    }

    private mutating func withheld(
        _ construct: StreamingMarkdownPresentation.WithheldConstruct,
        prefixUTF8: Int
    ) -> StreamingMarkdownPresentation {
        if cachedWithheldPrefixOffset != prefixUTF8 {
            let cut = normalized.utf8.index(normalized.utf8.startIndex, offsetBy: prefixUTF8)
            cachedWithheldPrefix = String(normalized[..<cut])
            cachedWithheldPrefixOffset = prefixUTF8
        }
        return StreamingMarkdownPresentation(
            visibleText: cachedWithheldPrefix,
            withheldConstruct: construct
        )
    }
}

/// Presentation-only structure for the public reasoning summaries emitted by ACP.
///
/// The source chunks stay ordered and separate in memory. This projection adds
/// labels and display bounds without becoming transcript, persistence, or export
/// state and without requesting or reconstructing hidden chain-of-thought.
struct ReasoningSummaryPresentation: Equatable {
    enum StageKind: String, Equatable {
        case plan
        case currentAction
        case fallback
        case synthesis
        case completion

        var displayName: String {
            switch self {
            case .plan: return "Plan"
            case .currentAction: return "Current action"
            case .fallback: return "Fallback or error"
            case .synthesis: return "Synthesis"
            case .completion: return "Completion"
            }
        }
    }

    struct Stage: Identifiable, Equatable {
        let ordinal: Int
        let kind: StageKind
        let text: String
        let isTextTruncated: Bool

        var id: Int { ordinal }
    }

    static let compactStageLimit = 5
    static let compactCharacterLimit = 4_000
    static let expandedStageLimit = 20
    static let expandedCharacterLimit = 12_000

    let stages: [Stage]
    let sourceChunkCount: Int
    let sourceStageCount: Int
    let omittedStageCount: Int
    let isTruncated: Bool

    var displayedCharacterCount: Int {
        stages.reduce(0) { $0 + $1.text.count }
    }

    static func make(chunks: [String], expanded: Bool) -> Self {
        let sourceChunks = chunks
            .map(TranscriptTextPresentation.normalize)
            .filter { !$0.isEmpty }
        let sourceStages = groupedStages(from: sourceChunks)
        let stageLimit = expanded ? expandedStageLimit : compactStageLimit
        var remainingCharacters = expanded ? expandedCharacterLimit : compactCharacterLimit
        var stages: [Stage] = []

        for (index, sourceText) in sourceStages.prefix(stageLimit).enumerated() {
            guard remainingCharacters > 0 else { break }
            let bounded = boundedText(sourceText, limit: remainingCharacters)
            stages.append(Stage(
                ordinal: index + 1,
                kind: stageKind(for: sourceText, ordinal: index + 1),
                text: bounded.text,
                isTextTruncated: bounded.truncated
            ))
            remainingCharacters -= bounded.text.count
            if bounded.truncated { break }
        }

        let omittedStageCount = max(0, sourceStages.count - stages.count)
        return Self(
            stages: stages,
            sourceChunkCount: sourceChunks.count,
            sourceStageCount: sourceStages.count,
            omittedStageCount: omittedStageCount,
            isTruncated: omittedStageCount > 0 || stages.contains(where: \.isTextTruncated)
        )
    }

    /// Useful for deterministic fixture assertions and plain-text accessibility
    /// fallbacks. The blank line is a presentation boundary, never durable text.
    var presentationOnlyText: String {
        stages.map(\.text).joined(separator: "\n\n")
    }

    private static func stageKind(for text: String, ordinal: Int) -> StageKind {
        let cue = TranscriptTextPresentation.singleLine(text, maxLength: 600).lowercased()
        if cue.contains("fallback") || cue.contains("failed") || cue.contains("error")
            || cue.contains("retry") || cue.contains("alternate") {
            return .fallback
        }
        if cue.contains("completed") || cue.contains("finished") || cue.contains("done")
            || cue.contains("ready for review") {
            return .completion
        }
        if cue.contains("synthesis") || cue.contains("synthes") || cue.contains("combining")
            || cue.contains("summarizing") {
            return .synthesis
        }
        if cue.contains("plan") || ordinal == 1 {
            return .plan
        }
        return .currentAction
    }

    /// ACP providers vary between sentence-sized public summary updates and
    /// token-sized deltas. A leading/trailing whitespace boundary or a punctuation
    /// delta is explicit continuation evidence, so it stays in the same stage.
    /// Two word-like chunks with no boundary become separate presentation stages
    /// instead of being fused into corrupt prose.
    private static func groupedStages(from chunks: [String]) -> [String] {
        guard var current = chunks.first else { return [] }
        var stages: [String] = []

        for chunk in chunks.dropFirst() {
            if continuesCurrentStage(previous: current, next: chunk) {
                current += chunk
            } else {
                stages.append(current)
                current = chunk
            }
        }
        stages.append(current)
        return stages
    }

    private static func continuesCurrentStage(previous: String, next: String) -> Bool {
        guard let previousLast = previous.unicodeScalars.last,
              let nextFirst = next.unicodeScalars.first else { return true }
        if CharacterSet.whitespacesAndNewlines.contains(previousLast)
            || CharacterSet.whitespacesAndNewlines.contains(nextFirst) {
            return true
        }
        return CharacterSet.punctuationCharacters.contains(nextFirst)
            || CharacterSet.symbols.contains(nextFirst)
    }

    private static func boundedText(_ text: String, limit: Int) -> (text: String, truncated: Bool) {
        guard text.count > limit else { return (text, false) }
        guard limit > 1 else { return ("…", true) }
        let end = text.index(text.startIndex, offsetBy: limit - 1)
        return (String(text[..<end]) + "…", true)
    }
}
