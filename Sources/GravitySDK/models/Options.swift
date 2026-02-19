import Foundation

public struct Options: Codable {
    public let isReturnCounter: Bool
    public let isReturnUserInfo: Bool
    public let isReturnAnalyticsMetadata: Bool
    public let isImplicitPageview: Bool
    public let isImplicitImpression: Bool
    
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
}
