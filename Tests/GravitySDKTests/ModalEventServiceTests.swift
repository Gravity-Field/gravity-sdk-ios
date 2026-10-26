import XCTest
import UIKit
@testable import GravitySDK

final class ModalEventServiceTests: XCTestCase {
    @MainActor func testSdkGateUses24HourProtectionInsteadOfDeliveryTtl() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("queue.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let shownAt = Date(timeIntervalSince1970: 1000)
        var time = shownAt
        let store = VisibleImpressionStore(fileURL: file, now: { time })
        let sdk = GravitySDK(apiKey: "policy", section: "policy", gravityEventCallback: nil,
            productViewBuilder: nil, productFilter: nil, uiSettings: nil, visibleImpressionStore: store)
        try store.insert(.init(id: UUID(), scope: sdk.impressionScope, campaignId: "campaign", contentId: "event",
            urls: ["original"], createdAt: shownAt))
        let request = sdk.presentationGate.beginRequest(location: "home", newScreen: true)
        time = shownAt.addingTimeInterval(86_399)
        XCTAssertNil(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        time = shownAt.addingTimeInterval(86_400)
        XCTAssertNotNil(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        XCTAssertTrue(store.contains(scope: sdk.impressionScope, campaignId: "campaign"))
    }

    @MainActor func testStoreDiagnosticsUseGravityLoggerAndHostListener() async throws {
        let fixture = TemporarySDKFixture()
        fixture.initialize()
        let diagnostic = expectation(description: "store diagnostic reaches host listener")
        GravitySDK.instance.logListener = { level, message in
            guard message.contains("[WRIMPStore]") else { return }
            XCTAssertEqual(level, .error)
            XCTAssertTrue(message.contains("quarantined"))
            diagnostic.fulfill()
        }
        defer { GravitySDK.instance.logListener = nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("queue.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: file)
        _ = VisibleImpressionStore(fileURL: file, log: GravitySDK.logImpressionStore)
        await fulfillment(of: [diagnostic], timeout: 1)

    }

    @MainActor func testCloseXAndCancelActionsConfirmBeforeDismissal() {
        let fixture = TemporarySDKFixture()
        fixture.initialize()
        let content = CampaignContent(contentId: "initial", deliveryMethod: .modal, contentType: "test", step: 0)
        for action in [Action.close, .cancel] {
            var impressions = 0
            var closed = 0
            let opening = ModalImpressionSession(confirm: { impressions += 1; return true }, release: {})
            opening.confirmFrame(isActive: true)
            let presentation = InAppPresentation(willClose: { opening.explicitClose() },
                performDismiss: { complete in
                    XCTAssertEqual(impressions, 1)
                    closed += 1
                    complete(true)
                }, didDismiss: { _ in })
            GravitySDK.instance.onClickHandler(onClickModel: OnClickModel(action: action),
                content: content, campaign: Campaign(), viewController: UIViewController(),
                impressionSession: opening, dismissCallback: { presentation.close() })
            XCTAssertEqual(impressions, 1)
            XCTAssertEqual(closed, 1)
        }
    }

    func testHostBackAndTargetedDismissalConfirmBeforeRemoval() {
        let registry = InAppPresentationRegistry()
        var impressions = 0
        let opening = ModalImpressionSession(confirm: { impressions += 1; return true }, release: {})
        opening.confirmFrame(isActive: true)
        let presentation = InAppPresentation(willClose: { opening.explicitClose() },
            performDismiss: { complete in XCTAssertEqual(impressions, 1); complete(true) }, didDismiss: { _ in })
        registry.register(presentation, contentId: "visible")
        registry.dismiss(contentId: "visible") { XCTAssertTrue($0) }
        registry.dismiss(contentId: "visible") { XCTAssertFalse($0) }
        XCTAssertEqual(impressions, 1)
    }

    @MainActor func testFirstFrameAndCloseProtectWithoutWaitingForDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let io = DispatchQueue(label: "test.first-frame.WRIMP")
        let store = VisibleImpressionStore(fileURL: root.appendingPathComponent("queue.json"), ioQueue: io)
        let persisted = expectation(description: "callback follows background persistence")
        let sdk = GravitySDK(apiKey: "async", section: "async", gravityEventCallback: { event in
            if event is ContentVisibleImpressionEvent {
                XCTAssertEqual(store.entries.count, 1)
                persisted.fulfill()
            }
        }, productViewBuilder: nil, productFilter: nil, uiSettings: nil, visibleImpressionStore: store)
        let content = CampaignContent(contentId: "content", deliveryMethod: .modal, contentType: "test", step: 0,
            events: [Event(type: .visibleImpression, urls: ["https://tracking.test/original"])])
        let campaign = Campaign(payload: [CampaignVariation(campaignId: "campaign", experienceId: "e", variationId: "v", decisionId: "d")])
        let request = sdk.presentationGate.beginRequest(location: "home", newScreen: true)
        let reservation = try XCTUnwrap(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        XCTAssertTrue(sdk.presentationGate.present(reservation, contentIds: [content.contentId]) { true })
        let opening = sdk.makeModalImpressionSession(content, campaign)
        io.suspend()
        opening.confirmFrame(isActive: true)
        opening.explicitClose()
        opening.disappeared()
        XCTAssertTrue(opening.hasFired)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        let next = sdk.presentationGate.beginRequest(location: "next", newScreen: true)
        XCTAssertNil(sdk.presentationGate.reserve(campaignId: "campaign", request: next))
        io.resume()
        await fulfillment(of: [persisted], timeout: 2)
        XCTAssertEqual(try Data(contentsOf: store.fileURL).isEmpty, false)
    }

    @MainActor func testModalPersistsBeforeCallbackAndUserChangeKeepsOriginalContext() async throws {
        let callback = expectation(description: "persisted visible impression callback")
        var sdk: GravitySDK!
        let fixture = TemporarySDKFixture()
        fixture.initialize(callback: { event in
            guard event is ContentVisibleImpressionEvent else { return }
            XCTAssertEqual(sdk.visibleImpressionDelivery.store?.entries.count, 1)
            callback.fulfill()
        })
        sdk = GravitySDK.instance
        await sdk.visibleImpressionDelivery.stop() // deterministic offline boundary, no external requests
        sdk.setUser(userId: "A", sessionId: "session-A")
        let originalScope = sdk.impressionScope
        let content = CampaignContent(contentId: "initial", deliveryMethod: .modal, contentType: "test", step: 0,
            events: [Event(type: .visibleImpression, urls: ["https://tracking.test/original?user=A"])])
        let campaign = Campaign(payload: [CampaignVariation(campaignId: "c", experienceId: "e", variationId: "v", decisionId: "d")])
        let success = ContentEventService.instance.sendModalVisibleImpression(content, campaign, sdk: sdk,
            openingId: UUID(), scope: originalScope)
        XCTAssertTrue(success)
        await fulfillment(of: [callback], timeout: 1)
        let store = try XCTUnwrap(sdk.visibleImpressionDelivery.store)
        let entry = try XCTUnwrap(store.entries.first)
        defer { for url in entry.urls { try? store.acknowledge(id: entry.id, url: url) } }
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [[String: Any]])
        XCTAssertNil(saved.first?["user"])
        XCTAssertEqual(entry.scope, originalScope)
        let requestA = sdk.presentationGate.beginRequest(location: "home", newScreen: true)
        XCTAssertNil(sdk.presentationGate.reserve(campaignId: "c", request: requestA))
        sdk.setUser(userId: "B", sessionId: "session-B")
        let requestB = sdk.presentationGate.beginRequest(location: "home", newScreen: true)
        XCTAssertNotNil(sdk.presentationGate.reserve(campaignId: "c", request: requestB))
        sdk.setUser(userId: "A", sessionId: "session-new")
        let backToA = sdk.presentationGate.beginRequest(location: "home", newScreen: true)
        XCTAssertNil(sdk.presentationGate.reserve(campaignId: "c", request: backToA))
        XCTAssertEqual(store.entries.first?.urls, ["https://tracking.test/original?user=A"])
        XCTAssertEqual(store.entries.first?.scope, originalScope)
    }
}
