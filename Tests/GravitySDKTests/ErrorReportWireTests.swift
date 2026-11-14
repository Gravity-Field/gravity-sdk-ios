import Foundation
import Testing
import UIKit
@testable import GravitySDK

extension SDKSingletonTests {
 struct ErrorReportWireTests {
    private let pageContext = PageContext(type: .other, data: [], location: "/custom-user")

    // Same key as Prefs
    private static let userIdKey = "gravity_user_id"

    private func withServer(_ body: (RecordingServer, TemporarySDKFixture) async throws -> Void) async throws {
        // The anonymous test persists a server uid; put back whatever was there
        let savedUserId = UserDefaults.standard.string(forKey: Self.userIdKey)
        defer { UserDefaults.standard.set(savedUserId, forKey: Self.userIdKey) }
        let fixture = TemporarySDKFixture(apiKey: "custom-user-key", section: "custom-user-section")
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        fixture.initialize()
        GravitySDK.instance.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        defer {
            fixture.initialize()
        }
        try await body(server, fixture)
    }

    private func user(_ request: RecordingServer.Request) -> [String: String] {
        (request.body["user"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
    }

    private func chooseRequests(_ server: RecordingServer) -> [RecordingServer.Request] {
        server.recorded.filter { $0.path.hasSuffix("/choose") }
    }

    private func getContentAllWays() async {
        _ = await GravitySDK.instance.getContentBySelector(selector: "sel", pageContext: pageContext)
        _ = await GravitySDK.instance.getContentByCampaignId("101", pageContext)
        _ = await GravitySDK.instance.getContentByGroupSelector(groupSelector: "grp", pageContext: pageContext)
    }

    @Test func httpLogsRedactAuthorizationBeforeCallingTheHostListener() async throws {
        try await withServer { server, fixture in
            let messages = PrivacyMessages()
            GravityLogger.configure(.debug)
            GravitySDK.instance.logListener = { _, message in messages.append(message) }
            defer {
                GravitySDK.instance.logListener = nil
                GravityLogger.configure(.error)
            }

            await getContentAllWays()
            let requests = messages.values.filter { $0.contains("REQUEST:") }
            #expect(requests.count == 3)
            for message in requests {
                #expect(!message.contains("Authorization"))
                #expect(!message.contains(fixture.apiKey))
            }
        }
    }

    @Test func errorReportsCarryDeviceUidNotCustomerIdAtEveryLogLevel() async throws {
        let savedUserId = UserDefaults.standard.string(forKey: Self.userIdKey)
        defer { UserDefaults.standard.set(savedUserId, forKey: Self.userIdKey) }
        let fixture = TemporarySDKFixture(apiKey: "privacy-key", section: "privacy-section")
        fixture.initialize()
        defer { fixture.initialize() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PrivacyReportProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = GravityRepository(urlSession: session)
        // Populate the repository's anonymous caches from an actual decoded answer.
        let anonymous = await repository.chooseBySelectorWithDetails(
            selector: "privacy", options: Options(), contentSettings: ContentSettings(),
            pageContext: pageContext)
        #expect(anonymous?.data.user?.uid == "private-anonymous-user")
        try Prefs.shared.setUserId("different-saved-user")
        PrivacyReportProtocol.reset()
        let messages = PrivacyMessages()
        let error = NSError(domain: "privacy", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "test stack"])

        for (index, level) in [LogLevel.debug, .info, .error, .none].enumerated() {
            GravityLogger.configure(level)
            GravitySDK.instance.setUser(userId: "private-custom-user", sessionId: "short-session")
            GravitySDK.instance.logListener = { level, message in
                if level == .error { messages.append(message) }
            }
            let localCount = messages.values.count
            GravityLogger.e("Privacy", "test error \(index)", error, repository: repository)
            #expect(messages.values.count == localCount + (level == .none ? 0 : 1))
            let sent = await PrivacyReportProtocol.waitFor(index + 1)
            try #require(sent.count == index + 1)
        }
        fixture.initialize()
        GravityLogger.configure(.none)
        GravityLogger.e("Privacy", "anonymous error", repository: repository)
        _ = await PrivacyReportProtocol.waitFor(5)

        let reports = PrivacyReportProtocol.requests
        #expect(reports.count == 5)
        for (index, request) in reports.enumerated() {
            #expect(request.url?.absoluteString == "https://sdk-sentry.gravityfield.ai/error")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            // The report endpoint answers 400 without a non-empty uid.
            #expect(json["uid"] as? String == "private-anonymous-user")
            #expect(!String(decoding: body, as: UTF8.self).contains("private-custom-user"))
            #expect(json["sec"] as? String == "privacy-section")
            #expect(json["level"] as? String == "error")
            #expect(json["sdkType"] as? String == "ios_native")
            if index < 4 {
                #expect(json["ses"] as? String == "anonymous-session")
                #expect(json["message"] as? String == "[Privacy] test error \(index)")
                #expect(json["stacktrace"] as? String == "test stack")
            } else {
                #expect(json["ses"] as? String == "anonymous-session")
                #expect(json["message"] as? String == "[Privacy] anonymous error")
            }
        }
    }

    @Test func reportsBeforeAnyResponseUseDeviceAndSessionFallbacks() async throws {
        let savedUid = Prefs.shared.getUserId()
        let savedDevice = Prefs.shared.getDeviceId()
        defer {
            UserDefaults.standard.set(savedUid, forKey: "gravity_user_id")
            UserDefaults.standard.set(savedDevice, forKey: "gravity_device_id")
        }
        let fixture = TemporarySDKFixture(apiKey: "privacy-key", section: "privacy-section")
        fixture.initialize()
        defer { fixture.initialize() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PrivacyReportProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        PrivacyReportProtocol.reset()
        for (index, storedUid) in [nil, "", "stored-server-uid", nil].enumerated() {
            UserDefaults.standard.set(storedUid, forKey: "gravity_user_id")
            UserDefaults.standard.set(index == 3 ? "stored-device-id" : (index == 1 ? "" : nil),
                forKey: "gravity_device_id")
            fixture.initialize()
            let repository = GravityRepository(urlSession: session)
            await repository.sendErrorMessage(message: "cold start", stacktrace: "")
            GravitySDK.instance.setUser(userId: "e2e-custom-private", sessionId: index == 3 ? "" : "custom-session")
            await repository.sendErrorMessage(message: "after setUser", stacktrace: "")
            let reports = PrivacyReportProtocol.requests
            try #require(reports.count == (index + 1) * 2)
            let deviceId = try #require(DeviceUtils.shared.getDevice().id)
            #expect(!deviceId.isEmpty)
            if index == 3 { #expect(deviceId == "stored-device-id") }
            for offset in 0..<2 {
                let body = try #require(reports[index * 2 + offset].httpBody)
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(json["uid"] as? String == (storedUid == "stored-server-uid" ? storedUid : deviceId))
                #expect(json["ses"] as? String == (offset == 0 || index == 3 ? "no-session" : "custom-session"))
                #expect(!String(decoding: body, as: UTF8.self).contains("e2e-custom-private"))
            }
        }
    }

    @Test func reportsUseRestoredIdentityAndDoNotResurrectStorageAfterReset() async throws {
        let savedUid = Prefs.shared.getUserId()
        defer { UserDefaults.standard.set(savedUid, forKey: Self.userIdKey) }
        let fixture = TemporarySDKFixture(apiKey: "privacy-key", section: "privacy-section")
        fixture.initialize()
        defer { fixture.initialize() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PrivacyReportProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = GravityRepository(urlSession: session)
        PrivacyReportProtocol.reset()
        try repository.sessionManager.restoreUserId("restored-server-uid")
        await repository.sendErrorMessage(message: "restored", stacktrace: "")
        try repository.sessionManager.resetUser()
        // A stale disk value must not override the authoritative reset in memory.
        try Prefs.shared.setUserId("stale-disk-uid")
        await repository.sendErrorMessage(message: "reset", stacktrace: "")
        let reports = PrivacyReportProtocol.requests
        try #require(reports.count == 2)
        let restored = try #require(reports[0].httpBody)
        let reset = try #require(reports[1].httpBody)
        let restoredJson = try #require(JSONSerialization.jsonObject(with: restored) as? [String: Any])
        let resetJson = try #require(JSONSerialization.jsonObject(with: reset) as? [String: Any])
        #expect(restoredJson["uid"] as? String == "restored-server-uid")
        #expect(resetJson["uid"] as? String == DeviceUtils.shared.getDevice().id)
        #expect(resetJson["ses"] as? String == "no-session")
    }
 }
}

private final class PrivacyMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func append(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(message)
    }
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

private final class PrivacyReportProtocol: URLProtocol, @unchecked Sendable {
    private static let recorder = TestRequestRecorder<URLRequest>()
    static var requests: [URLRequest] { recorder.values }
    static func reset() { recorder.reset() }
    static func waitFor(_ count: Int) async -> [URLRequest] { await recorder.waitFor(count) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            captured.httpBody = body
        }
        Self.recorder.append(captured)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = Data(#"{"data":[],"user":{"uid":"private-anonymous-user","ses":"anonymous-session"}}"#.utf8)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
