import Foundation

public class TrackingEvent {
    public let campaign: Campaign
    
    public init(campaign: Campaign) {
        self.campaign = campaign
    }
}

public class ContentLoadEvent: TrackingEvent {
    public let content: CampaignContent
    
    public init(content: CampaignContent, campaign: Campaign) {
        self.content = content
        super.init(campaign: campaign)
    }
}

public class ContentImpressionEvent: TrackingEvent {
    public let content: CampaignContent
    
    public init(content: CampaignContent, campaign: Campaign) {
        self.content = content
        super.init(campaign: campaign)
    }
}

public class ContentVisibleImpressionEvent: TrackingEvent {
    public let content: CampaignContent
    
    public init(content: CampaignContent, campaign: Campaign) {
        self.content = content
        super.init(campaign: campaign)
    }
}

public class ContentCloseEvent: TrackingEvent {
    public let content: CampaignContent
    
    public init(content: CampaignContent, campaign: Campaign) {
        self.content = content
        super.init(campaign: campaign)
    }
}

public class CopyEvent: TrackingEvent {
    public let copiedValue: String
    public let content: CampaignContent
    
    public init(copiedValue: String, content: CampaignContent, campaign: Campaign) {
        self.copiedValue = copiedValue
        self.content = content
        super.init(campaign: campaign)
    }
}

public class CancelEvent: TrackingEvent {
    public let content: CampaignContent
    
    public init(content: CampaignContent, campaign: Campaign) {
        self.content = content
        super.init(campaign: campaign)
    }
}

public class FollowUrlEvent: TrackingEvent {
    public let url: String
    public let type: FollowUrlType
    public let content: CampaignContent
    
    public init(url: String, type: FollowUrlType, content: CampaignContent, campaign: Campaign) {
        self.url = url
        self.type = type
        self.content = content
        super.init(campaign: campaign)
    }
}

public class FollowDeeplinkEvent: TrackingEvent {
    public let deeplink: String
    public let content: CampaignContent
    
    public init(deeplink: String, content: CampaignContent, campaign: Campaign) {
        self.deeplink = deeplink
        self.content = content
        super.init(campaign: campaign)
    }
}

public class RequestPushEvent: TrackingEvent {
    public let content: CampaignContent
    
    public init(content: CampaignContent, campaign: Campaign) {
        self.content = content
        super.init(campaign: campaign)
    }
}

public class ProductImpressionEvent: TrackingEvent {
    public let slot: Slot
    public let content: CampaignContent
    
    public init(slot: Slot, content: CampaignContent, campaign: Campaign) {
        self.slot = slot
        self.content = content
        super.init(campaign: campaign)
    }
}
