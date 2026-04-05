import Foundation

public struct Options: Codable {
    public let isReturnCounter: Bool
    public let isReturnUserInfo: Bool
    public let isReturnAnalyticsMetadata: Bool
    public let isImplicitPageview: Bool
    public let isImplicitImpression: Bool
    public let isBuildEngagementUrl: Bool = true
    
    public init(
        isReturnCounter: Bool = false,
        isReturnUserInfo: Bool = false,
        isReturnAnalyticsMetadata: Bool = false,
        isImplicitPageview: Bool = false,
        isImplicitImpression: Bool = true
    ) {
        self.isReturnCounter = isReturnCounter
        self.isReturnUserInfo = isReturnUserInfo
        self.isReturnAnalyticsMetadata = isReturnAnalyticsMetadata
        self.isImplicitPageview = isImplicitPageview
        self.isImplicitImpression = isImplicitImpression
    }

    enum CodingKeys: String, CodingKey {
        case isReturnCounter
        case isReturnUserInfo
        case isReturnAnalyticsMetadata
        case isImplicitPageview
        case isImplicitImpression
        case isBuildEngagementUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isReturnCounter = try container.decode(Bool.self, forKey: .isReturnCounter) ?? false
        isReturnUserInfo = try container.decode(Bool.self, forKey: .isReturnUserInfo) ?? false
        isReturnAnalyticsMetadata = try container.decode(Bool.self, forKey: .isReturnAnalyticsMetadata) ?? false
        isImplicitPageview = try container.decode(Bool.self, forKey: .isImplicitPageview) ?? false
        isImplicitImpression = try container.decode(Bool.self, forKey: .isImplicitImpression) ?? true
    }
}
