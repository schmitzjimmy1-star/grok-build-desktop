import Foundation

/// Canonical line-level TOML text helpers (Slice 10 dedup).
///
/// Five behaviorally identical `stripComment` copies (and two `unquote`/`quote` pairs)
/// had drifted across the config stores; a quoting bug fixed in one would silently
/// survive in the others. The stores keep one-line private shims so their call sites
/// are untouched — the logic lives here exactly once.
///
/// `GrokConfigLegacyMigration` deliberately keeps its own `unquote`: the one-shot
/// migration preserves backslash escapes verbatim, which is different semantics, not
/// a missed dedup.
enum TOMLLineParsing {
    /// Removes a `#` comment while respecting single/double quotes and `\"` escapes
    /// inside double-quoted strings.
    static func stripComment(_ line: String) -> String {
        var quote: Character?
        var escaped = false
        var result = ""

        for char in line {
            if let q = quote {
                if q == "\"" {
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == "\"" {
                        quote = nil
                    }
                } else if char == q {
                    quote = nil
                }
                result.append(char)
                continue
            }
            if char == "#" { break }
            if char == "\"" || char == "'" {
                quote = char
                result.append(char)
                continue
            }
            result.append(char)
        }
        return result
    }

    /// Trims, strips symmetric quotes, and unescapes `\"` / `\\`.
    static func unquote(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespaces)
        if v.count >= 2,
           (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Double-quotes a value, escaping backslashes and embedded quotes.
    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
