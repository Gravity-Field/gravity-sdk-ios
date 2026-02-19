import SwiftUI
import UIKit


public protocol ProductViewBuilder {
    @ViewBuilder
    func build(slot: Slot) -> AnyView
}
