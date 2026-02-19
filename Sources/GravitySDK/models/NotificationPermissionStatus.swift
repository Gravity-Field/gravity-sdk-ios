public enum NotificationPermissionStatus: String, Codable {
    case granted
    case denied
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "granted": self = .granted
        case "denied": self = .denied
        default: self = .unknown
        }
    }
}
