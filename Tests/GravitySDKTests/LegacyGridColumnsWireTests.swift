import XCTest
@testable import GravitySDK

final class LegacyGridColumnsWireTests: XCTestCase {
    func testLegacyColumnsUseTheSameDimensionAndRangeRulesAsGridSettings() throws {
        let cases: [(String, Int?)] = [
            ("3", 3), ("3.0", 3), ("3.7", 3), (#""3""#, 3), (#""3px""#, 3),
            (#"" 3.7px ""#, 3), (#""1e1""#, 10), ("1", 1), ("12", 12),
            ("0.9", nil), ("0", nil), ("-3", nil), ("12.1", nil), ("13", nil),
            (#""13px""#, nil), (#""NaN""#, nil), (#""Infinity""#, nil),
            (#""3PX""#, nil), (#""""#, nil), (#""abc""#, nil), ("true", nil),
            ("null", nil), ("{}", nil), ("[]", nil)
        ]
        for (token, expected) in cases {
            for settings in ["", #", "gridSettings": {"columns": 13}"#] {
                let style = try JSONDecoder().decode(Style.self, from: Data("{\"gridColumns\":\(token)\(settings)}".utf8))
                XCTAssertEqual(style.gridColumns, expected, token)
                XCTAssertEqual(ProductsGridLayout(style: style, itemCount: 6).columns, expected ?? 2, token)
            }
            let preferred = try JSONDecoder().decode(Style.self, from: Data("{\"gridColumns\":\(token),\"gridSettings\":{\"columns\":4}}".utf8))
            XCTAssertEqual(ProductsGridLayout(style: preferred, itemCount: 6).columns, 4)
        }
    }
}
