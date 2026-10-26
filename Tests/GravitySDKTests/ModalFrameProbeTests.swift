import XCTest
import SwiftUI
import UIKit
@testable import GravitySDK

final class ModalFrameProbeTests: XCTestCase {
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
            GravitySDK.initialize(apiKey: "probe-logs", section: UUID().uuidString)
            var errors = 0
            GravitySDK.instance.logListener = { level, message in
                if level == .error && message.contains("[ContentEvent]") { errors += 1 }
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
            for _ in 0..<100 { probe.sample(); opening.explicitClose(isActive: true) }
            XCTAssertTrue(opening.hasFired)
            XCTAssertNil(probe.displayLink)
            XCTAssertEqual(errors, 1)
            await fulfillment(of: [callback], timeout: 1)
            XCTAssertTrue(store.entries.isEmpty)
            opening.disappeared()
            XCTAssertNotNil(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        }
    }
}
