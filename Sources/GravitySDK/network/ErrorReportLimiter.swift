import Foundation
import CryptoKit

/// Bounds backend diagnostics before identity lookup, encoding or transport.
/// Failed attempts consume the rolling budget, but never mark a report as delivered.
internal final class ErrorReportLimiter {
    struct Permit {
        fileprivate let fingerprint: Data
        fileprivate let id: UUID
    }

    private let lock = NSLock()
    private let now: () -> TimeInterval
    private let limit: Int
    private let window: TimeInterval = 60
    private var attempts: [TimeInterval] = []
    private var delivered: [Data: TimeInterval] = [:]
    private var inFlight: [Data: UUID] = [:]

    init(limit: Int = 10, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.limit = max(0, limit)
        self.now = now
    }

    func begin(message: String, stacktrace: String) -> Permit? {
        lock.lock()
        defer { lock.unlock() }
        let time = now()
        attempts.removeAll { time - $0 >= window }
        delivered = delivered.filter { time - $0.value < window }
        // Reject a spent budget before even hashing the report; bound hung requests too.
        guard attempts.count < limit, inFlight.count < limit else { return nil }
        // Fingerprint exactly the sanitized, bounded free text carried by a report.
        // Keep the cheap budget check above this work.
        let message = ReportSanitizer.sanitizeText(message, limit: 1000)
        let stacktrace = ReportSanitizer.sanitizeText(stacktrace, limit: 5000)
        var hash = SHA256()
        // A length prefix keeps different message/stack tuples distinct, including NULs.
        var length = UInt64(message.utf8.count).bigEndian
        withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
        hash.update(data: Data(message.utf8))
        hash.update(data: Data(stacktrace.utf8))
        let fingerprint = Data(hash.finalize())
        guard delivered[fingerprint] == nil, inFlight[fingerprint] == nil else { return nil }
        let permit = Permit(fingerprint: fingerprint, id: UUID())
        attempts.append(time)
        inFlight[fingerprint] = permit.id
        return permit
    }

    func complete(_ permit: Permit, delivered successfully: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard inFlight[permit.fingerprint] == permit.id else { return }
        inFlight.removeValue(forKey: permit.fingerprint)
        if successfully { delivered[permit.fingerprint] = now() }
    }
}
