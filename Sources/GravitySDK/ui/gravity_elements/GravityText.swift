import SwiftUI
import os

struct GravityText: View {
    let element: Element
    let onClickCallback: (OnClickModel) -> Void
    var item: Item? = nil
    
    private var style: Style? {
        element.style
    }

    private var resolvedText: String {
        if let item = item, let key = element.text {
            return item.values[key] ?? ""
        }
        return element.text ?? ""
    }
    
    private var textAlignment: TextAlignment {
        style?.contentAlignment?.toTextAlignment() ?? .leading
    }

    private var frameAlignment: Alignment {
        switch style?.contentAlignment {
        case .center: return .center
        case .end: return .trailing
        default: return .leading
        }
    }
    
    private var labelFont: Font? {
        gravityFont(
            size: style?.fontSize.map { CGFloat($0) },
            fontWeight: style?.fontWeight
        )
    }

    private var isMatchParent: Bool {
        style?.layoutWidth == .matchParent
    }
    
    var body: some View {
        Text(resolvedText)
            .foregroundColor(style?.textColor)
            .multilineTextAlignment(textAlignment)
            .applyIf(labelFont != nil) {
                $0.font(labelFont!)
            }
            .applyIf(style?.padding != nil) {
                $0.padding(.init(
                    top: style!.padding!.top,
                    leading: style!.padding!.left,
                    bottom: style!.padding!.bottom,
                    trailing: style!.padding!.right
                ))
            }
            .applyIf(style?.size?.width != nil && !isMatchParent) {
                $0.frame(width: style!.size!.width!, alignment: frameAlignment)
            }
            .applyIf(style?.size?.height != nil) {
                $0.frame(height: style!.size!.height!)
            }
            .applyIf(isMatchParent) {
                $0.frame(maxWidth: .infinity, alignment: frameAlignment)
            }
            .applyIf(style?.size?.height == nil) {
                $0.fixedSize(horizontal: false, vertical: true)
            }
            .applyIf(element.onClick != nil) {
                $0.onTapGesture {
                    if let onClick = element.onClick {
                        onClickCallback(onClick)
                    }
                }
            }
            .applyIf(style?.margin != nil) {
                $0.padding(.init(
                    top: style!.margin!.top,
                    leading: style!.margin!.left,
                    bottom: style!.margin!.bottom,
                    trailing: style!.margin!.right
                ))
            }
    }
}
