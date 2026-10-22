import Foundation
import Testing
@testable import GravitySDK

private let props = ["list": "search", "payment_type": "card"]
// 2026-09-03 09:00:15.250 UTC
private let time = Date(timeIntervalSince1970: 1_788_426_015.25)

private func wire<T: Encodable>(_ event: T) throws -> [String: Any] {
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

@Test func typedFieldsStillSerializeNextToCustomProps() throws {
    let json = try wire(AddToCartEvent(value: 99.5, productId: "sku-1", quantity: 2, currency: "RUB", customProps: props))
    #expect(Set(json.keys) == ["type", "name", "value", "productId", "quantity", "currency", "customProps"])
    #expect(json["type"] as? String == "add-to-cart-v1")
    #expect(json["name"] as? String == "Add to Cart")
    #expect(json["value"] as? Double == 99.5)
    #expect(json["productId"] as? String == "sku-1")
    #expect(json["quantity"] as? Int == 2)
    #expect(json["currency"] as? String == "RUB")
    #expect(json["customProps"] as? [String: String] == props)
}

@Test func emptyCustomPropsIsSentAsEmptyObject() throws {
    let json = try wire(CustomEvent(type: "x", name: "X", customProps: [:]))
    #expect((json["customProps"] as? [String: String])?.isEmpty == true)
}

@Test func eventTimeIsSentInUtcWhateverTheTimeZoneItWasBuiltIn() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Novosibirsk"))
    // 16:00:15.250 in Novosibirsk (UTC+7) is 09:00:15.250 UTC
    let local = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 16, minute: 0, second: 15, nanosecond: 250_000_000))
    )
    let json = try wire(CustomEvent(type: "x", name: "X", eventTime: local))
    #expect(json["eventTime"] as? String == "2026-09-03T09:00:15.250Z")
}

@Test func eventsWithoutEventTimeGetTheRaisedAtTime() throws {
    let raisedAt = time.addingTimeInterval(60)
    let explicit = try wire(EventPayload(event: CustomEvent(type: "a", name: "A", eventTime: time), raisedAt: raisedAt))
    let implicit = try wire(EventPayload(event: CustomEvent(type: "b", name: "B"), raisedAt: raisedAt))
    #expect(explicit["eventTime"] as? String == "2026-09-03T09:00:15.250Z")
    #expect(implicit["eventTime"] as? String == "2026-09-03T09:01:15.250Z")
    #expect(implicit["type"] as? String == "b")
}

@Test func payloadKeepsTypedFieldsWhenAddingEventTime() throws {
    let json = try wire(EventPayload(event: AddToCartEvent(value: 99.5, productId: "sku-1", quantity: 2), raisedAt: time))
    #expect(Set(json.keys) == ["type", "name", "value", "productId", "quantity", "eventTime"])
    #expect(json["type"] as? String == "add-to-cart-v1")
    #expect(json["productId"] as? String == "sku-1")
    #expect(json["eventTime"] as? String == "2026-09-03T09:00:15.250Z")
}

/// Unset optional fields are omitted, not sent as null.
@Test func unsetTypedFieldsAreOmitted() throws {
    let events: [TriggerEvent] = [
        AddToCartEvent(value: 1, productId: "p", quantity: 1),
        RemoveFromCartEvent(value: 1, productId: "p", quantity: 1),
        SyncCartEvent(value: 1),
        PurchaseEvent(uniqueTransactionId: "t", value: 1, cart: []),
        AddToWishlistEvent(value: 1, productId: "p"),
        SignUpEvent(),
        LoginEvent(),
        CustomEvent(type: "x", name: "X"),
    ]
    for event in events {
        let json = try wire(event)
        #expect(!json.values.contains { $0 is NSNull }, "\(event.type)")
    }
}
