import UIKit

final class DeviceUtils {
    static let shared = DeviceUtils()

    private init() {
        userAgent = getUserAgent()
        contextAttributes = getContextAttributes()
    }

    private var userAgent: String = ""
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

    private func getDeviceId() -> String {
        if let deviceId = Prefs.shared.getDeviceId() {
            return deviceId
        } else {
            let deviceId = UUID().uuidString
            Prefs.shared.setDeviceId(deviceId)
            return deviceId
        }
    }
}
