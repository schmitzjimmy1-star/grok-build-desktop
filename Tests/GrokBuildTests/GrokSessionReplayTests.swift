import XCTest
@testable import GrokBuild

final class GrokSessionReplayTests: XCTestCase {
    private func envelope(
        sessionID: String,
        update: [String: Any],
        method: String = "session/update"
    ) -> ACPStoredUpdateEnvelope {
        ACPStoredUpdateEnvelope(foundation: [
            "method": method,
            "params": ["sessionId": sessionID, "update": update],
        ])!
    }

    func testReplayDetectedFromParamsMeta() {
        let params: [String: Any] = [
            "_meta": ["isReplay": true],
            "update": ["sessionUpdate": "tool_call"]
        ]
        XCTAssertTrue(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }

    func testReplayDetectedFromUpdateMeta() {
        let params: [String: Any] = [
            "update": [
                "_meta": ["isReplay": true],
                "sessionUpdate": "agent_thought_chunk"
            ]
        ]
        XCTAssertTrue(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }

    func testLiveUpdateNotReplay() {
        let params: [String: Any] = [
            "update": ["sessionUpdate": "agent_message_chunk", "content": ["text": "hi"]]
        ]
        XCTAssertFalse(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }

    func testReplayFalseWhenMetaMissing() {
        let params: [String: Any] = [
            "_meta": [:] as [String: Any],
            "update": ["sessionUpdate": "tool_call_update"]
        ]
        XCTAssertFalse(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }

    func testReplayFalseWhenIsReplayFalse() {
        let params: [String: Any] = [
            "_meta": ["isReplay": false],
            "update": ["sessionUpdate": "tool_call"]
        ]
        XCTAssertFalse(GrokSessionReplay.isReplaySessionUpdate(params: params))
    }

    func testTypedReplayBuildsOnlyRootConversationAndCoalescesChunks() {
        let replay = GrokSessionReplay.transcript(
            backendSessionID: "root-session",
            processGeneration: 7,
            envelopes: [
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "user_message_chunk",
                    "content": ["type": "text", "text": "Hello "],
                ]),
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "user_message_chunk",
                    "content": ["type": "text", "text": "world"],
                ]),
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "agent_thought_chunk",
                    "content": ["type": "text", "text": "private reasoning"],
                ]),
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "tool_call",
                    "title": "Read file",
                ]),
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "agent_message_chunk",
                    "content": ["type": "text", "text": "Final "],
                ]),
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "agent_message_chunk",
                    "content": ["type": "text", "text": "answer"],
                ]),
                envelope(sessionID: "other-session", update: [
                    "sessionUpdate": "agent_message_chunk",
                    "content": ["type": "text", "text": "wrong child"],
                ]),
            ]
        )

        XCTAssertEqual(replay.backendSessionID, "root-session")
        XCTAssertEqual(replay.processGeneration, 7)
        XCTAssertEqual(replay.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(replay.messages.map(\.content), ["Hello world", "Final answer"])
        XCTAssertEqual(replay.messages.map(\.provenance?.source), [.backendRoot, .backendRoot])
        XCTAssertEqual(replay.replayEventCount, 6)
    }

    func testTypedReplayExcludesHostTurnContext() {
        let replay = GrokSessionReplay.transcript(
            backendSessionID: "root-session",
            processGeneration: 1,
            envelopes: [
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "user_message_chunk",
                    "content": ["type": "text", "text": "injected host context"],
                    "_meta": ["hostTurn": true],
                ]),
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "user_message_chunk",
                    "content": ["type": "text", "text": "real prompt"],
                ]),
            ]
        )

        XCTAssertEqual(replay.messages.map(\.content), ["real prompt"])
    }

    func testTypedReplayDoesNotMergeInterruptedUserTurns() {
        let replay = GrokSessionReplay.transcript(
            backendSessionID: "root-session",
            processGeneration: 1,
            envelopes: [
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "user_message_chunk",
                    "content": [
                        "type": "text",
                        "text": "first",
                        "_meta": ["promptIndex": 0],
                    ],
                ]),
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "turn_completed",
                ], method: "_x.ai/session/update"),
                envelope(sessionID: "root-session", update: [
                    "sessionUpdate": "user_message_chunk",
                    "content": [
                        "type": "text",
                        "text": "second",
                        "_meta": ["promptIndex": 1],
                    ],
                ]),
            ]
        )

        XCTAssertEqual(replay.messages.map(\.role), [.user, .user])
        XCTAssertEqual(replay.messages.map(\.content), ["first", "second"])
    }
}
