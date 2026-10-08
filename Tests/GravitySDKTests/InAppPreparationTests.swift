import XCTest
@testable import GravitySDK

final class InAppPreparationTests: XCTestCase {
    private func content() throws -> CampaignContent {
        let json = """
        {"contentId":"content","deliveryMethod":"bottom_sheet","contentType":"products",
         "products":{"strategyId":"strategy","fallback":false,"name":"recently purchased",
           "pageNumber":1,"countPages":2,"slots":[
             {"item":{"sku":"A"},"fallback":false,"strId":5,"slotId":"first",
              "events":[{"type":"click","urls":["https://example.test/A"]}]},
             {"item":{"sku":"B"},"fallback":false,"strId":5,"slotId":"second"},
             {"item":{"sku":"C"},"fallback":false,"strId":5,"slotId":"third"}]},
         "events":[{"type":"impression","urls":["https://example.test/content"]}]}
        """
        return try JSONDecoder().decode(CampaignContent.self, from: Data(json.utf8))
    }

    func testFilteringPreservesOrderTrackingAndMetadata() throws {
        let original = try content()
        let filtered = try XCTUnwrap(original.filteringProducts { $0.item["sku"] as? String != "B" })
        XCTAssertEqual(filtered.products?.slots?.compactMap { $0.item["sku"] as? String }, ["A", "C"])
        XCTAssertEqual(filtered.products?.slots?.first?.slotId, "first")
        XCTAssertEqual(filtered.products?.slots?.first?.events?.first?.urls, ["https://example.test/A"])
        XCTAssertEqual(filtered.events?.first?.urls, original.events?.first?.urls)
        XCTAssertEqual(filtered.products?.strategyId, original.products?.strategyId)
        XCTAssertEqual(filtered.products?.countPages, original.products?.countPages)
        XCTAssertEqual(original.products?.slots?.count, 3)
    }

    func testEmptyProductsSkipContent() throws {
        XCTAssertNil(try content().filteringProducts { _ in false })
        let empty = CampaignContent(contentId: "empty", deliveryMethod: .bottomSheet,
                                    contentType: "products", step: nil)
        XCTAssertNil(empty.filteringProducts { _ in true })
    }

    func testPreparationCanFilterOrPassThrough() async throws {
        let original = try content()
        let campaign = Campaign(selector: "reviews")
        let preparation = InAppPreparation { content, campaign in
            guard campaign.selector == "reviews" else { return content }
            return content.filteringProducts { $0.item["sku"] as? String == "B" }
        }
        let filtered = await preparation.prepare(original, campaign)
        XCTAssertEqual(filtered?.products?.slots?.first?.slotId, "second")
        let unchanged = await preparation.prepare(original, Campaign(selector: "other"))
        XCTAssertEqual(unchanged?.products?.slots?.count, 3)
    }

    func testSkipAndErrorReturnNil() async throws {
        let original = try content()
        let skipped = await InAppPreparation { _, _ in nil }.prepare(original, Campaign())
        XCTAssertNil(skipped)
        struct Failure: Error {}
        let failed = await InAppPreparation { _, _ in throw Failure() }.prepare(original, Campaign())
        XCTAssertNil(failed)
    }
}
