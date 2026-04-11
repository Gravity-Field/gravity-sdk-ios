import SwiftUI
import os

struct GravityText: View {
    let element: Element
    let onClickCallback: (OnClickModel) -> Void
    
    private var style: Style? {
        element.style
    }
    
    private var textAlignment: TextAlignment {
        style?.contentAlignment?.toTextAlignment() ?? .leading
    }
    
    private var labelFont: Font? {
        let size = style?.fontSize.map { CGFloat($0) }
        let weight = style?.fontWeight.map { $0.toWeight() }
        switch (size, weight) {
        case let (s?, w?):
            return .system(size: s, weight: w)
        case let (s?, nil):
            return .system(size: s)
        case let (nil, w?):
            return .system(size: UIFont.labelFontSize, weight: w)
        default:
            return nil
        }
    }
    
    var body: some View {
        Text(element.text ?? "")
            .foregroundColor(style?.textColor)
            .multilineTextAlignment(textAlignment)
            .applyIf(labelFont != nil) {
                $0.font(labelFont!)
            }
            .applyIf(style?.margin != nil) {
                $0.padding(.init(
                    top: style!.margin!.top,
                    leading: style!.margin!.left,
                    bottom: style!.margin!.bottom,
                    trailing: style!.margin!.right
                ))
            }
            .applyIf(style?.size?.width != nil) {
                $0.frame(width: style!.size!.width!)
            }
            .applyIf(style?.size?.height != nil) {
                $0.frame(height: style!.size!.height!)
            }
            .applyIf(style?.layoutWidth == .matchParent) {
                $0.frame(maxWidth: .infinity)
            }
            .applyIf(element.onClick != nil) {
                $0.onTapGesture {
                    if let onClick = element.onClick {
                        onClickCallback(onClick)
                    }
                }
            }
    }
}
