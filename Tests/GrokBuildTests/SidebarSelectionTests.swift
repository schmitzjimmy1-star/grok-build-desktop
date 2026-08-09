import XCTest
@testable import GrokBuild

final class SidebarSelectionTests: XCTestCase {
    func testRailActionsNeverClaimPersistentSelection() {
        for action in SidebarRailAction.allCases {
            XCTAssertFalse(
                SidebarSelectionSemantics.railActionIsSelected(action),
                "\(action) is an action or transient destination, not persistent route state"
            )
        }
    }

    func testConversationRouteSelectsOnlyTheMatchingWorkspaceAndSession() {
        let selectedWorkspaceID = UUID()
        let otherWorkspaceID = UUID()
        let selectedSessionID = UUID()
        let otherSessionID = UUID()

        XCTAssertTrue(SidebarSelectionSemantics.workspaceIsSelected(
            selectedWorkspaceID,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedSessionID: nil,
            isConversationRouteActive: true
        ))
        XCTAssertFalse(SidebarSelectionSemantics.workspaceIsSelected(
            otherWorkspaceID,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedSessionID: nil,
            isConversationRouteActive: true
        ))
        XCTAssertTrue(SidebarSelectionSemantics.sessionIsSelected(
            selectedSessionID,
            selectedSessionID: selectedSessionID,
            isConversationRouteActive: true
        ))
        XCTAssertFalse(SidebarSelectionSemantics.sessionIsSelected(
            otherSessionID,
            selectedSessionID: selectedSessionID,
            isConversationRouteActive: true
        ))
    }

    func testSelectedSessionSupersedesItsParentWorkspace() {
        let workspaceID = UUID()
        let sessionID = UUID()

        XCTAssertFalse(SidebarSelectionSemantics.workspaceIsSelected(
            workspaceID,
            selectedWorkspaceID: workspaceID,
            selectedSessionID: sessionID,
            isConversationRouteActive: true
        ))
        XCTAssertTrue(SidebarSelectionSemantics.sessionIsSelected(
            sessionID,
            selectedSessionID: sessionID,
            isConversationRouteActive: true
        ))
        XCTAssertEqual(
            SidebarSelectionSemantics.persistentSelection(
                selectedWorkspaceID: workspaceID,
                selectedSessionID: sessionID,
                isConversationRouteActive: true
            ),
            .session(sessionID)
        )
    }

    func testSettingsRouteSuppressesConversationSelectionWithoutChangingIdentity() {
        let workspaceID = UUID()
        let sessionID = UUID()

        XCTAssertFalse(SidebarSelectionSemantics.workspaceIsSelected(
            workspaceID,
            selectedWorkspaceID: workspaceID,
            selectedSessionID: sessionID,
            isConversationRouteActive: false
        ))
        XCTAssertFalse(SidebarSelectionSemantics.sessionIsSelected(
            sessionID,
            selectedSessionID: sessionID,
            isConversationRouteActive: false
        ))
        XCTAssertNil(SidebarSelectionSemantics.persistentSelection(
            selectedWorkspaceID: workspaceID,
            selectedSessionID: sessionID,
            isConversationRouteActive: false
        ))

        XCTAssertTrue(SidebarSelectionSemantics.workspaceIsSelected(
            workspaceID,
            selectedWorkspaceID: workspaceID,
            selectedSessionID: nil,
            isConversationRouteActive: true
        ))
        XCTAssertTrue(SidebarSelectionSemantics.sessionIsSelected(
            sessionID,
            selectedSessionID: sessionID,
            isConversationRouteActive: true
        ))
    }

    func testNilSelectionCannotBeInventedByFocusOrHover() {
        let workspaceID = UUID()
        let sessionID = UUID()

        XCTAssertFalse(SidebarSelectionSemantics.workspaceIsSelected(
            workspaceID,
            selectedWorkspaceID: nil,
            selectedSessionID: nil,
            isConversationRouteActive: true
        ))
        XCTAssertFalse(SidebarSelectionSemantics.sessionIsSelected(
            sessionID,
            selectedSessionID: nil,
            isConversationRouteActive: true
        ))
    }
}
