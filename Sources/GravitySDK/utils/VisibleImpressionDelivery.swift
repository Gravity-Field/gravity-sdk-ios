import Foundation
#if canImport(Network)
import Network
#endif

/// Coalesces duplicate visibility callbacks for the same event URL and retries
/// transient delivery failures without re-sending URLs already acknowledged.
internal actor VisibleImpressionDelivery {
    private struct Flight {
        let id: UUID
        let task: Task<Bool, Never>
    }

    nonisolated let store: VisibleImpressionStore?
    private let discarded: (VisibleImpressionStore.Entry) -> Void
    private let acknowledged: (VisibleImpressionStore.Entry) -> Void
    private var drainFlight: (id: UUID, task: Task<Void, Never>)?
    private var stopped = false
    private var suspended: Bool
    private var permanentFailures: Set<String> = []
    private var retryTask: Task<Void, Never>?
    #if canImport(Network)
    private var monitor: NWPathMonitor?
    #endif

    private let send: (String) async throws -> Void
    private let retryable: (Error) -> Bool
    private let sleep: (UInt64) async throws -> Void
    private var flights: [String: Flight] = [:]
    private var delivered: [String: TimeInterval] = [:]
    // Keep successful durable sends until their local removal succeeds (bounded by the queue TTL).
    private var durableDelivered: Set<String> = []

    init(send: @escaping (String) async throws -> Void,
         retryable: @escaping (Error) -> Bool = { _ in true },
         sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
         store: VisibleImpressionStore? = nil,
         startsSuspended: Bool = false,
         discarded: @escaping (VisibleImpressionStore.Entry) -> Void = { _ in },
         acknowledged: @escaping (VisibleImpressionStore.Entry) -> Void = { _ in }) {
        self.suspended = startsSuspended
        self.store = store
        self.discarded = discarded
        self.acknowledged = acknowledged
        self.send = send
        self.retryable = retryable
        self.sleep = sleep
    }

    /// Owned by the SDK rather than the UI. Resume at initialization and every network restore.
    func start() async {
        guard !stopped else { return }
        suspended = false
        #if canImport(Network)
        if monitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                if path.status == .satisfied { Task { await self?.resumePending() } }
            }
            self.monitor = monitor
            monitor.start(queue: DispatchQueue(label: "GravitySDK.WRIMP.network"))
        }
        #endif
        await resumePending()
    }

    func stop() async {
        stopped = true
        retryTask?.cancel()
        retryTask = nil
        #if canImport(Network)
        monitor?.cancel()
        monitor = nil
        #endif
        // SDK reinitialization waits for the old sender before starting its successor.
        // Ordinary UI dismissal never calls stop and never cancels a delivery.
        if let flight = drainFlight { await flight.task.value }
    }

    func resumePending() async {
        guard store != nil, !stopped, !suspended else { return }
        if let flight = drainFlight { await flight.task.value; return }
        let id = UUID()
        let task = Task { await self.drainPending() }
        drainFlight = (id, task)
        await task.value
        if drainFlight?.id == id { drainFlight = nil }
    }

    private func drainPending() async {
        guard let store, !stopped else { return }
        retryTask?.cancel()
        retryTask = nil
        try? store.prune()
        let liveKeys = Set(store.entries.flatMap { entry in entry.urls.map { entry.id.uuidString + $0 } })
        durableDelivered.formIntersection(liveKeys)
        var attempted: Set<UUID> = []
        while let entry = store.entries.first(where: { !attempted.contains($0.id) }) {
            attempted.insert(entry.id)
            for url in entry.urls {
                guard !stopped else { return }
                let key = entry.id.uuidString + url
                // Durable events are coalesced by opening ID, not a session-wide URL cache.
                // A fresh allowed opening may legitimately reuse an identical tracking URL.
                if await deliver(url: url, cacheKey: key) {
                    if store.entries.first(where: { $0.id == entry.id })?.urls.allSatisfy({ $0 == url }) == true {
                        acknowledged(entry)
                    }
                    do {
                        try store.acknowledge(id: entry.id, url: url)
                        durableDelivered.remove(key)
                    }
                    catch { /* Keep the durable event and protection if the disk write fails. */ }
                } else if permanentFailures.contains(key) {
                    do {
                        try store.discard(id: entry.id)
                    } catch { /* The original timestamp bounds any stale disk copy. */ }
                    permanentFailures.remove(key)
                    durableDelivered = durableDelivered.filter { !$0.hasPrefix(entry.id.uuidString) }
                    discarded(entry)
                    break
                }
            }
        }
        if !stopped, !store.entries.isEmpty {
            retryTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { return }
                await self?.resumePending()
            }
        }
    }

    func deliver(urls: [String]) async -> Bool {
        guard !urls.isEmpty else { return false }
        var success = true
        for url in Set(urls) {
            let result = await deliver(url: url)
            success = success && result
        }
        return success
    }

    private func deliver(url: String, cacheKey: String? = nil) async -> Bool {
        let key = cacheKey ?? url
        if cacheKey != nil, durableDelivered.contains(key) { return true }
        let time = ProcessInfo.processInfo.systemUptime
        delivered = delivered.filter { time - $0.value < 900 }
        if delivered[key] != nil { return true }
        if let flight = flights[key] { return await flight.task.value }

        let id = UUID()
        let task = Task { [send, retryable, sleep] in
            for attempt in 0..<3 {
                do {
                    try Task.checkCancellation()
                    try await send(url)
                    return true
                } catch is CancellationError {
                    return false
                } catch {
                    guard retryable(error) else {
                        if cacheKey != nil { self.permanentFailures.insert(key) }
                        return false
                    }
                    guard attempt < 2 else { return false }
                    do { try await sleep(attempt == 0 ? 250_000_000 : 1_000_000_000) }
                    catch { return false }
                }
            }
            return false
        }
        flights[key] = Flight(id: id, task: task)
        let success = await task.value
        if flights[key]?.id == id { flights.removeValue(forKey: key) }
        if success {
            if cacheKey != nil { durableDelivered.insert(key) }
            delivered[key] = ProcessInfo.processInfo.systemUptime
            if delivered.count > 512, let oldest = delivered.min(by: { $0.value < $1.value })?.key {
                delivered.removeValue(forKey: oldest)
            }
        }
        return success
    }
}
