import XCTest
import SwiftUI
@testable import GravitySDK

@MainActor
final class ProductsGridHostTests: ProductsGridTestCase {
    func testGridRendersInModalAndBothInlineHosts() async throws {
        for placement in ["modal", "inlineUIKit", "inlineSwiftUI"] {
            let ready = expectation(description: "Three square cards in \(placement)")
            var fulfilled = false
            let builder = GridTestBuilder()
            builder.onFrame = {
                guard !fulfilled, builder.frames.count == 3,
                      builder.frames.values.allSatisfy({ $0.width > 10 && abs($0.width - $0.height) < 0.5 }) else { return }
                fulfilled = true
                ready.fulfill()
            }
            let server = try RecordingServer()
            try await server.start()
            defer { server.stop() }
            GravitySDK.initialize(apiKey: "grid-host", section: "grid-host", productViewBuilder: builder)
            defer { GravitySDK.initialize(apiKey: "", section: "") }
            GravitySDK.instance.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
            let slots: [[String: Any]] = (0..<3).map { ["item": [:], "strId": $0, "slotId": String($0), "fallback": false] }
            let wireContent: [String: Any] = [
                "contentId": "grid", "deliveryMethod": "inline", "contentType": "test",
                "variables": ["frameUI": ["container": ["style": ["size": ["height": 400]]]],
                              "elements": [["type": "products-container", "style": ["productContainerType": "grid"]]]],
                "products": ["strategyId": "s", "fallback": false, "slots": slots]]
            server.reset(content: [["payload": [["campaignId": "c", "experienceId": "e", "variationId": "v", "decisionId": "d", "contents": [wireContent]]]]])
            let host: UIViewController
            if placement == "modal" {
                let content = makeContent(slots: try makeSlots(count: 3), style: Style(productContainerType: .grid), frameStyle: Style())
                host = UIHostingController(rootView: GravityModalContent(content: content, campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onClickCallback: { _ in }, onDismiss: {}))
            } else if placement == "inlineSwiftUI" {
                host = UIHostingController(rootView: GravityInlineSwiftUIView(selector: "grid", pageContext: PageContext(type: .other, data: [], location: "grid")))
            } else {
                let inline = GravityInlineView(selector: "grid")
                inline.initialize(pageContext: PageContext(type: .other, data: [], location: "grid"))
                host = UIViewController()
                host.view = inline
            }
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            await fulfillment(of: [ready], timeout: 3)
            XCTAssertEqual(builder.frames.count, 3)
            if placement != "modal" { XCTAssertEqual(server.recorded.filter { $0.path == "/choose" }.count, 1) }
            builder.onFrame = nil
        }
    }
}
