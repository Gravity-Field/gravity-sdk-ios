import UIKit

final class DeviceUtils {
    static let shared = DeviceUtils()
    private static let deviceIdLock = NSLock()

    internal init(prefs: Prefs = .shared) {
        self.prefs = prefs
        userAgent = getUserAgent()
        contextAttributes = getContextAttributes()
    }

    private var userAgent: String = ""
    private let prefs: Prefs
    private(set) var contextAttributes: [String: String] = [:]

    func getPlatformVersion() -> String {
        return "iOS \(UIDevice.current.systemVersion)"
    }

    func getDevice() -> Device {
        return Device(
            userAgent: userAgent,
            id: getDeviceId(),
            permission: GravitySDK.instance.notificationPermissionStatus,
            tracking: "notSupported"
        )
    }

    private func getUserAgent() -> String {
        let appName =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ""
        let version =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? ""
        let platform = "iOS"
        let platformVersion = UIDevice.current.systemVersion
        let model = UIDevice.current.model
        let architecture = "arm64"

        return "\(appName)/\(version) (\(platform) \(platformVersion); \(model); \(architecture))"
    }

    private func getContextAttributes() -> [String: String] {
        let version =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? ""
        let buildNumber =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? ""
        
        let contextAttributes = [
            "app_version": "\(version)+\(buildNumber)",
            "sdk_version": GravitySDKInfo.version,
            "app_platform": "iOS"
        ]
        return contextAttributes
    }

    func getDeviceId() -> String {
        // Keep the full read/create/write atomic, without holding this lock
        // while accessing GravitySDK, session state or presentation state.
        Self.deviceIdLock.lock()
        defer { Self.deviceIdLock.unlock() }
        if let deviceId = prefs.getDeviceId(), !deviceId.isEmpty {
            return deviceId
        } else {
            let deviceId = UUID().uuidString
            prefs.setDeviceId(deviceId)
            return deviceId
        }
    }
}
