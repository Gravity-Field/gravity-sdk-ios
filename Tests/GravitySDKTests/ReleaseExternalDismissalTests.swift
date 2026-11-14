import XCTest
import SwiftUI
@testable import GravitySDK

final class ReleaseExternalDismissalTests: XCTestCase {
    @MainActor func testHostRemovalTracksCloseOnceForEveryModalMethod() async throws {
        for method in [DeliveryMethod.modal, .fullScreen, .bottomSheet] {
            let fixture = TemporarySDKFixture()
            let closed = expectation(description: "External removal closes \(method)")
            closed.assertForOverFulfill = true
            let sdk = fixture.initialize(callback: { if $0 is ContentCloseEvent { closed.fulfill() } })
            let content = CampaignContent(contentId: "external", deliveryMethod: method, contentType: "native", step: nil,
                variables: Variables(frameUI: FrameUI(container: Container()), elements: [Element(type: .text, text: "External")]))
            let host = UIViewController()
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            let opening = sdk.makeModalImpressionSession(content, Campaign())
            XCTAssertTrue(sdk.showBackendContent(host, content, Campaign(), impressionSession: opening))
            let presented = try XCTUnwrap(host.presentedViewController)
            // Drive the real hosting-controller lifecycle deterministically;
            // unhosted XCTest cannot complete UIKit presentation transitions.
            presented.viewDidAppear(false)
            opening.confirmFrame(isActive: true)
            presented.viewDidDisappear(false)
            presented.viewDidDisappear(false)
            await fulfillment(of: [closed], timeout: 0.3)
        }
    }
}
