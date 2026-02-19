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
}
