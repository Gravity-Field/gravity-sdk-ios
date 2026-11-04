import XCTest
@testable import GravitySDK

final class ProductsGridLayoutTests: XCTestCase {
    func testConfirmedAdminFixturesDecodeAndIgnoreHeightOnlyForGrid() throws {
        for (index, json) in ProductsGridWireFixtures.elements.enumerated() {
            let element = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
            XCTAssertEqual(element.type, .productsContainer)
            XCTAssertEqual(element.style.productContainerType, .grid)
            XCTAssertNotNil(element.style.backgroundColor)
            XCTAssertEqual(element.style.margin, GravityMargin(left: 16, right: 16, top: 16, bottom: 16))
            XCTAssertEqual(element.style.size?.height, index == 3 ? 400 : 250)
            let layout = ProductsGridLayout(style: element.style, itemCount: 5)
            XCTAssertEqual(layout.columns, index == 0 ? 2 : 4)
            XCTAssertEqual(layout.horizontalSpacing, index == 0 ? 8 : 6)
            XCTAssertEqual(layout.verticalSpacing, index == 0 ? 8 : 6)
            XCTAssertEqual(layout.aspect, 1)
            XCTAssertEqual(layout.padding.top, index >= 2 ? 5 : 0)
            XCTAssertEqual(layout.padding.leading, index >= 2 ? 5 : 0)
            XCTAssertEqual(layout.padding.trailing, index >= 2 ? 5 : 0)
            XCTAssertEqual(layout.padding.bottom, index >= 2 ? 5 : 0)
            XCTAssertEqual(layout.rows, index == 0 ? 3 : 2)
        }
    }

    func testPixelStringsAndBareNumericDimensionsDecode() throws {
        for unit in ["", "px"] {
            let style = try JSONDecoder().decode(Style.self, from: Data("{\"gridSettings\":{\"columns\":\"3\(unit)\",\"horizontalSpacing\":\"12\(unit)\",\"verticalSpacing\":\"10\(unit)\"}}".utf8))
            XCTAssertEqual(ProductsGridLayout(style: style, itemCount: 1).columns, 3)
            XCTAssertEqual(style.gridSettings?.horizontalSpacingValue, 12)
            XCTAssertEqual(style.gridSettings?.verticalSpacingValue, 10)
        }
    }

    func testGridSettingsDecodeDimensions() throws {
        let cases: [(String, Int, Double, Double)] = [
            (#"{"columns":3,"horizontalSpacing":12,"verticalSpacing":10}"#, 3, 12, 10),
            (#"{"columns":3.9,"horizontalSpacing":12.5,"verticalSpacing":10.5}"#, 3, 12.5, 10.5),
            (#"{"columns":"3","horizontalSpacing":"12","verticalSpacing":"10"}"#, 3, 12, 10)
        ]
        for (json, columns, horizontal, vertical) in cases {
            let style = try JSONDecoder().decode(Style.self, from: Data("{\"gridSettings\":\(json)}".utf8))
            XCTAssertEqual(ProductsGridLayout(style: style, itemCount: 1).columns, columns)
            XCTAssertEqual(style.gridSettings?.horizontalSpacingValue, horizontal)
            XCTAssertEqual(style.gridSettings?.verticalSpacingValue, vertical)
        }
    }

    func testMissingAndInvalidSettingsUseDefaults() throws {
        for json in ["{}", "{\"gridSettings\":null}", "{\"gridSettings\":{}}", "{\"gridSettings\":{\"columns\":0,\"horizontalSpacing\":-1,\"verticalSpacing\":\"NaN\"}}", "{\"gridSettings\":{\"columns\":\"NaN\",\"horizontalSpacing\":\"inf\",\"verticalSpacing\":false}}"] {
            let style = try JSONDecoder().decode(Style.self, from: Data(json.utf8))
            let layout = ProductsGridLayout(style: style, itemCount: 1)
            XCTAssertEqual(layout.columns, 2)
            XCTAssertEqual(layout.horizontalSpacing, 8)
            XCTAssertEqual(layout.verticalSpacing, 8)
        }
    }

    func testLegacyColumnsFallbackAndSettingsPrecedence() throws {
        for (settings, expected) in [("", 3), (",\"gridSettings\":{}", 3), (",\"gridSettings\":{\"columns\":0}", 3), (",\"gridSettings\":{\"columns\":2.9}", 2)] {
            let style = try JSONDecoder().decode(Style.self, from: Data("{\"gridColumns\":3\(settings)}".utf8))
            XCTAssertEqual(ProductsGridLayout(style: style, itemCount: 1).columns, expected)
        }
        for value in [-1.0, 0, 0.9, .nan, .infinity] {
            XCTAssertEqual(ProductsGridLayout(style: Style(gridSettings: GridSettings(columns: value)), itemCount: 1).columns, 2)
        }
    }

    func testEveryInvalidColumnSettingUsesValidLegacyColumnsBeforeDefault() {
        for invalid in [0.0, -1, 13, 12.9, 1000000, .nan, .infinity] {
            let legacy = ProductsGridLayout(style: Style(gridColumns: 3, gridSettings: GridSettings(columns: invalid)), itemCount: 1)
            XCTAssertEqual(legacy.columns, 3)
            for fallback in [0, 13, Int.max] {
                let layout = ProductsGridLayout(style: Style(gridColumns: fallback, gridSettings: GridSettings(columns: invalid)), itemCount: 1)
                XCTAssertEqual(layout.columns, 2)
            }
        }
    }

    func testExcessiveColumnsFallBackToTwo() {
        for value in [25, 32, 100] {
            XCTAssertEqual(ProductsGridLayout(style: Style(gridSettings: GridSettings(columns: Double(value))), itemCount: 3).columns, 2)
            XCTAssertEqual(ProductsGridLayout(style: Style(gridColumns: value), itemCount: 3).columns, 2)
        }
        for value in [Double(Int.max), Double.greatestFiniteMagnitude] {
            XCTAssertEqual(ProductsGridLayout(style: Style(gridSettings: GridSettings(columns: value)), itemCount: 1).columns, 2)
        }
    }

    func testColumnsBetweenZeroAndOneAreInvalidRatherThanClamped() {
        XCTAssertEqual(ProductsGridLayout(style: Style(gridSettings: GridSettings(columns: 0.9)), itemCount: 1).columns, 2)
        XCTAssertEqual(ProductsGridLayout(style: Style(gridColumns: 3, gridSettings: GridSettings(columns: 0.9)), itemCount: 1).columns, 3)
    }

    func testUnknownContainerDoesNotBreakElementDecoding() throws {
        for field in ["", ",\"productContainerType\":null", ",\"productContainerType\":\"future\""] {
            let element = try JSONDecoder().decode(Element.self, from: Data("{\"type\":\"productsContainer\",\"style\":{\"gridColumns\":3\(field)}}".utf8))
            XCTAssertEqual(element.style.productContainerType ?? .row, .row)
            XCTAssertEqual(element.style.gridColumns, 3)
        }
    }

    func testGridIgnoresHeightAndPreservesIdealWidthAndPadding() {
        let style = Style(size: GravitySize(width: 164, height: 250), padding: GravityPadding(left: 10, right: 10, top: 4, bottom: 6), gridSettings: GridSettings(columns: 2, horizontalSpacing: 12, verticalSpacing: 12))
        let layout = ProductsGridLayout(style: style, itemCount: 5)
        XCTAssertEqual(layout.aspect, 1)
        XCTAssertEqual(layout.idealCellWidth, 164)
        XCTAssertEqual(layout.padding.top, 4)
        XCTAssertEqual(layout.padding.leading, 10)
        XCTAssertEqual(layout.padding.bottom, 6)
        XCTAssertEqual(layout.padding.trailing, 10)
        XCTAssertEqual(layout.indices(in: 2), 4..<5)
    }

    func testAllItemsAreLaidOutIncludingIncompleteRows() {
        for (count, rows) in [(0, 0), (1, 1), (5, 3), (9, 5)] {
            let layout = ProductsGridLayout(style: .empty, itemCount: count)
            XCTAssertEqual(layout.rows, rows)
            XCTAssertEqual((0..<rows).flatMap { Array(layout.indices(in: $0)) }, Array(0..<count))
        }
        let padded = Style(padding: GravityPadding(left: 10, right: 10, top: 10, bottom: 10))
        XCTAssertEqual(ProductsGridLayout(style: padded, itemCount: 0).rows, 0)
    }

    func testVisibilityDeduplicatesBySlotAcrossCellRecreation() {
        let impressions = ProductsGridImpressions()
        XCTAssertTrue(impressions.insert(slotId: "first"))
        XCTAssertFalse(impressions.insert(slotId: "first"))
        XCTAssertTrue(impressions.insert(slotId: "second"))
        XCTAssertFalse(impressions.insert(slotId: "first"))
        XCTAssertFalse(impressions.insert(slotId: nil))
        XCTAssertFalse(impressions.insert(slotId: nil))
        XCTAssertFalse(impressions.insert(slotId: nil))
        XCTAssertFalse(impressions.insert(slotId: nil))
    }
}

// Wire payloads copied from the admin panel, including height without width.
enum ProductsGridWireFixtures {
    static let elements = [
        ##"{"type":"products-container","style":{"backgroundColor":"#fffff000","productContainerType":"grid","size":{"height":250},"rowSpacing":8,"margin":{"left":16,"right":16,"top":16,"bottom":16}}}"##,
        ##"{"type":"products-container","style":{"backgroundColor":"#fffff000","productContainerType":"grid","size":{"height":250},"rowSpacing":8,"margin":{"left":16,"right":16,"top":16,"bottom":16},"gridSettings":{"columns":4,"horizontalSpacing":6,"verticalSpacing":6}}}"##,
        ##"{"type":"products-container","style":{"backgroundColor":"#fffff000","productContainerType":"grid","size":{"height":250},"rowSpacing":8,"margin":{"left":16,"right":16,"top":16,"bottom":16},"gridSettings":{"columns":4,"horizontalSpacing":6,"verticalSpacing":6},"padding":{"top":5,"right":5,"bottom":5,"left":5}}}"##,
        ##"{"type":"products-container","style":{"backgroundColor":"#fffff000","productContainerType":"grid","size":{"height":400},"rowSpacing":8,"margin":{"left":16,"right":16,"top":16,"bottom":16},"gridSettings":{"columns":4,"horizontalSpacing":6,"verticalSpacing":6},"padding":{"top":5,"right":5,"bottom":5,"left":5}}}"##
    ]
}
