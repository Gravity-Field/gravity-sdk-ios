import Foundation

internal class ContentEventService {

    static let instance = ContentEventService()

    private init() {}

    private let repository = GravityRepository.instance


    func sendContentLoaded(
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        if callbackTrackingEvent {
            GravitySDK.instance.callbackTrackingEvent(
                ContentLoadEvent(content: content, campaign: campaign)
            )
        }
        
        guard let onLoad = content.variables?.onLoad else { return }
        trackEngagement(contentAction: onLoad, content: content)
    }

    func sendContentImpression(
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        if callbackTrackingEvent {
            GravitySDK.instance.callbackTrackingEvent(
                ContentImpressionEvent(content: content, campaign: campaign)
            )
        }
        
        guard let onImpression = content.variables?.onImpression else { return }
        trackEngagement(contentAction: onImpression, content: content)
    }

    func sendContentVisibleImpression(
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        let sdk = GravitySDK.instance
        sdk.presentationGate.visible(contentId: content.contentId)
        if callbackTrackingEvent {
            sdk.callbackTrackingEvent(ContentVisibleImpressionEvent(content: content, campaign: campaign))
        }
        // Visibility is a tracking event even when no custom onVisible action is configured.
        let action = content.variables?.onVisibleImpression?.action ?? .visibleImpression
        guard let event = content.events?.first(where: { $0.type == action }), !event.urls.isEmpty else {
            GravityLogger.e("ContentEvent", "Visible impression has no tracking URL")
            return
        }
        Task {
            if await sdk.visibleImpressionDelivery.deliver(urls: event.urls) {
                if action != .visibleImpression { return }
                sdk.presentationGate.acknowledged(contentId: content.contentId)
            } else {
                GravityLogger.e("ContentEvent", "Visible impression delivery failed after retries")
            }
        }
    }

    /// Modal visibility is WRIMP regardless of custom actions, persisted before callbacks/send.
    func sendModalVisibleImpression(
        _ content: CampaignContent, _ campaign: Campaign, sdk: GravitySDK,
        openingId: UUID, scope: String, user: String
    ) -> Bool {
        guard let event = content.events?.first(where: { $0.type == .visibleImpression }),
              !event.urls.isEmpty, let store = sdk.visibleImpressionDelivery.store else {
            GravityLogger.e("ContentEvent", "Modal visible impression has no tracking URL")
            return false
        }
        do {
            try store.insert(.init(id: openingId, scope: scope,
                campaignId: campaign.payload.first?.campaignId ?? content.contentId,
                contentId: content.contentId, urls: Array(Set(event.urls)), user: user))
        } catch {
            GravityLogger.e("ContentEvent", "Unable to persist modal visible impression")
            return false
        }
        sdk.presentationGate.visible(contentId: content.contentId, durable: true)
        Task { await sdk.visibleImpressionDelivery.resumePending() }
        sdk.callbackTrackingEvent(ContentVisibleImpressionEvent(content: content, campaign: campaign))
        if let custom = content.variables?.onVisibleImpression, custom.action != .visibleImpression {
            trackEngagement(contentAction: custom, content: content)
        }
        return true
    }

    func sendContentClosed(
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        GravitySDK.instance.presentationGate.closed(contentId: content.contentId)
        if callbackTrackingEvent {
            GravitySDK.instance.callbackTrackingEvent(
                ContentCloseEvent(content: content, campaign: campaign)
            )
        }
        
        guard let onClose = content.variables?.onClose else { return }
        trackEngagement(contentAction: onClose, content: content)
    }

    private func trackEngagement(
        contentAction: ContentActionModel,
        content: CampaignContent
    ) {
        guard let event = content.events?.first(where: { $0.type == contentAction.action }) else {
            return
        }
        Task {
            do {
                try await repository.trackEngagementEvent(urls: event.urls)
            } catch { GravityLogger.e("ContentEvent", "Engagement delivery failed: \(error)") }
        }
    }
}
