import Foundation

/// A parsed model together with the raw JSON of the same server response.
/// `json` keeps every key, including the ones the model does not know,
/// and JSON null values.
public struct GravityDataResponse<T> {
    public let data: T
    public let json: JSONValue

    /// Delay in integer milliseconds for the campaign chosen by a NoShow call.
    /// The host should wait before rendering. Zero means no extra wait, including
    /// missing or negative server delays and all direct getContent calls.
    /// NoShow returns loaded content immediately and never waits this delay.
    public let delayTime: Int

    public init(data: T, json: JSONValue, delayTime: Int = 0) {
        self.data = data
        self.json = json
        self.delayTime = max(0, delayTime)
    }
}
