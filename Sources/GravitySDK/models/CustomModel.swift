import Foundation

public struct CustomModel: Decodable {
    public let json: String?

    public init(json: String? = nil) {
        self.json = json
    }
}
