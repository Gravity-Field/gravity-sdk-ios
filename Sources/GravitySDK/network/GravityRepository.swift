import Foundation

internal class GravityRepository {

    private let BASE_URL = "https://evs-01.gravityfield.ai/v2"
    private let CHOOSE = "/choose"
    private let VISIT = "/visit"
    private let EVENT = "/event"

    static let instance = GravityRepository()

    private init() {}

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private let prefs = Prefs.shared
    private let deviceUtils = DeviceUtils.shared

    private var userIdCache: String?
    private var sessionIdCache: String?

    private var baseUrl: String {
        return GravitySDK.instance.proxyUrl ?? BASE_URL
    }

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5.0
        configuration.timeoutIntervalForResource = 5.0
        configuration.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(GravitySDK.instance.apiKey)",
        ]
        return URLSession(configuration: configuration)
    }()

    func visit(
        pageContext: PageContext,
        options: Options,
        customerUser: User?
    ) async throws -> CampaignIdsResponse {
        let requestBody = VisitRequest(
            sec: GravitySDK.instance.section,
            device: deviceUtils.getDevice(),
            type: "screenview",
            user: userForRequest(customerUser),
            ctx: mixPageContextAttributes(pageContext),
            options: options
        )

        let response: CampaignIdsResponse = try await performRequest(
            endpoint: VISIT,
            method: "POST",
            body: requestBody
        )

        saveUserIfNeeded(
            customerUser: customerUser,
            contentResponseUser: response.user
        )
        return response
    }

    func event(
        events: [TriggerEvent],
        pageContext: PageContext,
        options: Options,
        customerUser: User?
    ) async throws -> CampaignIdsResponse {
        let requestBody = EventRequest(
            sec: GravitySDK.instance.section,
            device: deviceUtils.getDevice(),
            data: events,
            user: userForRequest(customerUser),
            ctx: mixPageContextAttributes(pageContext),
            options: options
        )

        let response: CampaignIdsResponse = try await performRequest(
            endpoint: EVENT,
            method: "POST",
            body: requestBody
        )

        saveUserIfNeeded(
            customerUser: customerUser,
            contentResponseUser: response.user
        )
        return response
    }

    func chooseByCampaignId(
        campaignId: String,
        options: Options,
        contentSettings: ContentSettings,
        customerUser: User? = nil,
        pageContext: PageContext
    ) async throws -> ContentResponse {
        let requestBody = ContentRequest(
            sec: GravitySDK.instance.section,
            device: deviceUtils.getDevice(),
            data: [
                ByCampaignIdData(
                    campaignId: campaignId,
                    options: contentSettings
                )
            ],
            user: userForRequest(customerUser),
            ctx: mixPageContextAttributes(pageContext),
            options: options,
        )

        let response: ContentResponse = try await performRequest(
            endpoint: CHOOSE,
            method: "POST",
            body: requestBody
        )

        saveUserIfNeeded(
            customerUser: customerUser,
            contentResponseUser: response.user
        )
        return response
    }

    func chooseBySelector(
        selector: String,
        options: Options,
        contentSettings: ContentSettings,
        customerUser: User? = nil,
        pageContext: PageContext
    ) async throws -> ContentResponse {
        let requestBody = ContentRequest(
            sec: GravitySDK.instance.section,
            device: deviceUtils.getDevice(),
            data: [
                BySelectorData(
                    selector: selector,
                    options: contentSettings
                )
            ],
            user: userForRequest(customerUser),
            ctx: mixPageContextAttributes(pageContext),
            options: options,
        )

        let response: ContentResponse = try await performRequest(
            endpoint: CHOOSE,
            method: "POST",
            body: requestBody
        )

        saveUserIfNeeded(
            customerUser: customerUser,
            contentResponseUser: response.user
        )
        return response
    }

    func trackEngagementEvent(urls: [String]) async throws {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                if let url = URL(string: url) {
                    group.addTask {
                        _ = try? await self.urlSession.data(from: url)
                    }
                }
            }
        }
    }

    private func userForRequest(_ customerUser: User?) -> User {
        if let customerUser = customerUser {
            return customerUser
        } else if let userIdCache = userIdCache,
            let sessionIdCache = sessionIdCache
        {
            return User(uid: userIdCache, ses: sessionIdCache)
        } else if userIdCache == nil, let sessionIdCache = sessionIdCache {
            let userId = prefs.getUserId()
            return User(uid: userId, ses: sessionIdCache)
        } else {
            let userId = prefs.getUserId()
            return User(uid: userId, ses: nil)
        }
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
            utm: pageContext.utm,
            attributes: attributes
        )

    }

    private func saveUserIfNeeded(
        customerUser: User?,
        contentResponseUser: User?
    ) {
        guard customerUser == nil else { return }

        let uid = contentResponseUser?.uid
        let ses = contentResponseUser?.ses

        if let uid = uid {
            Prefs.shared.setUserId(uid)
            userIdCache = uid
        }

        if let ses = ses {
            sessionIdCache = ses
        }
    }

    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String,
        body: Encodable? = nil
    ) async throws -> T {
        let url = URL(string: "\(baseUrl)\(endpoint)")!
        return try await performRequest(url: url, method: method, body: body)
    }

    private func performRequest<T: Decodable>(
        url: URL,
        method: String,
        body: Encodable? = nil
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method

        if let body = body {
            request.httpBody = try jsonEncoder.encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
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
        let data: [TriggerEvent]
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
}

enum NetworkError: Error {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case encodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        }
    }
}
