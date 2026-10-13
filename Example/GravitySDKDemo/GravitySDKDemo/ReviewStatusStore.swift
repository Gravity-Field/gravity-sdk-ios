import Foundation

/// The client's real, durable source of truth for "has this SKU already been reviewed" —
/// `UserDefaults`-backed so it survives relaunches, unlike `ReviewPromptIntegration`'s own
/// in-memory `SubmittedReviews` (which only guards against a stale same-session result while this
/// store is the one actually consulted by `DemoReviewEligibilityAPI.eligibleSkus`).
final class ReviewStatusStore {
    static let shared = ReviewStatusStore()

    private let defaults: UserDefaults
    private let key = "com.gravityfield.demo.reviewedSkus"
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func reviewedSkus() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(defaults.stringArray(forKey: key) ?? [])
    }

    func markReviewed(_ sku: String) {
        lock.lock()
        var skus = Set(defaults.stringArray(forKey: key) ?? [])
        skus.insert(sku)
        defaults.set(Array(skus), forKey: key)
        lock.unlock()
    }

    /// For the demo's own "reset state" affordance — a real backend wouldn't need this.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}
