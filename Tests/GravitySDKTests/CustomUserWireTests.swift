import Foundation
import Testing
import UIKit
@testable import GravitySDK

/// Wire-level checks for the user set via `setUser`: content requests must carry
/// `custom`/`ses` like `/visit` and `/event` do, and stop carrying the previous
/// user after a switch. The SDK is a singleton, so the tests run one by one.
@Suite(.serialized)
struct CustomUserWireTests {
    private let pageContext = PageContext(type: .other, data: [], location: "/custom-user")

    // Same key as Prefs
    private static let userIdKey = "gravity_user_id"

    private func withServer(_ body: (RecordingServer) async throws -> Void) async throws {
        // The anonymous test persists a server uid; put back whatever was there
        let savedUserId = UserDefaults.standard.string(forKey: Self.userIdKey)
        defer { UserDefaults.standard.set(savedUserId, forKey: Self.userIdKey) }
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        if !GravitySDK.isInitialized {
            GravitySDK.initialize(apiKey: "custom-user-key", section: "custom-user-section")
        }
        GravitySDK.instance.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        defer {
            GravitySDK.instance.setOptions(options: nil, contentSettings: nil, proxyUrl: nil)
            GravitySDK.instance.user = nil
        }
        try await body(server)
    }

    private func user(_ request: RecordingServer.Request) -> [String: String] {
        (request.body["user"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
    }

    private func chooseRequests(_ server: RecordingServer) -> [RecordingServer.Request] {
        server.recorded.filter { $0.path.hasSuffix("/choose") }
    }

    private func getContentAllWays() async {
        _ = await GravitySDK.instance.getContentBySelector(selector: "sel", pageContext: pageContext)
        _ = await GravitySDK.instance.getContentByCampaignId("101", pageContext)
        _ = await GravitySDK.instance.getContentByGroupSelector(groupSelector: "grp", pageContext: pageContext)
    }

    @Test func allThreeChooseVariantsCarryTheCustomUser() async throws {
        try await withServer { server in
            GravitySDK.instance.setUser(userId: "user-A", sessionId: "session-A")

            await getContentAllWays()

            let requests = chooseRequests(server)
            #expect(requests.count == 3)
            for request in requests {
                #expect(user(request)["custom"] == "user-A")
                #expect(user(request)["ses"] == "session-A")
            }
        }
    }

    @Test func switchingUserReplacesCustomAndSession() async throws {
        try await withServer { server in
            GravitySDK.instance.setUser(userId: "user-A", sessionId: "session-A")
            await getContentAllWays()
            server.reset()

            GravitySDK.instance.setUser(userId: "user-B", sessionId: "session-B")
            await getContentAllWays()

            let requests = chooseRequests(server)
            #expect(requests.count == 3)
            for request in requests {
                #expect(user(request)["custom"] == "user-B")
                #expect(user(request)["ses"] == "session-B")
            }
        }
    }

    @Test func chooseAnswerDoesNotOverwriteTheAnonymousSession() async throws {
        try await withServer { server in
            // Anonymous: the server assigns the session, the SDK keeps it
            server.reset(responseUser: ["uid": "anon-uid", "ses": "anon-ses"])
            _ = await GravitySDK.instance.getContentBySelector(selector: "anon-1", pageContext: pageContext)
            let first = try #require(chooseRequests(server).first)
            #expect(chooseRequests(server).count == 1)
            #expect(user(first)["custom"] == nil)
            _ = await GravitySDK.instance.getContentBySelector(selector: "anon-2", pageContext: pageContext)
            let anonymous = try #require(chooseRequests(server).last)
            #expect(user(anonymous)["uid"] == "anon-uid")
            #expect(user(anonymous)["ses"] == "anon-ses")
            #expect(user(anonymous)["custom"] == nil)

            // With a custom user the server's answer must not replace anything
            server.reset(responseUser: ["uid": "other-uid", "ses": "other-ses"])
            GravitySDK.instance.setUser(userId: "user-A", sessionId: "session-A")
            await getContentAllWays()
            _ = await GravitySDK.instance.getContentBySelector(selector: "after", pageContext: pageContext)
            #expect(chooseRequests(server).count == 4)
            #expect(GravitySDK.instance.user?.custom == "user-A")
            #expect(GravitySDK.instance.user?.ses == "session-A")
            for request in chooseRequests(server) {
                #expect(user(request)["custom"] == "user-A")
                #expect(user(request)["ses"] == "session-A")
            }

            // Back to anonymous: the earlier session is still the one in use
            server.reset()
            GravitySDK.instance.user = nil
            _ = await GravitySDK.instance.getContentBySelector(selector: "anon-3", pageContext: pageContext)
            let back = try #require(chooseRequests(server).last)
            #expect(user(back)["uid"] == "anon-uid")
            #expect(user(back)["ses"] == "anon-ses")
            #expect(user(back)["custom"] == nil)
        }
    }

    @Test func trackViewSendsTheSameUserToVisitAndChoose() async throws {
        try await withServer { server in
            server.reset(campaigns: [["campaignId": "101", "trigger": "view", "priority": 1]])
            GravitySDK.instance.setUser(userId: "user-A", sessionId: "session-A")

            let viewController = await UIViewController()
            GravitySDK.instance.trackView(pageContext: pageContext, viewController: viewController)

            let requests = await server.waitFor(2).filter { $0.path.hasSuffix("/visit") || $0.path.hasSuffix("/choose") }
            #expect(requests.map { URL(string: $0.path)?.lastPathComponent ?? $0.path } == ["visit", "choose"])
            for request in requests {
                #expect(user(request)["custom"] == "user-A")
                #expect(user(request)["ses"] == "session-A")
            }
        }
    }

    @Test func triggerEventSendsTheSameUserToEventAndChoose() async throws {
        try await withServer { server in
            server.reset(campaigns: [["campaignId": "101", "trigger": "event", "priority": 1]])
            GravitySDK.instance.setUser(userId: "user-A", sessionId: "session-A")

            let viewController = await UIViewController()
            GravitySDK.instance.triggerEvent(
                events: [CustomEvent(type: "x", name: "X")],
                pageContext: pageContext,
                viewController: viewController
            )

            let requests = await server.waitFor(2).filter { $0.path.hasSuffix("/event") || $0.path.hasSuffix("/choose") }
            #expect(requests.map { URL(string: $0.path)?.lastPathComponent ?? $0.path } == ["event", "choose"])
            for request in requests {
                #expect(user(request)["custom"] == "user-A")
                #expect(user(request)["ses"] == "session-A")
            }
        }
    }
}
