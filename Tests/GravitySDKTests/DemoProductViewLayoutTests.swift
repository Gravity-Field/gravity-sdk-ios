import XCTest
import UIKit
import SwiftUI
@testable import GravitySDK

@MainActor
final class DemoProductViewLayoutTests: XCTestCase {
    func testNarrowCardsKeepTheSameLayoutAfterImagesLoad() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
        }
        let slots = try (0..<5).map { index in
            try JSONDecoder().decode(Slot.self, from: Data("{\"item\":{\"name\":\"Product 0\(index + 1)\",\"price\":\"\(1200 + index * 100)\",\"in_stock\":true},\"strId\":\(index),\"fallback\":false}".utf8))
        }
        for width in [320.0, 345, 354, 375] {
            let builder = DemoCardTestBuilder()
            GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
            defer { GravitySDK.initialize(apiKey: "", section: "") }
            let element = try JSONDecoder().decode(Element.self, from: Data(ProductsGridWireFixtures.elements[2].utf8))
            let content = CampaignContent(contentId: "demo", deliveryMethod: .inline, contentType: "test", step: nil,
                variables: Variables(elements: [element]),
                products: Products(strategyId: "test", fallback: false, name: nil, slots: slots, pageNumber: nil, countPages: nil))
            let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }).frame(maxHeight: .infinity, alignment: .top))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 700))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            settle(host)
            XCTAssertEqual(builder.cards.count, 5)
            // Images arrive one by one, as in the actual demo's asynchronous loader.
            for card in builder.cards {
                let imageView = try XCTUnwrap(descendants(in: card).compactMap { $0 as? UIImageView }.first)
                imageView.image = image
                settle(host)
            }
            var imageFrames: [CGRect] = []
            var nameFrames: [CGRect] = []
            for card in builder.cards {
                let views = descendants(in: card)
                let imageView = try XCTUnwrap(views.compactMap { $0 as? UIImageView }.first)
                let name = try XCTUnwrap(views.compactMap { $0 as? UILabel }.first { $0.text?.hasPrefix("Product") == true })
                imageFrames.append(imageView.convert(imageView.bounds, to: card))
                nameFrames.append(name.convert(name.bounds, to: card))
                XCTAssertGreaterThanOrEqual(imageView.bounds.height, 0)
            }
            let firstImage = try XCTUnwrap(imageFrames.first)
            let firstName = try XCTUnwrap(nameFrames.first)
            for (imageFrame, nameFrame) in zip(imageFrames, nameFrames) {
                XCTAssertEqual(imageFrame.minY, firstImage.minY, accuracy: 0.5)
                XCTAssertEqual(imageFrame.height, firstImage.height, accuracy: 0.5)
                XCTAssertEqual(nameFrame.minY, firstName.minY, accuracy: 0.5)
            }
        }
    }

    private func settle<Content: View>(_ host: UIHostingController<Content>) {
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.layoutIfNeeded()
    }

    private func descendants(in view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(in: $0) }
    }
}

private final class DemoCardTestBuilder: LegacyProductViewBuilder {
    var cards: [ProductView] = []

    func createView(slot: Slot, content: CampaignContent, campaign: Campaign) -> UIView {
        let card = ProductView(slot: slot)
        cards.append(card)
        return card
    }
}
