import SwiftUI

struct CloseButton: View {
    let close: Close
    let onClickCallback: (OnClickModel) -> Void

    private var style: Style {
        close.style
    }

    private var fit: GravityContentScale {
        style.fit ?? .crop
    }

    private var imageUrl: URL? {
        guard let image = close.image else { return nil }
        return URL(string: image)
    }

    var body: some View {
        Button(action: buttonAction) {
            closeButtonContent
        }
        .buttonStyle(CloseButtonPressStyle())
        .applyIf(style.positioned != nil) {
            $0.applyPositioned(style.positioned!)
        }
    }

    private func buttonAction() {
        if let onClick = close.onClick {
            onClickCallback(onClick)
        }
    }

    @ViewBuilder
    private var closeButtonContent: some View {
        Group {
            if let imageUrl = imageUrl {
                AsyncUIImage(url: imageUrl) { uiImage in
                    if let uiImage {
                        GravityScaledImageView(uiImage: uiImage, fit: fit)
                    } else {
                        Color.clear
                    }
                }
            } else {
                Image(systemName: "xmark")
            }
        }
        .applyIf(style.size?.width != nil) {
            $0.frame(width: style.size!.width!)
        }
        .applyIf(style.size?.height != nil) {
            $0.frame(height: style.size!.height!)
        }
        .contentShape(Rectangle())
    }
}

private struct CloseButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}
