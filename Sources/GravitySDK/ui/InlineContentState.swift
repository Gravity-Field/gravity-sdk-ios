import Foundation
import Combine
import SwiftUI
import UIKit

/// Tracks removal from the window even when a UIKit host is retained for reuse.
internal struct InlinePlacementLifecycle: UIViewRepresentable {
    let onMount: () -> Void
    let onUnmount: () -> Void

    func makeUIView(context: Context) -> LifecycleView {
        let view = LifecycleView()
        view.onMount = onMount
        view.onUnmount = onUnmount
        return view
    }

    func updateUIView(_ view: LifecycleView, context: Context) {
        view.onMount = onMount
        view.onUnmount = onUnmount
    }

    final class LifecycleView: UIView {
        var onMount: (() -> Void)?
        var onUnmount: (() -> Void)?
        private var mounted = false
        private var notifiedMount = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            let mounted = window != nil
            guard self.mounted != mounted else { return }
            self.mounted = mounted
            if mounted {
                // Starting a load publishes state; let SwiftUI finish mounting first.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.mounted, !self.notifiedMount else { return }
                    self.notifiedMount = true
                    self.onMount?()
                }
            } else {
                notifiedMount = false
                onUnmount?()
            }
        }
    }
}

/// Shared lifecycle for every inline placement. Stale loads retry for the current
/// identity; already rendered content stays until a normal reload. Access on the main thread.
internal final class InlineContentState<Value>: ObservableObject {
    struct Load: Equatable {
        fileprivate let generation: UInt64
        fileprivate let id = UUID()
    }

    @Published private(set) var value: Value?
    @Published private(set) var isLoading = true
    @Published private(set) var height: CGFloat?

    private let sessions: SessionManager
    private var active: Load?
    private var isMounted = false
    private var completed = false
    private var pendingContextChange = false

    init(sessions: SessionManager = GravityRepository.instance.sessionManager) {
        self.sessions = sessions
    }

    func appear() { isMounted = true }

    func disappear() {
        isMounted = false
    }

    /// A new context may retry a finished empty/failed load; remounting alone may not.
    func pageContextChanged() {
        if active != nil { pendingContextChange = true }
        else if value == nil { completed = false }
    }

    func begin() -> Load? {
        guard isMounted, !completed else { return nil }
        if let active, sessions.isCurrent(active.generation) { return nil }
        let load = Load(generation: sessions.generation)
        active = load
        pendingContextChange = false
        isLoading = true
        return load
    }

    /// Returns true when the caller must retry its load for the current identity.
    @discardableResult
    func complete(_ load: Load, value: Value?, height: CGFloat?) -> Bool {
        guard active == load else { return false }
        active = nil
        let contextChanged = pendingContextChange
        pendingContextChange = false
        guard sessions.isCurrent(load.generation), !contextChanged else {
            return isMounted
        }
        completed = true
        self.value = value
        self.height = height
        isLoading = false
        return false
    }

    func clear() {
        completed = false
        pendingContextChange = false
        active = nil
        value = nil
        height = 0
        isLoading = false
    }
}
