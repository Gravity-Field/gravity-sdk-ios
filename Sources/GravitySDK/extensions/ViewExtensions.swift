import SwiftUI

extension View {
    @ViewBuilder
    func applyIf(_ condition: Bool, transform: (Self) -> some View) -> some View
    {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func forceFrame(height: CGFloat, alignment: Alignment = .top) -> some View {
        self.frame(height: height, alignment: alignment)
            .clipped()
            .contentShape(Rectangle())
    }
}

extension View {
    @ViewBuilder
    func applyPositioned(_ positioned: GravityPositioned) -> some View {
        PositionedContainer(positioned: positioned) {
            self
        }
    }
}

private struct ViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct PositionedContainer<Content: View>: View {
    let positioned: GravityPositioned
    @ViewBuilder let content: () -> Content

    @State private var contentSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .allowsHitTesting(false)

                content()
                    .fixedSize()
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear
                                .preference(
                                    key: ViewSizePreferenceKey.self,
                                    value: contentGeometry.size
                                )
                        }
                    )
                    .onPreferenceChange(ViewSizePreferenceKey.self) { size in
                        contentSize = size
                    }
                    .position(
                        x: xPosition(containerWidth: geometry.size.width),
                        y: yPosition(containerHeight: geometry.size.height)
                    )
            }
        }
    }

    private func xPosition(containerWidth: CGFloat) -> CGFloat {
        let width = contentSize.width
        if let left = positioned.left {
            return left + width / 2
        }
        if let right = positioned.right {
            return containerWidth - right - width / 2
        }
        return containerWidth / 2
    }

    private func yPosition(containerHeight: CGFloat) -> CGFloat {
        let height = contentSize.height
        if let top = positioned.top {
            return top + height / 2
        }
        if let bottom = positioned.bottom {
            return containerHeight - bottom - height / 2
        }
        return containerHeight / 2
    }
}
