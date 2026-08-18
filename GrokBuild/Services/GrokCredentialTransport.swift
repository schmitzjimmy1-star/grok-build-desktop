import Darwin
import Dispatch
import Foundation
import Security

/// Serializes every GrokBuild-owned child creation across the tiny Darwin
/// socketpair -> FD_CLOEXEC window. macOS exposes no atomic SOCK_CLOEXEC for
/// socketpair, so every app-owned Foundation Process and candidate posix_spawn
/// must cross this same gate.
enum GrokChildProcessSpawnGate {
    private static let lock = NSLock()

    static func acquire() { lock.lock() }
    static func release() { lock.unlock() }

    static func run(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        try process.run()
    }
}

/// A fake-only, bounded byte payload used to prove the 4B.2 inherited-descriptor
/// transport. Production credential materialization is deliberately not wired
/// until 4B.3. Swift value copies make wiping best-effort only; 4B.3 must replace
/// this fixture type with consuming, single-owner zeroizing storage.
struct GrokCredentialTransportPayload: Sendable {
    static let maximumByteCount = 4_096

    fileprivate var bytes: [UInt8]

    init?(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, bytes.count <= Self.maximumByteCount else { return nil }
        self.bytes = bytes
    }
}

enum GrokCredentialTransportV1 {
    static let receiverFileDescriptor: Int32 = 198
    static let timeoutMilliseconds: Int32 = 2_000

    enum TransportError: Error {
        case socketPairFailed
        case descriptorPolicyFailed
        case randomFailed
        case frameWriteFailed
        case peerTimeout
        case peerProtocolFailed
    }

    #if DEBUG
    static var socketPairCreatedObserverForTests: (() -> Void)?
    enum OutboundFrameFaultForTests {
        case none
        case badMagic
        case oversizedClaim
        case truncated
        case trailingByte
        case duplicatedFrame
    }
    static var outboundFrameFaultForTests: OutboundFrameFaultForTests = .none
    #endif

    struct PreparedChannel {
        var parentDescriptor: Int32
        var childDescriptor: Int32
        fileprivate var nonce: [UInt8]
        fileprivate var frame: [UInt8]

        mutating func bestEffortWipe() {
            _ = nonce.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            _ = frame.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }


        mutating func closeParent() {
            if parentDescriptor >= 0 {
                Darwin.close(parentDescriptor)
                parentDescriptor = -1
            }
        }

        mutating func closeChild() {
            if childDescriptor >= 0 {
                Darwin.close(childDescriptor)
                childDescriptor = -1
            }
        }
    }

    private static let magic: [UInt8] = [0x47, 0x42, 0x43, 0x54, 0, 0, 0, 1]
    private static let credentialType: UInt8 = 1
    private static let acknowledgementType: UInt8 = 2
    private static let commitType: UInt8 = 3
    private static let readyType: UInt8 = 4
    private static let headerByteCount = 48

    static func prepare(payload: GrokCredentialTransportPayload) throws -> PreparedChannel {
        var rawDescriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &rawDescriptors) == 0 else {
            throw TransportError.socketPairFailed
        }
        #if DEBUG
        socketPairCreatedObserverForTests?()
        #endif
        var descriptors: [Int32] = [-1, -1]
        defer {
            rawDescriptors.filter { $0 >= 0 }.forEach { Darwin.close($0) }
            descriptors.filter { $0 >= 0 }.forEach { Darwin.close($0) }
        }
        for descriptor in rawDescriptors {
            guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
                throw TransportError.descriptorPolicyFailed
            }
        }
        descriptors[0] = fcntl(rawDescriptors[0], F_DUPFD_CLOEXEC, receiverFileDescriptor + 1)
        descriptors[1] = fcntl(rawDescriptors[1], F_DUPFD_CLOEXEC, receiverFileDescriptor + 1)
        guard descriptors[0] >= receiverFileDescriptor + 1,
              descriptors[1] >= receiverFileDescriptor + 1,
              descriptors[0] != descriptors[1] else {
            throw TransportError.descriptorPolicyFailed
        }
        rawDescriptors.forEach { Darwin.close($0) }
        rawDescriptors = [-1, -1]
        for descriptor in descriptors {
            var noSignal: Int32 = 1
            guard setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSignal,
                socklen_t(MemoryLayout<Int32>.size)
            ) == 0 else {
                throw TransportError.descriptorPolicyFailed
            }
        }

        var nonce = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce) == errSecSuccess else {
            throw TransportError.randomFailed
        }
        var frame = header(type: credentialType, nonce: nonce, payloadLength: payload.bytes.count)
        frame.append(contentsOf: payload.bytes)
        #if DEBUG
        switch outboundFrameFaultForTests {
        case .none: break
        case .badMagic: frame[0] ^= 0xff
        case .oversizedClaim:
            let oversized = UInt32(GrokCredentialTransportPayload.maximumByteCount + 1).bigEndian
            withUnsafeBytes(of: oversized) { frame.replaceSubrange(44..<48, with: $0) }
        case .truncated: frame.removeLast()
        case .trailingByte: frame.append(0xff)
        case .duplicatedFrame: frame.append(contentsOf: frame)
        }
        #endif
        let channel = PreparedChannel(
            parentDescriptor: descriptors[0],
            childDescriptor: descriptors[1],
            nonce: nonce,
            frame: frame
        )
        descriptors = [-1, -1]
        return channel
    }

    /// Transport-enabled fixture launches get a positive environment allowlist.
    /// The fake payload is never an input to this function and cannot enter env.
    static func sanitizedEnvironment(_ base: [String: String]) -> [String: String] {
        let allowed = Set([
            "HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL",
            "GROK_HARD_TOKEN_BUDGET_LEDGER",
            "GROK_HARD_TOKEN_BUDGET_MANIFEST",
            "GROK_HARD_TOKEN_BUDGET_ALLOCATION",
        ])
        return base.filter { allowed.contains($0.key) }
    }

    static func argumentsOrEnvironmentContainPayload(
        _ payload: GrokCredentialTransportPayload,
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        let candidates = arguments + environment.flatMap { [$0.key, $0.value] }
        return candidates.contains { candidate in
            contains(Array(candidate.utf8), subsequence: payload.bytes)
        }
    }

    static func installChildDescriptor(
        _ childDescriptor: Int32,
        parentDescriptor: Int32,
        actions: inout posix_spawn_file_actions_t?
    ) throws {
        let codes = [
            posix_spawn_file_actions_adddup2(&actions, childDescriptor, receiverFileDescriptor),
            posix_spawn_file_actions_addclose(&actions, childDescriptor),
            posix_spawn_file_actions_addclose(&actions, parentDescriptor),
        ]
        for code in codes {
            guard code == 0 else { throw TransportError.descriptorPolicyFailed }
        }
    }

    /// Runs only after the suspended child has passed the dynamic CDHash gate.
    /// The payload is buffered but not usable by the fixture until COMMIT.
    static func completeHandshake(_ channel: inout PreparedChannel) throws {
        defer {
            channel.closeParent()
            channel.bestEffortWipe()
        }
        guard sendExactlyOnce(channel.parentDescriptor, bytes: channel.frame) else {
            throw TransportError.frameWriteFailed
        }
        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(timeoutMilliseconds) * 1_000_000
        let acknowledgement = try readExact(
            channel.parentDescriptor,
            count: headerByteCount,
            deadlineNanoseconds: deadline
        )
        guard validate(
            acknowledgement,
            type: acknowledgementType,
            nonce: channel.nonce,
            payloadLength: channel.frame.count - headerByteCount
        ) else {
            throw TransportError.peerProtocolFailed
        }

        var commit = header(type: commitType, nonce: channel.nonce, payloadLength: 0)
        defer { _ = commit.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        guard sendExactlyOnce(channel.parentDescriptor, bytes: commit),
              shutdown(channel.parentDescriptor, SHUT_WR) == 0 else {
            throw TransportError.frameWriteFailed
        }
        let ready = try readExact(
            channel.parentDescriptor,
            count: headerByteCount,
            deadlineNanoseconds: deadline
        )
        guard validate(ready, type: readyType, nonce: channel.nonce, payloadLength: 0) else {
            throw TransportError.peerProtocolFailed
        }
        var trailing: UInt8 = 0
        guard pollReadable(channel.parentDescriptor, deadlineNanoseconds: deadline),
              Darwin.read(channel.parentDescriptor, &trailing, 1) == 0 else {
            throw TransportError.peerProtocolFailed
        }
    }

    private static func header(type: UInt8, nonce: [UInt8], payloadLength: Int) -> [UInt8] {
        precondition(nonce.count == 32)
        var bytes = magic
        bytes.append(type)
        bytes.append(contentsOf: [0, 0, 0])
        bytes.append(contentsOf: nonce)
        let length = UInt32(payloadLength).bigEndian
        withUnsafeBytes(of: length) { bytes.append(contentsOf: $0) }
        return bytes
    }

    private static func validate(
        _ bytes: [UInt8],
        type: UInt8,
        nonce: [UInt8],
        payloadLength: Int
    ) -> Bool {
        guard bytes.count == headerByteCount,
              Array(bytes[0..<8]) == magic,
              bytes[8] == type,
              bytes[9] == 0,
              bytes[10] == 0,
              bytes[11] == 0,
              Array(bytes[12..<44]) == nonce else { return false }
        let length = bytes[44..<48].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return length == UInt32(payloadLength)
    }

    private static func sendExactlyOnce(_ descriptor: Int32, bytes: [UInt8]) -> Bool {
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            let sent = Darwin.send(descriptor, base, raw.count, MSG_DONTWAIT)
            return sent == raw.count
        }
    }

    private static func readExact(
        _ descriptor: Int32,
        count: Int,
        deadlineNanoseconds: UInt64
    ) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            guard pollReadable(descriptor, deadlineNanoseconds: deadlineNanoseconds) else {
                throw TransportError.peerTimeout
            }
            let readCount = result.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(descriptor, base.advanced(by: offset), count - offset)
            }
            guard readCount > 0 else { throw TransportError.peerProtocolFailed }
            offset += readCount
        }
        return result
    }

    private static func pollReadable(_ descriptor: Int32, deadlineNanoseconds: UInt64) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadlineNanoseconds else { return false }
        let remainingNanoseconds = deadlineNanoseconds - now
        let timeoutMilliseconds = Int32(min(
            UInt64(Int32.max),
            max(1, (remainingNanoseconds + 999_999) / 1_000_000)
        ))
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
        var result: Int32
        repeat {
            result = poll(&pollDescriptor, 1, timeoutMilliseconds)
        } while result < 0 && errno == EINTR
        return result > 0 && (pollDescriptor.revents & Int16(POLLIN | POLLHUP)) != 0
    }

    private static func contains(
        _ candidate: [UInt8],
        subsequence: [UInt8]
    ) -> Bool {
        guard !subsequence.isEmpty, candidate.count >= subsequence.count else { return false }
        for offset in 0...(candidate.count - subsequence.count) {
            if candidate[offset..<(offset + subsequence.count)].elementsEqual(subsequence) {
                return true
            }
        }
        return false
    }
}
