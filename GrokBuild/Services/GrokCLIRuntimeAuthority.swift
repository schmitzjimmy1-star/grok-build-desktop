import CryptoKit
import Darwin
import Foundation
import Security

struct GrokCandidateSignatureReceipt: Equatable, Sendable {
    let teamIdentifier: String
    let designatedRequirement: String
    let codeDirectoryHash: String

    init(
        teamIdentifier: String,
        designatedRequirement: String,
        codeDirectoryHash: String = ""
    ) {
        self.teamIdentifier = teamIdentifier
        self.designatedRequirement = designatedRequirement
        self.codeDirectoryHash = codeDirectoryHash
    }
}

struct GrokCandidateRuntimeIdentity: Equatable, Sendable {
    let binaryPath: String
    let provenancePath: String
    let provenanceSHA256: String
    let binarySHA256: String
    let binarySize: Int64
    let architecture: String
    let sourceSHA: String
    let cliBuild: String
    let signature: GrokCandidateSignatureReceipt
}

/// One immutable, already-inspected candidate executable. The descriptor keeps
/// the inspected bytes available for revalidation until launch. Darwin cannot
/// execute that descriptor directly, so launch suspends the child before user
/// code and compares the dynamic CodeDirectory hash before allowing it to run.
final class GrokCandidateExecutionLease: @unchecked Sendable, Equatable {
    let identity: GrokCandidateRuntimeIdentity
    fileprivate let descriptor: Int32
    fileprivate let executionPath: String
    private let executionDirectory: String
    private let lock = NSLock()
    private var consumed = false

    fileprivate init(
        identity: GrokCandidateRuntimeIdentity,
        descriptor: Int32,
        executionPath: String,
        executionDirectory: String
    ) {
        self.identity = identity
        self.descriptor = descriptor
        self.executionPath = executionPath
        self.executionDirectory = executionDirectory
    }

    deinit {
        Darwin.close(descriptor)
        _ = Darwin.unlink(executionPath)
        _ = Darwin.rmdir(executionDirectory)
    }

    static func == (lhs: GrokCandidateExecutionLease, rhs: GrokCandidateExecutionLease) -> Bool {
        lhs === rhs || lhs.identity == rhs.identity
    }

    var heldFileRemainsValid: Bool {
        guard let snapshot = GrokCandidateRuntimeAuthority.fileSnapshot(descriptor: descriptor),
              snapshot.size == identity.binarySize,
              snapshot.sha256 == identity.binarySHA256,
              snapshot.architecture == identity.architecture else { return false }
        return true
    }

    fileprivate func claimForSpawn() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else { return false }
        consumed = true
        return true
    }
}

/// The single ordinary-runtime lookup policy. Armed launches never call this
/// resolver: they carry an inspected candidate lease instead. Any acceptance
/// authority argument makes ordinary CLI discovery fail closed across the app.
enum GrokCLIRuntimeResolver {
    static func locateOfficial(
        testOverride: URL? = nil,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> URL? {
        guard !AcceptanceBudgetGuard.isConfigured(arguments: arguments) else { return nil }
        if let testOverride { return testOverride }
        if let path = ProcessInfo.processInfo.environment["GROK_CLI_PATH"], !path.isEmpty {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        for candidate in [
            "\(NSHomeDirectory())/.grok/bin/grok",
            "\(NSHomeDirectory())/bin/grok",
            "/opt/homebrew/bin/grok",
            "/usr/local/bin/grok",
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("grok")
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }
}

enum GrokCandidateRuntimeAuthority {
    static let selectionArgumentPrefix = "--grokbuild-acceptance-runtime-selection-file="
    static let expectedTeamIdentifier = "DD2GCQJVB4"
    static let maximumManifestBytes = 1_048_576
    static let maximumCandidateBytes: Int64 = 536_870_912
    #if arch(arm64)
    static let hostArchitecture = "arm64"
    #elseif arch(x86_64)
    static let hostArchitecture = "x86_64"
    #else
    static let hostArchitecture = "unsupported"
    #endif

    /// Test-only seam. Armed production resolution never consults either legacy
    /// CLI path override; tests may replace only the signature observation for a
    /// disposable Mach-O fixture whose bytes and FD launch remain real.
    static var signatureVerifierOverrideForTests: ((URL) -> GrokCandidateSignatureReceipt?)?

    static func acquireLease(
        selectionPath: String,
        expectedCLIBuild: String
    ) -> GrokCandidateExecutionLease? {
        guard let selectionData = secureReadPrivateFile(path: selectionPath, maximumBytes: maximumManifestBytes),
              let selectionObject = try? JSONSerialization.jsonObject(with: selectionData) as? [String: Any],
              exactKeys(
                selectionObject,
                ["schemaVersion", "runtimeRoot", "candidatePath", "provenancePath", "provenanceSHA256"]
              ),
              selectionObject["schemaVersion"] as? Int == 1,
              let runtimeRoot = selectionObject["runtimeRoot"] as? String,
              let candidatePath = selectionObject["candidatePath"] as? String,
              let provenancePath = selectionObject["provenancePath"] as? String,
              let expectedProvenanceSHA = selectionObject["provenanceSHA256"] as? String,
              isSHA256(expectedProvenanceSHA),
              let provenanceData = secureReadPrivateFile(
                path: provenancePath,
                maximumBytes: maximumManifestBytes
              ),
              sha256(provenanceData) == expectedProvenanceSHA,
              let provenance = try? JSONSerialization.jsonObject(with: provenanceData) as? [String: Any],
              let identity = validateProvenance(
                provenance,
                candidatePath: candidatePath,
                provenancePath: provenancePath,
                expectedCLIBuild: expectedCLIBuild
              ),
              validateRuntimeLayout(
                root: runtimeRoot,
                candidatePath: candidatePath,
                provenancePath: provenancePath,
                binarySHA256: identity.binarySHA256
              ) else { return nil }

        let sourceDescriptor = Darwin.open(candidatePath, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard sourceDescriptor >= 0 else { return nil }
        defer { Darwin.close(sourceDescriptor) }
        guard let snapshot = fileSnapshot(descriptor: sourceDescriptor),
              snapshot.sha256 == identity.binarySHA256,
              snapshot.size == identity.binarySize,
              snapshot.architecture == identity.architecture,
              let executionCopy = createExecutionCopy(
                sourceDescriptor: sourceDescriptor,
                sourceSnapshot: snapshot,
                runtimeRoot: runtimeRoot
              ) else { return nil }
        var keepExecutionCopy = false
        defer {
            if !keepExecutionCopy {
                Darwin.close(executionCopy.descriptor)
                _ = Darwin.unlink(executionCopy.path)
                _ = Darwin.rmdir(executionCopy.directory)
            }
        }
        guard let signature = observedSignature(url: URL(fileURLWithPath: executionCopy.path)),
              signature.teamIdentifier == identity.signature.teamIdentifier,
              signature.designatedRequirement == identity.signature.designatedRequirement,
              let afterSignature = fileSnapshot(descriptor: executionCopy.descriptor),
              afterSignature.size == snapshot.size,
              afterSignature.sha256 == snapshot.sha256,
              afterSignature.architecture == snapshot.architecture else { return nil }
        keepExecutionCopy = true
        let boundIdentity = GrokCandidateRuntimeIdentity(
            binaryPath: identity.binaryPath,
            provenancePath: identity.provenancePath,
            provenanceSHA256: expectedProvenanceSHA,
            binarySHA256: identity.binarySHA256,
            binarySize: identity.binarySize,
            architecture: identity.architecture,
            sourceSHA: identity.sourceSHA,
            cliBuild: identity.cliBuild,
            signature: signature
        )
        return GrokCandidateExecutionLease(
            identity: boundIdentity,
            descriptor: executionCopy.descriptor,
            executionPath: executionCopy.path,
            executionDirectory: executionCopy.directory
        )
    }

    private struct ExecutionCopy {
        let directory: String
        let path: String
        let descriptor: Int32
    }

    /// Darwin has no usable descriptor-exec primitive. Seal the already held
    /// bytes into a random owner-private one-use pathname, retain that copy's FD,
    /// and later verify the suspended live CodeDirectory before user code runs.
    private static func createExecutionCopy(
        sourceDescriptor: Int32,
        sourceSnapshot: FileSnapshot,
        runtimeRoot: String
    ) -> ExecutionCopy? {
        let directory = URL(fileURLWithPath: runtimeRoot, isDirectory: true)
            .appendingPathComponent(".grokbuild-exec-\(UUID().uuidString)", isDirectory: true)
            .path
        guard Darwin.mkdir(directory, mode_t(0o700)) == 0 else { return nil }
        let path = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("grok")
            .path
        let output = Darwin.open(
            path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o700)
        )
        guard output >= 0 else {
            _ = Darwin.rmdir(directory)
            return nil
        }
        var succeeded = false
        defer {
            Darwin.close(output)
            if !succeeded {
                _ = Darwin.unlink(path)
                _ = Darwin.rmdir(directory)
            }
        }
        var offset: off_t = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while offset < sourceSnapshot.size {
            let desired = min(buffer.count, Int(sourceSnapshot.size - offset))
            let readCount = buffer.withUnsafeMutableBytes {
                pread(sourceDescriptor, $0.baseAddress, desired, offset)
            }
            guard readCount > 0 else { return nil }
            var written = 0
            while written < readCount {
                let writeCount = buffer.withUnsafeBytes {
                    Darwin.write(output, $0.baseAddress!.advanced(by: written), readCount - written)
                }
                guard writeCount > 0 else { return nil }
                written += writeCount
            }
            offset += off_t(readCount)
        }
        guard fsync(output) == 0 else { return nil }
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0,
              let copiedSnapshot = fileSnapshot(descriptor: descriptor),
              copiedSnapshot.size == sourceSnapshot.size,
              copiedSnapshot.sha256 == sourceSnapshot.sha256,
              copiedSnapshot.architecture == sourceSnapshot.architecture else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            return nil
        }
        succeeded = true
        return ExecutionCopy(directory: directory, path: path, descriptor: descriptor)
    }

    private static func validateProvenance(
        _ document: [String: Any],
        candidatePath: String,
        provenancePath: String,
        expectedCLIBuild: String
    ) -> GrokCandidateRuntimeIdentity? {
        guard exactKeys(document, ["schemaVersion", "source", "toolchain", "build", "binary", "signing"]),
              document["schemaVersion"] as? Int == 1 else { return nil }
        guard let source = document["source"] as? [String: Any],
              exactKeys(source, ["officialBaseSHA", "upstreamReplayBaseSHA", "forkSourceSHA", "sourceRev", "cargoLockSHA256"]),
              let forkSourceSHA = source["forkSourceSHA"] as? String,
              isGitSHA(forkSourceSHA),
              (source["cargoLockSHA256"] as? String).map(isSHA256) == true else { return nil }
        let sourceSHAsAreValid = ["officialBaseSHA", "upstreamReplayBaseSHA", "sourceRev"].allSatisfy { key in
            (source[key] as? String).map(isGitSHA) == true
        }
        guard sourceSHAsAreValid else { return nil }

        guard let toolchain = document["toolchain"] as? [String: Any],
              exactKeys(toolchain, [
                "rustVersion", "cargoVersion", "dotslashVersion", "rustcSHA256", "cargoSHA256",
                "dotslashSHA256", "targetTriple", "architecture"
              ]),
              let architecture = toolchain["architecture"] as? String,
              architecture == hostArchitecture,
              (toolchain["rustVersion"] as? String)?.hasPrefix("rustc 1.94.0 ") == true,
              (toolchain["cargoVersion"] as? String)?.hasPrefix("cargo 1.94.0 ") == true,
              toolchain["dotslashVersion"] as? String == "DotSlash 0.5.7",
              toolchain["targetTriple"] as? String == (
                architecture == "arm64" ? "aarch64-apple-darwin" : "x86_64-apple-darwin"
              ) else { return nil }
        let toolHashesAreValid = ["rustcSHA256", "cargoSHA256", "dotslashSHA256"].allSatisfy { key in
            (toolchain[key] as? String).map(isSHA256) == true
        }
        guard toolHashesAreValid,
              let build = document["build"] as? [String: Any],
              validateBuild(build) else { return nil }

        guard let binary = document["binary"] as? [String: Any],
              exactKeys(binary, [
                "artifactName", "sha256", "sizeBytes", "architecture", "expectedVersionWithCommit",
                "expectedACPCLIBuild", "observedVersionWithCommit"
              ]),
              binary["artifactName"] as? String == "xai-grok-pager",
              let binarySHA = binary["sha256"] as? String,
              isSHA256(binarySHA),
              let binarySize = binary["sizeBytes"] as? Int,
              binarySize > 0,
              Int64(binarySize) <= maximumCandidateBytes,
              binary["architecture"] as? String == architecture,
              let expectedVersion = binary["expectedVersionWithCommit"] as? String,
              let expectedACPBuild = binary["expectedACPCLIBuild"] as? String,
              let observedVersion = binary["observedVersionWithCommit"] as? String,
              expectedVersion == "1.0.5 (\(forkSourceSHA.prefix(7)))",
              expectedACPBuild == expectedVersion,
              observedVersion == expectedVersion,
              expectedACPBuild == expectedCLIBuild else { return nil }

        guard let signing = document["signing"] as? [String: Any],
              exactKeys(signing, ["state", "strictVerification", "teamIdentifier", "designatedRequirement"]),
              signing["state"] as? String == "signed",
              signing["strictVerification"] as? Bool == true,
              let teamIdentifier = signing["teamIdentifier"] as? String,
              teamIdentifier == expectedTeamIdentifier,
              let designatedRequirement = signing["designatedRequirement"] as? String,
              !designatedRequirement.isEmpty else { return nil }

        return GrokCandidateRuntimeIdentity(
            binaryPath: candidatePath,
            provenancePath: provenancePath,
            provenanceSHA256: "",
            binarySHA256: binarySHA,
            binarySize: Int64(binarySize),
            architecture: architecture,
            sourceSHA: forkSourceSHA,
            cliBuild: expectedACPBuild,
            signature: GrokCandidateSignatureReceipt(
                teamIdentifier: teamIdentifier,
                designatedRequirement: designatedRequirement
            )
        )
    }

    private static func validateBuild(_ build: [String: Any]) -> Bool {
        guard exactKeys(build, ["preBuildCommand", "command", "environment", "profile", "package", "features"]),
              build["preBuildCommand"] as? [String] == [
                "cargo", "clean", "--target-dir", "<candidate-target>", "--profile", "release-dist",
                "-p", "xai-grok-pager-bin"
              ],
              build["command"] as? [String] == [
                "cargo", "build", "--locked", "--profile", "release-dist", "-p",
                "xai-grok-pager-bin", "--features", "release-dist"
              ],
              build["profile"] as? String == "release-dist",
              build["package"] as? String == "xai-grok-pager-bin",
              build["features"] as? [String] == ["release-dist"],
              let environment = build["environment"] as? [String: Any],
              exactKeys(environment, [
                "clearEnvironment", "home", "path", "cargoHome", "rustupHome", "rustc",
                "cargoTargetDir", "cargoIncremental", "locale", "temporaryDirectory"
              ]),
              environment["clearEnvironment"] as? Bool == true,
              environment["home"] as? String == "<account-home>",
              environment["path"] as? [String] == [
                "/usr/bin", "/bin", "/usr/sbin", "/sbin", "<dotslash-directory>"
              ],
              environment["cargoHome"] as? String == "<account-home>/.cargo",
              environment["rustupHome"] as? String == "<account-home>/.rustup",
              environment["rustc"] as? String == "<pinned-rustc>",
              environment["cargoTargetDir"] as? String == "<candidate-target>",
              environment["cargoIncremental"] as? Bool == false,
              environment["locale"] as? String == "C",
              environment["temporaryDirectory"] as? String == "/private/tmp" else { return false }
        return true
    }

    private static func validateRuntimeLayout(
        root: String,
        candidatePath: String,
        provenancePath: String,
        binarySHA256: String
    ) -> Bool {
        guard NSString(string: root).isAbsolutePath,
              NSString(string: candidatePath).isAbsolutePath,
              NSString(string: provenancePath).isAbsolutePath else { return false }
        let canonicalRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        let digestDirectory = URL(fileURLWithPath: canonicalRoot)
            .appendingPathComponent(binarySHA256, isDirectory: true)
            .standardizedFileURL.path
        guard URL(fileURLWithPath: candidatePath).deletingLastPathComponent().standardizedFileURL.path == digestDirectory,
              URL(fileURLWithPath: provenancePath).deletingLastPathComponent().standardizedFileURL.path == digestDirectory,
              privateDirectory(path: canonicalRoot),
              privateDirectory(path: digestDirectory),
              privateRegularFile(path: candidatePath, executable: true),
              privateRegularFile(path: provenancePath, executable: false) else { return false }
        return true
    }

    private static func observedSignature(url: URL) -> GrokCandidateSignatureReceipt? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(
                staticCode,
                SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
                nil
              ) == errSecSuccess else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
              let info = information as? [String: Any],
              let codeDirectoryHash = codeDirectoryHash(info) else { return nil }
        if let override = signatureVerifierOverrideForTests,
           let receipt = override(url) {
            return GrokCandidateSignatureReceipt(
                teamIdentifier: receipt.teamIdentifier,
                designatedRequirement: receipt.designatedRequirement,
                codeDirectoryHash: codeDirectoryHash
            )
        }
        guard let team = info[kSecCodeInfoTeamIdentifier as String] as? String else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var requirementText: CFString?
        guard SecRequirementCopyString(requirement, [], &requirementText) == errSecSuccess,
              let requirementText else { return nil }
        return GrokCandidateSignatureReceipt(
            teamIdentifier: team,
            designatedRequirement: requirementText as String,
            codeDirectoryHash: codeDirectoryHash
        )
    }

    static func dynamicCodeDirectoryHash(processIdentifier: pid_t) -> String? {
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: processIdentifier)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
              let info = information as? [String: Any] else { return nil }
        return codeDirectoryHash(info)
    }

    private static func codeDirectoryHash(_ information: [String: Any]) -> String? {
        let data = (information["cdhashes"] as? [Data])?.first
            ?? information[kSecCodeInfoUnique as String] as? Data
        guard let data, !data.isEmpty else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    fileprivate struct FileSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let sha256: String
        let architecture: String
    }

    fileprivate static func fileSnapshot(descriptor: Int32) -> FileSnapshot? {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_mode & mode_t(S_IRWXG | S_IRWXO) == 0,
              metadata.st_mode & mode_t(S_IXUSR) != 0,
              metadata.st_nlink == 1,
              metadata.st_size > 0,
              metadata.st_size <= maximumCandidateBytes,
              let digest = descriptorSHA256(descriptor, size: metadata.st_size),
              let architecture = descriptorArchitecture(descriptor) else { return nil }
        var afterRead = stat()
        guard fstat(descriptor, &afterRead) == 0,
              afterRead.st_dev == metadata.st_dev,
              afterRead.st_ino == metadata.st_ino,
              afterRead.st_size == metadata.st_size else { return nil }
        return FileSnapshot(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            size: Int64(metadata.st_size),
            sha256: digest,
            architecture: architecture
        )
    }

    private static func descriptorSHA256(_ descriptor: Int32, size: off_t) -> String? {
        var hasher = SHA256()
        var offset: off_t = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while offset < size {
            let count = min(buffer.count, Int(size - offset))
            let readCount = buffer.withUnsafeMutableBytes {
                pread(descriptor, $0.baseAddress, count, offset)
            }
            guard readCount > 0 else { return nil }
            hasher.update(data: Data(buffer.prefix(readCount)))
            offset += off_t(readCount)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func descriptorArchitecture(_ descriptor: Int32) -> String? {
        var header = mach_header_64()
        let count = withUnsafeMutablePointer(to: &header) {
            pread(descriptor, $0, MemoryLayout<mach_header_64>.size, 0)
        }
        guard count == MemoryLayout<mach_header_64>.size,
              header.magic == MH_MAGIC_64 else { return nil }
        switch header.cputype {
        case CPU_TYPE_ARM64: return "arm64"
        case CPU_TYPE_X86_64: return "x86_64"
        default: return nil
        }
    }

    private static func secureReadPrivateFile(path: String, maximumBytes: Int) -> Data? {
        guard NSString(string: path).isAbsolutePath else { return nil }
        let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_mode & mode_t(S_IRWXG | S_IRWXO) == 0,
              metadata.st_nlink == 1,
              metadata.st_size >= 0,
              metadata.st_size <= maximumBytes else { return nil }
        let handle = FileHandle(fileDescriptor: dup(descriptor), closeOnDealloc: true)
        guard handle.fileDescriptor >= 0,
              let data = try? handle.readToEnd(),
              data.count == Int(metadata.st_size) else { return nil }
        var afterRead = stat()
        guard fstat(descriptor, &afterRead) == 0,
              afterRead.st_dev == metadata.st_dev,
              afterRead.st_ino == metadata.st_ino,
              afterRead.st_size == metadata.st_size else { return nil }
        return data
    }

    private static func privateDirectory(path: String) -> Bool {
        var metadata = stat()
        return lstat(path, &metadata) == 0
            && metadata.st_uid == getuid()
            && metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
            && metadata.st_mode & mode_t(S_IRWXG | S_IRWXO) == 0
            && metadata.st_nlink >= 1
    }

    private static func privateRegularFile(path: String, executable: Bool) -> Bool {
        var metadata = stat()
        guard lstat(path, &metadata) == 0,
              metadata.st_uid == getuid(),
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_mode & mode_t(S_IRWXG | S_IRWXO) == 0,
              metadata.st_nlink == 1 else { return false }
        return !executable || metadata.st_mode & mode_t(S_IXUSR) != 0
    }

    private static func exactKeys(_ value: [String: Any], _ expected: Set<String>) -> Bool {
        Set(value.keys) == expected
    }

    private static func isGitSHA(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) != nil
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

final class GrokManagedProcess: @unchecked Sendable {
    private enum Storage {
        case foundation(Process)
        case posix(pid_t)
    }

    private let storage: Storage
    private let lock = NSLock()
    private var posixExited = false

    init(_ process: Process) {
        storage = .foundation(process)
    }

    init(pid: pid_t) {
        storage = .posix(pid)
    }

    var processIdentifier: pid_t {
        switch storage {
        case .foundation(let process): return process.processIdentifier
        case .posix(let pid): return pid
        }
    }

    var isRunning: Bool {
        switch storage {
        case .foundation(let process): return process.isRunning
        case .posix(let pid):
            lock.lock()
            defer { lock.unlock() }
            guard !posixExited else { return false }
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result < 0 && errno == ECHILD) {
                posixExited = true
                return false
            }
            return result == 0
        }
    }

    func terminate() {
        switch storage {
        case .foundation(let process): process.terminate()
        case .posix(let pid): Darwin.kill(pid, SIGTERM)
        }
    }

    /// SIGKILL is terminal, so synchronously reap the direct child before the
    /// owner drops its process handle. This cannot wait on descendants; the
    /// separate owned-process ledger handles those exact fingerprints.
    func forceKillAndReap() {
        switch storage {
        case .foundation(let process):
            guard process.isRunning else { return }
            Darwin.kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        case .posix(let pid):
            lock.lock()
            defer { lock.unlock() }
            guard !posixExited else { return }
            _ = Darwin.kill(pid, SIGKILL)
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            posixExited = true
        }
    }
}

struct GrokCandidateSpawnResult {
    let process: GrokManagedProcess
    let standardInput: FileHandle
    let standardOutput: Pipe
    let standardError: Pipe
}

enum GrokCandidateProcessLauncher {
    #if DEBUG
    static var spawnedProcessObserverForTests: (@Sendable (pid_t) -> Void)?
    #endif

    enum LaunchError: LocalizedError {
        case leaseAlreadyConsumed
        case authorityChanged
        case pipeFailed(Int32)
        case fileActionFailed(Int32)
        case spawnFailed(Int32)
        case credentialTransportFailed

        var errorDescription: String? {
            switch self {
            case .leaseAlreadyConsumed: return "Candidate execution lease was already consumed."
            case .authorityChanged: return "Candidate executable changed after authorization."
            case .pipeFailed(let code): return "Could not create candidate process pipes (errno \(code))."
            case .fileActionFailed(let code): return "Could not configure candidate process descriptors (errno \(code))."
            case .spawnFailed(let code): return "Could not launch the held candidate executable (errno \(code))."
            case .credentialTransportFailed: return "Candidate credential transport handshake failed."
            }
        }
    }

    static func spawn(
        lease: GrokCandidateExecutionLease,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL,
        credentialTransport: GrokCredentialTransportPayload? = nil
    ) throws -> GrokCandidateSpawnResult {
        guard lease.heldFileRemainsValid else { throw LaunchError.authorityChanged }
        if let credentialTransport,
           GrokCredentialTransportV1.argumentsOrEnvironmentContainPayload(
               credentialTransport,
               arguments: arguments,
               environment: environment
           ) {
            throw LaunchError.credentialTransportFailed
        }
        guard lease.claimForSpawn() else { throw LaunchError.leaseAlreadyConsumed }

        GrokChildProcessSpawnGate.acquire()
        var spawnGateHeld = true
        defer { if spawnGateHeld { GrokChildProcessSpawnGate.release() } }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinRead = stdinPipe.fileHandleForReading.fileDescriptor
        let stdinWrite = stdinPipe.fileHandleForWriting.fileDescriptor
        let stdoutRead = stdoutPipe.fileHandleForReading.fileDescriptor
        let stdoutWrite = stdoutPipe.fileHandleForWriting.fileDescriptor
        let stderrRead = stderrPipe.fileHandleForReading.fileDescriptor
        let stderrWrite = stderrPipe.fileHandleForWriting.fileDescriptor
        for descriptor in [stdinRead, stdinWrite, stdoutRead, stdoutWrite, stderrRead, stderrWrite] {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }

        var transportChannel: GrokCredentialTransportV1.PreparedChannel?
        if let credentialTransport {
            transportChannel = try GrokCredentialTransportV1.prepare(payload: credentialTransport)
        }
        defer {
            if var channel = transportChannel {
                channel.closeParent()
                channel.closeChild()
                channel.bestEffortWipe()
            }
        }

        var actions: posix_spawn_file_actions_t?
        var actionCode = posix_spawn_file_actions_init(&actions)
        guard actionCode == 0 else {
            throw LaunchError.fileActionFailed(actionCode)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }

        let actionCalls: [(Int32) -> Int32] = [
            { _ in posix_spawn_file_actions_adddup2(&actions, stdinRead, STDIN_FILENO) },
            { _ in posix_spawn_file_actions_adddup2(&actions, stdoutWrite, STDOUT_FILENO) },
            { _ in posix_spawn_file_actions_adddup2(&actions, stderrWrite, STDERR_FILENO) },
            { _ in posix_spawn_file_actions_addclose(&actions, stdinWrite) },
            { _ in posix_spawn_file_actions_addclose(&actions, stdoutRead) },
            { _ in posix_spawn_file_actions_addclose(&actions, stderrRead) },
        ]
        for action in actionCalls {
            actionCode = action(0)
            guard actionCode == 0 else {
                throw LaunchError.fileActionFailed(actionCode)
            }
        }
        if let channel = transportChannel {
            do {
                try GrokCredentialTransportV1.installChildDescriptor(
                    channel.childDescriptor,
                    parentDescriptor: channel.parentDescriptor,
                    actions: &actions
                )
            } catch {
                throw LaunchError.fileActionFailed(EINVAL)
            }
        }
        actionCode = currentDirectory.path.withCString {
            posix_spawn_file_actions_addchdir(&actions, $0)
        }
        guard actionCode == 0 else {
            throw LaunchError.fileActionFailed(actionCode)
        }

        var attributes: posix_spawnattr_t?
        let attributeCode = posix_spawnattr_init(&attributes)
        guard attributeCode == 0 else { throw LaunchError.fileActionFailed(attributeCode) }
        defer { posix_spawnattr_destroy(&attributes) }
        var spawnFlags = Int16(POSIX_SPAWN_START_SUSPENDED)
        if credentialTransport != nil {
            spawnFlags |= Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP)
            guard posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
                throw LaunchError.fileActionFailed(EINVAL)
            }
        }
        let flagCode = posix_spawnattr_setflags(&attributes, spawnFlags)
        guard flagCode == 0 else { throw LaunchError.fileActionFailed(flagCode) }

        let executablePath = lease.executionPath
        let argv = [executablePath] + arguments
        let launchEnvironment = credentialTransport == nil
            ? environment
            : GrokCredentialTransportV1.sanitizedEnvironment(environment)
        let env = launchEnvironment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let spawnCode = withCStringArray(argv) { argvPointer in
            withCStringArray(env) { envPointer in
                executablePath.withCString {
                    posix_spawn(&pid, $0, &actions, &attributes, argvPointer, envPointer)
                }
            }
        }
        guard spawnCode == 0 else {
            throw LaunchError.spawnFailed(spawnCode)
        }
        #if DEBUG
        spawnedProcessObserverForTests?(pid)
        #endif

        if transportChannel != nil {
            transportChannel!.closeChild()
        }
        GrokChildProcessSpawnGate.release()
        spawnGateHeld = false

        guard GrokCandidateRuntimeAuthority.dynamicCodeDirectoryHash(processIdentifier: pid)
                == lease.identity.signature.codeDirectoryHash else {
            Darwin.kill(pid, SIGKILL)
            var status: Int32 = 0
            _ = waitpid(pid, &status, 0)
            throw LaunchError.authorityChanged
        }
        guard Darwin.kill(pid, SIGCONT) == 0 else {
            Darwin.kill(pid, SIGKILL)
            var status: Int32 = 0
            _ = waitpid(pid, &status, 0)
            throw LaunchError.spawnFailed(errno)
        }

        if var channel = transportChannel {
            do {
                try GrokCredentialTransportV1.completeHandshake(&channel)
                transportChannel = nil
            } catch {
                _ = Darwin.kill(-pid, SIGKILL)
                _ = Darwin.kill(pid, SIGKILL)
                var status: Int32 = 0
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
                throw LaunchError.credentialTransportFailed
            }
        }

        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        return GrokCandidateSpawnResult(
            process: GrokManagedProcess(pid: pid),
            standardInput: stdinPipe.fileHandleForWriting,
            standardOutput: stdoutPipe,
            standardError: stderrPipe
        )
    }

    private static func withCStringArray<T>(
        _ strings: [String],
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> T
    ) -> T {
        var pointers = strings.map { strdup($0) } + [nil]
        defer { pointers.dropLast().forEach { free($0) } }
        return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }
}
