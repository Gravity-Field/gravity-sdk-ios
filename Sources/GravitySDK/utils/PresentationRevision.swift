import Foundation

/// Invalidates in-flight presentation work even if a user changes A -> B -> A.
internal final class PresentationRevision {
    private let lock = NSLock()
    private var revision: UInt64 = 0

    var current: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }

    func invalidate() {
        lock.lock()
        revision &+= 1
        lock.unlock()
    }

    func canPresent(expected: UInt64, active: Bool, locked: Bool, cancelled: Bool) -> Bool {
        current == expected && active && !locked && !cancelled
    }
}
