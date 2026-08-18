import GrokBuildProviderAuthCore
import XCTest

final class ProviderAuthHelperTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testProviderIDsAreStrictAndNamespacedForOfficialConfig() {
        XCTAssertTrue(ProviderAuthContract.isValidProviderID("openrouter"))
        XCTAssertTrue(ProviderAuthContract.isValidProviderID("team.gateway-1"))
        XCTAssertFalse(ProviderAuthContract.isValidProviderID("../openrouter"))
        XCTAssertFalse(ProviderAuthContract.isValidProviderID("open router"))
        XCTAssertEqual(
            ProviderAuthContract.officialProviderID(for: "openrouter"),
            "grokbuild.saved.openrouter"
        )
        XCTAssertEqual(
            ProviderAuthContract.appProviderID(from: "grokbuild.saved.openrouter"),
            "openrouter"
        )
        XCTAssertNil(ProviderAuthContract.appProviderID(from: "someone-elses-provider"))
        XCTAssertEqual(
            ProviderAuthContract.officialLocalProviderID(for: "foo"),
            "grokbuild.local.foo"
        )
        XCTAssertNotEqual(
            ProviderAuthContract.officialProviderID(for: "local.foo"),
            ProviderAuthContract.officialLocalProviderID(for: "foo")
        )
        XCTAssertEqual(
            ProviderAuthContract.appProviderID(from: "grokbuild.saved.local.foo"),
            "local.foo"
        )
        XCTAssertNil(ProviderAuthContract.appProviderID(from: "grokbuild.local.foo"))
        XCTAssertEqual(ProviderAuthContract.localModelID(from: "grokbuild.local.foo"), "foo")
    }

    func testHelperAcceptsExactlyOneValidatedProviderArgument() throws {
        XCTAssertEqual(
            try ProviderAuthHelperContract.providerID(arguments: ["helper", "openrouter"]),
            "openrouter"
        )
        XCTAssertThrowsError(
            try ProviderAuthHelperContract.providerID(arguments: ["helper"])
        )
        XCTAssertThrowsError(
            try ProviderAuthHelperContract.providerID(arguments: ["helper", "../escape"])
        )
        XCTAssertThrowsError(
            try ProviderAuthHelperContract.providerID(arguments: ["helper", "openrouter", "extra"])
        )
    }

    func testHelperReturnsOnlyTrimmedCredentialAndFailsClosedWhenUnavailable() throws {
        let token = try ProviderAuthHelperContract.loadCredential(providerID: "openrouter") { id in
            XCTAssertEqual(id, "openrouter")
            return "  synthetic-token  \n"
        }
        XCTAssertEqual(token, "synthetic-token")

        XCTAssertThrowsError(
            try ProviderAuthHelperContract.loadCredential(providerID: "openrouter") { _ in nil }
        )
        XCTAssertThrowsError(
            try ProviderAuthHelperContract.loadCredential(providerID: "openrouter") { _ in "  \n" }
        )
    }

    func testBuiltHelperNegativePathsEmitNoCredentialBytes() throws {
        let helper = repositoryRoot.appendingPathComponent(".build/debug/GrokBuildProviderAuthHelper")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path))
        for arguments in [[], ["../invalid"], ["missing-fixture-\(UUID().uuidString)"]] {
            let process = Process()
            process.executableURL = helper
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let out = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertNotEqual(process.terminationStatus, 0)
            XCTAssertTrue(out.isEmpty)
            XCTAssertEqual(err, "Provider credential unavailable.\n")
        }
    }

    func testHelperIsRequiredCopiedAndNestedSignedByBothBuildPipelines() throws {
        let manifest = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let releaseBuild = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/build-macos-app.sh"),
            encoding: .utf8
        )
        let devBuild = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/build-dev-app.sh"),
            encoding: .utf8
        )
        let signing = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/codesign-app-bundle.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(manifest.contains("GrokBuildProviderAuthHelper"))
        XCTAssertTrue(releaseBuild.contains("ERROR: Missing GrokBuildProviderAuthHelper binary"))
        XCTAssertTrue(devBuild.contains("GrokBuildProviderAuthHelper"))
        XCTAssertTrue(signing.contains("sign_nested \"GrokBuildProviderAuthHelper\""))
    }
}
