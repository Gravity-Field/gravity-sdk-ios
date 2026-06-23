import SwiftUI
import os

struct GravityElements: View {
    let content: CampaignContent
    let campaign: Campaign
    let onClickCallback: (OnClickModel) -> Void
    var item: Item? = nil

    var body: some View {
        let elements = content.variables?.elements ?? []
        
        return ForEach(elements.indices, id: \.self) { index in
            let element = elements[index]

            switch element.type {
            case .image:
                GravityImage(element: element, onClickCallback: onClickCallback, item: item)
            case .text:
                GravityText(element: element, onClickCallback: onClickCallback, item: item)
            case .webview:
                GravityWebview(element: element)
            case .button:
                GravityButton(
                    element: element,
                    onClickCallback: onClickCallback,
                    item: item
                )
            case .spacer:
                Spacer()
                    .frame(minHeight: 0, maxHeight: .infinity)
                    .applyIf(element.style.weight != nil) {
                        $0.frame(maxHeight: .infinity)
                    }
            case .productsContainer:
                if let slots = content.products?.slots {
                    switch element.style.productContainerType ?? .row {
                    case .row:
                        ProductsRow(
                            element: element,
                            slots: slots,
                            content: content,
                            campaign: campaign
                        )
                    default:
                        EmptyView()
                    }
                } else {
                    EmptyView()
                }
            case .itemsContainer:
                if let items = content.items {
                    ItemsRow(
                        element: element,
                        items: items,
                        onClickCallback: onClickCallback
                    )
                } else {
                    EmptyView()
                }
            case .unknown:
                EmptyView()
            }
        }
    }
}

struct GravityElementsInCard: View {
    let elements: [Element]
    let onClickCallback: (OnClickModel) -> Void
    let item: Item

    var body: some View {
        ForEach(elements.indices, id: \.self) { index in
            let element = elements[index]

            switch element.type {
            case .image:
                GravityImage(element: element, onClickCallback: onClickCallback, item: item)
            case .text:
                GravityText(element: element, onClickCallback: onClickCallback, item: item)
            case .button:
                GravityButton(
                    element: element,
                    onClickCallback: onClickCallback,
                    item: item
                )
            case .webview:
                GravityWebview(element: element)
            case .spacer:
                Spacer()
                    .frame(minHeight: 0, maxHeight: .infinity)
                    .applyIf(element.style.weight != nil) {
                        $0.frame(maxHeight: .infinity)
                    }
            default:
                EmptyView()
            }
        }
    }
}
