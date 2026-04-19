import Foundation

public struct Products: Decodable {
    public let strategyId: String
    public let fallback: Bool
    public let name: String?
    public let slots: [Slot]?
    public let pageNumber: Int?
    public let countPages: Int?

    enum CodingKeys: String, CodingKey {
        case strategyId, fallback, name, slots, pageNumber, countPages
    }

    public init(
        strategyId: String,
        fallback: Bool,
        name: String?,
        slots: [Slot]? = nil,
        pageNumber: Int?,
        countPages: Int?,
    ) {
        self.strategyId = strategyId
        self.fallback = fallback
        self.name = name
        self.slots = slots
        self.pageNumber = pageNumber
        self.countPages = countPages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.strategyId = try container.decode(String.self, forKey: .strategyId)
        self.fallback = try container.decode(Bool.self, forKey: .fallback)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.pageNumber = try container.decodeIfPresent(Int.self, forKey: .pageNumber)
        self.countPages = try container.decodeIfPresent(Int.self, forKey: .countPages)

        var decodedSlots = try container.decodeIfPresent([Slot].self, forKey: .slots)
        if let filter = GravitySDK.instance.productFilter {
            decodedSlots = decodedSlots?.filter(filter)
        }
        self.slots = decodedSlots
    }
}

public struct Slot: Decodable {
    public let item: [String: Any?]
    public let fallback: Bool
    public let strId: Int
    public let slotId: String?
    public let events: [ProductEvent]?

    enum CodingKeys: String, CodingKey {
        case item, fallback, strId, slotId, events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let itemContainer = try container.decode([String: JSONAny].self, forKey: .item)
        self.item = itemContainer.mapValues { $0.value }

        self.fallback = try container.decode(Bool.self, forKey: .fallback)
        self.strId = try container.decode(Int.self, forKey: .strId)
        self.slotId = try container.decodeIfPresent(String.self, forKey: .slotId)
        self.events = try container.decodeIfPresent([ProductEvent].self, forKey: .events)
    }
}
