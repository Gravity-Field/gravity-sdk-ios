import SwiftUI
import UIKit

/// Hosts the chat screen and calls `onDismissed` once, however the screen is dismissed.
internal final class AssistantHostingController<Content: View>: UIHostingController<Content> {

    var onDismissed: (() -> Void)?

    private var isReported = false

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        guard isBeingDismissed || presentingViewController == nil else { return }
        guard !isReported else { return }
        isReported = true

        let onDismissed = self.onDismissed
        self.onDismissed = nil
        onDismissed?()
    }
}
