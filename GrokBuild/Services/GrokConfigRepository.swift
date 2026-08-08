import Darwin
import Foundation

/// The single read/modify/write boundary for `~/.grok/config.toml`.
///
/// Store-specific parsers remain pure, but every mutation is serialized here, rereads the
/// latest file contents, atomically replaces the file, and enforces owner-only permissions.
final class GrokConfigRepository: @unchecked Sendable {
    static let shared = GrokConfigRepository()
    static let securePermissions = 0o600

    let configURL: URL
    private let lock = NSLock()
    private let fileManager: FileManager

    /// Cached file contents keyed by the on-disk identity that produced them. Launch
    /// restore calls `read()` several times per restored tab (model merge, subagent
    /// roles); without this cache a 130-tab restore re-reads and re-parses the same
    /// unchanged file hundreds of times. External writers (the grok TUI/CLI) are still
    /// honored: every `read()` stats the file first and any mtime/size change drops
    /// the cache.
    private struct CacheStamp: Equatable {
        var modificationDate: Date
        var size: Int
    }
    private var cachedContents: String?
    private var cachedStamp: CacheStamp?

    private func currentStamp() -> CacheStamp? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: configURL.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.intValue else {
            return nil
        }
        return CacheStamp(modificationDate: modified, size: size)
    }

    init(
        configURL: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".grok/config.toml"),
        fileManager: FileManager = .default
    ) {
        self.configURL = configURL
        self.fileManager = fileManager
    }

    func read() -> String {
        lock.lock()
        defer { lock.unlock() }
        let stamp = currentStamp()
        if let cachedContents, let cachedStamp, let stamp, cachedStamp == stamp {
            return cachedContents
        }
        let contents = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        cachedContents = contents
        cachedStamp = stamp
        return contents
    }

    func update(_ transform: (String) throws -> String) throws {
        lock.lock()
        defer { lock.unlock() }

        // A missing file starts from empty, but a present-yet-unreadable file must fail
        // the update — otherwise a transient read error would rewrite the config from
        // empty and silently drop every unrelated section.
        let existing: String
        if fileManager.fileExists(atPath: configURL.path) {
            existing = try String(contentsOf: configURL, encoding: .utf8)
        } else {
            existing = ""
        }
        let updated = try transform(existing)
        try secureAtomicWrite(updated)
    }

    func enforceSecurePermissionsIfPresent() throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: configURL.path) else { return }
        try fileManager.setAttributes(
            [.posixPermissions: Self.securePermissions],
            ofItemAtPath: configURL.path
        )
    }

    private func secureAtomicWrite(_ contents: String) throws {
        let directory = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let temporaryURL = directory.appendingPathComponent(".config.toml.\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard let data = contents.data(using: .utf8),
              fileManager.createFile(
                atPath: temporaryURL.path,
                contents: data,
                attributes: [.posixPermissions: Self.securePermissions]
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let result = temporaryURL.path.withCString { source in
            configURL.path.withCString { destination in
                Darwin.rename(source, destination)
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        // `rename(2)` preserves the secure temporary-file mode, but set it again so future
        // filesystem behavior cannot weaken the contract.
        try fileManager.setAttributes(
            [.posixPermissions: Self.securePermissions],
            ofItemAtPath: configURL.path
        )

        cachedContents = contents
        cachedStamp = currentStamp()
    }
}
