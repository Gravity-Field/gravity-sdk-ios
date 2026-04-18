import SwiftUI
import UIKit


public protocol ProductViewBuilder {
    @ViewBuilder
    func build(
        slot: Slot,
        content: CampaignContent,
        campaign: Campaign
    ) -> AnyView
}

public protocol LegacyProductViewBuilder: ProductViewBuilder {
    func createView(
        slot: Slot,
        content: CampaignContent,
        campaign: Campaign
    ) -> UIView
}

extension LegacyProductViewBuilder {
    public func build(
        slot: Slot,
        content: CampaignContent,
        campaign: Campaign
    ) -> AnyView {
        AnyView(
            LegacyProductUIViewHost(
                slot: slot,
                content: content,
                campaign: campaign,
                factory: createView
            )
        )
    }
}

struct LegacyProductUIViewHost: UIViewRepresentable {
    let slot: Slot
    let content: CampaignContent
    let campaign: Campaign
    let factory: (Slot, CampaignContent, Campaign) -> UIView

    func makeUIView(context: Context) -> UIView {
        factory(slot, content, campaign)
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
