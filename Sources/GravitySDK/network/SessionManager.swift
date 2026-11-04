import Foundation

/// Errors from an explicit identity change. A storage error means that the
/// session was cleared, but the device may still contain its previous UID.
public enum GravityUserIdError: Error, Equatable {
    case invalidUserId
    case storageWriteFailed
    case storageRemovalFailed
}

internal protocol UserIdStorage {
    func getUserId() -> String?
    func setUserId(_ uid: String) throws
    /// Removes any stored value, including malformed values hidden by getUserId.
    /// An already absent key is a no-op.
    func removeUserId() throws
}

/// One session initializer per anonymous identity. Network work happens
/// outside the lock; identity changes and synchronous storage mutations are atomic.
internal final class SessionManager {
    struct Request {
        /// The content/custom-user generation: stale results cannot be shown.
        let generation: UInt64
        let user: User
        fileprivate let identityGeneration: UInt64
        fileprivate let initializer: UUID?
    }

    /// The identity known when a visit/event was raised, before its Task starts.
    struct Snapshot {
        let generation: UInt64
        fileprivate let identityGeneration: UInt64
        let user: User
    }

    private let lock = NSLock()
    private let storage: UserIdStorage
    private var version: UInt64 = 0
    // Only reset/restore replace the device's anonymous identity.
    private var identityVersion: UInt64 = 0
    private var uid: String?
    private var session: String?
    private var uidOnDisk = false
    private var initializer: UUID?
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var listener: ((String?) -> Void)?
    private var notifiedUid: String?

    init(storage: UserIdStorage) {
        self.storage = storage
        uid = storage.getUserId()
        uidOnDisk = uid != nil
    }

    private func scoped<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var generation: UInt64 { scoped { version } }
    func isCurrent(_ generation: UInt64) -> Bool { scoped { version == generation } }

    func setListener(_ listener: ((String?) -> Void)?) { scoped { self.listener = listener } }

    private func note(_ value: String?) {
        guard notifiedUid != value else { return }
        notifiedUid = value
        if let listener { DispatchQueue.main.async { listener(value) } }
    }

    private func releaseWaiters() {
        let pending = waiters
        waiters.removeAll()
        pending.values.forEach { $0.resume() }
    }

    /// Custom-user changes invalidate content but keep an anonymous initializer:
    /// its UID still belongs to this device until reset/restore changes identity.
    func invalidate() { scoped { invalidateContentLocked() } }

    private func invalidateContentLocked() {
        version &+= 1
        releaseWaiters()
    }

    private func invalidateLocked() {
        identityVersion &+= 1
        initializer = nil
        invalidateContentLocked()
    }

    func snapshot(customUser: User?, generation: UInt64? = nil) -> Snapshot {
        scoped {
            Snapshot(generation: generation ?? version, identityGeneration: identityVersion,
                     user: customUser ?? User(uid: uid, ses: session))
        }
    }

    func resetUser() throws {
        try scoped {
            let previous = uid
            invalidateLocked()
            uid = nil
            session = nil
            uidOnDisk = false
            defer {
                if notifiedUid == nil { notifiedUid = previous }
                note(nil)
            }
            // A failed disk removal is reported, but cannot resurrect memory identity.
            try storage.removeUserId()
        }
    }

    func restoreUserId(_ value: String) throws {
        let restored = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !restored.isEmpty else {
            throw GravityUserIdError.invalidUserId
        }
        try scoped {
            let previous = uid
            let previousOnDisk = uidOnDisk
            invalidateLocked()
            session = nil
            do { try storage.setUserId(restored) }
            catch {
                uid = previous
                uidOnDisk = previousOnDisk
                throw error
            }
            uid = restored
            uidOnDisk = true
            note(restored)
        }
    }

    /// Reading storage is not a change notification and does not create a session.
    func cachedUser(customUser: User?) -> User {
        scoped { customUser ?? User(uid: uid, ses: session) }
    }

    /// Returns nil when the calling task is cancelled, even if a UID is cached.
    func getUserId() async -> String? {
        while true {
            if Task.isCancelled { return nil }
            let result: (Bool, String?) = scoped {
                (initializer == nil, uid)
            }
            if result.0 { return result.1 }
            await waitForInitializer()
        }
    }

    private func waitForInitializer(generation: UInt64? = nil, identityGeneration: UInt64? = nil) async {
        let id = UUID()
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                scoped {
                    if Task.isCancelled || initializer == nil || generation.map({ $0 != version }) == true
                        || identityGeneration.map({ $0 != identityVersion }) == true { continuation.resume() }
                    else { waiters[id] = continuation }
                }
            }
        }, onCancel: {
            self.scoped { self.waiters.removeValue(forKey: id)?.resume() }
        })
    }

    func beginRequest(customUser: User?, generation: UInt64, raisedIdentity: Snapshot? = nil) async throws -> Request {
        while true {
            try Task.checkCancellation()
            let result: Request? = try scoped {
                // Content requests may stop before sending. Analytics must be sent
                // even if their content generation is no longer current.
                guard raisedIdentity != nil || generation == version else { throw CancellationError() }
                if let customUser {
                    return Request(generation: generation, user: customUser,
                                   identityGeneration: raisedIdentity?.identityGeneration ?? identityVersion,
                                   initializer: nil)
                }
                if let raised = raisedIdentity, raised.identityGeneration != identityVersion,
                   raised.user.uid != nil {
                    // A known old user never takes the new user's session gate.
                    // Adopt a session only when it belongs to the same UID.
                    let known = raised.user
                    let ses = known.ses ?? (known.uid == uid ? session : nil)
                    let owner = User(uid: known.uid, custom: known.custom, ses: ses, attributes: known.attributes)
                    return Request(generation: generation, user: owner,
                                   identityGeneration: raised.identityGeneration, initializer: nil)
                }
                guard initializer == nil else { return nil }
                let owner = session == nil ? UUID() : nil
                initializer = owner
                return Request(generation: generation, user: User(uid: uid, ses: session),
                               identityGeneration: identityVersion, initializer: owner)
            }
            if let result { return result }
            await waitForInitializer(generation: raisedIdentity == nil ? generation : nil,
                identityGeneration: raisedIdentity?.user.uid == nil ? nil : raisedIdentity?.identityGeneration)
        }
    }

    func accept(_ user: User?, for request: Request) throws {
        try scoped {
            guard request.identityGeneration == identityVersion, request.user.custom == nil else { return }
            session = user?.ses ?? session
            if let value = user?.uid, !value.isEmpty {
                let changed = uid != value
                let needsWrite = changed || !uidOnDisk
                uid = value
                if needsWrite {
                    uidOnDisk = false
                    // The request already succeeded. Keep the actual server UID
                    // in memory even on storage failure, and retry on its next echo.
                    defer { note(value) }
                    try storage.setUserId(value)
                    uidOnDisk = true
                } else { note(value) }
            }
        }
    }

    func finish(_ request: Request) {
        scoped {
            guard request.identityGeneration == identityVersion, let owner = request.initializer,
                  initializer == owner else { return }
            initializer = nil
            releaseWaiters()
        }
    }
}
