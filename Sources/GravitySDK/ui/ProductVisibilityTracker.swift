import SwiftUI

struct ProductVisibilityTracker<Content: View>: View {
    let slot: Slot
    let content: CampaignContent
    let campaign: Campaign
    @ViewBuilder let view: () -> Content

    var body: some View {
        VisibilityDetector(
            onVisible: {
                ProductEventService.instance.sendProductVisibleImpression(
                    slot,
                    content,
                    campaign
                )
            },
            view: view
        )
    }
}
