import SwiftUI

struct GravityImage: View {
    let element: Element
    let onClickCallback: (OnClickModel) -> Void
    var item: Item? = nil

    private var style: Style {
        element.style
    }
    private var fit: GravityContentScale {
        style.fit ?? .crop
    }
    private var resolvedSrc: String? {
        if let item = item, let key = element.src {
            return item.values[key]
        }
        return element.src
    }
    private var url: URL? {
        URL(string: resolvedSrc ?? "")
    }

    var body: some View {
        ZStack {
            if let url = url {
                AsyncUIImage(url: url) { uiImage in
                    if let uiImage {
                        GravityScaledImageView(uiImage: uiImage, fit: fit)
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
            $0.clipShape(
                RoundedRectangle(cornerRadius: style.cornerRadius!)
            )
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
