import Foundation

/// Bounded durable storage. UI enqueue establishes protection immediately; a serial
/// worker persists it before notifying delivery. Presentation awaits initial restoration.
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
    private let ioQueue: DispatchQueue
    let fileURL: URL
    private let now: () -> Date
    private let log: (String) -> Void
    // UI gate reads this snapshot without waiting for a disk mutation to finish.
    private let protectionLock = NSLock()
    private var protectionSnapshot: [Entry] = []
    private var stagedProtection: [UUID: Entry] = [:]
    private var loading = false
    private var encodedSizes: [UUID: Int] = [:]
    private var pending: [Entry] = [] {
        didSet {
            protectionLock.lock()
            protectionSnapshot = pending
            protectionLock.unlock()
        }
    }
    private var inserted: (() -> Void)?
    private var unreadable = false
    private var reportedReadFailure = false
    private var directoryPrepared = false

    init(fileURL: URL, now: @escaping () -> Date = Date.init,
         log: @escaping (String) -> Void = { _ in },
         loadsAsynchronously: Bool = false,
         ioQueue: DispatchQueue = DispatchQueue(label: "GravitySDK.WRIMP.store", qos: .userInitiated),
         scheduleMaintenance: @escaping (@escaping () -> Void) -> Void = { work in
             DispatchQueue.global(qos: .utility).async(execute: DispatchWorkItem(block: work))
         }) {
        self.fileURL = fileURL
        self.now = now
        self.log = log
        self.ioQueue = ioQueue
        let sweepTime = now()
        let read = { [self] in
            lock.lock()
            load()
            lock.unlock()
            protectionLock.lock()
            loading = false
            protectionLock.unlock()
            scheduleMaintenance { [self] in sweepExpiredNamespaces(at: sweepTime) }
        }
        if loadsAsynchronously {
            loading = true
            ioQueue.async(execute: DispatchWorkItem(block: read))
        } else { read() }
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
        protectionLock.lock()
        let snapshot = protectionSnapshot + Array(stagedProtection.values)
        protectionLock.unlock()
        let time = now()
        return snapshot.contains {
            $0.scope == scope && $0.campaignId == campaignId &&
            !$0.urls.isEmpty && ($0.rejectedUrls ?? []).isEmpty &&
            time.timeIntervalSince($0.createdAt ?? .distantPast) < Self.protectionWindow
        }
    }

    func observeInsert(_ callback: @escaping () -> Void) {
        protectionLock.lock(); defer { protectionLock.unlock() }
        inserted = callback
    }

    /// The staged entry protects re-open immediately, including while the UI disappears.
    /// It is deliberately absent from delivery's entries until the atomic write succeeds.
    func enqueue(_ entry: Entry, completion: @escaping (Result<Void, Error>) -> Void) {
        protectionLock.lock()
        stagedProtection[entry.id] = entry
        protectionLock.unlock()
        ioQueue.async { [self] in
            do {
                try insert(entry, beforeNotification: {
                    self.removeStaged(entry.id)
                    completion(.success(()))
                })
            } catch {
                removeStaged(entry.id)
                completion(.failure(error))
            }
        }
    }

    private func removeStaged(_ id: UUID) {
        protectionLock.lock(); defer { protectionLock.unlock() }
        stagedProtection.removeValue(forKey: id)
    }

    private var isLoading: Bool {
        protectionLock.lock(); defer { protectionLock.unlock() }
        return loading
    }

    /// Call before automatic presentation decisions, rather than treating unknown
    /// protection as a campaign ban. Timeout/cancellation never block the main thread.
    func waitUntilLoaded(timeout: TimeInterval = 5) async -> Bool {
        guard !Task.isCancelled else { return false }
        guard isLoading else { return true }
        guard timeout.isFinite, timeout > 0, timeout <= 60 else { return false }
        return await PreparationDeadline.run(timeout: timeout) { [self] in
            await waitForPendingWrites()
            return true
        } ?? false
    }

    func waitForPendingWrites() async {
        await withCheckedContinuation { continuation in
            ioQueue.async { continuation.resume() }
        }
    }

    func insert(_ entry: Entry, beforeNotification: () -> Void = {}) throws {
        lock.lock()
        var notify: (() -> Void)?
        var persisted = false
        defer {
            lock.unlock()
            if persisted { beforeNotification() }
            notify?()
        }
        try requireReadable()
        guard !pending.contains(where: { $0.id == entry.id }) else { persisted = true; return }
        var entry = entry
        entry.createdAt = min(entry.createdAt ?? now(), now())
        guard try JSONEncoder().encode([entry]).count <= Self.maximumBytes else { throw StoreError.capacityExceeded }
        let next = try bounded(liveEntries() + [entry], keeping: entry.id)
        try save(next)
        persisted = true
        protectionLock.lock()
        notify = inserted
        protectionLock.unlock()
    }

    func acknowledge(id: UUID, url: String) throws {
        lock.lock(); defer { lock.unlock() }
        try requireReadable()
        var next = liveEntries()
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].urls.removeAll { $0 == url }
        encodedSizes.removeValue(forKey: id)
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
        let ids = Set(sorted.map { $0.id })
        encodedSizes = encodedSizes.filter { ids.contains($0.key) }
        let sizes = try sorted.map { entry -> Int in
            if let size = encodedSizes[entry.id] { return size }
            let size = try encoder.encode(entry).count
            encodedSizes[entry.id] = size
            return size
        }
        var bytes = 2 + sizes.reduce(0, +) + max(0, sizes.count - 1)
        var dropped: Set<Int> = []
        for index in sorted.indices where bytes > Self.maximumBytes && sorted[index].id != id {
            bytes -= sizes[index] + (sorted.count - dropped.count > 1 ? 1 : 0)
            dropped.insert(index)
        }
        return sorted.indices.filter { !dropped.contains($0) }.map { sorted[$0] }
    }

    private func sweepExpiredNamespaces(at time: Date) {
        let directory = fileURL.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).sorted(by: { $0.path < $1.path }),
            !files.isEmpty else { return }
        Self.diskLock.lock()
        let start = Self.sweepOffset % files.count
        Self.diskLock.unlock()
        var removed = 0
        for step in 0..<min(files.count, Self.sweepScanLimit) {
            // Check metadata and remove atomically against writers, but yield the disk
            // lock between candidates so one sweep cannot hold it for the whole scan.
            Self.diskLock.lock(); defer { Self.diskLock.unlock() }
            let index = (start + step) % files.count
            Self.sweepOffset = (index + 1) % files.count
            let candidate = files[index]
            guard candidate.standardizedFileURL != fileURL.standardizedFileURL,
                  ["json", "corrupt"].contains(candidate.pathExtension),
                  let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate,
                  time.timeIntervalSince(modified) > Self.deliveryTimeToLive else { continue }
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
        // Old quarantines may contain a full User snapshot. They are diagnostics only.
        let quarantine = fileURL.appendingPathExtension("corrupt")
        if FileManager.default.fileExists(atPath: quarantine.path) {
            do { try FileManager.default.removeItem(at: quarantine) }
            catch { log("Unable to remove legacy WRIMP quarantine") }
        }
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
                    if (value as? [String: Any])?["user"] != nil { migrated = true }
                    decoded.append(entry)
                } else { corrupt = true }
            }
        } else { corrupt = true }
        encodedSizes.removeAll()
        pending = decoded
        if corrupt { log("Corrupt WRIMP queue detected; recovering valid minimal records") }
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
        #if os(iOS)
        try bytes.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try bytes.write(to: fileURL, options: .atomic)
        #endif
        pending = entries
        // Atomic replacement creates a new file; reapply the no-backup attribute.
        do { try excludeFromBackup(fileURL) }
        catch { log("Unable to exclude WRIMP queue file from backup") }
    }
}
