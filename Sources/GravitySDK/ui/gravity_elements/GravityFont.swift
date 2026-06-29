import SwiftUI
import UIKit

func gravityFont(size: CGFloat?, fontWeight: Double?) -> Font? {
    if let base = GravitySDK.instance.customFont {
        let pointSize = size ?? UIFont.labelFontSize
        guard let fontWeight = fontWeight else {
            return Font(base.withSize(pointSize))
        }
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [
                UIFontDescriptor.TraitKey.weight: fontWeight.toUIFontWeight()
            ]
        ])
        return Font(UIFont(descriptor: descriptor, size: pointSize))
    }

    let weight = fontWeight?.toWeight()
    switch (size, weight) {
    case let (s?, w?):
        return .system(size: s, weight: w)
    case let (s?, nil):
        return .system(size: s)
    case let (nil, w?):
        return .system(size: UIFont.labelFontSize, weight: w)
    default:
        return nil
    }
}
