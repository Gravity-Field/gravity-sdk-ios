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

@Test func buttonWithOnClickIsEnabled() {
    #expect(isButtonEnabled(true, onClick: OnClickModel(action: .close)))
}

@Test func buttonWithoutOnClickIsDisabled() {
    #expect(!isButtonEnabled(true, onClick: nil))
    #expect(!isButtonEnabled(false, onClick: OnClickModel(action: .close)))
}

@Test func explicitPressColorIsKept() {
    let color = Color(red: 0.1, green: 0.2, blue: 0.3)
    #expect(resolvePressColor(color, textColor: .white) == color)
}

@Test func defaultPressColorIsTextColorAt10Percent() {
    let resolved = resolvePressColor(nil, textColor: Color(red: 0.2, green: 0.4, blue: 0.6))
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(resolved).getRed(&r, green: &g, blue: &b, alpha: &a)
    #expect(abs(r - 0.2) < 0.001 && abs(g - 0.4) < 0.001 && abs(b - 0.6) < 0.001)
    #expect(abs(a - 0.1) < 0.001)
}
