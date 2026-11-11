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

    internal static func makeHttpRequestMessage(request: URLRequest) -> String {
        let url = request.url
        let method = request.httpMethod
        let bodyData = request.httpBody

        var logMessage = "REQUEST: \(url?.absoluteString ?? "nil")\n"
        logMessage += "METHOD: \(method ?? "nil")\n"

        logMessage += "COMMON HEADERS\n"
        if let headers = request.allHTTPHeaderFields {
            let sortedKeys = headers.keys.sorted { $0.lowercased() < $1.lowercased() }
            for key in sortedKeys {
                if let value = headers[key] {
                    logMessage += "-> \(key): \(value)\n"
                }
            }
        }

        logMessage += "CONTENT HEADERS\n"
        if let headers = request.allHTTPHeaderFields {
            if let contentType = headers["Content-Type"] {
                logMessage += "-> Content-Type: \(contentType)\n"
            }
            if let contentLength = bodyData?.count {
                logMessage += "-> Content-Length: \(contentLength)\n"
            }
        }

        if let bodyData = bodyData {
            if let jsonString = String(data: bodyData, encoding: .utf8) {
                let contentType = request.allHTTPHeaderFields?["Content-Type"] ?? "nil"
                logMessage += "BODY Content-Type: \(contentType)\n"
                logMessage += "BODY START\n"
                logMessage += "\(jsonString)\n"
                logMessage += "BODY END"
            } else {
                logMessage += "BODY Content-Type: application/json\n"
                logMessage += "BODY START\n"
                logMessage += "[non-UTF8 data]\n"
                logMessage += "BODY END"
            }
        } else {
            logMessage += "BODY: [empty]"
        }

        return logMessage
    }

    internal static func makeHttpResponseMessage(response: HTTPURLResponse, data: Data, method: String) -> String {
        var logMessage = "RESPONSE: \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))\n"
        logMessage += "METHOD: \(method)\n"
        logMessage += "FROM: \(response.url?.absoluteString  ?? "nil")\n"

        logMessage += "COMMON HEADERS\n"
        for (key, value) in response.allHeaderFields {
            logMessage += "-> \(key): \(value)\n"
        }

        if let jsonString = String(data: data, encoding: .utf8) {
            let contentType = response.allHeaderFields["Content-Type"] as? String ?? "nil"
            logMessage += "BODY Content-Type: \(contentType)\n"
            logMessage += "BODY START\n"
            logMessage += "\(jsonString)\n"
            logMessage += "BODY END"
        } else {
            logMessage += "BODY: [empty or non-UTF8]"
        }

        return logMessage
    }
}
