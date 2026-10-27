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

internal struct ModalFrameProbe: UIViewRepresentable {
    let session: ModalImpressionSession
    var activity: (UIWindow) -> (app: Bool, scene: Bool) = currentActivity

    static func currentActivity(_ window: UIWindow) -> (app: Bool, scene: Bool) {
        (UIApplication.shared.applicationState == .active, window.windowScene?.activationState == .foregroundActive)
    }

    func makeUIView(context: Context) -> FrameView { FrameView(session: session, activity: activity) }
    func updateUIView(_ uiView: FrameView, context: Context) {}
    static func dismantleUIView(_ uiView: FrameView, coordinator: ()) { uiView.stop() }

    final class FrameView: UIView {
        private final class TickTarget: NSObject {
            weak var view: FrameView?
            @objc func tick() { view?.sample() }
        }

        private let session: ModalImpressionSession
        private let activity: (UIWindow) -> (app: Bool, scene: Bool)
        private let target = TickTarget()
        private(set) var displayLink: CADisplayLink?

        init(session: ModalImpressionSession,
             activity: @escaping (UIWindow) -> (app: Bool, scene: Bool) = ModalFrameProbe.currentActivity) {
            self.session = session
            self.activity = activity
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

        func sample() {
            if session.hasFired { stop(); return }
            guard let window else { return }
            let state = activity(window)
            guard Self.contentIsVisible(
                rendered: layer.presentation(), window: window,
                applicationIsActive: state.app, sceneIsActive: state.scene
            ) else { return }
            session.confirmFrame(isActive: true)
            stop()
        }

        static func contentIsVisible(rendered: CALayer?, window: UIWindow,
                                     applicationIsActive: Bool, sceneIsActive: Bool) -> Bool {
            guard applicationIsActive, sceneIsActive, !window.isHidden, window.alpha > 0,
                  let rendered, !rendered.bounds.isEmpty else { return false }
            var ancestor: CALayer? = rendered
            while let current = ancestor {
                guard !current.isHidden, current.opacity > 0 else { return false }
                ancestor = current.superlayer
            }
            let windowLayer = window.layer.presentation() ?? window.layer
            let frame = rendered.convert(rendered.bounds, to: windowLayer)
            let intersection = frame.intersection(window.bounds)
            return !intersection.isNull && !intersection.isEmpty
        }
    }
}
