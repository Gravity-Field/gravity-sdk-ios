import Foundation

/// A parsed model together with the raw JSON of the same server response.
/// `json` keeps every key, including the ones the model does not know,
/// and JSON null values.
public struct GravityDataResponse<T> {
    public let data: T
    public let json: JSONValue

    public init(data: T, json: JSONValue) {
        self.data = data
        self.json = json
    }
}
