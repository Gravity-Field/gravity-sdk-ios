import Foundation
import SwiftUI

public enum AssistantPrepareResult: Equatable {
    case ready
    case unavailable(AssistantUnavailableReason)
    case failure(AssistantError)
    case cancelled
    case superseded
}

public enum AssistantUnavailableReason: Equatable {
    case noMatchingConfiguration
    case disabled
}

public enum AssistantErrorCode: Equatable {
    case invalidConfiguration
    case unauthorized
    case network
    case timeout
    case rateLimited
    case server
    case invalidResponse
}

public struct AssistantError: Equatable {
    public let code: AssistantErrorCode
    public let message: String?
    public let httpStatus: Int?

    public init(code: AssistantErrorCode, message: String? = nil, httpStatus: Int? = nil) {
        self.code = code
        self.message = message
        self.httpStatus = httpStatus
    }
}

public enum AssistantOpenResult: Equatable {
    case opened
    case alreadyOpen
    case notReady
    case invalidPresenter
}

public enum AssistantProductAction: Equatable {
    case visibleImpression

    /// Tap on the whole product card, which opens the product.
    case tap
}

public enum AssistantInteractionResult: Equatable {
    case accepted
    case duplicate
    case staleReference
    case notActionable
}

/// Opaque reference to a product occurrence in an answer.
/// Becomes invalid after a new chat or an identity change.
public struct AssistantProductRef: Equatable {
    /// Conversation generation the reference was issued in; unrelated to the `setUser` session.
    internal let epoch: Int64
    internal let itemId: String

    internal init(epoch: Int64, itemId: String) {
        self.epoch = epoch
        self.itemId = itemId
    }
}

public struct AssistantProduct: Equatable, Identifiable {
    public let itemId: String
    public let ref: AssistantProductRef
    public let name: String
    public let sku: String?
    public let url: String?
    public let imageUrl: String?
    public let price: Double?
    public let brand: String?
    public let features: String?
    public let categoryId: String?
    public let isStm: Bool?
    public let canOpen: Bool

    public var id: String { itemId }

    internal init(
        itemId: String,
        ref: AssistantProductRef,
        name: String,
        sku: String? = nil,
        url: String? = nil,
        imageUrl: String? = nil,
        price: Double? = nil,
        brand: String? = nil,
        features: String? = nil,
        categoryId: String? = nil,
        isStm: Bool? = nil,
        canOpen: Bool = false
    ) {
        self.itemId = itemId
        self.ref = ref
        self.name = name
        self.sku = sku
        self.url = url
        self.imageUrl = imageUrl
        self.price = price
        self.brand = brand
        self.features = features
        self.categoryId = categoryId
        self.isStm = isStm
        self.canOpen = canOpen
    }

    internal func withCanOpen(_ canOpen: Bool) -> AssistantProduct {
        AssistantProduct(
            itemId: itemId,
            ref: ref,
            name: name,
            sku: sku,
            url: url,
            imageUrl: imageUrl,
            price: price,
            brand: brand,
            features: features,
            categoryId: categoryId,
            isStm: isStm,
            canOpen: canOpen
        )
    }
}

public struct AssistantProductBlock: Equatable, Identifiable {
    public let blockId: String
    public let title: String?
    public let products: [AssistantProduct]

    public var id: String { blockId }

    internal init(blockId: String, title: String? = nil, products: [AssistantProduct] = []) {
        self.blockId = blockId
        self.title = title
        self.products = products
    }
}

public struct AssistantProductLayout: Equatable {
    /// Width available to the block in the chat. The height is chosen by the app.
    public let availableWidth: CGFloat

    internal init(availableWidth: CGFloat) {
        self.availableWidth = availableWidth
    }
}

/// Renders a product block in the chat with the app's own views.
@MainActor
public protocol AssistantProductBlockBuilder {
    @ViewBuilder
    func build(block: AssistantProductBlock, layout: AssistantProductLayout) -> AnyView
}

public enum AssistantAction {
    case openProduct(AssistantProduct)
    case openSupportChat(payload: [String: JSONValue])
    case followUrl(URL)
    case custom(type: String, payload: [String: JSONValue])
}

/// Performs assistant actions in the app. The chat is closed before `handle` is called.
@MainActor
public protocol AssistantActionHandler {
    func canHandle(_ action: AssistantAction) -> Bool
    func handle(_ action: AssistantAction)
}
