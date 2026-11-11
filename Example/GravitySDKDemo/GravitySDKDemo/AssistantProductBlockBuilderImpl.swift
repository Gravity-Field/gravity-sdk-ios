import GravitySDK
import SwiftUI

private let logTag = "AssistantBlock"

private let cardWidth: CGFloat = 164
private let imageHeight: CGFloat = 158
private let imageCornerRadius: CGFloat = 16

/// Corner radius of the tap highlight; larger values clip the text corners.
private let highlightCornerRadius: CGFloat = 8
private let placeholderColor = Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF7 / 255)
private let titleColor = Color(red: 0x10 / 255, green: 0x18 / 255, blue: 0x28 / 255)
private let brandColor = Color(red: 0x66 / 255, green: 0x70 / 255, blue: 0x85 / 255)
private let priceColor = Color(red: 0x10 / 255, green: 0x18 / 255, blue: 0x28 / 255)

/// A product impression counts once this fraction of the card stays on screen for `visibleDwellSeconds`.
private let visibleAreaFraction: CGFloat = 0.5
private let visibleDwellSeconds: Double = 1

/// Demo product carousel: renders the block title and product cards within the width provided by the SDK.
final class AssistantProductBlockBuilderImpl: AssistantProductBlockBuilder {

    @ViewBuilder
    func build(block: AssistantProductBlock, layout: AssistantProductLayout) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                if let title = block.title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(titleColor)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if block.products.isEmpty {
                    Text("Подборка пуста")
                        .font(.system(size: 14))
                        .foregroundColor(brandColor)
                        .padding(.horizontal, 16)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(block.products) { product in
                                TrackVisible(product: product) {
                                    ProductCard(product: product)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .frame(width: layout.availableWidth, alignment: .leading)
        )
    }
}

/// Reports a visible impression to the SDK each time the card becomes visible;
/// the SDK deduplicates repeated impressions.
private struct TrackVisible<Content: View>: View {
    let product: AssistantProduct
    @ViewBuilder let content: () -> Content

    @State private var isVisible = false
    @State private var dwell: Task<Void, Never>?

    var body: some View {
        content()
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: VisibleFractionKey.self,
                        value: visibleFraction(of: geometry)
                    )
                }
            )
            .onPreferenceChange(VisibleFractionKey.self) { fraction in
                update(isVisible: fraction >= visibleAreaFraction)
            }
            .onDisappear {
                dwell?.cancel()
                dwell = nil
                isVisible = false
            }
    }

    private func update(isVisible visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible

        dwell?.cancel()
        dwell = nil
        guard visible else { return }

        print("\(logTag): Half of \(product.itemId) is on screen")
        dwell = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(visibleDwellSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            perform(product, .visibleImpression)
        }
    }

    private func visibleFraction(of geometry: GeometryProxy) -> CGFloat {
        let frame = geometry.frame(in: .global)
        let cardArea = frame.width * frame.height
        guard cardArea > 0 else { return 0 }

        let visible = frame.intersection(UIScreen.main.bounds)
        guard !visible.isNull else { return 0 }

        return (visible.width * visible.height) / cardArea
    }
}

private struct VisibleFractionKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProductCard: View {
    let product: AssistantProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                placeholderColor

                if let imageUrl = product.imageUrl, let url = URL(string: imageUrl) {
                    SwiftUI.AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                } else {
                    Text("Нет фото")
                        .font(.system(size: 12))
                        .foregroundColor(brandColor)
                }
            }
            .frame(width: cardWidth, height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))

            Text(product.name)
                .font(.system(size: 14))
                .foregroundColor(titleColor)
                .lineLimit(2)
                .padding(.top, 8)

            if let brand = product.brand, !brand.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(brand)
                    .font(.system(size: 12))
                    .foregroundColor(brandColor)
                    .lineLimit(1)
                    .padding(.top, 4)
            }

            if let price = product.price {
                Text(formatPrice(price))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(priceColor)
                    .padding(.top, 8)
            }
        }
        .frame(width: cardWidth, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: highlightCornerRadius, style: .continuous))
        .onTapGesture {
            guard product.canOpen else { return }
            perform(product, .tap)
        }
    }
}

/// Reports a product action to the SDK; any resulting navigation is delivered to `AssistantActionHandler`.
@MainActor
private func perform(_ product: AssistantProduct, _ action: AssistantProductAction) {
    let result = GravitySDK.instance.performAssistantProductAction(
        product: product.ref,
        action: action
    )
    print("\(logTag): \(action) on \(product.itemId) = \(result)")
}

private func formatPrice(_ price: Double) -> String {
    let format = NumberFormatter()
    format.numberStyle = .decimal
    format.maximumFractionDigits = 0
    format.locale = Locale(identifier: "ru_RU")
    let value = format.string(from: NSNumber(value: price)) ?? "\(Int(price))"
    return "\(value) ₽"
}
