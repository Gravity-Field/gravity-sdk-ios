// Runs without Xcode/XCTest: swiftc Sources/GravitySDK/utils/{PreparationDeadline,PresentationRevision,InAppPresentation}.swift
// scripts/validate-preparation-core.swift -o /tmp/gravity-preparation-check && /tmp/gravity-preparation-check
import Foundation

@main struct PreparationCoreValidation {
    static func main() async {
        let value = await PreparationDeadline.run(timeout: 1) { 42 }
        precondition(value == 42)

        struct Failure: Error {}
        let failed: Int? = await PreparationDeadline.run(timeout: 1) { throw Failure() }
        precondition(failed == nil)

        let timedOut: Int? = await PreparationDeadline.run(timeout: 0.025) {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return 42
        }
        precondition(timedOut == nil)

        // A late callback must not delay the timeout or resume its continuation twice.
        let start = Date()
        let late: Int? = await PreparationDeadline.run(timeout: 0.025) {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                    continuation.resume(returning: ())
                }
            }
            return 42
        }
        precondition(late == nil && Date().timeIntervalSince(start) < 0.3)
        try? await Task.sleep(nanoseconds: 500_000_000)

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await PreparationDeadline.run(timeout: 1) { 42 }
        }
        let cancelledValue = await cancelled.value
        precondition(cancelledValue == nil)

        let revision = PresentationRevision()
        let original = revision.current
        precondition(revision.canPresent(expected: original, active: true, locked: false, cancelled: false))
        precondition(!revision.canPresent(expected: original, active: false, locked: false, cancelled: false))
        precondition(!revision.canPresent(expected: original, active: true, locked: true, cancelled: false))
        precondition(!revision.canPresent(expected: original, active: true, locked: false, cancelled: true))
        revision.invalidate()
        revision.invalidate()
        precondition(revision.current != original)
        precondition(!revision.canPresent(expected: original, active: true, locked: false, cancelled: false))

        // Repeated races exercise both registration/completion orderings.
        for _ in 0..<200 {
            let immediate = await PreparationDeadline.run(timeout: 0.1) { 7 }
            precondition(immediate == 7)
        }
        let registry = InAppPresentationRegistry()
        var events: [String] = []
        var finish: ((Bool) -> Void)?
        let a = InAppPresentation(performDismiss: { events.append("animate"); finish = $0 },
                                 didDismiss: { _ in events.append("close") })
        let b = InAppPresentation(performDismiss: { _ in preconditionFailure("Wrong target") },
                                 didDismiss: { _ in })
        registry.register(a, contentId: "A")
        registry.register(b, contentId: "B")
        registry.dismiss(contentId: "A") { success in precondition(success); events.append("navigate") }
        precondition(events == ["animate"])
        registry.dismiss(contentId: "A") { precondition(!$0) }
        finish?(true)
        finish?(true)
        precondition(events == ["animate", "close", "navigate"])
        registry.dismiss(contentId: "inline") { precondition(!$0) }
        registry.remove(a, contentId: "A")
        registry.dismiss(contentId: "A") { precondition(!$0) }

        print("PASS: preparation/gate, 200 races, targeted dismissal, callback ordering, duplicate close, inline unaffected")
    }
}
