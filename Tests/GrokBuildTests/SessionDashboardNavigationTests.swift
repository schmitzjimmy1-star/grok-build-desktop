import Foundation
import XCTest
@testable import GrokBuild

final class SessionDashboardNavigationTests: XCTestCase {
    func testDashboardOrderingUsesGroupThenActivationThenStableID() {
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let entries = [
            entry(id: highID, group: .idle, ordinal: 4),
            entry(id: UUID(), group: .working, ordinal: 1),
            entry(id: lowID, group: .idle, ordinal: 4),
            entry(id: UUID(), group: .needsInput, ordinal: 0),
        ]

        let ordered = SessionDashboardPresentation.ordered(entries)

        XCTAssertEqual(ordered.map(\.group), [.needsInput, .working, .idle, .idle])
        XCTAssertEqual(Array(ordered.suffix(2)).map(\.id), [lowID, highID])
    }

    func testDashboardAccessibilityContractIsStableAndExplicit() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let pending = SessionDashboardEntry(
            id: id,
            title: "Older work",
            workspaceName: "Grok Build",
            group: .needsInput,
            modelName: "Grok 4.5",
            pendingCount: 2,
            lastActivationOrdinal: 7
        )

        XCTAssertEqual(
            SessionDashboardPresentation.accessibilityIdentifier(for: id),
            "grok-session-dashboard-row-12345678-1234-1234-1234-123456789abc"
        )
        XCTAssertEqual(
            SessionDashboardPresentation.accessibilityLabel(for: pending, isSelected: true),
            "Session: Older work, Grok Build, Grok 4.5, Needs input, 2 pending, Selected"
        )
    }

    func testDashboardRowsAndSelectionKeepOneOwnerAndDoNotStartBackend() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let panel = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/Views/SessionDashboardPanel.swift"),
            encoding: .utf8
        )
        let content = try String(
            contentsOf: repositoryRoot.appendingPathComponent("GrokBuild/ContentView.swift"),
            encoding: .utf8
        )
        let selectionStart = try XCTUnwrap(content.range(of: "private func selectSession("))
        let selectionEnd = try XCTUnwrap(
            content.range(of: "private func noteSessionUsed", range: selectionStart.upperBound..<content.endIndex)
        )
        let selection = String(content[selectionStart.lowerBound..<selectionEnd.lowerBound])

        XCTAssertTrue(panel.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(panel.contains(".contentShape(Rectangle())"))
        XCTAssertTrue(panel.contains("grok-session-dashboard-row-"))
        XCTAssertFalse(panel.contains("onSelect(entry.id)\n                                        dismiss()"))
        XCTAssertTrue(content.contains("sessionModal = .none\n                selectSession(sessionID)"),
                      "the presenting ContentView stays the single dismissal owner through the Slice 2 sessionModal route")
        XCTAssertTrue(selection.contains("sessionSelectionGeneration == selectionGeneration"))
        XCTAssertFalse(selection.contains("ensureSessionStarted"))
        XCTAssertFalse(selection.contains("session.store.start"))
    }

    private func entry(
        id: UUID,
        group: SessionDashboardEntry.Group,
        ordinal: UInt64
    ) -> SessionDashboardEntry {
        SessionDashboardEntry(
            id: id,
            title: id.uuidString,
            workspaceName: "Workspace",
            group: group,
            modelName: "Model",
            pendingCount: 0,
            lastActivationOrdinal: ordinal
        )
    }
}
