import XCTest
@testable import GrokBuild

final class GrokSessionTranscriptImporterTests: XCTestCase {
    func testWorkspaceEncodingMatchesGrokForSpacesAndReservedCharacters() {
        let workspace = URL(fileURLWithPath: "/Users/test/MCP Servers/Grok Build/100% ready")
        XCTAssertEqual(
            GrokSessionTranscriptImporter.encodeWorkspacePath(workspace),
            "%2FUsers%2Ftest%2FMCP%20Servers%2FGrok%20Build%2F100%25%20ready"
        )
    }

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

    func testRecoveryCandidateReviewNeverAutoBindsOneCommonPrompt() throws {
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
        let oneMatch = SessionTranscriptRecovery.recoveryCandidates(
            workspacePath: workspace,
            workspaceName: "Legacy fixture",
            localMessages: [
                Message(role: .user, content: "Earlier prompt from a fractured backend"),
                Message(role: .assistant, content: "Earlier local answer"),
                Message(role: .user, content: "Use two workers"),
            ],
            key: Data(0..<32)
        )
        XCTAssertEqual(oneMatch.map(\.backendID), ["backend-one"])
        XCTAssertEqual(oneMatch.first?.matchingTurnCount, 0)
        XCTAssertFalse(try XCTUnwrap(oneMatch.first).isRelinkable)
        XCTAssertEqual(oneMatch.first?.relationship, .diverged)

        try writeHistory(id: "backend-two", prompt: "Use two workers")
        let twoMatches = SessionTranscriptRecovery.recoveryCandidates(
            workspacePath: workspace,
            workspaceName: "Legacy fixture",
            localMessages: [
                Message(role: .user, content: "Earlier prompt from a fractured backend"),
                Message(role: .assistant, content: "Earlier local answer"),
                Message(role: .user, content: "Use two workers"),
            ],
            key: Data(0..<32)
        )
        XCTAssertEqual(Set(twoMatches.map(\.backendID)), Set(["backend-one", "backend-two"]))
        XCTAssertTrue(twoMatches.allSatisfy { !$0.isRelinkable })
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

    func testImportedRowsPreserveWorkerAndRootProvenance() throws {
        let fixture = try fixtureURL("backend-composite-worker-parent.jsonl")
        let transcript = GrokSessionTranscriptImporter.importTranscript(
            from: fixture,
            backendSessionID: "backend-provenance",
            key: Data(0..<32)
        )

        XCTAssertEqual(transcript.rows.map(\.rowIndex), Array(0..<5))
        XCTAssertEqual(
            transcript.rows.map(\.kind),
            [.synthetic, .userTurn, .workerOutput, .workerOutput, .rootFinal]
        )
        XCTAssertEqual(transcript.displayMessages.count, 4)
        XCTAssertEqual(transcript.identityMessages.map(\.content), [
            "Coordinate two synthetic workers.",
            "Parent synthesis for the synthetic fixture.",
        ])
        XCTAssertEqual(
            transcript.displayMessages[1].provenance?.source,
            .backendWorker
        )
        XCTAssertEqual(
            transcript.displayMessages.last?.provenance?.source,
            .backendRoot
        )
        XCTAssertTrue(transcript.displayMessages.allSatisfy {
            $0.provenance?.backendSessionID == "backend-provenance"
                && $0.provenance?.opaqueContentTag != nil
        })
        XCTAssertFalse(transcript.hasQuarantinedIdentityRows)
    }

    func testKnownWorkerRowsDoNotDisplaceRootIdentityProof() throws {
        let fixture = try fixtureURL("backend-composite-worker-parent.jsonl")
        let local = [
            Message(role: .user, content: "Coordinate two synthetic workers."),
            Message(role: .assistant, content: "Parent synthesis for the synthetic fixture."),
        ]
        let verification = SessionTranscriptRecovery.verifyContinuity(
            localMessages: local,
            backendHistoryURL: fixture,
            key: Data(0..<32)
        )

        XCTAssertEqual(verification.receipt.status, .verified)
        XCTAssertEqual(verification.receipt.reason, .exactMatch)
        XCTAssertEqual(verification.backendMessages.count, 4)
        XCTAssertEqual(
            verification.backendMessages.filter {
                $0.provenance?.source == .backendWorker
            }.count,
            2
        )
    }

    func testUnknownOrNonFinalAssistantProvenanceFailsClosed() throws {
        let file = try writeTempJSONL("""
        {"type":"user","content":"Do the safe thing"}
        {"type":"assistant","content":"Unsettled root output","agent":"root","is_final":false}
        {"type":"assistant","content":"Settled root output","agent":"root","is_final":true}
        """)
        let verification = SessionTranscriptRecovery.verifyContinuity(
            localMessages: [
                Message(role: .user, content: "Do the safe thing"),
                Message(role: .assistant, content: "Settled root output"),
            ],
            backendHistoryURL: file,
            key: Data(0..<32)
        )

        XCTAssertEqual(verification.receipt.status, .compositeSuspected)
        XCTAssertEqual(verification.receipt.reason, .mixedOrUnknownProvenance)
    }

    func testContinuityVerifierAcceptsExactAndVerifiedPrefixHistories() {
        let key = Data(0..<32)
        let firstTurn = [
            Message(role: .user, content: "Build the synthetic fixture."),
            Message(role: .assistant, content: "Synthetic fixture complete."),
        ]
        let backend = firstTurn + [
            Message(role: .user, content: "Add a second deterministic turn."),
            Message(role: .assistant, content: "Second turn complete."),
        ]

        let exact = SessionTranscriptRecovery.verifyContinuity(
            localMessages: backend,
            backendMessages: backend,
            key: key
        )
        XCTAssertEqual(exact.status, .verified)
        XCTAssertEqual(exact.reason, .exactMatch)
        XCTAssertEqual(exact.matchingPrefixCount, backend.count)

        let prefix = SessionTranscriptRecovery.verifyContinuity(
            localMessages: firstTurn,
            backendMessages: backend,
            key: key
        )
        XCTAssertEqual(prefix.status, .verified)
        XCTAssertEqual(prefix.reason, .localVerifiedPrefix)
        XCTAssertEqual(prefix.matchingPrefixCount, firstTurn.count)
    }

    func testContinuityVerifierClassifiesBackendOnlyDivergenceAndCompositeEvidence() {
        let key = Data(0..<32)
        let backend = [
            Message(role: .user, content: "First backend turn"),
            Message(role: .assistant, content: "First backend answer"),
            Message(role: .user, content: "Second backend turn"),
            Message(role: .assistant, content: "Second backend answer"),
        ]

        let backendOnly = SessionTranscriptRecovery.verifyContinuity(
            localMessages: [],
            backendMessages: backend,
            key: key
        )
        XCTAssertEqual(backendOnly.status, .backendOnly)
        XCTAssertEqual(backendOnly.reason, .backendOnly)

        let diverged = SessionTranscriptRecovery.verifyContinuity(
            localMessages: [
                backend[0],
                Message(role: .assistant, content: "A different answer"),
            ],
            backendMessages: backend,
            key: key
        )
        XCTAssertEqual(diverged.status, .diverged)
        XCTAssertEqual(diverged.reason, .contentMismatch)

        let composite = SessionTranscriptRecovery.verifyContinuity(
            localMessages: [
                backend[0], backend[1],
                Message(role: .user, content: "Turn from another backend"),
                Message(role: .assistant, content: "Other backend answer"),
                backend[2], backend[3],
            ],
            backendMessages: backend,
            key: key
        )
        XCTAssertEqual(composite.status, .compositeSuspected)
        XCTAssertEqual(composite.reason, .nonContiguousBackendEvidence)
    }

    func testBoundedContinuityVerificationFailsClosedForSyntheticMissingAndIncompleteHistory() throws {
        let key = Data(0..<32)
        let local = [Message(role: .user, content: "Local work must stay safe")]
        let synthetic = try fixtureURL("backend-synthetic-only.jsonl")
        let syntheticResult = SessionTranscriptRecovery.verifyContinuity(
            localMessages: local,
            backendHistoryURL: synthetic,
            key: key
        )
        XCTAssertEqual(syntheticResult.receipt.status, .backendMissing)
        XCTAssertEqual(syntheticResult.receipt.reason, .syntheticOnlyHistory)

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-history-\(UUID().uuidString).jsonl")
        let missingResult = SessionTranscriptRecovery.verifyContinuity(
            localMessages: local,
            backendHistoryURL: missing,
            key: key
        )
        XCTAssertEqual(missingResult.receipt.status, .backendMissing)
        XCTAssertEqual(missingResult.receipt.reason, .backendHistoryMissing)

        let verified = try fixtureURL("backend-verified.jsonl")
        let incomplete = SessionTranscriptRecovery.verifyContinuity(
            localMessages: local,
            backendHistoryURL: verified,
            key: key,
            limits: .init(softByteLimit: 16, softConversationalRowLimit: 1, timeLimit: 0)
        )
        XCTAssertEqual(incomplete.receipt.status, .verificationIncomplete)
        XCTAssertEqual(incomplete.receipt.reason, .boundedReadIncomplete)
    }

    func testCandidateReviewMarksOnlyExactProvenanceSafeHistoryRelinkable() throws {
        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-candidate-review-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }
        let workspace = URL(fileURLWithPath: "/tmp/candidate-review")
        let exactHistory = grokHome
            .appendingPathComponent("sessions/%2Fprivate%2Ftmp%2Fcandidate-review/exact/chat_history.jsonl")
        let commonHistory = grokHome
            .appendingPathComponent("sessions/%2Fprivate%2Ftmp%2Fcandidate-review/common/chat_history.jsonl")
        for history in [exactHistory, commonHistory] {
            try FileManager.default.createDirectory(
                at: history.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        try """
        {"type":"user","content":"First exact prompt"}
        {"type":"assistant","content":"First exact answer"}
        {"type":"user","content":"Common prompt"}
        {"type":"assistant","content":"Common exact answer"}
        """.write(to: exactHistory, atomically: true, encoding: .utf8)
        try """
        {"type":"user","content":"Different history"}
        {"type":"assistant","content":"Different answer"}
        {"type":"user","content":"Common prompt"}
        {"type":"assistant","content":"Unrelated common answer"}
        """.write(to: commonHistory, atomically: true, encoding: .utf8)
        let local = [
            Message(role: .user, content: "First exact prompt"),
            Message(role: .assistant, content: "First exact answer"),
            Message(role: .user, content: "Common prompt"),
            Message(role: .assistant, content: "Common exact answer"),
        ]

        let candidates = SessionTranscriptRecovery.recoveryCandidates(
            workspacePath: workspace,
            workspaceName: "Candidate review",
            localMessages: local,
            key: Data(0..<32)
        )

        XCTAssertEqual(candidates.first?.backendID, "exact")
        XCTAssertTrue(try XCTUnwrap(candidates.first).isRelinkable)
        XCTAssertEqual(candidates.first?.matchingTurnCount, 2)
        XCTAssertFalse(try XCTUnwrap(candidates.first { $0.backendID == "common" }).isRelinkable)

        let promptOnly = SessionTranscriptRecovery.recoveryCandidates(
            workspacePath: workspace,
            workspaceName: "Candidate review",
            localMessages: [Message(role: .user, content: "First exact prompt")],
            key: Data(0..<32)
        )
        let exactPromptOnly = try XCTUnwrap(promptOnly.first { $0.backendID == "exact" })
        XCTAssertEqual(exactPromptOnly.relationship, .verified)
        XCTAssertEqual(exactPromptOnly.matchingTurnCount, 0)
        XCTAssertFalse(
            exactPromptOnly.isRelinkable,
            "one common user prompt is review evidence, never sufficient relink proof"
        )
    }

    @MainActor
    func testContinueAsNewPersistsIntentWithoutStartingBackend() async throws {
        let workspace = Workspace(
            name: "Continue fixture",
            path: URL(fileURLWithPath: "/tmp/continue-as-new")
        )
        let store = ChatStore(continuityKeyOverride: Data(0..<32))
        let tabID = UUID()
        store.prepare(workspace: workspace, savedGrokSessionID: "missing-backend")
        store.bindTabSession(
            tabID,
            modelIntent: .inheritProjectDefault,
            savedGrokSessionID: "missing-backend",
            savedBackendBinding: SessionBackendBinding(
                backendID: "missing-backend",
                origin: .restored,
                predecessorBackendID: nil,
                verification: .failed
            )
        )
        store.restorePersistedMessages([
            Message(role: .user, content: "Preserve this local work"),
            Message(role: .assistant, content: "Preserved local answer"),
        ])
        let missingStatus = await store.verifyContinuityBeforeResume()
        XCTAssertEqual(missingStatus, .backendMissing)
        XCTAssertEqual(store.continuityReceipt.localTabID, tabID)
        XCTAssertEqual(store.continuityReceipt.backendID, "missing-backend")
        XCTAssertNil(store.continuityReceipt.processGeneration)

        let continued = await store.continueAsNew()
        XCTAssertTrue(continued)
        XCTAssertNil(store.savedGrokSessionIDForTests)
        XCTAssertNil(store.grokSessionId)
        XCTAssertEqual(store.connectionState, .idle)
        XCTAssertEqual(store.continuityStatus, .recoveryForked)
        XCTAssertEqual(store.persistedPendingRecoveryIntent?.action, .continueAsNew)
        XCTAssertEqual(
            store.persistedPendingRecoveryIntent?.predecessorBackendID,
            "missing-backend"
        )
        XCTAssertTrue(store.pendingForkLedgerEntries.isEmpty)
        XCTAssertTrue(store.messages.last?.content.contains("Continue as New") == true)

        let relaunched = ChatStore(continuityKeyOverride: Data(0..<32))
        relaunched.prepare(workspace: workspace)
        relaunched.bindTabSession(
            UUID(),
            modelIntent: .inheritProjectDefault,
            savedPendingRecoveryIntent: store.persistedPendingRecoveryIntent
        )
        relaunched.restorePersistedMessages(store.messages)
        XCTAssertEqual(relaunched.continuityStatus, .recoveryForked)
        XCTAssertNil(relaunched.durableGrokSessionID)
        XCTAssertEqual(
            relaunched.continuityReceipt.localMessageCount,
            store.messages.filter { $0.role == .user || $0.role == .assistant }.count
        )
    }

    @MainActor
    func testExplicitRelinkReverifiesAndRecordsLedgerWithoutStartingBackend() async throws {
        let grokHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-relink-\(UUID().uuidString)", isDirectory: true)
        GrokSessionTranscriptImporter.grokHomeDirectory = grokHome
        defer { try? FileManager.default.removeItem(at: grokHome) }
        let workspace = Workspace(
            name: "Relink fixture",
            path: URL(fileURLWithPath: "/tmp/relink-fixture")
        )
        let history = grokHome
            .appendingPathComponent("sessions/%2Fprivate%2Ftmp%2Frelink-fixture/verified-candidate/chat_history.jsonl")
        try FileManager.default.createDirectory(
            at: history.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"type":"user","content":"Relink this exact turn"}
        {"type":"assistant","content":"Exact relink answer","model_id":"grok-4.5"}
        """.write(to: history, atomically: true, encoding: .utf8)

        let store = ChatStore(continuityKeyOverride: Data(0..<32))
        store.prepare(workspace: workspace, savedGrokSessionID: "wrong-backend")
        store.bindTabSession(
            UUID(),
            modelIntent: .inheritProjectDefault,
            savedGrokSessionID: "wrong-backend",
            savedBackendBinding: SessionBackendBinding(
                backendID: "wrong-backend",
                origin: .restored,
                predecessorBackendID: nil,
                verification: .failed
            )
        )
        store.restorePersistedMessages([
            Message(role: .user, content: "Relink this exact turn"),
            Message(role: .assistant, content: "Exact relink answer"),
        ])
        let missingStatus = await store.verifyContinuityBeforeResume()
        XCTAssertEqual(missingStatus, .backendMissing)
        await store.reviewRecoveryCandidates()
        let candidate = try XCTUnwrap(store.recoveryCandidates.first)
        XCTAssertTrue(candidate.isRelinkable)

        let relinked = await store.relink(to: candidate)
        XCTAssertTrue(relinked)
        XCTAssertEqual(store.savedGrokSessionIDForTests, "verified-candidate")
        XCTAssertNil(store.grokSessionId)
        XCTAssertEqual(store.connectionState, .idle)
        XCTAssertEqual(store.continuityStatus, .verified)
        XCTAssertEqual(store.pendingForkLedgerEntries.last?.reason, .explicitRelink)
        XCTAssertEqual(
            store.pendingForkLedgerEntries.last?.predecessorBackendID,
            "wrong-backend"
        )
    }

    func testSendGateAllowsOnlySafeContinuityStates() {
        XCTAssertEqual(SessionSendGate.decision(for: .localOnly), .allowLocalBackendCreation)
        XCTAssertEqual(SessionSendGate.decision(for: .backendBound), .allowVerifiedBackend)
        XCTAssertEqual(SessionSendGate.decision(for: .verified), .allowVerifiedBackend)
        XCTAssertEqual(SessionSendGate.decision(for: .backendOnly), .allowVerifiedBackend)
        XCTAssertEqual(SessionSendGate.decision(for: .recoveryForked), .allowRecoveryFork)

        for blocked in [
            SessionContinuityStatus.verifying,
            .diverged,
            .compositeSuspected,
            .backendMissing,
            .verificationIncomplete,
        ] {
            XCTAssertEqual(SessionSendGate.decision(for: blocked), .block)
        }
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

    func testExactBindingReconciliationAppendsProvenanceRowsOnce() throws {
        let transcript = GrokSessionTranscriptImporter.importTranscript(
            from: try fixtureURL("backend-composite-worker-parent.jsonl"),
            backendSessionID: "exact-backend",
            key: Data(0..<32)
        )
        let local = [Message(role: .user, content: "Coordinate two synthetic workers.")]

        let first = SessionTranscriptReconciler.reconcile(
            local: local,
            authoritative: transcript.displayMessages
        )
        let second = SessionTranscriptReconciler.reconcile(
            local: first,
            authoritative: transcript.displayMessages
        )

        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(first.filter {
            $0.provenance?.source == .backendWorker
        }.count, 2)
        XCTAssertEqual(first.last?.provenance?.source, .backendRoot)
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

    private func fixtureURL(_ filename: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(
                forResource: filename,
                withExtension: nil,
                subdirectory: "Fixtures/CoherenceRepair"
            )
        )
    }
}
