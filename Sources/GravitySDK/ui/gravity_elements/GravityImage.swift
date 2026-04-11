import SwiftUI

struct GravityImage: View {
    let element: Element
    let onClickCallback: (OnClickModel) -> Void

    private var style: Style {
        element.style
    }
    private var fit: GravityContentScale {
        style.fit ?? .crop
    }
    private var url: URL? {
        URL(string: element.src ?? "")
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
            if let url = url {
                AsyncImage(url: url) { image in
                    if let image = image {
                        styledImage(image)
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .applyIf(style.size?.width != nil) {
            $0.frame(width: style.size!.width!)
        }
        .applyIf(style.size?.height != nil) {
            $0.frame(height: style.size!.height!)
        }
        .applyIf(style.layoutWidth == .matchParent) {
            $0.frame(maxWidth: .infinity)
        }
        .clipped()
        .applyIf(style.cornerRadius != nil) {
            $0.clipShape(RoundedRectangle(cornerRadius: style.cornerRadius!))
        }
        .applyIf(style.margin != nil) {
            $0.padding(
                .init(
                    top: style.margin!.top,
                    leading: style.margin!.left,
                    bottom: style.margin!.bottom,
                    trailing: style.margin!.right
                )
            )
        }
        .applyIf(element.onClick != nil) {
            $0.onTapGesture {
                onClickCallback(element.onClick!)
            }
        }
    }
}
