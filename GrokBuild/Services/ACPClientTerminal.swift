import Foundation
import Darwin

/// Client-owned terminals advertised through ACP. Commands run directly (never through an
/// interpolated shell), inherit GrokBuild's environment, and retain a bounded combined output
/// stream for `terminal/output`.
final class ACPClientTerminalManager: @unchecked Sendable {
    struct ExitStatus: Sendable, Equatable {
        let exitCode: Int32?
        let signal: Int32?

        var jsonObject: [String: Any] {
            [
                "exitCode": exitCode.map { Int($0) as Any } ?? NSNull(),
                "signal": signal.map { Int($0) as Any } ?? NSNull()
            ]
        }
    }

    struct Snapshot: Sendable, Equatable {
        let output: String
        let truncated: Bool
        let exitStatus: ExitStatus?

        var jsonObject: [String: Any] {
            var result: [String: Any] = [
                "output": output,
                "truncated": truncated
            ]
            if let exitStatus {
                result["exitStatus"] = exitStatus.jsonObject
            }
            return result
        }
    }

    enum TerminalError: LocalizedError, Equatable {
        case invalidCommand
        case executableNotFound(String)
        case invalidWorkingDirectory(String)
        case unknownTerminal(String)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidCommand:
                return "Terminal command is empty."
            case .executableNotFound(let command):
                return "Executable not found: \(command)"
            case .invalidWorkingDirectory(let path):
                return "Terminal working directory is unavailable: \(path)"
            case .unknownTerminal(let id):
                return "Unknown or released terminal: \(id)"
            case .launchFailed(let message):
                return "Could not launch terminal command: \(message)"
            }
        }
    }

    private final class Session: @unchecked Sendable {
        let id: String
        let process: Process
        let pipe: Pipe
        private let outputByteLimit: Int
        private let lock = NSLock()
        private var retainedOutput = Data()
        private var didTruncate = false
        private var exitStatus: ExitStatus?
        private var waiters: [CheckedContinuation<ExitStatus, Never>] = []

        init(id: String, process: Process, pipe: Pipe, outputByteLimit: Int) {
            self.id = id
            self.process = process
            self.pipe = pipe
            self.outputByteLimit = outputByteLimit
        }

        func append(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock()
            retainedOutput.append(data)
            if retainedOutput.count > outputByteLimit {
                let overflow = retainedOutput.count - outputByteLimit
                retainedOutput.removeFirst(overflow)
                // If truncation cut into UTF-8, discard continuation bytes until the next
                // character boundary. JSON serialization then receives an intact String.
                while let first = retainedOutput.first, first & 0xC0 == 0x80 {
                    retainedOutput.removeFirst()
                }
                didTruncate = true
            }
            lock.unlock()
        }

        func finish(exitCode: Int32?, signal: Int32?) {
            lock.lock()
            guard exitStatus == nil else {
                lock.unlock()
                return
            }
            let status = ExitStatus(exitCode: exitCode, signal: signal)
            exitStatus = status
            let pending = waiters
            waiters.removeAll()
            lock.unlock()
            for waiter in pending { waiter.resume(returning: status) }
        }

        func snapshot() -> Snapshot {
            lock.lock()
            let data = retainedOutput
            let truncated = didTruncate
            let status = exitStatus
            lock.unlock()
            return Snapshot(
                output: String(decoding: data, as: UTF8.self),
                truncated: truncated,
                exitStatus: status
            )
        }

        func waitForExit() async -> ExitStatus {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let exitStatus {
                    lock.unlock()
                    continuation.resume(returning: exitStatus)
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }

        func terminateIfRunning() {
            if process.isRunning { process.terminate() }
        }

        func terminateAndEscalate() async {
            terminateIfRunning()
            if process.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private let lock = NSLock()
    private var sessions: [String: Session] = [:]
    private static let defaultOutputByteLimit = 1_048_576
    private static let maximumOutputByteLimit = 16_777_216

    func create(
        command: String,
        arguments: [String],
        environment additions: [String: String],
        workingDirectory: String?,
        outputByteLimit requestedLimit: Int?
    ) throws -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TerminalError.invalidCommand }

        let baseEnvironment = ProcessInfo.processInfo.environment
        let cwd: URL?
        if let workingDirectory, !workingDirectory.isEmpty {
            var isDirectory: ObjCBool = false
            guard workingDirectory.hasPrefix("/"),
                  FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw TerminalError.invalidWorkingDirectory(workingDirectory)
            }
            cwd = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        } else {
            cwd = nil
        }

        let resolvedExecutable = Self.resolveExecutable(
            trimmed,
            environment: baseEnvironment,
            workingDirectory: cwd
        )
        let executable: URL
        let effectiveArguments: [String]
        if let resolvedExecutable {
            executable = resolvedExecutable
            effectiveArguments = arguments
        } else if arguments.isEmpty,
                  trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil,
                  FileManager.default.isExecutableFile(atPath: "/bin/zsh") {
            // Current grok CLI versions sometimes place the complete approved shell
            // invocation in `command` instead of splitting ACP `command` + `args`.
            // Pass it as one literal zsh argument; never concatenate or re-quote it.
            executable = URL(fileURLWithPath: "/bin/zsh")
            effectiveArguments = ["-lc", trimmed]
        } else {
            throw TerminalError.executableNotFound(trimmed)
        }

        let limit = min(
            max(0, requestedLimit ?? Self.defaultOutputByteLimit),
            Self.maximumOutputByteLimit
        )
        let process = Process()
        process.executableURL = executable
        process.arguments = effectiveArguments
        process.currentDirectoryURL = cwd
        process.environment = baseEnvironment.merging(additions) { _, replacement in replacement }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let terminalID = "term_\(UUID().uuidString.lowercased())"
        let session = Session(id: terminalID, process: process, pipe: pipe, outputByteLimit: limit)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            session.append(handle.availableData)
        }
        process.terminationHandler = { process in
            pipe.fileHandleForReading.readabilityHandler = nil
            session.append(pipe.fileHandleForReading.readDataToEndOfFile())
            let reason = process.terminationReason
            session.finish(
                exitCode: reason == .exit ? process.terminationStatus : nil,
                signal: reason == .uncaughtSignal ? process.terminationStatus : nil
            )
        }

        lock.lock()
        sessions[terminalID] = session
        lock.unlock()
        do {
            try process.run()
        } catch {
            lock.lock()
            sessions.removeValue(forKey: terminalID)
            lock.unlock()
            pipe.fileHandleForReading.readabilityHandler = nil
            throw TerminalError.launchFailed(error.localizedDescription)
        }
        return terminalID
    }

    func snapshot(terminalID: String) throws -> Snapshot {
        try session(for: terminalID).snapshot()
    }

    func waitForExit(terminalID: String) async throws -> ExitStatus {
        let session = try session(for: terminalID)
        return await session.waitForExit()
    }

    func kill(terminalID: String) throws {
        try session(for: terminalID).terminateIfRunning()
    }

    func release(terminalID: String) throws {
        lock.lock()
        let session = sessions.removeValue(forKey: terminalID)
        lock.unlock()
        guard let session else { throw TerminalError.unknownTerminal(terminalID) }
        session.terminateIfRunning()
        session.pipe.fileHandleForReading.readabilityHandler = nil
    }

    func releaseAll() {
        lock.lock()
        let active = Array(sessions.values)
        sessions.removeAll()
        lock.unlock()
        for session in active {
            session.terminateIfRunning()
            session.pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    /// Teardown path for a Grok process: client terminals are independently
    /// launched, so they need their own bounded TERM → KILL verification rather
    /// than relying on the Grok-root descendant ledger.
    func releaseAllAndEscalate() async {
        let active = takeAllSessions()
        await withTaskGroup(of: Void.self) { group in
            for session in active {
                group.addTask { await session.terminateAndEscalate() }
            }
        }
    }

    private func takeAllSessions() -> [Session] {
        lock.lock()
        defer { lock.unlock() }
        let active = Array(sessions.values)
        sessions.removeAll()
        return active
    }

    private func session(for terminalID: String) throws -> Session {
        lock.lock()
        let session = sessions[terminalID]
        lock.unlock()
        guard let session else { throw TerminalError.unknownTerminal(terminalID) }
        return session
    }

    private static func resolveExecutable(
        _ command: String,
        environment: [String: String],
        workingDirectory: URL?
    ) -> URL? {
        if command.contains("/") {
            let path = command.hasPrefix("/")
                ? command
                : (workingDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    .appendingPathComponent(command).standardizedFileURL.path
            guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
        for directory in (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(command).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}
