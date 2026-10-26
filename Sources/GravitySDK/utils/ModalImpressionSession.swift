import Foundation

/// One logical opening, shared by frame detection, explicit close, and OPEN_STEP.
internal final class ModalImpressionSession {
    private let lock = NSRecursiveLock()
    private var appeared = false
    private var fired = false
    private var persisted = false
    private let confirm: () -> Bool
    private let release: () -> Void

    init(confirm: @escaping () -> Bool, release: @escaping () -> Void) {
        self.confirm = confirm
        self.release = release
    }

    var hasFired: Bool {
        lock.lock(); defer { lock.unlock() }
        return fired
    }

    func confirmFrame(isActive: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard isActive else { return }
        appeared = true
        fireIfNeeded()
    }

    func explicitClose(isActive: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard isActive, appeared else { return }
        fireIfNeeded()
    }

    func disappeared() {
        lock.lock(); defer { lock.unlock() }
        appeared = false
        if !persisted { release() }
    }

    private func fireIfNeeded() {
        guard !fired else { return }
        // Set before invoking callbacks, which may synchronously dismiss the UI.
        fired = true
        persisted = confirm()
    }
}
