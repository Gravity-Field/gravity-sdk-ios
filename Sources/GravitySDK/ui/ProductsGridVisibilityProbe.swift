import SwiftUI
import UIKit

/// One event-driven, throttled observer per grid. Offscreen cells do no idle work.
@MainActor
internal final class ProductsGridVisibilityObserver: ObservableObject {
    private final class WeakCell {
        weak var view: ProductsGridVisibilityProbe.FrameView?
        init(_ view: ProductsGridVisibilityProbe.FrameView) { self.view = view }
    }
    private var cells: [ObjectIdentifier: WeakCell] = [:]
    private weak var root: ProductsGridVisibilityRoot.RootView?
    private var pending: DispatchWorkItem?
    private var pendingDeadline: TimeInterval?
    private var animationDeadlines: [String: TimeInterval] = [:]

    func register(_ view: ProductsGridVisibilityProbe.FrameView) {
        cells[ObjectIdentifier(view)] = WeakCell(view)
        schedule()
    }
    func unregister(_ view: ProductsGridVisibilityProbe.FrameView) {
        cells.removeValue(forKey: ObjectIdentifier(view))
        if cells.isEmpty {
            pending?.cancel()
            pending = nil
            pendingDeadline = nil
            animationDeadlines.removeAll()
        }
    }
    func attach(_ root: ProductsGridVisibilityRoot.RootView) {
        self.root = root
        schedule()
    }
    func detach(_ root: ProductsGridVisibilityRoot.RootView) {
        guard self.root === root else { return }
        self.root = nil
        pending?.cancel()
        pending = nil
        pendingDeadline = nil
        animationDeadlines.removeAll()
    }
    func schedule(after delay: TimeInterval = 0.05) {
        guard !cells.isEmpty, root?.window != nil else { return }
        let deadline = CACurrentMediaTime() + delay
        if let pendingDeadline, pendingDeadline <= deadline { return }
        pending?.cancel()
        pendingDeadline = deadline
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.pendingDeadline = nil
            self.sample()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func sample() {
        guard !cells.isEmpty, root?.window != nil else { return }
        var animationDelay: TimeInterval = 0
        var liveAnimations = Set<String>()
        for (key, cell) in cells {
            guard let view = cell.view else { cells.removeValue(forKey: key); continue }
            animationDelay = max(animationDelay, remainingAnimationTime(for: view.layer, liveKeys: &liveAnimations))
            view.sample()
        }
        animationDeadlines = animationDeadlines.filter { liveAnimations.contains($0.key) }
        // A single trailing check at finite animation completion; never frame polling.
        if !cells.isEmpty, animationDelay > 0 { schedule(after: animationDelay + 0.05) }
    }
    private func remainingAnimationTime(for layer: CALayer, liveKeys: inout Set<String>) -> TimeInterval {
        let now = CACurrentMediaTime()
        var remaining: TimeInterval = 0
        var ancestor: CALayer? = layer
        while let current = ancestor {
            for key in current.animationKeys() ?? [] {
                guard let animation = current.animation(forKey: key),
                      animation.duration.isFinite, animation.duration > 0,
                      animation.repeatCount == 0, animation.repeatDuration == 0,
                      animation.speed > 0 else { continue }
                let duration = animation.duration * (animation.autoreverses ? 2 : 1) / Double(animation.speed)
                let id = "\(ObjectIdentifier(current))-\(key)-\(animation.beginTime)"
                liveKeys.insert(id)
                let end: TimeInterval
                if animation.beginTime > 0 {
                    end = now + animation.beginTime + duration - current.convertTime(now, from: nil)
                } else {
                    end = animationDeadlines[id] ?? (now + duration)
                    animationDeadlines[id] = end
                }
                remaining = max(remaining, end - now)
            }
            ancestor = current.superlayer
        }
        return remaining
    }
    deinit { pending?.cancel() }
}

/// Cells only register geometry/lifecycle changes; they own no timer or observer.
internal struct ProductsGridVisibilityProbe: UIViewRepresentable {
    let observer: ProductsGridVisibilityObserver
    let onVisible: () -> Void

    func makeUIView(context: Context) -> FrameView { FrameView(observer: observer, onVisible: onVisible) }
    func updateUIView(_ uiView: FrameView, context: Context) { uiView.onVisible = onVisible }
    static func dismantleUIView(_ uiView: FrameView, coordinator: ()) { uiView.observer.unregister(uiView) }

    final class FrameView: UIView {
        let observer: ProductsGridVisibilityObserver
        var onVisible: () -> Void
        private var hasFired = false

        init(observer: ProductsGridVisibilityObserver, onVisible: @escaping () -> Void) {
            self.observer = observer
            self.onVisible = onVisible
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil, !hasFired { observer.register(self) }
            else { observer.unregister(self) }
        }
        override func layoutSubviews() { super.layoutSubviews(); observer.schedule() }

        func sample() {
            guard !hasFired, let window, !window.isHidden, window.alpha > 0 else { return }
            let rendered = layer.presentation() ?? layer
            let windowLayer = window.layer.presentation() ?? window.layer
            let frame = rendered.convert(rendered.bounds, to: windowLayer)
            let area = frame.width * frame.height
            guard area > 0 else { return }
            var visible = frame.intersection(windowLayer.bounds)
            var ancestor: CALayer? = rendered
            while let current = ancestor {
                guard !current.isHidden, current.opacity > 0 else { return }
                if current.masksToBounds {
                    visible = visible.intersection(current.convert(current.bounds, to: windowLayer))
                }
                if let mask = current.mask, !mask.frame.isEmpty {
                    visible = visible.intersection(current.convert(mask.frame, to: windowLayer))
                }
                guard !visible.isNull, !visible.isEmpty else { return }
                ancestor = current.superlayer
            }
            guard visible.width * visible.height / area >= 0.5 else { return }
            hasFired = true
            observer.unregister(self)
            onVisible()
        }
    }
}

/// One root installs observations on the grid's enclosing scroll viewports.
internal struct ProductsGridVisibilityRoot: UIViewRepresentable {
    let observer: ProductsGridVisibilityObserver
    func makeUIView(context: Context) -> RootView { RootView(observer: observer) }
    func updateUIView(_ uiView: RootView, context: Context) { uiView.refresh() }
    static func dismantleUIView(_ uiView: RootView, coordinator: ()) { uiView.stop() }

    final class RootView: UIView {
        private let observer: ProductsGridVisibilityObserver
        private var observations: [NSKeyValueObservation] = []
        private var ancestorIds: [ObjectIdentifier] = []
        init(observer: ProductsGridVisibilityObserver) {
            self.observer = observer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); refresh() }
        override func layoutSubviews() { super.layoutSubviews(); refresh() }
        func stop() {
            observations.removeAll()
            ancestorIds.removeAll()
            observer.detach(self)
        }
        func refresh() {
            guard window != nil else { stop(); return }
            observer.attach(self)
            var views: [UIView] = []
            var ancestor = superview
            while let view = ancestor {
                views.append(view)
                ancestor = view.superview
            }
            let ids = views.map(ObjectIdentifier.init)
            if ids != ancestorIds {
                ancestorIds = ids
                observations = views.flatMap { view -> [NSKeyValueObservation] in
                    var changes = [
                        view.observe(\.isHidden, options: [.new]) { [weak self] _, _ in self?.observer.schedule() },
                        view.observe(\.alpha, options: [.new]) { [weak self] _, _ in self?.observer.schedule() },
                        view.layer.observe(\.transform, options: [.new]) { [weak self] _, _ in self?.observer.schedule() },
                        view.layer.observe(\.position, options: [.new]) { [weak self] _, _ in self?.observer.schedule() }]
                    if let scroll = view as? UIScrollView {
                        changes += [scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in self?.observer.schedule() },
                                    scroll.observe(\.bounds, options: [.new]) { [weak self] _, _ in self?.observer.schedule() }]
                    }
                    return changes
                }
            }
            observer.schedule()
        }
    }
}
