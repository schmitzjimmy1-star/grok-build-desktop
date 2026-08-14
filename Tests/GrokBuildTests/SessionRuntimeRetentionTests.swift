import Foundation
import XCTest
@testable import GrokBuild

final class SessionRuntimeRetentionTests: XCTestCase {
    func testFourRecentOrdinarySessionsPlusPinnedScheduleRetainsFiveAndWarns() {
        let ids = (0..<5).map { _ in UUID() }
        let candidates = ids.enumerated().map { index, id in
            candidate(
                id: id,
                recency: UInt64(index),
                hasSchedule: index == 0
            )
        }

        let decision = SessionRuntimeRetentionPolicy.decision(
            candidates: candidates,
            normalCap: 4
        )

        XCTAssertEqual(decision.retainedSessionIDs, Set(ids))
        XCTAssertTrue(decision.evictionCandidateIDs.isEmpty)
        XCTAssertEqual(decision.softCapExcess, 1)
        XCTAssertEqual(decision.protectionReasonsBySessionID[ids[0]], [.activeSchedule])
    }

    func testFifthOrdinaryIdleSessionOutsideMRUIsEvicted() {
        let ids = (0..<5).map { _ in UUID() }
        let candidates = ids.enumerated().map { index, id in
            candidate(id: id, recency: UInt64(5 - index))
        }

        let decision = SessionRuntimeRetentionPolicy.decision(
            candidates: candidates,
            normalCap: 4
        )

        XCTAssertEqual(decision.retainedSessionIDs, Set(ids.prefix(4)))
        XCTAssertEqual(decision.evictionCandidateIDs, [ids[4]])
        XCTAssertFalse(decision.exceedsSoftCap)
    }

    func testBusyAndStartingSessionsRemainProtectedBeyondSoftCap() {
        let ids = (0..<6).map { _ in UUID() }
        var candidates = ids.prefix(4).enumerated().map { index, id in
            candidate(id: id, recency: UInt64(index + 1))
        }
        candidates.append(candidate(id: ids[4], state: .busy, recency: 0))
        candidates.append(candidate(id: ids[5], state: .starting, recency: 0))

        let decision = SessionRuntimeRetentionPolicy.decision(
            candidates: candidates,
            normalCap: 4
        )

        XCTAssertEqual(decision.retainedLiveCount, 6)
        XCTAssertEqual(decision.softCapExcess, 2)
        XCTAssertEqual(decision.protectionReasonsBySessionID[ids[4]], [.busy])
        XCTAssertEqual(decision.protectionReasonsBySessionID[ids[5]], [.starting])
    }

    func testCancellationReleasesOldestSessionBackToOrdinaryEviction() {
        let pinnedID = UUID()
        let recent = (0..<4).map { _ in UUID() }
        let candidates = [candidate(id: pinnedID, recency: 0, hasSchedule: false)]
            + recent.enumerated().map { index, id in candidate(id: id, recency: UInt64(index + 1)) }

        let decision = SessionRuntimeRetentionPolicy.decision(
            candidates: candidates,
            normalCap: 4
        )

        XCTAssertEqual(decision.evictionCandidateIDs, [pinnedID])
        XCTAssertNil(decision.protectionReasonsBySessionID[pinnedID])
        XCTAssertFalse(decision.exceedsSoftCap)
    }

    func testCloseQuitAndProcessFailureCannotRetainDeadRuntime() {
        let closedID = UUID()
        let quitID = UUID()
        let failedID = UUID()
        let decision = SessionRuntimeRetentionPolicy.decision(
            candidates: [
                // Closed sessions are absent from the candidate list; this idle row
                // stands in for a quit-cleared shell with no active generation.
                candidate(id: quitID, state: .idle, hasLiveProcess: false, recency: 2, hasSchedule: true),
                candidate(id: failedID, state: .failed("gone"), hasLiveProcess: false, recency: 1, hasSchedule: true),
            ],
            normalCap: 4
        )

        XCTAssertFalse(decision.retainedSessionIDs.contains(closedID))
        XCTAssertFalse(decision.retainedSessionIDs.contains(quitID))
        XCTAssertFalse(decision.retainedSessionIDs.contains(failedID))
        XCTAssertTrue(decision.evictionCandidateIDs.isEmpty)
    }

    func testSelectedPinnedScheduleDoesNotConsumeOneOfFourOrdinarySlots() {
        let pinnedID = UUID()
        let ordinary = (0..<4).map { _ in UUID() }
        let decision = SessionRuntimeRetentionPolicy.decision(
            candidates: [candidate(id: pinnedID, isSelected: true, recency: 99, hasSchedule: true)]
                + ordinary.enumerated().map { index, id in candidate(id: id, recency: UInt64(index + 1)) },
            normalCap: 4
        )

        XCTAssertEqual(decision.retainedSessionIDs, Set([pinnedID] + ordinary))
        XCTAssertEqual(decision.retainedLiveCount, 5)
        XCTAssertEqual(decision.softCapExcess, 1)
        XCTAssertTrue(decision.evictionCandidateIDs.isEmpty)
    }

    func testRuntimeLeaseRequiresExactLiveGenerationAndAuthoritativeInventory() {
        let tabID = UUID()
        let observedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let settledAt = observedAt.addingTimeInterval(-60)
        let nextAt = observedAt.addingTimeInterval(60)
        let tasks = [ScheduledTask(
            id: "schedule-1",
            prompt: "check",
            intervalHuman: "every minute",
            nextFireAt: nextAt,
            recurring: true
        )]
        let receipt = ScheduledTaskInventoryReceipt(
            localTabID: tabID,
            backendSessionID: "backend-1",
            processGeneration: 7,
            observedAt: observedAt,
            taskCount: 1
        )

        let lease = SessionRuntimeLease.authoritative(
            tasks: tasks,
            receipt: receipt,
            localTabID: tabID,
            backendSessionID: "backend-1",
            processGeneration: 7,
            connectionState: .ready,
            lastSettledCheckpointAt: settledAt
        )

        XCTAssertEqual(lease?.activeScheduleCount, 1)
        XCTAssertEqual(lease?.nextScheduledCheckpointAt, nextAt)
        XCTAssertEqual(lease?.lastSettledCheckpointAt, settledAt)
        XCTAssertNil(SessionRuntimeLease.authoritative(
            tasks: tasks,
            receipt: receipt,
            localTabID: tabID,
            backendSessionID: "backend-1",
            processGeneration: 8,
            connectionState: .ready,
            lastSettledCheckpointAt: settledAt
        ), "a cached receipt from the prior process generation must not pin restored runtime")
        XCTAssertNil(SessionRuntimeLease.authoritative(
            tasks: tasks,
            receipt: receipt,
            localTabID: tabID,
            backendSessionID: "backend-1",
            processGeneration: 7,
            connectionState: .idle,
            lastSettledCheckpointAt: settledAt
        ), "an exited process releases the lease even when stale task metadata remains")
    }

    func testSchedulerTrackerDatesOnlyAuthoritativeRawOutput() {
        var tracker = ScheduledTaskTracker()
        let startedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let settledAt = startedAt.addingTimeInterval(1)
        tracker.apply(update: [
            "toolCallId": "create-1",
            "rawInput": ["interval": "60s", "prompt": "check"],
        ], observedAt: startedAt)
        XCTAssertNil(tracker.lastAuthoritativeObservationAt)

        tracker.apply(update: [
            "toolCallId": "create-1",
            "rawOutput": ["type": "SchedulerCreate", "id": "schedule-1"],
        ], observedAt: settledAt)
        XCTAssertEqual(tracker.lastAuthoritativeObservationAt, settledAt)
        XCTAssertEqual(tracker.tasks.map(\.id), ["schedule-1"])

        tracker.apply(update: [
            "toolCallId": "future-1",
            "rawOutput": ["type": "SchedulerFutureVariant"],
        ], observedAt: settledAt.addingTimeInterval(1))
        XCTAssertEqual(
            tracker.lastAuthoritativeObservationAt,
            settledAt,
            "an unrecognized scheduler-shaped payload must not refresh a live lease"
        )

        tracker.reset()
        XCTAssertTrue(tracker.tasks.isEmpty)
        XCTAssertNil(tracker.lastAuthoritativeObservationAt)
    }

    private func candidate(
        id: UUID,
        state: GrokProcessState = .ready,
        hasLiveProcess: Bool = true,
        isSelected: Bool = false,
        recency: UInt64,
        hasSchedule: Bool = false
    ) -> SessionRuntimeRetentionCandidate {
        SessionRuntimeRetentionCandidate(
            id: id,
            connectionState: state,
            hasLiveProcess: hasLiveProcess,
            isSelected: isSelected,
            lastActivationOrdinal: recency,
            hasAuthoritativeActiveSchedule: hasSchedule
        )
    }
}
