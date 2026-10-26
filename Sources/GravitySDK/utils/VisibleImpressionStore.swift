import Foundation

/// Synchronous atomic persistence is intentional: UI teardown must never race an enqueue.
/// The original URL already identifies the user/event; user is a snapshot for scope isolation,
/// never a replacement identity to append to a retry request.
internal final class VisibleImpressionStore {
    struct Entry: Codable {
        let id: UUID
        let scope: String
        let campaignId: String
        let contentId: String
        var urls: [String]
        let user: String
        var rejectedUrls: [String]? = nil
    }

    private let lock = NSLock()
    private let fileURL: URL
    private var pending: [Entry]
    private var inserted: (() -> Void)?

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            pending = entries
        } else {
            pending = []
        }
    }

    var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    func contains(scope: String, campaignId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pending.contains { $0.scope == scope && $0.campaignId == campaignId }
    }

    func observeInsert(_ callback: @escaping () -> Void) {
        lock.lock(); defer { lock.unlock() }
        inserted = callback
    }

    func insert(_ entry: Entry) throws {
        lock.lock()
        var notify: (() -> Void)?
        defer { lock.unlock(); notify?() }
        guard !pending.contains(where: { $0.id == entry.id }) else { return }
        try save(pending + [entry])
        notify = inserted
    }

    func acknowledge(id: UUID, url: String) throws {
        lock.lock(); defer { lock.unlock() }
        var next = pending
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].urls.removeAll { $0 == url }
        if next[index].urls.isEmpty { next.remove(at: index) }
        try save(next)
    }

    func reject(id: UUID, url: String) throws {
        lock.lock(); defer { lock.unlock() }
        var next = pending
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].rejectedUrls = Array(Set((next[index].rejectedUrls ?? []) + [url]))
        try save(next)
    }

    private func save(_ entries: [Entry]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        pending = entries
    }
}
