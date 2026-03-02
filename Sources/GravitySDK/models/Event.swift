import Foundation

public enum Action: Decodable, Equatable {
    case load
    case impression
    case visibleImpression
    case close
    case copy
    case cancel
    case followUrl
    case followDeeplink
    case requestPush
    case requestTracking
    case unknown(String)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        switch rawValue {
        case "load": self = .load
        case "impression": self = .impression
        case "visible_impression": self = .visibleImpression
        case "close": self = .close
        case "copy": self = .copy
        case "cancel": self = .cancel
        case "follow_url": self = .followUrl
        case "follow_deeplink": self = .followDeeplink
        case "request_push": self = .requestPush
        case "request_tracking": self = .requestTracking
        default: self = .unknown(rawValue)
        }
    }
}

public struct Event: Decodable {
    public let type: Action
    public let urls: [String]
    
    public init(
        type: Action,
        urls: [String] = []
    ) {
        self.type = type
        self.urls = urls
    }
}

public enum ProductAction: Decodable, Equatable {
    case visibleImpression
    case click
    case unknown(String)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        switch rawValue {
        case "visible_impression": self = .visibleImpression
        case "click": self = .click
        default: self = .unknown(rawValue)
        }
    }
}

public struct ProductEvent: Decodable {
    public let type: ProductAction
    public let urls: [String]
    
    public init(
        type: ProductAction,
        urls: [String] = []
    ) {
        self.type = type
        self.urls = urls
    }
}
