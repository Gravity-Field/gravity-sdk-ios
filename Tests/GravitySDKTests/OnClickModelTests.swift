import Foundation
import Testing
@testable import GravitySDK

private func decodeOnClick(_ json: String) throws -> OnClickModel {
    try JSONDecoder().decode(OnClickModel.self, from: Data(json.utf8))
}

@Test func followUrlTypeDefaultsToBrowserWhenMissing() throws {
    let model = try decodeOnClick(#"{"action":"follow_url","url":"https://example.com"}"#)
    #expect(model.type == .browser)
}

@Test func followUrlTypeDefaultsToBrowserWhenNull() throws {
    let model = try decodeOnClick(#"{"action":"follow_url","url":"https://example.com","type":null}"#)
    #expect(model.type == .browser)
}

@Test func followUrlTypeParsesBrowser() throws {
    let model = try decodeOnClick(#"{"action":"follow_url","url":"https://example.com","type":"browser"}"#)
    #expect(model.type == .browser)
}

@Test func followUrlTypeParsesWebview() throws {
    let model = try decodeOnClick(#"{"action":"follow_url","url":"https://example.com","type":"webview"}"#)
    #expect(model.type == .webview)
}

@Test func followUrlTypeFallsBackToBrowserWhenUnknown() throws {
    let model = try decodeOnClick(#"{"action":"follow_url","url":"https://example.com","type":"in_app"}"#)
    #expect(model.type == .browser)
}

@Test func followUrlTypeFallsBackToBrowserWhenEmpty() throws {
    let model = try decodeOnClick(#"{"action":"follow_url","url":"https://example.com","type":""}"#)
    #expect(model.type == .browser)
}
