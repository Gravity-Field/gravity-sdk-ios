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
    
    var body: some View {
        Text(element.text ?? "")
            .foregroundColor(style?.textColor)
            .multilineTextAlignment(textAlignment)
            .applyIf(style?.margin != nil) {
                $0.padding(.init(
                    top: style!.margin!.top,
                    leading: style!.margin!.left,
                    bottom: style!.margin!.bottom,
                    trailing: style!.margin!.right
                ))
            }
            .applyIf(element.onClick != nil) {
                $0.onTapGesture {
                    if let onClick = element.onClick {
                        onClickCallback(onClick)
                    }
                }
            }
            .applyIf(style?.fontSize != nil) {
                $0.font(.system(size: style!.fontSize!))
            }
//            .applyIf(style?.fontWeight != nil) {
//                $0.weight(style?.fontWeight?.toWeight())
//            }
    }
}
