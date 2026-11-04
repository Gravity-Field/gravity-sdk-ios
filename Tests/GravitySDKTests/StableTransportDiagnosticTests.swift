import Foundation
import Testing
@testable import GravitySDK

extension SDKSingletonTests {
    struct StableTransportDiagnosticTests {
        @Test func repeatedTransportFailuresKeepOnlyCodeAndEndpoint() async throws {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [DynamicFailureProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            var failures: [String] = []
            for query in ["first", "second"] {
                do {
                    try await EngagementTransport(session: session).send(url: "https://u:SECRET@host.test/p?id=\(query)")
                    Issue.record("Expected offline failure")
                } catch { failures.append(String(describing: error)) }
            }
            #expect(failures.count == 2)
            #expect(failures.first == failures.last)
            let text = try #require(failures.first)
            for retained in ["GET", "-1009", "https://host.test/p"] { #expect(text.contains(retained)) }
            for removed in ["LocalDataTask", "SECRET", "id=", "first", "second"] { #expect(!text.contains(removed)) }
        }

        @Test func repositoryFailureMessagesDoNotCarryPerRequestIds() async throws {
            let fixture = TemporarySDKFixture()
            let sdk = fixture.initialize()
            sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: "https://host.test")
            let level = GravityLogger.logLevel
            let listener = sdk.logListener
            defer { GravityLogger.configure(level); sdk.logListener = listener }
            GravityLogger.configure(.error)
            let messages = TestRequestRecorder<String>()
            sdk.logListener = { level, text in
                if level == .error && text.hasPrefix("[Repository] visit failed:") { messages.append(text) }
            }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [DynamicFailureProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let repository = GravityRepository(urlSession: session)
            for _ in 0..<2 {
                let response = await repository.visit(pageContext: PageContext(type: .other, data: [], location: "stable"),
                    options: Options(), customerUser: nil)
                #expect(response == nil)
            }
            #expect(messages.values.count == 2)
            #expect(messages.values.first == messages.values.last)
            let text = try #require(messages.values.first)
            #expect(text.contains("POST"))
            #expect(text.contains("https://host.test/visit"))
            #expect(text.contains("-1009"))
            #expect(!text.contains("LocalDataTask"))
            withExtendedLifetime(fixture) {}
        }
    }
}

private final class DynamicFailureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var sequence = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.sequence += 1
        let requestId = Self.sequence
        Self.lock.unlock()
        let error = URLError(.notConnectedToInternet, userInfo: [
            NSLocalizedDescriptionKey: "LocalDataTask <mock-request-\(requestId)>.<1> failed",
            NSURLErrorFailingURLStringErrorKey: request.url!.absoluteString
        ])
        client?.urlProtocol(self, didFailWithError: error)
    }
    override func stopLoading() {}
}
