import Foundation
import Testing
@testable import GravitySDK

private let props = ["list": "search", "payment_type": "card"]
// 2026-09-03 09:00:15.250 UTC
private let time = Date(timeIntervalSince1970: 1_788_426_015.25)

private func wire(_ event: TriggerEvent) throws -> [String: Any] {
    let data = try JSONEncoder().encode(event)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func typedEvents(customProps: [String: String]? = nil, eventTime: Date? = nil) -> [TriggerEvent] {
    [
        AddToCartEvent(value: 1, productId: "p", quantity: 1, customProps: customProps, eventTime: eventTime),
        RemoveFromCartEvent(value: 1, productId: "p", quantity: 1, customProps: customProps, eventTime: eventTime),
        SyncCartEvent(value: 1, customProps: customProps, eventTime: eventTime),
        PurchaseEvent(uniqueTransactionId: "t", value: 1, cart: [], customProps: customProps, eventTime: eventTime),
        AddToWishlistEvent(value: 1, productId: "p", customProps: customProps, eventTime: eventTime),
        SignUpEvent(cuid: "c", customProps: customProps, eventTime: eventTime),
        LoginEvent(cuid: "c", customProps: customProps, eventTime: eventTime),
        CustomEvent(type: "x", name: "X", customProps: customProps, eventTime: eventTime),
    ]
}

@Test func everyEventSendsCustomPropsAndEventTimeWhenSet() throws {
    for event in typedEvents(customProps: props, eventTime: time) {
        let json = try wire(event)
        #expect(json["customProps"] as? [String: String] == props, "\(event.type)")
        #expect(json["eventTime"] as? String == "2026-09-03T09:00:15.250Z", "\(event.type)")
        #expect(json["type"] as? String == event.type)
    }
}

@Test func unsetCustomPropsAndEventTimeAreOmitted() throws {
    for event in typedEvents() {
        let json = try wire(event)
        #expect(json["customProps"] == nil, "\(event.type)")
        #expect(json["eventTime"] == nil, "\(event.type)")
    }
}

@Test func customEventCarriesCuidCuidTypeCartAndEventTime() throws {
    let json = try wire(
        CustomEvent(
            type: "loyalty-v1",
            name: "Loyalty",
            cuid: "user@example.com",
            cuidType: "email",
            cart: [CartItem(productId: "sku-1", quantity: 2, itemPrice: 10.5)],
            customProps: props,
            eventTime: time
        )
    )
    #expect(Set(json.keys) == ["type", "name", "cuid", "cuidType", "cart", "customProps", "eventTime"])
    #expect(json["cuid"] as? String == "user@example.com")
    #expect(json["cuidType"] as? String == "email")
    let cart = try #require(json["cart"] as? [[String: Any]])
    #expect(cart.count == 1)
    #expect(cart[0]["productId"] as? String == "sku-1")
    #expect(cart[0]["quantity"] as? Int == 2)
    #expect(cart[0]["itemPrice"] as? Double == 10.5)
    #expect(json["eventTime"] as? String == "2026-09-03T09:00:15.250Z")
}

@Test func customEventWithoutNewFieldsIsUnchangedOnTheWire() throws {
    let json = try wire(CustomEvent(type: "x", name: "X"))
    #expect(Set(json.keys) == ["type", "name"])
}

@Test func customEventKeepsLegacyCustomPropsInit() throws {
    let json = try wire(CustomEvent(type: "x", name: "X", customProps: ["a": "b"]))
    #expect(json["customProps"] as? [String: String] == ["a": "b"])
}
