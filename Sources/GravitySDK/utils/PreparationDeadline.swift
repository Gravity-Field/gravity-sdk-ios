import Foundation

/// An unstructured race so a handler that ignores cancellation cannot delay the deadline.
internal enum PreparationDeadline {
    static func run<Value>(
        timeout: TimeInterval,
        operation: @escaping () async throws -> Value
    ) async -> Value? {
        let race = PreparationRace<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.install(continuation)
                let work = Task {
                    do { race.finish(try await operation()) }
                    catch { race.finish(nil) }
                }
                race.add(work)
                let deadline = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        race.finish(nil)
                    } catch { }
                }
                race.add(deadline)
            }
        } onCancel: {
            race.finish(nil)
        }
    }
}

private final class PreparationRace<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var value: Value?
    private var continuation: CheckedContinuation<Value?, Never>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value?, Never>) {
        lock.lock()
        if finished {
            let value = value
            lock.unlock()
            continuation.resume(returning: value)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func add(_ task: Task<Void, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            task.cancel()
        } else {
            tasks.append(task)
            lock.unlock()
        }
    }

    func finish(_ value: Value?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        self.value = value
        let continuation = continuation
        self.continuation = nil
        let tasks = tasks
        self.tasks.removeAll()
        lock.unlock()
        tasks.forEach { $0.cancel() }
        continuation?.resume(returning: value)
    }
}
