import XCTest
@testable import GrokBuild

final class GrokSessionTranscriptImporterTests: XCTestCase {
    private var savedGrokHome: URL!

    override func setUp() {
        super.setUp()
        savedGrokHome = GrokSessionTranscriptImporter.grokHomeDirectory
    }

    override func tearDown() {
        GrokSessionTranscriptImporter.grokHomeDirectory = savedGrokHome
        super.tearDown()
    }

    func testEncodeWorkspacePathMatchesGrokLayout() {
        let workspace = URL(fileURLWithPath: "/Users/demo/helm-oci-plugin/")
        XCTAssertEqual(
            GrokSessionTranscriptImporter.encodeWorkspacePath(workspace),
            "%2FUsers%2Fdemo%2Fhelm-oci-plugin"
        )
    }

    func testChatHistoryURLUsesEncodedWorkspaceAndSessionID() {
        let workspace = URL(fileURLWithPath: "/tmp/demo")
        let url = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: "019eef73-aadb-7b92-90a2-eff8825b3a0b"
        )
        XCTAssertEqual(
            url?.path,
            "\(NSHomeDirectory())/.grok/sessions/%2Ftmp%2Fdemo/019eef73-aadb-7b92-90a2-eff8825b3a0b/chat_history.jsonl"
        )
    }

    func testChatHistoryURLFindsPrivateTmpAliasForCanonicalWorkspace() throws {
        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-alias-test-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let grokID = "019f-private-tmp-alias"
        let expected = grokHome
            .appendingPathComponent("sessions/%2Fprivate%2Ftmp%2Falias-fixture/\(grokID)/chat_history.jsonl")
        try FileManager.default.createDirectory(
            at: expected.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "{\"type\":\"user\",\"content\":\"hello\"}\n".write(
            to: expected,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            GrokSessionTranscriptImporter.chatHistoryURL(
                workspacePath: URL(fileURLWithPath: "/tmp/alias-fixture"),
                grokSessionID: grokID
            ),
            expected
        )
    }

    func testLegacyNilIDLocatorRequiresOneExactPromptMatch() throws {
        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-legacy-locator-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let workspace = URL(fileURLWithPath: "/tmp/legacy-fixture")
        func writeHistory(id: String, prompt: String) throws {
            let history = grokHome
                .appendingPathComponent("sessions/%2Fprivate%2Ftmp%2Flegacy-fixture/\(id)/chat_history.jsonl")
            try FileManager.default.createDirectory(
                at: history.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try """
            {"type":"user","content":"\(prompt)"}
            {"type":"assistant","content":"done"}
            """.write(to: history, atomically: true, encoding: .utf8)
        }

        try writeHistory(id: "backend-one", prompt: "Use two workers")
        XCTAssertEqual(
            GrokSessionTranscriptImporter.uniqueSessionIDMatchingTranscript(
                workspacePath: workspace,
                localMessages: [
                    Message(role: .user, content: "Earlier prompt from a fractured backend"),
                    Message(role: .user, content: "Use  two workers"),
                ]
            ),
            "backend-one"
        )

        try writeHistory(id: "backend-two", prompt: "Use two workers")
        XCTAssertNil(
            GrokSessionTranscriptImporter.uniqueSessionIDMatchingTranscript(
                workspacePath: workspace,
                localMessages: [Message(role: .user, content: "Use two workers")]
            )
        )
    }

    func testImportMessagesExtractsUserQueryAndAssistantText() throws {
        let jsonl = """
        {"type":"system","content":"bootstrap"}
        {"type":"user","content":[{"type":"text","text":"<user_query>Fix the helm plugin</user_query>"}]}
        {"type":"assistant","content":"On it."}
        {"type":"reasoning","content":"hidden"}
        {"type":"tool_call","content":"ignored"}
        """
        let file = try writeTempJSONL(jsonl)

        let messages = GrokSessionTranscriptImporter.importMessages(from: file)

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].content, "Fix the helm plugin")
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertEqual(messages[1].content, "On it.")
        XCTAssertTrue(GrokSessionTranscriptImporter.hasRecoverableTranscript(at: file))
    }

    func testImportSkipsSyntheticSystemReminderOnlyUserRows() throws {
        let jsonl = """
        {"type":"user","content":[{"type":"text","text":"<system-reminder>follow the rules</system-reminder>"}]}
        """
        let file = try writeTempJSONL(jsonl)

        XCTAssertTrue(GrokSessionTranscriptImporter.importMessages(from: file).isEmpty)
        XCTAssertFalse(GrokSessionTranscriptImporter.hasRecoverableTranscript(at: file))
    }

    func testImportStripsRedactedThinkingFromAssistant() throws {
        let open = "<" + "redacted_thinking" + ">"
        let close = "</" + "redacted_thinking" + ">"
        let jsonl = """
        {"type":"assistant","content":"\(open)hidden\(close)Visible answer"}
        """
        let file = try writeTempJSONL(jsonl)

        let messages = GrokSessionTranscriptImporter.importMessages(from: file)
        XCTAssertEqual(messages.first?.content, "Visible answer")
    }

    func testImportSkipsSyntheticRowsAndToolPreambleButKeepsFinalSynthesis() throws {
        let jsonl = """
        {"type":"user","content":[{"type":"text","text":"<user_info>runtime context</user_info>\n<git_status>dirty</git_status>"}]}
        {"type":"user","synthetic_reason":"project_instructions","content":"hidden instructions"}
        {"type":"user","content":"Run the browser check"}
        {"type":"assistant","content":"I will use the browser.","tool_calls":[{"id":"tool-1"}]}
        {"type":"assistant","content":"BROWSER-FINAL-OK","tool_calls":[]}
        """
        let file = try writeTempJSONL(jsonl)

        XCTAssertEqual(
            GrokSessionTranscriptImporter.importMessages(from: file).map(\.content),
            ["Run the browser check", "BROWSER-FINAL-OK"]
        )
    }

    func testReconcilerExtendsPrefixInPlaceAndIsIdempotent() {
        let user = Message(role: .user, content: "Do the work")
        let partial = Message(role: .assistant, content: "Final result")
        let backend = [
            Message(role: .user, content: "Do   the work"),
            Message(role: .assistant, content: "Final result with MARKER-OK"),
        ]

        let first = SessionTranscriptReconciler.reconcile(local: [user, partial], authoritative: backend)
        let second = SessionTranscriptReconciler.reconcile(local: first, authoritative: backend)

        XCTAssertEqual(first[1].id, partial.id)
        XCTAssertEqual(first[1].content, "Final result with MARKER-OK")
        XCTAssertEqual(second, first)
    }

    func testReconcilerRepairsChunkBoundaryWhitespaceAndCollapsesDuplicateFinal() {
        let user = Message(role: .user, content: "Run browser")
        let streamed = Message(
            role: .assistant,
            content: "Heading: `Target`Rendered output: `OK`\n\nFINAL-MARKER"
        )
        let duplicate = Message(
            role: .assistant,
            content: "Heading: `Target`  \nRendered output: `OK`\n\nFINAL-MARKER"
        )
        let authoritative = [
            Message(role: .user, content: "Run browser"),
            Message(
                role: .assistant,
                content: "Heading: `Target`  \nRendered output: `OK`\n\nFINAL-MARKER"
            ),
        ]

        let first = SessionTranscriptReconciler.reconcile(
            local: [user, streamed, duplicate],
            authoritative: authoritative
        )
        let second = SessionTranscriptReconciler.reconcile(local: first, authoritative: authoritative)

        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first.last?.id, streamed.id)
        XCTAssertEqual(first.last?.content, authoritative.last?.content)
        XCTAssertEqual(second, first)
    }

    func testAuthoritativeRecoveryPersistsDuplicateRemovalDespiteNeverShrinkGuard() throws {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }
        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-dedupe-persist-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let workspace = URL(fileURLWithPath: "/tmp/dedupe-persist")
        let grokID = "019f-dedupe-persist"
        let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: grokID
        )!
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let authoritativeText = "Heading: `Target`  \nRendered: `OK`\n\nFINAL-MARKER"
        try """
        {"type":"user","content":"Run browser"}
        {"type":"assistant","content":"Heading: `Target`  \\nRendered: `OK`\\n\\nFINAL-MARKER"}
        """.write(to: historyURL, atomically: true, encoding: .utf8)

        let streamed = Message(
            role: .assistant,
            content: "Heading: `Target`Rendered: `OK`\n\nFINAL-MARKER"
        )
        let local = [
            Message(role: .user, content: "Run browser"),
            streamed,
            Message(role: .assistant, content: authoritativeText),
        ]
        SessionMessageStore.save(local, for: sessionID)

        let recovered = SessionTranscriptRecovery.recoverIfNeeded(
            sessionID: sessionID,
            grokSessionID: grokID,
            workspacePath: workspace,
            currentMessages: local
        )

        XCTAssertEqual(recovered?.count, 2)
        let persisted = SessionMessageStore.messages(for: sessionID)
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(persisted.last?.id, streamed.id)
        XCTAssertEqual(persisted.last?.content, authoritativeText)
    }

    func testReconcilerPreservesDivergentWorkerTextAndAppendsParentFinalOnce() {
        let local = [
            Message(role: .user, content: "Use two workers"),
            Message(role: .assistant, content: "worker explore output"),
        ]
        let authoritative = [
            Message(role: .user, content: "Use two workers"),
            Message(role: .assistant, content: "Clean parent synthesis SUBAGENT-OK"),
        ]

        let first = SessionTranscriptReconciler.reconcile(local: local, authoritative: authoritative)
        let second = SessionTranscriptReconciler.reconcile(local: first, authoritative: authoritative)

        XCTAssertEqual(first.map(\.content), [
            "Use two workers",
            "worker explore output",
            "Clean parent synthesis SUBAGENT-OK",
        ])
        XCTAssertEqual(second, first)
    }

    func testReconcilerKeepsRepeatedPromptsAsDistinctTurnsAndPreservesNewerLocalSuffix() {
        let local = [
            Message(role: .user, content: "repeat"),
            Message(role: .assistant, content: "first complete"),
            Message(role: .user, content: "repeat"),
            Message(role: .assistant, content: "second partial"),
            Message(role: .user, content: "newer local only"),
            Message(role: .assistant, content: "keep me"),
        ]
        let authoritative = [
            Message(role: .user, content: "repeat"),
            Message(role: .assistant, content: "first complete"),
            Message(role: .user, content: "repeat"),
            Message(role: .assistant, content: "second partial plus final"),
        ]

        let reconciled = SessionTranscriptReconciler.reconcile(
            local: local,
            authoritative: authoritative
        )

        XCTAssertEqual(reconciled[3].id, local[3].id)
        XCTAssertEqual(reconciled[3].content, "second partial plus final")
        XCTAssertEqual(Array(reconciled.suffix(2)).map(\.content), ["newer local only", "keep me"])
    }

    func testPartialRecoveryRunsEvenWhenLocalConversationAlreadyExists() throws {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }
        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-test-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let workspace = URL(fileURLWithPath: "/tmp/partial-recovery")
        let grokID = "019f-partial-recovery"
        let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: grokID
        )!
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"type":"user","content":"finish it"}
        {"type":"assistant","content":"complete answer FINAL-OK","tool_calls":[]}
        """.write(to: historyURL, atomically: true, encoding: .utf8)

        let partial = Message(role: .assistant, content: "complete answer")
        let recovered = SessionTranscriptRecovery.recoverIfNeeded(
            sessionID: sessionID,
            grokSessionID: grokID,
            workspacePath: workspace,
            currentMessages: [Message(role: .user, content: "finish it"), partial]
        )

        XCTAssertEqual(recovered?.last?.id, partial.id)
        XCTAssertEqual(recovered?.last?.content, "complete answer FINAL-OK")
        XCTAssertNil(SessionTranscriptRecovery.recoverIfNeeded(
            sessionID: sessionID,
            grokSessionID: grokID,
            workspacePath: workspace,
            currentMessages: recovered ?? []
        ))
    }

    @MainActor
    func testSelectingPopulatedTabReconcilesPrivateTmpBackendTail() throws {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }
        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-reselect-test-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let workspace = Workspace(
            name: "fixture",
            path: URL(fileURLWithPath: "/tmp/reselect-fixture")
        )
        let grokID = "019f-reselect-private-tail"
        let historyURL = grokHome
            .appendingPathComponent("sessions/%2Fprivate%2Ftmp%2Freselect-fixture/\(grokID)/chat_history.jsonl")
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"type":"user","content":"finish it"}
        {"type":"assistant","content":"partial plus RESTORED-FINAL-OK","tool_calls":[]}
        """.write(to: historyURL, atomically: true, encoding: .utf8)

        let store = ChatStore()
        store.restorePersistedMessages([
            Message(role: .user, content: "finish it"),
            Message(role: .assistant, content: "partial"),
        ])
        store.reconcilePersistedMessages(
            for: sessionID,
            grokSessionID: grokID,
            workspace: workspace
        )

        XCTAssertEqual(store.messages.last?.content, "partial plus RESTORED-FINAL-OK")
    }

    func testRecoverIfNeededImportsWhenLocalTranscriptEmpty() throws {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }

        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-test-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let workspace = URL(fileURLWithPath: "/tmp/recovery-demo")
        let grokID = "019eef73-aadb-7b92-90a2-eff8825b3a0b"
        let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: grokID
        )!
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"type":"user","content":[{"type":"text","text":"hello"}]}
        {"type":"assistant","content":"world"}
        """.write(to: historyURL, atomically: true, encoding: .utf8)

        let recovered = SessionTranscriptRecovery.recoverIfNeeded(
            sessionID: sessionID,
            grokSessionID: grokID,
            workspacePath: workspace,
            currentMessages: []
        )

        XCTAssertEqual(recovered?.count, 2)
        XCTAssertEqual(SessionMessageStore.messages(for: sessionID).count, 2)
    }

    func testRecoverIfNeededSkipsStaleFallbackOnlyTabWithStubHistory() throws {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }

        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-test-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }

        let workspace = URL(fileURLWithPath: "/tmp/stale-only")
        let grokID = "019eef73-stale-stub"
        let historyURL = GrokSessionTranscriptImporter.chatHistoryURL(
            workspacePath: workspace,
            grokSessionID: grokID
        )!
        try FileManager.default.createDirectory(
            at: historyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"type":"system","content":"session started"}
        {"type":"user","content":[{"type":"text","text":"<system-reminder>rules</system-reminder>"}]}
        {"type":"assistant","content":""}
        """.write(to: historyURL, atomically: true, encoding: .utf8)

        let staleOnly = [
            Message(
                role: .system,
                content: "Previous grok session expired; started a fresh chat. Your saved transcript in this tab is still shown."
            )
        ]

        XCTAssertNil(
            SessionTranscriptRecovery.recoverIfNeeded(
                sessionID: sessionID,
                grokSessionID: grokID,
                workspacePath: workspace,
                currentMessages: staleOnly
            )
        )
        XCTAssertTrue(SessionMessageStore.messages(for: sessionID).isEmpty)
    }

    func testStaleFallbackNoteIsNotRestorableTranscript() {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }

        let staleNote = Message(
            role: .system,
            content: "Previous grok session expired; started a fresh chat. Your saved transcript in this tab is still shown."
        )
        XCTAssertTrue(SessionMessageStore.isStaleSessionFallbackNote(staleNote))

        SessionMessageStore.save([staleNote], for: sessionID)
        XCTAssertTrue(SessionMessageStore.messages(for: sessionID).isEmpty)
        XCTAssertFalse(SessionMessageStore.hasRestorableTranscript(for: sessionID))
        XCTAssertFalse(
            SessionRestorePolicy.sessionHasRestorableTranscript(
                hasUserMessages: false,
                sessionID: sessionID
            )
        )
    }

    func testSaveAllPersistsMultipleSessionsWithNeverShrinkMerge() {
        let first = UUID()
        let second = UUID()
        defer {
            SessionMessageStore.remove(for: first)
            SessionMessageStore.remove(for: second)
        }

        let longer = [
            Message(role: .user, content: "one"),
            Message(role: .assistant, content: "two"),
            Message(role: .user, content: "three"),
        ]
        SessionMessageStore.save(longer, for: first)

        // One batched write: `first` shrinks in memory (partial restore),
        // `second` is brand new. The on-disk longer transcript must survive.
        SessionMessageStore.saveAll([
            first: [longer[0]],
            second: [Message(role: .user, content: "hello second")],
        ])

        XCTAssertEqual(SessionMessageStore.messages(for: first).count, 3)
        XCTAssertEqual(
            SessionMessageStore.messages(for: second).map(\.content),
            ["hello second"]
        )
    }

    func testEqualCountPartialSaveCannotShortenCompletedAssistant() {
        let sessionID = UUID()
        defer { SessionMessageStore.remove(for: sessionID) }
        let user = Message(role: .user, content: "finish")
        let complete = Message(role: .assistant, content: "complete answer FINAL-OK")
        SessionMessageStore.save([user, complete], for: sessionID)

        SessionMessageStore.save([
            user,
            Message(id: complete.id, role: .assistant, content: "complete answer"),
        ], for: sessionID)

        XCTAssertEqual(
            SessionMessageStore.messages(for: sessionID).last?.content,
            "complete answer FINAL-OK"
        )
    }

    private func writeTempJSONL(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_history-\(UUID().uuidString).jsonl")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
