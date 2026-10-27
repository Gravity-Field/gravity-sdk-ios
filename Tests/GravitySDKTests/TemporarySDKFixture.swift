import Foundation
@testable import GravitySDK

/// Owns the entire outbox directory; no test namespace reaches Application Support.
final class TemporarySDKFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let apiKey: String
    let section: String

    init(apiKey: String = "test", section: String = "test") {
        self.apiKey = apiKey
        self.section = section
    }

    @discardableResult
    func initialize(callback: GravityEventCallback? = nil) -> GravitySDK {
        let store = VisibleImpressionStore(fileURL: root.appendingPathComponent("queue.json"))
        let sdk = GravitySDK(apiKey: apiKey, section: section, gravityEventCallback: callback,
            productViewBuilder: nil, productFilter: nil, uiSettings: nil, visibleImpressionStore: store)
        GravitySDK.initialize(sdk)
        return sdk
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}
