import Foundation

/// OUTSTANDING O-6 (2026-08-08) — presentation policy for the session-migration
/// failure banner. It formats the persisted failure receipt and names the
/// sessions that loaded read-only; it never decides persistence policy. Writes
/// stay disabled while the failure stands, whether the banner is dismissed or
/// not, and the failure resurfaces on the next launch by design.
enum SessionMigrationBannerPresentation {
    static func reason(_ failure: SessionLayoutFailureCode) -> String {
        switch failure {
        case .incompleteV3Commit:
            return "an interrupted save left the session ledger incomplete"
        case .v3DecodeFailed:
            return "the saved session ledger could not be decoded"
        case .v3MarkerMismatch:
            return "the session ledger failed its integrity check"
        case .integrityKeyUnavailable:
            return "the session ledger's integrity key is unavailable"
        case .v2DecodeFailed:
            return "the legacy session index could not be decoded"
        case .v3WriteVerificationFailed:
            return "the last session ledger write failed verification"
        }
    }

    static func message(readOnlyCount: Int) -> String {
        guard readOnlyCount > 0 else {
            return "Saved session migration failed. Session saving is paused."
        }
        return "Saved session migration failed — \(readOnlyCount) "
            + (readOnlyCount == 1 ? "session is" : "sessions are")
            + " open read-only."
    }

    /// The full receipt behind the Details control: the failure reason and
    /// code, the sessions affected this launch, and what stays safe.
    static func detail(failure: SessionLayoutFailureCode, sessionTitles: [String]) -> String {
        var lines = [
            "Session saving is paused because \(reason(failure)) (code: \(failure.rawValue))."
        ]
        if sessionTitles.isEmpty {
            lines.append("No saved sessions were loaded read-only.")
        } else {
            lines.append("Open read-only this launch:")
            lines.append(contentsOf: sessionTitles.map { "• \($0)" })
        }
        lines.append(
            "Transcripts already on disk are untouched; new work in these sessions is not saved while the failure stands. Relaunching retries the migration."
        )
        return lines.joined(separator: "\n")
    }

    static func readOnlySessionTitles(records: [SavedSessionRecord]) -> [String] {
        records.map { record in
            let trimmed = record.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Untitled session" : trimmed
        }
    }
}
