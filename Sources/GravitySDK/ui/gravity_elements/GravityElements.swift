import SwiftUI
import os

struct GravityElements: View {
    let content: CampaignContent
    let campaign: Campaign
    let onClickCallback: (OnClickModel) -> Void

    var body: some View {
        ForEach(content.variables.elements.indices, id: \.self) { index in
            let element = content.variables.elements[index]

            switch element.type {
            case .image:
                GravityImage(element: element, onClickCallback: onClickCallback)
            case .text:
                GravityText(element: element, onClickCallback: onClickCallback)
            case .button:
                GravityButton(
                    element: element,
                    onClickCallback: onClickCallback
                )
            case .spacer:
                Spacer()
                    .frame(minHeight: 0, maxHeight: .infinity)
                    .applyIf(element.style.weight != nil) {
                        $0.frame(maxHeight: .infinity)
                    }
            case .productsContainer:
                if let products = content.products {

                    switch element.style.productContainerType {
                    case .row:
                        ProductsRow(
                            element: element,
                            products: products,
                            content: content,
                            campaign: campaign
                        )
                    default:
                        EmptyView()
                    }
                } else {
                    EmptyView()
                }
            case .unknown:
                EmptyView()
            }
        }
    }
}
