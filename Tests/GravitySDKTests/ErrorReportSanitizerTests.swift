import Foundation
import Testing
@testable import GravitySDK

/// What an error report carries: every http(s) URL in it loses its query, fragment
/// and credentials, where user ids, tokens and tracking parameters travel.
extension SDKSingletonTests {
struct ErrorReportSanitizerTests {

    @Test func stripsQueryFragmentAndCredentialsKeepingPort() {
        #expect(ReportSanitizer.sanitizeUrls(
            "GET https://user:pass@ev.example.com:8443/v2/engagement?uid=abc&token=t#frag failed"
        ) == "GET https://ev.example.com:8443/v2/engagement failed")
    }

    @Test func stripsUrlsInsideAStacktrace() {
        // The closing bracket goes with the query: a query may hold brackets
        // of its own, so nothing after `?` is trusted to end it.
        #expect(ReportSanitizer.sanitizeUrls("#0 fetch (see http://ev.example.com/pixel?cuid=secret)")
            == "#0 fetch (see http://ev.example.com/pixel")
    }

    @Test func keepsABracketedIPv6Host() {
        let sanitized = ReportSanitizer.sanitizeUrls(
            "DioException [connectionError] GET http://[::1]:8080/pixel?uid=ipv6-query-uid -> no response")
        #expect(sanitized == "DioException [connectionError] GET http://[::1]:8080/pixel -> no response")
        #expect(!sanitized.contains("ipv6-query-uid"))
    }

    @Test func dropsTheWholeQueryEvenWhereItHoldsCommasOrBrackets() {
        #expect(ReportSanitizer.sanitizeUrls(
            "GET http://[::1]:8080/pixel?uid=,comma-secret failed; "
                + "see https://ev.example.com/p?a=(x),y&uid=bracket-secret#f,frag-secret."
        ) == "GET http://[::1]:8080/pixel failed; see https://ev.example.com/p")
    }

    @Test func stripsAFragmentWithoutAQuery() {
        #expect(ReportSanitizer.sanitizeUrls("open HTTPS://ev.example.com/a/b#uid=frag-secret now")
            == "open HTTPS://ev.example.com/a/b now")
    }

    @Test func stripsUrlsWithCharactersOutsideRfc3986() {
        // Older Foundation refuses `|` and the URL is cut by hand; newer one
        // percent-encodes it. Either way the query and credentials are gone.
        let sanitized = ReportSanitizer.sanitizeUrls("see https://u:p@ev.example.com/a|b?uid=hand-secret")
        #expect(["see https://ev.example.com/a|b", "see https://ev.example.com/a%7Cb"].contains(sanitized))
    }

    @Test func leavesTextWithoutUrlsAsItIs() {
        let text = "[ContentEvent] Visible impression has no tracking URL: uid=abc, ftp://x/y?z=1"
        #expect(ReportSanitizer.sanitizeUrls(text) == "[ContentEvent] Visible impression has no tracking URL: uid=abc, ftp://x/y")
        #expect(ReportSanitizer.sanitizeUrls("") == "")
    }

    @Test func logMessageSanitizesEveryFreeTextField() {
        let message = LogMessage(
            message: "GET https://ev.example.com/v2/engagement?uid=abc failed",
            level: .error, sec: "section", uid: "device-uid", ses: "session",
            sdkVersion: "1.0", platform: "iOS",
            stacktrace: "#0 fetch (see http://ev.example.com/pixel?cuid=secret)",
            extra: ["url": "https://ev.example.com/v2/engagement?type=WCLICK&uid=abc", "plain": "plain text"],
            tags: ["endpoint": "https://ev.example.com/x?y=1"]
        )
        #expect(message.message == "GET https://ev.example.com/v2/engagement failed")
        #expect(message.stacktrace == "#0 fetch (see http://ev.example.com/pixel")
        #expect(message.extra == ["url": "https://ev.example.com/v2/engagement", "plain": "plain text"])
        #expect(message.tags == ["endpoint": "https://ev.example.com/x"])
        // Identity fields are not free text and go out as they are.
        #expect(message.uid == "device-uid")
        #expect(message.ses == "session")
    }

    @Test func punctuationInPathsCannotHideQueries() {
        for url in [
            "https://host/p(1)?uid=SECRET", "https://host/a,b?uid=SECRET",
            "https://host/{id}?token=SECRET", "https://host/a[b?uid=SECRET",
            "https://u:p@[::1/p?uid=1", "https://user:p@ss@host.com/p?uid=SECRET"
        ] {
            let clean = ReportSanitizer.sanitizeUrls(url)
            for secret in ["SECRET", "uid=", "token=", "u:p", "user:p", "ss@"] {
                #expect(!clean.contains(secret))
            }
        }
        #expect(ReportSanitizer.sanitizeUrls("https://user:p@ss@host.com/p") == "https://host.com/p")
    }

    @Test func adjacentAndNestedUrlsStripEveryAuthority() {
        for separator in [",", ";", "/redirect=", "("] {
            let input = "https://public.test/" + separator
                + "https://user:SECRET@private.test/path?token=QUERY#FRAGMENT"
            let clean = ReportSanitizer.sanitizeUrls(input)
            #expect(clean == "https://public.test/" + separator + "https://private.test/path")
            #expect(!clean.contains("SECRET"))
        }
        #expect(ReportSanitizer.sanitizeUrls(
            "https://first.test/?token=SECRET,https://user:PASS@second.test/path") == "https://first.test/")
        let chain = String(repeating: "https://user:SECRET@host.test/,", count: 10_000)
        let clean = ReportSanitizer.sanitizeUrls(chain)
        #expect(!clean.contains("SECRET"))
        #expect(clean.components(separatedBy: "https://host.test/").count == 10_001)
    }

    @Test func longUrlDoesNotBypassSanitization() {
        let url = "https://host/" + String(repeating: "a", count: 1_000_000) + "?uid=SECRET"
        let clean = ReportSanitizer.sanitizeUrls(url)
        let leakedSecret = clean.contains("SECRET") || clean.contains("uid=")
        #expect(!leakedSecret)
    }

    @Test func reportTextIsBoundedBeforeAndAfterSanitization() {
        let url = "https://host/p(1)?uid=SECRET" + String(repeating: "a", count: 1_000_000)
        let report = LogMessage(message: url, level: .error, sec: "s", uid: "d", ses: "s",
            sdkVersion: "1", platform: "iOS", stacktrace: url,
            extra: ["url": url], tags: ["url": url])
        // Keep failure diagnostics bounded too: do not print million-character values.
        let cleanMessage = report.message.isEmpty
        let cleanStacktrace = report.stacktrace.isEmpty
        let leakedExtra = report.extra["url"]!.contains("SECRET")
        let leakedTag = report.tags["url"]!.contains("SECRET")
        #expect(cleanMessage)
        #expect(cleanStacktrace)
        #expect(!leakedExtra)
        #expect(!leakedTag)
        let plain = LogMessage(message: String(repeating: "m", count: 100_000),
            level: .error, sec: "s", uid: "d", ses: "s", sdkVersion: "1", platform: "iOS",
            stacktrace: String(repeating: "s", count: 100_000))
        #expect(plain.message.count == 1000)
        #expect(plain.stacktrace.count == 5000)
        #expect(plain.message.hasSuffix("..."))
        #expect(plain.stacktrace.hasSuffix("..."))
    }

    @Test func preliminaryLimitDropsPartialCredentials() {
        for limit in [1000, 5000] {
            // A preceding query disappears during cleaning, exposing the cut URL
            // within the final limit; plain padding alone would hide this regression.
            let head = "https://padding/?"
            let partial = "https://user:SEC"
            let padding = head + String(repeating: "x", count: limit * 10 - head.count - 1 - partial.count) + " "
            let clean = ReportSanitizer.sanitizeText(
                padding + "https://user:SECRETPASS@host/p?uid=SECRET", limit: limit)
            #expect(clean == "https://padding/ ")
            #expect(!clean.contains("SEC"))
            #expect(!clean.contains("user:"))
        }
    }

    @Test func preliminaryLimitDropsPartialQueryButKeepsCompleteTokens() {
        for limit in [1000, 5000] {
            let head = "https://padding/?"
            let partial = "https://user:SECRETPASS@host/p?uid=SEC"
            let padding = head + String(repeating: "x", count: limit * 10 - head.count - 1 - partial.count) + " "
            let clean = ReportSanitizer.sanitizeText(padding + partial + "RET", limit: limit)
            #expect(clean == "https://padding/ ")
            #expect(!clean.contains("SEC"))
            // The same prefix is complete at EOF or when the next character is a delimiter.
            for suffix in ["", " next", "\"next", "<next"] {
                #expect(ReportSanitizer.sanitizeText(padding + partial + suffix, limit: limit)
                    == "https://padding/ https://host/p" + suffix)
            }
        }
    }

    @Test func httpFailureContainsOnlyRequestContextAndStatus() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailedReportProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            try await EngagementTransport(session: session).send(url: "https://host/p(1)?uid=SECRET")
            Issue.record("Expected HTTP failure")
        } catch {
            let text = String(describing: error)
            #expect(text.contains("GET"))
            #expect(text.contains("https://host/p(1)"))
            #expect(text.contains("404"))
            #expect(!text.contains("SECRET"))
            #expect(!text.contains("private-response-body"))
        }
    }

    @Test func decodingFailureCannotQuoteServerBody() {
        let error = DecodingError.dataCorrupted(.init(codingPath: [],
            debugDescription: "private-response-body", underlyingError: nil))
        #expect(!String(describing: NetworkError.decodingError(error)).contains("private-response-body"))
    }

    @Test func sentReportCarriesNoQueryOfAFailedTrackingUrl() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SanitizedReportProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = GravityRepository(urlSession: session)
        let trackingUrl = "https://ev.example.com/v2/engagement?type=WCLICK&uid=leaked-uid&token=leaked-token#leaked-frag"
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [
            NSLocalizedDescriptionKey: "The connection failed for \(trackingUrl)",
            NSURLErrorFailingURLStringErrorKey: trackingUrl,
        ])

        // The way ContentEventService reports a failed engagement delivery.
        GravityLogger.e("ContentEvent", "Engagement delivery failed: \(error)", error, repository: repository)

        let request = try #require(await SanitizedReportProtocol.waitForFirst())
        #expect(request.url?.absoluteString == "https://sdk-sentry.gravityfield.ai/error")
        let body = try #require(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        for secret in ["leaked-uid", "leaked-token", "leaked-frag", "WCLICK"] {
            #expect(!text.contains(secret))
        }
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let message = try #require(json["message"] as? String)
        #expect(message.hasPrefix("[ContentEvent] Engagement delivery failed: "))
        #expect(message.contains("https://ev.example.com/v2/engagement"))
        #expect(json["stacktrace"] as? String == "HTTP https://ev.example.com/v2/engagement -> URLError(-1009)")
    }
}

}

private final class SanitizedReportProtocol: URLProtocol, @unchecked Sendable {
    private static let recorder = TestRequestRecorder<URLRequest>()
    static func waitForFirst() async -> URLRequest? { await recorder.waitFor(1).first }
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
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class FailedReportProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 404,
            httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("private-response-body".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
