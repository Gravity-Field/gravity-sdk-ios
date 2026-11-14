import XCTest
@testable import GravitySDK

final class InAppPresentationTests: XCTestCase {
    func testCompletionFollowsPhysicalCloseAndOnlyRunsOnce() {
        var events: [String] = []
        var finish: ((Bool) -> Void)?
        let presentation = InAppPresentation(performDismiss: { events.append("animate"); finish = $0 },
                                             didDismiss: { _ in events.append("close") })
        presentation.close { XCTAssertTrue($0); events.append("navigate") }
        XCTAssertEqual(events, ["animate"])
        presentation.close { XCTAssertFalse($0) }
        finish?(true)
        finish?(true)
        presentation.close { XCTAssertFalse($0) }
        XCTAssertEqual(events, ["animate", "close", "navigate"])
    }

    func testTargetingAndMissingContent() {
        let registry = InAppPresentationRegistry()
        var aClosed = false
        var bClosed = false
        let a = InAppPresentation(performDismiss: { aClosed = true; $0(true) }, didDismiss: { _ in })
        let b = InAppPresentation(performDismiss: { bClosed = true; $0(true) }, didDismiss: { _ in })
        registry.register(a, contentId: "A")
        registry.register(b, contentId: "B")
        registry.dismiss(contentId: "A") { XCTAssertTrue($0) }
        XCTAssertTrue(aClosed)
        XCTAssertFalse(bClosed)
        registry.dismiss(contentId: "inline") { XCTAssertFalse($0) }
    }

    func testOldPresentationCannotRemoveNewerOne() {
        let registry = InAppPresentationRegistry()
        let old = InAppPresentation(performDismiss: { $0(true) }, didDismiss: { _ in })
        let new = InAppPresentation(performDismiss: { $0(true) }, didDismiss: { _ in })
        registry.register(old, contentId: "same")
        registry.register(new, contentId: "same")
        registry.remove(old, contentId: "same")
        registry.dismiss(contentId: "same") { XCTAssertTrue($0) }
    }

    func testExternalRemovalFinishesOnceWithoutRequestingAnotherDismissal() {
        var events: [String] = []
        let presentation = InAppPresentation(willClose: { events.append("visible") },
            performDismiss: { _ in XCTFail("The controller has already been removed") },
            didDismiss: { success in XCTAssertTrue(success); events.append("close") })
        presentation.removedExternally()
        presentation.removedExternally()
        presentation.close { XCTAssertFalse($0) }
        XCTAssertEqual(events, ["visible", "close"])
    }

    func testLifecycleDuringSDKDismissalPreservesCompletionAndOneClose() {
        var finish: ((Bool) -> Void)?
        var closes = 0
        var completions = 0
        let presentation = InAppPresentation(performDismiss: { finish = $0 }, didDismiss: { _ in closes += 1 })
        presentation.close { success in XCTAssertTrue(success); completions += 1 }
        presentation.removedExternally()
        XCTAssertEqual(closes, 0)
        finish?(true)
        presentation.removedExternally()
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(completions, 1)
    }

}
