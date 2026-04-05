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

    enum CodingKeys: String, CodingKey {
        case type, text, src, onClick, style
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(ElementType.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        src = try container.decodeIfPresent(String.self, forKey: .src)
        onClick = try container.decodeIfPresent(OnClickModel.self, forKey: .onClick)
        style = try container.decodeIfPresent(Style.self, forKey: .style) ?? Style.empty
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
    public let closeOnClick: Bool
    
    public init(
        action: Action,
        copyData: String? = nil,
        step: Int? = nil,
        url: String? = nil,
        type: FollowUrlType? = nil,
        deeplink: String? = nil,
        closeOnClick: Bool = true
    ) {
        self.action = action
        self.copyData = copyData
        self.step = step
        self.url = url
        self.type = type
        self.deeplink = deeplink
        self.closeOnClick = closeOnClick
    }

    enum CodingKeys: String, CodingKey {
        case action, copyData, step, url, type, deeplink, closeOnClick
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(Action.self, forKey: .action)
        copyData = try container.decodeIfPresent(String.self, forKey: .copyData)
        step = try container.decodeIfPresent(Int.self, forKey: .step)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        type = try container.decodeIfPresent(FollowUrlType.self, forKey: .type)
        deeplink = try container.decodeIfPresent(String.self, forKey: .deeplink)
        closeOnClick = try container.decodeIfPresent(Bool.self, forKey: .closeOnClick) ?? true
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
