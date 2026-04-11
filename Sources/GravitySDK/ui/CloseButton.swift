import SwiftUI

struct CloseButton: View {
    let close: Close
    let onClickCallback: (OnClickModel) -> Void

    private var style: Style {
        close.style
    }
    private var fit: GravityContentScale {
        close.style.fit ?? .crop
    }
    private var url: URL? {
        URL(string: close.image ?? "")
    }

    @ViewBuilder
    private func styledImage(_ image: Image) -> some View {
        switch fit {
        case .crop, .fillWidth, .fillHeight:
            image.resizable().aspectRatio(contentMode: .fill).clipped()
        case .fit, .inside:
            image.resizable().aspectRatio(contentMode: .fit)
        case .fillBounds:
            image.resizable()
        case .none:
            image
        }
    }

    var body: some View {
        ZStack {
            Button(action: {
                if let onClick = close.onClick {
                    onClickCallback(onClick)
                }
            }) {
                if let url = url {
                    AsyncImage(url: url) { image in
                        if let image = image {
                            styledImage(image)
                        } else {
                            Color.clear
                        }
                    }
                } else {
                    Image(systemName: "xmark")
                }
            }
            .buttonStyle(CloseButtonPressStyle())
            .applyIf(style.size?.width != nil) {
                $0.frame(width: style.size!.width!)
            }
            .applyIf(style.size?.height != nil) {
                $0.frame(height: style.size!.height!)
            }
        }
        .applyIf(style.positioned != nil) {
            $0.applyPositioned(style.positioned!)
        }
    }
}

private struct CloseButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
    }
}
