import Foundation

public struct Campaign: Decodable {
    public let selector: String
    public let payload: [CampaignVariation]
    
    public init(
        selector: String,
        payload: [CampaignVariation] = []
    ) {
        self.selector = selector
        self.payload = payload
    }
}
