import Foundation

/// Monotonic time and cancellable waiting used by in-app presentation.
internal struct PresentationTiming {
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
}
