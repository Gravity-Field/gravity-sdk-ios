import Foundation

public struct User: Codable {
    public let uid: String?
    public let custom: String?
    public let ses: String?
    public let attributes: [String: String]?
    
    public init(
        uid: String? = nil,
        custom: String? = nil,
        ses: String? = nil,
        attributes: [String: String]? = nil
    ) {
        self.uid = uid
        self.custom = custom
        self.ses = ses
        self.attributes = attributes
    }
}
