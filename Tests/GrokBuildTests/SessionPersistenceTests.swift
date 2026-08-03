import XCTest
@testable import GrokBuild

final class SessionPersistenceTests: XCTestCase {
    private struct StaticIntegrityKeyProvider: SessionLifecycleIntegrityKeyProviding {
        let key = Data(repeating: 0xA5, count: 32)
        func existingKey() -> Data? { key }
        func existingOrCreateKey() -> Data { key }
    }

    private let sessionLayoutKey = "GrokBuild.sessionLayout.v2"
    private let workspaceLayoutKey = "GrokBuild.workspaceLayout.v1"
    private let sessionNameKey = "grokbuild.sessionNames.v1"

    private var savedSessionLayoutData: Data?
    private var savedWorkspaceLayoutData: Data?
    private var savedSessionNames: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedSessionLayoutData = defaults.data(forKey: sessionLayoutKey)
        savedWorkspaceLayoutData = defaults.data(forKey: workspaceLayoutKey)
        savedSessionNames = defaults.object(forKey: sessionNameKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        restore(savedSessionLayoutData, forKey: sessionLayoutKey)
        restore(savedWorkspaceLayoutData, forKey: workspaceLayoutKey)
        if let savedSessionNames {
            defaults.set(savedSessionNames, forKey: sessionNameKey)
        } else {
            defaults.removeObject(forKey: sessionNameKey)
        }
        super.tearDown()
    }

    @MainActor
    func testBindingRestoredTabReassertsSavedBackendSessionIdentity() {
        let store = ChatStore()
        let restoredID = "019f-restored-gpt-session"

        store.bindTabSession(
            UUID(),
            savedModel: "gpt-5.6-terra",
            savedGrokSessionID: restoredID
        )

        let actualID = store.savedGrokSessionIDForTests
        XCTAssertEqual(actualID, restoredID)
    }

    func testPopulatedRestoredTabUsesSavedBackendIdentityWhenRestartRequestOmitsIt() {
        XCTAssertEqual(
            ChatStore.resolvedResumeSessionID(
                requested: nil,
                saved: "019f-saved-gpt-session",
                hasUserMessages: true
            ),
            "019f-saved-gpt-session"
        )
        XCTAssertNil(
            ChatStore.resolvedResumeSessionID(
                requested: nil,
                saved: "019f-saved-gpt-session",
                hasUserMessages: false
            )
        )
        XCTAssertEqual(
            ChatStore.resolvedResumeSessionID(
                requested: "019f-explicit-session",
                saved: "019f-saved-gpt-session",
                hasUserMessages: true
            ),
            "019f-explicit-session"
        )
    }

    func testProcessTeardownCannotErasePersistedBackendSessionIdentity() {
        XCTAssertFalse(SessionIdentityPersistencePolicy.shouldPersistChangedSessionID(nil))
        XCTAssertFalse(SessionIdentityPersistencePolicy.shouldPersistChangedSessionID("  "))
        XCTAssertTrue(
            SessionIdentityPersistencePolicy.shouldPersistChangedSessionID(
                "019f-durable-backend-session"
            )
        )
    }

    func testSidebarSessionMetadataExposesFullTitleModelAndStatus() {
        let session = SidebarSession(
            id: UUID(),
            workspaceID: UUID(),
            title: "Implement the persistent workflow dashboard with recovery",
            modelName: "GPT 5.6 Terra",
            lastAccessed: Date(timeIntervalSince1970: 1_719_000_000),
            isRunning: true
        )

        let help = SessionSidebarMetadata.helpText(for: session)
        let accessibility = SessionSidebarMetadata.accessibilityLabel(for: session)
        XCTAssertTrue(help.contains(session.title))
        XCTAssertTrue(help.contains("GPT 5.6 Terra"))
        XCTAssertTrue(accessibility.contains("working"))
        XCTAssertTrue(accessibility.contains(session.title))
    }

    func testSidebarSessionMetadataCallsUnpersistedTabNewSession() {
        let session = SidebarSession(
            id: UUID(),
            workspaceID: UUID(),
            title: "New chat",
            modelName: "Grok 4.5",
            lastAccessed: nil,
            isRunning: false
        )

        XCTAssertTrue(SessionSidebarMetadata.helpText(for: session).contains("New session"))
        XCTAssertTrue(SessionSidebarMetadata.accessibilityLabel(for: session).contains("new session"))
        XCTAssertFalse(SessionSidebarMetadata.accessibilityLabel(for: session).contains("last used"))
    }

    func testSessionTitleUsesFirstUserMessageOnly() {
        let messages = [
            Message(role: .assistant, content: "Ignore assistant output"),
            Message(role: .user, content: "  implement saved sessions per project  "),
            Message(role: .user, content: "ignore later user message")
        ]

        XCTAssertEqual(SessionTitle.auto(from: messages), "implement saved sessions per project")
    }

    func testSessionTitleCollapsesWhitespaceAndTruncatesToEightWords() {
        let messages = [
            Message(
                role: .user,
                content: "one\n two   three\tfour five six seven eight nine ten"
            )
        ]

        XCTAssertEqual(SessionTitle.auto(from: messages), "one two three four five six seven eight…")
    }

    func testSessionTitleReturnsNilForEmptyOrMissingUserMessage() {
        XCTAssertNil(SessionTitle.auto(from: []))
        XCTAssertNil(SessionTitle.auto(from: [Message(role: .assistant, content: "hello")]))
        XCTAssertNil(SessionTitle.auto(from: [Message(role: .user, content: "   \n\t  ")]))
    }

    func testSavedSessionRecordCodablePreservesGrokIDAndTitle() throws {
        let workspaceID = UUID()
        let sessionID = UUID()
        let selectedID = UUID()
        let otherWorkspaceID = UUID()
        let otherSelectedID = UUID()
        let expandedWorkspaceID = UUID()
        let hiddenWorkspaceID = UUID()
        let date = Date(timeIntervalSince1970: 1_719_000_000)
        let snapshot = SessionLayoutSnapshot(
            records: [
                SavedSessionRecord(
                    id: sessionID,
                    workspaceID: workspaceID,
                    grokSessionID: "019eef73-aadb-7b92-90a2-eff8825b3a0b",
                    title: "Generating Session Title for Test Query",
                    lastAccessed: date
                )
            ],
            sessionOrderByWorkspace: [workspaceID: [sessionID]],
            selectedSessionID: selectedID,
            selectedWorkspaceID: workspaceID,
            selectedSessionIDByWorkspace: [
                workspaceID: selectedID,
                otherWorkspaceID: otherSelectedID
            ],
            expandedSessionWorkspaceIDs: [expandedWorkspaceID],
            hiddenSessionWorkspaceIDs: [hiddenWorkspaceID]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionLayoutSnapshot.self, from: data)

        XCTAssertEqual(decoded.records.first?.id, sessionID)
        XCTAssertEqual(decoded.records.first?.workspaceID, workspaceID)
        XCTAssertEqual(decoded.records.first?.grokSessionID, "019eef73-aadb-7b92-90a2-eff8825b3a0b")
        XCTAssertEqual(decoded.records.first?.title, "Generating Session Title for Test Query")
        XCTAssertEqual(decoded.records.first?.lastAccessed, date)
        XCTAssertEqual(decoded.sessionOrderByWorkspace[workspaceID], [sessionID])
        XCTAssertEqual(decoded.selectedSessionID, selectedID)
        XCTAssertEqual(decoded.selectedWorkspaceID, workspaceID)
        XCTAssertEqual(decoded.selectedSessionIDByWorkspace[workspaceID], selectedID)
        XCTAssertEqual(decoded.selectedSessionIDByWorkspace[otherWorkspaceID], otherSelectedID)
        XCTAssertEqual(decoded.expandedSessionWorkspaceIDs, [expandedWorkspaceID])
        XCTAssertEqual(decoded.hiddenSessionWorkspaceIDs, [hiddenWorkspaceID])
    }

    func testSessionLayoutStoreRoundTripsSnapshot() {
        let suiteName = "SessionPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let workspaceID = UUID()
        let sessionID = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [
                SavedSessionRecord(
                    id: sessionID,
                    workspaceID: workspaceID,
                    grokSessionID: "019eef73-aadb-7b92-90a2-eff8825b3a0b",
                    title: "Saved title",
                    lastAccessed: Date(timeIntervalSince1970: 42)
                )
            ],
            sessionOrderByWorkspace: [workspaceID: [sessionID]],
            selectedSessionID: sessionID,
            selectedWorkspaceID: workspaceID,
            selectedSessionIDByWorkspace: [workspaceID: sessionID],
            expandedSessionWorkspaceIDs: [workspaceID],
            hiddenSessionWorkspaceIDs: [UUID()]
        )

        let receipt = SessionLayoutStore.saveSessions(
            snapshot,
            defaults: defaults,
            keyProvider: StaticIntegrityKeyProvider()
        )
        let loaded = SessionLayoutStore.loadSessionsResult(
            defaults: defaults,
            keyProvider: StaticIntegrityKeyProvider()
        ).snapshot

        XCTAssertTrue(receipt.committed)
        XCTAssertEqual(loaded.records, snapshot.records)
        XCTAssertEqual(loaded.sessionOrderByWorkspace, snapshot.sessionOrderByWorkspace)
        XCTAssertEqual(loaded.selectedSessionID, snapshot.selectedSessionID)
        XCTAssertEqual(loaded.selectedWorkspaceID, snapshot.selectedWorkspaceID)
        XCTAssertEqual(loaded.selectedSessionIDByWorkspace, snapshot.selectedSessionIDByWorkspace)
        XCTAssertEqual(loaded.expandedSessionWorkspaceIDs, snapshot.expandedSessionWorkspaceIDs)
        XCTAssertEqual(loaded.hiddenSessionWorkspaceIDs, snapshot.hiddenSessionWorkspaceIDs)
    }

    func testSessionLayoutSnapshotDecodesWithoutPerWorkspaceSelection() throws {
        let workspaceID = UUID()
        let sessionID = UUID()
        let json = """
        {
          "records": [],
          "sessionOrderByWorkspace": [],
          "selectedSessionID": "\(sessionID.uuidString)",
          "selectedWorkspaceID": "\(workspaceID.uuidString)"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SessionLayoutSnapshot.self, from: json)

        XCTAssertEqual(decoded.selectedSessionID, sessionID)
        XCTAssertEqual(decoded.selectedWorkspaceID, workspaceID)
        XCTAssertEqual(decoded.selectedSessionIDByWorkspace, [:])
        XCTAssertEqual(decoded.expandedSessionWorkspaceIDs, [])
        XCTAssertEqual(decoded.hiddenSessionWorkspaceIDs, [])
    }

    func testWorkspaceLayoutStoreRoundTripsPinnedAndManualOrder() {
        let pinned = [UUID(), UUID()]
        let ordered = [UUID(), UUID(), UUID()]
        let snapshot = WorkspaceLayoutSnapshot(
            pinnedWorkspaceIDs: pinned,
            workspaceOrder: ordered
        )

        SessionLayoutStore.saveWorkspaceLayout(snapshot)
        let loaded = SessionLayoutStore.loadWorkspaceLayout()

        XCTAssertEqual(loaded.pinnedWorkspaceIDs, pinned)
        XCTAssertEqual(loaded.workspaceOrder, ordered)
    }

    func testWorkspaceAgentSettingsRoundTripPerProject() {
        let workspaceID = UUID()
        let settings = WorkspaceAgentSettings(
            model: "grok-composer-2.5-fast",
            reasoningEffort: "high"
        )

        SessionLayoutStore.saveAgentSettings(settings, for: workspaceID)

        XCTAssertEqual(SessionLayoutStore.agentSettings(for: workspaceID), settings)

        SessionLayoutStore.removeAgentSettings(for: workspaceID)
        XCTAssertEqual(SessionLayoutStore.agentSettings(for: workspaceID), WorkspaceAgentSettings())
    }

    func testWorkspaceLayoutSnapshotDecodesWithoutAgentSettings() throws {
        let pinned = UUID()
        let ordered = UUID()
        let json = """
        {
          "pinnedWorkspaceIDs": ["\(pinned.uuidString)"],
          "workspaceOrder": ["\(ordered.uuidString)"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(WorkspaceLayoutSnapshot.self, from: json)

        XCTAssertEqual(decoded.pinnedWorkspaceIDs, [pinned])
        XCTAssertEqual(decoded.workspaceOrder, [ordered])
        XCTAssertEqual(decoded.agentSettingsByWorkspace, [:])
    }

    func testSessionNameStoreTrimsAndRemovesNames() {
        let id = UUID().uuidString

        SessionNameStore.setName("  Important session  ", for: id)
        XCTAssertEqual(SessionNameStore.name(for: id), "Important session")

        SessionNameStore.setName("   ", for: id)
        XCTAssertNil(SessionNameStore.name(for: id))
    }

    func testSessionMessageStoreRoundTripsTranscript() {
        let sessionID = UUID()
        let messages = [
            Message(role: .user, content: "hello"),
            Message(role: .assistant, content: "world")
        ]

        SessionMessageStore.save(messages, for: sessionID)
        XCTAssertEqual(SessionMessageStore.messages(for: sessionID), messages)

        SessionMessageStore.remove(for: sessionID)
        XCTAssertTrue(SessionMessageStore.messages(for: sessionID).isEmpty)
    }

    func testSessionMessageStoreRoundTripsAssistantThinkingAndToolTrace() {
        let sessionID = UUID()
        let trace = AssistantTurnTrace(
            reasoningSummaryChunks: ["Checked the connected source."],
            thinkingDuration: 2.4,
            tools: [
                .init(
                    id: "tool-1",
                    title: "List pages",
                    status: "Completed",
                    mcpServerName: "chrome-devtools"
                )
            ]
        )
        let messages = [
            Message(role: .user, content: "Inspect the page"),
            Message(role: .assistant, content: "Done", assistantTrace: trace),
        ]

        SessionMessageStore.save(messages, for: sessionID)
        defer { SessionMessageStore.remove(for: sessionID) }

        XCTAssertEqual(SessionMessageStore.messages(for: sessionID), messages)
        XCTAssertEqual(
            SessionMessageStore.messages(for: sessionID).last?.assistantTrace?.tools.first?.mcpServerName,
            "chrome-devtools"
        )
    }

    func testLongerTranscriptMergeKeepsNewAssistantTrace() {
        let root = temporaryTranscriptRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let sessionID = UUID()
        let assistantID = UUID()
        let timestamp = Date()
        let original = [
            Message(
                id: assistantID,
                role: .assistant,
                content: "A complete authoritative answer",
                timestamp: timestamp
            )
        ]
        _ = SessionMessageStore.save(original, for: sessionID, rootURL: root)

        let trace = AssistantTurnTrace(
            reasoningSummaryChunks: ["Verified the source."],
            thinkingDuration: 1,
            tools: []
        )
        let shorterWithTrace = [
            Message(
                id: assistantID,
                role: .assistant,
                content: "A complete",
                timestamp: timestamp,
                assistantTrace: trace
            )
        ]
        _ = SessionMessageStore.save(shorterWithTrace, for: sessionID, rootURL: root)

        let restored = SessionMessageStore.messages(for: sessionID, rootURL: root)
        XCTAssertEqual(restored.first?.content, "A complete authoritative answer")
        XCTAssertEqual(restored.first?.assistantTrace, trace)
    }

    func testFileBackedTranscriptUsesMetadataAndDirtyGenerations() throws {
        let root = temporaryTranscriptRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let sessionID = UUID()
        let first = [
            Message(role: .user, content: "first"),
            Message(role: .assistant, content: "answer"),
        ]

        let initial = try XCTUnwrap(SessionMessageStore.save(first, for: sessionID, rootURL: root))
        XCTAssertEqual(initial.storageVersion, SessionMessageStore.storageVersion)
        XCTAssertEqual(initial.generation, 1)
        XCTAssertEqual(initial.messageCount, 2)
        XCTAssertEqual(initial.restorableMessageCount, 2)
        XCTAssertEqual(SessionMessageStore.messageCount(for: sessionID, rootURL: root), 2)
        XCTAssertEqual(SessionMessageStore.storedTranscriptCount(rootURL: root), 1)

        let unchanged = try XCTUnwrap(SessionMessageStore.save(first, for: sessionID, rootURL: root))
        XCTAssertEqual(unchanged.generation, initial.generation, "clean writes must be skipped")

        let changed = first + [Message(role: .user, content: "second")]
        let updated = try XCTUnwrap(SessionMessageStore.save(changed, for: sessionID, rootURL: root))
        XCTAssertEqual(updated.generation, initial.generation + 1)
        XCTAssertEqual(SessionMessageStore.messageCount(for: sessionID, rootURL: root), 3)
        XCTAssertEqual(SessionMessageStore.messages(for: sessionID, rootURL: root), changed)

        let fileManager = FileManager.default
        let directoryPermissions = try XCTUnwrap(
            fileManager.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        let transcriptURL = root.appendingPathComponent("\(sessionID.uuidString).json")
        let transcriptPermissions = try XCTUnwrap(
            fileManager.attributesOfItem(atPath: transcriptURL.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(directoryPermissions, 0o700)
        XCTAssertEqual(transcriptPermissions, 0o600)
    }

    func testLegacyTranscriptMigrationCopiesVerifiesAndRetainsRollbackDictionary() throws {
        let root = temporaryTranscriptRoot()
        let suiteName = "SessionPersistenceTests.transcriptMigration.\(UUID().uuidString)"
        let defaults = isolatedTranscriptDefaults(suiteName)
        defer {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }
        let first = UUID()
        let second = UUID()
        let fractionalTimestamp = Date(timeIntervalSince1970: 1_722_000_000.1234567)
        let legacy: [String: Data] = [
            first.uuidString: try JSONEncoder().encode([
                Message(role: .user, content: "one", timestamp: fractionalTimestamp)
            ]),
            second.uuidString: try JSONEncoder().encode([
                Message(role: .user, content: "two", timestamp: fractionalTimestamp),
                Message(role: .assistant, content: "answer", timestamp: fractionalTimestamp),
            ]),
        ]
        defaults.set(legacy, forKey: SessionMessageStore.legacyStorageKey)

        let result = SessionMessageStore.migrateLegacyIfNeeded(
            defaults: defaults,
            rootURL: root,
            keyProvider: StaticIntegrityKeyProvider()
        )
        XCTAssertEqual(result, .migrated(transcriptCount: 2))
        XCTAssertTrue(SessionMessageStore.migrationMarkerExists(rootURL: root))
        XCTAssertEqual(defaults.dictionary(forKey: SessionMessageStore.legacyStorageKey) as? [String: Data], legacy)
        XCTAssertEqual(SessionMessageStore.messages(for: first, rootURL: root).map(\.content), ["one"])
        XCTAssertEqual(SessionMessageStore.messageCount(for: second, rootURL: root), 2)
        XCTAssertEqual(SessionMessageStore.storedTranscriptCount(rootURL: root), 2)
        XCTAssertEqual(
            SessionMessageStore.migrateLegacyIfNeeded(
                defaults: defaults,
                rootURL: root,
                keyProvider: StaticIntegrityKeyProvider()
            ),
            .alreadyVerified
        )
    }

    func testMigrationFailureKeepsEntireLegacyDictionaryAndWritesNoMarker() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-transcript-failure-\(UUID().uuidString)")
        let blockedRoot = parent.appendingPathComponent("blocked")
        let suiteName = "SessionPersistenceTests.transcriptMigrationFailure.\(UUID().uuidString)"
        let defaults = isolatedTranscriptDefaults(suiteName)
        defer {
            try? FileManager.default.removeItem(at: parent)
            defaults.removePersistentDomain(forName: suiteName)
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: blockedRoot)
        let sessionID = UUID()
        let legacy = [sessionID.uuidString: try JSONEncoder().encode([Message(role: .user, content: "keep me")])]
        defaults.set(legacy, forKey: SessionMessageStore.legacyStorageKey)

        XCTAssertEqual(
            SessionMessageStore.migrateLegacyIfNeeded(
                defaults: defaults,
                rootURL: blockedRoot,
                keyProvider: StaticIntegrityKeyProvider()
            ),
            .failed
        )
        XCTAssertEqual(defaults.dictionary(forKey: SessionMessageStore.legacyStorageKey) as? [String: Data], legacy)
        XCTAssertFalse(SessionMessageStore.migrationMarkerExists(rootURL: blockedRoot))
    }

    func testSerializedWriterLeavesACompleteTranscriptUnderConcurrentDirtySaves() throws {
        let root = temporaryTranscriptRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let sessionID = UUID()
        let messageID = UUID()

        DispatchQueue.concurrentPerform(iterations: 24) { revision in
            _ = SessionMessageStore.save(
                [Message(id: messageID, role: .user, content: "revision \(revision)")],
                for: sessionID,
                rootURL: root
            )
        }

        let saved = SessionMessageStore.messages(for: sessionID, rootURL: root)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.id, messageID)
        XCTAssertTrue(saved.first?.content.hasPrefix("revision ") == true)
        XCTAssertNotNil(SessionMessageStore.metadata(for: sessionID, rootURL: root))
    }

    func testThousandMessageDirtyWriteTouchesOnlyItsOwnTranscriptAndFeedsV3Integrity() throws {
        let root = temporaryTranscriptRoot()
        let suiteName = "SessionPersistenceTests.transcriptV3.\(UUID().uuidString)"
        let defaults = isolatedTranscriptDefaults(suiteName)
        defer {
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }
        let largeID = UUID()
        let untouchedID = UUID()
        let workspaceID = UUID()
        var messages = (0..<1_000).map { index in
            Message(role: index.isMultiple(of: 2) ? .user : .assistant, content: "row \(index)")
        }
        _ = SessionMessageStore.save(messages, for: largeID, rootURL: root)
        let untouched = try XCTUnwrap(SessionMessageStore.save(
            [Message(role: .user, content: "do not rewrite")],
            for: untouchedID,
            rootURL: root
        ))

        messages[messages.count - 1] = Message(
            id: messages[messages.count - 1].id,
            role: .assistant,
            content: "row 999 revised"
        )
        let started = Date()
        let large = try XCTUnwrap(SessionMessageStore.save(messages, for: largeID, rootURL: root))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.25, "1,000-message dirty write exceeded the local budget")
        XCTAssertEqual(SessionMessageStore.metadata(for: untouchedID, rootURL: root)?.generation, untouched.generation)
        XCTAssertEqual(large.messageCount, 1_000)

        let snapshot = SessionLayoutSnapshot(
            records: [SavedSessionRecord(
                id: largeID,
                workspaceID: workspaceID,
                lastAccessed: .now,
                transcriptGeneration: large.generation,
                transcriptStorageVersion: large.storageVersion
            )],
            sessionOrderByWorkspace: [workspaceID: [largeID]],
            selectedSessionID: largeID,
            selectedWorkspaceID: workspaceID
        )
        XCTAssertTrue(SessionLayoutStore.saveSessions(
            snapshot,
            defaults: defaults,
            keyProvider: StaticIntegrityKeyProvider()
        ).committed)
        let reloaded = SessionLayoutStore.loadSessionsResult(
            defaults: defaults,
            keyProvider: StaticIntegrityKeyProvider()
        )
        XCTAssertEqual(reloaded.authority, .v3Committed)
        XCTAssertEqual(reloaded.snapshot.records.first?.transcriptGeneration, large.generation)
        XCTAssertEqual(reloaded.snapshot.records.first?.transcriptStorageVersion, SessionMessageStore.storageVersion)
    }

    func testSessionMessageStoreSkipsLegacyResumeNotes() {
        let sessionID = UUID()
        let messages = [
            Message(role: .system, content: "Resumed session 019f281a-f002-7510-ab76-5244728404b6."),
            Message(role: .user, content: "real message")
        ]

        SessionMessageStore.save(messages, for: sessionID)
        let loaded = SessionMessageStore.messages(for: sessionID)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "real message")

        SessionMessageStore.remove(for: sessionID)
    }

    @MainActor
    func testChatStoreMarksResumedSessionTabFromSavedGrokID() {
        let store = ChatStore()
        let workspace = Workspace(name: "demo", path: URL(fileURLWithPath: "/tmp/demo"))
        store.prepare(workspace: workspace, savedGrokSessionID: "019eef73-aadb-7b92-90a2-eff8825b3a0b")
        XCTAssertTrue(store.isResumedSessionTab)
    }

    // MARK: - Session restore selection

    func testSessionHasContentIncludesPersistedTranscript() {
        let sessionID = UUID()
        SessionMessageStore.save([Message(role: .user, content: "hello")], for: sessionID)
        defer { SessionMessageStore.remove(for: sessionID) }

        XCTAssertTrue(
            SessionRestorePolicy.sessionHasContent(
                hasUserMessages: false,
                liveGrokSessionID: nil,
                savedGrokSessionID: nil,
                sessionID: sessionID
            )
        )
    }

    func testRecentSessionOrderSortsByLastAccessedDescending() {
        let older = UUID()
        let newer = UUID()
        let workspaceID = UUID()
        let records = [
            SavedSessionRecord(
                id: older,
                workspaceID: workspaceID,
                grokSessionID: nil,
                title: nil,
                lastAccessed: Date(timeIntervalSince1970: 100)
            ),
            SavedSessionRecord(
                id: newer,
                workspaceID: workspaceID,
                grokSessionID: nil,
                title: nil,
                lastAccessed: Date(timeIntervalSince1970: 200)
            )
        ]

        XCTAssertEqual(SessionRestorePolicy.recentSessionOrder(from: records), [newer, older])
    }

    func testPreferredSessionIDSkipsRememberedEmptySession() {
        let workspaceID = UUID()
        let emptySession = UUID()
        let contentSession = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [workspaceID: [emptySession, contentSession]],
            selectedSessionID: emptySession,
            selectedWorkspaceID: workspaceID,
            selectedSessionIDByWorkspace: [workspaceID: emptySession]
        )

        let preferred = SessionRestorePolicy.preferredSessionID(
            for: workspaceID,
            saved: snapshot,
            liveSessionIDsInWorkspace: [emptySession, contentSession],
            currentSelectedSessionID: nil,
            currentSelectedWorkspaceID: nil,
            recentSessionOrder: [],
            hasContent: { $0 == contentSession }
        )

        XCTAssertEqual(preferred, contentSession)
    }

    func testRestoreSelectedSessionIDSkipsEmptySavedSelection() {
        let workspaceID = UUID()
        let emptySession = UUID()
        let contentSession = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [:],
            selectedSessionID: emptySession,
            selectedWorkspaceID: workspaceID
        )

        let restored = SessionRestorePolicy.restoreSelectedSessionID(
            saved: snapshot,
            workspaceID: workspaceID,
            liveSessionIDsInWorkspace: [emptySession, contentSession],
            hasTranscript: { $0 == contentSession },
            hasContent: { $0 == contentSession },
            preferredSessionID: { _ in contentSession }
        )

        XCTAssertEqual(restored, contentSession)
    }

    func testRestoreSelectedSessionIDPrefersTranscriptOverGrokOnlySavedTab() {
        let workspaceID = UUID()
        let grokOnlySession = UUID()
        let transcriptSession = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [
                SavedSessionRecord(
                    id: grokOnlySession,
                    workspaceID: workspaceID,
                    grokSessionID: "019f28a8-4d84",
                    title: "overview",
                    lastAccessed: Date(timeIntervalSince1970: 300)
                ),
                SavedSessionRecord(
                    id: transcriptSession,
                    workspaceID: workspaceID,
                    grokSessionID: "019f2896-700",
                    title: "overview copy",
                    lastAccessed: Date(timeIntervalSince1970: 100)
                )
            ],
            sessionOrderByWorkspace: [workspaceID: [grokOnlySession, transcriptSession]],
            selectedSessionID: grokOnlySession,
            selectedWorkspaceID: workspaceID
        )

        let restored = SessionRestorePolicy.restoreSelectedSessionID(
            saved: snapshot,
            workspaceID: workspaceID,
            liveSessionIDsInWorkspace: [grokOnlySession, transcriptSession],
            hasTranscript: { $0 == transcriptSession },
            hasContent: { $0 == grokOnlySession || $0 == transcriptSession },
            preferredSessionID: { _ in grokOnlySession }
        )

        XCTAssertEqual(restored, transcriptSession)
    }

    func testRestoreSelectedSessionIDKeepsSavedSelectionWhenItHasContent() {
        let workspaceID = UUID()
        let savedSession = UUID()
        let otherSession = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [:],
            selectedSessionID: savedSession,
            selectedWorkspaceID: workspaceID
        )

        let restored = SessionRestorePolicy.restoreSelectedSessionID(
            saved: snapshot,
            workspaceID: workspaceID,
            liveSessionIDsInWorkspace: [savedSession, otherSession],
            hasTranscript: { $0 == savedSession },
            hasContent: { $0 == savedSession },
            preferredSessionID: { _ in otherSession }
        )

        XCTAssertEqual(restored, savedSession)
    }

    func testPreferredSessionIDKeepsCurrentSessionInSameWorkspace() {
        let workspaceID = UUID()
        let current = UUID()
        let other = UUID()
        let snapshot = SessionLayoutSnapshot(
            records: [],
            sessionOrderByWorkspace: [:],
            selectedSessionID: other,
            selectedWorkspaceID: workspaceID
        )

        let preferred = SessionRestorePolicy.preferredSessionID(
            for: workspaceID,
            saved: snapshot,
            liveSessionIDsInWorkspace: [current, other],
            currentSelectedSessionID: current,
            currentSelectedWorkspaceID: workspaceID,
            recentSessionOrder: [other, current],
            hasContent: { _ in true }
        )

        XCTAssertEqual(preferred, current)
    }

    func testSessionMessageStoreMergesOnPartialSave() {
        let sessionID = UUID()
        let original = [
            Message(role: .user, content: "hello"),
            Message(role: .assistant, content: "world")
        ]
        SessionMessageStore.save(original, for: sessionID)
        SessionMessageStore.save([Message(role: .system, content: "note")], for: sessionID)

        let loaded = SessionMessageStore.messages(for: sessionID)
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.filter { $0.role == .user }.first?.content, "hello")
        XCTAssertEqual(loaded.filter { $0.role == .assistant }.first?.content, "world")
        XCTAssertEqual(loaded.filter { $0.role == .system }.first?.content, "note")

        SessionMessageStore.remove(for: sessionID)
    }

    @MainActor
    func testPostStartRecoveryRehydratesOnlyAnEmptyStore() {
        let sessionID = UUID()
        let workspace = Workspace(
            name: "Post-start recovery",
            path: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
        let persisted = [
            Message(role: .user, content: "persisted prompt"),
            Message(role: .assistant, content: "persisted answer")
        ]
        SessionMessageStore.save(persisted, for: sessionID)
        defer { SessionMessageStore.remove(for: sessionID) }

        let store = ChatStore()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertTrue(store.recoverPersistedMessagesAfterStartIfEmpty(
            for: sessionID,
            grokSessionID: nil,
            workspace: workspace
        ))
        XCTAssertEqual(store.messages, persisted)

        store.restorePersistedMessages([
            Message(role: .user, content: "newer visible prompt"),
            Message(role: .assistant, content: "newer visible answer")
        ])
        XCTAssertFalse(store.recoverPersistedMessagesAfterStartIfEmpty(
            for: sessionID,
            grokSessionID: nil,
            workspace: workspace
        ))
        XCTAssertEqual(store.messages.map(\.content), [
            "newer visible prompt",
            "newer visible answer"
        ])
    }

    // MARK: - Stale grok session load

    func testStaleSessionLoadDetectsFSNotFound() {
        let error = NSError(
            domain: "ACP",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Path not found.",
                "acpErrorCode": "FS_NOT_FOUND"
            ]
        )
        XCTAssertTrue(GrokSessionLoadError.isStaleSessionMissing(error))
    }

    func testStaleSessionLoadIgnoresUnrelatedErrors() {
        let error = NSError(domain: "ACP", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Connection refused"
        ])
        XCTAssertFalse(GrokSessionLoadError.isStaleSessionMissing(error))
    }

    // MARK: - Session list parsing

    func testParseListOutputNormalizesNoSummaryPlaceholder() {
        let output = """
        SESSION ID                            CREATED     UPDATED     STATUS      SUMMARY
        019f191a-c344-7ac2-ac79-dd49cec5460a  2026-07-03  2026-07-03  both  Implement /voice Slash Command Feature
        019f191a-2795-74f1-a8a3-b1df0cf2d49f  2026-06-30  2026-06-30  local  (no summary)
        """

        let sessions = GrokSessionInfo.parseListOutput(output)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].summary, "Implement /voice Slash Command Feature")
        // The literal "(no summary)" placeholder normalizes to empty.
        XCTAssertEqual(sessions[1].summary, "")
    }

    // MARK: - Sessions cleanup ("Clear Empty")

    func testCleanableSessionRequiresNoIdentityAndNotInUse() {
        // Unnamed, no summary, not active, not live → safe to bulk-clear.
        XCTAssertTrue(SessionsBrowserPanel.isCleanableSession(
            summary: "   ", hasCustomName: false, isActive: false, isLive: false
        ))
    }

    func testCleanableSessionExcludesNamedSummarizedActiveOrLive() {
        // A summary protects the session.
        XCTAssertFalse(SessionsBrowserPanel.isCleanableSession(
            summary: "Implement feature", hasCustomName: false, isActive: false, isLive: false
        ))
        // A user-assigned name protects it.
        XCTAssertFalse(SessionsBrowserPanel.isCleanableSession(
            summary: "", hasCustomName: true, isActive: false, isLive: false
        ))
        // The active session is never cleared out from under the user.
        XCTAssertFalse(SessionsBrowserPanel.isCleanableSession(
            summary: "", hasCustomName: false, isActive: true, isLive: false
        ))
        // An open live tab is never cleared.
        XCTAssertFalse(SessionsBrowserPanel.isCleanableSession(
            summary: "", hasCustomName: false, isActive: false, isLive: true
        ))
    }

    // MARK: - Reasoning effort default inheritance

    func testResolveReasoningEffortInheritsGlobalDefaultWhenUnset() {
        // No per-project value → inherit the global default for new projects.
        XCTAssertEqual(ChatStore.resolveReasoningEffort(saved: nil, globalDefault: "high"), "high")
    }

    func testResolveReasoningEffortPrefersSavedValueIncludingDefault() {
        // An explicit per-project choice wins over the global default…
        XCTAssertEqual(ChatStore.resolveReasoningEffort(saved: "low", globalDefault: "high"), "low")
        // …including an explicit "Default" (empty string), which must not fall back.
        XCTAssertEqual(ChatStore.resolveReasoningEffort(saved: "", globalDefault: "high"), "")
    }

    // MARK: - Per-tab model

    func testSavedSessionRecordDecodesWithoutModel() throws {
        let record = SavedSessionRecord(
            id: UUID(),
            workspaceID: UUID(),
            lastAccessed: Date()
        )

        let decoded = try JSONDecoder().decode(
            SavedSessionRecord.self,
            from: JSONEncoder().encode(record)
        )

        XCTAssertNil(decoded.model)
    }

    func testSavedSessionRecordRoundTripsModel() throws {
        let record = SavedSessionRecord(
            id: UUID(),
            workspaceID: UUID(),
            grokSessionID: "abc",
            title: "Tab",
            model: "grok-build",
            lastAccessed: Date()
        )

        let decoded = try JSONDecoder().decode(SavedSessionRecord.self, from: JSONEncoder().encode(record))

        XCTAssertEqual(decoded.model, "grok-build")
    }

    // MARK: - Per-tab agent

    func testSavedSessionRecordDecodesWithoutAgent() throws {
        let record = SavedSessionRecord(id: UUID(), workspaceID: UUID(), lastAccessed: Date())
        let decoded = try JSONDecoder().decode(
            SavedSessionRecord.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertNil(decoded.agent)
    }

    func testSavedSessionRecordRoundTripsAgent() throws {
        let record = SavedSessionRecord(
            id: UUID(),
            workspaceID: UUID(),
            grokSessionID: "abc",
            title: "Tab",
            model: "grok-build",
            agent: "explore",
            lastAccessed: Date()
        )
        let decoded = try JSONDecoder().decode(SavedSessionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.agent, "explore")
    }

    @MainActor
    func testChatStoreTabFollowsGlobalDefaultAgentUntilOverridden() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: GrokSettingsKeys.selectedAgent)
        defaults.set("explore", forKey: GrokSettingsKeys.selectedAgent)
        defer {
            if let previous { defaults.set(previous, forKey: GrokSettingsKeys.selectedAgent) }
            else { defaults.removeObject(forKey: GrokSettingsKeys.selectedAgent) }
        }

        let store = ChatStore()
        // New tab (no saved agent) follows the global default and persists nothing.
        store.bindTabSession(UUID(), savedModel: nil, savedAgent: nil)
        XCTAssertFalse(store.hasExplicitAgent)
        XCTAssertEqual(store.effectiveAgentSelection, "explore")
        XCTAssertNil(store.persistedAgentSelection)
    }

    @MainActor
    func testChatStoreTabRestoresExplicitSavedAgent() {
        let store = ChatStore()
        store.bindTabSession(UUID(), savedModel: nil, savedAgent: "researcher")
        XCTAssertTrue(store.hasExplicitAgent)
        XCTAssertEqual(store.effectiveAgentSelection, "researcher")
        XCTAssertEqual(store.persistedAgentSelection, "researcher")
        XCTAssertEqual(store.effectiveAgentDisplayName, "researcher")
    }

    @MainActor
    func testChatStoreV3IntentBindingPreservesInheritanceAndLegacyUnknown() {
        let store = ChatStore()
        store.bindTabSession(
            UUID(),
            modelIntent: .inheritProjectDefault,
            agentIntent: .inheritGlobalDefault
        )
        XCTAssertEqual(store.persistedModelIntent, .inheritProjectDefault)
        XCTAssertEqual(store.persistedAgentIntent, .inheritGlobalDefault)

        store.bindTabSession(
            UUID(),
            modelIntent: .legacyUnknown("grok-4.5"),
            agentIntent: .explicit("researcher")
        )
        XCTAssertEqual(store.persistedModelIntent, .legacyUnknown("grok-4.5"))
        XCTAssertEqual(store.persistedAgentIntent, .explicit("researcher"))
    }

    func testSessionTabModelPolicyPrefersTabOverWorkspaceDefault() {
        XCTAssertEqual(
            SessionTabModelPolicy.resolvedModel(
                tabModel: "mini-max",
                workspaceDefault: "grok-composer-2.5-fast",
                appDefault: "grok-build"
            ),
            "mini-max"
        )
        XCTAssertEqual(
            SessionTabModelPolicy.resolvedModel(
                tabModel: nil,
                workspaceDefault: "grok-composer-2.5-fast",
                appDefault: "grok-build"
            ),
            "grok-composer-2.5-fast"
        )
        XCTAssertEqual(
            SessionTabModelPolicy.resolvedModel(
                tabModel: "  ",
                workspaceDefault: nil,
                appDefault: "grok-build"
            ),
            "grok-build"
        )
    }

    private func restore(_ data: Data?, forKey key: String) {
        if let data {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func temporaryTranscriptRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-transcripts-\(UUID().uuidString)")
            .appendingPathComponent("Transcripts")
    }

    private func isolatedTranscriptDefaults(_ suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
