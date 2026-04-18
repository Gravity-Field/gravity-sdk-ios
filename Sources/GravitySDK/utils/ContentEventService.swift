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
        if callbackTrackingEvent {
            GravitySDK.instance.callbackTrackingEvent(
                ContentVisibleImpressionEvent(content: content, campaign: campaign)
            )
        }
        
        guard let onVisibleImpression = content.variables?.onVisibleImpression else { return }
        trackEngagement(contentAction: onVisibleImpression, content: content)
    }

    func sendContentClosed(
        _ content: CampaignContent,
        _ campaign: Campaign,
        callbackTrackingEvent: Bool = true
    ) {
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
            } catch {}
        }
    }
}
