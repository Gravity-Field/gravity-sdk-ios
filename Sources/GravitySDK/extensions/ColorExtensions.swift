import SwiftUI

extension Color {
    init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        let length = hex.count
        
        if (length == 6) {
            hex = "\(hex)ff"
        } else {
            let rrggbb = String(hex.prefix(6))
            let aa = String(hex.suffix(2))
            hex = "\(aa)\(rrggbb)"
        }
        
        guard Scanner(string: hex).scanHexInt64(&rgb) else { return nil }
        
        var r, g, b, a: Double
        
        if length == 6 { // RRGGBB
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 { // AARRGGBB
            a = Double((rgb & 0xFF000000) >> 24) / 255.0
            r = Double((rgb & 0x00FF0000) >> 16) / 255.0
            g = Double((rgb & 0x0000FF00) >> 8) / 255.0
            b = Double(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
