import SwiftUI
import UIKit

/// Probes the content, never the scrim. The presentation layer reflects the frame
/// actually committed by UIKit/SwiftUI, including opening offsets and opacity.
struct ModalContentVisibilityTracker<Content: View>: View {
    let session: ModalImpressionSession
    @ViewBuilder let view: () -> Content

    var body: some View {
        view()
            .overlay(ModalFrameProbe(session: session).allowsHitTesting(false))
            .onDisappear { session.disappeared() }
    }
}

private struct ModalFrameProbe: UIViewRepresentable {
    let session: ModalImpressionSession

    func makeUIView(context: Context) -> FrameView { FrameView(session: session) }
    func updateUIView(_ uiView: FrameView, context: Context) {}
    static func dismantleUIView(_ uiView: FrameView, coordinator: ()) { uiView.stop() }

    final class FrameView: UIView {
        private final class TickTarget: NSObject {
            weak var view: FrameView?
            @objc func tick() { view?.sample() }
        }

        private let session: ModalImpressionSession
        private let target = TickTarget()
        private var displayLink: CADisplayLink?

        init(session: ModalImpressionSession) {
            self.session = session
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            target.view = self
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            guard window != nil, !session.hasFired else { return }
            let link = CADisplayLink(target: target, selector: #selector(TickTarget.tick))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        func stop() { displayLink?.invalidate(); displayLink = nil }
        deinit { stop() }

        private func sample() {
            if session.hasFired { stop(); return }
            guard UIApplication.shared.applicationState == .active,
                  let window, !window.isHidden, window.alpha > 0,
                  window.windowScene?.activationState == .foregroundActive,
                  let rendered = layer.presentation(), !rendered.bounds.isEmpty else { return }
            var ancestor: CALayer? = rendered
            while let current = ancestor {
                guard !current.isHidden, current.opacity > 0 else { return }
                ancestor = current.superlayer
            }
            let windowLayer = window.layer.presentation() ?? window.layer
            let frame = rendered.convert(rendered.bounds, to: windowLayer)
            let intersection = frame.intersection(window.bounds)
            guard !intersection.isNull, !intersection.isEmpty else { return }
            session.confirmFrame(isActive: true)
        }
    }
}
