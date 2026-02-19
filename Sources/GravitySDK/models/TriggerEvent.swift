import Foundation

public class TriggerEvent: Encodable {
    public let type: String
    public let name: String
    
    enum CodingKeys: String, CodingKey {
        case type, name
    }
    
    internal init(type: String, name: String) {
        self.type = type
        self.name = name
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
    }
}

public class AddToCartEvent: TriggerEvent {
    public let value: Double
    public let productId: String
    public let quantity: Int
    public let currency: String?
    public let cart: [CartItem]?
    
    enum CodingKeys: String, CodingKey {
        case value, productId, quantity, currency, cart
    }
    
    public init(value: Double, productId: String, quantity: Int, currency: String? = nil, cart: [CartItem]? = nil) {
        self.value = value
        self.productId = productId
        self.quantity = quantity
        self.currency = currency
        self.cart = cart
        super.init(type: "add-to-cart-v1", name: "Add to Cart")
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(productId, forKey: .productId)
        try container.encode(quantity, forKey: .quantity)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(cart, forKey: .cart)
    }
}

public class PurchaseEvent: TriggerEvent {
    public let uniqueTransactionId: String
    public let value: Double
    public let cart: [  CartItem]
    public let currency: String?
    
    enum CodingKeys: String, CodingKey {
        case uniqueTransactionId, value, cart, currency
    }
    
    public init(uniqueTransactionId: String, value: Double, cart: [CartItem], currency: String? = nil) {
        self.uniqueTransactionId = uniqueTransactionId
        self.value = value
        self.cart = cart
        self.currency = currency
        super.init(type: "purchase-v1", name: "Purchase")
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uniqueTransactionId, forKey: .uniqueTransactionId)
        try container.encode(value, forKey: .value)
        try container.encode(cart, forKey: .cart)
        try container.encodeIfPresent(currency, forKey: .currency)
    }
}

public class RemoveFromCartEvent: TriggerEvent {
    public let value: Double
    public let productId: String
    public let quantity: Int
    public let currency: String?
    public let cart: [CartItem]?
    
    enum CodingKeys: String, CodingKey {
        case value, productId, quantity, currency, cart
    }
    
    public init(value: Double, productId: String, quantity: Int, currency: String? = nil, cart: [CartItem]? = nil) {
        self.value = value
        self.productId = productId
        self.quantity = quantity
        self.currency = currency
        self.cart = cart
        super.init(type: "remove-from-cart-v1", name: "Remove from Cart")
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(productId, forKey: .productId)
        try container.encode(quantity, forKey: .quantity)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(cart, forKey: .cart)
    }
}

public class SyncCartEvent: TriggerEvent {
    public let value: Double
    public let currency: String?
    public let cart: [CartItem]?
    
    enum CodingKeys: String, CodingKey {
        case value, currency, cart
    }
    
    public init(value: Double, currency: String? = nil, cart: [CartItem]? = nil) {
        self.value = value
        self.currency = currency
        self.cart = cart
        super.init(type: "sync-cart-v1", name: "Sync cart")
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encodeIfPresent(cart, forKey: .cart)
    }
}

public class AddToWishlistEvent: TriggerEvent {
    public let value: Double
    public let productId: String
    
    enum CodingKeys: String, CodingKey {
        case value, productId
    }
    
    public init(value: Double, productId: String) {
        self.value = value
        self.productId = productId
        super.init(type: "add-to-wishlist-v1", name: "Add to Wishlist")
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(productId, forKey: .productId)
    }
}

public class SignUpEvent: TriggerEvent {
    public let hashedEmail: String?
    public let cuid: String?
    public let cuidType: String?
    
    enum CodingKeys: String, CodingKey {
        case hashedEmail, cuid, cuidType
    }
    
    public init(hashedEmail: String? = nil, cuid: String? = nil, cuidType: String? = nil) {
        self.hashedEmail = hashedEmail
        self.cuid = cuid
        self.cuidType = cuidType
        super.init(type: "signup-v1", name: "Signup")
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(hashedEmail, forKey: .hashedEmail)
        try container.encodeIfPresent(cuid, forKey: .cuid)
        try container.encodeIfPresent(cuidType, forKey: .cuidType)
    }
}

public class LoginEvent: TriggerEvent {
    public let hashedEmail: String?
    public let cuid: String?
    public let cuidType: String?
    
    enum CodingKeys: String, CodingKey {
        case hashedEmail, cuid, cuidType
    }
    
    public init(hashedEmail: String? = nil, cuid: String? = nil, cuidType: String? = nil) {
        self.hashedEmail = hashedEmail
        self.cuid = cuid
        self.cuidType = cuidType
        super.init(type: "login-v1", name: "Login")
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(hashedEmail, forKey: .hashedEmail)
        try container.encodeIfPresent(cuid, forKey: .cuid)
        try container.encodeIfPresent(cuidType, forKey: .cuidType)
    }
}

public class CustomEvent: TriggerEvent {
    public let customProps: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case customProps
    }
    
    public init(type: String, name: String, customProps: [String: String]? = nil) {
        self.customProps = customProps
        super.init(type: type, name: name)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(customProps, forKey: .customProps)
    }
}

public struct CartItem: Encodable {
    public let productId: String
    public let quantity: Int
    public let itemPrice: Double
    
    public init(productId: String, quantity: Int, itemPrice: Double) {
        self.productId = productId
        self.quantity = quantity
        self.itemPrice = itemPrice
    }
}
