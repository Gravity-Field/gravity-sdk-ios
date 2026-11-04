import Foundation
import Testing
@testable import GravitySDK

private final class ControlledUserDefaults: UserDefaults {
    var refusesWrite = false
    var refusesRemoval = false
    var refusesSync = false
    var synchronizationCount = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        if !refusesWrite { super.set(value, forKey: defaultName) }
    }
    override func removeObject(forKey defaultName: String) {
        if !refusesRemoval { super.removeObject(forKey: defaultName) }
    }
    override func synchronize() -> Bool {
        synchronizationCount += 1
        return !refusesSync && super.synchronize()
    }
}

struct PrefsUserIdStorageTests {
    @Test(arguments: [false, true])
    func nonStringUidStartsAnonymousAndServerResponseRepairsStorage(boolean: Bool) async throws {
        let name = "GravitySDK.identity-test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(boolean ? true : 42, forKey: "gravity_user_id")
        let storage = Prefs(userDefaults: defaults)
        #expect(storage.getUserId() == nil)
        let state = SessionManager(storage: storage)
        #expect(await state.getUserId() == nil)
        let request = try await state.beginRequest(customUser: nil, generation: state.generation)
        defer { state.finish(request) }
        #expect(request.user.uid == nil)
        #expect(request.user.ses == nil)
        try state.accept(User(uid: "server-uid", ses: "server-session"), for: request)
        #expect(defaults.object(forKey: "gravity_user_id") as? String == "server-uid")
        #expect(state.cachedUser(customUser: nil).uid == "server-uid")
        #expect(state.cachedUser(customUser: nil).ses == "server-session")
    }

    @Test(arguments: [false, true])
    func resetRemovesNonStringUidAndRestoreWritesString(boolean: Bool) async throws {
        let name = "GravitySDK.identity-test.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(boolean ? true : 42, forKey: "gravity_user_id")
        let state = SessionManager(storage: Prefs(userDefaults: defaults))
        try state.resetUser()
        #expect(defaults.object(forKey: "gravity_user_id") == nil)
        #expect(await state.getUserId() == nil)
        defaults.set(boolean ? true : 42, forKey: "gravity_user_id")
        try state.restoreUserId("restored-uid")
        #expect(defaults.object(forKey: "gravity_user_id") as? String == "restored-uid")
        #expect(await state.getUserId() == "restored-uid")
    }

    @Test(arguments: [false, true])
    func refusedWriteCannotMatchCoercedNumericUid(boolean: Bool) throws {
        let name = "GravitySDK.identity-test.\(UUID())"
        let defaults = try #require(ControlledUserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(boolean ? true : 42, forKey: "gravity_user_id")
        defaults.refusesWrite = true
        let storage = Prefs(userDefaults: defaults)
        #expect(throws: GravityUserIdError.storageWriteFailed) {
            try storage.setUserId(boolean ? "1" : "42")
        }
        #expect(storage.getUserId() == nil)
    }

    @Test func refusedRemovalOfNonStringUidIsReported() throws {
        let name = "GravitySDK.identity-test.\(UUID())"
        let defaults = try #require(ControlledUserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(42, forKey: "gravity_user_id")
        defaults.refusesRemoval = true
        let state = SessionManager(storage: Prefs(userDefaults: defaults))
        #expect(throws: GravityUserIdError.storageRemovalFailed) { try state.resetUser() }
        #expect(defaults.object(forKey: "gravity_user_id") as? Int == 42)
    }

    @Test func refusedWriteOrRemovalIsReportedByReadback() throws {
        let name = "GravitySDK.identity-test.\(UUID())"
        let defaults = try #require(ControlledUserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let storage = Prefs(userDefaults: defaults)
        defaults.refusesWrite = true
        #expect(throws: GravityUserIdError.storageWriteFailed) { try storage.setUserId("new") }
        defaults.refusesWrite = false
        try storage.setUserId("old")
        defaults.refusesRemoval = true
        #expect(throws: GravityUserIdError.storageRemovalFailed) { try storage.removeUserId() }
        #expect(storage.getUserId() == "old")
    }

    @Test func failedSynchronizationIsReportedEvenWhenReadbackMatches() throws {
        let name = "GravitySDK.identity-test.\(UUID())"
        let defaults = try #require(ControlledUserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let storage = Prefs(userDefaults: defaults)
        defaults.refusesSync = true
        #expect(throws: GravityUserIdError.storageWriteFailed) { try storage.setUserId("new") }
        #expect(storage.getUserId() == nil)
        defaults.set("old", forKey: "gravity_user_id")
        #expect(throws: GravityUserIdError.storageRemovalFailed) { try storage.removeUserId() }
        #expect(defaults.synchronizationCount == 3)
    }

    @Test @MainActor func failedRestoreRollsBackVolatileDefaultsAndDoesNotNotify() async throws {
        for original: String? in [nil, "old"] {
            let name = "GravitySDK.identity-test.\(UUID())"
            let defaults = try #require(ControlledUserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let storage = Prefs(userDefaults: defaults)
            let state = SessionManager(storage: storage)
            if let original { try state.restoreUserId(original) }
            var changes: [String?] = []
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            state.setListener { changes.append($0) }
            defaults.refusesSync = true
            #expect(throws: GravityUserIdError.storageWriteFailed) { try state.restoreUserId("new") }
            #expect(await state.getUserId() == original)
            #expect(storage.getUserId() == original)
            let request = try await state.beginRequest(customUser: nil, generation: state.generation)
            #expect(request.user.uid == original)
            #expect(request.user.ses == nil)
            state.finish(request)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            #expect(changes.isEmpty)
        }
    }

    @Test func unchangedUidAndAbsentRemovalDoNotSynchronize() throws {
        let name = "GravitySDK.identity-test.\(UUID())"
        let defaults = try #require(ControlledUserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let storage = Prefs(userDefaults: defaults)
        try storage.setUserId("same")
        try storage.setUserId("same")
        #expect(defaults.synchronizationCount == 1)
        try storage.removeUserId()
        try storage.removeUserId()
        #expect(defaults.synchronizationCount == 2)
    }

    @Test func deviceIdDoesNotForceSynchronization() throws {
        let name = "GravitySDK.identity-test.\(UUID())"
        let defaults = try #require(ControlledUserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let storage = Prefs(userDefaults: defaults)
        storage.setDeviceId("device")
        #expect(defaults.synchronizationCount == 0)
    }
}
