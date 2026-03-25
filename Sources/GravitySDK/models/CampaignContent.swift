import Foundation

public struct CampaignContent: Decodable {
    public let contentId: String
    public let templateSystemName: TemplateSystemName?
    public let deliveryMethod: DeliveryMethod
    public let contentType: String
    public let step: Int?
    public let variables: Variables?
    public let products: Products?
    public let events: [Event]?

    public init(
        contentId: String,
        templateSystemName: TemplateSystemName? = nil,
        deliveryMethod: DeliveryMethod,
        contentType: String,
        step: Int?,
        variables: Variables? = nil,
        products: Products? = nil,
        events: [Event]? = nil
    ) {
        self.contentId = contentId
        self.templateSystemName = templateSystemName
        self.deliveryMethod = deliveryMethod
        self.contentType = contentType
        self.step = step
        self.variables = variables
        self.products = products
        self.events = events
    }
}
