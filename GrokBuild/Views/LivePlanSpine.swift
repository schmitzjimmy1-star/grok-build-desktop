import SwiftUI

/// Workbench W-5 — pure presentation policy for the in-transcript plan spine.
/// It formats the generation-bound plan steps the live projection already
/// carries; it never decides lifecycle state or invents progress.
enum PlanSpinePresentation {
    static func isCompleted(_ status: String) -> Bool {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed", "complete", "done", "success", "succeeded": return true
        default: return false
        }
    }

    static func completedCount(_ plan: [RunEvidenceSnapshot.PlanStep]) -> Int {
        plan.filter { isCompleted($0.status) }.count
    }

    static func progressLabel(_ plan: [RunEvidenceSnapshot.PlanStep]) -> String {
        "\(completedCount(plan)) of \(plan.count) done"
    }

    static func stepAccessibilityLabel(_ step: RunEvidenceSnapshot.PlanStep) -> String {
        let state = isCompleted(step.status) ? "completed"
            : step.isCurrent ? "in progress"
            : "pending"
        return "\(step.title), \(state)"
    }
}

/// Workbench W-5 (2026-08-08): while a run is active, the live plan projection
/// renders in the transcript flow — the plan is the spine of the run, not a
/// receipt hidden behind the inspector's Run details disclosure. This view only
/// ever receives generation-bound live steps; settled turns keep the compact
/// trace and the authoritative snapshot, so the spine disappears at settlement.
struct LivePlanSpineView: View {
    let plan: [RunEvidenceSnapshot.PlanStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Label("Plan", systemImage: "list.bullet.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(PlanSpinePresentation.progressLabel(plan))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
            ForEach(plan) { step in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: stepSymbol(step))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stepColor(step))
                    Text(step.title)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(step.isCurrent ? .primary : .secondary)
                        .lineLimit(3)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PlanSpinePresentation.stepAccessibilityLabel(step))
            }
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run plan")
        .accessibilityValue(PlanSpinePresentation.progressLabel(plan))
        .accessibilityIdentifier("grok-plan-spine")
    }

    private func stepSymbol(_ step: RunEvidenceSnapshot.PlanStep) -> String {
        if PlanSpinePresentation.isCompleted(step.status) { return "checkmark.circle.fill" }
        return step.isCurrent ? "circle.inset.filled" : "circle"
    }

    private func stepColor(_ step: RunEvidenceSnapshot.PlanStep) -> Color {
        if PlanSpinePresentation.isCompleted(step.status) { return .secondary }
        return step.isCurrent ? .accentColor : Color(nsColor: .tertiaryLabelColor)
    }
}
