import XCTest
import SwiftUI
@testable import GravitySDK

@MainActor
final class ProductsHostScrollingTests: ProductsGridTestCase {
    func testFullscreenClipsScrolledProductsToSafeArea() throws {
        let builder = GridTestBuilder()
        GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let content = makeContent(slots: try makeSlots(count: 9), style: Style(productContainerType: .grid), frameStyle: Style(backgroundColor: .green))
        let host = UIHostingController(rootView: GravityFullScreenContent(content: content, campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onClickCallback: { _ in }))
        host.additionalSafeAreaInsets.top = 24 // Exercise clipping even on devices with no native top inset.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        settle(host)
        let safeFrame = host.view.safeAreaLayoutGuide.layoutFrame
        XCTAssertGreaterThan(safeFrame.minY, 0)
        let first = try XCTUnwrap(builder.frames["0"])
        let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
        scroll.setContentOffset(CGPoint(x: 0, y: first.height / 2), animated: false)
        settle(host)

        // Geometry frames still extend offscreen after clipping. Check the pixels
        // actually painted above the viewport, where the status bar is displayed.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { context in
            host.view.layer.render(in: context.cgContext)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        for (y, expectsGreen) in [(safeFrame.minY / 2, true), (safeFrame.minY + 4, false)] {
            let sample = try XCTUnwrap(cgImage.cropping(to: CGRect(x: first.midX, y: y, width: 1, height: 1)))
            var pixel = [UInt8](repeating: 0, count: 4)
            try pixel.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            if expectsGreen {
                XCTAssertGreaterThan(Int(pixel[1]), Int(pixel[2]) + 40, "Scrolled cards must not paint beneath the status bar")
            } else {
                XCTAssertGreaterThan(Int(pixel[2]), Int(pixel[1]) + 40, "Cards remain visible inside the safe viewport")
            }
        }
    }

    func testFullscreenScrollsTallGridAndPreservesShortContentAlignment() throws {
        for count in [1, 9] {
            let builder = GridTestBuilder()
            GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
            defer { GravitySDK.initialize(apiKey: "", section: "") }
            let frameStyle = Style(padding: GravityPadding(left: 10, right: 10, top: 12, bottom: 20), verticalAlignment: .center)
            let content = makeContent(slots: try makeSlots(count: count), style: Style(productContainerType: .grid), frameStyle: frameStyle)
            let host = UIHostingController(rootView: GravityFullScreenContent(content: content, campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onClickCallback: { _ in }))
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            settle(host)
            let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
            let safeFrame = host.view.safeAreaLayoutGuide.layoutFrame
            XCTAssertEqual(scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom, safeFrame.height + host.view.safeAreaInsets.bottom - 32, accuracy: 0.5)
            if count == 1 {
                let first = try XCTUnwrap(builder.frames["0"])
                XCTAssertEqual(first.width, (window.bounds.width - 28) / 2, accuracy: 0.5)
                XCTAssertEqual(first.minY, safeFrame.minY + 12 + (safeFrame.height + host.view.safeAreaInsets.bottom - 32 - first.height) / 2, accuracy: 0.5)
                XCTAssertLessThanOrEqual(scroll.contentSize.height, scroll.bounds.height + 0.5)
                XCTAssertFalse(scroll.isScrollEnabled)
                XCTAssertFalse(scroll.alwaysBounceVertical)
            } else {
                XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
                XCTAssertTrue(scroll.isScrollEnabled)
                XCTAssertTrue(scroll.bounces)
                scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom), animated: false)
                settle(host)
                let last = try XCTUnwrap(builder.frames["8"])
                XCTAssertEqual(last.maxY, window.bounds.maxY - 20, accuracy: 0.5)
            }
        }
    }

    func testBottomSheetPreservesShortHeightAndCapsTallContent() async throws {
        for count in [1, 9] {
            let builder = GridTestBuilder()
            GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
            defer { GravitySDK.initialize(apiKey: "", section: "") }
            let content = makeContent(slots: try makeSlots(count: count), style: Style(productContainerType: .grid), frameStyle: Style(padding: GravityPadding(left: 10, right: 10, top: 12, bottom: 20)))
            let host = UIHostingController(rootView: GravityBottomSheetContent(content: content, campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onBindClose: { _ in }, onClickCallback: { _ in }, onDismiss: {}))
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            await waitForLayout {
                host.view.layoutIfNeeded()
                guard let scroll = self.scrollViews(in: host.view).first else { return false }
                let expected = count == 1 ? (window.bounds.width - 28) / 2 + 32 : host.view.safeAreaLayoutGuide.layoutFrame.height
                return abs(scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom - expected) < 0.5
            }
            let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
            if count == 1 {
                XCTAssertEqual(scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom, (window.bounds.width - 28) / 2 + 32, accuracy: 0.5)
                XCTAssertEqual(scroll.contentSize.height, (window.bounds.width - 28) / 2 + 32, accuracy: 0.5)
                XCTAssertFalse(scroll.isScrollEnabled)
                XCTAssertFalse(scroll.alwaysBounceVertical)
            } else {
                XCTAssertEqual(scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom, host.view.safeAreaLayoutGuide.layoutFrame.height, accuracy: 0.5)
                XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
                XCTAssertTrue(scroll.isScrollEnabled)
                XCTAssertTrue(scroll.bounces)
                scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
                settle(host)
                XCTAssertGreaterThan(scroll.contentOffset.y, 0)
                let last = try XCTUnwrap(builder.frames["8"])
                XCTAssertLessThanOrEqual(last.maxY, scroll.convert(scroll.bounds, to: window).maxY + 0.5)
            }
        }
    }

    func testBottomSheetUsesConstrainedHostHeight() async throws {
        let builder = GridTestBuilder()
        GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: builder)
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let content = makeContent(slots: try makeSlots(count: 20), style: Style(productContainerType: .grid))
        let host = UIHostingController(rootView: GravityBottomSheetContent(content: content, campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onBindClose: { _ in }, onClickCallback: { _ in }, onDismiss: {})
            .frame(width: 260, height: 400).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await waitForLayout {
            guard let scroll = self.scrollViews(in: host.view).first else { return false }
            let viewport = scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom
            return abs(viewport - 400) < 0.5 && abs(scroll.bounds.width - 260) < 0.5
        }
        let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
        XCTAssertGreaterThan(scroll.contentSize.height, 400)
    }

    func testBottomSheetFirstProductImpressionAfterEntranceWithoutScrolling() async throws {
        let seen = expectation(description: "First visible sheet product")
        GravitySDK.initialize(apiKey: "", section: "", gravityEventCallback: { event in
            if event is ProductImpressionEvent { seen.fulfill() }
        }, productViewBuilder: GridTestBuilder())
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let content = makeContent(slots: try makeSlots(count: 1), style: Style(productContainerType: .grid))
        let host = UIHostingController(rootView: GravityBottomSheetContent(content: content, campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onBindClose: { _ in }, onClickCallback: { _ in }, onDismiss: {}))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [seen], timeout: 3)
    }

    func testFullscreenScrollConfigurationUpdatesWithoutRecreatingProductState() async throws {
        let builder = GridTestBuilder()
        var impressions = 0
        GravitySDK.initialize(apiKey: "", section: "", gravityEventCallback: { event in
            if event is ProductImpressionEvent { impressions += 1 }
        }, productViewBuilder: builder)
        defer { GravitySDK.initialize(apiKey: "", section: "") }
        let slots = try makeSlots(count: 9)
        let style = Style(productContainerType: .grid)
        let host = UIHostingController(rootView: GravityFullScreenContent(content: makeContent(slots: Array(slots.prefix(1)), style: style), campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onClickCallback: { _ in }))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await waitForLayout { impressions == 1 && self.scrollViews(in: host.view).first?.isScrollEnabled == false }
        let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
        XCTAssertFalse(scroll.isScrollEnabled)
        XCTAssertEqual(impressions, 1)
        host.rootView = GravityFullScreenContent(content: makeContent(slots: slots, style: style), campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onClickCallback: { _ in })
        await waitForLayout { scroll.isScrollEnabled && impressions > 1 }
        XCTAssertTrue(scroll === scrollViews(in: host.view).first)
        XCTAssertTrue(scroll.isScrollEnabled)
        let afterExpansion = impressions
        host.rootView = GravityFullScreenContent(content: makeContent(slots: Array(slots.prefix(1)), style: style), campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onClickCallback: { _ in })
        await waitForLayout { !scroll.isScrollEnabled && scroll.contentSize.height <= scroll.bounds.height + 0.5 }
        XCTAssertTrue(scroll === scrollViews(in: host.view).first)
        XCTAssertFalse(scroll.isScrollEnabled)
        XCTAssertEqual(impressions, afterExpansion)
    }

    func testLegacyScrollLockReassertsAfterLaterUIKitUpdates() {
        let scroll = UIScrollView()
        let configuration = LegacyScrollConfiguration.ScrollConfigurationView()
        scroll.addSubview(configuration)
        configuration.isScrollEnabled = false
        scroll.isScrollEnabled = true
        scroll.alwaysBounceVertical = true
        scroll.bounces = true
        XCTAssertFalse(scroll.isScrollEnabled)
        XCTAssertFalse(scroll.alwaysBounceVertical)
        XCTAssertFalse(scroll.bounces)
        configuration.isScrollEnabled = true
        scroll.isScrollEnabled = false
        scroll.alwaysBounceVertical = false
        scroll.bounces = false
        XCTAssertTrue(scroll.isScrollEnabled)
        XCTAssertTrue(scroll.alwaysBounceVertical)
        XCTAssertTrue(scroll.bounces)
    }

    func testFittingHostsKeepNestedProductRowsScrollable() throws {
        for isSheet in [false, true] {
            GravitySDK.initialize(apiKey: "", section: "", productViewBuilder: FlexibleLegacyGridTestBuilder())
            defer { GravitySDK.initialize(apiKey: "", section: "") }
            let content = makeContent(slots: try makeSlots(count: 8), style: Style(size: GravitySize(height: 250), productContainerType: .row))
            let root: AnyView
            if isSheet {
                root = AnyView(GravityBottomSheetContent(content: content, campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onBindClose: { _ in }, onClickCallback: { _ in }, onDismiss: {}))
            } else {
                root = AnyView(GravityFullScreenContent(content: content, campaign: Campaign(), impressionSession: ModalImpressionSession(confirm: { true }, release: {}), onClickCallback: { _ in }))
            }
            let host = UIHostingController(rootView: root)
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            settle(host)
            let scrolls = scrollViews(in: host.view)
            XCTAssertEqual(scrolls.count, 2)
            XCTAssertFalse(try XCTUnwrap(scrolls.first).isScrollEnabled)
            let row = try XCTUnwrap(scrolls.last)
            XCTAssertTrue(row.isScrollEnabled)
            XCTAssertGreaterThan(row.contentSize.width, row.bounds.width)
        }
    }
}
