import XCTest
import SwiftUI
@testable import GravitySDK

@MainActor final class ReleaseProductsRowLayoutTests: ProductsGridTestCase {
    func testRowMarginIsOutsideBackgroundAndPaddingIsInside() throws {
        let fixture = TemporarySDKFixture()
        fixture.initialize()
        let style = Style(backgroundColor: .red, size: GravitySize(height: 100),
            margin: GravityMargin(left: 20, right: 20, top: 20, bottom: 20),
            padding: GravityPadding(left: 10, right: 10, top: 10, bottom: 10))
        let slots = try makeSlots(count: 1)
        let content = makeContent(slots: slots, style: style)
        let row = ProductsRow(element: Element(type: .productsContainer, style: style), slots: slots, content: content, campaign: Campaign())
        let host = UIHostingController(rootView: row.background(Color.green).frame(width: 300, height: 140))
        host.view.backgroundColor = .white
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(host)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { host.view.layer.render(in: $0.cgContext) }
        let cgImage = try XCTUnwrap(image.cgImage)
        // The fixed row is centered in the hosting view. Sample its horizontal
        // margin and padding at the vertical center, away from safe areas.
        let center = CGPoint(x: host.view.bounds.midX, y: host.view.bounds.midY)
        for (x, red) in [(center.x - 145, false), (center.x - 125, true)] {
            let sample = try XCTUnwrap(cgImage.cropping(to: CGRect(x: x, y: center.y, width: 1, height: 1)))
            var pixel = [UInt8](repeating: 0, count: 4)
            try pixel.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            if red { XCTAssertGreaterThan(Int(pixel[0]), Int(pixel[1]) + 40, "Padding carries the row background") }
            else { XCTAssertGreaterThan(Int(pixel[1]), Int(pixel[0]) + 40, "Margin exposes the outer background") }
        }
    }

    /// A product row or grid without products takes no space, including its margin
    /// and padding.
    func testEmptyProductContainerHeights() throws {
        let fixture = TemporarySDKFixture()
        fixture.initialize()
        let states: [(String, Products?)] = [
            ("products missing", nil),
            ("slots missing", Products(strategyId: "s", fallback: false, name: nil, slots: nil, pageNumber: nil, countPages: nil)),
            ("slots empty", Products(strategyId: "s", fallback: false, name: nil, slots: [], pageNumber: nil, countPages: nil)),
        ]
        let expected: [ProductContainerType: [Double]] = [.row: [0, 0, 0], .grid: [0, 0, 0]]
        for type in [ProductContainerType.row, .grid] {
            for (index, (label, products)) in states.enumerated() {
                let style = Style(backgroundColor: .red, size: GravitySize(height: 84),
                    margin: GravityMargin(left: 12, right: 12, top: 12, bottom: 12),
                    padding: GravityPadding(left: 5, right: 9, top: 7, bottom: 11),
                    productContainerType: type)
                let content = CampaignContent(contentId: "empty-\(type)-\(index)", deliveryMethod: .inline,
                    contentType: "test", step: nil,
                    variables: Variables(elements: [Element(type: .productsContainer, style: style)]),
                    products: products)
                let host = UIHostingController(rootView: VStack(spacing: 0) {
                    GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in })
                    Color.clear.frame(height: 19)
                })
                let height = host.sizeThatFits(in: CGSize(width: 320, height: 600)).height - 19
                XCTAssertEqual(height, expected[type]![index], accuracy: 0.5, "\(type) \(label)")
            }
        }
    }
}
