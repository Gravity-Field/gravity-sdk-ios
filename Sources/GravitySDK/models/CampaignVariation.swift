import Foundation

public struct CampaignVariation: Decodable {
    public let campaignId: String
    public let experienceId: String
    public let variationId: String
    public let decisionId: String
    public let contents: [CampaignContent]
    
    public init(
        campaignId: String,
        experienceId: String,
        variationId: String,
        decisionId: String,
        contents: [CampaignContent] = []
    ) {
        self.campaignId = campaignId
        self.experienceId = experienceId
        self.variationId = variationId
        self.decisionId = decisionId
        self.contents = contents
    }
}
