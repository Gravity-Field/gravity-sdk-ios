import Foundation

public struct Container: Decodable {
    public let style: Style?
    public let onClick: OnClickModel?

    public init(
        style: Style? = nil,
        onClick: OnClickModel? = nil
    ) {
        self.style = style
        self.onClick = onClick
    }
}
