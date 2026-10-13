import Foundation
import GravitySDK

/// App-wide `ReviewPromptIntegration` used for the *real* campaign flow (as opposed to the
/// synthetic fixtures in `ReviewPromptTestConsoleView`). Created once and wired into
/// `GravitySDK.initialize` from `GravitySDKDemoApp`, so the one `GravitySDK.instance` singleton
/// uses it for every automatic in-app triggered by `trackView`/`triggerEvent`.
///
/// Points at the test campaign `6acdfec314d8e893950c5402` (selector "ios-review"), configured in
/// the Gravity dashboard with trigger "Page load" on page type "Search page", once per page view.
///
/// `DemoReviewEligibilityAPI` is a real, working client eligibility check: it does one batch
/// lookup against `ReviewStatusStore` (the durable "already reviewed" record — exactly the
/// mechanism `InAppPreparationTests.testPreparationWaitsForTheClientsBatchCheckBeforeResolving`
/// proves the SDK waits on), not a stub that approves everything. Tapping "Оставить отзыв" opens
/// a real `ReviewFormView`; submitting persists the status so the SKU is excluded next time.
final class ReviewPromptCoordinator: ObservableObject {
    static let campaignId = "6acdfec314d8e893950c5402"
    static let selector = "ios-review"
    static let shared = ReviewPromptCoordinator()

    struct PreviewSlot: Identifiable {
        let id: String
        let slot: Slot
        let content: CampaignContent
        let campaign: Campaign
    }

    private let searchPageContext = PageContext(type: .search, data: [], location: "search")

    // `lazy`, not `let`: the closure below captures `self`, which Swift forbids until `self` is
    // fully initialized — a `lazy var` defers evaluation until first access, well after `init()`
    // returns, instead of requiring it as part of definite initialization.
    lazy var integration: ReviewPromptIntegration = ReviewPromptIntegration(
        api: DemoReviewEligibilityAPI(),
        selector: Self.selector,
        fallbackProductViewBuilder: DemoProductViewBuilder(),
        onOpenReview: { [weak self] sku in
            self?.appendLog("→ onOpenReview: открыта форма отзыва для SKU \(sku)")
            self?.presentReviewForm(for: sku)
        }
    )
    @Published private(set) var log: [String] = []
    @Published private(set) var preview: [PreviewSlot] = []
    /// Drives `ReviewFormView`'s presentation from `ContentView`; non-nil while the sheet is up.
    @Published var reviewFormSKU: String?

    private init() {}

    /// Called by `ReviewFormView` on submit. Persists the status so `DemoReviewEligibilityAPI`
    /// excludes this SKU on the next batch check, and updates the in-session optimistic status
    /// too (`ReviewPromptIntegration.didSubmitReview`) in case the client's own API has caching lag.
    func didSubmitReview(sku: String, rating: Int, comment: String) {
        ReviewStatusStore.shared.markReviewed(sku)
        integration.didSubmitReview(sku: sku)
        appendLog("Отзыв отправлен: SKU \(sku), \(rating)★, \"\(comment)\" — статус сохранён")
    }

    /// Demo-only affordance so the real flow can be re-tested without reinstalling the app.
    func logReviewStatusReset() {
        appendLog("ReviewStatusStore сброшен — все SKU снова доступны для отзыва")
    }

    /// `fetchAndPreviewBySelector()` below never has a live SDK-presented in-app to close —
    /// `getContentBySelector` doesn't show anything, so there's nothing registered for
    /// `dismissInApp` to find, and it correctly returns `false`. The real card
    /// (`ReviewPromptIntegration`'s `ProductViewBuilder`) only opens the review screen when that
    /// dismissal succeeds, which is right for the real campaign but means it can never open from
    /// this preview. This sends the same real click tracking and opens the review screen directly,
    /// since there is genuinely nothing to dismiss here.
    func reviewFromPreview(slot: Slot, content: CampaignContent, campaign: Campaign) {
        let sku = slot.item["sku"] as? String ?? ""
        GravitySDK.instance.sendProductEngagement(
            engagement: ProductClickEngagement(slot: slot, content: content, campaign: campaign)
        )
        appendLog("Клик по превью SKU \(sku) — dismissInApp не вызывается (нет live in-app в этом режиме)")
        presentReviewForm(for: sku)
    }

    /// Matches the campaign's configured trigger (Page load / Search page): runs the full
    /// automatic pipeline. The SDK shows the *first* matching campaign on this trigger sorted by
    /// priority (`handleCampaignIdsResponse`) — if another campaign also fires on "Search page",
    /// it competes for the slot and may win, which is why this can show a different campaign than
    /// "ios-review". Use `fetchAndPreviewBySelector()` below to target this campaign specifically.
    func triggerRealCampaign() {
        appendLog("trackView(.search) отправлен — конкурирует с другими кампаниями на этом триггере")
        GravitySDK.instance.trackView(pageContext: searchPageContext)
    }

    /// Fetches the campaign directly by selector — no competition with other campaigns on the
    /// same trigger, deterministic. `getContentBySelector` itself never displays anything (no
    /// `inAppPreparation`, no UI — see README "Получение контента"), so this runs the content
    /// through the same `recommendedContent` filtering the automatic pipeline would apply, then
    /// renders whatever survives with the real `productViewBuilder` (see the preview below).
    func fetchAndPreviewBySelector() async {
        appendLog("getContentBySelector(\"\(Self.selector)\") …")
        guard let response = await GravitySDK.instance.getContentBySelector(
            selector: Self.selector,
            pageContext: searchPageContext
        ) else {
            appendLog("getContentBySelector → nil (нет кампании с этим selector, либо запрос не удался)")
            setPreview([])
            return
        }
        guard let campaign = response.data.first,
              let content = campaign.payload.first?.contents.first
        else {
            appendLog("getContentBySelector → кампания найдена, но без контента")
            setPreview([])
            return
        }

        let rawSkus = content.products?.slots?.compactMap { $0.item["sku"] as? String } ?? []
        appendLog("contentId=\(content.contentId), товаров до фильтрации: \(rawSkus.count) \(rawSkus)")

        do {
            let filtered = try await integration.recommendedContent(for: content, campaign: campaign)
            let slots = filtered?.products?.slots ?? []
            appendLog("после recommendedContent: \(slots.count) товар(ов)")
            setPreview(slots.enumerated().map { index, slot in
                PreviewSlot(id: slot.slotId ?? "slot-\(index)", slot: slot,
                            content: filtered ?? content, campaign: campaign)
            })
        } catch {
            appendLog("recommendedContent error: \(error)")
            setPreview([])
        }
    }

    // `await`-ed calls above don't guarantee resumption on the main thread, so these two hop
    // explicitly rather than relying on every caller to — same pattern as GravitySDK.swift's
    // own `callbackTrackingEvent`.
    private func appendLog(_ line: String) {
        if Thread.isMainThread {
            log.append(line)
        } else {
            DispatchQueue.main.async { self.log.append(line) }
        }
    }

    private func setPreview(_ slots: [PreviewSlot]) {
        if Thread.isMainThread {
            preview = slots
        } else {
            DispatchQueue.main.async { self.preview = slots }
        }
    }

    private func presentReviewForm(for sku: String) {
        if Thread.isMainThread {
            reviewFormSKU = sku
        } else {
            DispatchQueue.main.async { self.reviewFormSKU = sku }
        }
    }
}

/// The client's own eligibility check. Recently-purchased filtering already happened on the
/// Gravity side (the campaign's products strategy), so the only thing left for the client to
/// decide is "not already reviewed" — one batch lookup against the durable `ReviewStatusStore`,
/// with a short delay standing in for a real network round-trip.
private struct DemoReviewEligibilityAPI: ReviewEligibilityAPI {
    func eligibleSkus(_ skus: [String]) async throws -> Set<String> {
        try await Task.sleep(nanoseconds: 400_000_000)
        let reviewed = ReviewStatusStore.shared.reviewedSkus()
        return Set(skus).subtracting(reviewed)
    }
}
