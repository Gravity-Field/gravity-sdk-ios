import SwiftUI

struct ProductsGridLayout {
    let columns: Int
    let horizontalSpacing: Double
    let verticalSpacing: Double
    let aspect: Double
    let idealCellWidth: Double
    let rows: Int
    let padding: EdgeInsets
    private let itemCount: Int

    init(style: Style, itemCount: Int) {
        let settings = style.gridSettings ?? GridSettings()
        columns = settings.validColumns ?? style.gridColumns.flatMap { (1...12).contains($0) ? $0 : nil } ?? 2
        horizontalSpacing = settings.horizontalSpacingValue
        verticalSpacing = settings.verticalSpacingValue
        let insets = style.padding
        padding = EdgeInsets(top: insets?.top ?? 0, leading: insets?.left ?? 0,
                             bottom: insets?.bottom ?? 0, trailing: insets?.right ?? 0)
        if let width = style.size?.width, width.isFinite, width > 0 {
            idealCellWidth = width
        } else {
            idealCellWidth = 100
        }
        // Grid cards are square; server size.height only applies to product rows.
        self.aspect = 1
        self.itemCount = itemCount
        rows = itemCount == 0 ? 0 : (itemCount - 1) / columns + 1

    }

    func indices(in row: Int) -> Range<Int> {
        let start = row * columns
        return start..<(start + min(columns, itemCount - start))
    }
}

enum ProductsGridSlotID: Hashable {
    case slot(String)
    case index(Int)

    init(slotId: String?, index: Int) {
        self = slotId.map { .slot($0) } ?? .index(index)
    }
}

final class ProductsGridImpressions: ObservableObject {
    private var visibleSlotIds = Set<ProductsGridSlotID>()

    func insert(slotId: String?) -> Bool {
        guard let slotId else { return false }
        return visibleSlotIds.insert(.slot(slotId)).inserted
    }
}

struct ProductsGrid: View {
    let element: Element
    let slots: [Slot]
    let content: CampaignContent
    let campaign: Campaign

    var body: some View {
        ProductsGridCells(element: element, slots: slots, content: content, campaign: campaign)
            .id(Scope(content: content, campaign: campaign))
    }

    private struct Scope: Hashable {
        let contentId: String
        let selector: String?
        let variations: [[String]]

        init(content: CampaignContent, campaign: Campaign) {
            contentId = content.contentId
            selector = campaign.selector
            variations = campaign.payload.map { [$0.campaignId, $0.experienceId, $0.variationId, $0.decisionId] }
        }
    }
}

private struct ProductsGridCells: View {
    let element: Element
    let slots: [Slot]
    let content: CampaignContent
    let campaign: Campaign

    @StateObject private var impressions = ProductsGridImpressions()
    @StateObject private var visibility = ProductsGridVisibilityObserver()

    private struct Cell: Identifiable {
        let index: Int
        let slotId: ProductsGridSlotID
        var id: ID { ID(slotId: slotId, index: index) }

        struct ID: Hashable {
            let slotId: ProductsGridSlotID
            let index: Int
        }
    }

    var body: some View {
        if !slots.isEmpty {
            let style = element.style
            let layout = ProductsGridLayout(style: style, itemCount: slots.count)

            VStack(alignment: .leading, spacing: layout.verticalSpacing) {
                ForEach(0..<layout.rows, id: \.self) { row in
                    let indices = layout.indices(in: row)
                    let cells = indices.map { Cell(index: $0, slotId: ProductsGridSlotID(slotId: slots[$0].slotId, index: $0)) }
                    HStack(spacing: 0) {
                        ForEach(cells) { cell in
                            let slot = slots[cell.index]
                            if cell.index > indices.lowerBound {
                                horizontalSpacing(layout: layout)
                            }
                            if let builder = GravitySDK.instance.productViewBuilder {
                                cellFrame(layout: layout)
                                    .overlay(
                                        builder.build(slot: slot, content: content, campaign: campaign)
                                            .environment(\.gravityProductIsInGrid, true)
                                    )
                                    .clipped()
                                    .contentShape(Rectangle())
                                    .overlay(ProductsGridVisibilityProbe(observer: visibility, onVisible: {
                                        if impressions.insert(slotId: slot.slotId) {
                                            ProductEventService.instance.sendProductVisibleImpression(slot, content, campaign)
                                        }
                                    }).allowsHitTesting(false))
                            } else {
                                cellFrame(layout: layout)
                            }
                        }
                        ForEach(0..<(layout.columns - indices.count), id: \.self) { _ in
                            horizontalSpacing(layout: layout)
                            cellFrame(layout: layout)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .background(ProductsGridVisibilityRoot(observer: visibility))
            .fixedSize(horizontal: false, vertical: true)
            .padding(layout.padding)
            .frame(minWidth: 0, maxWidth: .infinity)

        }
    }

    private func horizontalSpacing(layout: ProductsGridLayout) -> some View {
        Color.clear
            .frame(minWidth: 0, idealWidth: layout.horizontalSpacing, maxWidth: layout.horizontalSpacing)
            .frame(height: 0)
            .allowsHitTesting(false)
    }

    private func cellFrame(layout: ProductsGridLayout) -> some View {
        Color.clear
            .frame(idealWidth: layout.idealCellWidth, maxWidth: .infinity, idealHeight: layout.idealCellWidth / layout.aspect)
            .aspectRatio(layout.aspect, contentMode: .fit)
    }
}
