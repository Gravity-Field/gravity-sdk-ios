import Foundation
import XCTest
@testable import GravitySDK

final class PreparationDeadlineTests: XCTestCase {
    func testValueReturnsBeforeDeadline() async {
        let result = await PreparationDeadline.run(timeout: 1) { 42 }
        XCTAssertEqual(result, 42)
    }

    func testErrorsReturnNil() async {
        struct Failure: Error {}
        let result: Int? = await PreparationDeadline.run(timeout: 1) { throw Failure() }
        XCTAssertNil(result)
    }

    func testTimeoutCancelsSuspendingHandler() async {
        let cancelled = expectation(description: "handler cancelled")
        let result: Int? = await PreparationDeadline.run(timeout: 0.025) {
            do { try await Task.sleep(nanoseconds: 10_000_000_000) }
            catch { cancelled.fulfill(); throw error }
            return 42
        }
        XCTAssertNil(result)
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testUncooperativeHandlerCannotDelayDeadline() async {
        let finished = expectation(description: "late completion")
        let start = Date()
        let result: Int? = await PreparationDeadline.run(timeout: 0.025) {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                    continuation.resume(returning: ())
                }
            }
            finished.fulfill()
            return 42
        }
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3)
        await fulfillment(of: [finished], timeout: 1)
    }

    func testParentCancellationReturnsNil() async {
        let started = expectation(description: "handler started")
        let task = Task {
            await PreparationDeadline.run(timeout: 10) {
                started.fulfill()
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return 42
            }
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
    }

    func testAlreadyCancelledTaskDoesNotPresent() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await PreparationDeadline.run(timeout: 1) { 42 }
        }
        let result = await task.value
        XCTAssertNil(result)
    }

    func testRevisionInvalidatesInFlightWorkEvenAfterSwitchingBack() {
        let revision = PresentationRevision()
        let before = revision.current
        revision.invalidate()
        revision.invalidate()
        XCTAssertNotEqual(before, revision.current)
    }

    func testPresentationGateRejectsInactiveLockedCancelledOrChangedUser() {
        let revision = PresentationRevision()
        let before = revision.current
        XCTAssertTrue(revision.canPresent(expected: before, active: true, locked: false, cancelled: false))
        XCTAssertFalse(revision.canPresent(expected: before, active: false, locked: false, cancelled: false))
        XCTAssertFalse(revision.canPresent(expected: before, active: true, locked: true, cancelled: false))
        XCTAssertFalse(revision.canPresent(expected: before, active: true, locked: false, cancelled: true))
        revision.invalidate()
        XCTAssertFalse(revision.canPresent(expected: before, active: true, locked: false, cancelled: false))
    }
}
