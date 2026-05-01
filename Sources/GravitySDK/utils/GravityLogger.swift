import Foundation
import os

internal class GravityLogger {

    internal static var logLevel: LogLevel = .error

    internal static func configure(_ logLevel: LogLevel) {
        self.logLevel = logLevel
    }

    internal static func d(prefix: String, _ message: String) {
        guard LogLevel.debug.rawValue >= logLevel.rawValue else { return }
        let logMessage = "[\(prefix)] \(message)"
        os_log(
            "[GravitySDK] %{public}@",
            log: .default,
            type: .default,
            logMessage
        )
        GravitySDK.instance.logListener?(.debug, logMessage)
    }

    internal static func i(prefix: String, _ message: String) {
        guard LogLevel.info.rawValue >= logLevel.rawValue else { return }
        let logMessage = "[\(prefix)] \(message)"
        os_log(
            "[GravitySDK] %{public}@",
            log: .default,
            type: .default,
            logMessage
        )
        GravitySDK.instance.logListener?(.info, logMessage)
    }

    internal static func e(
        _ prefix: String,
        _ message: String,
        _ error: Error? = nil,
        sendToBack: Bool = true
    ) {
        if LogLevel.error.rawValue >= logLevel.rawValue {
            let logMessage: String
            if let error = error {
                logMessage = "[\(prefix)] \(message) - Error: \(error.localizedDescription)"
            } else {
                logMessage = "[\(prefix)] \(message)"
            }
            os_log(
                "[GravitySDK] %{public}@",
                log: .default,
                type: .error,
                logMessage
            )
            GravitySDK.instance.logListener?(.error, logMessage)
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
