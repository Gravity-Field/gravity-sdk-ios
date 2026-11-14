import Foundation

/// A recommendation rule sent with a content request, for example the filters
/// the user applied to a catalog. Sent in the `rules` field of the request item.
public struct RtRule: Codable, Equatable {
    public let id: Int?
    public let type: String
    public let slots: [Int]?
    public let conditions: [RtRuleCondition]

    public init(id: Int? = nil, type: String, slots: [Int]? = nil, conditions: [RtRuleCondition]) {
        self.id = id
        self.type = type
        self.slots = slots
        self.conditions = conditions
    }

    private enum CodingKeys: String, CodingKey { case id, type, slots, conditions }

    // Absent `id` and `slots` are written as explicit nulls, like the Flutter SDK.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(slots, forKey: .slots)
        try container.encode(conditions, forKey: .conditions)
    }
}

public struct RtRuleCondition: Codable, Equatable {
    public let field: String
    public let arguments: [RtRuleArgument]

    public init(field: String, arguments: [RtRuleArgument]) {
        self.field = field
        self.arguments = arguments
    }
}

public struct RtRuleArgument: Codable, Equatable {
    public let action: String
    public let value: [String]

    public init(action: String, value: [String]) {
        self.action = action
        self.value = value
    }
}
