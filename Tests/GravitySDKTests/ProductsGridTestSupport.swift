import XCTest
import SwiftUI
@testable import GravitySDK

@MainActor
class ProductsGridTestCase: XCTestCase {
    func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    func settle<Content: View>(_ host: UIHostingController<Content>) {
        for _ in 0..<4 {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func waitForLayout(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) async {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        await fulfillment(of: [ready], timeout: timeout)
    }

    func makeSlots(count: Int) throws -> [Slot] {
        try (0..<count).map { index in
            try JSONDecoder().decode(Slot.self, from: Data("{\"item\":{},\"strId\":\(index),\"slotId\":\"\(index)\",\"fallback\":false}".utf8))
        }
    }

    func makeContent(slots: [Slot], style: Style, contentId: String = "grid-content", frameStyle: Style? = nil) -> CampaignContent {
        CampaignContent(contentId: contentId, deliveryMethod: .inline, contentType: "test", step: nil,
                        variables: Variables(frameUI: frameStyle.map { FrameUI(container: Container(style: $0)) }, elements: [Element(type: .productsContainer, style: style)]),
                        products: Products(strategyId: "test", fallback: false, name: nil, slots: slots, pageNumber: nil, countPages: nil))
    }
}

final class GridTestBuilder: ProductViewBuilder {
    var frames: [String: CGRect] = [:]
    var occurrenceFrames: [Int: CGRect] = [:]
    var contentIds = Set<String>()
    var selectors = Set<String>()
    var endFrame: CGRect = .zero
    var onFrame: (() -> Void)?

    func build(slot: Slot, content: CampaignContent, campaign: Campaign) -> AnyView {
        contentIds.insert(content.contentId)
        if let selector = campaign.selector { selectors.insert(selector) }
        return AnyView(Color.blue.background(GeometryReader { geometry in
            Color.clear.onAppear {
                self.frames[slot.slotId ?? "nil"] = geometry.frame(in: .global)
                self.occurrenceFrames[slot.strId] = geometry.frame(in: .global)
                self.onFrame?()
            }
            .onChange(of: geometry.frame(in: .global)) { frame in
                self.frames[slot.slotId ?? "nil"] = frame
                self.occurrenceFrames[slot.strId] = frame
                self.onFrame?()
            }
        }))
    }
}

struct GridTestHost: View {
    let content: CampaignContent
    let campaign: Campaign
    let builder: GridTestBuilder

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GravityElements(content: content, campaign: campaign, onClickCallback: { _ in })
                Color.clear.frame(height: 1).background(GeometryReader { geometry in
                    Color.clear.onAppear { builder.endFrame = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { builder.endFrame = $0 }
                })
            }
        }
    }
}

struct OversizedGridTestBuilder: ProductViewBuilder {
    var height: CGFloat = 400
    func build(slot: Slot, content: CampaignContent, campaign: Campaign) -> AnyView {
        AnyView((slot.strId == 0 ? Color.red : Color.blue).frame(width: 220, height: height))
    }
}

final class FlexibleLegacyGridTestBuilder: LegacyProductViewBuilder {
    var cards: [UIView] = []

    func createView(slot: Slot, content: CampaignContent, campaign: Campaign) -> UIView {
        let card = FlexibleGridTestCard()
        card.setContentHuggingPriority(.defaultLow, for: .horizontal)
        card.setContentHuggingPriority(.defaultLow, for: .vertical)
        card.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        card.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let width = card.widthAnchor.constraint(equalToConstant: 164)
        let height = card.heightAnchor.constraint(equalToConstant: 250)
        width.priority = .defaultLow
        height.priority = .defaultLow
        NSLayoutConstraint.activate([width, height])
        cards.append(card)
        return card
    }
}

final class FlexibleGridTestCard: UIView {
    override var intrinsicContentSize: CGSize { CGSize(width: 164, height: 250) }
}

final class ImageCardTestBuilder: LegacyProductViewBuilder {
    var cards: [ImageTestCard] = []

    func createView(slot: Slot, content: CampaignContent, campaign: Campaign) -> UIView {
        let card = ImageTestCard()
        cards.append(card)
        return card
    }
}

final class ImageTestCard: UIView {
    let imageView = UIImageView()
    let nameLabel = UILabel()
    let priceLabel = UILabel()

    override var intrinsicContentSize: CGSize { CGSize(width: 164, height: 250) }

    init() {
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.fittingSizeLevel, for: .horizontal)
        imageView.setContentHuggingPriority(.fittingSizeLevel, for: .vertical)
        imageView.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.fittingSizeLevel, for: .vertical)
        nameLabel.text = "Palm Tree Girls White Skirts"
        priceLabel.text = "324 ₽"
        let stack = UIStackView(arrangedSubviews: [imageView, nameLabel, priceLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
