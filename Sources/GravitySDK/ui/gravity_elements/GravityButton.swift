import SwiftUI
import UIKit
import os

struct GravityButton: View {
    let element: Element
    let onClickCallback: (OnClickModel) -> Void
    var item: Item? = nil
    var enabled: Bool = true

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

    private var isEnabled: Bool {
        isButtonEnabled(enabled, onClick: element.onClick)
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
                .foregroundColor(isEnabled ? textStyle?.color : disabledContentColor)
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
                backgroundColor: isEnabled ? style?.backgroundColor : disabledContainerColor,
                pressColor: resolvePressColor(style?.pressColor, textColor: textStyle?.color),
                outlineColor: resolveOutlineColor(style?.outlineColor, enabled: isEnabled),
                cornerRadius: style?.cornerRadius ?? defaultCornerRadius
            )
        )
        .disabled(!isEnabled)
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
    let outlineColor: Color?
    let cornerRadius: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(backgroundColor ?? .clear)
            .overlay(
                configuration.isPressed
                    ? (pressColor ?? .clear)
                    : .clear
            )
            .cornerRadius(cornerRadius)
            .applyIf(outlineColor != nil) {
                $0.overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(outlineColor!, lineWidth: 1)
                )
            }
    }
}

private let disabledOutlineAlpha: CGFloat = 0.4
private let defaultCornerRadius: Double = 8
private let defaultPressAlpha: CGFloat = 0.1
// Material 3 defaults for a disabled filled button: onSurface at 12% / 38%
private let disabledContainerColor = Color.primary.opacity(0.12)
private let disabledContentColor = Color.primary.opacity(0.38)

func isButtonEnabled(_ enabled: Bool, onClick: OnClickModel?) -> Bool {
    enabled && onClick != nil
}

/// Without an explicit pressColor, mirror the Material 3 pressed overlay:
/// the content color at 10% alpha.
func resolvePressColor(_ pressColor: Color?, textColor: Color?) -> Color {
    if let pressColor { return pressColor }
    return Color(UIColor(textColor ?? .primary).withAlphaComponent(defaultPressAlpha))
}

func resolveOutlineColor(_ outlineColor: Color?, enabled: Bool) -> Color? {
    guard let outlineColor else { return nil }
    if enabled { return outlineColor }
    return Color(UIColor(outlineColor).withAlphaComponent(disabledOutlineAlpha))
}
