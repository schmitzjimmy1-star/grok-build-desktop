import CryptoKit
import Foundation
import XCTest
@testable import GrokBuild

struct CandidateRuntimeTestFixture {
    enum CredentialReceiverBehavior: Int {
        case success = 0
        case malformedAcknowledgement = 1
        case timeout = 2
        case trailingReadyByte = 3
        case forkBeforeClose = 4
        case slowDripAcknowledgement = 5
    }
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

    static func makeCredentialReceiverExecutable(
        behavior: CredentialReceiverBehavior = .success
    ) throws -> Self {
        let behaviorValue = behavior.rawValue
        let acknowledgementType = behavior == .malformedAcknowledgement ? 9 : 2
        return try makeFixture { staged, container in
            let source = container.appendingPathComponent("fixture-credential-receiver.c")
            try """
            #include <errno.h>
            #include <fcntl.h>
            #include <poll.h>
            #include <stdint.h>
            #include <stdio.h>
            #include <stdlib.h>
            #include <string.h>
            #include <sys/socket.h>
            #include <sys/stat.h>
            #include <sys/types.h>
            #include <sys/wait.h>
            #include <unistd.h>

            extern char **environ;
            enum { receiver_fd = 198, identity_fd = 197, header_size = 48, max_payload = 4096 };
            static const unsigned char magic[8] = {'G','B','C','T',0,0,0,1};

            static int wait_readable(int fd) {
                struct pollfd p = { .fd = fd, .events = POLLIN | POLLHUP };
                int r;
                /* Fresh 4s per read so a DEBUG parent interphase delay of 1.8s
                   cannot starve COMMIT on a loaded CI runner. Hostile parent
                   phases still fail at the Swift 2s budget. */
                do { r = poll(&p, 1, 4000); } while (r < 0 && errno == EINTR);
                return r > 0 && (p.revents & (POLLIN | POLLHUP));
            }
            static int read_exact(int fd, unsigned char *out, size_t count) {
                size_t offset = 0;
                while (offset < count) {
                    if (!wait_readable(fd)) return 0;
                    ssize_t n = read(fd, out + offset, count - offset);
                    if (n <= 0) return 0;
                    offset += (size_t)n;
                }
                return 1;
            }
            static int write_exact(int fd, const unsigned char *bytes, size_t count) {
                size_t offset = 0;
                while (offset < count) {
                    ssize_t n = write(fd, bytes + offset, count - offset);
                    if (n <= 0) return 0;
                    offset += (size_t)n;
                }
                return 1;
            }
            static uint32_t length_from(const unsigned char *header) {
                return ((uint32_t)header[44] << 24) | ((uint32_t)header[45] << 16)
                    | ((uint32_t)header[46] << 8) | (uint32_t)header[47];
            }
            static void make_header(unsigned char *out, unsigned char type,
                                    const unsigned char *nonce, uint32_t length) {
                memset(out, 0, header_size);
                memcpy(out, magic, 8);
                out[8] = type;
                memcpy(out + 12, nonce, 32);
                out[44] = (unsigned char)(length >> 24);
                out[45] = (unsigned char)(length >> 16);
                out[46] = (unsigned char)(length >> 8);
                out[47] = (unsigned char)length;
            }
            static int contains_bytes(const char *haystack, const unsigned char *needle, size_t count) {
                size_t length = strlen(haystack);
                if (count == 0 || length < count) return 0;
                for (size_t i = 0; i + count <= length; i++) {
                    if (memcmp(haystack + i, needle, count) == 0) return 1;
                }
                return 0;
            }
            static int probe_mode(void) {
                errno = 0;
                return fcntl(receiver_fd, F_GETFD) == -1 && errno == EBADF ? 0 : 91;
            }
            static int identity_descriptor_is_private_readonly_regular(void) {
                int flags = fcntl(identity_fd, F_GETFL);
                if (flags < 0 || (flags & O_ACCMODE) != O_RDONLY) return 0;
                struct stat st;
                if (fstat(identity_fd, &st) != 0) return 0;
                if ((st.st_mode & S_IFMT) != S_IFREG) return 0;
                if (st.st_uid != geteuid()) return 0;
                if ((st.st_mode & 077) != 0) return 0;
                if (st.st_nlink != 1) return 0;
                return 1;
            }
            static int fail(int code, unsigned char *payload, size_t count) {
                if (payload) { memset(payload, 0, count); free(payload); }
                close(identity_fd);
                close(receiver_fd);
                return code;
            }

            int main(int argc, char **argv) {
                if (argc == 2 && strcmp(argv[1], "--probe-fd") == 0) return probe_mode();
                int expect_identity = 0;
                for (int i = 1; i < argc; i++) {
                    if (strcmp(argv[i], "stdio") == 0) { expect_identity = 1; break; }
                }
                if (fcntl(receiver_fd, F_SETFD, FD_CLOEXEC) != 0) return 10;
                int descriptor_limit = getdtablesize();
                if (descriptor_limit > 1024) descriptor_limit = 1024;
                for (int fd = 3; fd < descriptor_limit; fd++) {
                    if (fd == receiver_fd) continue;
                    if (fd == identity_fd) {
                        errno = 0;
                        if (expect_identity) {
                            if (!identity_descriptor_is_private_readonly_regular()) return 11;
                        } else if (fcntl(identity_fd, F_GETFD) != -1 || errno != EBADF) {
                            return 11;
                        }
                        continue;
                    }
                    if (fcntl(fd, F_GETFD) != -1 || errno != EBADF) return 11;
                }
                if (getenv("XAI_API_KEY") || getenv("OPENAI_API_KEY")
                    || getenv("DYLD_INSERT_LIBRARIES")) return 29;
                unsigned char header[header_size];
                if (!read_exact(receiver_fd, header, sizeof(header))) return 12;
                if (memcmp(header, magic, 8) != 0 || header[8] != 1
                    || header[9] || header[10] || header[11]) return 13;
                uint32_t length = length_from(header);
                if (length == 0 || length > max_payload) return 14;
                unsigned char *payload = malloc(length);
                if (!payload || !read_exact(receiver_fd, payload, length)) return fail(15, payload, length);

                if (\(behaviorValue) == 2) { sleep(3); return fail(18, payload, length); }
                unsigned char response[header_size];
                make_header(response, \(acknowledgementType), header + 12, length);
                if (\(behaviorValue) == 5) {
                    for (size_t i = 0; i < sizeof(response); i++) {
                        if (write(receiver_fd, response + i, 1) != 1) return fail(28, payload, length);
                        usleep(300000);
                    }
                }
                if (!write_exact(receiver_fd, response, sizeof(response))) return fail(19, payload, length);

                unsigned char commit[header_size];
                if (!read_exact(receiver_fd, commit, sizeof(commit))) return fail(20, payload, length);
                if (memcmp(commit, magic, 8) != 0 || commit[8] != 3
                    || memcmp(commit + 12, header + 12, 32) != 0 || length_from(commit) != 0) {
                    return fail(21, payload, length);
                }
                unsigned char trailing;
                if (!wait_readable(receiver_fd) || read(receiver_fd, &trailing, 1) != 0) return fail(22, payload, length);
                for (int i = 0; i < argc; i++) if (contains_bytes(argv[i], payload, length)) return fail(16, payload, length);
                for (char **entry = environ; *entry; entry++) if (contains_bytes(*entry, payload, length)) return fail(17, payload, length);

                pid_t leaking_child = -1;
                if (\(behaviorValue) == 4) {
                    leaking_child = fork();
                    if (leaking_child == 0) { for (;;) pause(); }
                    if (leaking_child < 0) return fail(23, payload, length);
                    dprintf(STDOUT_FILENO, "D:%d\\n", leaking_child);
                    if (argc > 1) {
                        FILE *receipt = fopen(argv[1], "w");
                        if (!receipt) return fail(26, payload, length);
                        fprintf(receipt, "%d\\n", leaking_child);
                        if (fclose(receipt) != 0) return fail(27, payload, length);
                    }
                }
                memset(payload, 0, length);
                free(payload);
                make_header(response, 4, header + 12, 0);
                if (!write_exact(receiver_fd, response, sizeof(response))) return fail(24, NULL, 0);
                if (\(behaviorValue) == 3) write(receiver_fd, "X", 1);
                if (leaking_child > 0) { for (;;) pause(); }
                shutdown(receiver_fd, SHUT_WR);
                close(receiver_fd);
                close(identity_fd);

                pid_t probe = fork();
                if (probe == 0) {
                    execl(argv[0], argv[0], "--probe-fd", (char *)0);
                    _exit(92);
                }
                int status = 0;
                if (probe < 0 || waitpid(probe, &status, 0) != probe
                    || !WIFEXITED(status) || WEXITSTATUS(status) != 0) return 25;
                write(STDOUT_FILENO, "transport=fd-v1,result=ok\\n", 26);
                return 0;
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
