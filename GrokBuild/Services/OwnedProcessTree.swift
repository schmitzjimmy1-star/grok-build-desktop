import Darwin
import Foundation

struct OwnedProcessIdentity: Equatable, Sendable {
    let localTabID: UUID?
    let backendSessionID: String?
    let processGeneration: UInt64
    let rootPID: pid_t
}

struct OwnedProcessFingerprint: Equatable, Hashable, Sendable {
    let pid: pid_t
    let executablePath: String
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

/// Exact, generation-bound process evidence. It is intentionally internal/testable;
/// no production path searches by executable name or approximate command substring.
struct OwnedProcessLedger: Equatable, Sendable {
    private(set) var identity: OwnedProcessIdentity?
    private(set) var children: Set<OwnedProcessFingerprint> = []

    mutating func begin(_ identity: OwnedProcessIdentity) {
        self.identity = identity
        children.removeAll()
    }

    mutating func rebindBackend(_ backendSessionID: String?) {
        guard let identity else { return }
        self.identity = OwnedProcessIdentity(
            localTabID: identity.localTabID,
            backendSessionID: backendSessionID,
            processGeneration: identity.processGeneration,
            rootPID: identity.rootPID
        )
    }

    mutating func record(_ fingerprints: some Sequence<OwnedProcessFingerprint>) {
        children.formUnion(fingerprints)
    }

    func owns(
        localTabID: UUID?,
        backendSessionID: String?,
        processGeneration: UInt64,
        child: OwnedProcessFingerprint
    ) -> Bool {
        guard let identity,
              identity.localTabID == localTabID,
              identity.backendSessionID == backendSessionID,
              identity.processGeneration == processGeneration else { return false }
        return children.contains(child)
    }
}

enum OwnedProcessTree {
    static func descendants(of rootPID: pid_t) -> [pid_t] {
        guard rootPID > 0 else { return [] }
        var result: [pid_t] = []
        var pending = [rootPID]
        var seen = Set([rootPID])
        while let parent = pending.popLast() {
            for child in directChildren(of: parent) where child > 0 && seen.insert(child).inserted {
                result.append(child)
                pending.append(child)
            }
        }
        return result
    }

    static func fingerprints(of pids: some Sequence<pid_t>) -> [OwnedProcessFingerprint] {
        pids.compactMap(fingerprint(of:))
    }

    static func fingerprint(of pid: pid_t) -> OwnedProcessFingerprint? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let infoSize = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(infoSize)) == infoSize else {
            return nil
        }
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else { return nil }
        return OwnedProcessFingerprint(
            pid: pid,
            executablePath: String(cString: pathBuffer),
            startSeconds: UInt64(info.pbi_start_tvsec),
            startMicroseconds: UInt64(info.pbi_start_tvusec)
        )
    }

    static func stillMatches(_ fingerprint: OwnedProcessFingerprint) -> Bool {
        Self.fingerprint(of: fingerprint.pid) == fingerprint
    }

    static func signal(_ signal: Int32, to fingerprints: some Sequence<OwnedProcessFingerprint>) {
        for fingerprint in fingerprints where stillMatches(fingerprint) {
            _ = Darwin.kill(fingerprint.pid, signal)
        }
    }

    private static func directChildren(of pid: pid_t) -> [pid_t] {
        var capacity = 16
        while capacity <= 4_096 {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let count = buffer.withUnsafeMutableBytes {
                proc_listchildpids(pid, $0.baseAddress, Int32($0.count))
            }
            guard count >= 0 else { return [] }
            if count < capacity { return Array(buffer.prefix(Int(count))) }
            capacity *= 2
        }
        return []
    }
}
