import Foundation
import XCTest
@testable import GrokBuild

final class GrokAuthenticationTests: XCTestCase {
    func testSignedInParserKeepsOnlyCoarseSource() {
        let result = GrokCLIResult(
            stdout: "You are logged in with grok.com.\nDefault model: grok-4.5",
            stderr: "",
            exitCode: 0
        )
        XCTAssertEqual(GrokAuthentication.status(from: result), .signedIn(source: "grok.com"))
    }

    func testSignedOutAndUnknownResultsAreSeparated() {
        XCTAssertEqual(
            GrokAuthentication.status(from: GrokCLIResult(
                stdout: "Authentication required. Run grok login.",
                stderr: "",
                exitCode: 1
            )),
            .signedOut
        )
        XCTAssertEqual(
            GrokAuthentication.status(from: GrokCLIResult(
                stdout: "unexpected future format containing account@example.test",
                stderr: "",
                exitCode: 0
            )),
            .unavailable
        )
    }

    func testLoginCommandPinsResolvedCLIAndOAuthFlag() {
        let url = URL(fileURLWithPath: "/Applications/Grok Build/bin/grok")
        XCTAssertEqual(
            GrokAuthentication.loginCommand(cliURL: url),
            "'/Applications/Grok Build/bin/grok' login --oauth"
        )
        XCTAssertEqual(GrokAuthentication.shellQuote("a'b"), "'a'\\''b'")
        XCTAssertNil(GrokAuthentication.loginCommand(cliURL: nil))
    }
}
