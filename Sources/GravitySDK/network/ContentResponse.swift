import Foundation

public struct ContentResponse: Decodable {
    public let user: User?
    public let data: [Campaign]

    public init(
        user: User? = nil,
        data: [Campaign] = []
    ) {
        self.user = user
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case user, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decodeIfPresent(User.self, forKey: .user)
        data = try container.decodeIfPresent([Campaign].self, forKey: .data) ?? []
    }
}
