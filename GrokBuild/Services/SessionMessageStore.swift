import Foundation

/// Persists one chat transcript per live session tab (keyed by `LiveSession.id`).
///
/// Transcript bodies deliberately live outside UserDefaults: layout metadata remains small and
/// authenticated in v3, while one tab can be read or written without decoding every other tab.
/// The legacy UserDefaults dictionary is retained as a read-only rollback source after a verified,
/// copy-first migration.
enum SessionMessageStore {
    static let storageVersion = 2
    static let legacyStorageKey = "GrokBuild.sessionMessages.v1"

    /// The single I/O lane for transcript bodies, metadata, and migration markers. Synchronous
    /// callers keep their existing API, but no two writers can interleave a temp-file swap.
    private static let storageQueue = DispatchQueue(label: "com.grokbuild.session-message-store")

    struct Metadata: Codable, Equatable, Sendable {
        let localSessionID: UUID
        let storageVersion: Int
        let generation: UInt64
        let messageCount: Int
        let restorableMessageCount: Int
        let modifiedAt: Date
    }

    enum MigrationResult: Equatable, Sendable {
        case notNeeded
        case alreadyVerified
        case migrated(transcriptCount: Int)
        case failed
    }

    private struct Envelope: Codable, Equatable {
        let localSessionID: UUID
        let storageVersion: Int
        let generation: UInt64
        let writtenAt: Date
        let messages: [Message]
    }

    private struct MigrationMarker: Codable, Equatable {
        let storageVersion: Int
        let legacyTranscriptCount: Int
        let localSessionIDs: [UUID]
        let completedAt: Date
        let integrityTag: String
    }

    static func messages(for sessionID: UUID, rootURL: URL = defaultRootURL()) -> [Message] {
        let messages = GrokBuildPerformance.measure(.selectedTranscriptLoad) {
            storageQueue.sync {
                if let envelope = readEnvelope(for: sessionID, rootURL: rootURL) {
                    return envelope.messages
                }
                // Before a successful first-release migration, an individual legacy blob remains
                // readable. This is a rollback path, not a new second source of truth.
                return legacyMessages(for: sessionID)
            }
        }
        GrokBuildPerformance.markOnce(.transcriptLoaded)
        return messages
    }

    static func metadata(for sessionID: UUID, rootURL: URL = defaultRootURL()) -> Metadata? {
        storageQueue.sync {
            readMetadata(for: sessionID, rootURL: rootURL)
        }
    }

    @discardableResult
    static func save(_ messages: [Message], for sessionID: UUID, rootURL: URL = defaultRootURL()) -> Metadata? {
        saveAll([sessionID: messages], rootURL: rootURL)[sessionID]
    }

    /// Persist the exact result of a role/turn/content reconciliation. This remains the only
    /// path allowed to shrink a transcript; ordinary delayed UI saves retain never-shrink.
    @discardableResult
    static func replaceAfterAuthoritativeReconciliation(
        _ messages: [Message],
        for sessionID: UUID,
        rootURL: URL = defaultRootURL()
    ) -> Metadata? {
        GrokBuildPerformance.measure(.transcriptWrite) {
            storageQueue.sync {
                let persistable = messages.filter { shouldPersist($0) }
                guard !persistable.isEmpty else {
                    removeLocked(for: sessionID, rootURL: rootURL)
                    return nil
                }
                return writeLocked(
                    persistable,
                    for: sessionID,
                    rootURL: rootURL,
                    existing: readEnvelope(for: sessionID, rootURL: rootURL),
                    preserveLongerExisting: false
                )
            }
        }
    }

    /// Writes only the supplied dirty tabs. Each tab is read, merged, and atomically replaced on
    /// the serial I/O lane; no full transcript map is decoded or rewritten.
    @discardableResult
    static func saveAll(
        _ messagesBySession: [UUID: [Message]],
        rootURL: URL = defaultRootURL()
    ) -> [UUID: Metadata] {
        guard !messagesBySession.isEmpty else { return [:] }
        return GrokBuildPerformance.measure(.transcriptWrite) {
            storageQueue.sync {
                var results: [UUID: Metadata] = [:]
                for (sessionID, messages) in messagesBySession {
                    let existing = readEnvelope(for: sessionID, rootURL: rootURL)
                    let persistable = messages.filter { shouldPersist($0) }
                    let merged = mergeTranscripts(existing: existing?.messages ?? [], incoming: persistable)
                    guard !merged.isEmpty else {
                        removeLocked(for: sessionID, rootURL: rootURL)
                        continue
                    }
                    if let metadata = writeLocked(
                        merged,
                        for: sessionID,
                        rootURL: rootURL,
                        existing: existing,
                        preserveLongerExisting: true
                    ) {
                        results[sessionID] = metadata
                    }
                }
                return results
            }
        }
    }

    /// Performs the one-time copy-first migration. The legacy dictionary is intentionally never
    /// deleted in this release; a failed verification leaves it completely intact and retries on
    /// the next launch.
    @discardableResult
    static func migrateLegacyIfNeeded(
        defaults: UserDefaults = .standard,
        rootURL: URL = defaultRootURL(),
        keyProvider: any SessionLifecycleIntegrityKeyProviding = KeychainSessionLifecycleIntegrityKeyProvider()
    ) -> MigrationResult {
        storageQueue.sync {
            guard let legacy = legacyMap(defaults: defaults), !legacy.isEmpty else {
                return .notNeeded
            }

            do {
                let key = try keyProvider.existingOrCreateKey()
                let sessionIDs = try legacy.keys.map { key -> UUID in
                    guard let id = UUID(uuidString: key) else { throw MigrationFailure.invalidSessionID }
                    return id
                }.sorted { $0.uuidString < $1.uuidString }
                let existingMarker = readMigrationMarker(rootURL: rootURL)
                if let existingMarker,
                   markerMatches(existingMarker, sessionIDs: sessionIDs, legacy: legacy, key: key) {
                    return .alreadyVerified
                }

                // Decode every legacy blob once before touching files. An unreadable entry leaves
                // the entire dictionary as the sole authority instead of partially switching.
                let decoded = try Dictionary(uniqueKeysWithValues: sessionIDs.map { id in
                    guard let data = legacy[id.uuidString],
                          let messages = try? JSONDecoder().decode([Message].self, from: data) else {
                        throw MigrationFailure.invalidLegacyTranscript
                    }
                    return (id, messages)
                })

                for id in sessionIDs {
                    guard let messages = decoded[id] else { throw MigrationFailure.invalidLegacyTranscript }
                    if let existing = readEnvelope(for: id, rootURL: rootURL) {
                        // A previous incomplete migration may have left a verified candidate. Do
                        // not overwrite a newer, different file with stale legacy bytes.
                        guard messagesEquivalent(existing.messages, messages) else {
                            throw MigrationFailure.candidateMismatch
                        }
                        guard let existingMetadata = readMetadata(for: id, rootURL: rootURL),
                              metadataMatches(existingMetadata, envelope: existing) else {
                            throw MigrationFailure.candidateMismatch
                        }
                        continue
                    }
                    guard writeLocked(
                        messages,
                        for: id,
                        rootURL: rootURL,
                        existing: nil,
                        preserveLongerExisting: false
                    ) != nil else {
                        throw MigrationFailure.writeFailed
                    }
                }

                // Verify session IDs, message counts, and keyed in-memory content tags before
                // the complete marker is written. The tags never leave this migration operation.
                for id in sessionIDs {
                    guard let expected = decoded[id],
                          let envelope = readEnvelope(for: id, rootURL: rootURL),
                          envelope.localSessionID == id,
                          messagesEquivalent(envelope.messages, expected),
                          let metadata = readMetadata(for: id, rootURL: rootURL),
                          metadataMatches(metadata, envelope: envelope),
                          transcriptVerificationTag(sessionID: id, messages: envelope.messages, key: key)
                            == transcriptVerificationTag(sessionID: id, messages: expected, key: key) else {
                        throw MigrationFailure.verificationFailed
                    }
                }

                let marker = MigrationMarker(
                    storageVersion: storageVersion,
                    legacyTranscriptCount: sessionIDs.count,
                    localSessionIDs: sessionIDs,
                    completedAt: Date(),
                    integrityTag: migrationIntegrityTag(sessionIDs: sessionIDs, legacy: legacy, key: key)
                )
                guard writeMigrationMarker(marker, rootURL: rootURL),
                      let storedMarker = readMigrationMarker(rootURL: rootURL),
                      migrationMarkersEquivalent(storedMarker, marker) else {
                    throw MigrationFailure.writeFailed
                }
                return .migrated(transcriptCount: sessionIDs.count)
            } catch {
                // Deliberately retain both the legacy dictionary and any already written, verified
                // candidates. A later retry may prove the complete set without data loss.
                return .failed
            }
        }
    }

    static func migrationMarkerExists(rootURL: URL = defaultRootURL()) -> Bool {
        storageQueue.sync { readMigrationMarker(rootURL: rootURL) != nil }
    }

    static func messageCount(for sessionID: UUID, rootURL: URL = defaultRootURL()) -> Int {
        if let metadata = metadata(for: sessionID, rootURL: rootURL) {
            return metadata.messageCount
        }
        // Legacy fallback only; current file-backed storage never parses bodies for a count.
        return messages(for: sessionID, rootURL: rootURL)
            .filter { $0.role == .user || $0.role == .assistant }
            .count
    }

    /// Metadata-only count for current storage. It lists only sidecars, never transcript bodies.
    static var storedTranscriptCount: Int {
        storedTranscriptCount(rootURL: defaultRootURL())
    }

    static func storedTranscriptCount(rootURL: URL) -> Int {
        storageQueue.sync {
            let fileManager = FileManager.default
            let urls = (try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            return urls.filter { $0.lastPathComponent.hasSuffix(".metadata.json") }.count
        }
    }

    static func remove(for sessionID: UUID, rootURL: URL = defaultRootURL()) {
        GrokBuildPerformance.measure(.transcriptWrite) {
            storageQueue.sync { removeLocked(for: sessionID, rootURL: rootURL) }
        }
    }

    /// Legacy resume notes added before message persistence — drop on save.
    static func isLegacyResumeNote(_ message: Message) -> Bool {
        guard message.role == .system else { return false }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("Resumed session ") && text.hasSuffix(".")
    }

    /// System note shown when grok `session/load` fell back to `session/new`.
    static func isStaleSessionFallbackNote(_ message: Message) -> Bool {
        guard message.role == .system else { return false }
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasPrefix("Previous grok session expired")
    }

    static func hasRestorableTranscript(for sessionID: UUID, rootURL: URL = defaultRootURL()) -> Bool {
        if let metadata = metadata(for: sessionID, rootURL: rootURL) {
            return metadata.restorableMessageCount > 0
        }
        return messages(for: sessionID, rootURL: rootURL).contains(where: isRestorableMessage)
    }

    /// True when local storage has no user/assistant transcript to show.
    static func needsTranscriptRecovery(_ messages: [Message]) -> Bool {
        !messages.contains(where: isRestorableMessage)
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("GrokBuild", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
    }

    private static func writeLocked(
        _ messages: [Message],
        for sessionID: UUID,
        rootURL: URL,
        existing: Envelope?,
        preserveLongerExisting _: Bool
    ) -> Metadata? {
        if let existing,
           existing.localSessionID == sessionID,
           messagesEquivalent(existing.messages, messages),
           let existingMetadata = readMetadata(for: sessionID, rootURL: rootURL),
           metadataMatches(existingMetadata, envelope: existing) {
            return existingMetadata
        }

        let generation = max((existing?.generation ?? 0) &+ 1, 1)
        let now = Date()
        let envelope = Envelope(
            localSessionID: sessionID,
            storageVersion: storageVersion,
            generation: generation,
            writtenAt: now,
            messages: messages
        )
        let metadata = Metadata(
            localSessionID: sessionID,
            storageVersion: storageVersion,
            generation: generation,
            messageCount: messages.count,
            restorableMessageCount: messages.filter(isRestorableMessage).count,
            modifiedAt: now
        )
        guard ensureStorageDirectory(rootURL: rootURL),
              let envelopeData = try? JSONEncoder().encode(envelope),
              let metadataData = try? JSONEncoder().encode(metadata),
              atomicWrite(envelopeData, to: transcriptURL(for: sessionID, rootURL: rootURL)),
              atomicWrite(metadataData, to: metadataURL(for: sessionID, rootURL: rootURL)),
              let storedEnvelope = readEnvelope(for: sessionID, rootURL: rootURL),
              envelopesEquivalent(storedEnvelope, envelope),
              let storedMetadata = readMetadata(for: sessionID, rootURL: rootURL),
              metadataMatches(storedMetadata, envelope: storedEnvelope),
              abs(storedMetadata.modifiedAt.timeIntervalSince(metadata.modifiedAt)) < 0.001 else {
            return nil
        }
        return metadata
    }

    /// Never drop a longer on-disk transcript when memory is temporarily empty or partial.
    private static func mergeTranscripts(existing: [Message], incoming: [Message]) -> [Message] {
        guard !existing.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return existing }
        if incoming.count >= existing.count {
            var result = incoming
            for index in 0..<min(existing.count, incoming.count)
            where existing[index].role == incoming[index].role {
                let oldText = existing[index].content
                let newText = incoming[index].content
                if oldText.count > newText.count && oldText.hasPrefix(newText) {
                    var preserved = existing[index]
                    // Reconciliation may briefly hand persistence a shorter
                    // display prefix after the trace has settled. Keep the
                    // longer authoritative body without discarding the newer,
                    // safe assistant disclosure.
                    if let trace = incoming[index].assistantTrace {
                        preserved.assistantTrace = trace
                    }
                    result[index] = preserved
                }
            }
            return result
        }

        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for message in incoming {
            byID[message.id] = message
        }
        var merged: [Message] = []
        var seen: Set<UUID> = []
        for message in existing {
            merged.append(byID[message.id] ?? message)
            seen.insert(message.id)
        }
        for message in incoming where !seen.contains(message.id) {
            merged.append(message)
        }
        return merged
    }

    private static func isRestorableMessage(_ message: Message) -> Bool {
        guard message.role == .user || message.role == .assistant else { return false }
        if message.role == .assistant,
           message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    private static func shouldPersist(_ message: Message) -> Bool {
        if isLegacyResumeNote(message) { return false }
        if isStaleSessionFallbackNote(message) { return false }
        if message.role == .assistant,
           message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    private static func readEnvelope(for sessionID: UUID, rootURL: URL) -> Envelope? {
        guard let data = try? Data(contentsOf: transcriptURL(for: sessionID, rootURL: rootURL)),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.storageVersion == storageVersion,
              envelope.localSessionID == sessionID else {
            return nil
        }
        return envelope
    }

    private static func readMetadata(for sessionID: UUID, rootURL: URL) -> Metadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: sessionID, rootURL: rootURL)),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: data),
              metadata.storageVersion == storageVersion,
              metadata.localSessionID == sessionID else {
            return nil
        }
        return metadata
    }

    private static func metadataMatches(_ metadata: Metadata, envelope: Envelope) -> Bool {
        metadata.localSessionID == envelope.localSessionID
            && metadata.storageVersion == envelope.storageVersion
            && metadata.generation == envelope.generation
            && metadata.messageCount == envelope.messages.count
            && metadata.restorableMessageCount == envelope.messages.filter(isRestorableMessage).count
    }

    /// Foundation's default Date JSON representation can move by a fraction of a microsecond
    /// across a decode→encode→decode cycle. Persistence verification must compare the transcript
    /// payload exactly while treating sub-millisecond timestamp representation as equivalent.
    private static func messagesEquivalent(_ lhs: [Message], _ rhs: [Message]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id
                && left.role == right.role
                && left.content == right.content
                && left.provenance == right.provenance
                && left.assistantTrace == right.assistantTrace
                && abs(left.timestamp.timeIntervalSince(right.timestamp)) < 0.001
        }
    }

    private static func envelopesEquivalent(_ lhs: Envelope, _ rhs: Envelope) -> Bool {
        lhs.localSessionID == rhs.localSessionID
            && lhs.storageVersion == rhs.storageVersion
            && lhs.generation == rhs.generation
            && abs(lhs.writtenAt.timeIntervalSince(rhs.writtenAt)) < 0.001
            && messagesEquivalent(lhs.messages, rhs.messages)
    }

    private static func migrationMarkersEquivalent(_ lhs: MigrationMarker, _ rhs: MigrationMarker) -> Bool {
        lhs.storageVersion == rhs.storageVersion
            && lhs.legacyTranscriptCount == rhs.legacyTranscriptCount
            && lhs.localSessionIDs == rhs.localSessionIDs
            && lhs.integrityTag == rhs.integrityTag
            && abs(lhs.completedAt.timeIntervalSince(rhs.completedAt)) < 0.001
    }

    private static func legacyMap(defaults: UserDefaults) -> [String: Data]? {
        defaults.dictionary(forKey: legacyStorageKey) as? [String: Data]
    }

    private static func legacyMessages(for sessionID: UUID) -> [Message] {
        guard let data = legacyMap(defaults: .standard)?[sessionID.uuidString] else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
    }

    private static func ensureStorageDirectory(rootURL: URL) -> Bool {
        let fileManager = FileManager.default
        do {
            let applicationRoot = rootURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: applicationRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: applicationRoot.path)
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
            return true
        } catch {
            return false
        }
    }

    private static func atomicWrite(_ data: Data, to url: URL) -> Bool {
        let fileManager = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: url)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            try? fileManager.removeItem(at: temporary)
            return false
        }
    }

    private static func removeLocked(for sessionID: UUID, rootURL: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: transcriptURL(for: sessionID, rootURL: rootURL))
        try? fileManager.removeItem(at: metadataURL(for: sessionID, rootURL: rootURL))
    }

    private static func transcriptURL(for sessionID: UUID, rootURL: URL) -> URL {
        rootURL.appendingPathComponent("\(sessionID.uuidString).json")
    }

    private static func metadataURL(for sessionID: UUID, rootURL: URL) -> URL {
        rootURL.appendingPathComponent("\(sessionID.uuidString).metadata.json")
    }

    private static func migrationMarkerURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent("legacy-v1-migration.json")
    }

    private static func readMigrationMarker(rootURL: URL) -> MigrationMarker? {
        guard let data = try? Data(contentsOf: migrationMarkerURL(rootURL: rootURL)) else { return nil }
        return try? JSONDecoder().decode(MigrationMarker.self, from: data)
    }

    private static func writeMigrationMarker(_ marker: MigrationMarker, rootURL: URL) -> Bool {
        guard ensureStorageDirectory(rootURL: rootURL),
              let data = try? JSONEncoder().encode(marker) else { return false }
        return atomicWrite(data, to: migrationMarkerURL(rootURL: rootURL))
    }

    private static func markerMatches(
        _ marker: MigrationMarker,
        sessionIDs: [UUID],
        legacy: [String: Data],
        key: Data
    ) -> Bool {
        marker.storageVersion == storageVersion
            && marker.legacyTranscriptCount == sessionIDs.count
            && marker.localSessionIDs == sessionIDs
            && marker.integrityTag == migrationIntegrityTag(sessionIDs: sessionIDs, legacy: legacy, key: key)
    }

    private static func migrationIntegrityTag(
        sessionIDs: [UUID],
        legacy: [String: Data],
        key: Data
    ) -> String {
        var payload = Data()
        for id in sessionIDs {
            payload.append(Data(id.uuidString.utf8))
            payload.append(0x1F)
            if let data = legacy[id.uuidString] { payload.append(data) }
            payload.append(0x1E)
        }
        return VersionedOpaqueTag.authenticationCode(
            key: key,
            domain: "session-message-store-migration",
            schemaVersion: storageVersion,
            payload: payload
        )
    }

    private static func transcriptVerificationTag(
        sessionID: UUID,
        messages: [Message],
        key: Data
    ) -> String {
        struct Fingerprint: Codable {
            let id: UUID
            let role: MessageRole
            let content: String
            let timestampMilliseconds: Int64
            let provenance: TranscriptMessageProvenance?
        }
        let fingerprints = messages.map { message in
            Fingerprint(
                id: message.id,
                role: message.role,
                content: message.content,
                timestampMilliseconds: Int64((message.timestamp.timeIntervalSince1970 * 1_000).rounded()),
                provenance: message.provenance
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = (try? encoder.encode(fingerprints)) ?? Data()
        var payload = Data(sessionID.uuidString.utf8)
        payload.append(0x1F)
        payload.append(body)
        return VersionedOpaqueTag.authenticationCode(
            key: key,
            domain: "session-message-store-copy-verification",
            schemaVersion: storageVersion,
            payload: payload
        )
    }

    private enum MigrationFailure: Error {
        case invalidSessionID
        case invalidLegacyTranscript
        case candidateMismatch
        case verificationFailed
        case writeFailed
    }
}
