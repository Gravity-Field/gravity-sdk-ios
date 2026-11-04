import Foundation
import Testing
@testable import GravitySDK

extension SDKSingletonTests {
    struct ErrorReportRateLimitTests {
        private func withRepository(limiter: ErrorReportLimiter = ErrorReportLimiter(), _ body: (GravityRepository) async throws -> Void) async throws {
            let fixture = TemporarySDKFixture()
            fixture.initialize()
            RateLimitReportProtocol.reset()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RateLimitReportProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel(); RateLimitReportProtocol.releaseHeld() }
            try await body(GravityRepository(urlSession: session, errorReportLimiter: limiter))
            withExtendedLifetime(fixture) {}
        }

        @Test func loggerCallsUseTheSameBudgetAndDeduplication() async throws {
            let fixture = TemporarySDKFixture()
            fixture.initialize()
            RateLimitReportProtocol.reset()
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [RateLimitReportProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let clock = ReportClock()
            let repository = CompletedReportRepository(urlSession: session,
                errorReportLimiter: ErrorReportLimiter(now: { clock.value }))
            for index in 0..<12 {
                GravityLogger.e("Budget", "failure-\(index)", repository: repository)
            }
            let first = await repository.completed.waitFor(12)
            #expect(first.count == 12)
            #expect(RateLimitReportProtocol.requests.values.count == 10)
            clock.advance(61)
            GravityLogger.e("Budget", "identical", repository: repository)
            GravityLogger.e("Budget", "identical", repository: repository)
            let duplicates = await repository.completed.waitFor(14)
            #expect(duplicates.count == 14)
            #expect(RateLimitReportProtocol.requests.values.count == 11)
            clock.advance(61)
            GravityLogger.e("Budget", "identical", repository: repository)
            let expired = await repository.completed.waitFor(15)
            #expect(expired.count == 15)
            #expect(RateLimitReportProtocol.requests.values.count == 12)
            withExtendedLifetime(fixture) {}
        }

        @Test func clockExpiryAllowsIdenticalReportsAgain() async throws {
            let clock = ReportClock()
            try await withRepository(limiter: ErrorReportLimiter(now: { clock.value })) { repository in
                await repository.sendErrorMessage(message: "same", stacktrace: "stack")
                clock.advance(59.999)
                await repository.sendErrorMessage(message: "same", stacktrace: "stack")
                #expect(RateLimitReportProtocol.requests.values.count == 1)
                clock.advance(1.001)
                await repository.sendErrorMessage(message: "same", stacktrace: "stack")
                #expect(RateLimitReportProtocol.requests.values.count == 2)
            }
        }

        @Test func budgetIsRollingAndRejectedReportsAreNotRemembered() async throws {
            let clock = ReportClock()
            try await withRepository(limiter: ErrorReportLimiter(now: { clock.value })) { repository in
                for index in 0..<5 {
                    await repository.sendErrorMessage(message: "first-\(index)", stacktrace: "")
                }
                clock.advance(30)
                for index in 0..<5 {
                    await repository.sendErrorMessage(message: "second-\(index)", stacktrace: "")
                }
                clock.advance(29)
                await repository.sendErrorMessage(message: "rejected", stacktrace: "")
                #expect(RateLimitReportProtocol.requests.values.count == 10)
                clock.advance(1)
                await repository.sendErrorMessage(message: "rejected", stacktrace: "")
                for index in 0..<5 {
                    await repository.sendErrorMessage(message: "third-\(index)", stacktrace: "")
                }
                #expect(RateLimitReportProtocol.requests.values.count == 15)
            }
        }

        @Test func duplicatesDoNotConsumeBudgetAndStackParticipatesInIdentity() async throws {
            try await withRepository { repository in
                for _ in 0..<12 { await repository.sendErrorMessage(message: "same", stacktrace: "stack") }
                for index in 0..<9 {
                    await repository.sendErrorMessage(message: "same", stacktrace: "stack-\(index)")
                }
                #expect(RateLimitReportProtocol.requests.values.count == 10)
            }
        }

        @Test func concurrentDistinctReportsCannotOverspendBudget() async throws {
            try await withRepository { repository in
                await withTaskGroup(of: Void.self) { group in
                    for index in 0..<100 {
                        group.addTask { await repository.sendErrorMessage(message: "failure-\(index)", stacktrace: "") }
                    }
                }
                #expect(RateLimitReportProtocol.requests.values.count == 10)
            }
        }

        @Test func failuresStillConsumeBudget() async throws {
            let clock = ReportClock()
            try await withRepository(limiter: ErrorReportLimiter(now: { clock.value })) { repository in
                RateLimitReportProtocol.setStatuses(Array(repeating: 500, count: 10))
                for _ in 0..<12 { await repository.sendErrorMessage(message: "retry", stacktrace: "") }
                #expect(RateLimitReportProtocol.requests.values.count == 10)
                clock.advance(61)
                await repository.sendErrorMessage(message: "retry", stacktrace: "")
                #expect(RateLimitReportProtocol.requests.values.count == 11)
            }
        }

        @Test func budgetRejectionPrecedesDeviceLookup() async throws {
            try await withRepository(limiter: ErrorReportLimiter(limit: 0)) { repository in
                let saved = UserDefaults.standard.object(forKey: "gravity_device_id")
                defer { UserDefaults.standard.set(saved, forKey: "gravity_device_id") }
                try repository.sessionManager.resetUser()
                UserDefaults.standard.set(42, forKey: "gravity_device_id")
                await repository.sendErrorMessage(message: "blocked", stacktrace: "")
                #expect(UserDefaults.standard.object(forKey: "gravity_device_id") as? Int == 42)
                #expect(RateLimitReportProtocol.requests.values.isEmpty)
                // Positive control: an admitted report performs the device fallback.
                let config = URLSessionConfiguration.ephemeral
                config.protocolClasses = [RateLimitReportProtocol.self]
                let session = URLSession(configuration: config)
                defer { session.invalidateAndCancel() }
                let admitted = GravityRepository(urlSession: session)
                await admitted.sendErrorMessage(message: "admitted", stacktrace: "")
                #expect(UserDefaults.standard.object(forKey: "gravity_device_id") as? Int == nil)
            }
        }

        @Test func deduplicationPrecedesDeviceLookup() async throws {
            try await withRepository { repository in
                let saved = UserDefaults.standard.object(forKey: "gravity_device_id")
                defer { UserDefaults.standard.set(saved, forKey: "gravity_device_id") }
                try repository.sessionManager.resetUser()
                await repository.sendErrorMessage(message: "same", stacktrace: "stack")
                UserDefaults.standard.set(42, forKey: "gravity_device_id")
                await repository.sendErrorMessage(message: "same", stacktrace: "stack")
                #expect(UserDefaults.standard.object(forKey: "gravity_device_id") as? Int == 42)
                #expect(RateLimitReportProtocol.requests.values.count == 1)
            }
        }

        @Test func sanitizedMessageAndStackDetermineDuplicateIdentity() async throws {
            try await withRepository { repository in
                await repository.sendErrorMessage(message: "GET https://u:ONE@host/p?id=1", stacktrace: "see https://host/stack?token=1")
                await repository.sendErrorMessage(message: "GET https://v:TWO@host/p?id=2", stacktrace: "see https://host/stack?token=2")
                #expect(RateLimitReportProtocol.requests.values.count == 1)
                await repository.sendErrorMessage(message: "GET https://host/other?id=3", stacktrace: "see https://host/stack?token=3")
                #expect(RateLimitReportProtocol.requests.values.count == 2, "Different sanitized endpoints remain distinct")
            }
        }

        @Test func dynamicUrlErrorsBecomeStableBeforeReportingAndDeduplication() async throws {
            let fixture = TemporarySDKFixture()
            fixture.initialize()
            RateLimitReportProtocol.reset()
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [RateLimitReportProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let repository = CompletedReportRepository(urlSession: session)
            for id in ["first-request", "second-request"] {
                let error = URLError(.notConnectedToInternet, userInfo: [
                    NSLocalizedDescriptionKey: "LocalDataTask <\(id)>.<1> failed",
                    NSURLErrorFailingURLStringErrorKey: "https://u:SECRET@host/p?token=\(id)"
                ])
                GravityLogger.e("Transport", "failure", error, repository: repository)
            }
            let completed = await repository.completed.waitFor(2)
            #expect(completed.count == 2)
            let requests = RateLimitReportProtocol.requests.values
            #expect(requests.count == 1)
            let body = try #require(requests.first?.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let stack = try #require(json["stacktrace"] as? String)
            #expect(stack.contains("-1009"))
            #expect(stack.contains("https://host/p"))
            for secret in ["SECRET", "LocalDataTask", "first-request", "second-request", "token="] {
                #expect(!stack.contains(secret))
            }
            withExtendedLifetime(fixture) {}
        }

        @Test func identicalReportsAreSentOnlyOnce() async throws {
            try await withRepository { repository in
                await repository.sendErrorMessage(message: "same", stacktrace: "stack")
                await repository.sendErrorMessage(message: "same", stacktrace: "stack")
                #expect(RateLimitReportProtocol.requests.values.count == 1)
            }
        }

        @Test func twelveDistinctReportsSpendOnlyTenSlots() async throws {
            try await withRepository { repository in
                for index in 0..<12 {
                    await repository.sendErrorMessage(message: "failure-\(index)", stacktrace: "stack")
                }
                #expect(RateLimitReportProtocol.requests.values.count == 10)
            }
        }

        @Test func failedSendCanRetryButSuccessfulRetryIsDeduplicated() async throws {
            try await withRepository { repository in
                RateLimitReportProtocol.setStatuses([500, 200])
                await repository.sendErrorMessage(message: "retry", stacktrace: "stack")
                await repository.sendErrorMessage(message: "retry", stacktrace: "stack")
                await repository.sendErrorMessage(message: "retry", stacktrace: "stack")
                #expect(RateLimitReportProtocol.requests.values.count == 2)
            }
        }

        @Test func transportFailureAlsoAllowsRetry() async throws {
            try await withRepository { repository in
                RateLimitReportProtocol.setStatuses([-1009, 200])
                await repository.sendErrorMessage(message: "offline", stacktrace: "stack")
                await repository.sendErrorMessage(message: "offline", stacktrace: "stack")
                await repository.sendErrorMessage(message: "offline", stacktrace: "stack")
                #expect(RateLimitReportProtocol.requests.values.count == 2)
            }
        }

        @Test func messageAndStackBoundariesCannotCollide() async throws {
            try await withRepository { repository in
                await repository.sendErrorMessage(message: "a", stacktrace: "bc")
                await repository.sendErrorMessage(message: "ab", stacktrace: "c")
                await repository.sendErrorMessage(message: "a\0", stacktrace: "b")
                await repository.sendErrorMessage(message: "a", stacktrace: "\0b")
                #expect(RateLimitReportProtocol.requests.values.count == 4)
            }
        }

        @Test func concurrentDuplicatesShareAnInflightReservation() async throws {
            try await withRepository { repository in
                RateLimitReportProtocol.holdNext()
                let first = Task { await repository.sendErrorMessage(message: "same", stacktrace: "stack") }
                _ = await RateLimitReportProtocol.requests.waitFor(1)
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<20 {
                        group.addTask { await repository.sendErrorMessage(message: "same", stacktrace: "stack") }
                    }
                }
                RateLimitReportProtocol.releaseHeld()
                await first.value
                #expect(RateLimitReportProtocol.requests.values.count == 1)
            }
        }
    }
}

private final class RateLimitReportProtocol: URLProtocol, @unchecked Sendable {
    static let requests = TestRequestRecorder<URLRequest>()
    private static let lock = NSLock()
    private static var statuses: [Int] = []
    private static var shouldHold = false
    private static var held: RateLimitReportProtocol?

    static func reset() {
        lock.lock(); statuses = []; shouldHold = false; lock.unlock()
        requests.reset()
    }
    static func setStatuses(_ values: [Int]) { lock.lock(); statuses = values; lock.unlock() }
    static func holdNext() { lock.lock(); shouldHold = true; lock.unlock() }
    static func releaseHeld() {
        lock.lock(); let pending = held; held = nil; lock.unlock()
        pending?.respond(200)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let hold = Self.shouldHold
        Self.shouldHold = false
        let status = Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
        if hold { Self.held = self }
        Self.lock.unlock()
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            captured.httpBody = data
        }
        Self.requests.append(captured)
        if !hold { respond(status) }
    }
    private func respond(_ status: Int) {
        if status < 0 {
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: status)))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class ReportClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    var value: TimeInterval { lock.lock(); defer { lock.unlock() }; return time }
    func advance(_ seconds: TimeInterval) { lock.lock(); time += seconds; lock.unlock() }
}

/// Observe completion of logger-created tasks without sleeps or production hooks.
private final class CompletedReportRepository: GravityRepository {
    let completed = TestRequestRecorder<Void>()
    override func sendErrorMessage(message: String, stacktrace: String) async {
        await super.sendErrorMessage(message: message, stacktrace: stacktrace)
        completed.append(())
    }
}
