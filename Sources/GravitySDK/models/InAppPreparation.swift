import Foundation

/// Return the content to present, or nil to skip this in-app and try the next campaign.
/// Runs after productFilter and content-loaded tracking, before any impression events.
public typealias InAppPreparationHandler = (CampaignContent, Campaign) async throws -> CampaignContent?

public struct InAppPreparation {
    public let timeout: TimeInterval
    private let handler: InAppPreparationHandler

    /// The handler should perform cancellable asynchronous work, never block a thread.
    public init(timeout: TimeInterval = 5, handler: @escaping InAppPreparationHandler) {
        self.timeout = timeout
        self.handler = handler
    }

    internal func prepare(_ content: CampaignContent, _ campaign: Campaign) async -> CampaignContent? {
        guard timeout.isFinite, timeout > 0, timeout <= 3_600 else { return nil }
        return await PreparationDeadline.run(timeout: timeout) {
            try await handler(content, campaign)
        } ?? nil
    }
}

extension CampaignContent {
    /// Keeps the original slots, order, events and content metadata. An empty result skips the in-app.
    public func filteringProducts(_ predicate: (Slot) -> Bool) -> CampaignContent? {
        guard let products = products else { return nil }
        let slots = (products.slots ?? []).filter(predicate)
        guard !slots.isEmpty else { return nil }
        return CampaignContent(
            contentId: contentId,
            templateSystemName: templateSystemName,
            deliveryMethod: deliveryMethod,
            contentType: contentType,
            step: step,
            variables: variables,
            products: Products(
                strategyId: products.strategyId,
                fallback: products.fallback,
                name: products.name,
                slots: slots,
                pageNumber: products.pageNumber,
                countPages: products.countPages
            ),
            items: items,
            custom: custom,
            events: events
        )
    }
}
