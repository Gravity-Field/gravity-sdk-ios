import SwiftUI

struct ProductsRow: View {
    let element: Element
    let slots: [Slot]
    let content: CampaignContent
    let campaign: Campaign

    private var style: Style? {
        element.style
    }
    private var height: Double? {
        style?.size?.height
    }
    private var margin: GravityMargin? {
        style?.margin
    }
    private var spacing: CGFloat {
        CGFloat(style?.rowSpacing ?? 8)
    }
    private var contentPadding: EdgeInsets {
        if let padding = style?.padding {
            return EdgeInsets(
                top: padding.top,
                leading: padding.left,
                bottom: padding.bottom,
                trailing: padding.right
            )
        }
        return EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) {
                ForEach(slots.indices, id: \.self) { index in
                    let slot = slots[index]

                    ProductVisibilityTracker(
                        slot: slot,
                        content: content,
                        campaign: campaign
                    ) {
                        if let builder = GravitySDK.instance.productViewBuilder {
                            builder.build(
                                slot: slot,
                                content: content,
                                campaign: campaign
                            )
                        }
                    }
                }
            }
            .padding(contentPadding)
        }
        .frame(maxWidth: .infinity)
        .applyIf(height != nil) {
            $0.frame(height: height!)
        }
        .applyIf(style?.backgroundColor != nil) {
            $0.background(style!.backgroundColor!)
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
