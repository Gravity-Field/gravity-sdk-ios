import XCTest
@testable import GravitySDK

final class ChooseStringIdentifierTests: XCTestCase {
    func testAllChooseIdentifiersArriveAsExactJSONStringValues() async throws {
        let saved = UserDefaults.standard.string(forKey: "gravity_user_id")
        defer { UserDefaults.standard.set(saved, forKey: "gravity_user_id") }
        let fixture = TemporarySDKFixture()
        let sdk = fixture.initialize()
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        let page = PageContext(type: .other, data: [], location: "identifiers")
        let identifiers = ["101", "1e3", "-0", "true", "false", "null", "", "007", "12345678901234567890", "q\"uote", #"{"a":1}"#, "[1]"]
        for value in identifiers {
            server.reset()
            _ = await sdk.getContentBySelector(selector: value, pageContext: page)
            _ = await sdk.getContentByGroupSelector(groupSelector: value, pageContext: page)
            _ = await sdk.getContentByCampaignId(value, page)
            let requests = server.recorded.filter { $0.path == "/choose" }
            XCTAssertEqual(requests.count, 3)
            for (request, field) in zip(requests, ["selector", "group", "campaignId"]) {
                let data = try XCTUnwrap((request.body["data"] as? [[String: Any]])?.first)
                XCTAssertTrue(data[field] is String, "\(field) must remain a string for \(value)")
                XCTAssertEqual(data[field] as? String, value)
            }
        }
        withExtendedLifetime(fixture) {}
    }
}
