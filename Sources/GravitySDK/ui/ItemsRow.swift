import SwiftUI

struct ItemsRow: View {
    let element: Element
    let items: [Item]
    let onClickCallback: (OnClickModel) -> Void

    private var style: Style? {
        element.style
    }
    private var height: Double? {
        style?.size?.height
    }
    private var margin: GravityMargin? {
        style?.margin
    }

    var body: some View {
        if let itemCard = element.itemCard {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: CGFloat(style?.rowSpacing ?? 0)) {
                    ForEach(items.indices, id: \.self) { index in
                        GravityItemCard(
                            item: items[index],
                            itemCard: itemCard,
                            onClickCallback: onClickCallback
                        )
                    }
                }
                .applyIf(style?.padding != nil) {
                    $0.padding(
                        EdgeInsets(
                            top: style?.padding?.top ?? 0,
                            leading: style?.padding?.left ?? 0,
                            bottom: style?.padding?.bottom ?? 0,
                            trailing: style?.padding?.right ?? 0
                        )
                    )
                }
                .applyIf(style?.backgroundColor != nil) {
                    $0.background(style!.backgroundColor!)
                }
            }
            .frame(maxWidth: .infinity)
            .applyIf(height != nil) {
                $0.frame(height: height!)
            }
            .applyIf(margin != nil) {
                $0.padding(
                    EdgeInsets(
                        top: margin?.top ?? 0,
                        leading: margin?.left ?? 0,
                        bottom: margin?.bottom ?? 0,
                        trailing: margin?.right ?? 0
                    )
                )
            }
        }
    }
}
