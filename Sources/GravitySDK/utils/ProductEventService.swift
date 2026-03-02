import Foundation

internal class ProductEventService {

    static let instance = ProductEventService()

    private init() {}

    private let repository = GravityRepository.instance

    func sendProductClick(
        _ slot: Slot,
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        trackEvent(
            action: .click,
            slot: slot,
            content: content,
            campaign: campaign,
            callbackTrackingEvent: callbackTrackingEvent
        )
    }

    func sendProductVisibleImpression(
        _ slot: Slot,
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        trackEvent(
            action: .visibleImpression,
            slot: slot,
            content: content,
            campaign: campaign,
            callbackTrackingEvent: callbackTrackingEvent
        )
    }

    private func trackEvent(
        action: ProductAction,
        slot: Slot,
        content: CampaignContent,
        campaign: Campaign,
        callbackTrackingEvent: Bool
    ) {
        guard let event = slot.events?.first(where: { $0.type == action }) else {
            return
        }

        Task {
            do {
                try await repository.trackEngagementEvent(urls: event.urls)

                if callbackTrackingEvent {
                    let trackingEvent: TrackingEvent?
                    switch action {
                    case .visibleImpression:
                        trackingEvent = ProductImpressionEvent(slot: slot, content: content, campaign: campaign)
                    default:
                        trackingEvent = nil
                    }

                    if let trackingEvent = trackingEvent {
                        GravitySDK.instance.callbackTrackingEvent(trackingEvent)
                    }
                }
            } catch {}
        }
    }
}
