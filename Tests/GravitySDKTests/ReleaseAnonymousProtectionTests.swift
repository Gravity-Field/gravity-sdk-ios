import XCTest
@testable import GravitySDK

final class ReleaseAnonymousProtectionTests: XCTestCase {
    func testAnonymousOpeningsShareDurableProtectionAcrossSDKReinitialization() async throws {
        let savedUID = UserDefaults.standard.string(forKey: "gravity_user_id")
        defer { UserDefaults.standard.set(savedUID, forKey: "gravity_user_id") }
        let fixture = TemporarySDKFixture()
        let first = fixture.initialize()
        try await first.resetUser()
        await first.visibleImpressionDelivery.stop()
        let scope = first.impressionScope
        let store = try XCTUnwrap(first.visibleImpressionDelivery.store)
        try store.insert(.init(id: UUID(), scope: scope, campaignId: "anonymous", contentId: "content",
            urls: ["http://127.0.0.1:1/visible"]))
        let second = fixture.initialize()
        await second.visibleImpressionDelivery.stop()
        XCTAssertNil(second.user)
        XCTAssertNil(GravityRepository.instance.userForRequest(nil).uid)
        XCTAssertEqual(second.impressionScope, scope)
        let request = second.presentationGate.beginRequest(location: "reopened", newScreen: true)
        XCTAssertNil(second.presentationGate.reserve(campaignId: "anonymous", request: request))
        XCTAssertEqual(second.visibleImpressionDelivery.store?.entries.count, 1)
    }
}
