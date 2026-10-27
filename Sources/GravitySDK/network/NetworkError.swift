import Foundation

enum NetworkError: Error, CustomStringConvertible {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case encodingError(Error)
    case invalidURL(String)

    var description: String {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error)"
        case .encodingError(let error):
            return "Failed to encode request: \(error)"
        case .invalidURL(let urlString):
            return "Invalid URL: \(urlString)"
        }
    }
}
