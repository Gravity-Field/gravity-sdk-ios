import SwiftUI
import UIKit

private let visibilityThreshold: Double = 0.5

struct VisibilityDetector<Content: View>: View {
    let onVisible: () -> Void
    @ViewBuilder let view: () -> Content

    @State private var hasBeenVisible = false

    var body: some View {
        view()
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: VisibilityFramePreferenceKey.self,
                            value: geometry.frame(in: .global)
                        )
                }
                .allowsHitTesting(false)
            )
            .onPreferenceChange(VisibilityFramePreferenceKey.self) { frame in
                handleFrame(frame)
            }
    }

    private func handleFrame(_ frame: CGRect) {
        guard !hasBeenVisible else { return }
        let fraction = Self.computeVisibleFraction(
            frame: frame,
            windowBounds: Self.keyWindowBounds()
        )
        guard fraction >= visibilityThreshold else { return }
        hasBeenVisible = true
        onVisible()
    }

    static func computeVisibleFraction(frame: CGRect, windowBounds: CGRect)
        -> Double
    {
        let area = frame.width * frame.height
        guard area > 0 else { return 0 }
        let intersection = frame.intersection(windowBounds)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let visibleArea = intersection.width * intersection.height
        return min(max(Double(visibleArea / area), 0), 1)
    }

    private static func keyWindowBounds() -> CGRect {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        {
            return window.bounds
        }
        return UIScreen.main.bounds
    }
}

private struct VisibilityFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
