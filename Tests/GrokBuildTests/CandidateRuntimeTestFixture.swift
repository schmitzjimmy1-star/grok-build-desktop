import CryptoKit
import Foundation
import XCTest
@testable import GrokBuild

struct CandidateRuntimeTestFixture {
    static let sourceSHA = "abcdef0123456789abcdef0123456789abcdef01"
    static let designatedRequirement = "identifier \"com.grokbuild.fixture\" and anchor apple generic"

    let container: URL
    let digestDirectory: URL
    let candidate: URL
    let provenance: URL
    let selection: URL
    let cliBuild: String
    let observedTeamIdentifier: String
    let observedDesignatedRequirement: String

    static func make(sourceExecutable: String = "/bin/echo") throws -> Self {
        try makeFixture { staged, _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
            process.arguments = [sourceExecutable, "-thin", "arm64e", "-output", staged.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CocoaError(.executableLoad)
            }
        }
    }

    static func makeTeamSigned(sourceExecutable: String = "/bin/echo") throws -> Self {
        guard let identity = availableSigningIdentity() else {
            throw XCTSkip("No local Apple Development signing identity is available")
        }
        return try makeFixture(signingIdentity: identity, useObservedSigning: true) { staged, _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
            process.arguments = [sourceExecutable, "-thin", "arm64e", "-output", staged.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CocoaError(.executableLoad)
            }
        }
    }

    static func makeShellWrapper(script: URL) throws -> Self {
        try makeFixture { staged, container in
            let source = container.appendingPathComponent("fixture-wrapper.c")
            let escaped = script.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            try """
            #include <unistd.h>
            int main(void) {
                execl("/bin/sh", "sh", "\(escaped)", (char *)0);
                return 127;
            }
            """.write(to: source, atomically: true, encoding: .utf8)
            let compiler = Process()
            compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            compiler.arguments = ["--sdk", "macosx", "clang", "-arch", "arm64", source.path, "-o", staged.path]
            try compiler.run()
            compiler.waitUntilExit()
            guard compiler.terminationStatus == 0 else {
                throw CocoaError(.executableLoad)
            }
        }
    }

    static func makeTermIgnoringExecutable() throws -> Self {
        try makeFixture { staged, container in
            let source = container.appendingPathComponent("fixture-ignore-term.c")
            try """
            #include <signal.h>
            #include <unistd.h>
            int main(void) {
                signal(SIGTERM, SIG_IGN);
                write(STDOUT_FILENO, "R", 1);
                for (;;) pause();
            }
            """.write(to: source, atomically: true, encoding: .utf8)
            let compiler = Process()
            compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            compiler.arguments = ["--sdk", "macosx", "clang", "-arch", "arm64", source.path, "-o", staged.path]
            try compiler.run()
            compiler.waitUntilExit()
            guard compiler.terminationStatus == 0 else {
                throw CocoaError(.executableLoad)
            }
        }
    }

    private static func makeFixture(
        signingIdentity: String = "-",
        useObservedSigning: Bool = false,
        build: (URL, URL) throws -> Void
    ) throws -> Self {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokbuild-candidate-shared-fixture-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: container.path)

        let staged = container.appendingPathComponent("staged")
        try build(staged, container)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", signingIdentity, staged.path]
        try signer.run()
        signer.waitUntilExit()
        guard signer.terminationStatus == 0 else { throw CocoaError(.executableLoad) }

        let observedTeam: String
        let observedRequirement: String
        if useObservedSigning {
            observedTeam = try codesignValue(staged, arguments: ["-d", "--verbose=4"], prefix: "TeamIdentifier=")
            observedRequirement = try codesignValue(staged, arguments: ["-d", "-r-"], prefix: "designated => ")
            guard observedTeam == GrokCandidateRuntimeAuthority.expectedTeamIdentifier else {
                throw CocoaError(.executableLoad)
            }
        } else {
            observedTeam = GrokCandidateRuntimeAuthority.expectedTeamIdentifier
            observedRequirement = designatedRequirement
        }

        let binaryData = try Data(contentsOf: staged)
        let binarySHA = sha256(binaryData)
        let digestDirectory = container.appendingPathComponent(binarySHA, isDirectory: true)
        try FileManager.default.createDirectory(at: digestDirectory, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: digestDirectory.path)
        let candidate = digestDirectory.appendingPathComponent("grok")
        try FileManager.default.moveItem(at: staged, to: candidate)
        let cliBuild = "1.0.5 (\(sourceSHA.prefix(7)))"
        let provenance = digestDirectory.appendingPathComponent("candidate-provenance.json")
        let zeros = String(repeating: "0", count: 64)
        let document: [String: Any] = [
            "schemaVersion": 1,
            "source": [
                "officialBaseSHA": String(repeating: "1", count: 40),
                "upstreamReplayBaseSHA": String(repeating: "2", count: 40),
                "forkSourceSHA": sourceSHA,
                "sourceRev": String(repeating: "3", count: 40),
                "cargoLockSHA256": zeros,
            ],
            "toolchain": [
                "rustVersion": "rustc 1.94.0 (fixture)",
                "cargoVersion": "cargo 1.94.0 (fixture)",
                "dotslashVersion": "DotSlash 0.5.7",
                "rustcSHA256": zeros,
                "cargoSHA256": zeros,
                "dotslashSHA256": zeros,
                "targetTriple": "aarch64-apple-darwin",
                "architecture": "arm64",
            ],
            "build": [
                "preBuildCommand": [
                    "cargo", "clean", "--target-dir", "<candidate-target>", "--profile", "release-dist",
                    "-p", "xai-grok-pager-bin",
                ],
                "command": [
                    "cargo", "build", "--locked", "--profile", "release-dist", "-p",
                    "xai-grok-pager-bin", "--features", "release-dist",
                ],
                "environment": [
                    "clearEnvironment": true,
                    "home": "<account-home>",
                    "path": ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "<dotslash-directory>"],
                    "cargoHome": "<account-home>/.cargo",
                    "rustupHome": "<account-home>/.rustup",
                    "rustc": "<pinned-rustc>",
                    "cargoTargetDir": "<candidate-target>",
                    "cargoIncremental": false,
                    "locale": "C",
                    "temporaryDirectory": "/private/tmp",
                ],
                "profile": "release-dist",
                "package": "xai-grok-pager-bin",
                "features": ["release-dist"],
            ],
            "binary": [
                "artifactName": "xai-grok-pager",
                "sha256": binarySHA,
                "sizeBytes": binaryData.count,
                "architecture": "arm64",
                "expectedVersionWithCommit": cliBuild,
                "expectedACPCLIBuild": cliBuild,
                "observedVersionWithCommit": cliBuild,
            ],
            "signing": [
                "state": "signed",
                "strictVerification": true,
                "teamIdentifier": observedTeam,
                "designatedRequirement": observedRequirement,
            ],
        ]
        try writeJSON(document, to: provenance)
        let selection = container.appendingPathComponent("runtime-selection.json")
        try writeJSON([
            "schemaVersion": 1,
            "runtimeRoot": container.path,
            "candidatePath": candidate.path,
            "provenancePath": provenance.path,
            "provenanceSHA256": sha256(try Data(contentsOf: provenance)),
        ], to: selection)
        return Self(
            container: container,
            digestDirectory: digestDirectory,
            candidate: candidate,
            provenance: provenance,
            selection: selection,
            cliBuild: cliBuild,
            observedTeamIdentifier: observedTeam,
            observedDesignatedRequirement: observedRequirement
        )
    }

    private static func availableSigningIdentity() -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-identity", "-v", "-p", "codesigning"]
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try? output.fileHandleForReading.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let match = text.range(of: #"[0-9A-F]{40}"#, options: .regularExpression) else { return nil }
        return String(text[match])
    }

    private static func codesignValue(
        _ executable: URL,
        arguments: [String],
        prefix: String
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments + [executable.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try output.fileHandleForReading.readToEnd() else {
            throw CocoaError(.executableLoad)
        }
        let text = String(decoding: data, as: UTF8.self)
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
            throw CocoaError(.executableLoad)
        }
        return String(line.dropFirst(prefix.count))
    }

    static func installSignatureOverride() {
        GrokCandidateRuntimeAuthority.signatureVerifierOverrideForTests = { _ in
            GrokCandidateSignatureReceipt(
                teamIdentifier: GrokCandidateRuntimeAuthority.expectedTeamIdentifier,
                designatedRequirement: designatedRequirement
            )
        }
    }

    private static func writeJSON(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
