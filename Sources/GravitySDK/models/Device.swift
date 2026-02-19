import Foundation

public struct Device: Codable {
    public let id: String
    public let userAgent: String
    public let permission: NotificationPermissionStatus?
    public let tracking: String?

    public init(
        id: String,
        userAgent: String,
        permission: NotificationPermissionStatus?,
        tracking: String?,
    ) {
        self.id = id
        self.userAgent = userAgent
        self.permission = permission
        self.tracking = tracking
    }
}
