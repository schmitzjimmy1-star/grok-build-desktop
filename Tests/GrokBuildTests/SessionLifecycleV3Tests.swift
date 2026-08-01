import Foundation
import XCTest
@testable import GrokBuild

final class SessionLifecycleV3Tests: XCTestCase {
    private struct StaticKeyProvider: SessionLifecycleIntegrityKeyProviding {
        let key: Data
        func existingKey() -> Data? { key }
        func existingOrCreateKey() -> Data { key }
    }

    private struct HMACFixture: Decodable {
        struct Vector: Decodable {
            let role: String
            let ordinal: Int
            let content: String
            let normalized: String
            let tag: String
        }
        let schemaVersion: Int
        let keyHex: String
        let vectors: [Vector]
    }

    private let provider = StaticKeyProvider(key: Data(0..<32))

    func testV2MigrationCommitsV3WithoutMutatingLegacyBytes() throws {
        let defaults = isolatedDefaults()
        let workspaceID = UUID()
        let inheritedID = UUID()
        let ambiguousID = UUID()
        let legacy = LegacySessionLayoutSnapshotV2(
            records: [
                LegacySavedSessionRecordV2(
                    id: inheritedID,
                    workspaceID: workspaceID,
                    grokSessionID: nil,
                    title: "Inherited",
                    model: nil,
                    agent: nil,
                    lastAccessed: Date(timeIntervalSince1970: 100)
                ),
                LegacySavedSessionRecordV2(
                    id: ambiguousID,
                    workspaceID: workspaceID,
                    grokSessionID: "synthetic-backend",
                    title: "Ambiguous",
                    model: "grok-4.5",
                    agent: "explore",
                    lastAccessed: Date(timeIntervalSince1970: 200)
                ),
            ],
            sessionOrderByWorkspace: [workspaceID: [inheritedID, ambiguousID]],
            selectedSessionID: ambiguousID,
            selectedWorkspaceID: workspaceID
        )
        let legacyData = try JSONEncoder().encode(legacy)
        defaults.set(legacyData, forKey: SessionLayoutStore.legacySessionKey)

        let first = SessionLayoutStore.loadSessionsResult(defaults: defaults, keyProvider: provider)
        XCTAssertEqual(first.authority, .migratedV2)
        XCTAssertNil(first.failure)
        XCTAssertEqual(defaults.data(forKey: SessionLayoutStore.legacySessionKey), legacyData)
        XCTAssertNotNil(defaults.data(forKey: SessionLayoutStore.sessionV3CandidateKey))
        XCTAssertNotNil(defaults.data(forKey: SessionLayoutStore.sessionV3CommitMarkerKey))
        XCTAssertEqual(first.snapshot.activationCounter, 2)
        XCTAssertEqual(first.snapshot.records.first(where: { $0.id == inheritedID })?.modelIntent, .inheritProjectDefault)
        XCTAssertEqual(first.snapshot.records.first(where: { $0.id == ambiguousID })?.modelIntent, .legacyUnknown("grok-4.5"))
        XCTAssertEqual(first.snapshot.records.first(where: { $0.id == ambiguousID })?.agentIntent, .explicit("explore"))
        XCTAssertEqual(first.snapshot.records.first(where: { $0.id == ambiguousID })?.backendBinding?.verification, .unverified)

        let second = SessionLayoutStore.loadSessionsResult(defaults: defaults, keyProvider: provider)
        XCTAssertEqual(second.authority, .v3Committed)
        XCTAssertEqual(second.snapshot, first.snapshot)
        XCTAssertEqual(defaults.data(forKey: SessionLayoutStore.legacySessionKey), legacyData)
    }

    func testIncompleteOrTamperedV3FallsBackToUntouchedV2() throws {
        let defaults = isolatedDefaults()
        let id = UUID()
        let workspaceID = UUID()
        let legacy = LegacySessionLayoutSnapshotV2(
            records: [LegacySavedSessionRecordV2(
                id: id,
                workspaceID: workspaceID,
                grokSessionID: nil,
                title: "Legacy",
                model: nil,
                agent: nil,
                lastAccessed: Date(timeIntervalSince1970: 1)
            )],
            sessionOrderByWorkspace: [workspaceID: [id]],
            selectedSessionID: id,
            selectedWorkspaceID: workspaceID
        )
        let legacyData = try JSONEncoder().encode(legacy)
        defaults.set(legacyData, forKey: SessionLayoutStore.legacySessionKey)
        _ = SessionLayoutStore.loadSessionsResult(defaults: defaults, keyProvider: provider)

        defaults.removeObject(forKey: SessionLayoutStore.sessionV3CommitMarkerKey)
        var fallback = SessionLayoutStore.loadSessionsResult(defaults: defaults, keyProvider: provider)
        XCTAssertEqual(fallback.authority, .legacyV2Fallback)
        XCTAssertEqual(fallback.failure, .incompleteV3Commit)
        XCTAssertEqual(fallback.snapshot.records.map(\.id), [id])
        XCTAssertEqual(defaults.data(forKey: SessionLayoutStore.legacySessionKey), legacyData)

        let validSave = SessionLayoutStore.saveSessions(fallback.snapshot, defaults: defaults, keyProvider: provider)
        XCTAssertTrue(validSave.committed)
        var candidate = try XCTUnwrap(defaults.data(forKey: SessionLayoutStore.sessionV3CandidateKey))
        candidate[0] ^= 0x01
        defaults.set(candidate, forKey: SessionLayoutStore.sessionV3CandidateKey)
        fallback = SessionLayoutStore.loadSessionsResult(defaults: defaults, keyProvider: provider)
        XCTAssertEqual(fallback.authority, .legacyV2Fallback)
        XCTAssertEqual(fallback.failure, .v3MarkerMismatch)
        XCTAssertEqual(defaults.data(forKey: SessionLayoutStore.legacySessionKey), legacyData)
    }

    func testIntentRoundTripDoesNotFreezeInheritance() throws {
        let workspaceID = UUID()
        let modelIdentity = ModelRequestIdentity(
            localTabID: UUID(), backendSessionID: "backend",
            processGeneration: 4, requestID: UUID()
        )
        let records = [
            SavedSessionRecord(
                id: UUID(), workspaceID: workspaceID, backendBinding: nil, title: nil,
                modelIntent: .inheritProjectDefault, agentIntent: .inheritGlobalDefault,
                lastAccessed: .distantPast, lastActivationOrdinal: 1
            ),
            SavedSessionRecord(
                id: UUID(), workspaceID: workspaceID, backendBinding: nil, title: nil,
                modelIntent: .explicit("gpt-5.6-terra"),
                modelExecutionState: ModelExecutionState(
                    status: .confirmed,
                    requestedModelID: "gpt-5.6-terra",
                    effectiveModelID: "gpt-5.6-terra",
                    identity: modelIdentity,
                    failure: nil,
                    updatedAt: Date(timeIntervalSince1970: 100)
                ),
                agentIntent: .explicit("researcher"),
                lastAccessed: .distantPast, lastActivationOrdinal: 2
            ),
        ]
        var snapshot = SessionLayoutSnapshot(
            records: records,
            sessionOrderByWorkspace: [workspaceID: records.map(\.id)],
            selectedSessionID: records.last?.id,
            selectedWorkspaceID: workspaceID
        )
        for _ in 0..<3 {
            snapshot = try JSONDecoder().decode(
                SessionLayoutSnapshot.self,
                from: JSONEncoder().encode(snapshot)
            )
        }
        XCTAssertEqual(snapshot.records[0].modelIntent, .inheritProjectDefault)
        XCTAssertEqual(snapshot.records[0].agentIntent, .inheritGlobalDefault)
        XCTAssertEqual(snapshot.records[1].modelIntent, .explicit("gpt-5.6-terra"))
        XCTAssertEqual(snapshot.records[1].modelExecutionState.status, .confirmed)
        XCTAssertEqual(snapshot.records[1].modelExecutionState.identity, modelIdentity)
        XCTAssertEqual(snapshot.records[1].agentIntent, .explicit("researcher"))
    }

    func testV3RecordWithoutModelExecutionReceiptDecodesAsUnknown() throws {
        let id = UUID()
        let workspaceID = UUID()
        let json = """
        {
          "id":"\(id.uuidString)",
          "workspaceID":"\(workspaceID.uuidString)",
          "modelIntent":{"kind":"inheritProjectDefault"},
          "agentIntent":{"kind":"inheritGlobalDefault"},
          "lastAccessed":0,
          "lastActivationOrdinal":1,
          "transcriptGeneration":0,
          "transcriptStorageVersion":1
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let record = try decoder.decode(SavedSessionRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.modelExecutionState, .unknown)
    }

    func testRestoreDecisionUsesTrueMRUNotTranscriptLength() {
        let workspaceID = UUID()
        let olderLongTranscript = UUID()
        let newerShortTranscript = UUID()
        let decision = SessionRestorePolicy.restoreDecision(
            input: SessionRestoreInput(
                workspaceID: workspaceID,
                savedSelectedSessionID: nil,
                workspaceWasRepaired: false,
                candidates: [
                    SessionRestoreCandidate(
                        id: olderLongTranscript, workspaceID: workspaceID,
                        lastActivationOrdinal: 9, lastAccessed: Date(timeIntervalSince1970: 900),
                        hasLocalTranscript: true, hasContent: true,
                        hasVerifiedBinding: false, isDiverged: false
                    ),
                    SessionRestoreCandidate(
                        id: newerShortTranscript, workspaceID: workspaceID,
                        lastActivationOrdinal: 10, lastAccessed: Date(timeIntervalSince1970: 100),
                        hasLocalTranscript: true, hasContent: true,
                        hasVerifiedBinding: false, isDiverged: false
                    ),
                ]
            )
        )
        XCTAssertEqual(decision.selectedSessionID, newerShortTranscript)
        XCTAssertEqual(decision.reason, .workspaceMRULocalTranscript)
        XCTAssertTrue(decision.deferBackendStart)
    }

    func testOrdinalTieUsesTimestampThenStableUUIDOrder() {
        let workspaceID = UUID()
        let lowID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let sameDate = Date(timeIntervalSince1970: 10)
        let records = [
            SavedSessionRecord(
                id: highID, workspaceID: workspaceID, lastAccessed: sameDate,
                lastActivationOrdinal: 7
            ),
            SavedSessionRecord(
                id: lowID, workspaceID: workspaceID, lastAccessed: sameDate,
                lastActivationOrdinal: 7
            ),
        ]
        XCTAssertEqual(SessionRestorePolicy.recentSessionOrder(from: records), [lowID, highID])
    }

    func testRapidAToBSelectionPersistsBBeforeQuit() {
        let defaults = isolatedDefaults()
        let workspaceID = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [
                SavedSessionRecord(
                    id: sessionA, workspaceID: workspaceID,
                    lastAccessed: Date(timeIntervalSince1970: 10), lastActivationOrdinal: 10
                ),
                SavedSessionRecord(
                    id: sessionB, workspaceID: workspaceID,
                    lastAccessed: Date(timeIntervalSince1970: 11), lastActivationOrdinal: 11
                ),
            ],
            sessionOrderByWorkspace: [workspaceID: [sessionA, sessionB]],
            selectedSessionID: sessionB,
            selectedWorkspaceID: workspaceID,
            selectedSessionIDByWorkspace: [workspaceID: sessionB],
            activationCounter: 11
        )
        XCTAssertTrue(SessionLayoutStore.saveSessions(
            snapshot, defaults: defaults, keyProvider: provider
        ).committed)
        let relaunched = SessionLayoutStore.loadSessionsResult(defaults: defaults, keyProvider: provider)
        XCTAssertEqual(relaunched.authority, .v3Committed)
        let candidates = relaunched.snapshot.records.map {
            SessionRestoreCandidate(
                id: $0.id, workspaceID: $0.workspaceID,
                lastActivationOrdinal: $0.lastActivationOrdinal, lastAccessed: $0.lastAccessed,
                hasLocalTranscript: true, hasContent: true,
                hasVerifiedBinding: false, isDiverged: false
            )
        }
        let decision = SessionRestorePolicy.restoreDecision(input: SessionRestoreInput(
            workspaceID: workspaceID,
            savedSelectedSessionID: relaunched.snapshot.selectedSessionID,
            workspaceWasRepaired: false,
            candidates: candidates
        ))
        XCTAssertEqual(decision.selectedSessionID, sessionB)
        XCTAssertEqual(SessionRestorePolicy.recentSessionOrder(from: relaunched.snapshot.records).first, sessionB)
    }

    func testNoViableCandidateCreatesNewTabWithoutStartingBackend() {
        let decision = SessionRestorePolicy.restoreDecision(input: SessionRestoreInput(
            workspaceID: UUID(),
            savedSelectedSessionID: nil,
            workspaceWasRepaired: false,
            candidates: []
        ))
        XCTAssertNil(decision.selectedSessionID)
        XCTAssertEqual(decision.reason, .createdNewBecauseNoViableTab)
        XCTAssertTrue(decision.createdNewTab)
        XCTAssertTrue(decision.deferBackendStart)
    }

    func testDivergedSavedSelectionIsRefusedForNextViableMRU() {
        let workspaceID = UUID()
        let diverged = UUID()
        let viable = UUID()
        let decision = SessionRestorePolicy.restoreDecision(
            input: SessionRestoreInput(
                workspaceID: workspaceID,
                savedSelectedSessionID: diverged,
                workspaceWasRepaired: false,
                candidates: [
                    SessionRestoreCandidate(
                        id: diverged, workspaceID: workspaceID,
                        lastActivationOrdinal: 2, lastAccessed: .now,
                        hasLocalTranscript: true, hasContent: true,
                        hasVerifiedBinding: false, isDiverged: true
                    ),
                    SessionRestoreCandidate(
                        id: viable, workspaceID: workspaceID,
                        lastActivationOrdinal: 1, lastAccessed: .distantPast,
                        hasLocalTranscript: true, hasContent: true,
                        hasVerifiedBinding: false, isDiverged: false
                    ),
                ]
            )
        )
        XCTAssertEqual(decision.selectedSessionID, viable)
        XCTAssertEqual(decision.reason, .refusedDivergedSelection)
        XCTAssertNotNil(decision.rejectedCandidateReasons[diverged])
    }

    func testFlushReceiptRequiresCommittedLayout() {
        let defaults = isolatedDefaults()
        let failed = SessionLayoutSaveReceipt(
            committed: false, schemaVersion: 3, recordCount: 1,
            activationCounter: 4, savedAt: .now, failure: .v3WriteVerificationFailed
        )
        XCTAssertNil(SessionLayoutStore.recordFlushReceipt(
            layoutReceipt: failed, transcriptCount: 1, defaults: defaults
        ))
        let committed = SessionLayoutSaveReceipt(
            committed: true, schemaVersion: 3, recordCount: 2,
            activationCounter: 7, savedAt: .now, failure: nil
        )
        let receipt = SessionLayoutStore.recordFlushReceipt(
            layoutReceipt: committed, transcriptCount: 2, defaults: defaults
        )
        XCTAssertEqual(receipt, SessionLayoutStore.lastFlushReceipt(defaults: defaults))
        XCTAssertEqual(receipt?.activationCounter, 7)
    }

    func testVersionedHMACFixtureAndNormalization() throws {
        let fixture = try decodeFixture(HMACFixture.self, name: "transcript-hmac-v1", extension: "json")
        let key = try Data(hex: fixture.keyHex)
        XCTAssertEqual(fixture.schemaVersion, VersionedOpaqueTag.transcriptNormalizationVersion)
        for vector in fixture.vectors {
            let payload = VersionedOpaqueTag.transcriptMessagePayload(
                role: vector.role, ordinal: vector.ordinal, content: vector.content
            )
            XCTAssertEqual(String(decoding: payload, as: UTF8.self), vector.normalized)
            XCTAssertEqual(
                VersionedOpaqueTag.transcriptMessageTag(
                    key: key, role: vector.role, ordinal: vector.ordinal, content: vector.content
                ),
                vector.tag
            )
        }
    }

    func testSliceZeroFixtureCorpusAndSignpostLanesArePinned() throws {
        let fixtureNames = [
            "backend-synthetic-only.jsonl", "backend-verified.jsonl",
            "backend-divergent.jsonl", "backend-composite-worker-parent.jsonl",
            "inspect-external-compat-0.2.118.json", "mcp-add-help-0.2.118.txt",
            "mcp-serialization-0.2.118.json", "transcript-hmac-v1.json",
        ]
        for filename in fixtureNames {
            XCTAssertNotNil(fixtureURL(filename), "Missing fixture: \(filename)")
        }
        XCTAssertEqual(
            Set(GrokBuildPerformanceLane.allCases.map(\.rawValue)),
            Set([
                "appLaunchToWindow", "layoutLoad", "restoreDecision", "selectedTranscriptLoad",
                "continuityVerification", "processSpawnToACPReady", "firstSendToFirstChunk",
                "finalChunkToSettledRender", "tabSwitchToInteractive", "settingsPaneLoad",
                "modelCatalogLoad", "providerCredentialMetadataLoad", "richMessageParse",
                "mermaidRender", "transcriptWrite",
            ])
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "SessionLifecycleV3Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func fixtureURL(_ filename: String) -> URL? {
        Bundle.module.url(
            forResource: filename,
            withExtension: nil,
            subdirectory: "Fixtures/CoherenceRepair"
        )
    }

    private func decodeFixture<Value: Decodable>(
        _ type: Value.Type,
        name: String,
        extension fileExtension: String
    ) throws -> Value {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Fixtures/CoherenceRepair"
        ))
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }
}

private extension Data {
    init(hex: String) throws {
        guard hex.count.isMultiple(of: 2) else { throw HexError.invalid }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { throw HexError.invalid }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }

    enum HexError: Error { case invalid }
}
