import Foundation

public struct ItemCard: Decodable {
    public let template: Template

    public init(template: Template) {
        self.template = template
    }
}

public struct Template: Decodable {
    public let frameUI: FrameUI?
    public let elements: [Element]

    public init(
        frameUI: FrameUI? = nil,
        elements: [Element] = []
    ) {
        self.frameUI = frameUI
        self.elements = elements
    }

    enum CodingKeys: String, CodingKey {
        case frameUI, elements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameUI = try container.decodeIfPresent(FrameUI.self, forKey: .frameUI)
        elements = try container.decodeIfPresent([Element].self, forKey: .elements) ?? []
    }
}
