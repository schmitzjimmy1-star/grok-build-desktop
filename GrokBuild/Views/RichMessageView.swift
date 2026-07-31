import SwiftUI
import WebKit

enum MarkdownBlock: Identifiable, Hashable {
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

enum MarkdownBlockParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
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
        if content.contains(where: { "^_{}".contains($0) }) { return true }
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

        if let m = matchInlineMath(in: text) {
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

    private static let displayMathRegex = try? NSRegularExpression(pattern: #"\$\$([\s\S]*?)\$\$"#)

    private static let inlineMathRegex = try? NSRegularExpression(pattern: #"(?<!\$)\$(?!\$)([^\$\n]+?)\$(?!\$)"#)

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
        guard let regex = displayMathRegex else { return nil }
        let ns = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              result.numberOfRanges > 1,
              let fullRange = Range(result.range, in: text),
              let contentRange = Range(result.range(at: 1), in: text) else { return nil }
        return Match(range: fullRange, block: .latex(String(text[contentRange]), display: true))
    }

    private static func matchInlineMath(in text: String) -> Match? {
        guard let regex = inlineMathRegex else { return nil }
        let ns = text as NSString
        for result in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard result.numberOfRanges > 1,
                  let fullRange = Range(result.range, in: text),
                  let contentRange = Range(result.range(at: 1), in: text) else { continue }
            let content = String(text[contentRange])
            guard looksLikeInlineMath(content) else { continue }
            return Match(range: fullRange, block: .latex(content, display: false))
        }
        return nil
    }
}

struct MarkdownTextBlock: Identifiable, Hashable {
    enum Content: Hashable {
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
        tableCells(in: line).count >= 2
    }

    private static func looksLikeTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(in: line)
        guard cells.count >= 2 else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        guard value.contains("|") else { return [] }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(MarkdownBlockParser.parse(text)) { block in
                switch block {
                case .text(let chunk):
                    MarkdownTextView(text: chunk)
                case .mermaid(let source):
                    SizedMermaidWebView(source: source)
                case .latex(let expr, let display):
                    SizedLaTeXWebView(latex: expr, displayMode: display)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(MarkdownTextBlockParser.parse(text)) { block in
                blockView(block.content)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

        case .heading(let level, let text):
            Text(renderedInlineMarkdown(text))
                .font(headingFont(level: level))
                .padding(.top, level == 1 ? 4 : 1)
                .textSelection(.enabled)

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
            }
            .padding(.vertical, 3)

        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 0) {
                if let language {
                    Text(language.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Palette.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 5)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(AppTheme.Typography.code)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
            .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .stroke(AppTheme.Palette.glassBorder)
            }

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
        }
    }

    private func markdownTable(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, emphasized: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    tableRow(row, emphasized: false)
                        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.025) : .clear)
                }
            }
        }
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .stroke(AppTheme.Palette.glassBorder)
        }
    }

    private func tableRow(_ cells: [String], emphasized: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(renderedInlineMarkdown(cell))
                    .font(.system(size: 13, weight: emphasized ? .semibold : .regular))
                    .foregroundStyle(emphasized ? Color.primary : AppTheme.Palette.textMuted)
                    .frame(width: 172, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(AppTheme.Palette.glassBorder)
                            .frame(width: 1)
                    }
            }
        }
        .background(emphasized ? AppTheme.Palette.accentSoft : .clear)
    }

    private func headingFont(level: Int) -> Font {
        AppTheme.Typography.markdownHeading(level: level)
    }

    private func renderedInlineMarkdown(_ chunk: String) -> AttributedString {
        if let attr = try? AttributedString(
            markdown: chunk,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return attr
        }
        return AttributedString(chunk)
    }
}

private struct SizedMermaidWebView: View {
    let source: String
    private let minHeight: CGFloat = 120
    @State private var height: CGFloat = 120

    var body: some View {
        MermaidWebView(source: source) { newHeight in
            // Never shrink below the fallback: a premature/small scrollHeight
            // (mermaid renders after didFinish) must not collapse the block.
            let clamped = max(newHeight, minHeight)
            if abs(clamped - height) > 1 {
                height = clamped
            }
        }
        .frame(height: height)
    }
}

private struct SizedLaTeXWebView: View {
    let latex: String
    let displayMode: Bool
    private let minHeight: CGFloat
    @State private var height: CGFloat

    init(latex: String, displayMode: Bool) {
        self.latex = latex
        self.displayMode = displayMode
        let floorHeight: CGFloat = displayMode ? 48 : 28
        self.minHeight = floorHeight
        _height = State(initialValue: floorHeight)
    }

    var body: some View {
        LaTeXWebView(latex: latex, displayMode: displayMode) { newHeight in
            let clamped = max(newHeight, minHeight)
            if abs(clamped - height) > 1 {
                height = clamped
            }
        }
        .frame(height: height)
    }
}

private struct MermaidWebView: NSViewRepresentable {
    let source: String
    var onHeightChange: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        guard source != context.coordinator.lastLoadedSource else { return }
        context.coordinator.lastLoadedSource = source
        view.loadHTMLString(Self.html(for: source), baseURL: nil)
    }

    private static func html(for source: String) -> String {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return """
        <!doctype html><html><head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <style>body{margin:0;padding:8px;background:transparent;color:#ccc;font-family:-apple-system,sans-serif}</style>
        </head><body><div class="mermaid">\(escaped)</div>
        <script>mermaid.initialize({startOnLoad:true,theme:'dark'});</script></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedSource: String?
        var onHeightChange: (CGFloat) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void) {
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
    var onHeightChange: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        let key = "\(displayMode)|\(latex)"
        guard key != context.coordinator.lastLoadedKey else { return }
        context.coordinator.lastLoadedKey = key
        view.loadHTMLString(Self.html(latex: latex, displayMode: displayMode), baseURL: nil)
    }

    private static func html(latex: String, displayMode: Bool) -> String {
        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
        return """
        <!doctype html><html><head>
        <meta charset="utf-8">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <style>body{margin:0;padding:4px 8px;background:transparent}</style>
        </head><body><div id="math"></div>
        <script>
        katex.render('\(escaped)', document.getElementById('math'), { displayMode: \(displayMode ? "true" : "false"), throwOnError: false });
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedKey: String?
        var onHeightChange: (CGFloat) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void) {
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
    }
}
