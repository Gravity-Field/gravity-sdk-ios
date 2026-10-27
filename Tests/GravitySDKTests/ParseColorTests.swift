import SwiftUI
import Testing
import UIKit
@testable import GravitySDK

// Same vectors as ParseColorTest.kt in the Android SDK; valid ones match Flutter's ParseUtils.parseColor.
private func rgba(_ hex: String) -> [Int]? {
    guard let color = ParseUtils.parseColor(hex) else { return nil }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return [r, g, b, a].map { Int(($0 * 255).rounded()) }
}

@Test func rrggbbIsOpaque() {
    #expect(rgba("#FF0000") == [255, 0, 0, 255])
    #expect(rgba("#00FF00") == [0, 255, 0, 255])
    #expect(rgba("#0000FF") == [0, 0, 255, 255])
    #expect(rgba("#000000") == [0, 0, 0, 255])
    #expect(rgba("#FFFFFF") == [255, 255, 255, 255])
    #expect(rgba("#123456") == [0x12, 0x34, 0x56, 255])
}

@Test func rrggbbaaTakesAlphaFromLastPair() {
    #expect(rgba("#FF0000FF") == rgba("#FF0000"))
    #expect(rgba("#12345680") == [0x12, 0x34, 0x56, 0x80])
    #expect(rgba("#12345600") == [0x12, 0x34, 0x56, 0])
}

@Test func lowercaseAndUppercaseHexAreEqual() {
    #expect(rgba("#abcdef") == rgba("#ABCDEF"))
    #expect(rgba("#abcdef80") == rgba("#ABCDEF80"))
    #expect(rgba("#abcdef") == [0xAB, 0xCD, 0xEF, 255])
}

@Test(arguments: [
    "", "FF0000", "#", "#FFF", "#FF00000", "#FF0000000",
    "#GG0000", "#+F0000", "#FF0000-1", "#0xFF00", " #FF0000", "#FF0000 ", "#ＦＦ0000",
    "#12345 ", "#123456+7", "#123456-7",
])
func invalidInputGivesNil(_ hex: String) {
    #expect(ParseUtils.parseColor(hex) == nil)
}

@Test func nilGivesNil() {
    #expect(ParseUtils.parseColor(nil) == nil)
}
