import Foundation

public struct Variables: Decodable {
    public let frameUI: FrameUI?
    public let elements: [Element]
    public let onLoad: ContentActionModel?
    public let onImpression: ContentActionModel?
    public let onVisibleImpression: ContentActionModel?
    public let onClose: ContentActionModel?
    
    public init(
        frameUI: FrameUI? = nil,
        elements: [Element] = [],
        onLoad: ContentActionModel? = nil,
        onImpression: ContentActionModel? = nil,
        onVisibleImpression: ContentActionModel? = nil,
        onClose: ContentActionModel? = nil
    ) {
        self.frameUI = frameUI
        self.elements = elements
        self.onLoad = onLoad
        self.onImpression = onImpression
        self.onVisibleImpression = onVisibleImpression
        self.onClose = onClose
    }
}
