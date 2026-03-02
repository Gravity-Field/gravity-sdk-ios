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
        guard let onLoad = content.variables.onLoad else { return }
        trackEvent(
            contentAction: onLoad,
            content: content,
            campaign: campaign,
            callbackTrackingEvent: callbackTrackingEvent
        )
    }

    func sendContentImpression(
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        guard let onImpression = content.variables.onImpression else { return }
        trackEvent(
            contentAction: onImpression,
            content: content,
            campaign: campaign,
            callbackTrackingEvent: callbackTrackingEvent
        )
    }

    func sendContentVisibleImpression(
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        guard let onVisibleImpression = content.variables.onVisibleImpression else { return }
        trackEvent(
            contentAction: onVisibleImpression,
            content: content,
            campaign: campaign,
            callbackTrackingEvent: callbackTrackingEvent
        )
    }

    func sendContentClosed(
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
        guard let onClose = content.variables.onClose else { return }
        trackEvent(
            contentAction: onClose,
            content: content,
            campaign: campaign,
            callbackTrackingEvent: callbackTrackingEvent
        )
    }

    private func trackEvent(
        contentAction: ContentActionModel,
        content: CampaignContent,
        campaign: Campaign,
        callbackTrackingEvent: Bool
    ) {
        guard let event = content.events?.first(where: { $0.type == contentAction.action }) else {
            return
        }

        Task {
            do {
                try await repository.trackEngagementEvent(urls: event.urls)

                if callbackTrackingEvent {
                    let trackingEvent: TrackingEvent?
                    switch contentAction.action {
                    case .load:
                        trackingEvent = ContentLoadEvent(content: content, campaign: campaign)
                    case .impression:
                        trackingEvent = ContentImpressionEvent(content: content, campaign: campaign)
                    case .visibleImpression:
                        trackingEvent = ContentVisibleImpressionEvent(content: content, campaign: campaign)
                    case .close:
                        trackingEvent = ContentCloseEvent(content: content, campaign: campaign)
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
