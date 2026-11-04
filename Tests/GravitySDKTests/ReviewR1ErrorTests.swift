import Foundation
import Testing
import XCTest
import NetworkTestGuard
@testable import GravitySDK

extension SDKSingletonTests {
    struct ReviewR1ErrorTests {
        @Test func malformedAndEncodedCredentialsNeverReachReports() {
            for input in [
                "https://user:SE?CRET@host.test/path", "https://user:SE#CRET@host.test/path",
                "https://user:SE/CRET@host.test/path", "https://proxy.test/redirect/ftp://user:SECRET@private.test/x",
                "wss://user:SECRET@socket.test/x", #"https:\/\/user:SECRET@host.test\/p"#,
                "https%3A%2F%2Fuser%3ASECRET%40host.test",
                "https://public.test/,https://user:SECRET@private.test/path?token=x"
            ] {
                let output = ReportSanitizer.sanitizeText(input, limit: 1000)
                #expect(!output.contains("SE"), "Credential bytes survived: \(output)")
                #expect(!output.contains("user:"))
            }
        }

        @Test func queryAtSignCannotPromoteSecretToHostname() {
            #expect(!ReportSanitizer.sanitizeText("https://public.test/path?token=value@SECRET", limit: 1000).contains("SECRET"))
        }

        @Test func incompleteEncodedAndRelativeCredentialsCannotSurvive() {
            for input in ["https://user:SE CRET@host.test/path", "//user:SECRET@host.test/p",
                "https%3A%2F%2Fuser%3ASECRET%40host.test/p%ZZ"] {
                #expect(!ReportSanitizer.sanitizeText(input, limit: 1000).contains("SE"))
            }
        }

        @Test func legitimateEndpointsRemainUsefulWithoutExposingQueries() {
            for (input, expected) in [
                ("https://public.test/path?token=value@SECRET", "https://public.test/path"),
                ("https://public.test/a%20b?token=SECRET", "https://public.test/a%20b"),
                ("https://public.test/p%3Fname?token=SECRET", "https://public.test/p%3Fname"),
                ("https://public.test/users/person@example.test", "https://public.test/users/person@example.test"),
                ("https://user%3ASECRET%40private.test/path?token=x", "https://private.test/path")
            ] {
                #expect(ReportSanitizer.sanitizeUrls(input) == expected)
            }
        }

        @Test @MainActor func debugFailuresKeepEndpointsButCannotExposeSecrets() async throws {
            let fixture = TemporarySDKFixture()
            let sdk = fixture.initialize()
            sdk.setOptions(options: nil, contentSettings: nil,
                proxyUrl: "https://user:AUTH-SECRET@public.test/proxy?token=QUERY-SECRET")
            let oldLevel = GravityLogger.logLevel
            let oldListener = sdk.logListener
            let messages = TestRequestRecorder<String>()
            GravityLogger.configure(.debug)
            sdk.logListener = { _, message in messages.append(message) }
            defer { sdk.logListener = oldListener; GravityLogger.configure(oldLevel) }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ReadinessHTTPFailureProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let repository = GravityRepository(urlSession: session)
            _ = await repository.chooseBySelectorWithDetails(selector: "test", options: Options(), contentSettings: ContentSettings(),
                pageContext: PageContext(type: .other, data: [], location: "diagnostics"))
            let text = messages.values.joined(separator: "\n")
            for secret in ["AUTH-SECRET", "QUERY-SECRET", "BODY-SECRET", "COOKIE-SECRET"] { #expect(!text.contains(secret)) }
            #expect(text.contains("https://public.test/proxy"))
            #expect(text.contains("500"))
        }

        @Test @MainActor func localErrorDiagnosticsRedactURLsWithoutDroppingEndpoints() {
            let fixture = TemporarySDKFixture()
            let sdk = fixture.initialize()
            let oldLevel = GravityLogger.logLevel
            let oldListener = sdk.logListener
            let messages = TestRequestRecorder<String>()
            GravityLogger.configure(.error)
            sdk.logListener = { _, message in messages.append(message) }
            defer { sdk.logListener = oldListener; GravityLogger.configure(oldLevel) }
            GravityLogger.e("Readiness", "GET https://user:AUTH-SECRET@public.test/p?token=QUERY-SECRET", sendToBack: false)
            let text = messages.values.joined(separator: "\n")
            #expect(!text.contains("AUTH-SECRET"))
            #expect(!text.contains("QUERY-SECRET"))
            #expect(text.contains("https://public.test/p"))
        }

        @Test @MainActor func cancelledInflightRequestsDoNotReport() async throws {
            let fixture = TemporarySDKFixture()
            let sdk = fixture.initialize()
            let server = try RecordingServer()
            try await server.start()
            defer { server.stop() }
            sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
            let page = PageContext(type: .other, data: [], location: "cancel")
            for operation in 0..<3 {
                server.reset()
                server.holdNextResponse()
                let reports = TestRequestRecorder<String>()
                let report = XCTestExpectation(description: "cancellation cannot report")
                report.isInverted = true
                let observation = NotificationCenter.default.addObserver(forName: .init("GravityTestNetworkGuardBlocked"), object: nil, queue: nil) {
                    if $0.object as? String == "sdk-sentry.gravityfield.ai",
                       let message = $0.userInfo?["message"] as? String, message.contains(server.url) {
                        reports.append(message)
                        report.fulfill()
                    }
                }
                defer { NotificationCenter.default.removeObserver(observation) }
                let session = URLSession(configuration: .ephemeral)
                let repository = GravityRepository(urlSession: session)
                let task = Task {
                    switch operation {
                    case 0: _ = await repository.visit(pageContext: page, options: Options(), customerUser: nil)
                    case 1: _ = await repository.event(events: [], raisedAt: Date(), pageContext: page, options: Options(), customerUser: nil)
                    default: _ = await repository.chooseBySelectorWithDetails(selector: "cancel", options: Options(), contentSettings: ContentSettings(), pageContext: page)
                    }
                }
                _ = await server.waitFor(1)
                // Cancelling the session produces URLError.cancelled even while the Swift task is not cancelled.
                session.invalidateAndCancel()
                await task.value
                let result = await XCTWaiter.fulfillment(of: [report], timeout: 1)
                #expect(result == .completed)
                #expect(reports.values.isEmpty, "Cancellation must not send a report for the cancelled request")
                server.releaseHeldResponses()
            }
        }
    }
}

private final class ReadinessHTTPFailureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "Set-Cookie": "session=COOKIE-SECRET; Secure; HttpOnly"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"message":"BODY-SECRET"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
