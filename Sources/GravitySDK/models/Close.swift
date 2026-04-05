import Foundation

public struct Close: Decodable {
    public let style: Style
    public let image: String?
    public let onClick: OnClickModel?
    
    public init(
        style: Style = Style.empty,
        image: String? = nil,
        onClick: OnClickModel? = nil
    ) {
        self.style = style
        self.image = image
        self.onClick = onClick
    }

    enum CodingKeys: String, CodingKey {
        case style, image, onClick
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = (try? container.decodeIfPresent(Style.self, forKey: .style)) ?? Style.empty
        image = try container.decodeIfPresent(String.self, forKey: .image)
        onClick = try container.decodeIfPresent(OnClickModel.self, forKey: .onClick)
    }
}
