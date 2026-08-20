import SwiftUI

/// Presentation-only status for one assistant turn. Every settled label comes
/// from the checkpoint already attached to that message; a legacy turn with no
/// receipt stays unlabeled instead of being promoted to success from prose.
struct ConversationTurnStatusPresentation: Equatable {
    enum Kind: Equatable {
        case working
        case completed
        case needsReview
        case failed
        case stopped
        case cancelled
    }

    let kind: Kind
    let label: String
    let systemImage: String

    static func make(
        isLive: Bool,
        checkpoint: AssistantTurnCheckpoint?
    ) -> ConversationTurnStatusPresentation? {
        if isLive {
            return .init(kind: .working, label: "Working", systemImage: "circle.dotted")
        }
        guard let checkpoint else { return nil }

        switch checkpoint.outcomeCode {
        case ChatStore.TurnOutcome.failed.rawValue:
            return .init(kind: .failed, label: "Failed", systemImage: "xmark.circle.fill")
        case ChatStore.TurnOutcome.userStopped.rawValue:
            return .init(kind: .stopped, label: "Stopped", systemImage: "stop.circle.fill")
        case ChatStore.TurnOutcome.cancelled.rawValue:
            return .init(kind: .cancelled, label: "Cancelled", systemImage: "slash.circle.fill")
        case ChatStore.TurnOutcome.completionReceiptMissing.rawValue:
            return .init(
                kind: .needsReview,
                label: "Needs review",
                systemImage: "exclamationmark.triangle.fill"
            )
        default:
            break
        }

        let toolReceipt = checkpoint.toolSummaryReceipt
        let hasUnresolvedTools = (toolReceipt?.failed ?? 0) > 0
            || (toolReceipt?.unknown ?? 0) > 0
        let hasUnresolvedWorkers = checkpoint.workerReceipts?.contains {
            let status = $0.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return status.contains("fail")
                || status.contains("review")
                || status.contains("unknown")
                || status.contains("orphan")
        } == true
        let needsReview = checkpoint.requiresRecoveryAction
            || checkpoint.unresolvedErrors?.isEmpty == false
            || hasUnresolvedTools
            || hasUnresolvedWorkers

        if needsReview {
            return .init(
                kind: .needsReview,
                label: "Needs review",
                systemImage: "exclamationmark.triangle.fill"
            )
        }
        if checkpoint.outcomeCode == ChatStore.TurnOutcome.completed.rawValue {
            return .init(kind: .completed, label: "Completed", systemImage: "checkmark.circle.fill")
        }
        return nil
    }
}

/// Human-readable tool phrasing for transcript rows. The raw receipt title is
/// retained as the target; this layer changes presentation only and never
/// manufactures a tool result or terminal status.
enum ToolActionPresentation {
    static func title(rawTitle: String, kind: String?, status: String?) -> String {
        let target = TranscriptTextPresentation.singleLine(rawTitle, maxLength: 120)
        let safeTarget = target.isEmpty ? "tool" : target
        guard !alreadyReadsLikeAction(safeTarget) else { return safeTarget }

        let haystack = "\(kind ?? "") \(safeTarget)".lowercased()
        let active = ToolActivitySummaryPresentation.isActive(status)
        if containsAny(haystack, ["browser", "navigate", "fetch", "http", "web"]) {
            return "\(active ? "Browsing" : "Browsed") \(safeTarget)"
        }
        if containsAny(haystack, ["search", "find", "grep", "ripgrep"]) {
            return "\(active ? "Searching" : "Searched") \(safeTarget)"
        }
        if containsAny(haystack, ["edit", "write", "patch", "apply_patch"]) {
            return "\(active ? "Editing" : "Edited") \(safeTarget)"
        }
        if containsAny(haystack, ["read", "inspect", "open_file"]) {
            return "\(active ? "Reading" : "Read") \(safeTarget)"
        }
        if containsAny(haystack, ["execute", "exec", "terminal", "shell", "command", "run"]) {
            return "\(active ? "Running" : "Ran") \(safeTarget)"
        }
        return "\(active ? "Using" : "Used") \(safeTarget)"
    }

    private static func alreadyReadsLikeAction(_ value: String) -> Bool {
        let first = value.split(whereSeparator: { $0.isWhitespace }).first?.lowercased() ?? ""
        return [
            "read", "reading", "edited", "editing", "wrote", "writing",
            "searched", "searching", "ran", "running", "browsed", "browsing",
            "used", "using", "generated", "generating",
        ].contains(first)
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains(where: value.contains)
    }
}

/// The one visual spine for an assistant turn. ChatView still owns ordering,
/// state, actions, and every child view; this component only composes them into
/// a readable timeline with a quiet turn boundary.
struct ConversationTurnSurface<Content: View>: View {
    let messageID: UUID
    let status: ConversationTurnStatusPresentation?
    private let content: Content

    init(
        messageID: UUID,
        status: ConversationTurnStatusPresentation?,
        @ViewBuilder content: () -> Content
    ) {
        self.messageID = messageID
        self.status = status
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 9)
                Rectangle()
                    .fill(AppTheme.Palette.divider)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 10)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.Palette.divider)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grok-conversation-turn-\(messageID.uuidString)")
    }

    private var statusColor: Color {
        guard let status else { return AppTheme.Palette.textFaint }
        switch status.kind {
        case .working: return AppTheme.Palette.link
        case .completed: return .green
        case .needsReview: return AppTheme.Palette.warning
        case .failed: return .red
        case .stopped, .cancelled: return .secondary
        }
    }
}

struct ConversationTurnStatusBadge: View {
    let presentation: ConversationTurnStatusPresentation

    var body: some View {
        Label(presentation.label, systemImage: presentation.systemImage)
            .font(AppTheme.Typography.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(color.opacity(0.10), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Turn status: \(presentation.label)")
    }

    private var color: Color {
        switch presentation.kind {
        case .working: return AppTheme.Palette.link
        case .completed: return .green
        case .needsReview: return AppTheme.Palette.warning
        case .failed: return .red
        case .stopped, .cancelled: return .secondary
        }
    }
}
