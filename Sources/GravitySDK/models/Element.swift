import Foundation

public struct Element: Decodable {
    public let type: ElementType
    public let text: String?
    public let src: String?
    public let onClick: OnClickModel?
    public let style: Style
    
    public init(
        type: ElementType,
        text: String? = nil,
        src: String? = nil,
        onClick: OnClickModel? = nil,
        style: Style = Style.empty
    ) {
        self.type = type
        self.text = text
        self.src = src
        self.onClick = onClick
        self.style = style
    }
}

public enum ElementType: Decodable, Equatable {
    case image
    case text
    case button
    case spacer
    case productsContainer
    case unknown(String)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ElementType.fromString(rawValue)
    }
    
    public static func fromString(_ type: String) -> ElementType {
        switch type {
        case "image": return .image
        case "text": return .text
        case "button": return .button
        case "spacer": return .spacer
        case "productsContainer", "products-container", "products_container": return .productsContainer
        default: return .unknown(type)
        }
    }
}

public struct OnClickModel: Decodable {
    public let action: Action
    public let copyData: String?
    public let step: Int?
    public let url: String?
    public let type: FollowUrlType?
    public let deeplink: String?
    public let closeOnClick: Bool?
    
    public init(
        action: Action,
        copyData: String? = nil,
        step: Int? = nil,
        url: String? = nil,
        type: FollowUrlType? = nil,
        deeplink: String? = nil,
        closeOnClick: Bool? = nil
    ) {
        self.action = action
        self.copyData = copyData
        self.step = step
        self.url = url
        self.type = type
        self.deeplink = deeplink
        self.closeOnClick = closeOnClick
    }
}

public enum FollowUrlType: Decodable, Equatable {
    case browser
    case webview
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = FollowUrlType.fromString(rawValue)
    }
    
    public static func fromString(_ type: String) -> FollowUrlType {
        switch type {
        case "browser": return .browser
        case "webview": return .webview
        default: return .browser
        }
    }
}
