import Foundation

public struct CampaignContent: Decodable {
    public let contentId: String
    public let templateSystemName: TemplateSystemName?
    public let deliveryMethod: DeliveryMethod
    public let contentType: String
    public let step: Int?
    public let variables: Variables?
    public let products: Products?
    public let items: [Item]?
    public let custom: CustomModel?
    public let events: [Event]?

    public init(
        contentId: String,
        templateSystemName: TemplateSystemName? = nil,
        deliveryMethod: DeliveryMethod,
        contentType: String,
        step: Int?,
        variables: Variables? = nil,
        products: Products? = nil,
        items: [Item]? = nil,
        custom: CustomModel? = nil,
        events: [Event]? = nil
    ) {
        self.contentId = contentId
        self.templateSystemName = templateSystemName
        self.deliveryMethod = deliveryMethod
        self.contentType = contentType
        self.step = step
        self.variables = variables
        self.products = products
        self.items = items
        self.custom = custom
        self.events = events
    }

    /// Raw `variables` object of this content, including keys with no typed
    /// counterpart in `Variables`. Empty when the content has no variables.
    public var rawVariables: [String: JSONValue] {
        variables?.raw ?? [:]
    }
}

extension Array where Element == CampaignContent {
    func firstByStep() -> CampaignContent? {
        let lowestStep = filter { $0.step != nil }
            .min { ($0.step ?? 0) < ($1.step ?? 0) }
        return lowestStep ?? first
    }

    func firstByStepNullsFirst() -> CampaignContent? {
        min { lhs, rhs in
            switch (lhs.step, rhs.step) {
            case (nil, nil):
                return false
            case (nil, _):
                return true
            case (_, nil):
                return false
            case let (lhsStep?, rhsStep?):
                return lhsStep < rhsStep
            }
        }
    }
}
