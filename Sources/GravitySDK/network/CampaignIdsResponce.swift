struct CampaignIdsResponse: Codable {
    let user: User?
    let campaigns: [CampaignId]

    enum CodingKeys: String, CodingKey {
        case user, campaigns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decodeIfPresent(User.self, forKey: .user)
        campaigns = try container.decodeIfPresent([CampaignId].self, forKey: .campaigns) ?? []
    }
}

struct CampaignId: Codable {
    let campaignId: String
    let trigger: String
    let priority: Int?
    let delayTime: Int?

    enum CodingKeys: String, CodingKey {
        case campaignId, trigger, priority, delayTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        campaignId = try container.decode(String.self, forKey: .campaignId)
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? ""
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        delayTime = try container.decodeIfPresent(Int.self, forKey: .delayTime)
    }
}
