import SwiftUI
import os

struct GravityButton: View {
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

    private var textStyle: GravityTextStyle? {
        style?.textStyle
    }

    private var labelFont: Font? {
        gravityFont(
            size: textStyle?.fontSize.map { CGFloat($0) },
            fontWeight: textStyle?.fontWeight
        )
    }

    private var contentAlignment: Alignment {
        style?.contentAlignment?.toAlignment() ?? .center
    }

    var body: some View {
        Button(action: {
            if let onClick = element.onClick {
                onClickCallback(onClick)
            }
        }) {
            Text(resolvedText)
                .applyIf(labelFont != nil) {
                    $0.font(labelFont!)
                }
                .foregroundColor(textStyle?.color)
                .applyIf(style?.padding != nil) {
                    $0.padding(
                        .init(
                            top: style!.padding!.top,
                            leading: style!.padding!.left,
                            bottom: style!.padding!.bottom,
                            trailing: style!.padding!.right
                        )
                    )
                }
                .applyIf(style?.size?.width != nil) {
                    $0.frame(
                        width: style!.size!.width!,
                        alignment: contentAlignment
                    )
                }
                .applyIf(style?.size?.height != nil) {
                    $0.frame(height: style!.size!.height!)
                }
                .applyIf(style?.layoutWidth == .matchParent) {
                    $0.frame(maxWidth: .infinity, alignment: contentAlignment)
                }
        }
        .buttonStyle(
            GravityPressButtonStyle(
                backgroundColor: style?.backgroundColor,
                pressColor: style?.pressColor,
                cornerRadius: style?.cornerRadius
            )
        )
        .applyIf(style?.margin != nil) {
            $0.padding(
                .init(
                    top: style?.margin?.top ?? 0,
                    leading: style?.margin?.left ?? 0,
                    bottom: style?.margin?.bottom ?? 0,
                    trailing: style?.margin?.right ?? 0
                )
            )
        }
    }
}

private struct GravityPressButtonStyle: ButtonStyle {
    let backgroundColor: Color?
    let pressColor: Color?
    let cornerRadius: Double?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(backgroundColor ?? .clear)
            .overlay(
                configuration.isPressed
                    ? (pressColor ?? .clear)
                    : .clear
            )
            .cornerRadius(cornerRadius ?? 0)
    }
}
