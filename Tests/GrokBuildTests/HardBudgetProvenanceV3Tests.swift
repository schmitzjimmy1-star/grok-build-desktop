import Foundation
import XCTest
@testable import GrokBuild

final class HardBudgetProvenanceV3Tests: XCTestCase {
    private typealias V3 = HardBudgetProvenanceV3

    private let golden = "{\"allocationId\":\"allocation-1\",\"campaignId\":\"campaign-v3\",\"campaignPolicy\":{\"absoluteTokenCeiling\":20000000,\"allocatableTokenCeiling\":19000000,\"schemaVersion\":3,\"unreachableReserveTokens\":1000000},\"candidate\":{\"binarySha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"cliBuild\":\"1.0.5 (003f955)\",\"sourceCommitSha\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"configIdentity\":{\"configProjectionSha256\":\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"generation\":7,\"managedProviderId\":\"openrouter\",\"sourceKind\":\"resolved-managed-provider\"},\"route\":{\"allocationTokenCeiling\":20000,\"apiBackend\":\"responses\",\"authScheme\":\"bearer\",\"conservativeRequestBoundTokens\":12288,\"credentialTransport\":\"fd_v1\",\"endpointSha256\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"maxFinalSerializedPayloadBytes\":8192,\"maxModelCalls\":1,\"maxOutputTokens\":4096,\"multimodalForbidden\":true,\"providerFacingModel\":\"openai/gpt-4.1-mini\",\"providerId\":\"openrouter\",\"redirectDisabled\":true,\"remoteContextForbidden\":true,\"retryDisabled\":true,\"routeId\":\"route-1\",\"textOnly\":true,\"toolIsolation\":{\"allowedToolIds\":[\"GrokBuild:read_file\",\"GrokBuild:task\"],\"authProviderHelpersDisabled\":true,\"externalMcpDisabled\":true,\"hooksDisabled\":true,\"lspDisabled\":true,\"pluginsDisabled\":true,\"protectedAuthorityFs\":true,\"samplerTransportRetriesDisabled\":true,\"schedulerDisabled\":true,\"terminalDisabled\":true,\"workflowsDisabled\":true,\"workspaceFsConfined\":true}},\"schemaVersion\":1,\"serializerVersion\":1}"

    func testRustGoldenDocumentBytesAndDigestMatchExactly() throws {
        let provenance = try V3.Provenance.fromCanonicalJSON(Data(golden.utf8))
        XCTAssertEqual(String(decoding: try provenance.canonicalBytes(), as: UTF8.self), golden)
        XCTAssertEqual(try provenance.sha256(), "5052a5285a35ea96151340259475a69351ed162c8308a8f2166b453a5720f950")
        XCTAssertEqual(
            String(decoding: try V3.CampaignPolicy.exact.canonicalBytes(), as: UTF8.self),
            "{\"absoluteTokenCeiling\":20000000,\"allocatableTokenCeiling\":19000000,\"schemaVersion\":3,\"unreachableReserveTokens\":1000000}"
        )
    }

    func testStrictCanonicalParserRejectsMissingExtraReorderedWhitespaceAndVersions() throws {
        let missing = golden.replacingOccurrences(of: ",\"serializerVersion\":1", with: "")
        let extra = golden.replacingOccurrences(of: "}", with: ",\"opaqueDigest\":\"ignored\"}")
        let campaign = "\"campaignId\":\"campaign-v3\","
        let reordered = "{" + campaign + golden
            .replacingOccurrences(of: campaign, with: "")
            .dropFirst()
        let whitespace = golden.replacingOccurrences(of: ":", with: ": ", options: [], range: golden.startIndex..<golden.index(golden.startIndex, offsetBy: 20))
        let wrongVersion = golden.replacingOccurrences(of: "\"serializerVersion\":1", with: "\"serializerVersion\":2")

        for hostile in [missing, extra, reordered, whitespace, wrongVersion] {
            XCTAssertThrowsError(try V3.Provenance.fromCanonicalJSON(Data(hostile.utf8)))
        }
    }

    func testExactPolicyArithmeticASCIIAndAuthSchemeAreFailClosed() throws {
        let oldPolicy = golden.replacingOccurrences(of: "20000000", with: "4000000")
        let overflow = golden.replacingOccurrences(of: "\"maxFinalSerializedPayloadBytes\":8192", with: "\"maxFinalSerializedPayloadBytes\":18446744073709551615")
        let unicode = golden.replacingOccurrences(of: "1.0.5", with: "1.0.é")
        let invalidAuth = golden.replacingOccurrences(of: "\"authScheme\":\"bearer\"", with: "\"authScheme\":\"oauth\"")

        for hostile in [oldPolicy, overflow, unicode, invalidAuth] {
            XCTAssertThrowsError(try V3.Provenance.fromCanonicalJSON(Data(hostile.utf8)))
        }
        XCTAssertEqual(V3.canonicalAuthHeaderNames("bearer"), ["authorization"])
        XCTAssertEqual(V3.canonicalAuthHeaderNames("x_api_key"), ["x-api-key"])
        XCTAssertEqual(V3.canonicalAuthHeaderNames("bearer_and_x_api_key"), ["authorization", "x-api-key"])
        XCTAssertNil(V3.canonicalAuthHeaderNames("oauth"))

        let wrongKind = golden.replacingOccurrences(
            of: "\"sourceKind\":\"resolved-managed-provider\"",
            with: "\"sourceKind\":\"toml\""
        )
        let providerMismatch = golden.replacingOccurrences(
            of: "\"managedProviderId\":\"openrouter\"",
            with: "\"managedProviderId\":\"other-provider\""
        )
        let delInBuild = golden.replacingOccurrences(of: "1.0.5 (003f955)", with: "1.0.5\u{007f}")
        for hostile in [wrongKind, providerMismatch, delInBuild] {
            XCTAssertThrowsError(try V3.Provenance.fromCanonicalJSON(Data(hostile.utf8)))
        }
    }

    func testDormantExecutionCapabilityRequiresNestedAuthorityAndDerivedHeaders() throws {
        let provenance = try V3.Provenance.fromCanonicalJSON(Data(golden.utf8))
        let expectation = V3.ExecutionExpectation(
            campaignID: provenance.campaignID,
            allocationID: provenance.allocationID,
            candidate: provenance.candidate,
            route: provenance.route
        )
        let provenanceObject = try JSONSerialization.jsonObject(with: Data(golden.utf8))
        let capability: [String: Any] = [
            "capabilityVersion": 3,
            "armed": true,
            "cliBuild": "1.0.5 (003f955)",
            "v3Authority": [
                "authorityVersion": 3,
                "provenance": provenanceObject,
                "provenanceSha256": try provenance.sha256(),
            ],
        ]
        let parsed = V3.ExecutionCapability.parse(capability, expectation: expectation)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.authHeaderNames, ["authorization"])
        XCTAssertNil(GrokBuildHardTokenBudgetCapability.parse(capability), "v2 execution parsing must not upgrade a v3 document")

        var extraNested = capability
        var extraAuthority = try XCTUnwrap(extraNested["v3Authority"] as? [String: Any])
        extraAuthority["authHeaderNames"] = ["authorization"]
        extraNested["v3Authority"] = extraAuthority
        XCTAssertNil(V3.ExecutionCapability.parse(extraNested, expectation: expectation))

        var digestMismatch = capability
        var mismatchedAuthority = try XCTUnwrap(digestMismatch["v3Authority"] as? [String: Any])
        mismatchedAuthority["provenanceSha256"] = String(repeating: "0", count: 64)
        digestMismatch["v3Authority"] = mismatchedAuthority
        XCTAssertNil(V3.ExecutionCapability.parse(digestMismatch, expectation: expectation))

        let legacyFourField: [String: Any] = [
            "capabilityVersion": 3,
            "provenanceCanonicalJson": golden,
            "provenanceSha256": try provenance.sha256(),
            "authHeaderNames": ["authorization"],
        ]
        XCTAssertNil(V3.ExecutionCapability.parse(legacyFourField, expectation: expectation))

        let combinedGolden = golden
            .replacingOccurrences(of: "\"authScheme\":\"bearer\"", with: "\"authScheme\":\"bearer_and_x_api_key\"")
            .replacingOccurrences(of: "\"apiBackend\":\"responses\"", with: "\"apiBackend\":\"messages\"")
        let combinedProvenance = try V3.Provenance.fromCanonicalJSON(Data(combinedGolden.utf8))
        let combinedExpectation = V3.ExecutionExpectation(
            campaignID: combinedProvenance.campaignID,
            allocationID: combinedProvenance.allocationID,
            candidate: combinedProvenance.candidate,
            route: combinedProvenance.route
        )
        let combinedObject = try JSONSerialization.jsonObject(with: Data(combinedGolden.utf8))
        let combinedCapability: [String: Any] = [
            "capabilityVersion": 3,
            "v3Authority": [
                "authorityVersion": 3,
                "provenance": combinedObject,
                "provenanceSha256": try combinedProvenance.sha256(),
            ],
        ]
        XCTAssertEqual(
            V3.ExecutionCapability.parse(combinedCapability, expectation: combinedExpectation)?.authHeaderNames,
            ["authorization", "x-api-key"]
        )

        let bound = try XCTUnwrap(GrokArmedCredentialAuthorizationV3(
            provenance: provenance,
            expectedProvenanceSHA256: try provenance.sha256()
        ))
        XCTAssertEqual(bound.keychainAccount, "openrouter")
        XCTAssertEqual(bound.managedProviderID, "openrouter")
        XCTAssertEqual(bound.authScheme, "bearer")
        XCTAssertEqual(bound.authHeaderNames, ["authorization"])
        XCTAssertNil(GrokArmedCredentialAuthorizationV3(
            provenance: provenance,
            expectedProvenanceSHA256: String(repeating: "0", count: 64)
        ))
    }

    func testInitializeProvenanceParserRequiresNestedAuthorityAndMatchingDigest() throws {
        let provenance = try V3.Provenance.fromCanonicalJSON(Data(golden.utf8))
        let provenanceObject = try JSONSerialization.jsonObject(with: Data(golden.utf8))
        let capability: [String: Any] = [
            "capabilityVersion": 3,
            "v3Authority": [
                "authorityVersion": 3,
                "provenance": provenanceObject,
                "provenanceSha256": try provenance.sha256(),
            ],
        ]
        XCTAssertEqual(
            V3.ExecutionCapability.parseInitializeProvenance(capability)?.campaignID,
            "campaign-v3"
        )
        var drifted = capability
        var authority = try XCTUnwrap(drifted["v3Authority"] as? [String: Any])
        authority["provenanceSha256"] = String(repeating: "0", count: 64)
        drifted["v3Authority"] = authority
        XCTAssertNil(V3.ExecutionCapability.parseInitializeProvenance(drifted))
        XCTAssertNil(V3.ExecutionCapability.parseInitializeProvenance(nil))

        let expectation = ArmedV3DispatchExpectation(
            campaignID: provenance.campaignID,
            allocationID: provenance.allocationID,
            selectedModelID: "gpt-41-mini",
            managedProviderID: provenance.route.providerID,
            providerFacingModel: provenance.route.providerFacingModel,
            authScheme: provenance.route.authScheme,
            apiBackend: provenance.route.apiBackend,
            authBoundary: .officialHelper,
            candidate: GrokCandidateRuntimeIdentity(
                binaryPath: "/tmp/pager",
                provenancePath: "/tmp/prov.json",
                provenanceSHA256: String(repeating: "b", count: 64),
                binarySHA256: provenance.candidate.binarySHA256,
                binarySize: 1,
                architecture: "arm64",
                sourceSHA: provenance.candidate.sourceCommitSHA,
                cliBuild: provenance.candidate.cliBuild,
                signature: GrokCandidateSignatureReceipt(
                    teamIdentifier: "DD2GCQJVB4",
                    designatedRequirement: "fixture"
                )
            ),
            frozenRoute: AcceptanceHardBudgetRoute(
                model: provenance.route.providerFacingModel,
                endpointSHA256: provenance.route.endpointSHA256,
                apiBackend: provenance.route.apiBackend,
                requestBoundTokens: 12_288,
                maxPayloadBytes: 8_192,
                maxOutputTokens: 4_096,
                boundProvenanceSHA256: try provenance.sha256(),
                managedProviderID: provenance.route.providerID,
                authScheme: provenance.route.authScheme
            ),
            credentialAuthorizationV3: try XCTUnwrap(GrokArmedCredentialAuthorizationV3(
                managedProviderID: provenance.route.providerID,
                authScheme: provenance.route.authScheme,
                expectedProvenanceSHA256: try provenance.sha256()
            ))
        )
        XCTAssertTrue(expectation.admitsInitializeMetadata(capability))
        XCTAssertFalse(expectation.admitsInitializeMetadata(drifted))
    }
}
