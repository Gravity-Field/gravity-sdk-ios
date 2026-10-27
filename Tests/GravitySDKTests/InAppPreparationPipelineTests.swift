import XCTest
@testable import GravitySDK

/// Tests `GravitySDK.resolvedContent`, the pure function `prepareAndShowBackendContent` delegates
/// to for the "wait for the client's preparation, or pass through unchanged" decision — covering
/// the acceptance criterion that campaigns without a handler keep their existing behavior.
final class InAppPreparationPipelineTests: XCTestCase {
    private func content(skus: [String]) throws -> CampaignContent {
        let slotsJSON = skus.enumerated().map { index, sku in
            """
            {"item":{"sku":"\(sku)"},"fallback":false,"strId":1,"slotId":"slot-\(index)"}
            """
        }.joined(separator: ",")
        let json = """
        {"contentId":"content","deliveryMethod":"bottom_sheet","contentType":"products",
         "products":{"strategyId":"strategy","fallback":false,"name":"recently purchased",
           "pageNumber":1,"countPages":1,"slots":[\(slotsJSON)]}}
        """
        return try JSONDecoder().decode(CampaignContent.self, from: Data(json.utf8))
    }

    func testNoHandlerPassesContentThroughUnchanged() async throws {
        let original = try content(skus: ["A", "B", "C"])
        let result = await GravitySDK.resolvedContent(original, Campaign(selector: "any"), preparation: nil)
        XCTAssertEqual(result?.contentId, original.contentId)
        XCTAssertEqual(result?.products?.slots?.count, 3)
    }

    func testHandlerPresentDelegatesToItsPrepare() async throws {
        let original = try content(skus: ["A", "B", "C"])
        let preparation = InAppPreparation { content, _ in
            content.filteringProducts { $0.item["sku"] as? String != "B" }
        }
        let result = await GravitySDK.resolvedContent(original, Campaign(), preparation: preparation)
        XCTAssertEqual(result?.products?.slots?.compactMap { $0.item["sku"] as? String }, ["A", "C"])
    }

    func testHandlerSkipDecisionPropagates() async throws {
        let original = try content(skus: ["A"])
        let preparation = InAppPreparation { _, _ in nil }
        let result = await GravitySDK.resolvedContent(original, Campaign(), preparation: preparation)
        XCTAssertNil(result)
    }
}
