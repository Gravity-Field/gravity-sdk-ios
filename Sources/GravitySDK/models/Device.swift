import Foundation

public struct Device: Codable {
    public let userAgent: String
    public let id: String?
    public let permission: NotificationPermissionStatus?
    public let tracking: String?

    public init(
        userAgent: String,
        id: String?,
        permission: NotificationPermissionStatus?,
        tracking: String?
    ) {
        self.userAgent = userAgent
        self.id = id
        self.permission = permission
        self.tracking = tracking
    }
}
