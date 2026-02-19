import Foundation

internal class Prefs {

    static let shared = Prefs()

    private init() {}

    private let keyUserId = "gravity_user_id"
    private let keyDeviceId = "gravity_device_id"

    private let userDefaults = UserDefaults.standard

    func setUserId(_ uid: String) {
        userDefaults.set(uid, forKey: keyUserId)
    }

    func getUserId() -> String? {
        return userDefaults.string(forKey: keyUserId)
    }

    func setDeviceId(_ uid: String) {
        userDefaults.set(uid, forKey: keyDeviceId)
    }

    func getDeviceId() -> String? {
        return userDefaults.string(forKey: keyDeviceId)
    }
}
