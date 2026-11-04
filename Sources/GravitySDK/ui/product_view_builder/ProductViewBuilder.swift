import SwiftUI
import UIKit


public protocol ProductViewBuilder {
    @ViewBuilder
    func build(
        slot: Slot,
        content: CampaignContent,
        campaign: Campaign
    ) -> AnyView
}

public protocol LegacyProductViewBuilder: ProductViewBuilder {
    func createView(
        slot: Slot,
        content: CampaignContent,
        campaign: Campaign
    ) -> UIView
}

extension LegacyProductViewBuilder {
    public func build(
        slot: Slot,
        content: CampaignContent,
        campaign: Campaign
    ) -> AnyView {
        AnyView(
            LegacyProductUIViewHost(
                slot: slot,
                content: content,
                campaign: campaign,
                factory: createView
            )
        )
    }
}

struct LegacyProductUIViewHost: UIViewRepresentable {
    let slot: Slot
    let content: CampaignContent
    let campaign: Campaign
    let factory: (Slot, CampaignContent, Campaign) -> UIView
    @Environment(\.gravityProductIsInGrid) private var isInGrid

    func makeUIView(context: Context) -> UIView {
        let view = factory(slot, content, campaign)
        if #available(iOS 16.0, *) {
            return view
        }
        return isInGrid ? GridProductUIView(content: view) : view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        guard isInGrid, let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }
}

private struct GravityProductGridKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var gravityProductIsInGrid: Bool {
        get { self[GravityProductGridKey.self] }
        set { self[GravityProductGridKey.self] = newValue }
    }
}

private final class GridProductUIView: UIView {
    private let content: UIView

    init(content: UIView) {
        self.content = content
        super.init(frame: .zero)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        content.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.setContentHuggingPriority(.defaultLow, for: .vertical)
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize { content.intrinsicContentSize }

}
