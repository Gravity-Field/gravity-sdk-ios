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
}
