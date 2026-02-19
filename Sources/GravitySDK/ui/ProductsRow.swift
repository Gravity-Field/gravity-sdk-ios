import SwiftUI

struct ProductsRow: View {
    let element: Element
    let products: Products
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
            LazyHStack(spacing: 8) {

                ForEach(products.slots!.indices, id: \.self) { index in
                    let slot = products.slots![index]

                    Group {
                        if let builder = GravitySDK.instance.productViewBuilder
                        {
                            builder.build(slot: slot)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
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
        .applyIf(height != nil && GravitySDK.instance.productViewBuilder == nil)
        {
            $0.frame(height: height!)
        }
        .frame(maxWidth: .infinity)
    }
}
