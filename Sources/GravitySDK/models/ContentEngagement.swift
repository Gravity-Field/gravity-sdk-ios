import Foundation

public class ContentEngagement {
    public let content: CampaignContent
    public let campaign: Campaign
    
    public init(content: CampaignContent, campaign: Campaign) {
        self.content = content
        self.campaign = campaign
    }
}

public class ContentImpressionEngagement: ContentEngagement {
    public override init(content: CampaignContent, campaign: Campaign) {
        super.init(content: content, campaign: campaign)
    }
}

public class ContentVisibleImpressionEngagement: ContentEngagement {
    public override init(content: CampaignContent, campaign: Campaign) {
        super.init(content: content, campaign: campaign)
    }
}

public class ContentCloseEngagement: ContentEngagement {
    public override init(content: CampaignContent, campaign: Campaign) {
        super.init(content: content, campaign: campaign)
    }
}
