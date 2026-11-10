import XCTest
import UIKit
@testable import GravitySDK

final class CampaignDelayTests: XCTestCase {
    func testCampaignDelayNanosecondsSkipsNonpositiveAndSaturatesOverflow() {
        let cases: [(Int?, UInt64?)] = [
            (nil, nil), (-1, nil), (Int.min, nil), (0, nil),
            (1, 1_000_000), (1500, 1_500_000_000),
            (9_223_372_036_854, 9_223_372_036_854_000_000),
            (9_223_372_036_855, UInt64(Int64.max)),
            (18_446_744_073_709, UInt64(Int64.max)),
            (18_446_744_073_710, UInt64(Int64.max)), (Int.max, UInt64(Int64.max))
        ]
        for (milliseconds, expected) in cases {
            XCTAssertEqual(campaignDelayNanoseconds(milliseconds), expected,
                           "delayTime: \(String(describing: milliseconds))")
        }
    }

    @MainActor func testPositiveAutomaticDelayWaitsBeforePresenting() async throws {
        for event in [false, true] {
            try await withAutomaticCampaign(delay: 400, event: event) { sdk, server, host, task in
                let requests = await server.waitFor(2)
                XCTAssertEqual(requests.filter { $0.path == "/choose" }.count, 1)
                try await Task.sleep(nanoseconds: 200_000_000)
                XCTAssertNil(host.presentedViewController, "Must not present halfway through the campaign delay")
                let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    host.presentedViewController != nil
                }, object: host)
                await fulfillment(of: [appeared], timeout: 4)
                await task.value
                XCTAssertNotNil(host.presentedViewController)
            }
        }
    }

    @MainActor func testCappedAutomaticDelayHoldsReservationUntilCancellation() async throws {
        for event in [false, true] {
            for delay: Any in [Int.max, "1e400"] {
                try await withAutomaticCampaign(delay: delay, event: event) { sdk, server, host, task in
                    let requests = await server.waitFor(2)
                    XCTAssertEqual(requests.filter { $0.path == "/choose" }.count, 1)
                    try await Task.sleep(nanoseconds: 200_000_000)
                    XCTAssertNil(host.presentedViewController, "\(delay) must remain asleep")
                    let request = sdk.presentationGate.beginRequest(location: "/campaign-delay", newScreen: false)
                    let held = sdk.presentationGate.reserve(campaignId: "delayed", request: request)
                    XCTAssertNil(held, "The sleeping task must hold its reservation")
                    if let held { sdk.presentationGate.cancel(held) }
                    let finished = expectation(description: "Cancelled sleep finishes promptly")
                    Task { await task.value; finished.fulfill() }
                    let cancelledAt = ProcessInfo.processInfo.systemUptime
                    task.cancel()
                    await fulfillment(of: [finished], timeout: 0.9)
                    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - cancelledAt, 1)
                    XCTAssertNil(host.presentedViewController)
                    let released = sdk.presentationGate.reserve(campaignId: "delayed", request: request)
                    XCTAssertNotNil(released, "Cancellation releases the sleeping task's reservation")
                    if let released { sdk.presentationGate.cancel(released) }
                }
            }
        }
    }

    @MainActor func testInvalidatedCappedAutomaticDelaysFinishAndReleaseReservations() async throws {
        for event in [false, true] {
            for invalidation in ["lock", "screen", "reset", "user"] {
                try await withAutomaticCampaign(delay: Int.max, event: event) { sdk, server, host, task in
                    let unexpectedError = expectation(description: "Invalidation is not an error")
                    unexpectedError.isInverted = true
                    sdk.setLogListener { level, _ in
                        if level == .error { unexpectedError.fulfill() }
                    }
                    defer { sdk.setLogListener(nil) }
                    let requests = await server.waitFor(2)
                    XCTAssertEqual(requests.filter { $0.path == "/choose" }.count, 1)
                    try await Task.sleep(nanoseconds: 200_000_000)
                    XCTAssertNil(host.presentedViewController)
                    let current = sdk.presentationGate.beginRequest(location: "/campaign-delay", newScreen: false)
                    let held = sdk.presentationGate.reserve(campaignId: "delayed", request: current)
                    XCTAssertNil(held)
                    if let held { sdk.presentationGate.cancel(held) }
                    let finished = expectation(description: "\(invalidation) ends the delayed task")
                    Task { await task.value; finished.fulfill() }
                    let invalidatedAt = ProcessInfo.processInfo.systemUptime
                    switch invalidation {
                    case "lock": sdk.lockPresentation()
                    case "reset": try await sdk.resetUser()
                    case "user": sdk.setUser(userId: "replacement", sessionId: "new-session")
                    default:
                        server.reset()
                        let next = try XCTUnwrap(sdk.trackViewTask(pageContext: PageContext(
                            type: .other, data: [], location: "/replacement"), viewController: host))
                        await next.value
                    }
                    await fulfillment(of: [finished], timeout: 0.9)
                    XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - invalidatedAt, 1)
                    XCTAssertNil(host.presentedViewController)
                    let request = sdk.presentationGate.beginRequest(
                        location: invalidation == "screen" ? "/replacement" : "/campaign-delay", newScreen: false)
                    let released = sdk.presentationGate.reserve(campaignId: "delayed", request: request)
                    XCTAssertNotNil(released, "\(invalidation) must release the reservation")
                    if let released { sdk.presentationGate.cancel(released) }
                    await fulfillment(of: [unexpectedError], timeout: 0.05)
                }
            }
        }
    }

    @MainActor func testInvalidatedCappedDelayReleasesItsTargetViewController() async throws {
        try await checkDelayedHostRelease(invalidate: true)
    }

    @MainActor func testDeallocatedHostEndsDelayWithoutOtherInvalidation() async throws {
        try await checkDelayedHostRelease(invalidate: false)
    }

    @MainActor private func checkDelayedHostRelease(invalidate: Bool) async throws {
        let fixture = TemporarySDKFixture(apiKey: "weak-delay", section: "weak-delay")
        let sdk = fixture.initialize()
        sdk.setUser(userId: "weak-delay-user", sessionId: "session")
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        server.reset(campaigns: [["campaignId": "weak", "delayTime": Int.max]], content: [["payload": [[
            "campaignId": "weak", "experienceId": "e", "variationId": "v", "decisionId": "d",
            "contents": [["contentId": "weak-content", "deliveryMethod": "modal", "contentType": "test",
                          "variables": ["elements": [["type": "text", "text": "Weak host"]]]]]
        ]]]])
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let window = UIWindow(frame: UIScreen.main.bounds)
        var host: UIViewController? = UIViewController()
        weak var weakHost = host
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let task = try XCTUnwrap(sdk.trackViewTask(pageContext: PageContext(
            type: .other, data: [], location: "/weak-delay"), viewController: host))
        defer { task.cancel() }
        let requests = await server.waitFor(2)
        XCTAssertEqual(requests.filter { $0.path == "/choose" }.count, 1)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(host?.presentedViewController)
        let request = sdk.presentationGate.beginRequest(location: "/weak-delay", newScreen: false)
        let held = sdk.presentationGate.reserve(campaignId: "weak", request: request)
        XCTAssertNil(held, "The delayed task must hold its reservation before host release")
        if let held { sdk.presentationGate.cancel(held) }
        let finished = expectation(description: "Host release ends the delayed task")
        Task { await task.value; finished.fulfill() }
        if invalidate { sdk.lockPresentation() }
        window.isHidden = true
        window.rootViewController = nil
        host = nil
        let releasedAt = ProcessInfo.processInfo.systemUptime
        await fulfillment(of: [finished], timeout: 0.9)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - releasedAt, 1)
        XCTAssertNil(weakHost, "Host deallocation alone must end the wait without retaining the controller")
        let released = sdk.presentationGate.reserve(campaignId: "weak", request: request)
        XCTAssertNotNil(released, "Host release must free the delayed reservation")
        if let released { sdk.presentationGate.cancel(released) }
    }

    @MainActor func testClockPastDeadlineEndsWaitAfterOneChunk() async throws {
        for event in [false, true] {
            for start in [UInt64(1_000_000_000), UInt64.max - 50_000_000] {
                let clock = JumpingCampaignDelayClock(start: start)
                let timing = CampaignDelayTiming(now: { clock.now }, sleep: { clock.sleep($0) })
                try await withAutomaticCampaign(delay: 400, event: event, timing: timing) { _, _, host, task in
                    await task.value
                    XCTAssertNotNil(host.presentedViewController)
                    XCTAssertEqual(clock.intervals, [start == 1_000_000_000 ? 100_000_000 : 50_000_000],
                        "A clock jump past the deadline must not leave a sum of unslept chunks")
                }
            }
        }
    }

    @MainActor private func withAutomaticCampaign(
        delay: Any, event: Bool, timing: CampaignDelayTiming? = nil,
        _ body: (GravitySDK, RecordingServer, UIViewController, Task<Void, Never>) async throws -> Void
    ) async throws {
        let savedUID = UserDefaults.standard.string(forKey: "gravity_user_id")
        defer { UserDefaults.standard.set(savedUID, forKey: "gravity_user_id") }
        let fixture = TemporarySDKFixture(apiKey: "campaign-delay", section: "campaign-delay")
        let sdk = fixture.initialize()
        if let timing { sdk.campaignDelayTiming = timing }
        sdk.setUser(userId: "delay-user", sessionId: "session")
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        server.reset(campaigns: [["campaignId": "delayed", "delayTime": delay]], content: [["payload": [[
            "campaignId": "delayed", "experienceId": "e", "variationId": "v", "decisionId": "d",
            "contents": [["contentId": "delayed-content", "deliveryMethod": "modal", "contentType": "test",
                          "variables": ["elements": [["type": "text", "text": "Delayed content"]]]]]
        ]]]])
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
        let page = PageContext(type: .other, data: [], location: "/campaign-delay")
        let task = try XCTUnwrap(event
            ? sdk.triggerEventTask(events: [], pageContext: page, viewController: host)
            : sdk.trackViewTask(pageContext: page, viewController: host))
        defer { task.cancel() }
        try await body(sdk, server, host, task)
    }

    @MainActor func testNegativeIntegerVisitDelayShowsCampaignWithoutWaiting() async throws {
        let fixture = TemporarySDKFixture(apiKey: "negative-delay", section: "negative-delay")
        let sdk = fixture.initialize()
        sdk.setUser(userId: "negative-delay-user", sessionId: "session")
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        server.reset(campaigns: [["campaignId": "negative-delay", "delayTime": -5]], content: [["payload": [[
            "campaignId": "negative-delay", "experienceId": "e", "variationId": "v", "decisionId": "d",
            "contents": [["contentId": "negative-delay-content", "deliveryMethod": "modal", "contentType": "test",
                          "variables": ["elements": [["type": "text", "text": "No delay"]]]]]
        ]]]])
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let host = UIViewController()
        let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            host.presentedViewController != nil
        }, object: host)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }

        sdk.trackView(pageContext: PageContext(type: .other, data: [], location: "/negative-delay"),
                      viewController: host)
        // Wait for real presentation, not the server delay; a negative delay is
        // skipped. The local response used to trap at the UInt64 conversion.
        await fulfillment(of: [appeared], timeout: 3)
        XCTAssertNotNil(host.presentedViewController)
        XCTAssertEqual(server.recorded.filter { $0.path == "/visit" }.count, 1)
        XCTAssertEqual(server.recorded.filter { $0.path == "/choose" }.count, 1)
    }
}

private final class JumpingCampaignDelayClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: UInt64
    private var sleeps: [UInt64] = []

    init(start: UInt64) { instant = start }
    var now: UInt64 { lock.lock(); defer { lock.unlock() }; return instant }
    var intervals: [UInt64] { lock.lock(); defer { lock.unlock() }; return sleeps }
    func sleep(_ interval: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        sleeps.append(interval)
        instant = UInt64.max // Simulate resuming after the deadline without a real wait.
    }
}
