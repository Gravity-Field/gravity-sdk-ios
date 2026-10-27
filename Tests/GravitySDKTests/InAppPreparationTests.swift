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

    func testInvalidTimeoutsSkipWithoutRunningTheHandler() async throws {
        let original = try content()
        for invalid: TimeInterval in [0, -1, .infinity, .nan, 3_601] {
            var handlerCalled = false
            let result = await InAppPreparation(timeout: invalid) { content, _ in
                handlerCalled = true
                return content
            }.prepare(original, Campaign())
            XCTAssertNil(result, "timeout \(invalid) should skip the in-app")
            XCTAssertFalse(handlerCalled, "an invalid timeout must not even invoke the handler")
        }
    }

    func testBoundaryTimeoutOfExactlyOneHourIsAllowed() async throws {
        let original = try content()
        let result = await InAppPreparation(timeout: 3_600) { content, _ in content }
            .prepare(original, Campaign())
        XCTAssertNotNil(result)
    }

    func testPreparationsOwnTimeoutSkipsASlowHandler() async throws {
        let original = try content()
        let result = await InAppPreparation(timeout: 0.03) { content, _ in
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return content
        }.prepare(original, Campaign())
        XCTAssertNil(result)
    }

    /// Mirrors `GravitySDK.prepareAndShowBackendContent`: the UI-thread revision is captured
    /// before awaiting preparation and re-checked after it completes. A user switching accounts
    /// mid-wait must block presentation even though the preparation itself succeeds.
    func testUserChangeDuringPreparationStillBlocksPresentationAfterItCompletes() async throws {
        let original = try content()
        let revision = PresentationRevision()
        let expectedRevision = revision.current

        async let prepared = InAppPreparation(timeout: 1) { content, _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            return content
        }.prepare(original, Campaign())

        try await Task.sleep(nanoseconds: 10_000_000)
        revision.invalidate() // simulates setUser() arriving while the client API call is in flight

        let result = await prepared
        XCTAssertNotNil(result, "the preparation itself still finishes and returns content")
        XCTAssertFalse(
            revision.canPresent(expected: expectedRevision, active: true, locked: false, cancelled: false),
            "but the gate must reject it since the user changed mid-flight"
        )
    }

    /// Same shape as above, for the screen (rather than the user) going away mid-wait: the
    /// `active` flag passed to `canPresent` tracks `isViewControllerActive`.
    func testLeavingTheScreenDuringPreparationStillBlocksPresentationAfterItCompletes() async throws {
        let original = try content()
        let revision = PresentationRevision()
        let expectedRevision = revision.current
        var viewControllerActive = true

        async let prepared = InAppPreparation(timeout: 1) { content, _ in
            try await Task.sleep(nanoseconds: 50_000_000)
            return content
        }.prepare(original, Campaign())

        try await Task.sleep(nanoseconds: 10_000_000)
        viewControllerActive = false // simulates the user navigating away while waiting

        let result = await prepared
        XCTAssertNotNil(result)
        XCTAssertFalse(
            revision.canPresent(expected: expectedRevision, active: viewControllerActive, locked: false, cancelled: false)
        )
    }

    /// From the integrating client's point of view: their own backend does one batch eligibility
    /// check for every SKU in the content, and the SDK must not resolve `prepare()` — i.e. must
    /// not show anything — until that check actually completes. Uses a manually-resumed
    /// continuation (not a sleep) so "waits" is proven, not assumed: nothing about `prepare()`
    /// can produce a value before the test explicitly resumes the client's check.
    func testPreparationWaitsForTheClientsBatchCheckBeforeResolving() async throws {
        let original = try content()
        var batchRequestedSkus: [String]?
        var resumeClientsBatchCheck: ((Set<String>) -> Void)?

        let preparation = InAppPreparation(timeout: 5) { content, _ in
            let skus = content.products?.slots?.compactMap { $0.item["sku"] as? String } ?? []
            batchRequestedSkus = skus // the client checks eligibility once, for the whole batch
            let eligible: Set<String> = await withCheckedContinuation { continuation in
                resumeClientsBatchCheck = { continuation.resume(returning: $0) }
            }
            return content.filteringProducts { eligible.contains($0.item["sku"] as? String ?? "") }
        }

        let start = Date()
        let task = Task { await preparation.prepare(original, Campaign()) }

        // Give the handler a chance to run up to its suspension point.
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(batchRequestedSkus, ["A", "B", "C"], "all SKUs are checked in one batch call")
        XCTAssertNotNil(resumeClientsBatchCheck, "prepare() must still be suspended on the client's check")

        try await Task.sleep(nanoseconds: 30_000_000) // the client's own API call is still "in flight"
        resumeClientsBatchCheck?(["A"]) // only "A" turns out to be eligible for a review

        let result = await task.value
        XCTAssertGreaterThanOrEqual(
            Date().timeIntervalSince(start), 0.045,
            "prepare() must not resolve before the client's batch check actually completes"
        )

        // Whatever survives keeps its original order and tracking — nothing is rebuilt.
        let survivors = try XCTUnwrap(result)
        XCTAssertEqual(survivors.products?.slots?.compactMap { $0.item["sku"] as? String }, ["A"])
        XCTAssertEqual(survivors.products?.slots?.first?.slotId, "first")
        XCTAssertEqual(survivors.products?.slots?.first?.events?.first?.urls, ["https://example.test/A"])
    }
}
