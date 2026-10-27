import Foundation

/// A JSON value exactly as it arrived from the server: strings, numbers,
/// booleans, null, arrays and nested objects. Whole numbers that fit Int64
/// are kept as `.integer` so large ids do not lose precision; other numbers
/// are `.number`.
public enum JSONValue: Codable, Equatable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Any number as a Double; very large integers may round.
    public var doubleValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .number(let value): return value
        default: return nil
        }
    }

    /// The number as an Int, only when it is whole and fits exactly.
    public var intValue: Int? {
        switch self {
        case .integer(let value): return Int(exactly: value)
        case .number(let value): return Int(exactly: value)
        default: return nil
        }
    }

    public var int64Value: Int64? {
        switch self {
        case .integer(let value): return value
        case .number(let value): return Int64(exactly: value)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var isNull: Bool {
        self == .null
    }

    /// Value of `key` when this is an object.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// Element at `index` when this is an array.
    public subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }
}
