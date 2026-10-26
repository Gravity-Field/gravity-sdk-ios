import Foundation

/// Bounded durable storage. Reads/writes are synchronous so a frame/explicit close
/// cannot outrun persistence; network delivery always follows the atomic write.
internal final class VisibleImpressionStore {
    static let deliveryTimeToLive: TimeInterval = 7 * 24 * 60 * 60
    static let protectionWindow: TimeInterval = 24 * 60 * 60
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

    // Serialize sweeping with this process's atomic writers, including other namespaces.
    private static let diskLock = NSRecursiveLock()
    private static var sweepOffset = 0
    private static let sweepScanLimit = 256
    private static let sweepRemovalLimit = 32

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
         log: @escaping (String) -> Void = { _ in }) {
        self.fileURL = fileURL
        self.now = now
        self.log = log
        sweepExpiredNamespaces()
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

    /// Protection expires independently of delivery, even during an in-flight send.
    func protects(scope: String, campaignId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let time = now()
        return liveEntries().contains {
            $0.scope == scope && $0.campaignId == campaignId &&
            time.timeIntervalSince($0.createdAt ?? .distantPast) < Self.protectionWindow
        }
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
        guard try JSONEncoder().encode([entry]).count <= Self.maximumBytes else { throw StoreError.capacityExceeded }
        let next = try bounded(liveEntries() + [entry], keeping: entry.id)
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
        let next = try bounded(liveEntries())
        if next.count != pending.count { pending = next; try save(next) }
    }

    private func liveEntries() -> [Entry] {
        let time = now()
        return pending.filter {
            !$0.urls.isEmpty && ($0.rejectedUrls ?? []).isEmpty &&
            time.timeIntervalSince($0.createdAt ?? .distantPast) < Self.deliveryTimeToLive
        }
    }

    private func bounded(_ entries: [Entry], keeping id: UUID? = nil) throws -> [Entry] {
        let incoming = entries.first { $0.id == id }
        var sorted = Array(entries.filter { $0.id != id }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
            .suffix(Self.maximumEntries - (incoming == nil ? 0 : 1)))
        if let incoming { sorted.append(incoming) }
        sorted.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        // Array JSON size = encoded records + commas + brackets. Encode each record once,
        // then evict the oldest existing records, preserving the accepted incoming WRIMP.
        let encoder = JSONEncoder()
        let sizes = try sorted.map { try encoder.encode($0).count }
        var bytes = 2 + sizes.reduce(0, +) + max(0, sizes.count - 1)
        var dropped: Set<Int> = []
        for index in sorted.indices where bytes > Self.maximumBytes && sorted[index].id != id {
            bytes -= sizes[index] + (sorted.count - dropped.count > 1 ? 1 : 0)
            dropped.insert(index)
        }
        return sorted.indices.filter { !dropped.contains($0) }.map { sorted[$0] }
    }

    private func sweepExpiredNamespaces() {
        Self.diskLock.lock(); defer { Self.diskLock.unlock() }
        let directory = fileURL.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).sorted(by: { $0.path < $1.path }),
            !files.isEmpty else { return }
        let start = Self.sweepOffset % files.count
        var removed = 0
        for step in 0..<min(files.count, Self.sweepScanLimit) {
            let index = (start + step) % files.count
            Self.sweepOffset = (index + 1) % files.count
            let candidate = files[index]
            guard candidate.standardizedFileURL != fileURL.standardizedFileURL,
                  ["json", "corrupt"].contains(candidate.pathExtension),
                  let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate,
                  now().timeIntervalSince(modified) > Self.deliveryTimeToLive else { continue }
            do {
                try FileManager.default.removeItem(at: candidate)
                removed += 1
            } catch { log("Unable to remove expired WRIMP namespace file") }
            if removed == Self.sweepRemovalLimit { break }
        }
    }

    private func requireReadable() throws {
        if unreadable { load() }
        guard !unreadable else { throw StoreError.unreadable }
    }

    private func load() {
        Self.diskLock.lock(); defer { Self.diskLock.unlock() }
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
        do {
            let next = try bounded(liveEntries())
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
        Self.diskLock.lock(); defer { Self.diskLock.unlock() }
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
