public class ProductEngagement {
    public let slot: Slot
    public let content: CampaignContent
    public let campaign: Campaign
    
    public init(slot: Slot, content: CampaignContent, campaign: Campaign) {
        self.slot = slot
        self.content = content
        self.campaign = campaign
    }
}

public class ProductClickEngagement: ProductEngagement {
    public override init(slot: Slot, content: CampaignContent, campaign: Campaign) {
        super.init(slot: slot, content: content, campaign: campaign)
    }
}

public class ProductVisibleImpressionEngagement: ProductEngagement {
    public override init(slot: Slot, content: CampaignContent, campaign: Campaign) {
        super.init(slot: slot, content: content, campaign: campaign)
    }
}
