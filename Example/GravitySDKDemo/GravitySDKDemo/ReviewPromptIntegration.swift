import Foundation
import GravitySDK
import SwiftUI

/// Implement with your authenticated API. Include delivery/return rules in eligibility if needed.
protocol ReviewEligibilityAPI {
    func eligibleSkus(_ skus: [String]) async throws -> Set<String>
}

/// Keep one instance for the signed-in user; create a new instance when the account changes.
final class ReviewPromptIntegration {
    private let api: ReviewEligibilityAPI
    private let status = SubmittedReviews()
    private let onOpenReview: (String) -> Void
    private let selector: String
    private let fallbackProductViewBuilder: ProductViewBuilder

    init(api: ReviewEligibilityAPI, selector: String, fallbackProductViewBuilder: ProductViewBuilder,
         onOpenReview: @escaping (String) -> Void) {
        self.api = api
        self.selector = selector
        self.fallbackProductViewBuilder = fallbackProductViewBuilder
        self.onOpenReview = onOpenReview
    }

    func preparation() -> InAppPreparation {
        InAppPreparation(timeout: 5) { [self] content, campaign in
            guard campaign.selector == selector else { return content }
            let skus = content.products?.slots?.compactMap { $0.item["sku"] as? String } ?? []
            guard !skus.isEmpty else { return nil }
            let eligible = try await api.eligibleSkus(Array(Set(skus)))
            return content.filteringProducts { slot in
                guard let sku = slot.item["sku"] as? String else { return false }
                return eligible.contains(sku) && !status.contains(sku)
            }
        }
    }

    var productViewBuilder: ProductViewBuilder {
        ReviewProductViewBuilder(selector: selector, fallback: fallbackProductViewBuilder,
                                 onOpenReview: onOpenReview)
    }

    /// Call only after a successful submission, not when the review screen opens.
    func didSubmitReview(sku: String) {
        status.insert(sku)
    }
}

private final class SubmittedReviews {
    private let lock = NSLock()
    private var skus: Set<String> = []
    func contains(_ sku: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return skus.contains(sku)
    }
    func insert(_ sku: String) {
        lock.lock()
        skus.insert(sku)
        lock.unlock()
    }
}

private struct ReviewProductViewBuilder: ProductViewBuilder {
    let selector: String
    let fallback: ProductViewBuilder
    let onOpenReview: (String) -> Void

    func build(slot: Slot, content: CampaignContent, campaign: Campaign) -> AnyView {
        guard campaign.selector == selector else {
            return fallback.build(slot: slot, content: content, campaign: campaign)
        }
        let sku = slot.item["sku"] as? String ?? ""
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text(slot.item["name"] as? String ?? sku)
                Button("Оставить отзыв") {
                    GravitySDK.instance.sendProductEngagement(
                        engagement: ProductClickEngagement(slot: slot, content: content, campaign: campaign)
                    )
                    GravitySDK.instance.dismissInApp(contentId: content.contentId) { dismissed in
                        if dismissed { onOpenReview(sku) }
                    }
                }
            }
            .frame(width: 160)
        )
    }
}
