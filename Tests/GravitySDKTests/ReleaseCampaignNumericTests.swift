import XCTest
@testable import GravitySDK

final class ReleaseCampaignNumericTests: XCTestCase {
    func testRawNumbersUseBinaryPrecisionAndPreserveCampaignSiblings() throws {
        let vectors: [(String, Int?)] = [
            ("1e128", Int.max), ("1e-129", 0), ("1e-300", 0),
            ("1e400", nil), ("1e-400", 0), ("-1e400", nil),
            ("0.99999999999999999999", 1), ("1500.99999999999999999999", 1501),
            ("0", 0), ("42", 42), ("-42", -42), ("1500.9", 1500), ("-1.5", -1)
        ]
        for (token, expected) in vectors {
            let data = Data("{\"campaigns\":[{\"campaignId\":\"c\",\"priority\":\(token),\"delayTime\":\(token)},{\"campaignId\":\"sibling\",\"priority\":7,\"delayTime\":9}]}".utf8)
            let response = try JSONDecoder().decode(CampaignIdsResponse.self, from: data)
            XCTAssertEqual(response.campaigns.count, 2, token)
            XCTAssertEqual(response.campaigns[0].priority, expected, token)
            XCTAssertEqual(response.campaigns[0].delayTime, expected, token)
            XCTAssertEqual(response.campaigns[1].campaignId, "sibling", token)
            XCTAssertEqual(response.campaigns[1].priority, 7, token)
            XCTAssertEqual(response.campaigns[1].delayTime, 9, token)
        }
    }

    func testRawNumericDelayAndExactStringPrioritySurviveVisitAndEventWireResponses() async throws {
        let saved = UserDefaults.standard.string(forKey: "gravity_user_id")
        defer { UserDefaults.standard.set(saved, forKey: "gravity_user_id") }
        let fixture = TemporarySDKFixture()
        let sdk = fixture.initialize()
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let fetch = sdk.isFetchContentOnTrack
        defer { sdk.isFetchContentOnTrack = fetch }
        sdk.isFetchContentOnTrack = true
        let ids = Data(#"{"campaigns":[{"campaignId":"rounded-wrongly","priority":"0.99999999999999999999"},{"campaignId":"winner","priority":1,"delayTime":1500.99999999999999999999}]}"#.utf8)
        let content = Data(#"{"data":[{"payload":[{"campaignId":"winner","experienceId":"e","variationId":"v","decisionId":"d","contents":[{"contentId":"c","deliveryMethod":"modal","contentType":"native"}]}]}]}"#.utf8)
        for event in [false, true] {
            server.reset()
            server.setResponseHandler { request in .init(json: [:], rawBody: request.path == "/choose" ? content : ids) }
            let page = PageContext(type: .other, data: [], location: "decimal")
            let result = try await (event
                ? sdk.triggerEventNoShow(events: [CustomEvent(type: "decimal", name: "Decimal")], pageContext: page)
                : sdk.trackViewNoShow(pageContext: page))
            XCTAssertEqual(result?.delayTime, 1501)
            let request = try XCTUnwrap(server.recorded.first { $0.path == "/choose" })
            let chosen = try XCTUnwrap((request.body["data"] as? [[String: Any]])?.first)
            XCTAssertEqual(chosen["campaignId"] as? String, "winner")
            XCTAssertEqual(server.recorded.map(\.path), [event ? "/event" : "/visit", "/choose"])
        }
    }

}
