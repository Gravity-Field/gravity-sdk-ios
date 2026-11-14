import XCTest
@testable import GravitySDK

final class ReleaseHTTPDiagnosticTests: XCTestCase {
    @MainActor func testHTTPDiagnosticsContainOnlyMethodEndpointAndStatus() async throws {
        let fixture = TemporarySDKFixture(apiKey: "API-KEY-SECRET")
        let sdk = fixture.initialize()
        sdk.setUser(userId: "CUSTOMER-ID-SECRET", sessionId: "SESSION-SECRET")
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: "https://example.test")
        let oldLevel = GravityLogger.logLevel
        let messages = TestRequestRecorder<String>()
        GravityLogger.configure(.debug)
        sdk.logListener = { _, text in messages.append(text) }
        defer { sdk.logListener = nil; GravityLogger.configure(oldLevel) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseHTTPFailureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let repository = GravityRepository(urlSession: session)
        _ = await repository.chooseBySelectorWithDetails(selector: "selector", options: Options(),
            contentSettings: ContentSettings(), customerUser: sdk.user, pageContext: PageContext(type: .other, data: [], location: "test"))
        let logs = messages.values.filter { $0.hasPrefix("[HTTP]") }.joined(separator: "\n")
        XCTAssertTrue(logs.contains("POST"))
        XCTAssertTrue(logs.contains("403"))
        XCTAssertTrue(logs.contains("https://example.test/choose"))
        for secret in ["API-KEY-SECRET", "CUSTOMER-ID-SECRET", "SESSION-SECRET", "HEADER-SECRET", "BODY-SECRET"] {
            XCTAssertFalse(logs.contains(secret), secret)
        }
        XCTAssertFalse(logs.contains("COMMON HEADERS"))
        XCTAssertFalse(logs.contains("BODY"))
    }
}

private final class ReleaseHTTPFailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1",
            headerFields: ["X-Authorization": "Bearer HEADER-SECRET", "X-Diagnostic": "HEADER-SECRET"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("BODY-SECRET".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
