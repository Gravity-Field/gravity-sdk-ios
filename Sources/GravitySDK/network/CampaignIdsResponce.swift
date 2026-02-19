struct CampaignIdsResponse: Codable {
    let user: User
    let campaigns: [CampaignId]
}

struct CampaignId: Codable {
    let campaignId: String
    let trigger: String
    let priority: Int?
    let delayTime: Int?
}
