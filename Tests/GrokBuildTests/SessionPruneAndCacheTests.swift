import XCTest
@testable import GrokBuild

/// Launch-restore pruning and the restore-path caches (config contents, workspace
/// layout). These exist because a 130-tab restore was spending 60-80 seconds
/// re-reading unchanged files and rebuilding empty warm-started tabs.
final class SessionPruneAndCacheTests: XCTestCase {
    private func record(
        id: UUID = UUID(),
        workspaceID: UUID,
        backendBinding: SessionBackendBinding? = nil,
        lastAccessed: Date,
        pendingRecoveryIntent: SessionPendingRecoveryIntent? = nil
    ) -> SavedSessionRecord {
        SavedSessionRecord(
            id: id,
            workspaceID: workspaceID,
            backendBinding: backendBinding,
            title: nil,
            modelIntent: .inheritProjectDefault,
            agentIntent: .inheritGlobalDefault,
            lastAccessed: lastAccessed,
            lastActivationOrdinal: 1,
            pendingRecoveryIntent: pendingRecoveryIntent
        )
    }

    func testPruneDropsOnlyStaleEmptyUnselectedRecords() {
        let workspaceID = UUID()
        let now = Date()
        let stale = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let binding = SessionBackendBinding(
            backendID: "backend-1",
            origin: .runtime,
            predecessorBackendID: nil,
            verification: .unverified
        )

        let withTranscript = record(workspaceID: workspaceID, lastAccessed: stale)
        let selectedEmpty = record(workspaceID: workspaceID, lastAccessed: stale)
        let recoveryEmpty = record(
            workspaceID: workspaceID,
            lastAccessed: stale,
            pendingRecoveryIntent: SessionPendingRecoveryIntent(
                action: .continueAsNew,
                predecessorBackendID: "backend-0",
                chosenAt: stale,
                localMessageCountAtChoice: 3,
                transcriptTag: nil
            )
        )
        let recentEmpty = record(workspaceID: workspaceID, lastAccessed: now.addingTimeInterval(-60))
        // Warm-started New chats acquire a backend binding without ever holding a
        // message; the binding alone must not protect them.
        let staleEmptyWithBinding = record(
            workspaceID: workspaceID,
            backendBinding: binding,
            lastAccessed: stale
        )
        let staleEmpty = record(workspaceID: workspaceID, lastAccessed: stale)

        let decision = SessionRestorePolicy.pruneDecision(
            records: [withTranscript, selectedEmpty, recoveryEmpty, recentEmpty, staleEmptyWithBinding, staleEmpty],
            restorableMessageCounts: [withTranscript.id: 12],
            selectedSessionIDs: [selectedEmpty.id],
            now: now
        )

        XCTAssertEqual(
            decision.keptRecords.map(\.id),
            [withTranscript.id, selectedEmpty.id, recoveryEmpty.id, recentEmpty.id]
        )
        XCTAssertEqual(
            decision.prunedRecordIDs.sorted { $0.uuidString < $1.uuidString },
            [staleEmptyWithBinding.id, staleEmpty.id].sorted { $0.uuidString < $1.uuidString }
        )
    }

    func testPruneKeepsEverythingWhenAllRecordsProtected() {
        let workspaceID = UUID()
        let now = Date()
        let records = [
            record(workspaceID: workspaceID, lastAccessed: now),
            record(workspaceID: workspaceID, lastAccessed: now.addingTimeInterval(-60))
        ]
        let decision = SessionRestorePolicy.pruneDecision(
            records: records,
            restorableMessageCounts: [:],
            selectedSessionIDs: [],
            now: now
        )
        XCTAssertEqual(decision.keptRecords.map(\.id), records.map(\.id))
        XCTAssertTrue(decision.prunedRecordIDs.isEmpty)
    }

    func testConfigRepositoryReadCacheHonorsExternalRewrites() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grokbuild-config-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.toml")
        let repository = GrokConfigRepository(configURL: configURL)

        try "[models]\n".write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(repository.read(), "[models]\n")
        // Cached read returns identical contents without observable change.
        XCTAssertEqual(repository.read(), "[models]\n")

        // An external writer (grok TUI/CLI) must invalidate the cache: the stamp
        // check covers both size and modification time.
        let external = "[models]\n\n[model.kimi-k3]\nmodel = \"kimi-k3\"\n"
        try external.write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(repository.read(), external)

        // Repository-owned updates refresh the cache in the same call.
        try repository.update { contents in contents + "# trailing\n" }
        XCTAssertEqual(repository.read(), external + "# trailing\n")
    }

    func testConfigRepositoryRefusesConcurrentExternalReplacement() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grokbuild-config-conflict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("config.toml")
        let repository = GrokConfigRepository(configURL: configURL)
        let original = "[models]\ndefault = \"old\"\n"
        let external = "[models]\ndefault = \"external-wins\"\n"
        try original.write(to: configURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try repository.update { contents in
            XCTAssertEqual(contents, original)
            try external.write(to: configURL, atomically: true, encoding: .utf8)
            return "[models]\ndefault = \"stale-grokbuild-write\"\n"
        }) { error in
            guard case GrokConfigRepository.UpdateError.changedDuringUpdate = error else {
                return XCTFail("Unexpected conflict error: \(error)")
            }
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), external)
    }

    func testWorkspaceLayoutCacheTracksSaves() {
        let saved = SessionLayoutStore.loadWorkspaceLayout()
        defer {
            SessionLayoutStore.saveWorkspaceLayout(saved)
            SessionLayoutStore.invalidateWorkspaceLayoutCacheForTesting()
        }

        let first = WorkspaceLayoutSnapshot(pinnedWorkspaceIDs: [UUID()], workspaceOrder: [UUID()])
        SessionLayoutStore.saveWorkspaceLayout(first)
        XCTAssertEqual(SessionLayoutStore.loadWorkspaceLayout().pinnedWorkspaceIDs, first.pinnedWorkspaceIDs)

        let second = WorkspaceLayoutSnapshot(pinnedWorkspaceIDs: [], workspaceOrder: first.workspaceOrder)
        SessionLayoutStore.saveWorkspaceLayout(second)
        XCTAssertEqual(SessionLayoutStore.loadWorkspaceLayout().pinnedWorkspaceIDs, [])
        XCTAssertEqual(SessionLayoutStore.loadWorkspaceLayout().workspaceOrder, first.workspaceOrder)
    }
}
