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
            try await recommendedContent(for: content, campaign: campaign)
        }
    }

    /// The decision logic behind `preparation()`, exposed directly so it can be exercised
    /// without going through the SDK's network/presentation pipeline (see the demo's test console).
    func recommendedContent(for content: CampaignContent, campaign: Campaign) async throws -> CampaignContent? {
        guard campaign.selector == selector else { return content }
        let skus = content.products?.slots?.compactMap { $0.item["sku"] as? String } ?? []
        guard !skus.isEmpty else { return nil }
        let eligible = try await api.eligibleSkus(Array(Set(skus)))
        return content.filteringProducts { slot in
            guard let sku = slot.item["sku"] as? String else { return false }
            return eligible.contains(sku) && !status.contains(sku)
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

    /// `status` is an optimistic cache layered on top of `api` (the client's own backend) — a
    /// real app wouldn't normally need to clear it directly, since it just mirrors the backend's
    /// state until the next successful `eligibleSkus` call. This exists for demo/testing: if the
    /// backend-side status is reset out of band (e.g. `ReviewStatusStore.reset()`), this cache
    /// would otherwise keep excluding the SKU until the next `didSubmitReview`-free app launch.
    func clearSubmittedReviews() {
        status.removeAll()
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
    func removeAll() {
        lock.lock()
        skus.removeAll()
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
        let name = slot.item["name"] as? String ?? sku
        let price = slot.item["price"] as? String
        let imageURL = (slot.item["image_url"] as? String).flatMap(URL.init(string:))

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6))
                    if let imageURL {
                        AsyncImage(url: imageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fit).padding(6)
                        } placeholder: {
                            ProgressView()
                        }
                    }
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(name)
                    .font(.caption)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .top)

                if let price {
                    Text("\(price) ₽").font(.caption.bold())
                }

                Button {
                    GravitySDK.instance.sendProductEngagement(
                        engagement: ProductClickEngagement(slot: slot, content: content, campaign: campaign)
                    )
                    GravitySDK.instance.dismissInApp(contentId: content.contentId) { dismissed in
                        if dismissed { onOpenReview(sku) }
                    }
                } label: {
                    Text("Оставить отзыв")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(10)
            .frame(width: 150)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        )
    }
}
