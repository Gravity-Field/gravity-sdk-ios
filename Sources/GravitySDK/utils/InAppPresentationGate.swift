import Foundation

/// Bridges the gap between /choose and the WRIMP acknowledgement. This is not a
/// frequency cap: after acknowledgement, subsequent requests use the server's policy.
internal final class InAppPresentationGate {
    struct Request {
        let sequence: UInt64
        let generation: UInt64
        let screen: UInt64
    }

    struct Reservation: Equatable {
        let id: UInt64
        let campaignId: String
        let generation: UInt64
        let screen: UInt64
    }

    private struct Pending {
        let reservation: Reservation
        var contentIds: Set<String> = []
        var visible = false
        var durable = false
        var expiresAt: TimeInterval?
    }

    var deliveryScope: () -> String = { "" }
    var deliveryPending: (String) -> Bool = { _ in false }

    private let lock = NSRecursiveLock()
    private let now: () -> TimeInterval
    private let acknowledgementTimeout: TimeInterval
    private var sequence: UInt64 = 0
    private var generation: UInt64 = 0
    private var screen: UInt64 = 0
    private var location: String?
    private var pending: [String: Pending] = [:]
    private var confirmedThrough: [String: UInt64] = [:]

    init(acknowledgementTimeout: TimeInterval = 60,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.acknowledgementTimeout = acknowledgementTimeout
        self.now = now
    }

    func scoped<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func beginRequest(location: String, newScreen: Bool) -> Request {
        lock.lock()
        defer { lock.unlock() }
        sequence &+= 1
        if newScreen || self.location != location {
            screen &+= 1
            self.location = location
            pending = pending.filter { $0.value.visible || $0.value.expiresAt != nil }
        }
        return Request(sequence: sequence, generation: generation, screen: screen)
    }

    func isCurrent(_ request: Request) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return request.generation == generation && request.screen == screen
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        pending.removeAll()
        confirmedThrough.removeAll()
        location = nil
    }

    func reserve(campaignId: String, request: Request) -> Reservation? {
        lock.lock()
        defer { lock.unlock() }
        removeExpired()
        guard isCurrent(request), !deliveryPending(campaignId), pending[campaignId] == nil,
              request.sequence > (confirmedThrough[campaignId] ?? 0) else { return nil }
        sequence &+= 1
        let reservation = Reservation(id: sequence, campaignId: campaignId,
                                      generation: generation, screen: screen)
        pending[campaignId] = Pending(reservation: reservation)
        return reservation
    }

    /// Runs on the UI thread. The scope check and presentation cannot interleave
    /// with setUser or a new screen notification.
    func present(_ reservation: Reservation, contentIds: [String], show: () -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard reservation.generation == generation, reservation.screen == screen,
              reservation.id > (confirmedThrough[reservation.campaignId] ?? 0),
              !deliveryPending(reservation.campaignId),
              var entry = pending[reservation.campaignId],
              entry.reservation == reservation else { return false }
        entry.contentIds.formUnion(contentIds)
        entry.expiresAt = now() + acknowledgementTimeout
        pending[reservation.campaignId] = entry
        let shown = show()
        if !shown { cancel(reservation) }
        return shown
    }

    func cancel(_ reservation: Reservation) {
        lock.lock()
        defer { lock.unlock() }
        if pending[reservation.campaignId]?.reservation == reservation {
            pending.removeValue(forKey: reservation.campaignId)
        }
    }

    func visible(contentId: String, durable: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        guard let campaignId = campaign(for: contentId) else { return }
        pending[campaignId]?.visible = true
        if durable {
            pending[campaignId]?.durable = true
            pending[campaignId]?.expiresAt = nil
        }
    }

    func closed(contentId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let campaignId = campaign(for: contentId),
              pending[campaignId]?.visible == false else { return }
        pending.removeValue(forKey: campaignId)
    }

    func discardDelivery(scope: String, campaignId: String, contentId: String) {
        lock.lock(); defer { lock.unlock() }
        guard deliveryScope() == scope, !deliveryPending(campaignId),
              pending[campaignId]?.durable == true,
              pending[campaignId]?.contentIds.contains(contentId) == true else { return }
        pending.removeValue(forKey: campaignId)
    }

    func acknowledgeDelivery(scope: String, campaignId: String, contentId: String) {
        lock.lock(); defer { lock.unlock() }
        guard deliveryScope() == scope else { return }
        // A reloaded queue has no in-memory reservation, but requests that started
        // while it was pending must still be fenced off after the ACK.
        confirmedThrough[campaignId] = sequence
        trimConfirmed()
        if pending[campaignId]?.contentIds.contains(contentId) == true {
            pending.removeValue(forKey: campaignId)
        }
    }

    func acknowledged(contentId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let campaignId = campaign(for: contentId) else { return }
        // A response from a request started before this ACK may still contain
        // the campaign. Do not let it re-present after the reservation is released.
        confirmedThrough[campaignId] = sequence
        pending.removeValue(forKey: campaignId)
        trimConfirmed()
    }

    private func trimConfirmed() {
        if confirmedThrough.count > 512,
           let oldest = confirmedThrough.min(by: { $0.value < $1.value })?.key {
            confirmedThrough.removeValue(forKey: oldest)
        }
    }

    private func campaign(for contentId: String) -> String? {
        pending.first { $0.value.contentIds.contains(contentId) }?.key
    }

    private func removeExpired() {
        let time = now()
        pending = pending.filter { campaignId, entry in
            if entry.durable { return deliveryPending(campaignId) }
            return entry.expiresAt.map { $0 > time } ?? true
        }
    }
}
