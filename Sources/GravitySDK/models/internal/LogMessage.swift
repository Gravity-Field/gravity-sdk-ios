import Foundation

internal enum LogMessageLevel: String, Codable {
    case error
    case warning
    case info
    case debug
}

internal struct LogMessage: Codable {
    internal let message: String
    internal let level: LogMessageLevel
    internal let sec: String
    internal let uid: String
    internal let ses: String
    internal let sdkVersion: String
    internal let platform: String
    internal let extra: [String: String]
    internal let tags: [String: String]
    internal let stacktrace: String
    internal let sdkType: String = "ios_native"

    public init(
        message: String,
        level: LogMessageLevel,
        sec: String,
        uid: String,
        ses: String,
        sdkVersion: String,
        platform: String,
        stacktrace: String = "",
        extra: [String: String] = [:],
        tags: [String: String] = [:]
    ) {
        self.message = message
        self.level = level
        self.sec = sec
        self.uid = uid
        self.ses = ses
        self.sdkVersion = sdkVersion
        self.platform = platform
        self.stacktrace = stacktrace
        self.extra = extra
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case message
        case level
        case sec
        case uid
        case ses
        case sdkVersion
        case sdkType
        case platform
        case extra
        case tags
        case stacktrace
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        level = try container.decode(LogMessageLevel.self, forKey: .level)
        sec = try container.decode(String.self, forKey: .sec)
        uid = try container.decode(String.self, forKey: .uid)
        ses = try container.decode(String.self, forKey: .ses)
        sdkVersion = try container.decode(String.self, forKey: .sdkVersion)
        platform = try container.decode(String.self, forKey: .platform)
        extra = try container.decode([String: String].self, forKey: .extra)
        tags = try container.decode([String: String].self, forKey: .tags)
        stacktrace = try container.decode(String.self, forKey: .stacktrace)
    }
}
