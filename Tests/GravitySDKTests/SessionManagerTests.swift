import Foundation
import Testing
@testable import GravitySDK

private final class MemoryUserIdStorage: UserIdStorage {
    var uid: String?
    var refusesWrites = false
    var refusesRemoval = false
    var writes = 0
    var removals = 0
    var beforeWrite: (() -> Void)?
    init(_ uid: String? = nil) { self.uid = uid }
    func getUserId() -> String? { uid }
    func setUserId(_ uid: String) throws {
        beforeWrite?()
        writes += 1
        if refusesWrites { throw GravityUserIdError.storageWriteFailed }
        self.uid = uid
    }
    func removeUserId() throws {
        guard uid != nil else { return }
        removals += 1
        if refusesRemoval { throw GravityUserIdError.storageRemovalFailed }
        uid = nil
    }
}

struct SessionManagerTests {
    @Test func coldStartRestartAndCustomIdAreIndependent() async throws {
        let disk = MemoryUserIdStorage()
        let state = SessionManager(storage: disk)
        #expect(await state.getUserId() == nil)
        let request = try await state.beginRequest(customUser: nil, generation: state.generation)
        #expect(request.user.uid == nil)
        try state.accept(User(uid: "server", ses: "session"), for: request)
        state.finish(request)
        #expect(await state.getUserId() == "server")
        let custom = try await state.beginRequest(customUser: User(custom: "customer", ses: "customer-session"), generation: state.generation)
        try state.accept(User(uid: "wrong", ses: "wrong"), for: custom)
        #expect(await state.getUserId() == "server")
        let restarted = SessionManager(storage: disk)
        #expect(await restarted.getUserId() == "server")
        let restored = try await restarted.beginRequest(customUser: nil, generation: restarted.generation)
        #expect(restored.user.uid == "server")
        #expect(restored.user.ses == nil)
        restarted.finish(restored)
    }

    @Test @MainActor func notificationsAreOrderedAndDuplicateResponsesAreSilent() async throws {
        let state = SessionManager(storage: MemoryUserIdStorage())
        var changes: [String?] = []
        state.setListener { changes.append($0) }
        for _ in 0..<3 {
            let request = try await state.beginRequest(customUser: nil, generation: state.generation)
            try state.accept(User(uid: "one", ses: "session"), for: request)
            state.finish(request)
        }
        #expect((state.cachedUser(customUser: nil).uid) == "one")
        let changed = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "server-changed", ses: "session"), for: changed)
        state.finish(changed)
        try state.restoreUserId("two")
        try state.resetUser()
        await drainMainQueue()
        #expect(changes == ["one", "server-changed", "two", nil])
        #expect(await state.getUserId() == nil)
        state.setListener(nil)
        try state.restoreUserId("three")
        await drainMainQueue()
        #expect(changes.count == 4)
    }

    @Test func resetAndRestoreFenceOldResponsesAndReleaseWaiters() async throws {
        let disk = MemoryUserIdStorage("old")
        let state = SessionManager(storage: disk)
        let old = try await state.beginRequest(customUser: nil, generation: state.generation)
        let getter = Task { await state.getUserId() }
        try state.restoreUserId("restored")
        #expect(await getter.value == "restored")
        try state.accept(User(uid: "late", ses: "late-session"), for: old)
        state.finish(old)
        #expect(disk.uid == "restored")
        let next = try await state.beginRequest(customUser: nil, generation: state.generation)
        #expect(next.user.uid == "restored")
        #expect(next.user.ses == nil)
        try state.resetUser()
        try state.accept(User(uid: "late-again", ses: "session"), for: next)
        #expect(disk.uid == nil)
        #expect(await state.getUserId() == nil)
        #expect(!state.isCurrent(next.generation))
    }

    @Test func storageRefusalsThrowAndServerUidStaysConsistentInMemory() async throws {
        let disk = MemoryUserIdStorage("old")
        let state = SessionManager(storage: disk)
        disk.refusesWrites = true
        #expect(throws: GravityUserIdError.storageWriteFailed) { try state.restoreUserId("new") }
        #expect(await state.getUserId() == "old")
        let request = try await state.beginRequest(customUser: nil, generation: state.generation)
        #expect(throws: GravityUserIdError.storageWriteFailed) {
            try state.accept(User(uid: "server", ses: "session"), for: request)
        }
        state.finish(request)
        #expect(await state.getUserId() == "server")
        disk.refusesWrites = false
        let retry = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "server", ses: "session"), for: retry)
        state.finish(retry)
        #expect(disk.uid == "server")
        disk.refusesRemoval = true
        #expect(throws: GravityUserIdError.storageRemovalFailed) { try state.resetUser() }
        #expect(disk.uid == "server")
        #expect(await state.getUserId() == nil)
        #expect(throws: GravityUserIdError.invalidUserId) { try state.restoreUserId("") }
    }

    @Test @MainActor func failedServerUidPersistenceStillNotifiesOnceAndRetries() async throws {
        let disk = MemoryUserIdStorage()
        disk.refusesWrites = true
        let state = SessionManager(storage: disk)
        var changes: [String?] = []
        state.setListener { changes.append($0) }
        let first = try await state.beginRequest(customUser: nil, generation: state.generation)
        #expect(throws: GravityUserIdError.storageWriteFailed) {
            try state.accept(User(uid: "server", ses: "session"), for: first)
        }
        state.finish(first)
        #expect(await state.getUserId() == "server")
        await drainMainQueue()
        #expect(changes == ["server"])
        #expect(disk.uid == nil)
        disk.refusesWrites = false
        for _ in 0..<3 {
            let retry = try await state.beginRequest(customUser: nil, generation: state.generation)
            try state.accept(User(uid: "server", ses: "session"), for: retry)
            state.finish(retry)
        }
        await drainMainQueue()
        #expect(changes == ["server"])
        #expect(disk.uid == "server")
        #expect(disk.writes == 2)
    }

    @Test @MainActor func failedResetClearsMemoryAndNotifiesNil() async throws {
        let disk = MemoryUserIdStorage("stored")
        let state = SessionManager(storage: disk)
        var changes: [String?] = []
        state.setListener { changes.append($0) }
        disk.refusesRemoval = true
        #expect(throws: GravityUserIdError.storageRemovalFailed) { try state.resetUser() }
        #expect(await state.getUserId() == nil)
        #expect(state.cachedUser(customUser: nil).ses == nil)
        #expect(disk.uid == "stored")
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(changes.count == 1 && changes[0] == nil)
    }

    @Test(arguments: [false, true], [false, true])
    func onlyKnownAnalyticsSnapshotsFreezeTheOldIdentity(knownUid: Bool, restore: Bool) async throws {
        let state = SessionManager(storage: MemoryUserIdStorage(knownUid ? "original" : nil))
        let raised = state.snapshot(customUser: nil)
        if restore { try state.restoreUserId("new") } else { try state.resetUser() }
        let request = try await state.beginRequest(customUser: nil, generation: raised.generation, raisedIdentity: raised)
        #expect(request.user.uid == (knownUid ? "original" : (restore ? "new" : nil)))
        #expect(request.user.ses == nil)
        state.finish(request)
    }

    @Test func storedUidIsReadBeforeRaisedAnalyticsSnapshot() async throws {
        let disk = MemoryUserIdStorage("original")
        // Storage reads are synchronous in init: no caller can obtain a snapshot
        // until construction has read the stored identity.
        let state = SessionManager(storage: disk)
        let raised = state.snapshot(customUser: nil)
        try state.resetUser()
        let request = try await state.beginRequest(customUser: nil, generation: raised.generation, raisedIdentity: raised)
        #expect(request.user.uid == "original")
        #expect(await state.getUserId() == nil)
        state.finish(request)
    }

    @Test func emptySessionReplacesCachedSessionWhileEmptyUidIsIgnored() async throws {
        let state = SessionManager(storage: MemoryUserIdStorage("stored"))
        let first = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "stored", ses: "session"), for: first)
        state.finish(first)
        let next = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "", ses: ""), for: next)
        state.finish(next)
        #expect(state.cachedUser(customUser: nil).uid == "stored")
        #expect(state.cachedUser(customUser: nil).ses == "")
    }

    @Test func requestsCapturedBeforeIdentityChangeCannotStart() async throws {
        let state = SessionManager(storage: MemoryUserIdStorage())
        let generation = state.generation
        try state.restoreUserId("new")
        do {
            _ = try await state.beginRequest(customUser: User(custom: "old"), generation: generation)
            Issue.record("Stale request was allowed to start")
        } catch { #expect(error is CancellationError) }
    }

    @Test func getterWaitsForInitializationRatherThanReturningTheOldStoredUid() async throws {
        let state = SessionManager(storage: MemoryUserIdStorage("stored"))
        let request = try await state.beginRequest(customUser: nil, generation: state.generation)
        let probe = UserIdReadProbe()
        let getter = Task {
            let uid = await state.getUserId()
            await probe.complete()
            return uid
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(await probe.completed == false)
        try state.accept(User(uid: "server", ses: "session"), for: request)
        state.finish(request)
        #expect(await getter.value == "server")
    }

    @Test func serverUidChangeWithoutSessionKeepsCachedSession() async throws {
        let state = SessionManager(storage: MemoryUserIdStorage())
        let first = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "first", ses: "first-session"), for: first)
        state.finish(first)
        let next = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "second"), for: next)
        state.finish(next)
        #expect(state.cachedUser(customUser: nil).uid == "second")
        #expect(state.cachedUser(customUser: nil).ses == "first-session")
        let following = try await state.beginRequest(customUser: nil, generation: state.generation)
        #expect(following.user.uid == "second")
        #expect(following.user.ses == "first-session")
        state.finish(following)
    }

    @Test func sparseResponseKeepsCachedIdentityPair() async throws {
        let state = SessionManager(storage: MemoryUserIdStorage())
        let first = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "first", ses: "first-session"), for: first)
        state.finish(first)
        let next = try await state.beginRequest(customUser: nil, generation: state.generation)
        let sparse = try JSONDecoder().decode(User.self, from: Data("{}".utf8))
        try state.accept(sparse, for: next)
        state.finish(next)
        let cached = state.cachedUser(customUser: nil)
        #expect(cached.uid == "first")
        #expect(cached.ses == "first-session")
    }

    @Test func emptyResponseUidIsIgnoredWhileSessionCanRefresh() async throws {
        let disk = MemoryUserIdStorage("stored")
        let state = SessionManager(storage: disk)
        for session in ["first-session", "refreshed-session"] {
            let request = try await state.beginRequest(customUser: nil, generation: state.generation)
            try state.accept(User(uid: "", ses: session), for: request)
            state.finish(request)
            let cached = state.cachedUser(customUser: nil)
            #expect(cached.uid == "stored")
            #expect(cached.ses == session)
        }
        #expect(disk.uid == "stored")
        #expect(disk.writes == 0)
    }

    @Test func acceptedIdentityPairIsPublishedTogetherToReaders() async throws {
        let disk = MemoryUserIdStorage()
        let state = SessionManager(storage: disk)
        let first = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "first", ses: "first-session"), for: first)
        state.finish(first)
        let next = try await state.beginRequest(customUser: nil, generation: state.generation)
        let writing = DispatchSemaphore(value: 0)
        let releaseWrite = DispatchSemaphore(value: 0)
        disk.beforeWrite = { writing.signal(); releaseWrite.wait() }
        let writer = Task {
            try await onDispatchQueue {
                try state.accept(User(uid: "second", ses: "second-session"), for: next)
            }
        }
        try await onDispatchQueue { writing.wait() }
        let reading = DispatchSemaphore(value: 0)
        let completed = DispatchSemaphore(value: 0)
        let reader = Task {
            try await onDispatchQueue {
                reading.signal()
                let cached = state.cachedUser(customUser: nil)
                completed.signal()
                return cached
            }
        }
        try await onDispatchQueue { reading.wait() }
        let earlyRead = try await onDispatchQueue {
            completed.wait(timeout: .now() + .milliseconds(50))
        }
        releaseWrite.signal()
        try await writer.value
        state.finish(next)
        let cached = try await reader.value
        #expect(earlyRead == .timedOut)
        #expect(cached.uid == "second")
        #expect(cached.ses == "second-session")
        let snapshot = state.snapshot(customUser: nil)
        #expect(snapshot.user.uid == "second")
        #expect(snapshot.user.ses == "second-session")
    }

    @Test(arguments: ["", " ", "\t\r\n "]) func blankRestoreLeavesIdentityUnchanged(_ value: String) async throws {
        let disk = MemoryUserIdStorage("stored")
        let state = SessionManager(storage: disk)
        let request = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "stored", ses: "session"), for: request)
        state.finish(request)
        let generation = state.generation
        #expect(throws: GravityUserIdError.invalidUserId) { try state.restoreUserId(value) }
        #expect(state.generation == generation)
        #expect(state.cachedUser(customUser: nil).uid == "stored")
        #expect(state.cachedUser(customUser: nil).ses == "session")
        #expect(disk.uid == "stored")
        #expect(disk.writes == 0)
    }

    @Test func knownOldAnalyticsDoNotTakeTheNewSessionsBarrier() async throws {
        let state = SessionManager(storage: MemoryUserIdStorage("old"))
        let known = state.snapshot(customUser: nil)
        try state.restoreUserId("new")
        let owner = try await state.beginRequest(customUser: nil, generation: state.generation)
        let stale = try await state.beginRequest(customUser: nil, generation: known.generation, raisedIdentity: known)
        #expect(stale.user.uid == "old")
        #expect(stale.user.ses == nil)
        try state.accept(User(uid: "wrong", ses: "wrong"), for: stale)
        state.finish(stale)
        #expect(state.cachedUser(customUser: nil).uid == "new")
        try state.accept(User(uid: "new", ses: "new-session"), for: owner)
        state.finish(owner)
        #expect(await state.getUserId() == "new")
    }

    @Test func unknownAnalyticsAdoptTheNewIdentityAndShareItsSession() async throws {
        let state = SessionManager(storage: MemoryUserIdStorage())
        let unknown = state.snapshot(customUser: nil)
        try state.restoreUserId("new")
        let owner = try await state.beginRequest(customUser: nil, generation: state.generation)
        let pending = Task {
            try await state.beginRequest(customUser: nil, generation: unknown.generation, raisedIdentity: unknown)
        }
        try state.accept(User(uid: "new", ses: "new-session"), for: owner)
        state.finish(owner)
        let adopted = try await pending.value
        #expect(adopted.user.uid == "new")
        #expect(adopted.user.ses == "new-session")
        #expect(!state.isCurrent(adopted.generation))
        state.finish(adopted)
    }

    @Test func storedUidEchoAndEmptyResetDoNotMutateStorage() async throws {
        let disk = MemoryUserIdStorage("stored")
        let state = SessionManager(storage: disk)
        let request = try await state.beginRequest(customUser: nil, generation: state.generation)
        try state.accept(User(uid: "stored", ses: "session"), for: request)
        state.finish(request)
        #expect(disk.writes == 0)
        try state.resetUser()
        try state.resetUser()
        #expect(disk.removals == 1)
    }

    @Test func directRestoreStoresAndUsesTheTrimmedUid() async throws {
        let disk = MemoryUserIdStorage()
        let state = SessionManager(storage: disk)
        try state.restoreUserId(" \tstored\n")
        #expect(disk.uid == "stored")
        #expect(await state.getUserId() == "stored")
        let request = try await state.beginRequest(customUser: nil, generation: state.generation)
        #expect(request.user.uid == "stored")
        #expect(request.user.ses == nil)
        state.finish(request)
    }

    @Test func failedInitializationReleasesNextRequest() async throws {
        let state = SessionManager(storage: MemoryUserIdStorage())
        let first = try await state.beginRequest(customUser: nil, generation: state.generation)
        let next = Task { try await state.beginRequest(customUser: nil, generation: state.generation) }
        state.finish(first)
        let second = try await next.value
        #expect(second.user.ses == nil)
        try state.accept(User(uid: "recovered", ses: "session"), for: second)
        state.finish(second)
        #expect(await state.getUserId() == "recovered")
    }

    @MainActor private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func onDispatchQueue<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(with: Result(catching: operation))
            }
        }
    }
}

private actor UserIdReadProbe {
    private(set) var completed = false
    func complete() { completed = true }
}
