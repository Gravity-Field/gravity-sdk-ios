import XCTest
@testable import GravitySDK

final class TrackingConfigurationTests: XCTestCase {
    func testUninstalledInstanceAndReinitializationShareSettings() {
        let fixture = TemporarySDKFixture()
        fixture.initialize() // Deliberately initialize first: test order is irrelevant.
        let placeholder = GravitySDK(apiKey: "", section: "", gravityEventCallback: nil,
            productViewBuilder: nil, productFilter: nil, uiSettings: nil,
            visibleImpressionStore: VisibleImpressionStore(fileURL: fixture.root.appendingPathComponent("placeholder.json")))
        let oldFetch = placeholder.isFetchContentOnTrack
        let oldTimeout = placeholder.staleContentTimeout
        defer {
            GravitySDK.instance.isFetchContentOnTrack = oldFetch
            GravitySDK.instance.staleContentTimeout = oldTimeout
        }
        placeholder.isFetchContentOnTrack = false
        placeholder.staleContentTimeout = 31
        let first = fixture.initialize()
        XCTAssertFalse(first.isFetchContentOnTrack)
        XCTAssertEqual(first.staleContentTimeout, 31)
        first.staleContentTimeout = 45
        let second = fixture.initialize()
        XCTAssertFalse(second.isFetchContentOnTrack)
        XCTAssertEqual(second.staleContentTimeout, 45)
        XCTAssertEqual(placeholder.staleContentTimeout, 45)
    }
}
