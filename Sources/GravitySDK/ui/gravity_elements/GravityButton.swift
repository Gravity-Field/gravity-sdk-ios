import SwiftUI
import os

struct GravityButton: View {
    let element: Element
    let onClickCallback: (OnClickModel) -> Void
    
    private var style: Style? {
        element.style
    }
    
    private var textStyle: GravityTextStyle? {
        style?.textStyle
    }
    
    var body: some View {
//        Button(action: {
//            if let onClick = element.onClick {
//                onClickCallback(onClick)
//            }
//        }) {
//            Text(element.text ?? ""
////                .multilineTextAlignment(.center)
//                .applyIf(style?.fontSize != nil) {
//                    $0.font(.system(size: style!.fontSize!))
//                }
//                .applyIf(style?.fontWeight != nil) {
//                    $0.weight(style?.fontWeight?.toWeight())
//                }
//                .applyIf(style?.margin == nil) {
//                    $0.padding()
//                }
//                .applyIf(style?.size?.height != nil) {
//                    $0.frame(height: style!.size!.height!)
//                }
//                .applyIf(style?.size?.height == nil) {
//                    $0.frame(height: 48)
//                }
//                .applyIf(style?.layoutWidth == .matchParent) {
//                    $0.frame(maxWidth: .infinity)
//                }
//                .foregroundColor(style?.textColor)
//                .background(style?.backgroundColor)
//                .applyIf(style?.cornerRadius != nil) {
//                    $0.cornerRadius(style!.cornerRadius!)
//                }
//        }
//        .applyIf(style?.margin != nil) {
//            $0.padding(.init(
//                top: style?.margin?.top ?? 0,
//                leading: style?.margin?.left ?? 0,
//                bottom: style?.margin?.bottom ?? 0,
//                trailing: style?.margin?.right ?? 0
//            ))
//        }
    }
}
