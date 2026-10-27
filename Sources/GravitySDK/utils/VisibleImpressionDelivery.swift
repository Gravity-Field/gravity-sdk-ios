import Foundation

/// Coalesces duplicate visibility callbacks for the same event URL and retries
/// transient delivery failures without re-sending URLs already acknowledged.
internal actor VisibleImpressionDelivery {
    private struct Flight {
        let id: UUID
        let task: Task<Bool, Never>
    }

    private let send: (String) async throws -> Void
    private let retryable: (Error) -> Bool
    private let sleep: (UInt64) async throws -> Void
    private var flights: [String: Flight] = [:]
    private var delivered: [String: TimeInterval] = [:]

    init(send: @escaping (String) async throws -> Void,
         retryable: @escaping (Error) -> Bool = { _ in true },
         sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.send = send
        self.retryable = retryable
        self.sleep = sleep
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

    private func deliver(url: String) async -> Bool {
        let time = ProcessInfo.processInfo.systemUptime
        delivered = delivered.filter { time - $0.value < 900 }
        if delivered[url] != nil { return true }
        if let flight = flights[url] { return await flight.task.value }

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
                    guard attempt < 2, retryable(error) else { return false }
                    do { try await sleep(attempt == 0 ? 250_000_000 : 1_000_000_000) }
                    catch { return false }
                }
            }
            return false
        }
        flights[url] = Flight(id: id, task: task)
        let success = await task.value
        if flights[url]?.id == id { flights.removeValue(forKey: url) }
        if success {
            delivered[url] = ProcessInfo.processInfo.systemUptime
            if delivered.count > 512, let oldest = delivered.min(by: { $0.value < $1.value })?.key {
                delivered.removeValue(forKey: oldest)
            }
        }
        return success
    }
}
