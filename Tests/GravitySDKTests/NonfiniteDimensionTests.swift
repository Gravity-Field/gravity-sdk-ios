import XCTest
import SwiftUI
@testable import GravitySDK

@MainActor final class NonfiniteDimensionTests: ProductsGridTestCase {
    private let tokens = [#""Infinity""#, #""-Infinity""#, #""NaN""#, #""1e400""#, #""Infinitypx""#, "1e400", "-1e400"]

    private func decode(_ json: String, convertFloats: Bool = false) throws -> Style {
        let decoder = JSONDecoder()
        if convertFloats {
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        }
        return try decoder.decode(Style.self, from: Data(json.utf8))
    }

    func testNonfiniteDimensionsFallBackWithoutLosingFiniteSiblings() throws {
        for token in tokens {
            for convert in [false, true] {
                let style = try decode("""
                    {"cornerRadius":\(token),"size":{"width":\(token),"height":37},
                    "padding":{"left":\(token),"right":5},"margin":{"top":\(token),"bottom":7},
                    "positioned":{"left":\(token),"right":11},"rowSpacing":\(token),
                    "gridSettings":{"columns":\(token),"horizontalSpacing":\(token),"verticalSpacing":\(token)}}
                    """, convertFloats: convert)
                XCTAssertNil(style.cornerRadius, token)
                XCTAssertNil(style.size?.width, token)
                XCTAssertEqual(style.size?.height, 37, token)
                XCTAssertEqual(style.padding?.left, 0, token)
                XCTAssertEqual(style.padding?.right, 5, token)
                XCTAssertEqual(style.margin?.top, 0, token)
                XCTAssertEqual(style.margin?.bottom, 7, token)
                XCTAssertNil(style.positioned?.left, token)
                XCTAssertEqual(style.positioned?.right, 11, token)
                XCTAssertNil(style.rowSpacing, token)
                XCTAssertNil(style.gridSettings?.columns, token)
                XCTAssertNil(style.gridSettings?.horizontalSpacing, token)
                XCTAssertNil(style.gridSettings?.verticalSpacing, token)
                XCTAssertEqual(style.gridSettings?.horizontalSpacingValue, 8, token)
                XCTAssertEqual(style.gridSettings?.verticalSpacingValue, 8, token)
            }
        }
        for token in ["12.5", #""12.5px""#, #"" 12.5 ""#] {
            let style = try decode("{\"cornerRadius\":\(token),\"rowSpacing\":\(token)}")
            XCTAssertEqual(style.cornerRadius, 12.5)
            XCTAssertEqual(style.rowSpacing, 12.5)
        }
    }

    func testNonfiniteSizeRendersLikeAbsentDimensions() throws {
        try compareTextLayout { "{\"size\":{\"width\":\($0),\"height\":\($0)}}" }
    }

    func testNonfinitePaddingRendersLikeAbsentDimensions() throws {
        try compareTextLayout { "{\"padding\":{\"left\":\($0),\"top\":\($0),\"right\":\($0),\"bottom\":\($0)}}" }
    }

    func testNonfiniteMarginRendersLikeAbsentDimensions() throws {
        try compareTextLayout { "{\"margin\":{\"left\":\($0),\"top\":\($0),\"right\":\($0),\"bottom\":\($0)}}" }
    }

    private func compareTextLayout(_ json: (String) -> String) throws {
        func size(_ style: Style) -> CGSize {
            UIHostingController(rootView: GravityText(element: Element(type: .text, text: "Visible text", style: style), onClickCallback: { _ in }))
                .sizeThatFits(in: CGSize(width: 320, height: 600))
        }
        let expected = size(.empty)
        for token in tokens {
            let actual = size(try decode(json(token)))
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, token)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, token)
        }
    }

    func testNonfiniteCornerRadiusRendersButton() throws {
        for token in tokens {
            let style = try decode("{\"cornerRadius\":\(token),\"size\":{\"width\":120,\"height\":40}}")
            let host = UIHostingController(rootView: GravityButton(element: Element(type: .button, text: "Button", style: style), onClickCallback: { _ in }))
            let size = host.sizeThatFits(in: CGSize(width: 320, height: 600))
            XCTAssertEqual(size.width, 120, accuracy: 0.5, token)
            XCTAssertEqual(size.height, 40, accuracy: 0.5, token)
            host.view.frame = CGRect(x: 0, y: 0, width: 120, height: 40)
            host.view.layoutIfNeeded()
            _ = UIGraphicsImageRenderer(size: host.view.bounds.size).image { host.view.layer.render(in: $0.cgContext) }
        }
    }

    func testNonfiniteGridPlaceholderHeightRendersAsZero() throws {
        for token in tokens {
            let style = try decode("{\"productContainerType\":\"grid\",\"size\":{\"height\":\(token)}}")
            let content = CampaignContent(contentId: "placeholder", deliveryMethod: .inline, contentType: "test", step: nil,
                variables: Variables(elements: [Element(type: .productsContainer, style: style)]))
            let host = UIHostingController(rootView: VStack(spacing: 0) {
                GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in })
                Color.clear.frame(height: 19)
            })
            XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 320, height: 600)).height, 19, accuracy: 0.5, token)
        }
    }

    func testNonfiniteSpacingRendersProductRowsAndGridsWithDefaultGap() throws {
        let fixture = TemporarySDKFixture()
        let builder = DimensionCardBuilder()
        let store = VisibleImpressionStore(fileURL: fixture.root.appendingPathComponent("queue.json"))
        GravitySDK.initialize(GravitySDK(apiKey: "", section: "", gravityEventCallback: nil,
            productViewBuilder: builder, productFilter: nil, uiSettings: nil, visibleImpressionStore: store))
        defer { fixture.initialize() }
        for kind in ["row", "grid"] {
            for token in tokens {
                builder.frames = [:]
                let style = try decode("""
                    {"productContainerType":"\(kind)","size":{"height":40},"rowSpacing":\(token),
                    "gridSettings":{"columns":2,"horizontalSpacing":\(token),"verticalSpacing":\(token)}}
                    """)
                let content = makeContent(slots: try makeSlots(count: 4), style: style)
                let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                settle(host)
                let first = try XCTUnwrap(builder.frames[0], token)
                let second = try XCTUnwrap(builder.frames[1], token)
                XCTAssertEqual(second.minX - first.maxX, 8, accuracy: 0.5, "\(kind): \(token)")
                if kind == "grid" {
                    let third = try XCTUnwrap(builder.frames[2], token)
                    XCTAssertEqual(third.minY - first.maxY, 8, accuracy: 0.5, token)
                }
            }
        }
    }
}

private final class DimensionCardBuilder: ProductViewBuilder {
    var frames: [Int: CGRect] = [:]
    func build(slot: Slot, content: CampaignContent, campaign: Campaign) -> AnyView {
        AnyView(Color.blue.frame(minWidth: 40, minHeight: 40).background(GeometryReader { geometry in
            Color.clear.onAppear { self.frames[slot.strId] = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { self.frames[slot.strId] = $0 }
        }))
    }
}
