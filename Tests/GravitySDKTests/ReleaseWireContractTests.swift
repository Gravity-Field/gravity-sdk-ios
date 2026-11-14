import XCTest
@testable import GravitySDK

final class ReleaseWireContractTests: XCTestCase {
    private let page = PageContext(type: .other, data: [], location: "release-wire")

    func testNonSuccessResponsesCannotPublishIdentityOrContentForAnyAPI() async throws {
        let savedUID = UserDefaults.standard.string(forKey: "gravity_user_id")
        defer { UserDefaults.standard.set(savedUID, forKey: "gravity_user_id") }
        let fixture = TemporarySDKFixture()
        let callbacks = TestRequestRecorder<TrackingEvent>()
        let sdk = fixture.initialize(callback: { callbacks.append($0) })
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let fetch = sdk.isFetchContentOnTrack
        defer { sdk.isFetchContentOnTrack = fetch }
        sdk.isFetchContentOnTrack = true
        for status in [300, 400, 401, 429, 503] {
            try await sdk.restoreUserId("known")
            let body: [String: Any] = ["user": ["uid": "rejected", "ses": "rejected-session"],
                "campaigns": [["campaignId": "rejected"]],
                "data": [["payload": [["campaignId": "rejected", "experienceId": "e", "variationId": "v", "decisionId": "d",
                    "contents": [["contentId": "rejected", "deliveryMethod": "modal", "contentType": "native"]]]]]]]
            server.setResponseHandler { _ in .init(json: body, status: status) }
            let before = server.recorded.count
            let selector = await sdk.getContentBySelectorWithDetails(selector: "s", pageContext: page)
            let campaign = await sdk.getContentByCampaignIdWithDetails("c", page)
            let group = await sdk.getContentByGroupSelector(groupSelector: "g", pageContext: page)
            let visit = try await sdk.trackViewNoShow(pageContext: page)
            let event = try await sdk.triggerEventNoShow(events: [CustomEvent(type: "release", name: "Release")], pageContext: page)
            XCTAssertNil(selector, "\(status)"); XCTAssertNil(campaign); XCTAssertNil(group)
            XCTAssertNil(visit); XCTAssertNil(event)
            let uid = await sdk.getUserId()
            XCTAssertEqual(uid, "known")
            XCTAssertNil(GravityRepository.instance.sessionManager.cachedUser(customUser: nil).ses)
            XCTAssertEqual(Array(server.recorded.dropFirst(before)).map(\.path), ["/choose", "/choose", "/choose", "/visit", "/event"])
        }
        XCTAssertTrue(callbacks.values.isEmpty)
    }

    func testStandardEventOptionalFieldsAreAbsentInActualEventBody() async throws {
        let fixture = TemporarySDKFixture()
        let sdk = fixture.initialize()
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let fetch = sdk.isFetchContentOnTrack
        defer { sdk.isFetchContentOnTrack = fetch }
        sdk.isFetchContentOnTrack = false
        let events: [TriggerEvent] = [AddToCartEvent(value: 1, productId: "p", quantity: 1),
            RemoveFromCartEvent(value: 1, productId: "p", quantity: 1), SyncCartEvent(value: 1),
            PurchaseEvent(uniqueTransactionId: "t", value: 1, cart: []), AddToWishlistEvent(value: 1, productId: "p"),
            SignUpEvent(), LoginEvent(), CustomEvent(type: "release", name: "Release")]
        _ = try await sdk.triggerEventNoShow(events: events, pageContext: page)
        let request = try XCTUnwrap(server.recorded.first)
        let payload = try XCTUnwrap(request.body["data"] as? [[String: Any]])
        XCTAssertEqual(payload.count, 8)
        for event in payload {
            XCTAssertFalse(event.values.contains { $0 is NSNull })
            XCTAssertNotNil(event["eventTime"] as? String)
            for field in ["currency", "hashedEmail", "cuid", "cuidType", "customProps"] { XCTAssertNil(event[field]) }
        }
        XCTAssertEqual(server.recorded.map(\.path), ["/event"])
    }

    func testNegativeStaleTimeoutClampsAndTracksWithoutChoosingContent() async throws {
        let fixture = TemporarySDKFixture()
        let sdk = fixture.initialize()
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let timeout = sdk.staleContentTimeout
        let fetch = sdk.isFetchContentOnTrack
        defer { sdk.staleContentTimeout = timeout; sdk.isFetchContentOnTrack = fetch }
        sdk.isFetchContentOnTrack = true
        sdk.staleContentTimeout = -0.5
        XCTAssertEqual(sdk.staleContentTimeout, 0)
        server.reset(campaigns: [["campaignId": "must-not-choose"]])
        let response = try await sdk.trackViewNoShow(pageContext: page)
        XCTAssertNil(response)
        XCTAssertEqual(server.recorded.map(\.path), ["/visit"])
    }
}
