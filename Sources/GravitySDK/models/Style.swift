import Foundation
import SwiftUI
import UIKit
import os


public struct Style: Decodable, Equatable {
    public let backgroundColor: Color?
    public let pressColor: Color?
    public let outlineColor: Color?
    public let cornerRadius: Double?
    public let size: GravitySize?
    public let margin: GravityMargin?
    public let padding: GravityPadding?
    public let fontSize: Double?
    public let fontWeight: Double?
    public let textColor: Color?
    public let textStyle: GravityTextStyle?
    public let fit: GravityContentScale?
    public let contentAlignment: GravityContentAlignment?
    public let layoutWidth: GravityLayoutWidth?
    public let positioned: GravityPositioned?
    public let weight: Float?
    public let productContainerType: ProductContainerType?
    public let gridColumns: Int?
    public let rowSpacing: Double?

    public init(
        backgroundColor: Color? = nil,
        pressColor: Color? = nil,
        outlineColor: Color? = nil,
        cornerRadius: Double? = nil,
        size: GravitySize? = nil,
        margin: GravityMargin? = nil,
        padding: GravityPadding? = nil,
        fontSize: Double? = nil,
        fontWeight: Double? = nil,
        textColor: Color? = nil,
        textStyle: GravityTextStyle? = nil,
        fit: GravityContentScale? = nil,
        contentAlignment: GravityContentAlignment? = nil,
        layoutWidth: GravityLayoutWidth? = nil,
        positioned: GravityPositioned? = nil,
        weight: Float? = nil,
        productContainerType: ProductContainerType? = nil,
        gridColumns: Int? = nil,
        rowSpacing: Double? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.pressColor = pressColor
        self.outlineColor = outlineColor
        self.cornerRadius = cornerRadius
        self.size = size
        self.margin = margin
        self.padding = padding
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.textColor = textColor
        self.textStyle = textStyle
        self.fit = fit
        self.contentAlignment = contentAlignment
        self.layoutWidth = layoutWidth
        self.positioned = positioned
        self.weight = weight
        self.productContainerType = productContainerType
        self.gridColumns = gridColumns
        self.rowSpacing = rowSpacing
    }

    private enum CodingKeys: String, CodingKey {
        case backgroundColor, pressColor, outlineColor, cornerRadius, size, margin, padding
        case fontSize, fontWeight, textColor, textcolor, textStyle, fit, contentAlignment, layoutWidth
        case positioned, weight, productContainerType, gridColumns, rowSpacing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        backgroundColor = container.decodeOptionalColor(forKey: .backgroundColor)
        pressColor = container.decodeOptionalColor(forKey: .pressColor)
        outlineColor = container.decodeOptionalColor(forKey: .outlineColor)
        if let color = container.decodeOptionalColor(forKey: .textColor) {
            textColor = color
        } else if let color = container.decodeOptionalColor(forKey: .textcolor) {
            textColor = color
        } else {
            textColor = nil
        }
        fit = try? container.decodeIfPresent(GravityContentScale.self, forKey: .fit)
        fontSize = try? container.decodeOptionalFontSize(forKey: .fontSize)
        fontWeight = try? container.decodeOptionalFontWeight(forKey: .fontWeight)
        cornerRadius = try? container.decodeOptionalDimension(forKey: .cornerRadius)
        size = try? container.decodeIfPresent(GravitySize.self, forKey: .size)
        margin = try? container.decodeIfPresent(GravityMargin.self, forKey: .margin)
        padding = try? container.decodeIfPresent(GravityPadding.self, forKey: .padding)
        textStyle = try? container.decodeIfPresent(GravityTextStyle.self, forKey: .textStyle)
        contentAlignment = try? container.decodeIfPresent(GravityContentAlignment.self, forKey: .contentAlignment)
        layoutWidth = try? container.decodeIfPresent(GravityLayoutWidth.self, forKey: .layoutWidth)
        positioned = try? container.decodeIfPresent(GravityPositioned.self, forKey: .positioned)
        weight = try? container.decodeIfPresent(Float.self, forKey: .weight)
        productContainerType = try? container.decodeIfPresent(ProductContainerType.self, forKey: .productContainerType)
        gridColumns = try? container.decodeIfPresent(Int.self, forKey: .gridColumns)
        rowSpacing = try? container.decodeOptionalDimension(forKey: .rowSpacing)
    }

    public static let empty = Style()
}

public struct GravitySize: Codable, Equatable {
    public let width: Double?
    public let height: Double?

    public init(width: Double? = nil, height: Double? = nil) {
        self.width = width
        self.height = height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.width = (try? container.decodeOptionalDimension(forKey: .width))
        self.height = (try? container.decodeOptionalDimension(forKey: .height))
    }

    private enum CodingKeys: String, CodingKey {
        case width, height
    }
}

public struct GravityMargin: Codable, Equatable {
    public let left: Double
    public let right: Double
    public let top: Double
    public let bottom: Double

    public init(left: Double = 0.0, right: Double = 0.0, top: Double = 0.0, bottom: Double = 0.0) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.left = (try? container.decodeOptionalDimension(forKey: .left)) ?? 0.0
        self.right = (try? container.decodeOptionalDimension(forKey: .right)) ?? 0.0
        self.top = (try? container.decodeOptionalDimension(forKey: .top)) ?? 0.0
        self.bottom = (try? container.decodeOptionalDimension(forKey: .bottom)) ?? 0.0
    }

    private enum CodingKeys: String, CodingKey {
        case left, right, top, bottom
    }
}

public struct GravityPadding: Codable, Equatable {
    public let left: Double
    public let right: Double
    public let top: Double
    public let bottom: Double

    public init(left: Double = 0.0, right: Double = 0.0, top: Double = 0.0, bottom: Double = 0.0) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.left = (try? container.decodeOptionalDimension(forKey: .left)) ?? 0.0
        self.right = (try? container.decodeOptionalDimension(forKey: .right)) ?? 0.0
        self.top = (try? container.decodeOptionalDimension(forKey: .top)) ?? 0.0
        self.bottom = (try? container.decodeOptionalDimension(forKey: .bottom)) ?? 0.0
    }

    private enum CodingKeys: String, CodingKey {
        case left, right, top, bottom
    }
}

public struct GravityPositioned: Codable, Equatable {
    public let left: Double?
    public let right: Double?
    public let top: Double?
    public let bottom: Double?

    public init(left: Double? = nil, right: Double? = nil, top: Double? = nil, bottom: Double? = nil) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.left = (try? container.decodeOptionalDimension(forKey: .left))
        self.right = (try? container.decodeOptionalDimension(forKey: .right))
        self.top = (try? container.decodeOptionalDimension(forKey: .top))
        self.bottom = (try? container.decodeOptionalDimension(forKey: .bottom))
    }

    private enum CodingKeys: String, CodingKey {
        case left, right, top, bottom
    }
}

public enum GravityContentScale: String, Codable, Equatable {
    case fillBounds = "fill"
    case fit = "contain"
    case crop = "cover"
    case fillWidth = "fitWidth"
    case fillHeight = "fitHeight"
    case none = "none"
    case inside = "scaleDown"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = GravityContentScale(rawValue: rawValue) ?? .fit
    }
}

public enum GravityContentAlignment: String, Codable {
    case start = "start"
    case center = "center"
    case end = "end"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = GravityContentAlignment(rawValue: rawValue) ?? .start
    }


#if canImport(SwiftUI)
    @available(iOS 13.0, *)
    public func toHorizontalAlignment() -> HorizontalAlignment {
        switch self {
        case .start: return .leading
        case .center: return .center
        case .end: return .trailing
        }
    }
    
    @available(iOS 13.0, *)
    public func toVerticalAlignment() -> VerticalAlignment {
        switch self {
        case .start: return .top
        case .center: return .center
        case .end: return .bottom
        }
    }

    @available(iOS 13.0, *)
    public func toAlignment() -> Alignment {
        switch self {
        case .start: return .top
        case .center: return .center
        case .end: return .bottom
        }
    }

    @available(iOS 13.0, *)
    public func toTextAlignment() -> TextAlignment {
        switch self {
        case .start: return .leading
        case .center: return .center
        case .end: return .trailing
        }
    }
#endif
}

public struct GravityTextStyle: Decodable, Equatable {
    public let fontSize: Double?
    public let fontWeight: Double?
    public let color: Color?

    public init(fontSize: Double?, fontWeight: Double?, color: Color?) {
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.color = color
    }

    private enum CodingKeys: String, CodingKey {
        case fontSize, fontWeight, color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fontSize = try? container.decodeOptionalFontSize(forKey: .fontSize)
        self.fontWeight = try? container.decodeOptionalFontWeight(forKey: .fontWeight)
        self.color = container.decodeOptionalColor(forKey: .color)
    }
}

public enum GravityLayoutWidth: String, Codable {
    case matchParent = "match_parent"
    case wrapContent = "wrap_content"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = GravityLayoutWidth(rawValue: rawValue) ?? .matchParent
    }
}

public enum ProductContainerType: String, Codable {
    case row = "row"
    case grid = "grid"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if let value = ProductContainerType(rawValue: rawValue) {
            self = value
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ProductContainerType value: \(rawValue)"
            )
        }
    }
}

extension KeyedDecodingContainer {
    func decodeOptionalColor(forKey key: K) -> Color?  {
        guard let colorString = try? self.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return ParseUtils.parseColor(colorString)
    }

    func decodeOptionalDimension(forKey key: K) throws -> Double? {
        if let value = try? self.decode(Double.self, forKey: key) {
            return value
        } else if let value = try? self.decode(Int.self, forKey: key) {
            return Double(value)
        } else if let value = try? self.decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeOptionalFontSize(forKey key: K) throws -> Double? {
        if let value = try? self.decode(Double.self, forKey: key) {
            return value
        } else if let value = try? self.decode(Int.self, forKey: key) {
            return Double(value)
        } else if let value = try? self.decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeOptionalFontWeight(forKey key: K) throws -> Double? {
        if let value = try? self.decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}

extension Double {
    func toWeight() -> Font.Weight {
        switch self {
        case 100: return .ultraLight
        case 200: return .thin
        case 300: return .light
        case 400 : return .regular
        case 500: return .medium
        case 600: return .semibold
        case 700: return .bold
        case 800: return .heavy
        case 900: return .black
        default: return .regular
        }
    }
}
