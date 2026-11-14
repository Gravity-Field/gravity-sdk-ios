import XCTest
import SwiftUI
import ObjectiveC
@testable import GravitySDK

final class ModalCloseAppearanceTests: XCTestCase {
    @MainActor func testExternalRemovalBeforeContentFrameOmitsCloseWithAndWithoutWRIMP() async throws {
        try await checkRemoval(confirmed: false)
    }

    @MainActor func testExternalRemovalAfterContentFrameClosesWithoutRequiringWRIMPPersistence() async throws {
        try await checkRemoval(confirmed: true)
    }

    @MainActor private func checkRemoval(confirmed: Bool) async throws {
        for method in [DeliveryMethod.modal, .fullScreen, .bottomSheet] {
            for hasURL in [false, true] {
                let fixture = TemporarySDKFixture()
                let closed = expectation(description: "close \(method) confirmed=\(confirmed) wrimp=\(hasURL)")
                closed.isInverted = !confirmed
                let sdk = fixture.initialize(callback: { if $0 is ContentCloseEvent { closed.fulfill() } })
                let server = try RecordingServer()
                try await server.start()
                defer { server.stop() }
                let events = [Event(type: .close, urls: [server.url + "/close"])]
                    + (hasURL ? [Event(type: .visibleImpression, urls: [server.url + "/visible"])] : [])
                let content = CampaignContent(contentId: "appearance", deliveryMethod: method, contentType: "native", step: nil,
                    variables: Variables(frameUI: FrameUI(container: Container()), elements: [Element(type: .text, text: "Close")],
                        onClose: ContentActionModel(action: .close)), events: events)
                let opening = sdk.makeModalImpressionSession(content, Campaign())
                let host = UIViewController()
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                XCTAssertTrue(sdk.showBackendContent(host, content, Campaign(), impressionSession: opening))
                let presented = try XCTUnwrap(host.presentedViewController)
                presented.viewDidAppear(false)
                if confirmed { opening.confirmFrame(isActive: true) }
                presented.viewDidDisappear(false)
                presented.viewDidDisappear(false)
                await fulfillment(of: [closed], timeout: confirmed ? 2 : 0.1)
                _ = await server.waitFor(confirmed ? 1 : 0, timeout: 0.2)
                // A WRIMP request may arrive first; wait for close delivery separately.
                if confirmed {
                    let deadline = Date().addingTimeInterval(2)
                    while !server.recorded.contains(where: { $0.path == "/close" }), Date() < deadline {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                }
                XCTAssertEqual(server.recorded.filter { $0.path == "/close" }.count, confirmed ? 1 : 0)
            }
        }
    }

    @MainActor func testHostThatNeverAppearedDoesNotReportExternalRemoval() {
        let host = InAppHostingController(rootView: Text("not appeared"))
        var removals = 0
        host.onExternalRemoval = { removals += 1 }
        host.viewDidDisappear(false)
        XCTAssertEqual(removals, 0)
    }

    @MainActor func testDisappearanceWhileHostRemainsAttachedDoesNotReportExternalRemoval() throws {
        let fixture = TemporarySDKFixture()
        let sdk = fixture.initialize()
        let content = CampaignContent(contentId: "covered", deliveryMethod: .modal, contentType: "native", step: nil)
        let root = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertTrue(sdk.showBackendContent(root, content, Campaign()))
        let host = try XCTUnwrap(root.presentedViewController as? InAppHostingController<GravityModalContent>)
        // Unhosted XCTest leaves presentation pending; attach its view explicitly
        // while preserving the real UIKit presenter relationship.
        window.addSubview(host.view)
        host.viewDidAppear(false)
        XCTAssertNotNil(host.presentingViewController)
        XCTAssertNotNil(host.view.window)
        XCTAssertFalse(host.isBeingDismissed)
        var removals = 0
        host.onExternalRemoval = { removals += 1 }
        host.viewDidDisappear(false)
        XCTAssertEqual(removals, 0)
    }

    @MainActor func testCoveredHostWithoutWindowDoesNotReportExternalRemoval() throws {
        let root = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let host = InAppHostingController(rootView: Text("covered"))
        root.present(host, animated: false)
        host.beginAppearanceTransition(true, animated: false)
        host.endAppearanceTransition()
        let cover = UIViewController()

        // Unhosted XCTest cannot complete the second UIKit presentation. Stub
        // only this host's cover getter; all other controllers use the original
        // implementation, and restoration happens before window teardown.
        let selector = #selector(getter: UIViewController.presentedViewController)
        let method = try XCTUnwrap(class_getInstanceMethod(UIViewController.self, selector))
        let original = method_getImplementation(method)
        typealias Getter = @convention(c) (UIViewController, Selector) -> UIViewController?
        let originalGetter = unsafeBitCast(original, to: Getter.self)
        let getter: @convention(block) (UIViewController) -> UIViewController? = { controller in
            controller === host ? cover : originalGetter(controller, selector)
        }
        let replacement = imp_implementationWithBlock(getter)
        method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }

        host.view.removeFromSuperview()
        XCTAssertTrue(host.presentingViewController === root)
        XCTAssertTrue(host.presentedViewController === cover)
        XCTAssertFalse(host.isBeingDismissed)
        XCTAssertNil(host.view.window)
        var removals = 0
        host.onExternalRemoval = { removals += 1 }
        host.viewDidDisappear(false)
        XCTAssertEqual(removals, 0)
    }

}
