import XCTest
import SwiftUI
import UIKit
@testable import GravitySDK

final class ModalFrameProbeTests: XCTestCase {
    @MainActor func testRealDisplayLinkConfirmsSwiftUIContent() async throws {
        let confirmed = expectation(description: "real display-link confirms rendered SwiftUI content")
        let opening = ModalImpressionSession(confirm: { confirmed.fulfill(); return true }, release: {})
        // Package tests have no UIWindowScene. Only activity is supplied; sample(), the
        // CADisplayLink and the committed SwiftUI/Core Animation presentation tree are real.
        let host = UIHostingController(rootView: Color.red.frame(width: 180, height: 120)
            .overlay(ModalFrameProbe(session: opening, activity: { _ in (true, true) })))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [confirmed], timeout: 3)
        XCTAssertTrue(opening.hasFired)
    }

    @MainActor func testSwiftUIRemovalBeforeContentAppearanceDoesNotConfirm() async throws {
        let mounted = expectation(description: "transparent SwiftUI content mounted")
        let released = expectation(description: "transparent content removed")
        let opening = ModalImpressionSession(confirm: { XCTFail("Invisible content is not an impression"); return false },
            release: { released.fulfill() })
        let host = UIHostingController(rootView: AnyView(ModalContentVisibilityTracker(session: opening) {
            Color.red.frame(width: 180, height: 120).onAppear { mounted.fulfill() }
        }.opacity(0)))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [mounted], timeout: 2)
        host.rootView = AnyView(EmptyView())
        await fulfillment(of: [released], timeout: 2)
        XCTAssertFalse(opening.hasFired)
    }

    @MainActor func testCustomSheetBindingClosesBeforeContentDisappears() async throws {
        let mounted = expectation(description: "sheet mounted")
        let appeared = expectation(description: "sheet content appeared")
        let dismissed = expectation(description: "sheet finished dismissing")
        let removed = expectation(description: "sheet content removed")
        let state = SheetState()
        var callbacks: [String] = []
        let host = UIHostingController(rootView: SheetHarness(state: state,
            mounted: { mounted.fulfill() }, appeared: { appeared.fulfill() },
            willDismiss: { callbacks.append("willDismiss") },
            disappeared: { callbacks.append("disappeared"); removed.fulfill() },
            dismissed: { callbacks.append("dismissed"); dismissed.fulfill() }))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [mounted], timeout: 2)
        state.isPresented = true
        await fulfillment(of: [appeared], timeout: 2)
        // Swipe and backdrop both set this production binding; exercise its real onChange.
        state.isPresented = false
        await fulfillment(of: [dismissed], timeout: 2)
        XCTAssertEqual(callbacks.first, "willDismiss")
        await fulfillment(of: [removed], timeout: 2)
        XCTAssertEqual(callbacks.first, "willDismiss")
        XCTAssertEqual(callbacks.filter { $0 == "willDismiss" }.count, 1)
    }

    @MainActor func testContentIntersectionOpacityAndActiveSceneUseProductionProbePredicate() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.isHidden = false
        defer { window.isHidden = true }
        let parent = CALayer()
        parent.frame = window.bounds
        window.layer.addSublayer(parent)
        let content = CALayer()
        parent.addSublayer(content)
        func visible(active: Bool = true, scene: Bool = true) -> Bool {
            ModalFrameProbe.FrameView.contentIsVisible(rendered: content, window: window,
                applicationIsActive: active, sceneIsActive: scene)
        }
        content.frame = CGRect(x: 0, y: 200, width: 200, height: 100) // bottom-sheet preroll
        XCTAssertFalse(visible())
        content.frame.origin.y = 199 // first exposed strip, no 50% or duration threshold
        XCTAssertTrue(visible())
        parent.opacity = 0
        XCTAssertFalse(visible())
        parent.opacity = 1
        parent.isHidden = true
        XCTAssertFalse(visible())
        parent.isHidden = false
        XCTAssertFalse(visible(active: false))
        XCTAssertFalse(visible(scene: false))
        XCTAssertFalse(ModalFrameProbe.FrameView.contentIsVisible(rendered: nil, window: window,
            applicationIsActive: true, sceneIsActive: true))
    }

    @MainActor func testProductionSessionStopsMountedProbeAndPreservesCallbackOnMissingUrlOrDiskFailure() async throws {
        for diskFails in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let file = root.appendingPathComponent("queue.json")
            defer { try? FileManager.default.removeItem(at: root) }
            if diskFails { try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true) }
            let store = VisibleImpressionStore(fileURL: file, log: { _ in })
            let callback = expectation(description: diskFails ? "disk failure callback" : "missing URL callback")
            callback.assertForOverFulfill = true
            let fixture = TemporarySDKFixture()
            fixture.initialize()
            let diagnostic = expectation(description: "one local persistence diagnostic")
            diagnostic.assertForOverFulfill = true
            GravitySDK.instance.logListener = { level, message in
                if level == .error && message.contains("[ContentEvent]") { diagnostic.fulfill() }
            }
            defer { GravitySDK.instance.logListener = nil }
            let sdk = GravitySDK(apiKey: "probe", section: "probe", gravityEventCallback: { event in
                if event is ContentVisibleImpressionEvent { callback.fulfill() }
            }, productViewBuilder: nil, productFilter: nil, uiSettings: nil, visibleImpressionStore: store)
            let content = CampaignContent(contentId: "content", deliveryMethod: .modal, contentType: "test", step: 0,
                events: diskFails ? [Event(type: .visibleImpression, urls: ["https://tracking.test/event"])] : [])
            let campaign = Campaign(payload: [CampaignVariation(campaignId: "campaign", experienceId: "e", variationId: "v", decisionId: "d")])
            let request = sdk.presentationGate.beginRequest(location: "home", newScreen: true)
            let reservation = try XCTUnwrap(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
            XCTAssertTrue(sdk.presentationGate.present(reservation, contentIds: [content.contentId]) { true })
            let opening = sdk.makeModalImpressionSession(content, campaign) // actual presenter factory
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            let rootController = UIViewController()
            window.rootViewController = rootController
            window.isHidden = false
            defer { window.isHidden = true }
            let probe = ModalFrameProbe.FrameView(session: opening)
            probe.frame = window.bounds
            rootController.view.addSubview(probe)
            XCTAssertNotNil(probe.displayLink)
            // Supply a confirmed frame: layer visibility is independently tested above.
            opening.confirmFrame(isActive: true)
            for _ in 0..<100 { probe.sample(); opening.explicitClose() }
            XCTAssertTrue(opening.hasFired)
            XCTAssertNil(probe.displayLink)
            await fulfillment(of: [callback, diagnostic], timeout: 1)
            XCTAssertTrue(store.entries.isEmpty)
            opening.disappeared()
            XCTAssertNil(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        }
    }
}

private final class SheetState: ObservableObject {
    @Published var isPresented = false
}

private struct SheetHarness: View {
    @ObservedObject var state: SheetState
    let mounted: () -> Void
    let appeared: () -> Void
    let willDismiss: () -> Void
    let disappeared: () -> Void
    let dismissed: () -> Void

    var body: some View {
        CustomSheet(isPresented: $state.isPresented, cornerRadius: 8, imagePrerollDelay: 0,
            onWillDismiss: willDismiss, onDismiss: dismissed) {
            Color.red.frame(height: 180).onAppear(perform: appeared).onDisappear(perform: disappeared)
        }.onAppear(perform: mounted)
    }
}
