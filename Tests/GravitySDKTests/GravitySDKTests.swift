import Foundation
#if !CORE_TEST_HARNESS
import XCTest
@testable import GravitySDK
#endif

final class InAppPresentationGateTests: XCTestCase {
    func testConcurrentChooseReservesCampaignOnce() {
        let gate = InAppPresentationGate()
        let request = gate.beginRequest(location: "home", newScreen: true)
        let lock = NSLock()
        var winners = 0
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            if gate.reserve(campaignId: "campaign", request: request) != nil {
                lock.lock(); winners += 1; lock.unlock()
            }
        }
        XCTAssertEqual(winners, 1)
    }

    func testVisibleCloseKeepsReservationUntilAcknowledgementAndRejectsStaleResponse() throws {
        let gate = InAppPresentationGate()
        let first = gate.beginRequest(location: "home", newScreen: true)
        let reservation = try XCTUnwrap(gate.reserve(campaignId: "campaign", request: first))
        XCTAssertTrue(gate.present(reservation, contentIds: ["step1:event1", "step2:event1"]) { true })
        gate.visible(contentId: "step1:event1")
        gate.closed(contentId: "step1:event1")
        let inFlight = gate.beginRequest(location: "next", newScreen: true)
        XCTAssertNil(gate.reserve(campaignId: "campaign", request: inFlight))
        gate.acknowledged(contentId: "step2:event1")
        XCTAssertNil(gate.reserve(campaignId: "campaign", request: inFlight))
        let fresh = gate.beginRequest(location: "next", newScreen: false)
        XCTAssertNotNil(gate.reserve(campaignId: "campaign", request: fresh))
    }

    func testFailedPresentationAndCloseBeforeVisibilityReleaseCampaign() throws {
        let gate = InAppPresentationGate()
        let request = gate.beginRequest(location: "home", newScreen: true)
        let first = try XCTUnwrap(gate.reserve(campaignId: "c", request: request))
        XCTAssertFalse(gate.present(first, contentIds: ["c:e1"]) { false })
        let second = try XCTUnwrap(gate.reserve(campaignId: "c", request: request))
        XCTAssertTrue(gate.present(second, contentIds: ["c:e2"]) { true })
        gate.closed(contentId: "c:e2")
        XCTAssertNotNil(gate.reserve(campaignId: "c", request: request))
    }

    func testScreenChangeReleasesDelayedChooseAndOldCancellationCannotReleaseNewOwner() throws {
        let gate = InAppPresentationGate()
        let first = gate.beginRequest(location: "home", newScreen: true)
        let old = try XCTUnwrap(gate.reserve(campaignId: "c", request: first))
        let second = gate.beginRequest(location: "next", newScreen: true)
        XCTAssertFalse(gate.isCurrent(first))
        let current = try XCTUnwrap(gate.reserve(campaignId: "c", request: second))
        gate.cancel(old)
        var presented = false
        XCTAssertFalse(gate.present(old, contentIds: ["old"]) { presented = true; return true })
        XCTAssertFalse(presented)
        XCTAssertTrue(gate.present(current, contentIds: ["new"]) { true })
        XCTAssertNil(gate.reserve(campaignId: "c", request: second))
    }

    func testIdentityResetInvalidatesOldRequestAndLateAcknowledgement() throws {
        let gate = InAppPresentationGate()
        let oldRequest = gate.beginRequest(location: "home", newScreen: true)
        let old = try XCTUnwrap(gate.reserve(campaignId: "c", request: oldRequest))
        XCTAssertTrue(gate.present(old, contentIds: ["old:event"]) { true })
        gate.reset()
        let request = gate.beginRequest(location: "home", newScreen: true)
        let current = try XCTUnwrap(gate.reserve(campaignId: "c", request: request))
        XCTAssertTrue(gate.present(current, contentIds: ["new:event"]) { true })
        gate.acknowledged(contentId: "old:event")
        XCTAssertFalse(gate.isCurrent(oldRequest))
        XCTAssertNil(gate.reserve(campaignId: "c", request: request))
    }

    func testMissingAcknowledgementExpiresAndCampaignsAreIndependent() throws {
        var time: TimeInterval = 0
        let gate = InAppPresentationGate(now: { time })
        let request = gate.beginRequest(location: "home", newScreen: true)
        let first = try XCTUnwrap(gate.reserve(campaignId: "c", request: request))
        XCTAssertTrue(gate.present(first, contentIds: ["c:event"]) { true })
        XCTAssertNotNil(gate.reserve(campaignId: "other", request: request))
        time = 59
        XCTAssertNil(gate.reserve(campaignId: "c", request: request))
        time = 60
        XCTAssertNotNil(gate.reserve(campaignId: "c", request: request))
    }
}

private actor AttemptCounter {
    var values: [String: Int] = [:]
    func next(_ url: String) -> Int { values[url, default: 0] += 1; return values[url]! }
    func count(_ url: String) -> Int { values[url, default: 0] }
}
private enum DeliveryFailure: Error { case transient, permanent }

final class VisibleImpressionDeliveryTests: XCTestCase {
    func testConcurrentCallbacksShareDeliveryAndSuccessIsNotResent() async {
        let counter = AttemptCounter()
        let delivery = VisibleImpressionDelivery(send: { url in
            _ = await counter.next(url)
            try await Task.sleep(nanoseconds: 10_000_000)
        })
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<30 { group.addTask { await delivery.deliver(urls: ["event", "event"]) } }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        XCTAssertTrue(results.allSatisfy { $0 })
        let repeatResult = await delivery.deliver(urls: ["event"])
        XCTAssertTrue(repeatResult)
        let count = await counter.count("event")
        XCTAssertEqual(count, 1)
    }

    func testTransientErrorsRetryThreeTimesBeforeSuccess() async {
        let counter = AttemptCounter()
        let delivery = VisibleImpressionDelivery(send: { url in
            if await counter.next(url) < 3 { throw DeliveryFailure.transient }
        }, sleep: { _ in })
        let success = await delivery.deliver(urls: ["event"])
        let count = await counter.count("event")
        XCTAssertTrue(success)
        XCTAssertEqual(count, 3)
    }

    func testPartialFailureDoesNotResendSuccessfulUrlsAndDoesNotCacheFailure() async {
        let counter = AttemptCounter()
        let delivery = VisibleImpressionDelivery(send: { url in
            let count = await counter.next(url)
            if url == "bad" && count <= 3 { throw DeliveryFailure.transient }
        }, sleep: { _ in })
        let first = await delivery.deliver(urls: ["good", "bad"])
        let second = await delivery.deliver(urls: ["good", "bad"])
        let good = await counter.count("good")
        let bad = await counter.count("bad")
        XCTAssertFalse(first)
        XCTAssertTrue(second)
        XCTAssertEqual(good, 1)
        XCTAssertEqual(bad, 4)
    }

    func testPermanentErrorAndEmptyUrlsCannotAcknowledge() async {
        let counter = AttemptCounter()
        let delivery = VisibleImpressionDelivery(send: { url in
            _ = await counter.next(url); throw DeliveryFailure.permanent
        }, retryable: { _ in false }, sleep: { _ in XCTFail("Permanent failure must not retry") })
        let result = await delivery.deliver(urls: ["bad"])
        let empty = await delivery.deliver(urls: [])
        let count = await counter.count("bad")
        XCTAssertFalse(result)
        XCTAssertFalse(empty)
        XCTAssertEqual(count, 1)
    }

    func testCancelledTransportDoesNotCacheSuccess() async {
        let counter = AttemptCounter()
        let delivery = VisibleImpressionDelivery(send: { url in
            if await counter.next(url) == 1 { throw CancellationError() }
        }, sleep: { _ in })
        let first = await delivery.deliver(urls: ["event"])
        let second = await delivery.deliver(urls: ["event"])
        XCTAssertFalse(first)
        XCTAssertTrue(second)
    }
}

private final class EngagementURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var statuses: [Int] = []
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let status = Self.statuses.removeFirst()
        Self.requests.append(request)
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class EngagementTransportTests: XCTestCase {
    private func transport(statuses: [Int]) -> EngagementTransport {
        EngagementURLProtocol.statuses = statuses
        EngagementURLProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EngagementURLProtocol.self]
        return EngagementTransport(session: URLSession(configuration: config))
    }

    func testActualHttpTransportRetries500And429AndAccepts204() async {
        let transport = transport(statuses: [500, 429, 204])
        let delivery = VisibleImpressionDelivery(send: { try await transport.send(url: $0, headers: ["Authorization": "Bearer test-key"]) },
                                                retryable: EngagementTransport.isRetryable, sleep: { _ in })
        let success = await delivery.deliver(urls: ["https://tracking.test/engagement?event=WRIMP"])
        XCTAssertTrue(success)
        XCTAssertEqual(EngagementURLProtocol.requests.count, 3)
        XCTAssertEqual(EngagementURLProtocol.requests.first?.httpMethod, "GET")
        XCTAssertEqual(EngagementURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testActualHttp400CannotAcknowledgeOrRetry() async {
        let transport = transport(statuses: [400])
        let delivery = VisibleImpressionDelivery(send: { try await transport.send(url: $0) },
                                                retryable: EngagementTransport.isRetryable, sleep: { _ in XCTFail("400 must not retry") })
        let success = await delivery.deliver(urls: ["https://tracking.test/engagement"])
        XCTAssertFalse(success)
        XCTAssertEqual(EngagementURLProtocol.requests.count, 1)
    }

    func testMalformedUrlCannotAcknowledge() async {
        let transport = transport(statuses: [])
        let delivery = VisibleImpressionDelivery(send: { try await transport.send(url: $0) },
                                                retryable: EngagementTransport.isRetryable, sleep: { _ in XCTFail("Invalid URL must not retry") })
        let success = await delivery.deliver(urls: ["relative-path"])
        XCTAssertFalse(success)
        XCTAssertTrue(EngagementURLProtocol.requests.isEmpty)
    }
}
