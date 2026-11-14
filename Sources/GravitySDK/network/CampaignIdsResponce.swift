import Foundation

struct CampaignIdsResponse: Codable {
    let user: User?
    let campaigns: [CampaignId]

    enum CodingKeys: String, CodingKey {
        case user, campaigns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decodeIfPresent(User.self, forKey: .user)
        campaigns = try container.decodeIfPresent([CampaignId].self, forKey: .campaigns) ?? []
    }
}

struct CampaignId: Codable {
    let campaignId: String
    let trigger: String
    let priority: Int?
    let delayTime: Int?

    enum CodingKeys: String, CodingKey {
        case campaignId, trigger, priority, delayTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        campaignId = try container.decode(String.self, forKey: .campaignId)
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger) ?? ""
        priority = container.tolerantInteger(forKey: .priority)
        delayTime = container.tolerantInteger(forKey: .delayTime)
    }
}

private extension KeyedDecodingContainer {
    /// Optional campaign metadata must not invalidate the campaign list.
    func tolerantInteger(forKey key: Key) -> Int? {
        if let string = try? decode(String.self, forKey: key) {
            return exactCampaignInteger(string)
        }
        if let integer = try? decode(Int.self, forKey: key) { return integer }
        guard let number = try? decode(Double.self, forKey: key) else { return nil }
        guard number.isFinite else { return nil }
        if number >= Double(Int.max) { return Int.max }
        if number <= Double(Int.min) { return Int.min }
        return Int(number.rounded(.towardZero))
    }
}

// Unicode White_Space, deliberately excluding U+FEFF and U+200B. Foundation's
// broader whitespace sets do not define the campaign wire contract.
private let campaignWhiteSpace = CharacterSet(charactersIn:
    "\u{9}\u{A}\u{B}\u{C}\u{D}\u{20}\u{85}\u{A0}\u{1680}"
    + "\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
    + "\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}")

/// Parse ASCII decimal notation exactly, truncating before saturating to Int.
/// Work is linear in the input length. Keep at most 19 significant digits and
/// cap the exponent relative to the input length: never expand exponent zeros.
private func exactCampaignInteger(_ string: String) -> Int? {
    let bytes = Array(string.trimmingCharacters(in: campaignWhiteSpace).utf8)
    guard !bytes.isEmpty else { return nil }
    var index = 0
    let negative = bytes[0] == 45
    if bytes[0] == 43 || negative { index += 1 }
    var digitCount = 0
    var firstNonzero: Int?
    var significant: [UInt8] = []
    significant.reserveCapacity(19)
    func consumeDigits() {
        while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
            let digit = bytes[index] - 48
            if firstNonzero == nil, digit != 0 { firstNonzero = digitCount }
            if firstNonzero != nil, significant.count < 19 { significant.append(digit) }
            digitCount += 1
            index += 1
        }
    }
    consumeDigits()
    let integerDigits = digitCount
    if index < bytes.count, bytes[index] == 46 {
        index += 1
        consumeDigits()
    }
    guard digitCount > 0 else { return nil }
    var exponent = 0
    var negativeExponent = false
    if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
        index += 1
        if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 {
            negativeExponent = bytes[index] == 45
            index += 1
        }
        let exponentStart = index
        let limit = bytes.count > Int.max - 20 ? Int.max : bytes.count + 20
        while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
            let digit = Int(bytes[index] - 48)
            exponent = exponent > (limit - digit) / 10 ? limit : exponent * 10 + digit
            index += 1
        }
        guard index > exponentStart else { return nil }
    }
    guard index == bytes.count else { return nil }
    guard let firstNonzero else { return 0 }
    let shifted = (integerDigits - firstNonzero).addingReportingOverflow(
        negativeExponent ? -exponent : exponent)
    let integerLength = shifted.overflow ? (negativeExponent ? Int.min : Int.max) : shifted.partialValue
    guard integerLength > 0 else { return 0 }
    guard integerLength <= 19 else { return negative ? Int.min : Int.max }
    var magnitude: UInt64 = 0
    for position in 0..<integerLength {
        magnitude = magnitude * 10 + UInt64(position < significant.count ? significant[position] : 0)
    }
    let bound = UInt64(Int.max) + (negative ? 1 : 0)
    guard magnitude < bound else { return negative ? Int.min : Int.max }
    return negative ? -Int(magnitude) : Int(magnitude)
}
