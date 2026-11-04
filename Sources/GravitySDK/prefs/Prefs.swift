import Foundation

internal class Prefs: UserIdStorage {

    static let shared = Prefs()

    internal init(userDefaults: UserDefaults = .standard) { self.userDefaults = userDefaults }

    private let keyUserId = "gravity_user_id"
    private let keyDeviceId = "gravity_device_id"

    private let userDefaults: UserDefaults

    func setUserId(_ uid: String) throws {
        let previous = getUserId()
        if previous == uid { return }
        userDefaults.set(uid, forKey: keyUserId)
        // Identity APIs promise an observable storage result. Synchronize only
        // UID mutations, then verify readback; this is still a best-effort signal.
        guard userDefaults.synchronize(), getUserId() == uid else {
            // set updates the volatile domain before synchronize returns. Restore
            // that domain too, so a failed restore cannot apply a new UID locally.
            if let previous { userDefaults.set(previous, forKey: keyUserId) }
            else { userDefaults.removeObject(forKey: keyUserId) }
            _ = userDefaults.synchronize()
            throw GravityUserIdError.storageWriteFailed
        }
    }

    func removeUserId() throws {
        // Remove corrupt values too, even though getUserId treats them as absent.
        guard userDefaults.object(forKey: keyUserId) != nil else { return }
        userDefaults.removeObject(forKey: keyUserId)
        guard userDefaults.synchronize(), userDefaults.object(forKey: keyUserId) == nil else {
            throw GravityUserIdError.storageRemovalFailed
        }
    }

    func getUserId() -> String? {
        // string(forKey:) also coerces numbers and booleans into strings.
        return userDefaults.object(forKey: keyUserId) as? String
    }

    func setDeviceId(_ uid: String) {
        userDefaults.set(uid, forKey: keyDeviceId)
    }

    func getDeviceId() -> String? {
        // string(forKey:) also coerces numbers and booleans into strings.
        return userDefaults.object(forKey: keyDeviceId) as? String
    }
}
