import Foundation
import XCTest
@testable import GrokBuild

/// Agentic Cockpit Campaign — Phase 1 (Long-Horizon Task Retention).
///
/// Complements `SessionRuntimeRetentionTests` by pinning the eviction *ordering*
/// and protection *priority* rules that keep long-horizon work (`/loop`, background
/// shells, monitors, live subagents, and scheduled leases) alive when the user
/// opens more tabs than the ordinary four-process window allows. The focus here is
/// the newly added `.activeBackgroundTask` protection reason and its interaction
/// with the existing `.busy`, `.starting`, and `.activeSchedule` reasons.
final class SessionRetentionPolicyTests: XCTestCase {

    // MARK: - Background-task protection priority

    func testActiveBackgroundTaskIsProtectedBeyondSoftCapEvenWhenIdle() {
        let recent = (0..<4).map { _ in UUID() }
        let backgroundID = UUID()
        let candidates = recent.enumerated().map { index, id in
            candidate(id: id, recency: UInt64(index + 1))
        } + [candidate(id: backgroundID, state: .ready, recency: 0, backgroundTasks: true)]

        let decision = SessionRuntimeRetentionPolicy.decision(candidates: candidates, normalCap: 4)

        XCTAssertEqual(decision.retainedSessionIDs, Set(recent + [backgroundID]))
        XCTAssertTrue(decision.evictionCandidateIDs.isEmpty)
        XCTAssertEqual(decision.softCapExcess, 1)
        XCTAssertEqual(
            decision.protectionReasonsBySessionID[backgroundID],
            [.activeBackgroundTask],
            "an idle-connection session with live background work must be protected like a busy turn"
        )
    }

    func testActiveBackgroundTaskDoesNotConsumeOrdinaryMRUSlot() {
        let backgroundID = UUID()
        let ordinary = (0..<4).map { _ in UUID() }
        // The background session is the most-recently activated, yet it must not
        // steal one of the four ordinary slots away from the idle sessions.
        let candidates = [candidate(id: backgroundID, state: .idle, recency: 99, backgroundTasks: true)]
            + ordinary.enumerated().map { index, id in candidate(id: id, recency: UInt64(index + 1)) }

        let decision = SessionRuntimeRetentionPolicy.decision(candidates: candidates, normalCap: 4)

        XCTAssertEqual(decision.retainedSessionIDs, Set([backgroundID] + ordinary))
        XCTAssertEqual(decision.retainedLiveCount, 5)
        XCTAssertEqual(decision.softCapExcess, 1)
        XCTAssertTrue(decision.evictionCandidateIDs.isEmpty)
    }

    // MARK: - Eviction ordering

    func testTrulyIdleUnpinnedSessionIsEvictedBeforeProtectedWork() {
        let backgroundID = UUID()
        // Five ordinary idle sessions compete for four ordinary slots while one
        // background-protected session (lowest recency) sits outside that window.
        let ordinary = (0..<5).map { _ in UUID() }
        let candidates = [candidate(id: backgroundID, state: .ready, recency: 0, backgroundTasks: true)]
            + ordinary.enumerated().map { index, id in
                // recency 5 (most recent) down to 1 (least recent) in list order.
                candidate(id: id, recency: UInt64(5 - index))
            }

        let decision = SessionRuntimeRetentionPolicy.decision(candidates: candidates, normalCap: 4)

        XCTAssertEqual(
            decision.evictionCandidateIDs, [ordinary[4]],
            "only the least-recent ordinary idle session is evicted; protected work is untouched"
        )
        XCTAssertTrue(decision.retainedSessionIDs.contains(backgroundID))
        XCTAssertFalse(decision.retainedSessionIDs.contains(ordinary[4]))
        // Four ordinary sessions fill the cap; the protected background session is
        // retained on top of them, so exactly one protected runtime exceeds the cap.
        XCTAssertEqual(decision.retainedLiveCount, 5)
        XCTAssertEqual(decision.softCapExcess, 1)
    }

    func testEvictionPrefersMostRecentOrdinarySessions() {
        let ids = (0..<6).map { _ in UUID() }
        // Descending recency by list order: ids[0] most recent, ids[5] least.
        let candidates = ids.enumerated().map { index, id in
            candidate(id: id, recency: UInt64(6 - index))
        }

        let decision = SessionRuntimeRetentionPolicy.decision(candidates: candidates, normalCap: 4)

        XCTAssertEqual(decision.retainedSessionIDs, Set(ids.prefix(4)))
        XCTAssertEqual(
            Set(decision.evictionCandidateIDs), Set(ids.suffix(2)),
            "the two least-recent ordinary sessions are the eviction candidates"
        )
        XCTAssertFalse(decision.exceedsSoftCap)
    }

    func testSelectedIdleSessionOutranksMoreRecentOrdinaryPeers() {
        let selectedID = UUID()
        let ordinary = (0..<4).map { _ in UUID() }
        // The selected session is the least-recently activated, but selection must
        // pin it into the ordinary window ahead of a more-recent unselected peer.
        let candidates = [candidate(id: selectedID, isSelected: true, recency: 0)]
            + ordinary.enumerated().map { index, id in candidate(id: id, recency: UInt64(index + 1)) }

        let decision = SessionRuntimeRetentionPolicy.decision(candidates: candidates, normalCap: 4)

        XCTAssertTrue(decision.retainedSessionIDs.contains(selectedID))
        XCTAssertEqual(decision.evictionCandidateIDs, [ordinary[0]])
    }

    // MARK: - Combined protection reasons

    func testBusyAndBackgroundTaskReasonsAreBothRecorded() {
        let id = UUID()
        let decision = SessionRuntimeRetentionPolicy.decision(
            candidates: [candidate(id: id, state: .busy, recency: 0, backgroundTasks: true)],
            normalCap: 4
        )
        XCTAssertEqual(decision.protectionReasonsBySessionID[id], [.busy, .activeBackgroundTask])
    }

    func testScheduleAndBackgroundTaskReasonsAreBothRecorded() {
        let id = UUID()
        let decision = SessionRuntimeRetentionPolicy.decision(
            candidates: [candidate(id: id, state: .ready, recency: 0, hasSchedule: true, backgroundTasks: true)],
            normalCap: 4
        )
        XCTAssertEqual(decision.protectionReasonsBySessionID[id], [.activeSchedule, .activeBackgroundTask])
    }

    // MARK: - Release + liveness guards

    func testFinishedBackgroundTaskReleasesSessionToOrdinaryEviction() {
        let releasedID = UUID()
        let recent = (0..<4).map { _ in UUID() }
        // Same shape as the protection test, but the background work has ended, so
        // the fifth idle session outside the MRU window is now evictable.
        let candidates = [candidate(id: releasedID, state: .ready, recency: 0, backgroundTasks: false)]
            + recent.enumerated().map { index, id in candidate(id: id, recency: UInt64(index + 1)) }

        let decision = SessionRuntimeRetentionPolicy.decision(candidates: candidates, normalCap: 4)

        XCTAssertEqual(decision.evictionCandidateIDs, [releasedID])
        XCTAssertNil(decision.protectionReasonsBySessionID[releasedID])
        XCTAssertFalse(decision.exceedsSoftCap)
    }

    func testDeadRuntimeIsNeverProtectedByBackgroundFlag() {
        let deadID = UUID()
        let decision = SessionRuntimeRetentionPolicy.decision(
            candidates: [
                candidate(id: deadID, state: .idle, hasLiveProcess: false, recency: 9, backgroundTasks: true),
            ],
            normalCap: 4
        )
        XCTAssertFalse(decision.retainedSessionIDs.contains(deadID))
        XCTAssertTrue(decision.evictionCandidateIDs.isEmpty)
        XCTAssertNil(decision.protectionReasonsBySessionID[deadID])
    }

    // MARK: - Reason vocabulary

    func testProtectionReasonDisplayNames() {
        XCTAssertEqual(SessionRuntimeProtectionReason.starting.displayName, "Agent starting")
        XCTAssertEqual(SessionRuntimeProtectionReason.busy.displayName, "Active turn")
        XCTAssertEqual(SessionRuntimeProtectionReason.activeBackgroundTask.displayName, "Background work")
        XCTAssertEqual(SessionRuntimeProtectionReason.activeSchedule.displayName, "Active schedule")
    }

    // MARK: - Helper

    private func candidate(
        id: UUID,
        state: GrokProcessState = .ready,
        hasLiveProcess: Bool = true,
        isSelected: Bool = false,
        recency: UInt64,
        hasSchedule: Bool = false,
        backgroundTasks: Bool = false
    ) -> SessionRuntimeRetentionCandidate {
        SessionRuntimeRetentionCandidate(
            id: id,
            connectionState: state,
            hasLiveProcess: hasLiveProcess,
            isSelected: isSelected,
            lastActivationOrdinal: recency,
            hasAuthoritativeActiveSchedule: hasSchedule,
            hasActiveBackgroundTasks: backgroundTasks
        )
    }
}
