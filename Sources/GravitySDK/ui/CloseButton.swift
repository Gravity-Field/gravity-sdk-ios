import SwiftUI

struct CloseButton: View {
    let close: Close
    let onClickCallback: (OnClickModel) -> Void

    private var style: Style {
        close.style
    }
    private var fit: GravityContentScale? {
        close.style.fit
    }
    private var url: URL? {
        URL(string: close.image ?? "")
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
        }
        .applyIf(style.positioned != nil) {
            $0.applyPositioned(style.positioned!)
        }
    }
}
