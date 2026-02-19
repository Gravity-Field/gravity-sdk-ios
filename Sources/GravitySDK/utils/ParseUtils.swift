import SwiftUI

class ParseUtils {
    static func parseColor(_ color: String?) -> Color? {
        guard let color = color else { return nil }
        if let color = Color(hex: color) {
            return color
        }
        return nil
    }
}
