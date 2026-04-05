import Foundation

public struct ContentSettings: Codable {
    public let skusOnly: Bool
    public let fields: [String]?
    
    public init(
        skusOnly: Bool = false,
        fields: [String]? = nil
    ) {
        self.skusOnly = skusOnly
        self.fields = fields
    }

    enum CodingKeys: String, CodingKey {
        case skusOnly, fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skusOnly = try container.decodeIfPresent(Bool.self, forKey: .skusOnly) ?? false
        fields = try container.decodeIfPresent([String].self, forKey: .fields)
    }
}
