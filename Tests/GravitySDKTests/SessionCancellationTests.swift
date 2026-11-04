import XCTest
@testable import GravitySDK

private final class CancellationStorage: UserIdStorage {
    func getUserId() -> String? { "stored" }
    func setUserId(_ uid: String) throws {}
    func removeUserId() throws {}
}

final class SessionCancellationTests: XCTestCase {
    func testCancelledWaitersFinishBeforeInitializer() async throws {
        let state = SessionManager(storage: CancellationStorage())
        let owner = try await state.beginRequest(customUser: nil, generation: state.generation)
        let getterDone = expectation(description: "Cancelled getter released")
        let requestDone = expectation(description: "Cancelled request released")
        let getter = Task {
            let value = await state.getUserId()
            XCTAssertNil(value)
            getterDone.fulfill()
        }
        let request = Task {
            do {
                _ = try await state.beginRequest(customUser: nil, generation: state.generation)
                XCTFail("Cancelled request must not start")
            } catch { XCTAssertTrue(error is CancellationError) }
            requestDone.fulfill()
        }
        getter.cancel()
        request.cancel()
        await fulfillment(of: [getterDone, requestDone], timeout: 1)
        state.finish(owner)
        await getter.value
        await request.value
    }
}
