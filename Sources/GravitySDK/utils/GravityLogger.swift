import Foundation
import os

internal class GravityLogger {

    private static let TAG = "GravitySDK"

    internal static var logLevel: LogLevel = .error

    internal static func configure(_ logLevel: LogLevel) {
        self.logLevel = logLevel
    }

    internal static func d(prefix: String, _ message: String) {
        guard LogLevel.debug.rawValue >= logLevel.rawValue else { return }
        os_log(
            "[GravitySDK] [%{public}@] %{public}@",
            log: .default,
            type: .debug,
            prefix,
            message
        )
    }

    internal static func i(prefix: String, _ message: String) {
        guard LogLevel.info.rawValue >= logLevel.rawValue else { return }
        os_log(
            "[GravitySDK] [%{public}@] %{public}@",
            log: .default,
            type: .info,
            prefix,
            message
        )
    }

    internal static func e(
        _ prefix: String,
        _ message: String,
        _ error: Error? = nil,
        sendToBack: Bool = true
    ) {
        if LogLevel.error.rawValue >= logLevel.rawValue {
            if let error = error {
                os_log("[GravitySDK] [%{public}@] %{public}@ - Error: %{public}@", log: .default, type: .error, prefix, message, error.localizedDescription)
            } else {
                os_log("[GravitySDK] [%{public}@] %{public}@", log: .default, type: .error, prefix, message)
            }
        }

        if sendToBack {
            Task {
                await GravityRepository.instance.sendErrorMessage(
                    message: "[\(prefix)] \(message)",
                    stacktrace: error?.localizedDescription ?? ""
                )
            }
        }
    }
}
