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
        if callbackTrackingEvent {
            GravitySDK.instance.callbackTrackingEvent(
                ProductClickEvent(slot: slot, content: content, campaign: campaign)
            )
        }
        
        trackEngagement(action: .click, slot: slot)
    }

    func sendProductVisibleImpression(
        _ slot: Slot,
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        if callbackTrackingEvent {
            GravitySDK.instance.callbackTrackingEvent(
                ProductImpressionEvent(slot: slot, content: content, campaign: campaign)
            )
        }
        
        trackEngagement(action: .visibleImpression, slot: slot)
    }

    private func trackEngagement(
        action: ProductAction,
        slot: Slot
    ) {
        guard let event = slot.events?.first(where: { $0.type == action }) else {
            return
        }
        Task {
            do {
                try await repository.trackEngagementEvent(urls: event.urls)
            } catch {}
        }
    }
}
