import XCTest
import UIKit
@testable import GravitySDK

final class SlowStartupPresentationTests: XCTestCase {
    @MainActor func testColdStartShowsFirstCampaignAfterSlowEmptyStoreLoad() async throws {
        try await checkSlowStartup(pending: false)
    }

    @MainActor func testColdStartBlocksOnlyPersistedCampaignAfterSlowStoreLoad() async throws {
        try await checkSlowStartup(pending: true)
    }

    @MainActor func testUserChangeDuringSlowLoadInvalidatesWaitingPresentation() async throws {
        try await checkSlowStartup(pending: false, invalidateRequest: true)
    }

    @MainActor private func checkSlowStartup(pending: Bool, invalidateRequest: Bool = false) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("queue.json")
        if pending {
            let scope = String(decoding: try JSONEncoder().encode(["startup", "A", ""]), as: UTF8.self)
            try VisibleImpressionStore(fileURL: file).insert(.init(id: UUID(), scope: scope,
                campaignId: "first", contentId: "old-event", urls: ["original-url"]))
        }
        let io = DispatchQueue(label: "test.slow-startup")
        io.suspend()
        var suspended = true
        defer { if suspended { io.resume() } }
        let store = VisibleImpressionStore(fileURL: file, loadsAsynchronously: true, ioQueue: io)
        let shouldShow = !pending && !invalidateRequest
        let sdk = GravitySDK(apiKey: "startup", section: "startup", gravityEventCallback: nil,
            productViewBuilder: nil, productFilter: nil, uiSettings: nil, visibleImpressionStore: store)
        await sdk.visibleImpressionDelivery.stop() // keep the restored entry offline
        GravitySDK.initialize(sdk)
        sdk.setUser(userId: "A", sessionId: "session")
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        server.reset(campaigns: [["campaignId": "first", "priority": 1]], content: [["payload": [[
            "campaignId": "first", "experienceId": "e", "variationId": "v", "decisionId": "d",
            "contents": [["contentId": "new-event", "deliveryMethod": "modal", "contentType": "test", "step": 0,
                          "variables": ["elements": [["type": "text", "text": "Cold start"]]]]]
        ]]]])
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let host = UIViewController()
        let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            host.presentedViewController != nil
        }, object: host)
        appeared.isInverted = !shouldShow
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }

        // Detect an early gate decision, including a false protected=true decision that
        // would silently discard this response. The real provider still decides the result.
        let earlyDecision = expectation(description: "no protection decision until initial load")
        earlyDecision.isInverted = true
        let protects = sdk.presentationGate.deliveryPending
        sdk.presentationGate.deliveryPending = { campaign in
            earlyDecision.fulfill()
            return protects(campaign)
        }
        sdk.trackView(pageContext: PageContext(type: .other, data: [], location: "/cold-start"), viewController: host)
        let visits = await server.waitFor(1)
        XCTAssertEqual(visits.filter { $0.path.hasSuffix("/visit") }.count, 1)
        await fulfillment(of: [earlyDecision], timeout: 0.15) // I/O remains deliberately suspended
        XCTAssertNil(host.presentedViewController)
        XCTAssertEqual(server.recorded.filter { $0.path.hasSuffix("/choose") }.count, 0)
        sdk.presentationGate.scoped { sdk.presentationGate.deliveryPending = protects }
        if invalidateRequest { sdk.setUser(userId: "B", sessionId: "new-session") }
        io.resume()
        suspended = false
        await store.waitForPendingWrites()
        await fulfillment(of: [appeared], timeout: shouldShow ? 3 : 0.25)
        XCTAssertEqual(server.recorded.filter { $0.path.hasSuffix("/choose") }.count, shouldShow ? 1 : 0)
        if shouldShow { XCTAssertNotNil(host.presentedViewController) }
        else { XCTAssertNil(host.presentedViewController) }
        XCTAssertEqual(store.protects(scope: sdk.impressionScope, campaignId: "first"), pending)
    }
}
