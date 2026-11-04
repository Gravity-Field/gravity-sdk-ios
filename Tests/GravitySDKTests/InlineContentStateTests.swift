import Foundation
import Testing
@testable import GravitySDK

private final class InlineMemoryStorage: UserIdStorage {
    private var uid: String?
    func getUserId() -> String? { uid }
    func setUserId(_ uid: String) throws { self.uid = uid }
    func removeUserId() throws { uid = nil }
}

@MainActor struct InlineContentStateTests {
    @Test func nilResponseIsCompletedUntilExplicitClear() throws {
        let sessions = SessionManager(storage: InlineMemoryStorage())
        let state = InlineContentState<String>(sessions: sessions)
        state.appear()
        let load = try #require(state.begin())
        #expect(!state.complete(load, value: nil, height: 0))
        #expect(!state.isLoading)
        state.disappear()
        state.appear()
        #expect(state.begin() == nil)
        // Completed placements, including empty ones, do not subscribe to identity changes.
        sessions.invalidate()
        #expect(state.begin() == nil)
        state.clear()
        #expect(state.begin() != nil)
    }

    @Test func newPageContextRetriesEmptyResponseButKeepsRenderedContent() throws {
        let state = InlineContentState<String>(sessions: SessionManager(storage: InlineMemoryStorage()))
        state.appear()
        let empty = try #require(state.begin())
        state.complete(empty, value: nil, height: 0)
        state.pageContextChanged()
        let retry = try #require(state.begin())
        state.complete(retry, value: "rendered", height: 80)
        state.pageContextChanged()
        #expect(state.begin() == nil)
        #expect(state.value == "rendered")
    }

    @Test(arguments: [true, false], [true, false])
    func changedContextDuringLoadWaitsThenRetries(succeeded: Bool, mounted: Bool) throws {
        let state = InlineContentState<String>(sessions: SessionManager(storage: InlineMemoryStorage()))
        state.appear()
        let old = try #require(state.begin())
        state.pageContextChanged()
        #expect(state.begin() == nil)
        if !mounted { state.disappear() }
        #expect(state.complete(old, value: succeeded ? "old-context" : nil, height: 80) == mounted)
        #expect(state.value == nil)
        if !mounted { #expect(state.begin() == nil); state.appear() }
        let current = try #require(state.begin())
        #expect(!state.complete(current, value: "new-context", height: 100))
        #expect(state.value == "new-context")
        #expect(state.begin() == nil)
    }

    @Test func currentResponseIsRetainedWhileOffscreen() throws {
        let sessions = SessionManager(storage: InlineMemoryStorage())
        let state = InlineContentState<String>(sessions: sessions)
        state.appear()
        let load = try #require(state.begin())
        state.disappear()
        #expect(!state.complete(load, value: "current-user", height: 120))
        #expect(state.value == "current-user")
        #expect(state.height == 120)
        #expect(!state.isLoading)
        state.appear()
        #expect(state.begin() == nil)
    }

    @Test func remountKeepsTheInFlightCurrentRequest() throws {
        let sessions = SessionManager(storage: InlineMemoryStorage())
        let state = InlineContentState<String>(sessions: sessions)
        state.appear()
        let load = try #require(state.begin())
        state.disappear()
        state.appear()
        #expect(state.begin() == nil)
        #expect(!state.complete(load, value: "current-user", height: 120))
        #expect(state.value == "current-user")
    }

    @Test(arguments: [true, false])
    func staleOffscreenResponseWaitsForMountBeforeRetry(succeeded: Bool) throws {
        let sessions = SessionManager(storage: InlineMemoryStorage())
        let state = InlineContentState<String>(sessions: sessions)
        state.appear()
        let load = try #require(state.begin())
        state.disappear()
        sessions.invalidate()
        #expect(!state.complete(load, value: succeeded ? "previous-user" : nil, height: 120))
        #expect(state.value == nil)
        #expect(state.height == nil)
        #expect(state.begin() == nil)
        state.appear()
        let current = try #require(state.begin())
        #expect(!state.complete(current, value: "current-user", height: 80))
        #expect(state.value == "current-user")
    }

    @Test func unmountedLoadCannotRetryOrReplaceARemountedLoad() throws {
        let sessions = SessionManager(storage: InlineMemoryStorage())
        let state = InlineContentState<String>(sessions: sessions)
        #expect(state.begin() == nil)
        state.appear()
        let old = try #require(state.begin())
        state.disappear()
        sessions.invalidate()
        #expect(state.begin() == nil)
        state.appear()
        let current = try #require(state.begin())
        #expect(!state.complete(old, value: "previous-user", height: 120))
        #expect(state.value == nil)
        #expect(state.isLoading)
        #expect(!state.complete(current, value: "current-user", height: 80))
        #expect(state.value == "current-user")
    }

    @Test(arguments: [true, false])
    func identityChangeBeforeUiCommitKeepsLoadingForCurrentUser(succeeded: Bool) throws {
        let sessions = SessionManager(storage: InlineMemoryStorage())
        let state = InlineContentState<String>(sessions: sessions)
        state.appear()
        let load = try #require(state.begin())
        sessions.invalidate()
        #expect(state.complete(load, value: succeeded ? "previous-user" : nil, height: succeeded ? 120 : 0))
        #expect(state.value == nil)
        #expect(state.isLoading)
        #expect(state.height == nil)
        // A repeated completion must not launch a second replacement request.
        #expect(!state.complete(load, value: "previous-user", height: 120))
        let current = try #require(state.begin())
        #expect(!state.complete(current, value: "current-user", height: 80))
        #expect(state.value == "current-user")
        #expect(state.height == 80)
        #expect(!state.isLoading)
    }

    @Test func alreadyRenderedContentStaysUntilNormalReload() async throws {
        let sessions = SessionManager(storage: InlineMemoryStorage())
        let state = InlineContentState<String>(sessions: sessions)
        state.appear()
        let load = try #require(state.begin())
        state.complete(load, value: "previous-user", height: 120)
        #expect(state.value == "previous-user")
        try sessions.restoreUserId("new")
        await drainMainQueue()
        #expect(state.value == "previous-user")
        #expect(!state.isLoading)
        #expect(state.height == 120)
        #expect(state.begin() == nil)
        state.clear()
        let current = try #require(state.begin())
        state.complete(current, value: "current-user", height: 80)
        #expect(state.value == "current-user")
    }

    @Test func delayedInvalidationCannotEraseARequestStartedForTheNewIdentity() async throws {
        let sessions = SessionManager(storage: InlineMemoryStorage())
        let state = InlineContentState<String>(sessions: sessions)
        state.appear()
        sessions.invalidate()
        let current = try #require(state.begin())
        state.complete(current, value: "current-user", height: 80)
        await drainMainQueue()
        #expect(state.value == "current-user")
        #expect(state.height == 80)
        #expect(!state.isLoading)
    }

    @Test func supersededLoadCannotRepopulateAnEmptyPlacement() throws {
        let sessions = SessionManager(storage: InlineMemoryStorage())
        let state = InlineContentState<String>(sessions: sessions)
        state.appear()
        let old = try #require(state.begin())
        state.clear()
        state.complete(old, value: "previous-user", height: 120)
        #expect(state.value == nil)
        #expect(!state.isLoading)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
