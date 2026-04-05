import Foundation

struct JSONAny: Decodable {
    let value: Any?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = nil
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([JSONAny].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: JSONAny].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = nil
        }
    }
}
