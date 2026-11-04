import Foundation
import XCTest
import UIKit
@testable import GravitySDK

final class UnknownActionTrackingTests: XCTestCase {
    @MainActor func testDifferentUnknownActionsCannotSendForeignTrackingURLFromAnyHook() async throws {
        let fixture = TemporarySDKFixture()
        let sdk = fixture.initialize()
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        let foreign = expectation(description: "no foreign URL from unknown actions")
        foreign.isInverted = true
        server.observeRequests { if $0.path == "/foreign" { foreign.fulfill() } }
        let unknownHook: [String: Any] = ["action": "foo_custom"]
        let json: [String: Any] = ["contentId": "unknown", "deliveryMethod": "modal", "contentType": "native", "step": 0,
            "variables": ["onLoad": unknownHook, "onImpression": unknownHook,
                "onVisibleImpression": unknownHook, "onClose": unknownHook],
            "events": [["type": "bar_custom", "urls": [server.url + "/foreign"]]]]
        let content = try JSONDecoder().decode(CampaignContent.self, from: JSONSerialization.data(withJSONObject: json))
        let button = try JSONDecoder().decode(OnClickModel.self, from: Data(#"{"action":"foo_custom","closeOnClick":false}"#.utf8))
        let campaign = Campaign(payload: [CampaignVariation(campaignId: "unknown", experienceId: "e", variationId: "v", decisionId: "d")])
        ContentEventService.instance.sendContentLoaded(content, campaign)
        ContentEventService.instance.sendContentImpression(content, campaign)
        ContentEventService.instance.sendContentVisibleImpression(content, campaign)
        ContentEventService.instance.sendContentClosed(content, campaign)
        sdk.onClickHandler(onClickModel: button, content: content, campaign: campaign, viewController: UIViewController())
        await fulfillment(of: [foreign], timeout: 1)
        XCTAssertTrue(server.recorded.isEmpty, "Foreign URL must never match a different raw unknown action")
        // Positive control: verify this fixture actually sends recognized tracking events.
        let known = CampaignContent(contentId: "known", deliveryMethod: .modal, contentType: "native", step: 0,
            variables: Variables(onLoad: ContentActionModel(action: .load)), events: [Event(type: .load, urls: [server.url + "/known"])])
        ContentEventService.instance.sendContentLoaded(known, campaign)
        _ = await server.waitFor(1)
        XCTAssertEqual(server.recorded.map(\.path), ["/known"])
        withExtendedLifetime(fixture) {}
    }
}
