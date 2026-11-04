import SwiftUI
import UIKit

/// Probes the content, never the scrim. The presentation layer reflects the frame
/// actually committed by UIKit/SwiftUI, including opening offsets and opacity.
struct ModalContentVisibilityTracker<Content: View>: View {
    let session: ModalImpressionSession
    var minimumVisibleFraction: CGFloat = 0
    var visibleDuration: TimeInterval = 0
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var onFirstVisibleFrame: (() -> Void)? = nil
    @ViewBuilder let view: () -> Content

    var body: some View {
        view()
            .overlay(ModalFrameProbe(session: session, minimumVisibleFraction: minimumVisibleFraction,
                visibleDuration: visibleDuration, now: now, onFirstVisibleFrame: onFirstVisibleFrame).allowsHitTesting(false))
            .onDisappear { session.disappeared() }
    }
}

internal struct ModalFrameProbe: UIViewRepresentable {
    let session: ModalImpressionSession
    var activity: (UIWindow) -> (app: Bool, scene: Bool) = currentActivity

    var minimumVisibleFraction: CGFloat = 0
    var visibleDuration: TimeInterval = 0
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var onFirstVisibleFrame: (() -> Void)? = nil

    static func currentActivity(_ window: UIWindow) -> (app: Bool, scene: Bool) {
        (UIApplication.shared.applicationState == .active, window.windowScene?.activationState == .foregroundActive)
    }

    func makeUIView(context: Context) -> FrameView { FrameView(session: session, activity: activity, minimumVisibleFraction: minimumVisibleFraction,
        visibleDuration: visibleDuration, now: now, onFirstVisibleFrame: onFirstVisibleFrame) }
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
        private let minimumVisibleFraction: CGFloat
        private let visibleDuration: TimeInterval
        private let clock: () -> TimeInterval
        private let onFirstVisibleFrame: (() -> Void)?
        private var notifiedFirstFrame = false
        private var visibleSince: CFTimeInterval?
        private(set) var displayLink: CADisplayLink?

        init(session: ModalImpressionSession,
             activity: @escaping (UIWindow) -> (app: Bool, scene: Bool) = ModalFrameProbe.currentActivity,
             minimumVisibleFraction: CGFloat = 0, visibleDuration: TimeInterval = 0,
             now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
             onFirstVisibleFrame: (() -> Void)? = nil) {
            self.session = session
            self.activity = activity
            self.minimumVisibleFraction = minimumVisibleFraction
            self.visibleDuration = visibleDuration
            self.clock = now
            self.onFirstVisibleFrame = onFirstVisibleFrame
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            target.view = self
            NotificationCenter.default.addObserver(self, selector: #selector(resetVisibleInterval(_:)),
                name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(resetVisibleInterval(_:)),
                name: UIScene.willDeactivateNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            guard window != nil, !session.hasFired || (onFirstVisibleFrame != nil && !notifiedFirstFrame) else { return }
            let link = CADisplayLink(target: target, selector: #selector(TickTarget.tick))
            displayLink = link
            link.add(to: .main, forMode: .common)
        }

        func stop() { displayLink?.invalidate(); displayLink = nil; visibleSince = nil }
        deinit { stop(); NotificationCenter.default.removeObserver(self) }

        @objc private func resetVisibleInterval(_ notification: Notification) {
            visibleSince = nil
        }

        func sample() {
            guard session.isValid else { stop(); return }
            if session.hasFired && (onFirstVisibleFrame == nil || notifiedFirstFrame) { stop(); return }
            guard let window else { visibleSince = nil; return }
            let state = activity(window)
            guard let rendered = layer.presentation(), Self.contentIsVisible(
                rendered: rendered, window: window,
                applicationIsActive: state.app, sceneIsActive: state.scene
            ), contentIsUnoccluded(rendered: rendered, window: window) else { visibleSince = nil; return }
            if !notifiedFirstFrame {
                notifiedFirstFrame = true
                onFirstVisibleFrame?()
            }
            if session.hasFired { stop(); return }
            let frame = rendered.convert(rendered.bounds, to: window.layer.presentation() ?? window.layer)
            let intersection = frame.intersection(window.bounds)
            let fraction = (intersection.width * intersection.height) / (frame.width * frame.height)
            guard fraction >= minimumVisibleFraction else { visibleSince = nil; return }
            let instant = clock()
            if visibleSince == nil { visibleSince = instant }
            guard instant - (visibleSince ?? instant) >= visibleDuration else { return }
            session.confirmFrame(isActive: true)
            stop()
        }

        // The probe does not receive touches. Inspect UIKit presentation and
        // opaque siblings instead, including covers that disable hit testing.
        private func contentIsUnoccluded(rendered: CALayer, window: UIWindow) -> Bool {
            let windowLayer = window.layer.presentation() ?? window.layer
            let exposed = rendered.convert(rendered.bounds, to: windowLayer).intersection(window.bounds)
            guard !exposed.isEmpty, !exposed.isNull else { return false }
            let point = CGPoint(x: exposed.midX, y: exposed.midY)
            var responder: UIResponder? = self
            var owner: UIViewController?
            while let current = responder {
                if let controller = current as? UIViewController { owner = controller; break }
                responder = current.next
            }
            var presented = window.rootViewController?.presentedViewController
            while let next = presented?.presentedViewController { presented = next }
            if let controller = presented {
                var ancestor = owner
                var ownsContent = false
                while let current = ancestor {
                    if current === controller { ownsContent = true; break }
                    ancestor = current.parent
                }
                if !ownsContent, let view = controller.viewIfLoaded, view.window === window,
                   !view.isHidden, view.alpha > 0,
                   let layer = view.layer.presentation(), layer.opacity > 0,
                   layer.convert(layer.bounds, to: windowLayer).contains(point) { return false }
            }
            var child: UIView = self
            while let parent = child.superview {
                if let index = parent.subviews.firstIndex(of: child) {
                    for (position, sibling) in parent.subviews.enumerated() where sibling !== child {
                        let above = sibling.layer.zPosition > child.layer.zPosition ||
                            (sibling.layer.zPosition == child.layer.zPosition && position > index)
                        if above && Self.opaqueCover(sibling, at: point, in: windowLayer) { return false }
                    }
                }
                child = parent
            }
            return true
        }

        private static func opaqueCover(_ view: UIView, at point: CGPoint, in window: CALayer) -> Bool {
            guard !view.isHidden, let rendered = view.layer.presentation(),
                  !rendered.isHidden, rendered.opacity >= 0.999 else { return false }
            let contains = rendered.convert(rendered.bounds, to: window).contains(point)
            if contains, let color = rendered.backgroundColor, color.alpha >= 0.999 { return true }
            if view.clipsToBounds && !contains { return false }
            return view.subviews.contains { opaqueCover($0, at: point, in: window) }
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
