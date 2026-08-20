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
/// transport. Production credential materialization now lives in
/// `GrokArmedCredentialMaterializer` (4B.3+). Swift value copies make wiping
/// this fixture type best-effort only.
struct GrokCredentialTransportPayload: Sendable {
    static let maximumByteCount = 4_096

    fileprivate var bytes: [UInt8]

    init?(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, bytes.count <= Self.maximumByteCount else { return nil }
        self.bytes = bytes
    }
}

/// A consuming transfer. It has no string representation. Only this source
/// file's descriptor transport can borrow its bytes, while the eventual Rust
/// receiver remains the zeroizing owner.
final class GrokArmedCredentialTransfer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8]?

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    deinit { discard() }

    enum TransferError: Error, Equatable {
        case alreadyConsumed
    }

    var byteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes?.count ?? 0
    }

    fileprivate func contains(_ candidate: [UInt8]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let bytes, !candidate.isEmpty, candidate.count >= bytes.count else { return false }
        for offset in 0...(candidate.count - bytes.count) {
            if candidate[offset..<(offset + bytes.count)].elementsEqual(bytes) { return true }
        }
        return false
    }

    /// Has no result value and lends an unsafe buffer only to this file's
    /// descriptor framing implementation. The pointer expires at callback
    /// return; the owning Swift buffer is wiped after return or throw.
    fileprivate func consumeForDescriptorTransport(
        _ body: (UnsafeBufferPointer<UInt8>) throws -> Void
    ) throws {
        lock.lock()
        guard var owned = bytes else {
            lock.unlock()
            throw TransferError.alreadyConsumed
        }
        bytes = nil
        lock.unlock()
        defer { Self.wipe(&owned) }
        try owned.withUnsafeBufferPointer { buffer in
            try body(buffer)
        }
    }

    func discard() {
        lock.lock()
        defer { lock.unlock() }
        guard var value = bytes else { return }
        bytes = nil
        Self.wipe(&value)
    }

    private static func wipe(_ bytes: inout [UInt8]) {
        _ = bytes.withUnsafeMutableBytes { raw in
            raw.initializeMemory(as: UInt8.self, repeating: 0)
        }
    }
}

enum GrokCredentialTransportV1 {
    static let receiverFileDescriptor: Int32 = 198
    static let identityFileDescriptor: Int32 = 197
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
    /// Injected pause after ACK so tests can prove ACK/READY/EOF each get a
    /// fresh `timeoutMilliseconds` budget instead of one shared deadline.
    static var handshakeInterphaseDelayMillisecondsForTests: Int32 = 0
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
        try prepare(bytes: payload.bytes)
    }

    /// Reserved for the schema-3 armed path. The transfer is consumed by the
    /// frame writer, never converted to a String, and cannot be reused after a
    /// failed or successful prepare.
    static func prepare(transfer: GrokArmedCredentialTransfer) throws -> PreparedChannel {
        var prepared: PreparedChannel?
        try transfer.consumeForDescriptorTransport { bytes in
            prepared = try prepare(bytes: bytes)
        }
        guard let prepared else { throw TransportError.frameWriteFailed }
        return prepared
    }

    private static func prepare(bytes: [UInt8]) throws -> PreparedChannel {
        try bytes.withUnsafeBufferPointer { buffer in
            try prepare(bytes: buffer)
        }
    }

    private static func prepare(bytes: UnsafeBufferPointer<UInt8>) throws -> PreparedChannel {
        guard !bytes.isEmpty, bytes.count <= GrokCredentialTransportPayload.maximumByteCount else {
            throw TransportError.frameWriteFailed
        }
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
        var frame = header(type: credentialType, nonce: nonce, payloadLength: bytes.count)
        frame.append(contentsOf: bytes)
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

    static func argumentsOrEnvironmentContainTransfer(
        _ transfer: GrokArmedCredentialTransfer,
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        let candidates = arguments + environment.flatMap { [$0.key, $0.value] }
        return candidates.contains { transfer.contains(Array($0.utf8)) }
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

    static func installChildIdentityDescriptor(
        _ parentDuplicate: Int32,
        actions: inout posix_spawn_file_actions_t?
    ) throws {
        let codes = [
            posix_spawn_file_actions_adddup2(&actions, parentDuplicate, identityFileDescriptor),
            posix_spawn_file_actions_addclose(&actions, parentDuplicate),
        ]
        for code in codes {
            guard code == 0 else { throw TransportError.descriptorPolicyFailed }
        }
    }

    /// Runs only after the suspended child has passed the dynamic CDHash gate.
    /// The payload is buffered but not usable by the fixture until COMMIT.
    /// Each phase (credential send, ACK, COMMIT/READY, EOF) gets its own
    /// `timeoutMilliseconds` budget so scheduler load cannot collapse later
    /// phases. Hostile peers that stall one phase still fail at 2s.
    static func completeHandshake(_ channel: inout PreparedChannel) throws {
        defer {
            channel.closeParent()
            channel.bestEffortWipe()
        }
        try sendExactly(
            channel.parentDescriptor,
            bytes: channel.frame,
            deadlineNanoseconds: phaseDeadline()
        )
        let acknowledgement = try readExact(
            channel.parentDescriptor,
            count: headerByteCount,
            deadlineNanoseconds: phaseDeadline()
        )
        guard validate(
            acknowledgement,
            type: acknowledgementType,
            nonce: channel.nonce,
            payloadLength: channel.frame.count - headerByteCount
        ) else {
            throw TransportError.peerProtocolFailed
        }
        #if DEBUG
        delayHandshakeInterphaseForTests()
        #endif

        var commit = header(type: commitType, nonce: channel.nonce, payloadLength: 0)
        defer { _ = commit.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        try sendExactly(
            channel.parentDescriptor,
            bytes: commit,
            deadlineNanoseconds: phaseDeadline()
        )
        guard shutdown(channel.parentDescriptor, SHUT_WR) == 0 else {
            throw TransportError.frameWriteFailed
        }
        let ready = try readExact(
            channel.parentDescriptor,
            count: headerByteCount,
            deadlineNanoseconds: phaseDeadline()
        )
        guard validate(ready, type: readyType, nonce: channel.nonce, payloadLength: 0) else {
            throw TransportError.peerProtocolFailed
        }
        var trailing: UInt8 = 0
        guard pollReadable(channel.parentDescriptor, deadlineNanoseconds: phaseDeadline()),
              Darwin.read(channel.parentDescriptor, &trailing, 1) == 0 else {
            throw TransportError.peerProtocolFailed
        }
    }

    private static func phaseDeadline() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds + UInt64(timeoutMilliseconds) * 1_000_000
    }

    #if DEBUG
    private static func delayHandshakeInterphaseForTests() {
        var remaining = handshakeInterphaseDelayMillisecondsForTests
        while remaining > 0 {
            let slice = min(remaining, 50)
            usleep(useconds_t(slice) * 1_000)
            remaining -= slice
        }
    }
    #endif

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

    private static func sendExactly(
        _ descriptor: Int32,
        bytes: [UInt8],
        deadlineNanoseconds: UInt64
    ) throws {
        var offset = 0
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                throw TransportError.frameWriteFailed
            }
            while offset < raw.count {
                guard pollWritable(descriptor, deadlineNanoseconds: deadlineNanoseconds) else {
                    throw TransportError.peerTimeout
                }
                let sent = Darwin.send(
                    descriptor,
                    base.advanced(by: offset),
                    raw.count - offset,
                    MSG_DONTWAIT
                )
                if sent < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        continue
                    }
                    throw TransportError.frameWriteFailed
                }
                guard sent > 0 else { throw TransportError.frameWriteFailed }
                offset += sent
            }
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
        poll(descriptor, events: Int16(POLLIN | POLLHUP), deadlineNanoseconds: deadlineNanoseconds)
    }

    private static func pollWritable(_ descriptor: Int32, deadlineNanoseconds: UInt64) -> Bool {
        poll(descriptor, events: Int16(POLLOUT), deadlineNanoseconds: deadlineNanoseconds)
    }

    private static func poll(
        _ descriptor: Int32,
        events: Int16,
        deadlineNanoseconds: UInt64
    ) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadlineNanoseconds else { return false }
        let remainingNanoseconds = deadlineNanoseconds - now
        let timeoutMilliseconds = Int32(min(
            UInt64(Int32.max),
            max(1, (remainingNanoseconds + 999_999) / 1_000_000)
        ))
        var pollDescriptor = pollfd(fd: descriptor, events: events, revents: 0)
        var result: Int32
        repeat {
            result = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
        } while result < 0 && errno == EINTR
        return result > 0 && (pollDescriptor.revents & events) != 0
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
