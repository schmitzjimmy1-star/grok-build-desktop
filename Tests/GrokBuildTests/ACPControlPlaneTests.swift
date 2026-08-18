import Foundation
import XCTest
@testable import GrokBuild

final class ACPControlPlaneTests: XCTestCase {
    func testAgentVersionParsingUsesNumericFamilyAndOrdersSemantically() throws {
        XCTAssertEqual(ACPAgentVersion("1.0.5-alpha.2")?.description, "1.0.5-alpha.2")
        XCTAssertEqual(ACPAgentVersion("grok 1.0.5 (abcdef)")?.major, 1)
        XCTAssertFalse(try XCTUnwrap(ACPAgentVersion("1.0.4")) < ACPControlMethod.models.officialExtensionFloor)
        XCTAssertTrue(try XCTUnwrap(ACPAgentVersion("1.0.4")) < ACPControlMethod.sessionUsage.officialExtensionFloor)
        XCTAssertFalse(try XCTUnwrap(ACPAgentVersion("1.0.10")) < ACPControlMethod.sessionUsage.officialExtensionFloor)
        XCTAssertNil(ACPAgentVersion("stable-ish"))
    }

    func testOfficialModelCatalogUpdateIsCompleteAndRejectsMalformedRows() throws {
        let event = try XCTUnwrap(ACPModelCatalogEvent.parse([
            "currentModelId": "custom-a",
            "availableModels": [
                ["modelId": "custom-a", "name": "Custom A"],
                ["modelId": "grok-4.6", "name": "Grok 4.6", "_meta": ["totalContextTokens": 200_000]],
            ],
        ], processGeneration: 9))
        XCTAssertEqual(event.processGeneration, 9)
        XCTAssertEqual(event.currentModelID, "custom-a")
        XCTAssertEqual(event.models.map(\.id), ["custom-a", "grok-4.6"])
        XCTAssertEqual(event.models.last?.contextTokens, 200_000)

        XCTAssertNil(ACPModelCatalogEvent.parse([
            "availableModels": [["name": "missing id"]],
        ], processGeneration: 9))
        XCTAssertNil(ACPModelCatalogEvent.parse([
            "availableModels": [
                ["modelId": "duplicate"],
                ["modelId": "duplicate"],
            ],
        ], processGeneration: 9))
    }

    func testModelsAreAvailableOn104WhilePersistedControlsStayGated() {
        let registry = ACPControlCapabilityRegistry()
        registry.reset(generation: 4, agentVersion: ACPAgentVersion("1.0.4"))
        XCTAssertTrue(registry.shouldAttempt(.models, generation: 4))
        XCTAssertFalse(registry.shouldAttempt(.sessionUsage, generation: 4))
        XCTAssertEqual(registry.state(for: .sessionUsage, generation: 4), .unsupported)
    }

    func testTypedParsersAcceptOfficial105WireShapes() throws {
        let catalog = try ACPControlModelCatalog.parse([
            "result": [
                "currentModelId": "grok-4.5",
                "availableModels": [[
                    "modelId": "grok-4.5",
                    "name": "Grok 4.5",
                    "_meta": ["totalContextTokens": 131_072],
                ]],
            ],
        ])
        XCTAssertEqual(catalog.currentModelID, "grok-4.5")
        XCTAssertEqual(catalog.availableModels, [
            ACPControlModel(id: "grok-4.5", name: "Grok 4.5", contextTokens: 131_072),
        ])

        let usage = try ACPControlSessionUsage.parse([
            "usage": [
                "inputTokens": 100,
                "outputTokens": 10,
                "totalTokens": 110,
                "numTurns": 1,
                "costUsdTicks": 20_000_000,
                "costIsPartial": false,
                "modelUsage": [
                    "grok-4.5": ["inputTokens": 100, "outputTokens": 10, "totalTokens": 110],
                ],
            ],
        ])
        XCTAssertEqual(usage.totalTokens, 110)
        XCTAssertEqual(usage.turnCount, 1)
        XCTAssertEqual(usage.costUsdTicks, 20_000_000)
        XCTAssertEqual(usage.modelUsage.map(\.modelID), ["grok-4.5"])

        let metadata = try ACPControlSessionMetadata.parse([
            "result": [
                "sessionId": "backend-1",
                "cwd": "/tmp/work",
                "agentName": "grok-build",
                "model": "grok-4.5",
                "turns": 3,
                "turnIndex": 2,
                "context": ["used": 500, "total": 131_072, "usagePct": 1],
            ],
        ])
        XCTAssertEqual(metadata.sessionID, "backend-1")
        XCTAssertEqual(metadata.contextTotalTokens, 131_072)

        let page = try ACPControlSessionUpdatePage.parse([
            "updates": [[
                "timestamp": 5,
                "method": "_x.ai/session/update",
                "params": [
                    "sessionId": "child-1",
                    "update": [
                        "sessionUpdate": "tool_call_update",
                        "toolCallId": "tool-1",
                        "status": "completed",
                    ],
                ],
            ]],
            "totalCount": 1,
            "hasMore": false,
            "lastEventId": "event-1",
            "promptStarts": [0],
        ])
        XCTAssertEqual(page.updates.first?.sessionID, "child-1")
        XCTAssertEqual(page.updates.first?.foundationUpdate?["toolCallId"] as? String, "tool-1")
        XCTAssertEqual(page.lastEventID, "event-1")
    }

    func testUpdatePageRejectsMalformedEnvelopeInsteadOfDroppingIt() {
        XCTAssertThrowsError(try ACPControlSessionUpdatePage.parse([
            "updates": [["method": "session/update"]],
            "totalCount": 1,
            "hasMore": false,
        ])) { error in
            XCTAssertEqual(
                error as? ACPControlError,
                .invalidResponse(method: .sessionUpdates, reason: "malformed update envelope")
            )
        }
    }

    func testTypedParsersRejectMalformedCollectionsAndOversizedPages() {
        XCTAssertThrowsError(try ACPControlModelCatalog.parse([
            "result": ["availableModels": [["name": "missing id"]]],
        ]))
        XCTAssertThrowsError(try ACPControlSessionUsage.parse([
            "usage": ["modelUsage": "not an object"],
        ]))
        XCTAssertThrowsError(try ACPControlSessionUpdatePage.parse([
            "updates": Array(repeating: [
                "method": "session/update",
                "params": ["sessionId": "child"],
            ], count: 513),
            "totalCount": 513,
            "hasMore": false,
        ])) { error in
            XCTAssertEqual(
                error as? ACPControlError,
                .invalidResponse(method: .sessionUpdates, reason: "page exceeded 512 updates")
            )
        }
    }

    func testCapabilityCacheCannotLeakAcrossProcessGenerations() {
        let registry = ACPControlCapabilityRegistry()
        registry.reset(generation: 7, agentVersion: ACPAgentVersion("1.0.5"))
        registry.record(.unsupported, for: .sessionUsage, generation: 7)
        XCTAssertEqual(registry.state(for: .sessionUsage, generation: 7), .unsupported)

        registry.reset(generation: 8, agentVersion: ACPAgentVersion("1.0.5"))
        XCTAssertEqual(registry.state(for: .sessionUsage, generation: 8), .unknown)
        XCTAssertEqual(registry.state(for: .sessionUsage, generation: 7), .unsupported)
    }

    func testMissingAgentVersionFailsClosedWithoutAProbe() {
        let registry = ACPControlCapabilityRegistry()
        registry.reset(generation: 11, agentVersion: nil)

        XCTAssertFalse(registry.shouldAttempt(.sessionUpdates, generation: 11))
        XCTAssertEqual(registry.state(for: .sessionUpdates, generation: 11), .unsupported)
    }

    @MainActor
    func testOfficial105MethodsShareTheExistingConnectionAndReturnTypedReceipts() async throws {
        let fixture = try makeFakeAgent(version: "1.0.5", behavior: .official)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        GrokProcess.cliOverrideForTests = fixture.script
        defer { GrokProcess.cliOverrideForTests = nil }

        let process = GrokProcess()
        await process.start(workspace: Workspace(name: "typed-control", path: fixture.root))
        do {
            XCTAssertEqual(process.state, .ready)
            XCTAssertEqual(process.acpAgentVersion?.description, "1.0.5")

            let catalog = try await process.fetchACPModelCatalog()
            XCTAssertEqual(catalog.availableModels.map(\.id), ["grok-4.5", "open-model"])

            let usage = try await process.fetchACPSessionUsage()
            XCTAssertEqual(usage.totalTokens, 110)
            XCTAssertEqual(usage.modelUsage.first?.modelID, "grok-4.5")

            let metadata = try await process.fetchACPSessionMetadata()
            XCTAssertEqual(metadata.sessionID, "typed-backend")
            XCTAssertEqual(metadata.modelID, "grok-4.5")

            let page = try await process.fetchACPSessionUpdates(
                sessionID: "child-123",
                offset: -256,
                limit: 256
            )
            XCTAssertEqual(page.totalCount, 2)
            XCTAssertEqual(page.updates.count, 2)

            let fetchedReceipts = await process.fetchChildToolReceipts(
                childID: "child-123",
                expectedToolCallCount: 2
            )
            let receipts = try XCTUnwrap(fetchedReceipts)
            XCTAssertEqual(receipts.map(\.id), ["tool-1", "tool-2"])
            XCTAssertEqual(receipts.map(\.status), [.succeeded, .succeeded])

            for method in ACPControlMethod.allCases {
                XCTAssertEqual(process.acpControlCapabilityState(for: method), .supported)
            }
        } catch {
            await process.shutdown()
            let rpc = (try? String(contentsOf: fixture.log, encoding: .utf8)) ?? "missing RPC log"
            XCTFail("Typed control request failed: \(error)\n\(rpc)")
            throw error
        }
        await process.shutdown()

        let log = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertTrue(log.contains(#""method":"x.ai/models/list""#))
        XCTAssertTrue(log.contains(#""method":"x.ai/session/usage""#))
        XCTAssertTrue(log.contains(#""method":"x.ai/session/info""#))
        XCTAssertTrue(log.contains(#""method":"x.ai/session/updates""#))
    }

    @MainActor
    func testKnown104RefusesExtensionWithoutPuttingItOnTheWire() async throws {
        let fixture = try makeFakeAgent(version: "1.0.4", behavior: .official)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        GrokProcess.cliOverrideForTests = fixture.script
        defer { GrokProcess.cliOverrideForTests = nil }

        let process = GrokProcess()
        await process.start(workspace: Workspace(name: "known-old-control", path: fixture.root))
        do {
            await XCTAssertThrowsErrorAsync(try await process.fetchACPSessionUsage()) { error in
                XCTAssertEqual(
                    error as? ACPControlError,
                    .unavailable(method: .sessionUsage, agentVersion: "1.0.4")
                )
            }
            XCTAssertEqual(process.acpControlCapabilityState(for: .sessionUsage), .unsupported)
            let unsupportedReceipts = await process.fetchChildToolReceipts(
                childID: "child-old",
                expectedToolCallCount: 1
            )
            XCTAssertNil(unsupportedReceipts)
        }
        await process.shutdown()

        let log = try String(contentsOf: fixture.log, encoding: .utf8)
        XCTAssertFalse(log.contains(#""method":"x.ai/session/usage""#))
        XCTAssertFalse(log.contains(#""method":"x.ai/session/updates""#))
    }

    @MainActor
    func testMethodNotFoundIsProbedOnceAndCachedForThatGeneration() async throws {
        let fixture = try makeFakeAgent(version: "1.0.5", behavior: .methodNotFound)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        GrokProcess.cliOverrideForTests = fixture.script
        defer { GrokProcess.cliOverrideForTests = nil }

        let process = GrokProcess()
        await process.start(workspace: Workspace(name: "unsupported-control", path: fixture.root))
        for _ in 0..<2 {
            await XCTAssertThrowsErrorAsync(try await process.fetchACPSessionUsage()) { error in
                XCTAssertEqual(
                    error as? ACPControlError,
                    .unavailable(method: .sessionUsage, agentVersion: "1.0.5")
                )
            }
        }
        XCTAssertEqual(process.acpControlCapabilityState(for: .sessionUsage), .unsupported)
        await process.shutdown()

        let count = try String(contentsOf: fixture.log, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .filter { $0.contains(#""method":"x.ai/session/usage""#) }
            .count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testBoundedUpdatesRejectOversizedLimitBeforeWriting() async {
        let process = GrokProcess()
        await XCTAssertThrowsErrorAsync(
            try await process.fetchACPSessionUpdates(sessionID: "child", offset: 0, limit: 513)
        ) { error in
            XCTAssertEqual(
                error as? ACPControlError,
                .invalidRequest("limit must be 1...512")
            )
        }
    }

    func testStandardSessionListParsesTypedInventoryAndCursor() throws {
        let page = try ACPStandardSessionListPage.parse([
            "sessions": [
                [
                    "sessionId": "session-1",
                    "cwd": "/tmp/project",
                    "title": "Repair replay",
                    "modelId": "grok-4.5",
                    "updatedAt": "2026-08-17T12:34:56Z",
                ],
                [
                    "id": "session-2",
                    "_meta": [
                        "modelId": "open-model",
                        "updatedAt": "2026-08-17T12:35:56.123Z",
                    ],
                ],
            ],
            "nextCursor": "page-2",
        ])

        XCTAssertEqual(page.sessions.map(\.sessionID), ["session-1", "session-2"])
        XCTAssertEqual(page.sessions.map(\.modelID), ["grok-4.5", "open-model"])
        XCTAssertNotNil(page.sessions[0].updatedAt)
        XCTAssertNotNil(page.sessions[1].updatedAt)
        XCTAssertEqual(page.nextCursor, "page-2")
    }

    private enum FakeBehavior {
        case official
        case methodNotFound
    }

    private struct FakeAgentFixture {
        let root: URL
        let script: URL
        let log: URL
    }

    private func makeFakeAgent(version: String, behavior: FakeBehavior) throws -> FakeAgentFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-acp-control-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("fake-grok")
        let log = root.appendingPathComponent("rpc.log")
        let usageResponse: String = switch behavior {
        case .official:
            #"printf '{"jsonrpc":"2.0","id":%s,"result":{"usage":{"inputTokens":100,"outputTokens":10,"totalTokens":110,"numTurns":1,"modelCalls":1,"modelUsage":{"grok-4.5":{"inputTokens":100,"outputTokens":10,"totalTokens":110,"modelCalls":1}}}}}\n' "$id""#
        case .methodNotFound:
            #"printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"Method not found"}}\n' "$id""#
        }
        let body = """
        #!/bin/sh
        while IFS= read -r line; do
          printf '%s\n' "$line" >> '\(log.path)'
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\\1/')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"_meta":{"agentVersion":"\(version)","modelState":{"currentModelId":"grok-4.5","availableModels":[{"modelId":"grok-4.5","name":"Grok 4.5"}]}}}}\n' "$id" ;;
            *'"method":"session/new"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"typed-backend","models":{"currentModelId":"grok-4.5","availableModels":[{"modelId":"grok-4.5","name":"Grok 4.5"}]}}}\n' "$id" ;;
            *'"method":"x.ai/models/list"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"result":{"currentModelId":"grok-4.5","availableModels":[{"modelId":"grok-4.5","name":"Grok 4.5","_meta":{"totalContextTokens":131072}},{"modelId":"open-model","name":"Open Model"}]}}}\n' "$id" ;;
            *'"method":"x.ai/session/usage"'*) \(usageResponse) ;;
            *'"method":"x.ai/session/info"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"result":{"sessionId":"typed-backend","cwd":"\(root.path)","agentName":"grok-build","model":"grok-4.5","turns":1,"turnIndex":0,"context":{"used":100,"total":131072,"usagePct":1}}}}\n' "$id" ;;
            *'"method":"x.ai/session/updates"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"updates":[{"timestamp":1,"method":"session/update","params":{"sessionId":"child-123","update":{"sessionUpdate":"tool_call_update","toolCallId":"tool-1","status":"completed","rawInput":{"toolName":"first_tool"}}}},{"timestamp":2,"method":"_x.ai/session/update","params":{"sessionId":"child-123","update":{"sessionUpdate":"tool_call_update","toolCallId":"tool-2","status":"completed","rawInput":{"toolName":"second_tool"}}}}],"totalCount":2,"hasMore":false,"promptStarts":[]}}\n' "$id" ;;
          esac
        done
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return FakeAgentFixture(root: root, script: script, log: log)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
