import Foundation

/// UI-thread state for one SDK-owned presentation. Completion follows physical dismissal.
internal final class InAppPresentation {
    private var isClosing = false
    private var result: Bool?
    var isOpen: Bool { result == nil && !isClosing }
    private let willClose: () -> Void
    private let performDismiss: (@escaping (Bool) -> Void) -> Void
    private let didDismiss: (Bool) -> Void

    init(willClose: @escaping () -> Void = {},
         performDismiss: @escaping (@escaping (Bool) -> Void) -> Void,
         didDismiss: @escaping (Bool) -> Void) {
        self.willClose = willClose
        self.performDismiss = performDismiss
        self.didDismiss = didDismiss
    }

    /// UIKit may remove the host without invoking an SDK close action.
    func removedExternally() {
        guard result == nil, !isClosing else { return }
        isClosing = true
        willClose()
        result = true
        didDismiss(true)
    }

    func close(completion: @escaping (Bool) -> Void = { _ in }) {
        guard result == nil, !isClosing else { completion(false); return }
        isClosing = true
        willClose()
        performDismiss { [self] success in
            guard result == nil else { return }
            result = success
            didDismiss(success)
            completion(success)
        }
    }
}

/// Weak references ensure an externally removed UI is not retained by the SDK.
internal final class InAppPresentationRegistry {
    private final class Entry {
        weak var presentation: InAppPresentation?
        let campaignId: String?
        init(_ presentation: InAppPresentation, campaignId: String?) {
            self.presentation = presentation
            self.campaignId = campaignId
        }
    }
    private var entries: [String: Entry] = [:]

    /// True while this content is mounted, until its dismissal completes.
    func contains(contentId: String) -> Bool {
        entries[contentId]?.presentation != nil
    }

    /// True while any content of this campaign is mounted, until its dismissal completes.
    func containsCampaign(_ campaignId: String) -> Bool {
        entries.values.contains { $0.campaignId == campaignId && $0.presentation != nil }
    }

    func register(_ presentation: InAppPresentation, contentId: String, campaignId: String? = nil) {
        entries = entries.filter { $0.value.presentation != nil }
        entries[contentId] = Entry(presentation, campaignId: campaignId)
    }

    func remove(_ presentation: InAppPresentation?, contentId: String) {
        if entries[contentId]?.presentation === presentation { entries.removeValue(forKey: contentId) }
    }

    func dismiss(contentId: String, completion: @escaping (Bool) -> Void) {
        guard let presentation = entries[contentId]?.presentation else {
            entries.removeValue(forKey: contentId)
            completion(false)
            return
        }
        presentation.close(completion: completion)
    }
}

#if canImport(UIKit)
import UIKit
import SwiftUI

/// Marks a controller that hosts an SDK modal, fullscreen or bottom sheet.
internal protocol GravityInAppHost: UIViewController {}

/// Observes host removal while leaving SDK-owned dismissal completion in charge.
internal final class InAppHostingController<Content: View>: UIHostingController<Content>, GravityInAppHost {
    var onExternalRemoval: (() -> Void)?
    private var hasAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard hasAppeared else { return }
        if isBeingDismissed || presentingViewController == nil
            || (presentedViewController == nil && viewIfLoaded?.window == nil) {
            onExternalRemoval?()
        }
    }
}
#endif
