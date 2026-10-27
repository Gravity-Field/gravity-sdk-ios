import Foundation

/// A successful HTTP acknowledgement, rather than a completed coroutine, releases the local gate.
internal struct EngagementTransport {
    let session: URLSession

    func send(url value: String, headers: [String: String] = [:],
              logRequest: (URLRequest) -> Void = { _ in },
              logResponse: (HTTPURLResponse, Data) -> Void = { _, _ in }) async throws {
        guard let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw NetworkError.invalidURL(value)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers
        logRequest(request)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        logResponse(response, data)
        guard (200...299).contains(response.statusCode) else {
            throw NetworkError.httpError(statusCode: response.statusCode)
        }
    }

    static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case NetworkError.httpError(let status): return status == 408 || status == 429 || status >= 500
        case NetworkError.invalidURL: return false
        default: return true
        }
    }
}
