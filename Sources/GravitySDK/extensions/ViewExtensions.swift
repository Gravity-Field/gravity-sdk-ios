import SwiftUICore

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

    func forceFrame(height: CGFloat) -> some View {
        self.aspectRatio(contentMode: .fit)
            .frame(height: height)
            .clipped()
            .contentShape(Rectangle())
    }
}

extension View {
    @ViewBuilder
    func applyPositioned(_ positioned: GravityPositioned) -> some View {
        let horizontal: HorizontalAlignment =
            (positioned.left != nil)
            ? .leading : (positioned.right != nil) ? .trailing : .leading

        let vertical: VerticalAlignment =
            (positioned.top != nil)
            ? .top : (positioned.bottom != nil) ? .bottom : .top

        let x: Double =
            horizontal == .leading
            ? (positioned.left ?? 0)
            : (horizontal == .trailing) ? -(positioned.right ?? 0) : 0

        let y: Double =
            vertical == .top
            ? (positioned.top ?? 0)
            : (vertical == .bottom) ? -(positioned.bottom ?? 0) : 0

        self
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topTrailing
            )
            .offset(x: x, y: y)
    }
}
