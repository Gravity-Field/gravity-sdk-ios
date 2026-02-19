import Foundation

public enum TemplateSystemName: Decodable {
    case snackbar1
    case snackbar2
    case unknown
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        switch rawValue {
        case "snackbar-1": self = .snackbar1
        case "snackbar-2": self = .snackbar2
        default: self = .unknown
        }
    }
}
