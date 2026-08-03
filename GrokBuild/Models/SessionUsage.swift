import Foundation

/// Configured role→model routing lookups for spawned workers (agentic roadmap Slice 5).
///
/// A spawned worker's title is the role name when the spawn call named one
/// (`BackgroundToolParsing.title`), so an exact case-insensitive title match against
/// `[subagents.roles.*]` yields the *configured* route. This is declared routing from
/// config — the display labels it "(configured)" and never claims runtime billing.
/// No match, or a role that inherits (empty model), means no claim at all.
enum SubagentRouting {
    static func rolesByName(_ roles: [SubagentRole]) -> [String: String] {
        var map: [String: String] = [:]
        for role in roles {
            let name = role.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let model = role.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !model.isEmpty else { continue }
            map[name] = model
        }
        return map
    }

    static func routedModel(forWorkerTitle title: String, rolesByName: [String: String]) -> String? {
        let key = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return rolesByName[key]
    }
}

/// Cumulative, session-local usage ledger (agentic roadmap Slice 6).
///
/// One entry per settled turn, recorded from the authoritative `turn_completed` usage
/// receipt. Display-only: it never estimates while a turn is running, and dollar
/// figures are labeled estimates derived from catalog pricing — absent pricing shows
/// tokens only, never a fabricated $0.
struct SessionUsageLedger: Equatable {
    struct Entry: Equatable {
        let modelID: String?
        let totalTokens: Int
        let modelCalls: Int
    }

    /// A low–high USD bound: the true split between prompt and completion tokens is
    /// not reported over ACP, so the honest estimate brackets both extremes.
    struct Estimate: Equatable {
        let low: Double
        let high: Double
        let pricedTokens: Int
        let totalTokens: Int

        var coversAllTokens: Bool { pricedTokens == totalTokens }
    }

    private(set) var entries: [Entry] = []

    var turnCount: Int { entries.count }
    var totalTokens: Int { entries.reduce(0) { $0 + $1.totalTokens } }
    var totalModelCalls: Int { entries.reduce(0) { $0 + $1.modelCalls } }
    var isEmpty: Bool { entries.isEmpty }

    mutating func recordTurn(modelID: String?, totalTokens: Int?, modelCalls: Int?) {
        guard let totalTokens, totalTokens > 0 else { return }
        entries.append(Entry(
            modelID: modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
            totalTokens: totalTokens,
            modelCalls: modelCalls ?? 0
        ))
    }

    mutating func reset() {
        entries = []
    }

    func estimate(pricing: [String: ModelPricing]) -> Estimate? {
        var low = 0.0
        var high = 0.0
        var pricedTokens = 0
        for entry in entries {
            guard let modelID = entry.modelID, let price = pricing[modelID] else { continue }
            let lowRate = min(price.promptPerToken, price.completionPerToken)
            let highRate = max(price.promptPerToken, price.completionPerToken)
            low += Double(entry.totalTokens) * lowRate
            high += Double(entry.totalTokens) * highRate
            pricedTokens += entry.totalTokens
        }
        guard pricedTokens > 0 else { return nil }
        return Estimate(low: low, high: high, pricedTokens: pricedTokens, totalTokens: totalTokens)
    }

    /// One-line HUD text: "12.4k tokens · 3 calls · 2 turns · ≈$0.004–$0.016 est."
    /// Dollar figures appear only when at least one turn's model has known pricing;
    /// a partial-priced session says so instead of implying full coverage.
    func summaryText(pricing: [String: ModelPricing]) -> String? {
        guard !isEmpty else { return nil }
        var parts = [
            "\(Self.compactTokens(totalTokens)) tokens",
            "\(totalModelCalls) calls",
            "\(turnCount) \(turnCount == 1 ? "turn" : "turns")"
        ]
        if let estimate = estimate(pricing: pricing) {
            var dollars = "≈\(Self.dollars(estimate.low))–\(Self.dollars(estimate.high)) est."
            if !estimate.coversAllTokens {
                dollars += " (priced portion)"
            }
            parts.append(dollars)
        }
        return parts.joined(separator: " · ")
    }

    static func compactTokens(_ count: Int) -> String {
        switch count {
        case ..<1_000:
            return "\(count)"
        case ..<1_000_000:
            return "\((Double(count) / 1_000).formatted(.number.precision(.fractionLength(1))))k"
        default:
            return "\((Double(count) / 1_000_000).formatted(.number.precision(.fractionLength(2))))M"
        }
    }

    static func dollars(_ value: Double) -> String {
        if value >= 0.01 {
            return "$\(value.formatted(.number.precision(.fractionLength(2))))"
        }
        return "$\(value.formatted(.number.precision(.significantDigits(2))))"
    }
}
