import XCTest
import UIKit
@testable import GravitySDK

final class ModalEventServiceTests: XCTestCase {
    @MainActor func testCloseXAndCancelActionsConfirmBeforeDismissal() {
        GravitySDK.initialize(apiKey: "ego272-actions", section: UUID().uuidString)
        let content = CampaignContent(contentId: "initial", deliveryMethod: .modal, contentType: "test", step: 0)
        for action in [Action.close, .cancel] {
            var impressions = 0
            var closed = 0
            let opening = ModalImpressionSession(confirm: { impressions += 1; return true }, release: {})
            opening.confirmFrame(isActive: true)
            let presentation = InAppPresentation(willClose: { opening.explicitClose(isActive: true) },
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
        let presentation = InAppPresentation(willClose: { opening.explicitClose(isActive: true) },
            performDismiss: { complete in XCTAssertEqual(impressions, 1); complete(true) }, didDismiss: { _ in })
        registry.register(presentation, contentId: "visible")
        registry.dismiss(contentId: "visible") { XCTAssertTrue($0) }
        registry.dismiss(contentId: "visible") { XCTAssertFalse($0) }
        XCTAssertEqual(impressions, 1)
    }

    @MainActor func testModalPersistsBeforeCallbackAndUserChangeKeepsOriginalContext() async throws {
        let callback = expectation(description: "persisted visible impression callback")
        var sdk: GravitySDK!
        GravitySDK.initialize(apiKey: "ego272-test", section: UUID().uuidString, gravityEventCallback: { event in
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
            openingId: UUID(), scope: originalScope, user: sdk.impressionUser)
        XCTAssertTrue(success)
        await fulfillment(of: [callback], timeout: 1)
        let store = try XCTUnwrap(sdk.visibleImpressionDelivery.store)
        let entry = try XCTUnwrap(store.entries.first)
        defer { for url in entry.urls { try? store.acknowledge(id: entry.id, url: url) } }
        let snapshot = try JSONDecoder().decode(User.self, from: Data(entry.user.utf8))
        XCTAssertEqual(snapshot.custom, "A")
        XCTAssertEqual(snapshot.ses, "session-A")
        let requestA = sdk.presentationGate.beginRequest(location: "home", newScreen: true)
        XCTAssertNil(sdk.presentationGate.reserve(campaignId: "c", request: requestA))
        sdk.setUser(userId: "B", sessionId: "session-B")
        let requestB = sdk.presentationGate.beginRequest(location: "home", newScreen: true)
        XCTAssertNotNil(sdk.presentationGate.reserve(campaignId: "c", request: requestB))
        sdk.setUser(userId: "A", sessionId: "session-new")
        let backToA = sdk.presentationGate.beginRequest(location: "home", newScreen: true)
        XCTAssertNil(sdk.presentationGate.reserve(campaignId: "c", request: backToA))
        XCTAssertEqual(store.entries.first?.urls, ["https://tracking.test/original?user=A"])
        XCTAssertEqual(store.entries.first?.user, entry.user)
    }
}
