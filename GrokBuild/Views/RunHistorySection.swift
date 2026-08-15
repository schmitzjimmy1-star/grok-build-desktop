import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RedactedRunHistoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(record: RunHistory.Record) {
        data = (try? RunHistory.jsonData(for: record)) ?? Data("{}".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct RunHistorySection: View {
    struct HistoryRow: Identifiable {
        let sessionID: UUID
        let record: RunHistory.Record
        var id: String { "\(sessionID.uuidString)|\(record.id)" }
    }

    let entries: [SessionDashboardEntry]
    let runHistoryBySessionID: [UUID: [RunHistory.Record]]
    @Binding var exportRecord: RunHistory.Record?

    private var histories: [HistoryRow] {
        runHistoryBySessionID
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .flatMap { pair in
                pair.value.map { HistoryRow(sessionID: pair.key, record: $0) }
            }
    }

    var body: some View {
        if !histories.isEmpty {
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Label("Run history", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Saved checkpoints are historical receipts, not current Live state. Exports exclude transcript prose, prompts, responses, raw tool payloads, paths, and credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(histories) { history in
                    let sessionTitle = entries.first(where: { $0.id == history.sessionID })?.title ?? "Saved session"
                    let record = history.record
                    VStack(alignment: .leading, spacing: 5) {
                        Text(sessionTitle).font(.subheadline.weight(.semibold))
                        Text(RunHistory.Presentation.checkpointSummary(for: record))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(RunHistory.Presentation.routeLine(for: record))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        if let latest = record.latest {
                            Text(RunHistory.Presentation.toolsLine(for: latest))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Text(record.lastAuthoritativeContinuationPoint)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                        HStack {
                            Button("Copy redacted Markdown receipt") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(RunHistory.markdown(for: record), forType: .string)
                            }
                            .accessibilityIdentifier("grok-run-history-copy-markdown")
                            Button("Export redacted JSON") { exportRecord = record }
                                .accessibilityIdentifier("grok-run-history-export-json")
                        }
                        .font(.caption)
                    }
                    .padding(10)
                    .background(AppTheme.Palette.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
                    .accessibilityIdentifier("grok-run-history-\(RunHistory.safeText(record.id))")
                }
            }
            .accessibilityIdentifier("grok-run-history")
        }
    }
}
