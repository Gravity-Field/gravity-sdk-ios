import Foundation

/// Bounded durable storage. Reads/writes are synchronous so a frame/explicit close
/// cannot outrun persistence; network delivery always follows the atomic write.
internal final class VisibleImpressionStore {
    static let timeToLive: TimeInterval = 7 * 24 * 60 * 60
    static let maximumEntries = 256
    static let maximumBytes = 1_048_576

    struct Entry: Codable {
        let id: UUID
        let scope: String
        let campaignId: String
        let contentId: String
        var urls: [String]
        let user: String
        var createdAt: Date? = Date()
        // Read compatibility with the first outbox version; legacy rejected events are dropped.
        var rejectedUrls: [String]? = nil
    }

    enum StoreError: Error { case unreadable, capacityExceeded }

    private let lock = NSLock()
    let fileURL: URL
    private let now: () -> Date
    private let log: (String) -> Void
    private var pending: [Entry] = []
    private var inserted: (() -> Void)?
    private var unreadable = false
    private var reportedReadFailure = false
    private var directoryPrepared = false

    init(fileURL: URL, now: @escaping () -> Date = Date.init,
         log: @escaping (String) -> Void = { NSLog("[GravitySDK] [WRIMPStore] %@", $0) }) {
        self.fileURL = fileURL
        self.now = now
        self.log = log
        load()
    }

    var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return liveEntries()
    }

    func contains(scope: String, campaignId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return liveEntries().contains { $0.scope == scope && $0.campaignId == campaignId }
    }

    func observeInsert(_ callback: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        inserted = callback
    }

    func insert(_ entry: Entry) throws {
        lock.lock()
        var notify: (() -> Void)?
        defer { lock.unlock(); notify?() }
        try requireReadable()
        guard !pending.contains(where: { $0.id == entry.id }) else { return }
        var entry = entry
        entry.createdAt = min(entry.createdAt ?? now(), now())
        let next = bounded(liveEntries() + [entry])
        try save(next)
        notify = inserted
    }

    func acknowledge(id: UUID, url: String) throws {
        lock.lock(); defer { lock.unlock() }
        try requireReadable()
        var next = liveEntries()
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].urls.removeAll { $0 == url }
        if next[index].urls.isEmpty { next.remove(at: index) }
        try save(next)
    }

    /// Terminal failure/TTL/eviction is not a server ACK and never creates an ACK fence.
    func discard(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        try requireReadable()
        pending.removeAll { $0.id == id }
        // Release in-memory protection even if the disk has become unwritable.
        // A stale disk copy is still bounded by its original creation timestamp.
        try save(liveEntries())
    }

    func prune() throws {
        lock.lock(); defer { lock.unlock() }
        try requireReadable()
        let next = bounded(liveEntries())
        if next.count != pending.count { pending = next; try save(next) }
    }

    private func liveEntries() -> [Entry] {
        let time = now()
        return pending.filter {
            !$0.urls.isEmpty && ($0.rejectedUrls ?? []).isEmpty &&
            time.timeIntervalSince($0.createdAt ?? .distantPast) < Self.timeToLive
        }
    }

    private func bounded(_ entries: [Entry]) -> [Entry] {
        Array(entries.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .suffix(Self.maximumEntries))
    }

    private func requireReadable() throws {
        if unreadable { load() }
        guard !unreadable else { throw StoreError.unreadable }
    }

    private func load() {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoSuchFileError {
                unreadable = false
                return
            }
            unreadable = true
            if !reportedReadFailure { log("Unable to read WRIMP queue; preserving file for a later retry") }
            reportedReadFailure = true
            return
        }
        unreadable = false
        reportedReadFailure = false
        var corrupt = false
        var migrated = false
        var decoded: [Entry] = []
        if data.count <= Self.maximumBytes,
           let values = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            for value in values {
                if JSONSerialization.isValidJSONObject(value),
                   let bytes = try? JSONSerialization.data(withJSONObject: value),
                   var entry = try? JSONDecoder().decode(Entry.self, from: bytes) {
                    if entry.createdAt == nil || entry.createdAt! > now() {
                        entry.createdAt = now()
                        migrated = true
                    }
                    decoded.append(entry)
                } else { corrupt = true }
            }
        } else { corrupt = true }
        pending = decoded
        if corrupt {
            do {
                let quarantine = fileURL.appendingPathExtension("corrupt")
                if FileManager.default.fileExists(atPath: quarantine.path) { try FileManager.default.removeItem(at: quarantine) }
                try FileManager.default.moveItem(at: fileURL, to: quarantine)
                log("Corrupt WRIMP queue quarantined; valid entries recovered")
            } catch {
                unreadable = true
                log("Unable to quarantine WRIMP queue; original file preserved")
                return
            }
        }
        let next = bounded(liveEntries())
        do {
            try prepareDirectory()
            if corrupt || migrated || next.count != decoded.count { try save(next) }
            else { try excludeFromBackup(fileURL) }
        } catch { log("Unable to update WRIMP queue storage metadata or recovered entries") }
    }

    private func prepareDirectory() throws {
        guard !directoryPrepared else { return }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackup(directory)
        directoryPrepared = true
    }

    private func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func save(_ entries: [Entry]) throws {
        let bytes = try JSONEncoder().encode(entries)
        guard bytes.count <= Self.maximumBytes else { throw StoreError.capacityExceeded }
        try prepareDirectory()
        try bytes.write(to: fileURL, options: .atomic)
        pending = entries
        // Atomic replacement creates a new file; reapply the no-backup attribute.
        do { try excludeFromBackup(fileURL) }
        catch { log("Unable to exclude WRIMP queue file from backup") }
    }
}
