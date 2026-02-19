import Foundation

public struct Container: Decodable {
    public let style: Style
    public let onClick: OnClickModel?
    
    public init(
        style: Style = Style.empty,
        onClick: OnClickModel? = nil
    ) {
        self.style = style
        self.onClick = onClick
    }
}
