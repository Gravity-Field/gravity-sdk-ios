import Foundation

public enum ContextType: String, Codable {
    case homepage = "HOMEPAGE"
    case product = "PRODUCT"
    case cart = "CART"
    case category = "CATEGORY"
    case search = "SEARCH"
    case other = "OTHER"
}

public struct PageContext: Codable {
    public let type: ContextType
    public let data: [String]
    public let location: String
    public let lng: String?
    public let pageNumber: Int?
    public let referrer: String?
    public let utm: [String: String]?
    public let attributes: [String: String]
    
    public init(
        type: ContextType,
        data: [String],
        location: String,
        lng: String? = nil,
        pageNumber: Int? = nil,
        referrer: String? = nil,
        utm: [String: String]? = nil,
        attributes: [String: String] = [:]
    ) {
        self.type = type
        self.data = data
        self.location = location
        self.lng = lng
        self.pageNumber = pageNumber
        self.referrer = lng
        self.utm = utm
        self.attributes = attributes
    }
}
