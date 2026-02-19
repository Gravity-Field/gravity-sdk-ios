import Foundation

public enum DeliveryMethod: Decodable, Equatable {
    case snackBar
    case modal
    case bottomSheet
    case fullScreen
    case inline
    case unknown
    
    public init(from decoder: Decoder) throws {
        let container = try? decoder.singleValueContainer()
        let rawValue = try? container?.decode(String.self)
        self = DeliveryMethod.fromString(rawValue)
    }
    
    public static func fromString(_ value: String?) -> DeliveryMethod {
        guard let value = value else { return .unknown }
        
        switch value.lowercased() {
        case "snackbar", "snack_bar":
            return .snackBar
        case "modal":
            return .modal
        case "bottomsheet", "bottom-sheet", "bottom_sheet":
            return .bottomSheet
        case "fullscreen", "full_screen", "full-screen":
            return .fullScreen
        case "inline":
            return .inline
        default:
            return .unknown
        }
    }
}
