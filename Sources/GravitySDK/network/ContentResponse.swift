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
}
