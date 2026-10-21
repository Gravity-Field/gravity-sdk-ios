import SwiftUI
import Testing
import UIKit
@testable import GravitySDK

private func alpha(of color: Color) -> CGFloat {
    var a: CGFloat = 0
    UIColor(color).getRed(nil, green: nil, blue: nil, alpha: &a)
    return a
}

@Test func outlineColorAbsentGivesNoBorder() {
    #expect(resolveOutlineColor(nil, enabled: true) == nil)
    #expect(resolveOutlineColor(nil, enabled: false) == nil)
}

@Test func enabledButtonKeepsOutlineColor() {
    let color = Color(red: 0.1, green: 0.2, blue: 0.3)
    #expect(resolveOutlineColor(color, enabled: true) == color)
}

@Test func disabledButtonSetsOutlineAlphaTo04() throws {
    let color = Color(red: 0.1, green: 0.2, blue: 0.3)
    let resolved = try #require(resolveOutlineColor(color, enabled: false))
    #expect(abs(alpha(of: resolved) - 0.4) < 0.001)
}
