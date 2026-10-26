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

    func testVisibleOfflineReservationDoesNotExpireOnNavigation() throws {
        var time: TimeInterval = 0
        let gate = InAppPresentationGate(now: { time })
        let request = gate.beginRequest(location: "home", newScreen: true)
        let reservation = try XCTUnwrap(gate.reserve(campaignId: "c", request: request))
        XCTAssertTrue(gate.present(reservation, contentIds: ["event"]) { true })
        gate.visible(contentId: "event", durable: true)
        gate.closed(contentId: "event")
        time = 3600
        let next = gate.beginRequest(location: "next", newScreen: true)
        XCTAssertNil(gate.reserve(campaignId: "c", request: next))
    }

    func testReloadedQueueAcknowledgementFencesStaleRequestsButAllowsFreshViews() throws {
        let gate = InAppPresentationGate()
        var pending = true
        gate.deliveryScope = { "A" }
        gate.deliveryPending = { _ in pending }
        let stale = gate.beginRequest(location: "home", newScreen: true)
        XCTAssertNil(gate.reserve(campaignId: "c", request: stale))
        gate.acknowledgeDelivery(scope: "B", campaignId: "c", contentId: "old")
        XCTAssertNil(gate.reserve(campaignId: "c", request: stale))
        gate.acknowledgeDelivery(scope: "A", campaignId: "c", contentId: "old")
        pending = false
        XCTAssertNil(gate.reserve(campaignId: "c", request: stale))
        let fresh = gate.beginRequest(location: "home", newScreen: false)
        XCTAssertNotNil(gate.reserve(campaignId: "c", request: fresh))
    }

    func testQueueArrivingAfterReservationCannotPresentAndOldUserAckCannotUnlock() throws {
        let gate = InAppPresentationGate()
        gate.deliveryScope = { "B" }
        let request = gate.beginRequest(location: "home", newScreen: true)
        let reservation = try XCTUnwrap(gate.reserve(campaignId: "c", request: request))
        gate.deliveryPending = { _ in true }
        var shown = false
        XCTAssertFalse(gate.present(reservation, contentIds: ["event"]) { shown = true; return true })
        XCTAssertFalse(shown)
        gate.deliveryPending = { _ in false }
        XCTAssertTrue(gate.present(reservation, contentIds: ["event"]) { true })
        gate.acknowledgeDelivery(scope: "A", campaignId: "c", contentId: "event")
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

final class ModalVisibleImpressionTests: XCTestCase {
    func testFastExplicitCloseAndStepSignalsFireOnce() async throws {
        for milliseconds in [100, 200, 400] {
            var events = 0
            let opening = ModalImpressionSession(confirm: { events += 1; return true }, release: {})
            opening.confirmFrame(isActive: true)
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
            let presentation = InAppPresentation(willClose: { opening.explicitClose(isActive: true) },
                performDismiss: { complete in
                    XCTAssertEqual(events, 1) // WRIMP precedes physical dismissal.
                    complete(true)
                }, didDismiss: { _ in })
            presentation.close()
            opening.confirmFrame(isActive: true) // next OPEN_STEP shares the opening
            opening.explicitClose(isActive: true)
            XCTAssertEqual(events, 1)
        }
    }

    func testCloseRetriesUnpersistedImpressionOnlyAfterAnActualFrame() {
        var attempts = 0
        var events = 0
        let opening = ModalImpressionSession(confirm: {
            attempts += 1
            guard attempts > 1 else { return false }
            events += 1
            return true
        }, release: {})
        opening.explicitClose(isActive: true)
        XCTAssertEqual(attempts, 0)
        opening.confirmFrame(isActive: true)
        XCTAssertEqual(events, 0)
        opening.explicitClose(isActive: false)
        XCTAssertEqual(attempts, 1)
        opening.explicitClose(isActive: true)
        opening.confirmFrame(isActive: true)
        XCTAssertEqual(events, 1)
        XCTAssertEqual(attempts, 2)
    }

    func testUnappearedAndInactiveDisposalReleasesWithoutImpression() {
        var events = 0
        var releases = 0
        let opening = ModalImpressionSession(confirm: { events += 1; return true }, release: { releases += 1 })
        opening.confirmFrame(isActive: false)
        opening.explicitClose(isActive: true)
        opening.disappeared()
        XCTAssertEqual(events, 0)
        XCTAssertEqual(releases, 1)
    }

    func testConcurrentDetectorAndCloseUseOneAtomicFlag() {
        var events = 0
        let opening = ModalImpressionSession(confirm: { events += 1; return true }, release: {})
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            opening.confirmFrame(isActive: true)
            opening.explicitClose(isActive: true)
        }
        XCTAssertTrue(opening.hasFired)
        XCTAssertEqual(events, 1)
    }
}

final class DurableVisibleImpressionTests: XCTestCase {
    private func temporaryStore() -> (URL, VisibleImpressionStore) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("wrimp.json")
        return (url, VisibleImpressionStore(fileURL: url))
    }

    func testOfflineCloseReloadRestoreAndUserSectionIsolation() async throws {
        let (url, store) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let event = VisibleImpressionStore.Entry(id: UUID(), scope: "section-A/user-A", campaignId: "campaign",
                                                 contentId: "original", urls: ["https://tracking.test/original?user=A"], user: "user-A")
        try store.insert(event)
        let gate = InAppPresentationGate()
        gate.deliveryPending = { store.contains(scope: "section-A/user-A", campaignId: $0) }
        let request = gate.beginRequest(location: "next", newScreen: true)
        XCTAssertNil(gate.reserve(campaignId: "campaign", request: request))
        let counter = AttemptCounter()
        let delivery = VisibleImpressionDelivery(send: { value in
            XCTAssertEqual(value, "https://tracking.test/original?user=A")
            _ = await counter.next(value)
            throw DeliveryFailure.transient
        }, sleep: { _ in }, store: store)
        await delivery.resumePending()
        XCTAssertTrue(store.contains(scope: "section-A/user-A", campaignId: "campaign"))
        let reloaded = VisibleImpressionStore(fileURL: url)
        XCTAssertEqual(reloaded.entries.first?.user, "user-A")
        XCTAssertFalse(reloaded.contains(scope: "section-A/user-B", campaignId: "campaign"))
        XCTAssertFalse(reloaded.contains(scope: "section-B/user-A", campaignId: "campaign"))
        let restored = VisibleImpressionDelivery(send: { value in
            XCTAssertEqual(value, "https://tracking.test/original?user=A")
        }, store: reloaded)
        await restored.resumePending()
        XCTAssertTrue(reloaded.entries.isEmpty)
        let afterRestart = VisibleImpressionStore(fileURL: url)
        XCTAssertTrue(afterRestart.entries.isEmpty)
    }

    func testQueuedEventWaitsForSdkStartAndThenDeliversOnce() async throws {
        let (url, store) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try store.insert(.init(id: UUID(), scope: "A", campaignId: "c", contentId: "event", urls: ["pending"], user: "A"))
        let counter = AttemptCounter()
        let delivery = VisibleImpressionDelivery(send: { _ = await counter.next($0) }, store: store, startsSuspended: true)
        await delivery.resumePending()
        let beforeStart = await counter.count("pending")
        XCTAssertEqual(beforeStart, 0)
        XCTAssertTrue(store.contains(scope: "A", campaignId: "c"))
        await delivery.start()
        let afterStart = await counter.count("pending")
        XCTAssertEqual(afterStart, 1)
        XCTAssertTrue(store.entries.isEmpty)
        await delivery.stop()
    }

    func testFreshOpeningCanReuseUrlAfterAcknowledgement() async throws {
        let (url, store) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let counter = AttemptCounter()
        let delivery = VisibleImpressionDelivery(send: { _ = await counter.next($0) }, store: store)
        for _ in 0..<2 {
            try store.insert(.init(id: UUID(), scope: "A", campaignId: "c", contentId: "event", urls: ["same"], user: "A"))
            await delivery.resumePending()
            XCTAssertTrue(store.entries.isEmpty)
        }
        let count = await counter.count("same")
        XCTAssertEqual(count, 2)
    }

    func testPermanentRejectionIsPreservedWithoutAutomaticResend() async throws {
        let (url, store) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try store.insert(.init(id: UUID(), scope: "A", campaignId: "c", contentId: "event", urls: ["bad"], user: "A"))
        let counter = AttemptCounter()
        let delivery = VisibleImpressionDelivery(send: { value in
            _ = await counter.next(value)
            throw DeliveryFailure.permanent
        }, retryable: { _ in false }, store: store)
        await delivery.resumePending()
        await delivery.resumePending()
        let count = await counter.count("bad")
        XCTAssertEqual(count, 1)
        let reload = VisibleImpressionStore(fileURL: url)
        XCTAssertEqual(reload.entries.first?.rejectedUrls, ["bad"])
        XCTAssertTrue(reload.contains(scope: "A", campaignId: "c"))
    }

    func testPersistencePrecedesSendAndSuccessfulUrlsAreRemoved() async throws {
        let (url, store) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let event = VisibleImpressionStore.Entry(id: UUID(), scope: "A", campaignId: "c", contentId: "event", urls: ["first", "second"], user: "A")
        try store.insert(event)
        let delivery = VisibleImpressionDelivery(send: { value in
            let disk = VisibleImpressionStore(fileURL: url)
            XCTAssertTrue(disk.entries.contains { $0.urls.contains(value) })
            if value == "second" { throw DeliveryFailure.permanent }
        }, retryable: { _ in false }, store: store)
        await delivery.resumePending()
        XCTAssertEqual(store.entries.first?.urls, ["second"])
    }
}
