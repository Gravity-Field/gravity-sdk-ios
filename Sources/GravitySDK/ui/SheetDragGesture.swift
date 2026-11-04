import SwiftUI
import UIKit

/// Downward drags at the top belong to the sheet. Other directions and drags
/// within scrolled content remain with UIScrollView, without simultaneous bounce.
internal struct SheetDragGesture: UIViewRepresentable {
    let isEnabled: Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.changed = changed
        uiView.ended = ended
        uiView.pan.isEnabled = isEnabled
    }
    static func dismantleUIView(_ uiView: Probe, coordinator: ()) { uiView.stop() }

    final class Probe: UIView, UIGestureRecognizerDelegate {
        var changed: (CGFloat) -> Void = { _ in }
        var ended: (CGFloat, CGFloat) -> Void = { _, _ in }
        private(set) lazy var pan: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            gesture.delegate = self
            gesture.maximumNumberOfTouches = 1
            return gesture
        }()
        private weak var originScroll: UIScrollView?
        private var receivesTouch = false

        init() { super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            window?.addGestureRecognizer(pan)
        }
        func stop() {
            pan.view?.removeGestureRecognizer(pan)
            originScroll = nil
            receivesTouch = false
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            receivesTouch = bounds.contains(touch.location(in: self))
            originScroll = nil
            var ancestor = touch.view
            while let view = ancestor {
                if let scroll = view as? UIScrollView,
                   scroll.contentSize.height > scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom {
                    originScroll = scroll
                    break
                }
                ancestor = view.superview
            }
            return receivesTouch
        }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: window)
            guard receivesTouch, velocity.y > 0, velocity.y > abs(velocity.x) else { return false }
            guard let scroll = originScroll else { return true }
            // UIKit/SwiftUI can round the resting offset near adjusted safe-area insets.
            return scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 2
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            return receivesTouch && other is UIPanGestureRecognizer && other.view is UIScrollView
        }
        @objc private func handle(_ gesture: UIPanGestureRecognizer) {
            let translation = max(0, gesture.translation(in: window).y)
            switch gesture.state {
            case .began, .changed: changed(translation)
            case .ended: ended(translation, gesture.velocity(in: window).y)
            case .cancelled, .failed: ended(0, 0)
            default: break
            }
        }
    }
}
