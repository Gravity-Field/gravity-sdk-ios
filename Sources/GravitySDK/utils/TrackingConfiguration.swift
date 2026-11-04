import Foundation

/// Shared by SDK instances and the placeholder, independently of SDK initialization.
internal final class TrackingConfiguration {
    private let lock = NSLock()
    private var fetch = true
    private var age: TimeInterval = 10
    var fetchContent: Bool {
        get { lock.lock(); defer { lock.unlock() }; return fetch }
        set { lock.lock(); defer { lock.unlock() }; fetch = newValue }
    }
    var timeout: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return age }
        set { lock.lock(); defer { lock.unlock() }; age = newValue }
    }
}
