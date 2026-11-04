import XCTest
import SwiftUI
@testable import GravitySDK

@MainActor
final class ProductsGridVisibilityTests: ProductsGridTestCase {
    func testClippedRowsWaitForHalfVisibilityInsideScrollViewport() async throws {
        var impressions = Set<String>()
        let rows = (0..<3).map { expectation(description: "Visible row \($0)") }
        rows.forEach { $0.expectedFulfillmentCount = 2 }
        let noNextRow = expectation(description: "Less than half of next row stays unreported")
        noNextRow.isInverted = true
        var allowNextRows = false
        GravitySDK.initialize(apiKey: "", section: "", gravityEventCallback: { event in
            if let event = event as? ProductImpressionEvent, let id = event.slot.slotId {
                if impressions.insert(id).inserted, let index = Int(id) {
                    if index >= 2, !allowNextRows { noNextRow.fulfill() }
                    rows[index / 2].fulfill()
                }
            }
        }, productViewBuilder: GridTestBuilder())
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let content = makeContent(slots: try makeSlots(count: 6), style: Style(productContainerType: .grid))
        let host = UIHostingController(rootView: VStack(spacing: 0) {
            Color.clear.frame(height: 100)
            ScrollView {
                GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in })
            }.frame(width: 360, height: 200)
            Spacer()
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [rows[0]], timeout: 2)
        XCTAssertEqual(impressions, ["0", "1"])
        let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
        // Second row starts at 184, so 73 pixels (< 50%) must not count.
        scroll.setContentOffset(CGPoint(x: 0, y: 57), animated: false)
        await fulfillment(of: [noNextRow], timeout: 0.15)
        XCTAssertEqual(impressions, ["0", "1"])
        allowNextRows = true
        scroll.setContentOffset(CGPoint(x: 0, y: 184), animated: false)
        await fulfillment(of: [rows[1]], timeout: 2)
        XCTAssertEqual(impressions, ["0", "1", "2", "3"])
        scroll.setContentOffset(CGPoint(x: 0, y: 368), animated: false)
        await fulfillment(of: [rows[2]], timeout: 2)
        XCTAssertEqual(impressions, Set((0..<6).map(String.init)))
    }

    func testInlineGridImpressionsFollowExternalUIKitScrollViewport() async throws {
        let loaded = expectation(description: "Inline content loaded")
        let hidden = expectation(description: "Offscreen inline grid stays unreported")
        hidden.isInverted = true
        let firstRow = expectation(description: "First row visible after external scroll")
        firstRow.expectedFulfillmentCount = 2
        var showing = false
        var impressions = Set<String>()
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        GravitySDK.initialize(apiKey: "inline-scroll", section: "inline-scroll", gravityEventCallback: { event in
            if event is ContentLoadEvent { loaded.fulfill() }
            if let product = event as? ProductImpressionEvent, let id = product.slot.slotId {
                if !showing { hidden.fulfill() }
                if impressions.insert(id).inserted { firstRow.fulfill() }
            }
        }, productViewBuilder: GridTestBuilder())
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        GravitySDK.instance.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let slots: [[String: Any]] = (0..<6).map { ["item": [:], "strId": $0, "slotId": String($0), "fallback": false] }
        let content: [String: Any] = ["contentId": "inline", "deliveryMethod": "inline", "contentType": "native",
            "variables": ["frameUI": ["container": ["style": ["size": ["height": 560]]]],
                          "elements": [["type": "products-container", "style": ["productContainerType": "grid"]]]],
            "products": ["strategyId": "s", "fallback": false, "slots": slots]]
        server.reset(content: [["payload": [["campaignId": "c", "experienceId": "e", "variationId": "v", "decisionId": "d", "contents": [content]]]]])
        let parent = UIViewController()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 100, width: 360, height: 200))
        parent.view.addSubview(scroll)
        let inline = GravityInlineView(selector: "grid")
        inline.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(inline)
        NSLayoutConstraint.activate([
            inline.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            inline.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            inline.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            inline.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 400),
            inline.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -240)])
        inline.initialize(pageContext: PageContext(type: .other, data: [], location: "inline-scroll"))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 900))
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [loaded], timeout: 3)
        await waitForLayout { scroll.contentSize.height > 1000 }
        await fulfillment(of: [hidden], timeout: 0.15)
        XCTAssertTrue(impressions.isEmpty)
        showing = true
        scroll.setContentOffset(CGPoint(x: 0, y: 400), animated: false)
        await fulfillment(of: [firstRow], timeout: 3)
        XCTAssertEqual(impressions, ["0", "1"])
    }

}

@MainActor
final class ProductsGridObserverEventTests: XCTestCase {
    func testAncestorBecomingVisibleTriggersObservation() async {
        let observer = ProductsGridVisibilityObserver()
        let appeared = expectation(description: "Cell appears after ancestor alpha change")
        let unexpected = expectation(description: "Hidden cell has no impression")
        unexpected.isInverted = true
        var shown = false
        let host = UIViewController()
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        parent.alpha = 0
        host.view.addSubview(parent)
        let root = ProductsGridVisibilityRoot.RootView(observer: observer)
        root.frame = parent.bounds
        parent.addSubview(root)
        let cell = ProductsGridVisibilityProbe.FrameView(observer: observer) {
            if shown { appeared.fulfill() } else { unexpected.fulfill() }
        }
        cell.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        root.addSubview(cell)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [unexpected], timeout: 0.15)
        shown = true
        parent.alpha = 1
        await fulfillment(of: [appeared], timeout: 1)
    }

    func testEntranceAnimationCompletionTriggersObservation() async {
        let observer = ProductsGridVisibilityObserver()
        let appeared = expectation(description: "Cell appears after entrance animation")
        let host = UIViewController()
        let root = ProductsGridVisibilityRoot.RootView(observer: observer)
        root.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        host.view.addSubview(root)
        let cell = ProductsGridVisibilityProbe.FrameView(observer: observer) { appeared.fulfill() }
        cell.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        root.addSubview(cell)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let entrance = CABasicAnimation(keyPath: "position")
        entrance.fromValue = CGPoint(x: 50, y: 1000)
        entrance.toValue = cell.layer.position
        entrance.duration = 0.3
        cell.layer.add(entrance, forKey: "entrance")
        await fulfillment(of: [appeared], timeout: 1)
    }
}
