import SwiftUI

/// Codex parity Slice 3 — the compact inline changed-files card rendered in the
/// transcript after a settled assistant turn, mirroring the photographed Codex
/// "Edited N files" completion card.
///
/// The card presents `ChangedFilesSummaryProjection` facts only: turn-attributed
/// edits lead, repository-wide changes are disclosed as such, absent diff counts
/// stay absent, and the Review action opens the real Git review pane for the
/// current project (its Review opens the pane in the Last turn scope, shipped 2026-08-08).
/// There is deliberately no Undo control: GrokBuild has no safe, real undo
/// operation for agent edits today, and a decorative one is forbidden.
struct ChangedFilesSummaryCard: View {
    let summary: ChangedFilesSummaryProjection.Summary
    var onOpenReview: () -> Void = {}

    @State private var isExpanded = false

    private var visibleRows: [ChangedFilesSummaryProjection.FileRow] {
        isExpanded
            ? summary.rows
            : Array(summary.rows.prefix(ChangedFilesSummaryProjection.visibleRowLimit))
    }

    private var hiddenRowCount: Int {
        max(0, summary.rows.count - ChangedFilesSummaryProjection.visibleRowLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(summary.headline)
                    .font(AppTheme.Typography.captionStrong)
                if let additions = summary.additionsTotal, let deletions = summary.deletionsTotal {
                    HStack(spacing: 4) {
                        Text("+\(additions)")
                            .foregroundStyle(.green)
                        Text("−\(deletions)")
                            .foregroundStyle(.red)
                        if !summary.hasCompleteCounts {
                            Text("(counted files)")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(AppTheme.Typography.label)
                }
                Spacer(minLength: 8)
                Button("Review", action: onOpenReview)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open the Git review pane for this project")
                    .accessibilityLabel("Review changed files")
                    .accessibilityIdentifier("grok-changed-files-review")
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(visibleRows) { row in
                    HStack(spacing: 6) {
                        Image(systemName: row.isTurnAttributed ? "pencil" : "doc")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(row.path)
                            .font(AppTheme.Typography.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        if let additions = row.additions, let deletions = row.deletions {
                            Text("+\(additions)")
                                .font(AppTheme.Typography.label)
                                .foregroundStyle(.green)
                            Text("−\(deletions)")
                                .font(AppTheme.Typography.label)
                                .foregroundStyle(.red)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(rowAccessibilityLabel(row))
                }
            }

            if hiddenRowCount > 0 {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded
                         ? "Show fewer files"
                         : "Show \(hiddenRowCount) more \(hiddenRowCount == 1 ? "file" : "files")")
                        .font(AppTheme.Typography.label)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("grok-changed-files-show-more")
            }

            if let note = summary.scopeNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .grokGlassSurface(cornerRadius: AppTheme.Radius.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Changed files summary: \(summary.headline)")
        .accessibilityIdentifier("grok-changed-files-card")
    }

    private func rowAccessibilityLabel(_ row: ChangedFilesSummaryProjection.FileRow) -> String {
        var parts = [row.path]
        parts.append(row.isTurnAttributed ? "edited this turn" : "changed in project")
        if let additions = row.additions, let deletions = row.deletions {
            parts.append("\(additions) additions, \(deletions) deletions")
        }
        return parts.joined(separator: ", ")
    }
}
