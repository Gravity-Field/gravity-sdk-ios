import Foundation

public struct Variables: Decodable {
    public let frameUI: FrameUI?
    public let elements: [Element]?
    public let onLoad: ContentActionModel?
    public let onImpression: ContentActionModel?
    public let onVisibleImpression: ContentActionModel?
    public let onClose: ContentActionModel?
    /// Raw `variables` object exactly as it arrived from the server, including
    /// keys that have no typed counterpart and null values. Empty for
    /// `Variables` constructed by hand rather than decoded from JSON.
    public let raw: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case frameUI, elements, onLoad, onImpression, onVisibleImpression, onClose
    }

    public init(
        frameUI: FrameUI? = nil,
        elements: [Element]? = nil,
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
        self.raw = [:]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameUI = try container.decodeIfPresent(FrameUI.self, forKey: .frameUI)
        elements = try container.decodeIfPresent([Element].self, forKey: .elements)
        onLoad = try container.decodeIfPresent(ContentActionModel.self, forKey: .onLoad)
        onImpression = try container.decodeIfPresent(ContentActionModel.self, forKey: .onImpression)
        onVisibleImpression = try container.decodeIfPresent(ContentActionModel.self, forKey: .onVisibleImpression)
        onClose = try container.decodeIfPresent(ContentActionModel.self, forKey: .onClose)
        raw = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }

    /// Reads an arbitrary `variables` key, e.g. `variables["my-param"]`.
    public subscript(key: String) -> JSONValue? {
        raw[key]
    }
}
