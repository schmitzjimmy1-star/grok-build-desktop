import SwiftUI
import AppKit
import WebKit
import CryptoKit

enum RichContentWidthClass: String, Hashable, Sendable {
    case regular
    case narrow
}

enum MarkdownBlock: Identifiable, Hashable, Sendable {
    case text(String)
    case mermaid(String)
    case latex(String, display: Bool)

    var id: String {
        switch self {
        case .text(let s): return "t-\(s.hashValue)"
        case .mermaid(let s): return "m-\(s.hashValue)"
        case .latex(let s, let d): return "l-\(d)-\(s.hashValue)"
        }
    }
}

/// Bounded, process-local rich content cache. Transcript bodies remain the source of truth;
/// this cache is disposable render work only and never crosses launches or gets persisted.
enum RichContentCache {
    static let renderVersion = 2
    static let maximumEntries = 64

    struct Key: Hashable, Sendable {
        let messageID: UUID?
        let contentDigest: String
        let widthClass: RichContentWidthClass
        let renderVersion: Int
    }

    struct TextKey: Hashable, Sendable {
        let contentDigest: String
        let renderVersion: Int
    }

    enum WebContentKind: String, Sendable {
        case mermaid
        case latex
    }

    struct Stats: Equatable, Sendable {
        let blockHits: Int
        let blockMisses: Int
        let textHits: Int
        let textMisses: Int
        let webHeightHits: Int
        let webHeightMisses: Int
        let entryCount: Int
    }

    private struct BlockEntry {
        let blocks: [MarkdownBlock]
        var lastUsed: UInt64
    }

    private struct TextEntry {
        let blocks: [MarkdownTextBlock]
        var lastUsed: UInt64
    }

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var sequence: UInt64 = 0
        var blockEntries: [String: BlockEntry] = [:]
        var textEntries: [String: TextEntry] = [:]
        var webHeights: [String: CGFloat] = [:]
        var blockHits = 0
        var blockMisses = 0
        var textHits = 0
        var textMisses = 0
        var webHeightHits = 0
        var webHeightMisses = 0
    }

    private static let storage = Storage()

    static func key(
        messageID: UUID?,
        text: String,
        widthClass: RichContentWidthClass = .regular
    ) -> Key {
        Key(
            messageID: messageID,
            contentDigest: digest(text),
            widthClass: widthClass,
            renderVersion: renderVersion
        )
    }

    static func textKey(_ text: String) -> TextKey {
        TextKey(contentDigest: digest(text), renderVersion: renderVersion)
    }

    static func blocks(for key: Key) -> [MarkdownBlock]? {
        withLock { storage in
            let rawKey = blockStorageKey(key)
            guard let entry = storage.blockEntries[rawKey] else {
                storage.blockMisses += 1
                return nil
            }
            storage.blockHits += 1
            storage.sequence &+= 1
            storage.blockEntries[rawKey]?.lastUsed = storage.sequence
            return entry.blocks
        }
    }

    static func store(_ blocks: [MarkdownBlock], for key: Key) {
        withLock { storage in
            storage.sequence &+= 1
            storage.blockEntries[blockStorageKey(key)] = BlockEntry(
                blocks: blocks,
                lastUsed: storage.sequence
            )
            evictIfNeeded(storage)
        }
    }

    static func textBlocks(for key: TextKey) -> [MarkdownTextBlock]? {
        withLock { storage in
            let rawKey = textStorageKey(key)
            guard let entry = storage.textEntries[rawKey] else {
                storage.textMisses += 1
                return nil
            }
            storage.textHits += 1
            storage.sequence &+= 1
            storage.textEntries[rawKey]?.lastUsed = storage.sequence
            return entry.blocks
        }
    }

    static func store(_ blocks: [MarkdownTextBlock], for key: TextKey) {
        withLock { storage in
            storage.sequence &+= 1
            storage.textEntries[textStorageKey(key)] = TextEntry(
                blocks: blocks,
                lastUsed: storage.sequence
            )
            evictIfNeeded(storage)
        }
    }

    static func cachedWebHeight(
        kind: WebContentKind,
        source: String,
        displayMode: Bool = false,
        appearanceKey: String = "default"
    ) -> CGFloat? {
        withLock { storage in
            let key = webStorageKey(
                kind: kind,
                source: source,
                displayMode: displayMode,
                appearanceKey: appearanceKey
            )
            guard let height = storage.webHeights[key] else {
                storage.webHeightMisses += 1
                return nil
            }
            storage.webHeightHits += 1
            return height
        }
    }

    static func storeWebHeight(
        _ height: CGFloat,
        kind: WebContentKind,
        source: String,
        displayMode: Bool = false,
        appearanceKey: String = "default"
    ) {
        guard height > 0 else { return }
        withLock { storage in
            storage.webHeights[webStorageKey(
                kind: kind,
                source: source,
                displayMode: displayMode,
                appearanceKey: appearanceKey
            )] = height
            evictIfNeeded(storage)
        }
    }

    static var stats: Stats {
        withLock { storage in
            Stats(
                blockHits: storage.blockHits,
                blockMisses: storage.blockMisses,
                textHits: storage.textHits,
                textMisses: storage.textMisses,
                webHeightHits: storage.webHeightHits,
                webHeightMisses: storage.webHeightMisses,
                entryCount: storage.blockEntries.count + storage.textEntries.count + storage.webHeights.count
            )
        }
    }

    static func resetForTests() {
        withLock { storage in
            storage.sequence = 0
            storage.blockEntries.removeAll()
            storage.textEntries.removeAll()
            storage.webHeights.removeAll()
            storage.blockHits = 0
            storage.blockMisses = 0
            storage.textHits = 0
            storage.textMisses = 0
            storage.webHeightHits = 0
            storage.webHeightMisses = 0
        }
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func blockStorageKey(_ key: Key) -> String {
        "block|\(key.messageID?.uuidString ?? "none")|\(key.contentDigest)|\(key.widthClass.rawValue)|\(key.renderVersion)"
    }

    private static func textStorageKey(_ key: TextKey) -> String {
        "text|\(key.contentDigest)|\(key.renderVersion)"
    }

    private static func webStorageKey(
        kind: WebContentKind,
        source: String,
        displayMode: Bool,
        appearanceKey: String
    ) -> String {
        "web|\(kind.rawValue)|\(digest(source))|\(displayMode)|\(appearanceKey)|\(renderVersion)"
    }

    private static func evictIfNeeded(_ storage: Storage) {
        while storage.blockEntries.count + storage.textEntries.count + storage.webHeights.count > maximumEntries {
            let oldestBlock = storage.blockEntries.min { $0.value.lastUsed < $1.value.lastUsed }
            let oldestText = storage.textEntries.min { $0.value.lastUsed < $1.value.lastUsed }
            if let oldestBlock,
               oldestText == nil || oldestBlock.value.lastUsed <= oldestText!.value.lastUsed {
                storage.blockEntries.removeValue(forKey: oldestBlock.key)
            } else if let oldestText {
                storage.textEntries.removeValue(forKey: oldestText.key)
            } else if let oldestWeb = storage.webHeights.keys.first {
                storage.webHeights.removeValue(forKey: oldestWeb)
            } else {
                break
            }
        }
    }

    private static func withLock<Value>(_ body: (Storage) -> Value) -> Value {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return body(storage)
    }
}

enum MarkdownBlockParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let interval = GrokBuildPerformance.begin(.richMessageParse)
        defer { interval.end() }
        var blocks: [MarkdownBlock] = []
        var remaining = text

        while !remaining.isEmpty {
            if let match = firstSpecialBlock(in: remaining) {
                let before = String(remaining[..<match.range.lowerBound])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(before))
                }
                blocks.append(match.block)
                remaining = String(remaining[match.range.upperBound...])
            } else {
                blocks.append(.text(remaining))
                break
            }
        }

        return blocks.isEmpty ? [.text(text)] : blocks
    }

    /// True when `$…$` content looks like LaTeX, not currency or shell variables.
    static func looksLikeInlineMath(_ content: String) -> Bool {
        if content.contains("\\") { return true }
        if content.contains(where: { "^_{}[]".contains($0) }) { return true }
        if content.contains(where: { "=<>≠≤≥≈∝".contains($0) }) { return true }
        return false
    }

    private struct Match {
        let range: Range<String.Index>
        let block: MarkdownBlock
    }

    private static func firstSpecialBlock(in text: String) -> Match? {
        var best: Match?

        if let m = matchFenced(in: text, language: "mermaid") {
            best = m
        }

        for lang in ["latex", "tex", "math"] {
            if let m = matchFenced(in: text, language: lang) {
                if best == nil || m.range.lowerBound < best!.range.lowerBound { best = m }
            }
        }

        if let m = matchDisplayMath(in: text) {
            if best == nil || m.range.lowerBound < best!.range.lowerBound { best = m }
        }

        return best
    }

    // Compiled once — these run inside body-adjacent parsing for every
    // rendered block, and NSRegularExpression construction is not cheap.
    private static let fencedRegexes: [String: NSRegularExpression] = {
        var regexes: [String: NSRegularExpression] = [:]
        for language in ["mermaid", "latex", "tex", "math"] {
            regexes[language] = try? NSRegularExpression(
                pattern: "```\(language)\\s*([\\s\\S]*?)```",
                options: .caseInsensitive
            )
        }
        return regexes
    }()

    private static let displayMathRegexes = [
        try? NSRegularExpression(pattern: #"\$\$([\s\S]*?)\$\$"#),
        try? NSRegularExpression(pattern: #"\\\[([\s\S]*?)\\\]"#),
    ].compactMap { $0 }

    private static func matchFenced(in text: String, language: String) -> Match? {
        guard let regex = fencedRegexes[language] else { return nil }
        let ns = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              result.numberOfRanges > 1,
              let fullRange = Range(result.range, in: text),
              let contentRange = Range(result.range(at: 1), in: text) else { return nil }
        let content = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let block: MarkdownBlock = language.lowercased() == "mermaid"
            ? .mermaid(content)
            : .latex(content, display: true)
        return Match(range: fullRange, block: block)
    }

    private static func matchDisplayMath(in text: String) -> Match? {
        let ns = text as NSString
        var best: Match?
        for regex in displayMathRegexes {
            guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
                  result.numberOfRanges > 1,
                  let fullRange = Range(result.range, in: text),
                  let contentRange = Range(result.range(at: 1), in: text) else { continue }
            let candidate = Match(
                range: fullRange,
                block: .latex(String(text[contentRange]), display: true)
            )
            if best == nil || candidate.range.lowerBound < best!.range.lowerBound {
                best = candidate
            }
        }
        return best
    }

}

/// Inline LaTeX must remain inside its paragraph/list/table cell. Promoting `\(...\)`
/// to a top-level WKWebView splits Markdown tables at every formula. Keep display math
/// in KaTeX blocks, while translating common inline notation to readable native text.
enum InlineMathNormalizer {
    private static let escapedRegex = try? NSRegularExpression(pattern: #"\\\(([^\n]*?)\\\)"#)
    private static let dollarRegex = try? NSRegularExpression(
        pattern: #"(?<!\$)\$(?!\$)([^\$\n]+?)\$(?!\$)"#
    )
    private static let bracedFractionRegex = try? NSRegularExpression(
        pattern: #"\\(?:[td]?frac)\{([^{}]+)\}\{([^{}]+)\}"#
    )
    private static let textCommandRegex = try? NSRegularExpression(
        pattern: #"\\(?:text|texttt|mathrm|operatorname)\{([^{}]*)\}"#
    )

    static func normalize(_ source: String) -> String {
        var result = replacingMatches(in: source, regex: escapedRegex, requireMathSignals: false)
        result = replacingMatches(in: result, regex: dollarRegex, requireMathSignals: true)
        return result
    }

    private static func replacingMatches(
        in source: String,
        regex: NSRegularExpression?,
        requireMathSignals: Bool
    ) -> String {
        guard let regex else { return source }
        var result = source
        let matches = regex.matches(
            in: source,
            range: NSRange(location: 0, length: (source as NSString).length)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range, in: result),
                  let contentRange = Range(match.range(at: 1), in: result) else { continue }
            let content = String(result[contentRange])
            if requireMathSignals && !MarkdownBlockParser.looksLikeInlineMath(content) { continue }
            result.replaceSubrange(fullRange, with: readable(content))
        }
        return result
    }

    static func readable(_ latex: String) -> String {
        var result = latex
        result = replacingCapture(in: result, regex: textCommandRegex, template: "$1")
        result = replacingCapture(in: result, regex: bracedFractionRegex, template: "$1/$2")
        let replacements = [
            (#"\Bigl"#, ""), (#"\Bigr"#, ""), (#"\left"#, ""), (#"\right"#, ""),
            (#"\frac12"#, "1/2"), (#"\frac14"#, "1/4"),
            (#"\tfrac12"#, "1/2"), (#"\tfrac14"#, "1/4"),
            (#"\dfrac12"#, "1/2"), (#"\dfrac14"#, "1/4"),
            (#"\ln"#, "ln"), (#"\int"#, "∫"), (#"\sum"#, "∑"),
            (#"\times"#, "×"), (#"\cdot"#, "·"), (#"\to"#, "→"),
            (#"\approx"#, "≈"), (#"\le"#, "≤"), (#"\ge"#, "≥"),
            (#"\,"#, " "), (#"\!"#, ""), (#"\;"#, " "),
        ]
        for (target, replacement) in replacements {
            result = result.replacingOccurrences(of: target, with: replacement)
        }
        return result
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
    }

    private static func replacingCapture(
        in source: String,
        regex: NSRegularExpression?,
        template: String
    ) -> String {
        guard let regex else { return source }
        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(location: 0, length: (source as NSString).length),
            withTemplate: template
        )
    }
}

struct InlineMarkdownLink: Identifiable, Hashable, Sendable {
    let title: String
    let destination: URL

    var id: String { "\(title)|\(destination.absoluteString)" }
}

/// One parser owns visual link treatment and the virtual AX link children. SwiftUI's
/// native Markdown `Text` keeps links clickable, while the virtual children stop a
/// paragraph containing several sources from collapsing into one undifferentiated AX node.
enum InlineMarkdownPresentation {
    static func rendered(_ source: String) -> AttributedString {
        let normalized = InlineMathNormalizer.normalize(source)
        guard var attributed = try? AttributedString(
            markdown: normalized,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            return AttributedString(normalized)
        }

        let linkRanges = attributed.runs.compactMap { run in
            run.link == nil ? nil : run.range
        }
        for range in linkRanges {
            attributed[range].foregroundColor = .accentColor
            attributed[range].underlineStyle = .single
        }
        return attributed
    }

    static func links(in source: String) -> [InlineMarkdownLink] {
        let attributed = rendered(source)
        return attributed.runs.compactMap { run in
            guard let destination = run.link else { return nil }
            let title = String(attributed.characters[run.range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return InlineMarkdownLink(title: title, destination: destination)
        }
    }

    static func spokenText(_ source: String) -> String {
        String(rendered(source).characters)
    }
}

enum MathAccessibility {
    static func spokenDescription(_ latex: String) -> String {
        let readable = InlineMathNormalizer.readable(latex)
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return readable.isEmpty ? "Equation" : "Equation: \(readable)"
    }
}

enum MarkdownTableAccessibility {
    static func summary(headers: [String], rows: [[String]]) -> String {
        "Table, \(headers.count) column\(headers.count == 1 ? "" : "s"), \(rows.count) data row\(rows.count == 1 ? "" : "s")"
    }

    static func headerLabel(_ header: String, column: Int) -> String {
        "Column \(column + 1), \(InlineMarkdownPresentation.spokenText(header))"
    }

    static func cellLabel(headers: [String], value: String, column: Int) -> String {
        let spokenValue = InlineMarkdownPresentation.spokenText(value)
        guard headers.indices.contains(column) else {
            return "Column \(column + 1): \(spokenValue)"
        }
        return "\(InlineMarkdownPresentation.spokenText(headers[column])): \(spokenValue)"
    }

    static func linearDescription(headers: [String], rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "Table has no data rows." }
        return rows.enumerated().map { rowIndex, row in
            let cells = row.enumerated().map { column, value in
                cellLabel(headers: headers, value: value, column: column)
            }
            return "Row \(rowIndex + 1): \(cells.joined(separator: "; "))."
        }.joined(separator: " ")
    }
}

/// Pure table sizing policy. A table fills the reading column when it fits,
/// but preserves a usable minimum cell width and falls back to horizontal
/// scrolling rather than crushing technical text into a fake grid.
enum MarkdownTableLayout {
    static let minimumColumnWidth: CGFloat = 96
    static let maximumColumnWidth: CGFloat = 360

    static func columnWidths(
        headers: [String],
        rows: [[String]],
        availableWidth: CGFloat
    ) -> [CGFloat] {
        guard !headers.isEmpty else { return [] }
        let columnCount = headers.count
        let minimumTotal = minimumColumnWidth * CGFloat(columnCount)
        let targetTotal = max(minimumTotal, availableWidth)
        let weights = (0..<columnCount).map { column in
            let values = [headers[column]] + rows.compactMap { row in
                row.indices.contains(column) ? row[column] : nil
            }
            return CGFloat(min(max(values.map { $0.count }.max() ?? 1, 8), 42))
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return Array(repeating: targetTotal / CGFloat(columnCount), count: columnCount)
        }

        var widths = Array(repeating: minimumColumnWidth, count: columnCount)
        var remaining = targetTotal - minimumTotal
        var eligible = Set(widths.indices)
        while remaining > 0.5, !eligible.isEmpty {
            let eligibleWeight = eligible.reduce(CGFloat.zero) { $0 + weights[$1] }
            guard eligibleWeight > 0 else { break }
            var allocated: CGFloat = 0
            var capped: [Int] = []
            for column in eligible {
                let share = remaining * (weights[column] / eligibleWeight)
                let room = maximumColumnWidth - widths[column]
                let addition = min(share, room)
                widths[column] += addition
                allocated += addition
                if room - addition < 0.5 { capped.append(column) }
            }
            guard allocated > 0 else { break }
            remaining -= allocated
            capped.forEach { eligible.remove($0) }
        }
        return widths
    }
}

enum RichContentFallback {
    static func mermaid(source: String) -> String {
        "Diagram preview unavailable. Mermaid source: \(source)"
    }

    static func latex(source: String) -> String {
        "Equation preview unavailable. \(MathAccessibility.spokenDescription(source)). Source: \(source)"
    }
}

private struct InlineMarkdownAccessibilityModifier: ViewModifier {
    let source: String

    func body(content: Content) -> some View {
        let links = InlineMarkdownPresentation.links(in: source)
        content
            .accessibilityElement(children: links.isEmpty ? .combine : .contain)
            .accessibilityLabel(InlineMarkdownPresentation.spokenText(source))
            .accessibilityChildren {
                ForEach(links) { link in
                    Link(link.title, destination: link.destination)
                        .accessibilityLabel("Link: \(link.title)")
                }
            }
    }
}

private extension View {
    func accessibleInlineMarkdown(_ source: String) -> some View {
        modifier(InlineMarkdownAccessibilityModifier(source: source))
    }
}

struct MarkdownTextBlock: Identifiable, Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case unorderedList([String])
        case orderedList([String])
        case quote(String)
        case code(language: String?, text: String)
        case table(headers: [String], rows: [[String]])
        case divider
    }

    let id: Int
    let content: Content
}

enum MarkdownTextBlockParser {
    static func parse(_ text: String) -> [MarkdownTextBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownTextBlock] = []
        var index = 0

        func append(_ content: MarkdownTextBlock.Content) {
            blocks.append(MarkdownTextBlock(id: blocks.count, content: content))
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let languageText = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let language = languageText.isEmpty ? nil : languageText
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(candidate)
                    index += 1
                }
                append(.code(language: language, text: codeLines.joined(separator: "\n")))
                continue
            }

            if index + 1 < lines.count,
               looksLikeTableRow(line),
               looksLikeTableSeparator(lines[index + 1]) {
                let headers = tableCells(in: line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let candidate = lines[index]
                    guard looksLikeTableRow(candidate),
                          !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        break
                    }
                    rows.append(tableCells(in: candidate))
                    index += 1
                }
                append(.table(headers: headers, rows: rows))
                continue
            }

            if let heading = heading(in: trimmed) {
                append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(
                        String(candidate.dropFirst())
                            .trimmingCharacters(in: .whitespaces)
                    )
                    index += 1
                }
                append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            if unorderedListItem(in: trimmed) != nil {
                var items: [String] = []
                while index < lines.count,
                      let item = unorderedListItem(
                        in: lines[index].trimmingCharacters(in: .whitespaces)
                      ) {
                    items.append(item)
                    index += 1
                }
                append(.unorderedList(items))
                continue
            }

            if orderedListItem(in: trimmed) != nil {
                var items: [String] = []
                while index < lines.count,
                      let item = orderedListItem(
                        in: lines[index].trimmingCharacters(in: .whitespaces)
                      ) {
                    items.append(item)
                    index += 1
                }
                append(.orderedList(items))
                continue
            }

            if isDivider(trimmed) {
                append(.divider)
                index += 1
                continue
            }

            var paragraphLines: [String] = [line]
            index += 1
            while index < lines.count, !isBlockStart(lines, at: index) {
                paragraphLines.append(lines[index])
                index += 1
            }
            append(
                .paragraph(
                    paragraphLines
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }

        return blocks
    }

    private static func isBlockStart(_ lines: [String], at index: Int) -> Bool {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty
            || trimmed.hasPrefix("```")
            || trimmed.hasPrefix(">")
            || heading(in: trimmed) != nil
            || unorderedListItem(in: trimmed) != nil
            || orderedListItem(in: trimmed) != nil
            || isDivider(trimmed) {
            return true
        }
        return index + 1 < lines.count
            && looksLikeTableRow(lines[index])
            && looksLikeTableSeparator(lines[index + 1])
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...3).contains(hashes.count) else { return nil }
        let remainder = line.dropFirst(hashes.count)
        guard remainder.first == " " else { return nil }
        return (
            hashes.count,
            String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces)
        )
    }

    private static func unorderedListItem(in line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedListItem(in line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let number = line[..<dot]
        guard !number.isEmpty,
              number.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...])
    }

    private static func looksLikeTableRow(_ line: String) -> Bool {
        !tableCells(in: line).isEmpty
    }

    private static func looksLikeTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(in: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        let wasPipeWrapped = value.hasPrefix("|") && value.hasSuffix("|")
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        guard value.contains("|") || wasPipeWrapped else { return [] }
        return value
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3 && compact.allSatisfy { $0 == "-" }
    }
}

struct RichMessageView: View {
    let text: String
    let messageID: UUID?
    private let cacheKey: RichContentCache.Key
    @State private var parsedBlocks: [MarkdownBlock]?
    @State private var parsedKey: RichContentCache.Key?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        text: String,
        messageID: UUID? = nil,
        widthClass: RichContentWidthClass = .regular
    ) {
        self.text = text
        self.messageID = messageID
        let key = RichContentCache.key(messageID: messageID, text: text, widthClass: widthClass)
        cacheKey = key
        let cached = RichContentCache.blocks(for: key)
        _parsedBlocks = State(initialValue: cached)
        _parsedKey = State(initialValue: cached == nil ? nil : key)
    }

    var body: some View {
        let blocks = parsedKey == cacheKey ? parsedBlocks : nil
        Group {
            if let blocks {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(blocks) { block in
                        switch block {
                        case .text(let chunk):
                            MarkdownTextView(text: chunk)
                        case .mermaid(let source):
                            SizedMermaidWebView(
                                source: source,
                                appearance: RichWebAppearance(
                                    colorScheme: colorScheme,
                                    highContrast: colorSchemeContrast == .increased,
                                    reduceMotion: reduceMotion
                                )
                            )
                        case .latex(let expr, let display):
                            SizedLaTeXWebView(
                                latex: expr,
                                displayMode: display,
                                appearance: RichWebAppearance(
                                    colorScheme: colorScheme,
                                    highContrast: colorSchemeContrast == .increased,
                                    reduceMotion: reduceMotion
                                )
                            )
                        }
                    }
                }
            } else {
                Text(text)
                    .font(AppTheme.Typography.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Build agent response: \(text)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: cacheKey) {
            if let cached = RichContentCache.blocks(for: cacheKey) {
                parsedBlocks = cached
                parsedKey = cacheKey
                return
            }
            let source = text
            let parsed = await GrokBuildBackgroundWork.run(
                { MarkdownBlockParser.parse(source) },
                priority: .utility
            )
            guard !Task.isCancelled else { return }
            RichContentCache.store(parsed, for: cacheKey)
            parsedBlocks = parsed
            parsedKey = cacheKey
        }
    }
}

private struct MarkdownTextView: View {
    let text: String
    private let cacheKey: RichContentCache.TextKey
    @State private var parsedBlocks: [MarkdownTextBlock]?
    @State private var parsedKey: RichContentCache.TextKey?

    init(text: String) {
        self.text = text
        let key = RichContentCache.textKey(text)
        cacheKey = key
        let cached = RichContentCache.textBlocks(for: key)
        _parsedBlocks = State(initialValue: cached)
        _parsedKey = State(initialValue: cached == nil ? nil : key)
    }

    var body: some View {
        let blocks = parsedKey == cacheKey ? parsedBlocks : nil
        Group {
            if let blocks {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(blocks) { block in
                        blockView(block.content)
                    }
                }
            } else {
                Text(text)
                    .font(AppTheme.Typography.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: cacheKey) {
            if let cached = RichContentCache.textBlocks(for: cacheKey) {
                parsedBlocks = cached
                parsedKey = cacheKey
                return
            }
            let source = text
            let parsed = await GrokBuildBackgroundWork.run(
                { MarkdownTextBlockParser.parse(source) },
                priority: .utility
            )
            guard !Task.isCancelled else { return }
            RichContentCache.store(parsed, for: cacheKey)
            parsedBlocks = parsed
            parsedKey = cacheKey
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownTextBlock.Content) -> some View {
        switch block {
        case .paragraph(let text):
            Text(renderedInlineMarkdown(text))
                .font(AppTheme.Typography.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibleInlineMarkdown(text)

        case .heading(let level, let text):
            Text(renderedInlineMarkdown(text))
                .font(headingFont(level: level))
                .padding(.top, level == 1 ? 4 : 1)
                .textSelection(.enabled)
                .accessibleInlineMarkdown(text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Heading level \(level): \(InlineMarkdownPresentation.spokenText(text))")

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", text: item)
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listRow(marker: "\(index + 1).", text: item)
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 12) {
                Capsule()
                    .fill(AppTheme.Palette.accent.opacity(0.52))
                    .frame(width: 3)
                Text(renderedInlineMarkdown(text))
                    .font(AppTheme.Typography.body)
                    .italic()
                    .foregroundStyle(AppTheme.Palette.textMuted)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .accessibleInlineMarkdown(text)
            }
            .padding(.vertical, 3)

        case .code(let language, let text):
            CodeBlockView(language: language, text: text)

        case .table(let headers, let rows):
            markdownTable(headers: headers, rows: rows)

        case .divider:
            Divider()
                .overlay(AppTheme.Palette.glassBorderStrong)
                .padding(.vertical, 4)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(marker)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Palette.accent)
                .frame(width: 22, alignment: .trailing)
            Text(renderedInlineMarkdown(text))
                .font(AppTheme.Typography.body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibleInlineMarkdown(text)
        }
    }

    private func markdownTable(headers: [String], rows: [[String]]) -> some View {
        MarkdownTableView(headers: headers, rows: rows)
    }

    private func headingFont(level: Int) -> Font {
        AppTheme.Typography.markdownHeading(level: level)
    }

    private func renderedInlineMarkdown(_ chunk: String) -> AttributedString {
        InlineMarkdownPresentation.rendered(chunk)
    }
}

private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let widths = MarkdownTableLayout.columnWidths(
            headers: headers,
            rows: rows,
            availableWidth: availableWidth
        )
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, rowIndex: nil, emphasized: true, widths: widths)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    tableRow(row, rowIndex: index, emphasized: false, widths: widths)
                        .background(index.isMultiple(of: 2) ? AppTheme.Palette.accentSoft.opacity(0.33) : .clear)
                }
            }
            .frame(minWidth: widths.reduce(0, +), alignment: .leading)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in availableWidth = width }
            }
        }
        .background(AppTheme.Palette.richTableBackground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .stroke(AppTheme.Palette.glassBorder)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MarkdownTableAccessibility.summary(headers: headers, rows: rows))
        .accessibilityHint("A linear row-by-row description is available to assistive technology.")
        .accessibilityChildren {
            Text(MarkdownTableAccessibility.linearDescription(headers: headers, rows: rows))
        }
    }

    private func tableRow(
        _ cells: [String],
        rowIndex: Int?,
        emphasized: Bool,
        widths: [CGFloat]
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { column, cell in
                Text(InlineMarkdownPresentation.rendered(cell))
                    .font(.system(size: 13, weight: emphasized ? .semibold : .regular))
                    .foregroundStyle(emphasized ? Color.primary : AppTheme.Palette.textMuted)
                    .frame(
                        width: widths.indices.contains(column)
                            ? widths[column]
                            : MarkdownTableLayout.minimumColumnWidth,
                        alignment: .leading
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(AppTheme.Palette.glassBorder)
                            .frame(width: 1)
                    }
                    .accessibilityLabel(
                        emphasized
                            ? MarkdownTableAccessibility.headerLabel(cell, column: column)
                            : MarkdownTableAccessibility.cellLabel(headers: headers, value: cell, column: column)
                    )
                    .accessibilityAddTraits(emphasized ? .isHeader : [])
            }
        }
        .background(emphasized ? AppTheme.Palette.accentSoft : .clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowIndex.map { "Row \($0 + 1)" } ?? "Column headers")
    }
}

private struct CodeBlockView: View {
    let language: String?
    let text: String
    @State private var didCopy = false

    private var isAssistantDiffExample: Bool {
        AssistantDiffPresentation.isExample(language: language)
    }

    private var displayLanguage: String {
        isAssistantDiffExample ? "EXAMPLE DIFF" : (language?.uppercased() ?? "CODE")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(displayLanguage)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Palette.textMuted)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    didCopy = true
                    VoiceOverAnnouncer.announce("Code copied.")
                } label: {
                    Label(didCopy ? "Copied" : "Copy code", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .accessibilityLabel(didCopy ? "Code copied" : "Copy code")
                .accessibilityHint(isAssistantDiffExample ? "Copies this assistant-provided example. It is not a repository change." : "Copies the complete code block to the clipboard.")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 5)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(AppTheme.Typography.code)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(AppTheme.Palette.richContentBackground, in: RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .stroke(AppTheme.Palette.glassBorder)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isAssistantDiffExample ? "Assistant-provided diff example" : "\(language ?? "Code") code block")
        .accessibilityValue("\(text.split(whereSeparator: \.isNewline).count) lines")
    }
}

private struct RichWebAppearance: Equatable {
    let isDark: Bool
    let highContrast: Bool
    let reduceMotion: Bool

    init(colorScheme: ColorScheme, highContrast: Bool, reduceMotion: Bool) {
        isDark = colorScheme == .dark
        self.highContrast = highContrast
        self.reduceMotion = reduceMotion
    }

    var cacheKey: String {
        "\(isDark ? "dark" : "light")-\(highContrast ? "contrast" : "standard")-\(reduceMotion ? "still" : "motion")"
    }
}

private struct SizedMermaidWebView: View {
    let source: String
    let appearance: RichWebAppearance
    private let minHeight: CGFloat = 120
    @State private var height: CGFloat
    @State private var isMounted = false
    @State private var renderFailed = false

    init(source: String, appearance: RichWebAppearance) {
        self.source = source
        self.appearance = appearance
        _height = State(
            initialValue: max(
                RichContentCache.cachedWebHeight(
                    kind: .mermaid,
                    source: source,
                    appearanceKey: appearance.cacheKey
                ) ?? 120,
                120
            )
        )
    }

    var body: some View {
        Group {
            if renderFailed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagram preview unavailable — showing Mermaid source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CodeBlockView(language: "mermaid", text: source)
                }
            } else if isMounted {
                MermaidWebView(source: source, appearance: appearance, onFailure: {
                    renderFailed = true
                }) { newHeight in
                    // Never shrink below the fallback: a premature/small scrollHeight
                    // (mermaid renders after didFinish) must not collapse the block.
                    let clamped = max(newHeight, minHeight)
                    RichContentCache.storeWebHeight(
                        clamped,
                        kind: .mermaid,
                        source: source,
                        appearanceKey: appearance.cacheKey
                    )
                    if abs(clamped - height) > 1 {
                        height = clamped
                    }
                }
            } else {
                Text("Diagram preview loads when visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: renderFailed ? nil : height)
        .accessibilityElement(children: renderFailed ? .contain : .ignore)
        .accessibilityLabel(
            renderFailed
                ? RichContentFallback.mermaid(source: source)
                : "Diagram: \(source)"
        )
        .onAppear {
            isMounted = true
            renderFailed = false
        }
        .onDisappear { isMounted = false }
    }
}

private struct SizedLaTeXWebView: View {
    let latex: String
    let displayMode: Bool
    let appearance: RichWebAppearance
    private let minHeight: CGFloat
    @State private var height: CGFloat
    @State private var isMounted = false
    @State private var renderFailed = false

    init(latex: String, displayMode: Bool, appearance: RichWebAppearance) {
        self.latex = latex
        self.displayMode = displayMode
        self.appearance = appearance
        let floorHeight: CGFloat = displayMode ? 48 : 28
        self.minHeight = floorHeight
        _height = State(
            initialValue: max(
                RichContentCache.cachedWebHeight(
                    kind: .latex,
                    source: latex,
                    displayMode: displayMode,
                    appearanceKey: appearance.cacheKey
                ) ?? floorHeight,
                floorHeight
            )
        )
    }

    var body: some View {
        Group {
            if renderFailed {
                Text(RichContentFallback.latex(source: latex))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else if isMounted {
                LaTeXWebView(
                    latex: latex,
                    displayMode: displayMode,
                    appearance: appearance,
                    onFailure: { renderFailed = true }
                ) { newHeight in
                    let clamped = max(newHeight, minHeight)
                    RichContentCache.storeWebHeight(
                        clamped,
                        kind: .latex,
                        source: latex,
                        displayMode: displayMode,
                        appearanceKey: appearance.cacheKey
                    )
                    if abs(clamped - height) > 1 {
                        height = clamped
                    }
                }
            } else {
                Text(MathAccessibility.spokenDescription(latex))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: renderFailed ? nil : height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            renderFailed
                ? RichContentFallback.latex(source: latex)
                : MathAccessibility.spokenDescription(latex)
        )
        .onAppear {
            isMounted = true
            renderFailed = false
        }
        .onDisappear { isMounted = false }
    }
}

private enum RichHTML {
    static func escaped(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    static func javascriptString(_ source: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [source]),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "\"\""
        }
        return String(encoded.dropFirst().dropLast())
    }
}

private struct MermaidWebView: NSViewRepresentable {
    let source: String
    let appearance: RichWebAppearance
    var onFailure: () -> Void = {}
    var onHeightChange: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure, onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.renderInterval?.end()
        coordinator.renderInterval = nil
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.onFailure = onFailure
        let key = "\(appearance.cacheKey)|\(source)"
        guard key != context.coordinator.lastLoadedKey else { return }
        context.coordinator.renderInterval?.end()
        context.coordinator.renderInterval = GrokBuildPerformance.begin(.mermaidRender)
        context.coordinator.lastLoadedKey = key
        view.loadHTMLString(Self.html(for: source, appearance: appearance), baseURL: nil)
    }

    private static func html(for source: String, appearance: RichWebAppearance) -> String {
        let textColor = appearance.isDark ? "#e6e6e6" : "#202124"
        let borderColor = appearance.highContrast ? "#707070" : (appearance.isDark ? "#444444" : "#b8b8b8")
        let sourceLiteral = RichHTML.javascriptString(source)
        let fallbackSource = RichHTML.escaped(source)
        let motionCSS = appearance.reduceMotion ? "*{animation:none!important;transition:none!important;}" : ""
        return """
        <!doctype html><html><head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <style>
        body{margin:0;padding:8px;background:transparent;color:\(textColor);font-family:-apple-system,sans-serif}
        #fallback{margin:0;padding:8px;border:1px solid \(borderColor);border-radius:6px;white-space:pre-wrap;font:12px ui-monospace,monospace}
        #diagram[hidden],#fallback[hidden]{display:none}
        \(motionCSS)
        </style>
        </head><body>
        <pre id="fallback">Diagram preview unavailable.\n\(fallbackSource)</pre>
        <div id="diagram" class="mermaid" hidden></div>
        <script>
        const source = \(sourceLiteral);
        const fallback = document.getElementById('fallback');
        const diagram = document.getElementById('diagram');
        function renderDiagram() {
          if (typeof mermaid === 'undefined') return;
          diagram.textContent = source;
          try {
            mermaid.initialize({startOnLoad:false, theme:'\(appearance.isDark ? "dark" : "default")'});
            mermaid.run({nodes:[diagram]}).then(() => {
              fallback.hidden = true;
              diagram.hidden = false;
            }).catch(() => {
              diagram.hidden = true;
              fallback.hidden = false;
            });
          } catch (_) {
            diagram.hidden = true;
            fallback.hidden = false;
          }
        }
        window.addEventListener('load', () => setTimeout(renderDiagram, 0));
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedKey: String?
        var onFailure: () -> Void
        var onHeightChange: (CGFloat) -> Void
        var renderInterval: GrokBuildPerformanceInterval?

        init(
            onFailure: @escaping () -> Void,
            onHeightChange: @escaping (CGFloat) -> Void
        ) {
            self.onFailure = onFailure
            self.onHeightChange = onHeightChange
        }

        deinit {
            renderInterval?.end()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            renderInterval?.end()
            renderInterval = nil
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                guard let height = webViewScrollHeight(from: result) else { return }
                DispatchQueue.main.async {
                    self.onHeightChange(height)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            renderInterval?.end()
            renderInterval = nil
            onFailure()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            renderInterval?.end()
            renderInterval = nil
            onFailure()
        }
    }
}

private func webViewScrollHeight(from result: Any?) -> CGFloat? {
    let raw: CGFloat?
    if let value = result as? Double { raw = CGFloat(value) }
    else if let value = result as? Int { raw = CGFloat(value) }
    else if let value = result as? CGFloat { raw = value }
    else { raw = nil }
    // Ignore non-positive readings (transient/blocked load) so the fallback height holds.
    guard let height = raw, height > 0 else { return nil }
    return height
}

private struct LaTeXWebView: NSViewRepresentable {
    let latex: String
    let displayMode: Bool
    let appearance: RichWebAppearance
    var onFailure: () -> Void = {}
    var onHeightChange: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure, onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onFailure = onFailure
        context.coordinator.onHeightChange = onHeightChange
        let key = "\(appearance.cacheKey)|\(displayMode)|\(latex)"
        guard key != context.coordinator.lastLoadedKey else { return }
        context.coordinator.lastLoadedKey = key
        view.loadHTMLString(
            Self.html(latex: latex, displayMode: displayMode, appearance: appearance),
            baseURL: nil
        )
    }

    private static func html(
        latex: String,
        displayMode: Bool,
        appearance: RichWebAppearance
    ) -> String {
        let textColor = appearance.isDark ? "#e6e6e6" : "#202124"
        let borderColor = appearance.highContrast ? "#707070" : (appearance.isDark ? "#444444" : "#b8b8b8")
        let sourceLiteral = RichHTML.javascriptString(latex)
        let fallbackSource = RichHTML.escaped(latex)
        let motionCSS = appearance.reduceMotion ? "*{animation:none!important;transition:none!important;}" : ""
        return """
        <!doctype html><html><head>
        <meta charset="utf-8">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <style>
        body{margin:0;padding:4px 8px;background:transparent;color:\(textColor);font-family:-apple-system,sans-serif}
        .katex{color:\(textColor)}
        #fallback{margin:0;padding:8px;border:1px solid \(borderColor);border-radius:6px;white-space:pre-wrap;font:12px ui-monospace,monospace}
        #math[hidden],#fallback[hidden]{display:none}
        \(motionCSS)
        </style>
        </head><body><pre id="fallback">Equation preview unavailable.\n\(fallbackSource)</pre><div id="math" hidden></div>
        <script>
        const source = \(sourceLiteral);
        const fallback = document.getElementById('fallback');
        const math = document.getElementById('math');
        try {
          if (typeof katex === 'undefined') throw new Error('KaTeX unavailable');
          katex.render(source, math, { displayMode: \(displayMode ? "true" : "false"), throwOnError: false });
          fallback.hidden = true;
          math.hidden = false;
        } catch (_) {
          fallback.hidden = false;
          math.hidden = true;
        }
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedKey: String?
        var onFailure: () -> Void
        var onHeightChange: (CGFloat) -> Void

        init(
            onFailure: @escaping () -> Void,
            onHeightChange: @escaping (CGFloat) -> Void
        ) {
            self.onFailure = onFailure
            self.onHeightChange = onHeightChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                guard let height = webViewScrollHeight(from: result) else { return }
                DispatchQueue.main.async {
                    self.onHeightChange(height)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }
    }
}
