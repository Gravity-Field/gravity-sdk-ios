import Combine
import GravitySDK

/// Demo `AssistantActionHandler`: instead of real navigation, publishes a message
/// for the assistant demo screen to show.
@MainActor
final class AssistantActionHandlerImpl: AssistantActionHandler {

    static let shared = AssistantActionHandlerImpl()

    /// Messages to show the user; dropped if no screen is subscribed.
    let messages = PassthroughSubject<String, Never>()

    private init() {}

    func canHandle(_ action: AssistantAction) -> Bool {
        switch action {
        case let .openProduct(product): return canOpenProduct(product)
        default: return false
        }
    }

    func handle(_ action: AssistantAction) {
        guard case let .openProduct(product) = action else { return }

        messages.send("Открыта карточка товара \(product.name)")
    }

    private func canOpenProduct(_ product: AssistantProduct) -> Bool {
        if let sku = product.sku, !sku.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }

        guard let url = product.url else { return false }
        return url.hasPrefix("http://") || url.hasPrefix("https://")
    }
}
