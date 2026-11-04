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
        sendToBack: Bool = true,
        repository: GravityRepository? = nil
    ) {
        if LogLevel.error.rawValue >= logLevel.rawValue {
            let logMessage: String
            if let error = error {
                logMessage = "[\(prefix)] \(message) - Error: \(NetworkError.diagnosticText(error))"
            } else {
                logMessage = "[\(prefix)] \(message)"
            }
            let safeLogMessage = ReportSanitizer.sanitizeText(logMessage, limit: 1000)
            os_log(
                "[GravitySDK] %{public}@",
                log: .default,
                type: .error,
                safeLogMessage
            )
            GravitySDK.instance.logListener?(.error, safeLogMessage)
        }

        if sendToBack {
            Task {
                await (repository ?? GravityRepository.instance).sendErrorMessage(
                    message: "[\(prefix)] \(message)",
                    stacktrace: error.map { NetworkError.diagnosticText($0) } ?? ""
                )
            }
        }
    }
}
