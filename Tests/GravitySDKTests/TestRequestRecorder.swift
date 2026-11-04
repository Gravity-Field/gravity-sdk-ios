import Foundation

/// Request-driven synchronization shared by URLProtocol fixtures.
final class TestRequestRecorder<Request>: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [Request] = []
    private var waiters: [UUID: (count: Int, continuation: CheckedContinuation<[Request], Never>)] = [:]

    var values: [Request] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        requests.removeAll()
    }

    func append(_ request: Request) {
        lock.lock()
        requests.append(request)
        let ready = waiters.filter { requests.count >= $0.value.count }
        for id in ready.keys { waiters.removeValue(forKey: id) }
        let snapshot = requests
        lock.unlock()
        for waiter in ready.values { waiter.continuation.resume(returning: snapshot) }
    }

    func waitFor(_ count: Int, timeout: TimeInterval = 10) async -> [Request] {
        await withCheckedContinuation { continuation in
            lock.lock()
            if requests.count >= count {
                let snapshot = requests
                lock.unlock()
                continuation.resume(returning: snapshot)
                return
            }
            let id = UUID()
            waiters[id] = (count, continuation)
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                self.lock.lock()
                let waiter = self.waiters.removeValue(forKey: id)
                let snapshot = self.requests
                self.lock.unlock()
                waiter?.continuation.resume(returning: snapshot)
            }
        }
    }
}
