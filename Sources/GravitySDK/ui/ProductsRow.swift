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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: CGFloat(style?.rowSpacing ?? 0)) {
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
        }
        .frame(maxWidth: .infinity)
        .applyIf(height != nil && GravitySDK.instance.productViewBuilder == nil)
        {
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
