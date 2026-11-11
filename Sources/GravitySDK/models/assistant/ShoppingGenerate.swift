import Foundation

/// Response of `POST /shopping/generate`.
internal struct ShoppingGenerateResponse {
    let threadId: String?
    let resourceId: String?
    let assistantMessageId: String?
    let contents: [ShoppingContent]
    let suggests: [String]
    let events: [ShoppingEngagementEvent]

    static func fromJson(_ json: JSONValue) -> ShoppingGenerateResponse {
        let response = json["response"]
        let ui = response?["ui"]

        return ShoppingGenerateResponse(
            threadId: json["threadId"]?.stringValue,
            resourceId: json["resourceId"]?.stringValue,
            assistantMessageId: json["assistantMessageId"]?.stringValue,
            contents: (response?["contents"]?.arrayValue ?? [])
                .compactMap(ShoppingContent.fromJson),
            suggests: (ui?["suggests"]?.arrayValue ?? [])
                .compactMap { $0.stringValue },
            events: parseShoppingEvents(json["events"])
        )
    }
}

internal enum ShoppingContent {
    case message(value: String)
    case products(title: String?, shelfId: String?, products: [ShoppingProduct])
    case button(value: String, action: String, url: String?)

    static func fromJson(_ json: JSONValue) -> ShoppingContent? {
        switch json["type"]?.stringValue {
        case "message":
            guard let value = json["value"]?.stringValue else { return nil }
            return .message(value: value)

        case "products":
            return .products(
                title: json["title"]?.stringValue,
                shelfId: json["shelf_id"]?.stringValue,
                products: (json["value"]?.arrayValue ?? [])
                    .compactMap(ShoppingProduct.fromJson)
            )

        case "button":
            guard let value = json["value"]?.stringValue,
                  let action = json["action"]?.stringValue
            else { return nil }
            return .button(value: value, action: action, url: json["url"]?.stringValue)

        default:
            return nil
        }
    }
}

internal struct ShoppingProduct {
    let name: String
    let sku: String?
    let categoryId: String?
    let price: Double?
    let features: String?
    let isStm: Bool?
    let brand: String?
    let url: String?
    let imageUrl: String?
    let events: [ShoppingEngagementEvent]

    static func fromJson(_ json: JSONValue) -> ShoppingProduct? {
        guard let name = json["name"]?.stringValue else { return nil }

        return ShoppingProduct(
            name: name,
            sku: json["sku"]?.stringValue,
            categoryId: json["category_id"]?.stringValue,
            price: json["price"]?.doubleValue,
            features: json["features"]?.stringValue,
            isStm: json["is_stm"]?.boolValue,
            brand: json["brand"]?.stringValue,
            url: json["url"]?.stringValue,
            imageUrl: json["image_url"]?.stringValue,
            events: parseShoppingEvents(json["events"])
        )
    }
}

internal struct ShoppingEngagementEvent {
    let type: String
    let urls: [String]
}

/// Parses engagement events; each event has either a `urls` array or a single `url`.
private func parseShoppingEvents(_ raw: JSONValue?) -> [ShoppingEngagementEvent] {
    guard let events = raw?.arrayValue else { return [] }

    return events.compactMap { event in
        guard let type = event["type"]?.stringValue else { return nil }

        let urls: [String]
        if let list = event["urls"]?.arrayValue {
            urls = list.compactMap { $0.stringValue }
        } else {
            urls = [event["url"]?.stringValue].compactMap { $0 }
        }

        return urls.isEmpty ? nil : ShoppingEngagementEvent(type: type, urls: urls)
    }
}
