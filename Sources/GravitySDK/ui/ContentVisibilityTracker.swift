import SwiftUI

struct ContentVisibilityTracker<Content: View>: View {
    let content: CampaignContent
    let campaign: Campaign
    @ViewBuilder let view: () -> Content

    var body: some View {
        VisibilityDetector(
            onVisible: {
                ContentEventService.instance.sendContentVisibleImpression(
                    content,
                    campaign
                )
            },
            view: view
        )
    }
}
