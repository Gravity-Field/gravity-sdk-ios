import Foundation
import Testing
@testable import GravitySDK

private struct CampaignNumberCase {
    let json: String
    let expected: Int?
}

private let campaignNumberCases: [CampaignNumberCase] = [
    .init(json: "1500.9", expected: 1500), .init(json: "-1.5", expected: -1),
    // JSONDecoder rejects the overflowing numeric token as Double/Int. The
    // optional metadata remains absent while its campaign and sibling survive.
    .init(json: "1e400", expected: nil),
    .init(json: #""\u00A01500\u3000""#, expected: 1500),
    .init(json: #""\u00851500""#, expected: 1500),
    .init(json: #""\uFEFF15""#, expected: nil),
    .init(json: #""\u200B15""#, expected: nil),
    .init(json: #""1.""#, expected: 1), .init(json: #""1.e2""#, expected: 100),
    .init(json: #""0.9999999999999999999999""#, expected: 0),
    .init(json: #""-0.9""#, expected: 0),
    .init(json: #""1e400""#, expected: Int.max),
    .init(json: #""-1e400""#, expected: Int.min),
    .init(json: #""1e-400""#, expected: 0),
    .init(json: #""1e999999999""#, expected: Int.max),
    .init(json: #""99999999999999999999""#, expected: Int.max),
    .init(json: #""9007199254740993""#, expected: 9007199254740993),
    .init(json: #""1_000""#, expected: nil), .init(json: #""1,5""#, expected: nil),
    .init(json: #""١٥""#, expected: nil),
    .init(json: #""9223372036854775807.9""#, expected: Int.max),
    .init(json: #""-9223372036854775808.9""#, expected: Int.min),
    .init(json: #""9007199254740993.9""#, expected: 9007199254740993),
    .init(json: #""0e999999999""#, expected: 0),
    .init(json: #""1e-999999999""#, expected: 0),
    .init(json: "0", expected: 0), .init(json: "1500", expected: 1500), .init(json: "15.9", expected: 15),
    .init(json: "-3.9", expected: -3), .init(json: #""1500""#, expected: 1500),
    .init(json: #"" 1500 ""#, expected: 1500), .init(json: #""1500.0""#, expected: 1500),
    .init(json: #""+5""#, expected: 5), .init(json: #""-3""#, expected: -3),
    .init(json: #""1e3""#, expected: 1000), .init(json: #"".5""#, expected: 0),
    .init(json: #""0x10""#, expected: nil), .init(json: "true", expected: nil),
    .init(json: "false", expected: nil), .init(json: "null", expected: nil),
    .init(json: "{}", expected: nil), .init(json: "[]", expected: nil),
    .init(json: #""""#, expected: nil), .init(json: #""  ""#, expected: nil),
    .init(json: #""abc""#, expected: nil), .init(json: #""NaN""#, expected: nil),
    .init(json: #""Infinity""#, expected: nil), .init(json: #""-inf""#, expected: nil),
    .init(json: "1e100", expected: Int.max), .init(json: "-1e100", expected: Int.min),
    .init(json: #""1e100""#, expected: Int.max), .init(json: #""-1e100""#, expected: Int.min),
    .init(json: "9223372036854775807", expected: Int.max),
    .init(json: "-9223372036854775808", expected: Int.min),
    .init(json: #""9223372036854775807""#, expected: Int.max)
]

@Test func campaignNumbersAreTolerantWithoutDroppingSiblings() throws {
    for field in ["priority", "delayTime"] {
        for item in campaignNumberCases {
            let data = Data("{\"campaigns\":[{\"campaignId\":\"first\",\"\(field)\":\(item.json)},{\"campaignId\":\"sibling\"}]}".utf8)
            let response = try JSONDecoder().decode(CampaignIdsResponse.self, from: data)
            #expect(response.campaigns.count == 2)
            let campaign = try #require(response.campaigns.first)
            #expect((field == "priority" ? campaign.priority : campaign.delayTime) == item.expected,
                    "\(field): \(item.json)")
            #expect(response.campaigns[1].priority == nil)
            #expect(response.campaigns[1].delayTime == nil)
        }
    }
}

@Test func nonfiniteStringsAreAbsentEvenWithFloatStringConversionEnabled() throws {
    // These values decode as strings first, so the decimal grammar rejects them.
    // Plain JSON cannot supply nonfinite numeric tokens to the SDK's JSONDecoder;
    // this checks string rejection, not the parser's defensive isFinite branch.
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
        positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    for spelling in ["Infinity", "-Infinity", "NaN"] {
        let data = Data("{\"campaignId\":\"c\",\"priority\":\"\(spelling)\",\"delayTime\":\"\(spelling)\"}".utf8)
        let campaign = try decoder.decode(CampaignId.self, from: data)
        #expect(campaign.priority == nil)
        #expect(campaign.delayTime == nil)
    }
}

@Test func automaticDelaysAreSafeForEveryParserVector() throws {
    for item in campaignNumberCases {
        let data = Data("{\"campaignId\":\"c\",\"delayTime\":\(item.json)}".utf8)
        let campaign = try JSONDecoder().decode(CampaignId.self, from: data)
        #expect(campaign.delayTime == item.expected)
        let nanoseconds = campaignDelayNanoseconds(campaign.delayTime)
        guard let parsed = item.expected, parsed > 0 else {
            #expect(nanoseconds == nil)
            continue
        }
        let sleep = try #require(nanoseconds)
        #expect(sleep > 0)
        #expect(sleep <= UInt64(Int64.max))
    }
}

@Test func campaignNumbersStripExactlyUnicodeWhiteSpace() throws {
    let whiteSpace: [UInt32] = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0,
        0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
        0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
    for scalar in whiteSpace + [0xFEFF, 0x200B] {
        let character = String(Unicode.Scalar(scalar)!)
        let string = character + "1500" + character
        for field in ["priority", "delayTime"] {
            let data = try JSONSerialization.data(withJSONObject: ["campaigns": [
                ["campaignId": "first", field: string], ["campaignId": "sibling"]]])
            let response = try JSONDecoder().decode(CampaignIdsResponse.self, from: data)
            #expect(response.campaigns.count == 2)
            let value = field == "priority" ? response.campaigns[0].priority : response.campaigns[0].delayTime
            #expect(value == (whiteSpace.contains(scalar) ? 1500 : nil))
        }
    }
}
