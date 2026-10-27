import SwiftUI

extension Color {
    /// Parses `#RRGGBB` (opaque) and `#RRGGBBAA` (alpha last), same as the Flutter SDK. Anything else gives nil.
    init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let hex = hex.dropFirst()
        guard hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        guard hex.count == 6 || hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }

        let rgba = hex.count == 6 ? (value << 8) | 0xFF : value

        let r = Double((rgba >> 24) & 0xFF) / 255.0
        let g = Double((rgba >> 16) & 0xFF) / 255.0
        let b = Double((rgba >> 8) & 0xFF) / 255.0
        let a = Double(rgba & 0xFF) / 255.0

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
