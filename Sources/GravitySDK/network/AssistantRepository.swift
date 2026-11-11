import Foundation

private let ASSISTANT_BASE_URL = "https://shopping-assistant-api.gravityfield.ai"
private let GENERATE = "/shopping/generate"

internal struct ShoppingMessage: Encodable {
    let role: String
    let content: String
}

internal struct ShoppingRuntimeContext: Encodable {
    let tenantId: String
    /// Canonical Gravity uid; also used as the request's `resourceId`.
    let uid: String
    let ctx: PageContext?

    enum CodingKeys: String, CodingKey {
        case tenantId = "tenant_id"
        case uid, ctx
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tenantId, forKey: .tenantId)
        try container.encode(uid, forKey: .uid)
        try container.encodeIfPresent(ctx, forKey: .ctx)
    }
}

internal struct ShoppingGenerateRequest: Encodable {
    let threadId: String
    let resourceId: String
    let messages: [ShoppingMessage]
    let runtimeContext: ShoppingRuntimeContext
    let trafficType: String?

    init(
        threadId: String,
        resourceId: String,
        messages: [ShoppingMessage],
        runtimeContext: ShoppingRuntimeContext,
        trafficType: String? = nil
    ) {
        self.threadId = threadId
        self.resourceId = resourceId
        self.messages = messages
        self.runtimeContext = runtimeContext
        self.trafficType = trafficType
    }

    enum CodingKeys: String, CodingKey {
        case threadId, resourceId, messages, runtimeContext, trafficType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadId, forKey: .threadId)
        try container.encode(resourceId, forKey: .resourceId)
        try container.encode(messages, forKey: .messages)
        try container.encode(runtimeContext, forKey: .runtimeContext)
        try container.encodeIfPresent(trafficType, forKey: .trafficType)
    }
}

/// Result of a generate request. The error code is used for diagnostics only.
internal enum ShoppingGenerateOutcome {
    case success(ShoppingGenerateResponse)
    case failure(AssistantErrorCode)
}

/// Shopping Assistant API client. Requests are sent without the API key.
internal final class AssistantRepository {

    static let instance = AssistantRepository()

    private static let TAG = "AssistantRepository"

    private init() {}

    private let jsonEncoder = JSONEncoder()

    /// Dedicated session with a two-minute request and resource timeout.
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 120
        return URLSession(configuration: configuration)
    }()

    func generate(_ request: ShoppingGenerateRequest) async -> ShoppingGenerateOutcome {
        do {
            guard let url = URL(string: ASSISTANT_BASE_URL + GENERATE) else {
                return failure(.invalidResponse, "bad url")
            }

            var urlRequest = URLRequest(url: url)
            // URLRequest has its own 60 s default timeout; keep it in sync with the session.
            urlRequest.timeoutInterval = 120
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try jsonEncoder.encode(request)

            logHttpRequest(request: urlRequest)

            let (data, response) = try await urlSession.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return failure(.invalidResponse, "no http response")
            }

            logHttpResponse(response: httpResponse, data: data, method: "POST")

            let status = httpResponse.statusCode
            guard (200...299).contains(status) else {
                return failure(statusCode(status), "status \(status)")
            }

            return parse(data)
        } catch let error as URLError {
            let code: AssistantErrorCode = error.code == .timedOut ? .timeout : .network
            return failure(code, error.localizedDescription)
        } catch {
            return failure(.invalidResponse, error.localizedDescription)
        }
    }

    /// Parses a 2xx body. Fails if there is no `response` object; empty `contents` is valid.
    private func parse(_ data: Data) -> ShoppingGenerateOutcome {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return failure(.invalidResponse, "body is not json")
        }
        guard json["response"]?.objectValue != nil else {
            return failure(.invalidResponse, "no response object")
        }
        return .success(ShoppingGenerateResponse.fromJson(json))
    }

    private func statusCode(_ status: Int) -> AssistantErrorCode {
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        case 500...: return .server
        default: return .invalidResponse
        }
    }

    private func logHttpRequest(request: URLRequest) {
        let logMessage = GravityLogger.makeHttpRequestMessage(request: request)
        GravityLogger.d(prefix: "HTTP", logMessage)
    }

    private func logHttpResponse(response: HTTPURLResponse, data: Data, method: String) {
        let logMessage = GravityLogger.makeHttpResponseMessage(response: response, data: data, method: method)
        GravityLogger.d(prefix: "HTTP", logMessage)
    }

    private func failure(_ code: AssistantErrorCode, _ reason: String?) -> ShoppingGenerateOutcome {
        GravityLogger.e(Self.TAG, "generate failed with \(code): \(reason ?? "")")
        return .failure(code)
    }
}
