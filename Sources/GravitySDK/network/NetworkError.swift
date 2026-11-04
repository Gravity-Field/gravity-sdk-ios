import Foundation

enum NetworkError: Error, CustomStringConvertible {
    case transportError(code: Int, method: String, url: String)
    case invalidResponse
    case httpError(statusCode: Int, method: String = "HTTP", url: String = "")
    case decodingError(Error)
    case encodingError(Error)
    case invalidURL(String)

    static func transportFailure(_ error: URLError, method: String, url: String) -> Error {
        // Preserve cancellation classification at every existing caller.
        guard error.code != .cancelled else { return error }
        return NetworkError.transportError(code: error.code.rawValue, method: method, url: url)
    }

    static func diagnosticText(_ error: Error) -> String {
        if let error = error as? URLError {
            let endpoint = error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
                ?? (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString ?? ""
            return NetworkError.transportError(code: error.code.rawValue, method: "HTTP", url: endpoint).description
        }
        if let error = error as? NetworkError { return error.description }
        return error.localizedDescription
    }

    var description: String {
        switch self {
        case .transportError(let code, let method, let url):
            let context = [method, ReportSanitizer.sanitizeUrls(url)].filter { !$0.isEmpty }.joined(separator: " ")
            return "\(context) -> URLError(\(code))"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let method, let url):
            return "\(method) \(ReportSanitizer.sanitizeUrls(url)) -> \(statusCode)"
        case .decodingError:
            // Decoder diagnostics may quote arbitrary response values.
            return "Failed to decode response"
        case .encodingError:
            return "Failed to encode request"
        case .invalidURL(let urlString):
            return "Invalid URL: \(urlString)"
        }
    }
}
