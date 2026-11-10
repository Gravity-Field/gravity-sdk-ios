import Foundation

/// Internal seam for automatic-delay deadlines and deterministic suspension tests.
/// Swift's Dispatch-backed Task.sleep(nanoseconds:) schedules relative to
/// DISPATCH_TIME_NOW; uptimeNanoseconds uses that same monotonic clock family.
internal struct CampaignDelayTiming {
    var now: () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    var sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
}
