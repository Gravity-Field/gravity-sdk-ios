import XCTest
import SwiftUI
@testable import GravitySDK

@MainActor
final class ProductsGridRenderingTests: ProductsGridTestCase {
    func testGridIgnoresMarginAndBackgroundAndUsesOnlyPadding() throws {
        for (fixtureIndex, json) in ProductsGridWireFixtures.elements.enumerated() {
            let element = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
            let columns = fixtureIndex == 0 ? 2 : 4
            let spacing = fixtureIndex == 0 ? 8.0 : 6.0
            let padding = fixtureIndex >= 2 ? 5.0 : 0.0
            for width in [320.0, 393.0] {
                for count in [0, 1, 5, 20] {
                    let builder = GridTestBuilder()
                    GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
                    defer { GravitySDK.initialize(apiKey: "", section: "") }
                    let content = makeContent(slots: try makeSlots(count: count), style: element.style)
                    let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }))
                    let cellWidth = (width - 2 * padding - Double(columns - 1) * spacing) / Double(columns)
                    let rows = Double((count + columns - 1) / columns)
                    let expectedHeight = count == 0 ? 0 : 2 * padding + rows * cellWidth + (rows - 1) * spacing
                    let size = host.sizeThatFits(in: CGSize(width: width, height: 5000))
                    XCTAssertEqual(size.height, expectedHeight, accuracy: 0.5, "fixture \(fixtureIndex + 1), count \(count)")
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 1000))
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    settle(host)
                    XCTAssertEqual(builder.frames.count, count)
                    if count > 0 {
                        let first = try XCTUnwrap(builder.frames["0"])
                        XCTAssertEqual(first.width, cellWidth, accuracy: 0.5)
                        XCTAssertEqual(first.height, cellWidth, accuracy: 0.5)
                        XCTAssertEqual(first.minX, padding, accuracy: 0.5)
                        if count > columns {
                            let nextRow = try XCTUnwrap(builder.frames[String(columns)])
                            XCTAssertEqual(nextRow.minY - first.maxY, spacing, accuracy: 0.5)
                            XCTAssertEqual(nextRow.minX, first.minX, accuracy: 0.5)
                        }
                        if count > 1 {
                            XCTAssertEqual(try XCTUnwrap(builder.frames["1"]).minX - first.maxX, spacing, accuracy: 0.5)
                        }
                    }
                    window.isHidden = true
                }
            }
        }
    }

    func testGridRendersAllCellsAndResizesWithoutDuplicateImpressions() async throws {
        let builder = GridTestBuilder()
        var impressions: [String] = []
        let duplicate = expectation(description: "No duplicate impressions after cell restoration or resizing")
        duplicate.isInverted = true
        var detectsDuplicates = false
        GravitySDK.initialize(apiKey: "", section: "", gravityEventCallback: { event in
            if let event = event as? ProductImpressionEvent, let id = event.slot.slotId {
                impressions.append(id)
                if detectsDuplicates { duplicate.fulfill() }
            }
        }, productViewBuilder: builder)
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let slots = try makeSlots(count: 5)
        let style = Style(size: GravitySize(width: 164, height: 250), padding: GravityPadding(left: 10, right: 10, top: 4, bottom: 6), productContainerType: .grid, gridSettings: GridSettings(columns: 2, horizontalSpacing: 12, verticalSpacing: 12))
        let content = makeContent(slots: slots, style: style)
        let campaign = Campaign(selector: "grid")
        let host = UIHostingController(rootView: GridTestHost(content: content, campaign: campaign, builder: builder))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 1400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await waitForLayout { builder.frames.count == 5 && impressions.count == 5 && builder.endFrame.minY > 0 }

        XCTAssertEqual(builder.frames.count, 5)
        let first = try XCTUnwrap(builder.frames["0"])
        let second = try XCTUnwrap(builder.frames["1"])
        let last = try XCTUnwrap(builder.frames["4"])
        XCTAssertEqual(first.width, 164, accuracy: 0.5)
        XCTAssertEqual(first.height, first.width, accuracy: 0.5)
        XCTAssertEqual(second.minX - first.maxX, 12, accuracy: 0.5)
        XCTAssertEqual(last.minX, first.minX, accuracy: 0.5)
        XCTAssertEqual(last.minY - first.minY, 352, accuracy: 0.5)
        XCTAssertEqual(builder.endFrame.minY - first.minY, 522, accuracy: 0.5)
        XCTAssertEqual(Set(impressions), Set(["0", "1", "2", "3", "4"]))
        XCTAssertEqual(impressions.count, 5)
        XCTAssertEqual(builder.contentIds, Set(["grid-content"]))
        XCTAssertEqual(builder.selectors, Set(["grid"]))

        detectsDuplicates = true

        // Removing and restoring cells resets their detector state, but not container deduplication.
        host.rootView = GridTestHost(content: makeContent(slots: Array(slots.prefix(1)), style: style), campaign: campaign, builder: builder)
        await waitForLayout { abs(builder.endFrame.minY - (builder.frames["0"]?.minY ?? 0) - 170) < 0.5 }
        host.rootView = GridTestHost(content: content, campaign: campaign, builder: builder)
        await waitForLayout { abs(builder.endFrame.minY - (builder.frames["0"]?.minY ?? 0) - 522) < 0.5 }
        XCTAssertEqual(impressions.count, 5)

        window.frame.size.width = 400
        host.view.frame = window.bounds
        await waitForLayout { abs((builder.frames["0"]?.width ?? 0) - 184) < 0.5 }
        XCTAssertEqual(try XCTUnwrap(builder.frames["0"]).width, 184, accuracy: 0.5)
        await fulfillment(of: [duplicate], timeout: 0.3)
        XCTAssertEqual(impressions.count, 5)
    }

    func testFirstSizeThatFitsMeasuresFullGridHeight() throws {
        GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: GridTestBuilder())
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let cases: [(Style, Int, Double)] = [
            (Style(size: GravitySize(width: 100, height: 100), productContainerType: .grid), 4, 360),
            (Style(size: GravitySize(width: 164, height: 250), margin: GravityMargin(left: 0, right: 0, top: 6, bottom: 8), padding: GravityPadding(left: 10, right: 10, top: 4, bottom: 6), productContainerType: .grid, gridSettings: GridSettings(columns: 2, horizontalSpacing: 12, verticalSpacing: 12)), 5, 526)
        ]
        for (style, count, height) in cases {
            let content = makeContent(slots: try makeSlots(count: count), style: style)
            let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }))
            let size = host.sizeThatFits(in: CGSize(width: 360, height: 5000))
            XCTAssertEqual(size.width, 360, accuracy: 0.5)
            XCTAssertEqual(size.height, height, accuracy: 0.5)
        }
    }

    func testFixedHorizontalSizeUsesIdealCardWidthWithoutCollapsing() throws {
        GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: GridTestBuilder())
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        for style in [Style(size: GravitySize(width: 100, height: 100), productContainerType: .grid), Style(productContainerType: .grid)] {
            let content = makeContent(slots: try makeSlots(count: 4), style: style)
            let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in })
                .fixedSize(horizontal: true, vertical: false))
            let size = host.sizeThatFits(in: CGSize(width: 360, height: 5000))
            XCTAssertEqual(size.width, 208, accuracy: 0.5)
            XCTAssertEqual(size.height, 208, accuracy: 0.5)
        }
    }

    func testNilSlotIdsAreIgnoredAndKnownSlotsCanSendForNewContentOrCampaign() async throws {
        let builder = GridTestBuilder()
        var impressions = 0
        GravitySDK.initialize(apiKey: "", section: "", gravityEventCallback: { event in
            if event is ProductImpressionEvent { impressions += 1 }
        }, productViewBuilder: builder)
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let slots = try (0..<4).map { index in
            try JSONDecoder().decode(Slot.self, from: Data("{\"item\":{},\"strId\":\(index),\"fallback\":false}".utf8))
        }
        let style = Style(size: GravitySize(width: 100, height: 100), productContainerType: .grid)
        let content = makeContent(slots: slots, style: style)
        let host = UIHostingController(rootView: GridTestHost(content: content, campaign: Campaign(), builder: builder))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 1000))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(host)
        XCTAssertEqual(impressions, 0)
        host.rootView = GridTestHost(content: makeContent(slots: Array(slots.prefix(1)), style: style), campaign: Campaign(), builder: builder)
        settle(host)
        host.rootView = GridTestHost(content: content, campaign: Campaign(), builder: builder)
        settle(host)
        XCTAssertEqual(impressions, 0)
        let next = makeContent(slots: slots, style: style, contentId: "next-content")
        host.rootView = GridTestHost(content: next, campaign: Campaign(), builder: builder)
        settle(host)
        XCTAssertEqual(impressions, 0)
        host.rootView = GridTestHost(content: next, campaign: Campaign(selector: "next-campaign"), builder: builder)
        settle(host)
        XCTAssertEqual(impressions, 0)
        host.rootView = GridTestHost(content: makeContent(slots: try makeSlots(count: 4), style: style, contentId: "next-content"), campaign: Campaign(selector: "next-campaign"), builder: builder)
        await waitForLayout { impressions == 4 }
        XCTAssertEqual(impressions, 4)
        let nextCampaign = Campaign(selector: "next-campaign", payload: [CampaignVariation(campaignId: "campaign-2", experienceId: "experience", variationId: "variation", decisionId: "decision")])
        host.rootView = GridTestHost(content: makeContent(slots: try makeSlots(count: 4), style: style, contentId: "next-content"), campaign: nextCampaign, builder: builder)
        await waitForLayout { impressions == 8 }
        XCTAssertEqual(impressions, 8)
        host.rootView = GridTestHost(content: makeContent(slots: Array(try makeSlots(count: 8).suffix(4)), style: style, contentId: "next-content"), campaign: nextCampaign, builder: builder)
        await waitForLayout { impressions == 12 }
        XCTAssertEqual(impressions, 12)

    }

    func testMissingNullAndUnknownContainerRenderSingleHorizontalRow() throws {
        for field in ["", ",\"productContainerType\":null", ",\"productContainerType\":\"future\""] {
            let builder = GridTestBuilder()
            GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
            let style = try JSONDecoder().decode(Style.self, from: Data("{\"size\":{\"height\":100}\(field)}".utf8))
            let content = makeContent(slots: try makeSlots(count: 4), style: style)
            let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 800))
            window.rootViewController = host
            window.makeKeyAndVisible()
            settle(host)
            XCTAssertEqual(builder.frames.count, 4)
            let first = try XCTUnwrap(builder.frames["0"])
            for index in 1..<4 {
                let frame = try XCTUnwrap(builder.frames[String(index)])
                XCTAssertEqual(frame.minY, first.minY, accuracy: 0.5)
                XCTAssertGreaterThan(frame.minX, first.minX)
            }
            window.isHidden = true
        }
        GravitySDK.initialize(apiKey: "", section: "")
    }

    /// Grids and rows without products take no space despite a configured height.
    func testMissingSlotsTakeNoSpace() throws {
        for kind in [ProductContainerType.grid, .row] {
            for missingProducts in [false, true] {
                let style = Style(size: GravitySize(height: 173), productContainerType: kind)
                let content = CampaignContent(contentId: "missing", deliveryMethod: .inline, contentType: "test", step: nil,
                    variables: Variables(elements: [Element(type: .productsContainer, style: style)]),
                    products: missingProducts ? nil : Products(strategyId: "test", fallback: false, name: nil, slots: nil, pageNumber: nil, countPages: nil))
                let host = UIHostingController(rootView: VStack(spacing: 0) {
                    GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in })
                    Color.clear.frame(height: 19)
                })
                XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 360, height: 2000)).height,
                               19, accuracy: 0.5, "\(kind) missingProducts=\(missingProducts)")
            }
        }
    }

    func testEmptyGridHasZeroHeightEvenWithPaddingAndMargin() throws {
        GravitySDK.initialize(apiKey: "", section: "")
        let content = makeContent(slots: [], style: Style(margin: GravityMargin(left: 8, right: 8, top: 8, bottom: 8), padding: GravityPadding(left: 10, right: 10, top: 10, bottom: 10), productContainerType: .grid))
        let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }))
        let size = host.sizeThatFits(in: CGSize(width: 360, height: 2000))
        XCTAssertEqual(size.height, 0, accuracy: 0.5)
    }

    func testGridUsesFilteredSlots() throws {
        let builder = GridTestBuilder()
        GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder, productFilter: { $0.slotId == "1" })
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let products = try JSONDecoder().decode(Products.self, from: Data("{\"strategyId\":\"test\",\"fallback\":false,\"slots\":[{\"item\":{},\"strId\":0,\"slotId\":\"0\",\"fallback\":false},{\"item\":{},\"strId\":1,\"slotId\":\"1\",\"fallback\":false}]}".utf8))
        let content = makeContent(slots: try XCTUnwrap(products.slots), style: Style(productContainerType: .grid))
        let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 800))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(host)
        XCTAssertEqual(Set(builder.frames.keys), Set(["1"]))
    }

    func testSpacingCompressesToFitNarrowProposals() throws {
        let builder = GridTestBuilder()
        GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        for (columns, width) in [(10.0, 50.0), (4.0, 20.0)] {
            let style = Style(size: GravitySize(width: 164, height: 250), padding: GravityPadding(left: 10, right: 10), productContainerType: .grid, gridSettings: GridSettings(columns: columns, horizontalSpacing: 12))
            let content = makeContent(slots: try makeSlots(count: 5), style: style)
            let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }))
            let size = host.sizeThatFits(in: CGSize(width: width, height: 5000))
            XCTAssertLessThanOrEqual(size.width, width + 0.5)
            XCTAssertTrue(size.height.isFinite)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 800))
            window.rootViewController = host
            window.makeKeyAndVisible()
            settle(host)
            for frame in builder.frames.values {
                XCTAssertGreaterThanOrEqual(frame.minX, 9.5)
                XCTAssertLessThanOrEqual(frame.maxX, width - 9.5)
            }
            window.isHidden = true
            builder.frames.removeAll()
        }
    }

    func testDuplicateSlotIdsKeepEveryOccurrenceButDeduplicateImpressions() throws {
        let builder = GridTestBuilder()
        var impressions = 0
        GravitySDK.initialize(apiKey: "", section: "", gravityEventCallback: { event in
            if event is ProductImpressionEvent { impressions += 1 }
        }, productViewBuilder: builder)
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let slots = try (0..<5).map { index in
            try JSONDecoder().decode(Slot.self, from: Data("{\"item\":{},\"strId\":\(index),\"slotId\":\(index < 3 ? "\"x\"" : "null"),\"fallback\":false}".utf8))
        }
        let style = Style(productContainerType: .grid)
        let host = UIHostingController(rootView: GridTestHost(content: makeContent(slots: slots, style: style), campaign: Campaign(), builder: builder))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 1000))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(host)
        XCTAssertEqual(Set(builder.occurrenceFrames.keys), Set(0..<5))
        XCTAssertEqual(impressions, 1)
        let originalFirst = try XCTUnwrap(builder.occurrenceFrames[0])
        host.rootView = GridTestHost(content: makeContent(slots: Array(slots.reversed()), style: style), campaign: Campaign(), builder: builder)
        settle(host)
        XCTAssertEqual(Set(builder.occurrenceFrames.keys), Set(0..<5))
        // Missing slot IDs never emit; duplicate real IDs share one impression.
        XCTAssertEqual(impressions, 1)
        XCTAssertEqual(try XCTUnwrap(builder.occurrenceFrames[0]).minY - originalFirst.minY, 368, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(builder.occurrenceFrames[4]).minY, originalFirst.minY, accuracy: 0.5)
    }

    func testOversizedCardsAreClippedToCells() throws {
        GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: OversizedGridTestBuilder())
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let content = makeContent(slots: try makeSlots(count: 2), style: Style(backgroundColor: .red, productContainerType: .grid, gridSettings: GridSettings(horizontalSpacing: 12)))
        let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }).frame(maxHeight: .infinity, alignment: .top).background(Color.green))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 700))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(host)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { context in
            host.view.layer.render(in: context.cgContext)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel = [UInt8](repeating: 0, count: 4)
        let y = Int(host.view.safeAreaInsets.top + 80)
        let sample = try XCTUnwrap(cgImage.cropping(to: CGRect(x: 160, y: y, width: 1, height: 1)))
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let attachment = XCTAttachment(image: image)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(Int(pixel[1]), Int(pixel[0]) + 40)
        XCTAssertGreaterThan(Int(pixel[1]), Int(pixel[2]) + 40)
    }

    func testVisibilityTracksAllocatedCellInsteadOfOversizedCard() throws {
        var impressions = 0
        GravitySDK.initialize(apiKey: "", section: "", gravityEventCallback: { event in
            if event is ProductImpressionEvent { impressions += 1 }
        }, productViewBuilder: OversizedGridTestBuilder(height: 4000))
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let content = makeContent(slots: try makeSlots(count: 1), style: Style(productContainerType: .grid))
        let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }).frame(width: 168).frame(maxHeight: .infinity, alignment: .top))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(host)
        XCTAssertEqual(impressions, 1)
    }

    func testLegacyCardsUseGridProposalAndKeepRowIntrinsicSize() throws {
        for type in [ProductContainerType.grid, .row] {
            let builder = FlexibleLegacyGridTestBuilder()
            GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
            defer { GravitySDK.initialize(apiKey: "", section: "") }
            let style = Style(size: GravitySize(width: 164, height: 250), productContainerType: type, gridSettings: GridSettings(horizontalSpacing: 12))
            let content = makeContent(slots: try makeSlots(count: 2), style: style)
            let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }).frame(width: 320).frame(maxHeight: .infinity, alignment: .top))
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            settle(host)
            let card = try XCTUnwrap(builder.cards.first)
            XCTAssertEqual(card.bounds.width, type == .grid ? 154 : 164, accuracy: 0.5)
            XCTAssertEqual(card.bounds.height, type == .grid ? 154 : 250, accuracy: 0.5)
        }
    }

    func testImageCardsFillGridAndKeepIntrinsicSizeInFullscreenRowsWithoutHeight() throws {
        for (width, count) in [(320.0, 1), (320.0, 2), (440.0, 1), (440.0, 2)] {
            let builder = ImageCardTestBuilder()
            GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
            let content = makeContent(slots: try makeSlots(count: count), style: Style(size: GravitySize(width: 164, height: 250), productContainerType: .grid, gridSettings: GridSettings(horizontalSpacing: 12)))
            let host = UIHostingController(rootView: GravityElements(content: content, campaign: Campaign(), onClickCallback: { _ in }).frame(width: width).frame(maxHeight: .infinity, alignment: .top))
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            settle(host)
            for card in builder.cards {
                card.imageView.image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600)).image { context in
                    UIColor.blue.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
                }
            }
            settle(host)
            let card = try XCTUnwrap(builder.cards.first)
            let cellWidth = (width - 12) / 2
            XCTAssertEqual(card.bounds.width, cellWidth, accuracy: 0.5)
            XCTAssertEqual(card.bounds.height, cellWidth, accuracy: 0.5)
            XCTAssertGreaterThan(card.imageView.bounds.height, 10)
            XCTAssertLessThanOrEqual(card.nameLabel.frame.maxY, card.bounds.height + 0.5)
            XCTAssertLessThanOrEqual(card.priceLabel.frame.maxY, card.bounds.height + 0.5)
            XCTAssertGreaterThan(card.nameLabel.bounds.height, 10)
            XCTAssertGreaterThan(card.priceLabel.bounds.height, 10)
            window.isHidden = true
        }
        let builder = ImageCardTestBuilder()
        GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let content = makeContent(slots: try makeSlots(count: 2), style: Style(productContainerType: .row))
        let host = UIHostingController(rootView: GravityFullScreenContent(content: content, campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onClickCallback: { _ in }))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(host)
        let card = try XCTUnwrap(builder.cards.first)
        XCTAssertEqual(card.bounds.width, 164, accuracy: 0.5)
        XCTAssertEqual(card.bounds.height, 250, accuracy: 0.5)
    }

}
