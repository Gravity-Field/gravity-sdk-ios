import XCTest
import UIKit
@testable import GravitySDK

@MainActor
final class SheetDragGestureTests: XCTestCase {
    private final class Pan: UIPanGestureRecognizer {
        var testVelocity = CGPoint.zero
        override func velocity(in view: UIView?) -> CGPoint { testVelocity }
    }
    private final class Touch: UITouch {
        var source: UIView?
        var point = CGPoint(x: 40, y: 40)
        override var view: UIView? { source }
        override func location(in view: UIView?) -> CGPoint { point }
    }

    func testDirectionAndOutsideSheet() {
        let probe = SheetDragGesture.Probe()
        probe.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        let touch = Touch()
        touch.source = probe
        let pan = Pan()
        XCTAssertTrue(probe.gestureRecognizer(pan, shouldReceive: touch))
        for (velocity, expected) in [(CGPoint(x: 0, y: 100), true), (CGPoint(x: 20, y: 100), true),
                                     (CGPoint(x: 0, y: -100), false), (CGPoint(x: 100, y: 20), false),
                                     (CGPoint(x: -100, y: 100), false), (.zero, false)] {
            pan.testVelocity = velocity
            XCTAssertEqual(probe.gestureRecognizerShouldBegin(pan), expected, "velocity \(velocity)")
        }
        touch.point = CGPoint(x: 40, y: 401)
        XCTAssertFalse(probe.gestureRecognizer(pan, shouldReceive: touch))
        pan.testVelocity = CGPoint(x: 0, y: 100)
        XCTAssertFalse(probe.gestureRecognizerShouldBegin(pan))
        let scroll = UIScrollView()
        XCTAssertFalse(probe.gestureRecognizer(pan, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
    }

    func testScrollTopToleranceDirectionAndFailurePriority() {
        let probe = SheetDragGesture.Probe()
        probe.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        let scroll = UIScrollView(frame: probe.bounds)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset.top = 59
        scroll.contentSize = CGSize(width: 300, height: 1500)
        probe.addSubview(scroll)
        let cell = UIView(frame: scroll.bounds)
        scroll.addSubview(cell)
        let touch = Touch()
        touch.source = cell
        let pan = Pan()
        XCTAssertTrue(probe.gestureRecognizer(pan, shouldReceive: touch))
        for offset in [-65.0, -59, -57.4, -57, -56, 0, 200] {
            scroll.contentOffset.y = offset
            for velocity in [CGPoint(x: 0, y: 150), CGPoint(x: 0, y: -150), CGPoint(x: 150, y: 10)] {
                pan.testVelocity = velocity
                XCTAssertEqual(probe.gestureRecognizerShouldBegin(pan), offset <= -57 && velocity.y > abs(velocity.x))
                // The scroll waits for the sheet's decision even when that decision is refusal.
                XCTAssertTrue(probe.gestureRecognizer(pan, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
            }
        }
        XCTAssertFalse(probe.gestureRecognizer(pan, shouldBeRequiredToFailBy: UITapGestureRecognizer()))
        let unrelatedPan = UIPanGestureRecognizer()
        cell.addGestureRecognizer(unrelatedPan)
        XCTAssertFalse(probe.gestureRecognizer(pan, shouldBeRequiredToFailBy: unrelatedPan))
        probe.stop()
        XCTAssertFalse(probe.gestureRecognizerShouldBegin(pan))
        XCTAssertFalse(probe.gestureRecognizer(pan, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
    }

    func testHorizontalProductRowDoesNotHideScrolledVerticalAncestor() {
        let probe = SheetDragGesture.Probe()
        probe.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        let vertical = UIScrollView(frame: probe.bounds)
        vertical.contentSize = CGSize(width: 300, height: 1500)
        probe.addSubview(vertical)
        let row = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 120))
        row.contentSize = CGSize(width: 1200, height: 120)
        vertical.addSubview(row)
        let touch = Touch()
        touch.source = row
        let pan = Pan()
        pan.testVelocity = CGPoint(x: 0, y: 100)
        XCTAssertTrue(probe.gestureRecognizer(pan, shouldReceive: touch))
        vertical.contentOffset.y = 100
        XCTAssertFalse(probe.gestureRecognizerShouldBegin(pan))
        vertical.contentOffset.y = 0
        XCTAssertTrue(probe.gestureRecognizerShouldBegin(pan))
    }
}
