import Foundation

public class TriggerEvent: Encodable {
    public let type: String
    public let name: String
    /// Extra properties sent alongside the typed fields. String values only.
    public let customProps: [String: String]?
    /// When the event happened; sent in UTC. Omitted, the time `triggerEvent` was called is sent.
    public let eventTime: Date?
    
    enum CodingKeys: String, CodingKey {
        case type, name, customProps, eventTime
    }
    
    internal init(type: String, name: String, customProps: [String: String]?, eventTime: Date?) {
        self.type = type
        self.name = name
        self.customProps = customProps
        self.eventTime = eventTime
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(customProps, forKey: .customProps)
        try container.encodeIfPresent(eventTime.map(formatEventTime), forKey: .eventTime)
    }
}

/// An event as it goes into the /event body: events without their own eventTime
/// get `raisedAt`, the moment the app raised them; an explicit eventTime is kept.
struct EventPayload: Encodable {
    let event: TriggerEvent
    let raisedAt: Date

    func encode(to encoder: Encoder) throws {
        try event.encode(to: encoder)
        if event.eventTime == nil {
            var container = encoder.container(keyedBy: TriggerEvent.CodingKeys.self)
            try container.encode(formatEventTime(raisedAt), forKey: .eventTime)
        }
    }
}

/// RFC 3339 timestamp in UTC with millisecond precision, e.g. `2026-08-28T11:00:00.123Z`.
func formatEventTime(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
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
    
    public init(value: Double, productId: String, quantity: Int, currency: String? = nil, cart: [CartItem]? = nil, customProps: [String: String]? = nil, eventTime: Date? = nil) {
        self.value = value
        self.productId = productId
        self.quantity = quantity
        self.currency = currency
        self.cart = cart
        super.init(type: "add-to-cart-v1", name: "Add to Cart", customProps: customProps, eventTime: eventTime)
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
    
    public init(uniqueTransactionId: String, value: Double, cart: [CartItem], currency: String? = nil, customProps: [String: String]? = nil, eventTime: Date? = nil) {
        self.uniqueTransactionId = uniqueTransactionId
        self.value = value
        self.cart = cart
        self.currency = currency
        super.init(type: "purchase-v1", name: "Purchase", customProps: customProps, eventTime: eventTime)
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
    
    public init(value: Double, productId: String, quantity: Int, currency: String? = nil, cart: [CartItem]? = nil, customProps: [String: String]? = nil, eventTime: Date? = nil) {
        self.value = value
        self.productId = productId
        self.quantity = quantity
        self.currency = currency
        self.cart = cart
        super.init(type: "remove-from-cart-v1", name: "Remove from Cart", customProps: customProps, eventTime: eventTime)
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
    
    public init(value: Double, currency: String? = nil, cart: [CartItem]? = nil, customProps: [String: String]? = nil, eventTime: Date? = nil) {
        self.value = value
        self.currency = currency
        self.cart = cart
        super.init(type: "sync-cart-v1", name: "Sync cart", customProps: customProps, eventTime: eventTime)
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
    
    public init(value: Double, productId: String, customProps: [String: String]? = nil, eventTime: Date? = nil) {
        self.value = value
        self.productId = productId
        super.init(type: "add-to-wishlist-v1", name: "Add to Wishlist", customProps: customProps, eventTime: eventTime)
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
    
    public init(hashedEmail: String? = nil, cuid: String? = nil, cuidType: String? = nil, customProps: [String: String]? = nil, eventTime: Date? = nil) {
        self.hashedEmail = hashedEmail
        self.cuid = cuid
        self.cuidType = cuidType
        super.init(type: "signup-v1", name: "Signup", customProps: customProps, eventTime: eventTime)
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
    
    public init(hashedEmail: String? = nil, cuid: String? = nil, cuidType: String? = nil, customProps: [String: String]? = nil, eventTime: Date? = nil) {
        self.hashedEmail = hashedEmail
        self.cuid = cuid
        self.cuidType = cuidType
        super.init(type: "login-v1", name: "Login", customProps: customProps, eventTime: eventTime)
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
    public let cuid: String?
    public let cuidType: String?
    public let cart: [CartItem]?
    
    enum CodingKeys: String, CodingKey {
        case cuid, cuidType, cart
    }
    
    public init(
        type: String,
        name: String,
        cuid: String? = nil,
        cuidType: String? = nil,
        cart: [CartItem]? = nil,
        customProps: [String: String]? = nil,
        eventTime: Date? = nil
    ) {
        self.cuid = cuid
        self.cuidType = cuidType
        self.cart = cart
        super.init(type: type, name: name, customProps: customProps, eventTime: eventTime)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cuid, forKey: .cuid)
        try container.encodeIfPresent(cuidType, forKey: .cuidType)
        try container.encodeIfPresent(cart, forKey: .cart)
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
