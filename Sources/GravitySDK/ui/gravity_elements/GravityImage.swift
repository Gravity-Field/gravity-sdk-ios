import SwiftUI

struct GravityImage: View {
    let element: Element
    let onClickCallback: (OnClickModel) -> Void

    private var style: Style {
        element.style
    }
    private var fit: GravityContentScale? {
        style.fit
    }
    private var url: URL? {
        URL(string: element.src ?? "")
    }

    var body: some View {
        ZStack {
            if let url = url {
                AsyncImage(url: url) { image in
                    if let image = image {
                        image
                            .resizable(
                                resizingMode: fit
                                    == GravityContentScale.crop
                                    ? .tile : .stretch
                            )
                    } else {
                        Color.clear
                    }
                }
            }
        }.applyIf(style.size?.width != nil) {
            $0.frame(width: style.size!.width!)
        }
        .applyIf(style.size?.height != nil) {
            $0.frame(height: style.size!.height!)
        }
        .applyIf(style.layoutWidth == .matchParent) {
            $0.frame(maxWidth: .infinity)
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
