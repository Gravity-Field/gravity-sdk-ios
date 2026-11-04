import SwiftUI
import UIKit

extension View {
    @ViewBuilder
    func gravityScrollBehavior(isEnabled: Bool) -> some View {
        if #available(iOS 16.4, *) {
            self.scrollDisabled(!isEnabled)
                .scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    @ViewBuilder
    func gravityScrollContent() -> some View {
        if #available(iOS 16.4, *) {
            // Keep nested product rows independently scrollable.
            self.environment(\.isScrollEnabled, true)
        } else {
            self
        }
    }
}

struct GravityScrollConfiguration: View {
    let isEnabled: Bool

    @ViewBuilder var body: some View {
        if #available(iOS 16.4, *) {
            EmptyView()
        } else {
            LegacyScrollConfiguration(isEnabled: isEnabled)
        }
    }
}

struct LegacyScrollConfiguration: UIViewRepresentable {
    let isEnabled: Bool

    func makeUIView(context: Context) -> ScrollConfigurationView {
        let view = ScrollConfigurationView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ScrollConfigurationView, context: Context) {
        uiView.isScrollEnabled = isEnabled
        DispatchQueue.main.async { [weak uiView] in
            uiView?.configureScrollView()
        }
    }

    final class ScrollConfigurationView: UIView {
        var isScrollEnabled = false {
            didSet { configureScrollView() }
        }

        private weak var scrollView: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var isApplying = false

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            configureScrollView()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            configureScrollView()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            configureScrollView()
        }

        func configureScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    if scrollView !== scroll {
                        scrollView = scroll
                        observations = [
                            scroll.observe(\.isScrollEnabled, options: [.new]) { [weak self] _, _ in self?.applyConfiguration() },
                            scroll.observe(\.alwaysBounceVertical, options: [.new]) { [weak self] _, _ in self?.applyConfiguration() },
                            scroll.observe(\.bounces, options: [.new]) { [weak self] _, _ in self?.applyConfiguration() }
                        ]
                    }
                    applyConfiguration()
                    return
                }
                ancestor = view.superview
            }
        }

        private func applyConfiguration() {
            guard let scroll = scrollView, !isApplying else { return }
            isApplying = true
            defer { isApplying = false }
            if scroll.isScrollEnabled != isScrollEnabled { scroll.isScrollEnabled = isScrollEnabled }
            if scroll.bounces != isScrollEnabled { scroll.bounces = isScrollEnabled }
            if scroll.alwaysBounceVertical != isScrollEnabled { scroll.alwaysBounceVertical = isScrollEnabled }
            if scroll.alwaysBounceHorizontal { scroll.alwaysBounceHorizontal = false }
        }
    }
}
