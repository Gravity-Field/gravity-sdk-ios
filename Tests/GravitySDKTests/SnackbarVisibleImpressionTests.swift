import XCTest
import SwiftUI
import UIKit
@testable import GravitySDK

final class SnackbarVisibleImpressionTests: XCTestCase {
    @MainActor private func fixture(template: TemplateSystemName = .snackbar1, variables: Bool = true, callback: GravityEventCallback? = nil, timing: PresentationTiming = PresentationTiming()) -> (TemporarySDKFixture, GravitySDK, CampaignContent, Campaign) {
        let fixture = TemporarySDKFixture()
        let sdk = GravitySDK(apiKey: fixture.apiKey, section: fixture.section, gravityEventCallback: callback,
            productViewBuilder: nil, productFilter: nil, uiSettings: nil,
            visibleImpressionStore: VisibleImpressionStore(fileURL: fixture.root.appendingPathComponent("queue.json")),
            presentationTiming: timing)
        GravitySDK.initialize(sdk)
        let content = CampaignContent(contentId: "snackbar", templateSystemName: template,
            deliveryMethod: .snackBar, contentType: "test", step: 0,
            variables: variables ? Variables(frameUI: FrameUI(container: Container()),
                elements: [Element(type: .text, text: "Snackbar")]) : nil,
            events: [Event(type: .visibleImpression, urls: ["http://127.0.0.1:9/wrimp"])])
        let campaign = Campaign(payload: [CampaignVariation(campaignId: "campaign", experienceId: "e", variationId: "v", decisionId: "d")])
        return (fixture, sdk, content, campaign)
    }

    @MainActor private func probes(in view: UIView) -> [ModalFrameProbe.FrameView] {
        (view as? ModalFrameProbe.FrameView).map { [$0] } ?? view.subviews.flatMap { probes(in: $0) }
    }

    @MainActor func testBothSnackbarTemplatesMountContentVisibilityProbeAndShareOpening() async throws {
        for template in [TemplateSystemName.snackbar1, .snackbar2] {
            let (fixture, sdk, content, campaign) = fixture(template: template)
            _ = fixture
            var confirmations = 0
            var releases = 0
            let appeared = expectation(description: "rendered snackbar confirmed by production display link")
            let opening = ModalImpressionSession(confirm: {
                confirmations += 1; appeared.fulfill(); return true
            }, release: { releases += 1 })
            let controller = UIViewController()
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            XCTAssertTrue(sdk.showBackendContent(controller, content, campaign, impressionSession: opening))
            await fulfillment(of: [appeared], timeout: 10)
            let probe = try XCTUnwrap(probes(in: controller.view).first,
                "Rendered snackbar must use the production content visibility tracker")
            XCTAssertTrue(opening.hasFired)
            probe.sample()
            XCTAssertNil(probe.displayLink)
            for _ in 0..<20 { opening.confirmFrame(isActive: true); opening.explicitClose() }
            let closed = expectation(description: "snackbar removed")
            sdk.dismissInApp(contentId: content.contentId) { XCTAssertTrue($0); closed.fulfill() }
            await fulfillment(of: [closed], timeout: 10)
            probe.sample()
            XCTAssertNil(probe.displayLink)
            XCTAssertEqual(confirmations, 1)
            XCTAssertEqual(releases, 0)
            XCTAssertTrue(probes(in: controller.view).isEmpty)
        }
    }

    @MainActor func testConfirmedSnackbarEnqueuesOneDurableWRIMPAndAutoCloseKeepsProtection() async throws {
        var visible = 0
        var closed = 0
        let appeared = expectation(description: "durable snackbar visibility callback")
        let dismissed = expectation(description: "snackbar auto closed")
        let (fixture, sdk, content, campaign) = fixture(callback: { event in
            if event is ContentVisibleImpressionEvent { visible += 1; appeared.fulfill() }
            if event is ContentCloseEvent { closed += 1; dismissed.fulfill() }
        })
        _ = fixture
        await sdk.visibleImpressionDelivery.stop()
        let request = sdk.presentationGate.beginRequest(location: "snackbar", newScreen: true)
        let reservation = try XCTUnwrap(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        let opening = sdk.makeModalImpressionSession(content, campaign)
        let controller = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertTrue(sdk.presentationGate.present(reservation, contentIds: [content.contentId]) {
            sdk.showBackendContent(controller, content, campaign, impressionSession: opening)
        })
        await fulfillment(of: [appeared], timeout: 10)
        XCTAssertTrue(opening.hasFired)
        _ = try XCTUnwrap(probes(in: controller.view).first)
        for _ in 0..<20 { opening.confirmFrame(isActive: true); opening.explicitClose() }
        await sdk.visibleImpressionDelivery.store?.waitForPendingWrites()
        XCTAssertEqual(visible, 1)
        XCTAssertEqual(sdk.visibleImpressionDelivery.store?.entries.count, 1)
        // The production four-second timer closes the view; pending offline WRIMP survives.
        await fulfillment(of: [dismissed], timeout: 15)
        XCTAssertTrue(controller.children.isEmpty)
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(visible, 1)
        XCTAssertEqual(sdk.visibleImpressionDelivery.store?.entries.count, 1)
        XCTAssertNil(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        sdk.setUser(userId: "next-user", sessionId: "next-session")
        let next = sdk.presentationGate.beginRequest(location: "snackbar", newScreen: true)
        XCTAssertNotNil(sdk.presentationGate.reserve(campaignId: "campaign", request: next),
            "The previous user's pending WRIMP must not block the next user")
    }

    @MainActor func testCloseBeforeVisibleFrameReleasesReservationWithoutWRIMP() async throws {
        var impressions = 0
        let (fixture, sdk, content, campaign) = fixture(callback: { event in
            if event is ContentImpressionEvent { impressions += 1 }
        })
        _ = fixture
        let request = sdk.presentationGate.beginRequest(location: "snackbar", newScreen: true)
        let reservation = try XCTUnwrap(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        let opening = sdk.makeModalImpressionSession(content, campaign)
        let controller = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        // Attach the content to a transparent window: it has no rendered visible frame.
        window.makeKeyAndVisible()
        window.alpha = 0
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertTrue(sdk.presentationGate.present(reservation, contentIds: [content.contentId]) {
            sdk.showBackendContent(controller, content, campaign, impressionSession: opening)
        })
        await waitForUI("transparent snackbar mounted") { !self.probes(in: controller.view).isEmpty }
        XCTAssertFalse(opening.hasFired)
        let closed = expectation(description: "early close")
        sdk.dismissInApp(contentId: content.contentId) { XCTAssertTrue($0); closed.fulfill() }
        await fulfillment(of: [closed], timeout: 10)
        await nextMainTurn()
        XCTAssertFalse(opening.hasFired)
        XCTAssertEqual(impressions, 0, "A transparent window never showed a frame")
        XCTAssertTrue(sdk.visibleImpressionDelivery.store?.entries.isEmpty == true)
        XCTAssertNotNil(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
    }

    @MainActor func testModalIdentityChangeBeforeFirstVisibleFrameDropsWRIMP() async throws {
        for change in ["setUser", "resetUser", "restoreUserId"] {
            var visible = 0
            let (fixture, sdk, snackbar, campaign) = fixture(callback: { event in
                if event is ContentVisibleImpressionEvent { visible += 1 }
            })
            await sdk.visibleImpressionDelivery.stop()
            let modal = CampaignContent(contentId: "modal-identity", deliveryMethod: .modal,
                contentType: "native", step: 0, variables: snackbar.variables, events: snackbar.events)
            let opening = sdk.makeModalImpressionSession(modal, campaign)
            let host = UIViewController()
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.alpha = 0
            defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
            XCTAssertTrue(sdk.showBackendContent(host, modal, campaign, impressionSession: opening))
            await waitForUI("modal presented before its visible frame") { host.presentedViewController != nil }
            switch change {
            case "setUser": sdk.setUser(userId: "next-user", sessionId: "next-session")
            case "resetUser": try await sdk.resetUser()
            default: try await sdk.restoreUserId("restored-user")
            }
            window.alpha = 1
            // Drive the same session used by the mounted modal tracker explicitly;
            // the identity guard must reject it even if a visible frame now arrives.
            opening.confirmFrame(isActive: true)
            opening.explicitClose()
            await sdk.visibleImpressionDelivery.store?.waitForPendingWrites()
            XCTAssertFalse(opening.hasFired, change)
            XCTAssertEqual(visible, 0, change)
            XCTAssertTrue(sdk.visibleImpressionDelivery.store?.entries.isEmpty == true, change)
            sdk.dismissInApp(contentId: modal.contentId)
            withExtendedLifetime(fixture) {}
        }
    }

    @MainActor func testIdentityChangeBeforeFirstFrameCannotEnqueueOldSnackbarImpression() async throws {
        var visible = 0
        let (fixture, sdk, content, campaign) = fixture(callback: { event in
            if event is ContentVisibleImpressionEvent { visible += 1 }
        })
        _ = fixture
        let opening = sdk.makeModalImpressionSession(content, campaign)
        let controller = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.alpha = 0
        XCTAssertTrue(sdk.showBackendContent(controller, content, campaign, impressionSession: opening))
        await waitForUI("hidden snackbar probe mounted") { !self.probes(in: controller.view).isEmpty }
        let probe = try XCTUnwrap(probes(in: controller.view).first)
        sdk.setUser(userId: "next-user", sessionId: "next-session")
        window.alpha = 1
        defer { window.isHidden = true; window.rootViewController = nil }
        probe.sample()
        XCTAssertNil(probe.displayLink)
        await nextMainTurn()
        XCTAssertEqual(visible, 0)
        XCTAssertTrue(sdk.visibleImpressionDelivery.store?.entries.isEmpty == true,
            "A frame rendered after the identity changed must not enqueue the old opening")
        sdk.dismissInApp(contentId: content.contentId)
    }

    @MainActor func testMissingSnackbarFrameDoesNotMountVisibilityProbe() async throws {
        let (fixture, sdk, content, campaign) = fixture(variables: false)
        _ = fixture
        let opening = ModalImpressionSession(confirm: { XCTFail("Missing content is not visible"); return false }, release: {})
        let controller = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertFalse(sdk.showBackendContent(controller, content, campaign, impressionSession: opening))
        XCTAssertTrue(probes(in: controller.view).isEmpty)
        XCTAssertFalse(opening.hasFired)
        sdk.dismissInApp(contentId: content.contentId)
    }
    @MainActor func testSnackbarRequiresOneSecondAndEarlyCloseCannotSendWRIMP() async throws {
        var clock: TimeInterval = 0
        var impressions = 0
        var visible = 0
        let first = expectation(description: "actual first snackbar frame")
        let closed = expectation(description: "early physical close")
        let (fixture, sdk, content, campaign) = fixture(callback: { event in
            if event is ContentImpressionEvent { impressions += 1; first.fulfill() }
            if event is ContentVisibleImpressionEvent { visible += 1 }
            if event is ContentCloseEvent { closed.fulfill() }
        }, timing: PresentationTiming(now: { clock }))
        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertTrue(sdk.showBackendContent(host, content, campaign))
        await fulfillment(of: [first], timeout: 10)
        let probe = try XCTUnwrap(probes(in: host.view).first)
        XCTAssertEqual(impressions, 1)
        XCTAssertEqual(visible, 0, "A frozen first frame cannot satisfy a one-second interval")
        sdk.dismissInApp(contentId: content.contentId)
        await fulfillment(of: [closed], timeout: 10)
        clock = 10
        probe.sample()
        await sdk.visibleImpressionDelivery.store?.waitForPendingWrites()
        XCTAssertEqual(visible, 0)
        XCTAssertTrue(sdk.visibleImpressionDelivery.store?.entries.isEmpty == true)
        withExtendedLifetime(fixture) {}
    }

    @MainActor func testSnackbarReappearanceSendsOnlyOneImpression() async throws {
        var impressions = 0
        let first = expectation(description: "first actual snackbar appearance")
        let repeated = expectation(description: "no second impression after reappearance")
        repeated.isInverted = true
        let (fixture, sdk, content, campaign) = fixture(callback: { event in
            if event is ContentImpressionEvent {
                impressions += 1
                if impressions == 1 { first.fulfill() } else { repeated.fulfill() }
            }
        })
        let snackbar = GravitySnackbarContent(content: content, campaign: campaign,
            impressionSession: sdk.makeModalImpressionSession(content, campaign), visibilityClock: { 0 },
            onClickCallback: { _ in }, onDismiss: {})
        let host = UIHostingController(rootView: snackbar)
        let navigation = UINavigationController(rootViewController: host)
        let signal = SnackbarNavigationSignal()
        navigation.delegate = signal
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [first], timeout: 10)
        let other = UIViewController()
        let covered = expectation(description: "navigation covered snackbar")
        signal.didShow = { if $0 === other { covered.fulfill() } }
        navigation.pushViewController(other, animated: false)
        await fulfillment(of: [covered], timeout: 10)
        let uncovered = expectation(description: "navigation restored snackbar")
        signal.didShow = { if $0 === host { uncovered.fulfill() } }
        navigation.popViewController(animated: false)
        await fulfillment(of: [uncovered], timeout: 10)
        await fulfillment(of: [repeated], timeout: 1)
        XCTAssertEqual(impressions, 1)
        withExtendedLifetime((fixture, signal)) {}
    }

    @MainActor func testMissingWindowFailsAndReleasesReservation() throws {
        let (fixture, sdk, content, campaign) = fixture()
        let request = sdk.presentationGate.beginRequest(location: "missing-window", newScreen: true)
        let reservation = try XCTUnwrap(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        XCTAssertFalse(sdk.presentationGate.present(reservation, contentIds: [content.contentId]) {
            sdk.showBackendContent(UIViewController(), content, campaign)
        })
        XCTAssertNotNil(sdk.presentationGate.reserve(campaignId: "campaign", request: request))
        withExtendedLifetime(fixture) {}
    }

    @MainActor func testProgrammaticDismissBeforeAppearanceRemovesWithoutAnyTracking() async throws {
        try await checkProgrammaticDismiss(appeared: false)
    }

    @MainActor func testProgrammaticDismissAfterAppearanceClosesExactlyOnce() async throws {
        try await checkProgrammaticDismiss(appeared: true)
    }

    @MainActor private func checkProgrammaticDismiss(appeared: Bool) async throws {
        for configured in [false, true] {
            let server = try RecordingServer()
            try await server.start()
            defer { server.stop() }
            let fixture = TemporarySDKFixture()
            var impressions = 0
            var closes = 0
            let impression = expectation(description: "impression only after appearance")
            impression.isInverted = !appeared
            let closed = expectation(description: "close only after appearance")
            closed.isInverted = !appeared
            let noVisible = expectation(description: "early dismissal has no WRIMP")
            noVisible.isInverted = true
            let closeURL = expectation(description: "configured close URL only after appearance")
            closeURL.isInverted = !(appeared && configured)
            let impressionURL = expectation(description: "impression URL only after appearance")
            impressionURL.isInverted = !appeared
            server.observeRequests { request in
                if request.path == "/close" { closeURL.fulfill() }
                if request.path == "/impression" { impressionURL.fulfill() }
            }
            let sdk = fixture.initialize(callback: { event in
                if event is ContentImpressionEvent { impressions += 1; impression.fulfill() }
                if event is ContentCloseEvent { closes += 1; closed.fulfill() }
                if event is ContentVisibleImpressionEvent { noVisible.fulfill() }
            })
            let content = CampaignContent(contentId: "dismiss-appearance", templateSystemName: .snackbar1,
                deliveryMethod: .snackBar, contentType: "native", step: 0,
                variables: Variables(frameUI: FrameUI(container: Container()),
                    elements: [Element(type: .text, text: "Dismiss")],
                    onImpression: ContentActionModel(action: .impression),
                    onClose: configured ? ContentActionModel(action: .close) : nil),
                events: [Event(type: .close, urls: [server.url + "/close"]),
                    Event(type: .impression, urls: [server.url + "/impression"])])
            let campaign = Campaign(payload: [CampaignVariation(campaignId: "dismiss-campaign", experienceId: "e", variationId: "v", decisionId: "d")])
            let host = UIViewController()
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            if !appeared { host.view.alpha = 0 } // Deterministically prevent the first rendered frame.
            let request = sdk.presentationGate.beginRequest(location: "dismiss", newScreen: true)
            let reservation = try XCTUnwrap(sdk.presentationGate.reserve(campaignId: "dismiss-campaign", request: request))
            XCTAssertTrue(sdk.presentationGate.present(reservation, contentIds: [content.contentId]) {
                sdk.showBackendContent(host, content, campaign)
            })
            let child = try XCTUnwrap(host.children.first)
            if appeared { await fulfillment(of: [impression], timeout: 10) }
            let removed = expectation(description: "completion follows physical removal")
            sdk.dismissInApp(contentId: content.contentId) { success in
                XCTAssertTrue(success)
                XCTAssertNil(child.parent)
                XCTAssertNil(child.view.superview)
                removed.fulfill()
            }
            await fulfillment(of: [removed], timeout: 3)
            let repeated = expectation(description: "second dismissal finds nothing")
            sdk.dismissInApp(contentId: content.contentId) { success in
                XCTAssertFalse(success)
                repeated.fulfill()
            }
            await fulfillment(of: [repeated], timeout: 3)
            XCTAssertNotNil(sdk.presentationGate.reserve(campaignId: "dismiss-campaign", request: request),
                "Both tracked and untracked removal release the reservation")
            await fulfillment(of: (appeared ? [] : [impression]) + [closed, noVisible, closeURL, impressionURL], timeout: 1)
            XCTAssertEqual(impressions, appeared ? 1 : 0)
            XCTAssertEqual(closes, appeared ? 1 : 0)
            XCTAssertEqual(server.recorded.filter { $0.path == "/impression" }.count, appeared ? 1 : 0)
            XCTAssertEqual(server.recorded.filter { $0.path == "/close" }.count, appeared && configured ? 1 : 0)
            withExtendedLifetime(fixture) {}
        }
    }

    @MainActor func testAllSnackbarClosePathsTrackCloseAtMostOnce() async throws {
        for cause in ["programmatic", "button", "timer"] {
            for configured in [false, true] {
                let server = try RecordingServer()
                try await server.start()
                defer { server.stop() }
                let fixture = TemporarySDKFixture()
                var closes = 0
                let first = expectation(description: "first snackbar frame")
                let closed = expectation(description: "one close callback")
                let shouldTrack = configured || cause == "button"
                let delivered = shouldTrack ? expectation(description: "expected close URL") : nil
                let unexpected = expectation(description: "no duplicate/unconfigured close URL")
                unexpected.isInverted = true
                var requests = 0
                server.observeRequests { request in
                    guard request.path == "/close" else { return }
                    requests += 1
                    if shouldTrack && requests == 1 { delivered?.fulfill() } else { unexpected.fulfill() }
                }
                let sdk = fixture.initialize(callback: { event in
                    if event is ContentImpressionEvent { first.fulfill() }
                    if event is ContentCloseEvent { closes += 1; closed.fulfill() }
                })
                let content = CampaignContent(contentId: "close", templateSystemName: .snackbar1,
                    deliveryMethod: .snackBar, contentType: "native", step: 0,
                    variables: Variables(frameUI: FrameUI(container: Container()), elements: [Element(type: .text, text: "Close")],
                        onClose: configured ? ContentActionModel(action: .close) : nil),
                    events: [Event(type: .close, urls: [server.url + "/close"])])
                let campaign = Campaign(payload: [CampaignVariation(campaignId: "close", experienceId: "e", variationId: "v", decisionId: "d")])
                let host = UIViewController()
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                XCTAssertTrue(sdk.showBackendContent(host, content, campaign))
                await fulfillment(of: [first], timeout: 10)
                if cause == "button" {
                    let child = try XCTUnwrap(host.children.first as? UIHostingController<GravitySnackbarContent>)
                    child.rootView.onClickCallback(OnClickModel(action: .close))
                    child.rootView.onClickCallback(OnClickModel(action: .close))
                } else if cause == "programmatic" {
                    sdk.dismissInApp(contentId: content.contentId)
                }
                await fulfillment(of: [closed] + (delivered.map { [$0] } ?? []), timeout: 15)
                await fulfillment(of: [unexpected], timeout: 1)
                XCTAssertEqual(closes, 1)
                XCTAssertEqual(server.recorded.filter { $0.path == "/close" }.count, shouldTrack ? 1 : 0)
                withExtendedLifetime(fixture) {}
            }
        }
    }

    @MainActor func testOpenStepFromSnackbarToModalKeepsOneDurableWRIMP() async throws {
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        let fixture = TemporarySDKFixture()
        let sdk = fixture.initialize()
        let variables = Variables(frameUI: FrameUI(container: Container()), elements: [Element(type: .text, text: "Step")])
        let snackbar = CampaignContent(contentId: "snack-step", templateSystemName: .snackbar1, deliveryMethod: .snackBar,
            contentType: "native", step: 0, variables: variables, events: [Event(type: .visibleImpression, urls: [server.url + "/wrimp"])])
        let modal = CampaignContent(contentId: "modal-step", deliveryMethod: .modal, contentType: "native", step: 1,
            variables: variables, events: [Event(type: .visibleImpression, urls: [server.url + "/second-wrimp"])])
        let campaign = Campaign(payload: [CampaignVariation(campaignId: "steps", experienceId: "e", variationId: "v", decisionId: "d", contents: [snackbar, modal])])
        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { host.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil }
        XCTAssertTrue(sdk.showBackendContent(host, snackbar, campaign))
        _ = await server.waitFor(1, timeout: 10)
        let child = try XCTUnwrap(host.children.first as? UIHostingController<GravitySnackbarContent>)
        child.rootView.onClickCallback(OnClickModel(action: .openStep, step: 1))
        await waitForUI("modal step presented") { host.presentedViewController != nil }
        XCTAssertNotNil(host.presentedViewController)
        XCTAssertEqual(server.recorded.filter { $0.path == "/wrimp" || $0.path == "/second-wrimp" }.map(\.path), ["/wrimp"])
        withExtendedLifetime(fixture) {}
    }
    @MainActor func testAttachedSnackbarKeepsCountingAcrossLockAndTrackView() async throws {
        for (change, phase) in [("lock", "before"), ("lock", "after"), ("trackView", "before"), ("trackView", "after")] {
            var impressions = 0
            var visible = 0
            var closes = 0
            var clock: TimeInterval = 0
            var order: [String] = []
            let visibleSignal = expectation(description: "durable visible callback")
            let closeSignal = expectation(description: "one close callback")
            let (fixture, sdk, content, campaign) = fixture(callback: { event in
                if event is ContentImpressionEvent { impressions += 1; order.append("impression") }
                if event is ContentVisibleImpressionEvent { visible += 1; order.append("visible"); visibleSignal.fulfill() }
                if event is ContentCloseEvent { closes += 1; order.append("close"); closeSignal.fulfill() }
            }, timing: PresentationTiming(now: { clock }))
            try await sdk.resetUser()
            await sdk.visibleImpressionDelivery.stop()
            let server = try RecordingServer()
            try await server.start()
            defer { server.stop(); sdk.unlockPresentation() }
            server.reset(responseUser: ["uid": "r4-server-uid", "ses": "r4-server-session"])
            sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
            let opening = sdk.makeModalImpressionSession(content, campaign)
            let host = UIViewController()
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.alpha = 0
            defer { window.isHidden = true; window.rootViewController = nil }
            XCTAssertTrue(sdk.showBackendContent(host, content, campaign, impressionSession: opening))
            await waitForFrame("attached snackbar probe") { !self.probes(in: host.view).isEmpty }
            let probe = try XCTUnwrap(probes(in: host.view).first)
            if phase == "after" {
                window.alpha = 1
                await waitForFrame("first snackbar frame before navigation or lock") {
                    ModalFrameProbe.FrameView.contentIsVisible(rendered: probe.layer.presentation(), window: window,
                        applicationIsActive: true, sceneIsActive: true)
                }
                probe.sample()
                XCTAssertEqual(impressions, 1)
            }
            if change == "lock" { sdk.lockPresentation() }
            else {
                let task = try XCTUnwrap(sdk.trackViewTask(
                    pageContext: PageContext(type: .other, data: [], location: "r4-next-screen"), viewController: host))
                await task.value
                let uid = await sdk.getUserId()
                XCTAssertEqual(uid, "r4-server-uid")
            }
            XCTAssertTrue(opening.isValid, change)
            window.alpha = 1
            await waitForFrame("snackbar frame committed after navigation or lock") {
                ModalFrameProbe.FrameView.contentIsVisible(rendered: probe.layer.presentation(), window: window,
                    applicationIsActive: true, sceneIsActive: true)
            }
            probe.sample()
            XCTAssertEqual(impressions, 1, change)
            clock = 1.1
            probe.sample()
            await fulfillment(of: [visibleSignal], timeout: 10)
            await sdk.visibleImpressionDelivery.store?.waitForPendingWrites()
            XCTAssertEqual(visible, 1, change)
            XCTAssertEqual(sdk.visibleImpressionDelivery.store?.entries.count, 1, change)
            XCTAssertEqual(sdk.visibleImpressionDelivery.store?.entries.first?.scope, sdk.impressionScope,
                "Delivery binds the current anonymous UID without treating it as an explicit user change")
            sdk.dismissInApp(contentId: content.contentId)
            await fulfillment(of: [closeSignal], timeout: 10)
            XCTAssertEqual(closes, 1)
            XCTAssertEqual(order, ["impression", "visible", "close"], change)
            withExtendedLifetime(fixture) {}
        }
    }

    @MainActor func testFocusAfterLastCommittedFrameKeepsPollingUntilVisible() async throws {
        var focused = false
        var clock: TimeInterval = 0
        var impressions = 0
        var visible = 0
        let opening = ModalImpressionSession(confirm: { visible += 1; return true }, release: {})
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let probe = ModalFrameProbe.FrameView(session: opening, activity: { _ in (focused, focused) },
            minimumVisibleFraction: 0.5, visibleDuration: 1, now: { clock },
            onFirstVisibleFrame: { impressions += 1 })
        probe.frame = window.bounds
        host.view.addSubview(probe)
        await waitForFrame("last frame committed while inactive") { probe.layer.presentation() != nil }
        probe.sample()
        XCTAssertEqual(impressions, 0)
        XCTAssertNotNil(probe.displayLink, "Inactive samples keep polling, independent of future draw events")
        // No layout or draw request: only activity changes, then the existing tick samples again.
        focused = true
        clock = 100
        probe.sample()
        XCTAssertEqual(impressions, 1)
        clock = 101.1
        probe.sample()
        XCTAssertEqual(visible, 1)
        XCTAssertNil(probe.displayLink)
    }

    @MainActor func testSnackbarFractionAndContinuousActiveDuration() async throws {
        var confirmations = 0
        var active = true
        var clock: TimeInterval = 0
        let frame = expectation(description: "probe has a committed visible frame")
        let opening = ModalImpressionSession(confirm: { confirmations += 1; return true }, release: {})
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let probe = ModalFrameProbe.FrameView(session: opening, activity: { _ in (active, active) },
            minimumVisibleFraction: 0.5, visibleDuration: 1, now: { clock }, onFirstVisibleFrame: { frame.fulfill() })
        probe.frame = CGRect(x: 0, y: 120, width: 200, height: 200)
        host.view.addSubview(probe)
        await fulfillment(of: [frame], timeout: 10)
        clock = 10
        probe.sample()
        XCTAssertEqual(confirmations, 0, "40 percent is insufficient regardless of elapsed time")
        probe.frame.origin.y = 100
        await waitForUI("half-visible geometry committed") { probe.layer.presentation()?.frame == probe.layer.frame }
        probe.sample()
        clock = 10.6
        probe.sample()
        active = false
        probe.sample()
        active = true
        clock = 20
        probe.sample()
        clock = 20.9
        probe.sample()
        XCTAssertEqual(confirmations, 0, "Background resets the continuous visibility interval")
        clock = 21.1
        probe.sample()
        XCTAssertEqual(confirmations, 1)
    }

    @MainActor func testLifecycleNotificationResetsVisibilityEvenWhenDisplayLinkPaused() async throws {
        var confirmations = 0
        var clock: TimeInterval = 0
        let frame = expectation(description: "probe has a committed visible frame")
        let opening = ModalImpressionSession(confirm: { confirmations += 1; return true }, release: {})
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let probe = ModalFrameProbe.FrameView(session: opening, activity: { _ in (true, true) },
            minimumVisibleFraction: 0.5, visibleDuration: 1, now: { clock }, onFirstVisibleFrame: { frame.fulfill() })
        probe.frame = window.bounds
        host.view.addSubview(probe)
        await fulfillment(of: [frame], timeout: 10)
        clock = 0.6
        probe.sample()
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        clock = 1.2
        probe.sample()
        clock = 1.8
        probe.sample()
        XCTAssertEqual(confirmations, 0, "Visibility before background must not count after resume")
        clock = 2.3
        probe.sample()
        XCTAssertEqual(confirmations, 1)
    }

    @MainActor func testXReviewFullyOccludedSnackbarMustNotCountAsVisible() async throws {
        var impressions = 0
        var visible = 0
        var clock: TimeInterval = 0
        let visibleCallback = expectation(description: "uncovered snackbar visible-impression callback")
        visibleCallback.assertForOverFulfill = true
        let (fixture, sdk, content, campaign) = fixture(callback: { event in
            if event is ContentImpressionEvent { impressions += 1 }
            if event is ContentVisibleImpressionEvent { visible += 1; visibleCallback.fulfill() }
        }, timing: PresentationTiming(now: { clock }))
        await sdk.visibleImpressionDelivery.stop()
        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertTrue(sdk.showBackendContent(host, content, campaign))
        let cover = UIView(frame: window.bounds)
        cover.backgroundColor = .black
        cover.isOpaque = true
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(cover)
        await waitForFrame("snackbar and opaque covering sibling committed") {
            guard let p = self.probes(in: host.view).first else { return false }
            return cover.layer.presentation() != nil && ModalFrameProbe.FrameView.contentIsVisible(rendered: p.layer.presentation(), window: window, applicationIsActive: true, sceneIsActive: true)
        }
        let probe = try XCTUnwrap(probes(in: host.view).first)
        XCTAssertTrue(host.view.subviews.last === cover)
        XCTAssertTrue(cover.bounds.contains(probe.convert(probe.bounds, to: cover)))
        probe.sample()
        clock = 1.1
        probe.sample()
        await sdk.visibleImpressionDelivery.store?.waitForPendingWrites()
        XCTAssertEqual(impressions, 0, "Fully occluded snackbar has never appeared to the user")
        XCTAssertEqual(visible, 0, "No 50%-visible interval occurred")
        XCTAssertEqual(sdk.visibleImpressionDelivery.store?.entries.count, 0)
        cover.removeFromSuperview()
        probe.sample()
        await waitForFrame("uncovered snackbar impression callback") { impressions == 1 }
        XCTAssertEqual(impressions, 1)
        XCTAssertEqual(visible, 0)
        clock = 2.2
        probe.sample()
        await sdk.visibleImpressionDelivery.store?.waitForPendingWrites()
        await fulfillment(of: [visibleCallback], timeout: 10)
        XCTAssertEqual(impressions, 1)
        XCTAssertEqual(visible, 1)
        XCTAssertEqual(sdk.visibleImpressionDelivery.store?.entries.count, 1)
        sdk.dismissInApp(contentId: content.contentId)
        withExtendedLifetime(fixture) {}
    }

    @MainActor func testSharedModalProbeRestartsIntervalAfterOpaqueCover() async throws {
        var active = false
        var clock: TimeInterval = 0
        var firstFrames = 0
        var confirmed = 0
        let opening = ModalImpressionSession(confirm: { confirmed += 1; return true }, release: {})
        let window = UIWindow(frame: UIScreen.main.bounds)
        let modal = UIViewController()
        window.rootViewController = modal
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let probe = ModalFrameProbe.FrameView(session: opening, activity: { _ in (active, active) },
            minimumVisibleFraction: 0.5, visibleDuration: 1, now: { clock },
            onFirstVisibleFrame: { firstFrames += 1 })
        probe.frame = CGRect(x: window.bounds.midX - 40, y: window.bounds.midY - 40, width: 80, height: 80)
        modal.view.addSubview(probe)
        let cover = UIView(frame: window.bounds)
        cover.backgroundColor = .black
        cover.isUserInteractionEnabled = false // Hit testing alone misses this cover.
        modal.view.addSubview(cover)
        await waitForFrame("modal probe and opaque cover committed") {
            probe.layer.presentation() != nil && cover.layer.presentation() != nil
        }
        active = true
        probe.sample()
        clock = 2
        probe.sample()
        XCTAssertEqual(firstFrames, 0)
        XCTAssertEqual(confirmed, 0)
        cover.removeFromSuperview()
        probe.sample()
        XCTAssertEqual(firstFrames, 1)
        XCTAssertEqual(confirmed, 0)
        clock = 2.5
        probe.sample()
        modal.view.addSubview(cover)
        await waitForFrame("cover committed again") { cover.layer.presentation() != nil }
        clock = 10
        probe.sample()
        XCTAssertEqual(confirmed, 0, "An opaque cover resets the partial visible interval")
        cover.removeFromSuperview()
        probe.sample()
        clock = 10.6
        probe.sample()
        XCTAssertEqual(confirmed, 0, "Covered time does not count toward the threshold")
        clock = 11.1
        probe.sample()
        XCTAssertEqual(firstFrames, 1)
        XCTAssertEqual(confirmed, 1)
        probe.sample()
        XCTAssertEqual(confirmed, 1)
    }

    @MainActor func testTopPresentedModalDoesNotOccludeItselfBehindAnotherPresentation() async throws {
        var active = false
        var confirmed = 0
        let root = OcclusionPresentationController()
        let first = OcclusionPresentationController()
        let top = OcclusionPresentationController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        // Package tests lack a UIWindowScene for native present(). Model only the
        // UIKit presentation relationships; all views and committed layers are real.
        root.nextPresented = first
        first.nextPresented = top
        first.view.frame = window.bounds
        top.view.frame = window.bounds
        root.view.addSubview(first.view)
        root.view.addSubview(top.view)
        let opening = ModalImpressionSession(confirm: { confirmed += 1; return true }, release: {})
        let probe = ModalFrameProbe.FrameView(session: opening, activity: { _ in (active, active) })
        probe.frame = CGRect(x: window.bounds.midX - 40, y: window.bounds.midY - 40, width: 80, height: 80)
        top.view.addSubview(probe)
        await waitForFrame("stacked presentation layers committed") {
            first.view.layer.presentation() != nil && top.view.layer.presentation() != nil && probe.layer.presentation() != nil
        }
        active = true
        probe.sample()
        XCTAssertEqual(confirmed, 1, "Only a controller above the content may occlude it")
    }

    @MainActor private func waitForFrame(_ description: String, _ predicate: @escaping () -> Bool) async {
        let frame = expectation(description: description)
        let signal = SnackbarFrameSignal(condition: predicate) { frame.fulfill() }
        signal.start()
        defer { signal.stop() }
        await fulfillment(of: [frame], timeout: 10)
    }

    @MainActor private func waitForUI(_ description: String, _ predicate: @escaping () -> Bool) async {
        let signal = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        signal.expectationDescription = description
        await fulfillment(of: [signal], timeout: 10)
    }

    @MainActor private func nextMainTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

private final class SnackbarNavigationSignal: NSObject, UINavigationControllerDelegate {
    var didShow: (UIViewController) -> Void = { _ in }
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        didShow(viewController)
    }
}

@MainActor private final class SnackbarFrameSignal: NSObject {
    private let condition: () -> Bool
    private let fulfilled: () -> Void
    private var link: CADisplayLink?
    init(condition: @escaping () -> Bool, fulfilled: @escaping () -> Void) {
        self.condition = condition
        self.fulfilled = fulfilled
    }
    func start() {
        let link = CADisplayLink(target: self, selector: #selector(sample))
        self.link = link
        link.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil }
    @objc private func sample() {
        guard condition() else { return }
        stop()
        fulfilled()
    }
}

private final class OcclusionPresentationController: UIViewController {
    var nextPresented: UIViewController?
    override var presentedViewController: UIViewController? { nextPresented }
}
