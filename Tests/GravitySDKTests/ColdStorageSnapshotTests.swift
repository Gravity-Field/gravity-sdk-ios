import XCTest
@testable import GravitySDK

private final class GatedIdentityStorage: UserIdStorage {
    let started: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    init(started: XCTestExpectation) { self.started = started }
    func getUserId() -> String? {
        started.fulfill()
        release.wait()
        return "original-uid"
    }
    func setUserId(_ uid: String) throws {}
    func removeUserId() throws {}
}

final class ColdStorageSnapshotTests: XCTestCase {
    func testTrackingStartedBeforeStorageReadKeepsOriginalUidAfterReset() async throws {
        let reading = expectation(description: "Cold storage read started")
        let disk = GatedIdentityStorage(started: reading)
        // This is the same synchronous construction/snapshot ordering used by
        // automaticRequest before visit/event is scheduled on its Task.
        let tracking = Task.detached {
            let state = SessionManager(storage: disk)
            return (state, state.snapshot(customUser: nil))
        }
        await fulfillment(of: [reading], timeout: 1)
        disk.release.signal()
        let (state, raised) = await tracking.value
        try state.resetUser()
        let request = try await state.beginRequest(customUser: nil, generation: raised.generation, raisedIdentity: raised)
        XCTAssertEqual(request.user.uid, "original-uid")
        XCTAssertNil(request.user.ses)
        let uid = await state.getUserId()
        XCTAssertNil(uid)
        state.finish(request)
    }
}
