import Foundation

/// UI-thread state for one SDK-owned presentation. Completion follows physical dismissal.
internal final class InAppPresentation {
    private var isClosing = false
    private var result: Bool?
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
        init(_ presentation: InAppPresentation) { self.presentation = presentation }
    }
    private var entries: [String: Entry] = [:]

    func register(_ presentation: InAppPresentation, contentId: String) {
        entries = entries.filter { $0.value.presentation != nil }
        entries[contentId] = Entry(presentation)
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
