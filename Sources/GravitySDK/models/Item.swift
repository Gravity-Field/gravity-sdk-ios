import Foundation

public struct Item: Decodable {
    public let id: String
    public let values: [String: String]

    public init(
        id: String,
        values: [String: String] = [:]
    ) {
        self.id = id
        self.values = values
    }

    enum CodingKeys: String, CodingKey {
        case id, values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        values = try container.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
    }
}
