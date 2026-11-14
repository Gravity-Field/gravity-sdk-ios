import XCTest
import UIKit
@testable import GravitySDK

final class ReleaseCloseWireTests: XCTestCase {
    @MainActor func testCloseActionAndDismissalSendOneURLForEveryModalMethod() async throws {
        for method in [DeliveryMethod.modal, .fullScreen, .bottomSheet] {
            let fixture = TemporarySDKFixture()
            let sdk = fixture.initialize()
            let server = try RecordingServer()
            try await server.start()
            defer { server.stop() }
            let delivered = expectation(description: "one close URL for \(method)")
            delivered.assertForOverFulfill = false
            server.observeRequests { if $0.path == "/close" { delivered.fulfill() } }
            let content = CampaignContent(contentId: "close", deliveryMethod: method, contentType: "native", step: 0,
                variables: Variables(onClose: ContentActionModel(action: .close)),
                events: [Event(type: .close, urls: [server.url + "/close"])])
            // Exercise the action and successful dismissal composition without
            // UIKit transitions, which cannot complete in an unhosted test bundle.
            let presentation = InAppPresentation(performDismiss: { $0(true) }, didDismiss: { success in
                if success { ContentEventService.instance.sendContentClosed(content, Campaign()) }
            })
            sdk.onClickHandler(onClickModel: OnClickModel(action: .close), content: content,
                campaign: Campaign(), viewController: UIViewController(), dismissCallback: { presentation.close() })
            await fulfillment(of: [delivered], timeout: 3)
            _ = await server.waitFor(2, timeout: 0.2)
            XCTAssertEqual(server.recorded.filter { $0.path == "/close" }.count, 1, "\(method)")
        }
    }
}
