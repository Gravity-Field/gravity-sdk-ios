import Foundation

internal class GravityRepository {

    private let BASE_URL = "https://evs-01.gravityfield.ai/v2"
    private let CHOOSE = "/choose"
    private let VISIT = "/visit"
    private let EVENT = "/event"

    static let instance = GravityRepository()

    private static let TAG = "Repository"

    private init() {
        urlSession = Self.makeURLSession()
        errorReportLimiter = ErrorReportLimiter()
    }

    internal init(urlSession: URLSession, errorReportLimiter: ErrorReportLimiter = ErrorReportLimiter()) {
        self.urlSession = urlSession
        self.errorReportLimiter = errorReportLimiter
    }

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private let deviceUtils = DeviceUtils.shared

    internal let sessionManager = SessionManager(storage: Prefs.shared)

    private var baseUrl: String {
        return GravitySDK.instance.proxyUrl ?? BASE_URL
    }

    private let urlSession: URLSession
    private let errorReportLimiter: ErrorReportLimiter

    private static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5.0
        configuration.timeoutIntervalForResource = 5.0
        return URLSession(configuration: configuration)
    }

    func visit(
        pageContext: PageContext,
        options: Options,
        customerUser: User?,
        identityGeneration: UInt64? = nil,
        raisedIdentity: SessionManager.Snapshot? = nil
    ) async -> CampaignIdsResponse? {
        do {
            let raised = raisedIdentity ?? sessionManager.snapshot(customUser: customerUser, generation: identityGeneration)
            let identityRequest = try await sessionManager.beginRequest(
                customUser: customerUser, generation: raised.generation, raisedIdentity: raised)
            defer { sessionManager.finish(identityRequest) }
            let requestBody = VisitRequest(
                sec: GravitySDK.instance.section,
                device: deviceUtils.getDevice(),
                type: "screenview",
                user: identityRequest.user,
                ctx: mixPageContextAttributes(pageContext),
                options: options
            )

            let response: CampaignIdsResponse = try await performRequest(
                endpoint: VISIT,
                method: "POST",
                body: requestBody
            )

            guard saveUserIfNeeded(request: identityRequest, contentResponseUser: response.user) else { return nil }
            try Task.checkCancellation()
            return response
        } catch is CancellationError {
            return nil
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
            GravityLogger.e(Self.TAG, "visit failed: \(error)")
            return nil
        }
    }

    func event(
        events: [TriggerEvent],
        raisedAt: Date,
        pageContext: PageContext,
        options: Options,
        customerUser: User?,
        identityGeneration: UInt64? = nil,
        raisedIdentity: SessionManager.Snapshot? = nil
    ) async -> CampaignIdsResponse? {
        do {
            let raised = raisedIdentity ?? sessionManager.snapshot(customUser: customerUser, generation: identityGeneration)
            let identityRequest = try await sessionManager.beginRequest(
                customUser: customerUser, generation: raised.generation, raisedIdentity: raised)
            defer { sessionManager.finish(identityRequest) }
            let requestBody = EventRequest(
                sec: GravitySDK.instance.section,
                device: deviceUtils.getDevice(),
                data: events.map { EventPayload(event: $0, raisedAt: raisedAt) },
                user: identityRequest.user,
                ctx: mixPageContextAttributes(pageContext),
                options: options
            )

            let response: CampaignIdsResponse = try await performRequest(
                endpoint: EVENT,
                method: "POST",
                body: requestBody
            )

            guard saveUserIfNeeded(request: identityRequest, contentResponseUser: response.user) else { return nil }
            try Task.checkCancellation()
            return response
        } catch is CancellationError {
            return nil
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
            GravityLogger.e(Self.TAG, "event failed: \(error)")
            return nil
        }
    }

    func chooseByCampaignIdWithDetails(
        campaignId: String,
        options: Options,
        contentSettings: ContentSettings,
        customerUser: User? = nil,
        pageContext: PageContext,
        identityGeneration: UInt64? = nil
    ) async -> GravityDataResponse<ContentResponse>? {
        do {
            let identityRequest = try await sessionManager.beginRequest(
                customUser: customerUser, generation: identityGeneration ?? sessionManager.generation)
            defer { sessionManager.finish(identityRequest) }
            let requestBody = ContentRequest(
                sec: GravitySDK.instance.section,
                device: deviceUtils.getDevice(),
                data: [
                    ByCampaignIdData(
                        campaignId: campaignId,
                        options: contentSettings
                    )
                ],
                user: identityRequest.user,
                ctx: mixPageContextAttributes(pageContext),
                options: options
            )

            let data = try await performRequestForData(
                endpoint: CHOOSE,
                method: "POST",
                body: requestBody
            )
            let response = try parseContentResponse(data)

            guard saveUserIfNeeded(request: identityRequest, contentResponseUser: response.data.user) else { return nil }
            try Task.checkCancellation()
            return response
        } catch is CancellationError {
            return nil
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
            GravityLogger.e(Self.TAG, "chooseByCampaignIdWithDetails failed: \(error)")
            return nil
        }
    }

    func chooseBySelectorWithDetails(
        selector: String,
        options: Options,
        contentSettings: ContentSettings,
        customerUser: User? = nil,
        pageContext: PageContext,
        identityGeneration: UInt64? = nil
    ) async -> GravityDataResponse<ContentResponse>? {
        do {
            let identityRequest = try await sessionManager.beginRequest(
                customUser: customerUser, generation: identityGeneration ?? sessionManager.generation)
            defer { sessionManager.finish(identityRequest) }
            let requestBody = ContentRequest(
                sec: GravitySDK.instance.section,
                device: deviceUtils.getDevice(),
                data: [
                    BySelectorData(
                        selector: selector,
                        options: contentSettings
                    )
                ],
                user: identityRequest.user,
                ctx: mixPageContextAttributes(pageContext),
                options: options
            )

            let data = try await performRequestForData(
                endpoint: CHOOSE,
                method: "POST",
                body: requestBody
            )
            let response = try parseContentResponse(data)

            guard saveUserIfNeeded(request: identityRequest, contentResponseUser: response.data.user) else { return nil }
            try Task.checkCancellation()
            return response
        } catch is CancellationError {
            return nil
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
            GravityLogger.e(Self.TAG, "chooseBySelectorWithDetails failed: \(error)")
            return nil
        }
    }

    func chooseByGroup(
        group: String,
        options: Options,
        contentSettings: ContentSettings,
        customerUser: User? = nil,
        pageContext: PageContext,
        identityGeneration: UInt64? = nil
    ) async -> ContentResponse? {
        do {
            let identityRequest = try await sessionManager.beginRequest(
                customUser: customerUser, generation: identityGeneration ?? sessionManager.generation)
            defer { sessionManager.finish(identityRequest) }
            let requestBody = ContentRequest(
                sec: GravitySDK.instance.section,
                device: deviceUtils.getDevice(),
                data: [
                    ByGroupData(
                        group: group,
                        options: contentSettings
                    )
                ],
                user: identityRequest.user,
                ctx: mixPageContextAttributes(pageContext),
                options: options
            )

            let response: ContentResponse = try await performRequest(
                endpoint: CHOOSE,
                method: "POST",
                body: requestBody
            )

            guard saveUserIfNeeded(request: identityRequest, contentResponseUser: response.user) else { return nil }
            try Task.checkCancellation()
            return response
        } catch is CancellationError {
            return nil
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
            GravityLogger.e(Self.TAG, "chooseByGroup failed: \(error)")
            return nil
        }
    }

    func trackEngagementEvent(urls: [String], apiKey: String? = nil) async throws {
        let transport = EngagementTransport(session: urlSession)
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(apiKey ?? GravitySDK.instance.apiKey)"]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for value in urls {
                group.addTask {
                    try await transport.send(url: value, headers: headers,
                                             logRequest: self.logHttpRequest,
                                             logResponse: { self.logHttpResponse(response: $0, data: $1, method: "GET") })
                }
            }
            try await group.waitForAll()
        }
    }

    func sendErrorMessage(
        message: String,
        stacktrace: String
    ) async {
        guard !Task.isCancelled,
              let permit = errorReportLimiter.begin(message: message, stacktrace: stacktrace) else { return }
        defer { errorReportLimiter.complete(permit, delivered: false) }
        let customerUser = GravitySDK.instance.user
        let cached = sessionManager.cachedUser(customUser: nil)
        // SessionManager owns the current device identity, including reset/restore.
        // Never resurrect stale storage or substitute the host's custom user id.
        let uid = [cached.uid].compactMap { $0 }.first { !$0.isEmpty }
            ?? deviceUtils.getDeviceId()
        let ses = [cached.ses, customerUser?.ses].compactMap { $0 }
            .first { !$0.isEmpty } ?? "no-session"
        let sec = GravitySDK.instance.section

        let logMessage = LogMessage(
            message: message,
            level: .error,
            sec: sec,
            uid: uid,
            ses: ses,
            sdkVersion: GravitySDKInfo.version,
            platform: deviceUtils.getPlatformVersion(),
            stacktrace: stacktrace
        )

        do {
            let urlString = "https://sdk-sentry.gravityfield.ai/error"
            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL(urlString)
            }
            try await performRequest(url: url, method: "POST", body: logMessage, authorized: false)
            errorReportLimiter.complete(permit, delivered: true)
        } catch {
            errorReportLimiter.complete(permit, delivered: false)
            GravityLogger.e(Self.TAG, "sendErrorMessage failed: \(error)", sendToBack: false)
        }
    }

    func userForRequest(_ customerUser: User?) -> User {
        sessionManager.cachedUser(customUser: customerUser)
    }

    private func mixPageContextAttributes(_ pageContext: PageContext)
        -> PageContext
    {
        var attributes = pageContext.attributes
        attributes.merge(DeviceUtils.shared.contextAttributes) { current, _ in
            current
        }
        return PageContext(
            type: pageContext.type,
            data: pageContext.data,
            location: pageContext.location,
            lng: pageContext.lng,
            pageNumber: pageContext.pageNumber,
            referrer: pageContext.referrer,
            utm: pageContext.utm,
            attributes: attributes
        )
    }

    private func saveUserIfNeeded(request: SessionManager.Request, contentResponseUser: User?) -> Bool {
        do { try sessionManager.accept(contentResponseUser, for: request) }
        catch {
            GravityLogger.e(Self.TAG, "Server UID is available in memory but could not be stored: \(error)", sendToBack: false)
        }
        return sessionManager.isCurrent(request.generation)
    }

    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String,
        body: Encodable? = nil,
        authorized: Bool = true
    ) async throws -> T {
        let urlString = "\(baseUrl)\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }
        return try await performRequest(url: url, method: method, body: body, authorized: authorized)
    }

    private func performRequest<T: Decodable>(
        url: URL,
        method: String,
        body: Encodable? = nil,
        authorized: Bool = true
    ) async throws -> T {
        let (data, response) = try await makeRequest(url: url, method: method, body: body, authorized: authorized)
        
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    private func performRequestForData(
        endpoint: String,
        method: String,
        body: Encodable? = nil
    ) async throws -> Data {
        let urlString = "\(baseUrl)\(endpoint)"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }
        let (data, _) = try await makeRequest(url: url, method: method, body: body)
        return data
    }

    private func performRequest(
        url: URL,
        method: String,
        body: Encodable? = nil,
        authorized: Bool = true
    ) async throws {
        _ = try await makeRequest(url: url, method: method, body: body, authorized: authorized)
    }

    private func makeRequest(
        url: URL,
        method: String,
        body: Encodable? = nil,
        authorized: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized {
            request.setValue("Bearer \(GravitySDK.instance.apiKey)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            do {
                request.httpBody = try jsonEncoder.encode(body)
            } catch {
                throw NetworkError.encodingError(error)
            }
        }

        logHttpRequest(request: request)

        let data: Data
        let response: URLResponse
        do { (data, response) = try await urlSession.data(for: request) }
        catch let error as URLError {
            throw NetworkError.transportFailure(error, method: method, url: url.absoluteString)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        logHttpResponse(response: httpResponse, data: data, method: method)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, method: method, url: url.absoluteString)
        }
        
        return (data, httpResponse)
    }

    private func safeDiagnosticHeader(key: String, value: String) -> String {
        let name = key.lowercased()
        if name == "authorization" { return "Bearer ***" }
        if ["proxy-authorization", "cookie", "set-cookie", "x-api-key"].contains(name) { return "***" }
        return ReportSanitizer.sanitizeText(value, limit: 1000)
    }

    private func logHttpRequest(request: URLRequest) {
        let url = request.url
        let method = request.httpMethod
        let bodyData = request.httpBody
        
        var logMessage = "REQUEST: \(ReportSanitizer.sanitizeUrls(url?.absoluteString ?? "nil"))\n"
        logMessage += "METHOD: \(method ?? "nil")\n"

        logMessage += "COMMON HEADERS\n"
        if let headers = request.allHTTPHeaderFields {
            let sortedKeys = headers.keys.sorted { $0.lowercased() < $1.lowercased() }
            for key in sortedKeys {
                if let value = headers[key] {
                    let loggedValue = safeDiagnosticHeader(key: key, value: value)
                    logMessage += "-> \(key): \(loggedValue)\n"
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
                logMessage += "\(ReportSanitizer.sanitizeText(jsonString, limit: 5000))\n"
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

        GravityLogger.d(prefix: "HTTP", logMessage)
    }

    private func logHttpResponse(response: HTTPURLResponse, data: Data, method: String) {
        var logMessage = "RESPONSE: \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))\n"
        logMessage += "METHOD: \(method)\n"
        logMessage += "FROM: \(ReportSanitizer.sanitizeUrls(response.url?.absoluteString ?? "nil"))\n"
        
        logMessage += "COMMON HEADERS\n"
        for (key, value) in response.allHeaderFields {
            logMessage += "-> \(key): \(safeDiagnosticHeader(key: String(describing: key), value: String(describing: value)))\n"
        }
        
        if !(200...299).contains(response.statusCode) {
            logMessage += "BODY: [omitted for HTTP failure; \(data.count) bytes]"
        } else if let jsonString = String(data: data, encoding: .utf8) {
            let contentType = response.allHeaderFields["Content-Type"] as? String ?? "nil"
            logMessage += "BODY Content-Type: \(contentType)\n"
            logMessage += "BODY START\n"
            logMessage += "\(ReportSanitizer.sanitizeText(jsonString, limit: 5000))\n"
            logMessage += "BODY END"
        } else {
            logMessage += "BODY: [empty or non-UTF8]"
        }
        
        GravityLogger.d(prefix: "HTTP", logMessage)
    }

    private struct VisitRequest: Encodable {
        let sec: String
        let device: Device
        let type: String
        let user: User
        let ctx: PageContext
        let options: Options
    }

    private struct EventRequest: Encodable {
        let sec: String
        let device: Device
        let data: [EventPayload]
        let user: User
        let ctx: PageContext
        let options: Options
    }

    private struct ContentRequest<T: ContentRequestData>: Encodable {
        let sec: String
        let device: Device
        let data: [T]
        let user: User
        let ctx: PageContext
        let options: Options
    }

    private protocol ContentRequestData: Encodable {}

    private struct ByCampaignIdData: ContentRequestData {
        let campaignId: String
        let options: ContentSettings
    }

    private struct BySelectorData: ContentRequestData {
        let selector: String
        let options: ContentSettings
    }

    private struct ByGroupData: ContentRequestData {
        let group: String
        let options: ContentSettings
    }
}

/// Decodes a /choose answer into the model and the raw JSON of the same bytes.
func parseContentResponse(_ data: Data) throws -> GravityDataResponse<ContentResponse> {
    do {
        let decoder = JSONDecoder()
        return GravityDataResponse(
            data: try decoder.decode(ContentResponse.self, from: data),
            json: try decoder.decode(JSONValue.self, from: data)
        )
    } catch {
        throw NetworkError.decodingError(error)
    }
}
