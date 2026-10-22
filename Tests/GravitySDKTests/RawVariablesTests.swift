import Foundation
import Testing
@testable import GravitySDK

private func response(variables: String?) -> Data {
    let variablesField = variables.map { #", "variables": \#($0)"# } ?? ""
    return Data(#"""
    {
      "user": {"uid": "u", "ses": "s"},
      "data": [{
        "selector": "sel",
        "payload": [{
          "campaignId": "c", "experienceId": "e", "variationId": "v", "decisionId": "d",
          "contents": [{
            "contentId": "content-1", "contentType": "native", "deliveryMethod": "inline"
            \#(variablesField)
          }]
        }]
      }]
    }
    """#.utf8)
}

private let variables = #"""
{
  "elements": [{"type": "text", "text": "Hi"}],
  "onLoad": null,
  "ab_button_color": "#FF0000",
  "ab_limit": 3,
  "ab_ratio": 0.5,
  "ab_enabled": true,
  "ab_missing": null,
  "ab_list": [1, "two", null, {"k": "v"}],
  "ab_nested": {"inner": {"deep": [true, false]}, "none": null}
}
"""#

private func content(_ data: Data) throws -> CampaignContent {
    let parsed = try parseContentResponse(data)
    return try #require(parsed.data.data.first?.payload.first?.contents.first)
}

@Test func unknownKeysAndJsonTypesAreKept() throws {
    let raw = try content(response(variables: variables)).rawVariables

    #expect(raw["ab_button_color"] == .string("#FF0000"))
    #expect(raw["ab_limit"]?.intValue == 3)
    #expect(raw["ab_ratio"]?.doubleValue == 0.5)
    #expect(raw["ab_enabled"] == .bool(true))
    #expect(raw["ab_missing"] == .null)
    #expect(raw["onLoad"] == .null)
}

@Test func nestedValuesKeepNullsInArraysAndObjects() throws {
    let raw = try content(response(variables: variables)).rawVariables

    #expect(raw["ab_list"] == .array([.integer(1), .string("two"), .null, .object(["k": .string("v")])]))
    #expect(raw["ab_list"]?[2]?.isNull == true)
    #expect(raw["ab_nested"]?["inner"]?["deep"] == .array([.bool(true), .bool(false)]))
    #expect(raw["ab_nested"]?["none"] == .null)
}

@Test func keyAccessOnVariables() throws {
    let vars = try #require(try content(response(variables: variables)).variables)

    #expect(vars["ab_button_color"]?.stringValue == "#FF0000")
    #expect(vars["ab_limit"]?.stringValue == nil)
    #expect(vars["no_such_key"] == nil)
}

@Test func typedFieldsStillDecode() throws {
    let vars = try #require(try content(response(variables: variables)).variables)

    let element = try #require(vars.elements?.first)
    #expect(vars.elements?.count == 1)
    #expect(element.type == .text)
    #expect(element.text == "Hi")
    #expect(vars.onLoad == nil)
}

@Test func contentWithoutVariablesHasEmptyRaw() throws {
    let content = try content(response(variables: nil))

    #expect(content.variables == nil)
    #expect(content.rawVariables.isEmpty)
}

@Test func handBuiltVariablesHaveEmptyRaw() {
    let vars = Variables()

    #expect(vars.raw.isEmpty)
    #expect(vars["anything"] == nil)
}

@Test func emptyResponse() throws {
    let parsed = try parseContentResponse(Data("{}".utf8))

    #expect(parsed.data.data.isEmpty)
    #expect(parsed.json == .object([:]))
}

@Test func rawJsonMatchesTheModelOfTheSameResponse() throws {
    let data = response(variables: variables)
    let parsed = try parseContentResponse(data)

    let campaign = try #require(parsed.json["data"]?[0])
    let payload = try #require(campaign["payload"]?[0])
    #expect(campaign["selector"]?.stringValue == parsed.data.data.first?.selector)
    #expect(payload["campaignId"]?.stringValue == parsed.data.data.first?.payload.first?.campaignId)
    #expect(payload["contents"]?[0]?["variables"] == .object(try content(data).rawVariables))
    #expect(parsed.json["user"] == .object(["uid": .string("u"), "ses": .string("s")]))
}

@Test func jsonValueRoundTrips() throws {
    let value = JSONValue.object([
        "s": .string("x"), "i": .integer(Int64.max), "n": .number(1.5), "b": .bool(false), "z": .null,
        "a": .array([.integer(1), .null]), "o": .object(["k": .string("v")]),
    ])
    let decoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    #expect(decoded == value)
}

@Test func largeIntegersKeepPrecision() throws {
    let json = Data(#"{"a": 9007199254740993, "b": 9223372036854775807, "c": -9223372036854775808, "d": 1.5, "e": 2.0, "f": true, "g": 0}"#.utf8)
    let value = try JSONDecoder().decode(JSONValue.self, from: json)

    #expect(value["a"] == .integer(9_007_199_254_740_993))
    #expect(value["b"]?.int64Value == Int64.max)
    #expect(value["c"]?.int64Value == Int64.min)
    #expect(value["d"] == .number(1.5))
    #expect(value["d"]?.intValue == nil)
    #expect(value["e"]?.doubleValue == 2.0)
    #expect(value["f"] == .bool(true))
    #expect(value["g"] == .integer(0))
    #expect(value["g"]?.boolValue == nil)
}
