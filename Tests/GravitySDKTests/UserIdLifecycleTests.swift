import Foundation
import Testing
import UIKit
import SwiftUI
@testable import GravitySDK

extension SDKSingletonTests {
    struct UserIdLifecycleTests {
        private let page = PageContext(type: .other, data: [], location: "/identity")

        private func withServer(callback: GravityEventCallback? = nil,
                                _ body: (GravitySDK, RecordingServer) async throws -> Void) async throws {
            let stored = UserDefaults.standard.string(forKey: "gravity_user_id")
            defer { UserDefaults.standard.set(stored, forKey: "gravity_user_id") }
            let fixture = TemporarySDKFixture(apiKey: "identity-key", section: "identity")
            let sdk = fixture.initialize(callback: callback)
            sdk.setUserIdListener(nil)
            try await sdk.resetUser()
            let server = try RecordingServer()
            try await server.start()
            defer { server.stop(); sdk.setUserIdListener(nil) }
            sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
            try await body(sdk, server)
            try await sdk.resetUser()
        }

        private func user(_ request: RecordingServer.Request) -> [String: String] {
            request.body["user"] as? [String: String] ?? [:]
        }

        @MainActor private func inlineHost(_ placement: String, loader: AnyView) -> UIViewController {
            switch placement {
            case "swiftUI":
                return UIHostingController(rootView: GravityInlineSwiftUIView(selector: "inline", pageContext: page) { loader })
            case "view":
                let view = GravityInlineView(selector: "inline")
                view.initialize(pageContext: page) { loader }
                let host = UIViewController()
                host.view = view
                return host
            default:
                let view = GravityInlineListView(groupSelector: "inline")
                view.initialize(pageContext: page) { loader }
                let host = UIViewController()
                host.view = view
                return host
            }
        }

        @Test @MainActor
        func listenerRegisteredBeforeInstallationSurvivesRepeatedInitialize() async throws {
            let stored = UserDefaults.standard.string(forKey: "gravity_user_id")
            let fixture = TemporarySDKFixture(apiKey: "listener-lifecycle", section: "listener")
            // Use an uninstalled instance, like the pre-initialize singleton placeholder.
            // This exercises pre-initialize registration without depending on test order.
            let placeholder = GravitySDK(apiKey: "", section: "", gravityEventCallback: nil,
                productViewBuilder: nil, productFilter: nil, uiSettings: nil,
                visibleImpressionStore: VisibleImpressionStore(fileURL: fixture.root.appendingPathComponent("placeholder.json")))
            placeholder.setUserIdListener(nil)
            try await placeholder.resetUser()
            defer {
                GravitySDK.instance.setUserIdListener(nil)
                UserDefaults.standard.set(stored, forKey: "gravity_user_id")
            }
            var first: [String?] = []
            var replacement: [String?] = []
            placeholder.setUserIdListener { uid in
                #expect(Thread.isMainThread)
                first.append(uid)
            }
            #expect(GravitySDK.instance !== placeholder)
            let installed = fixture.initialize()
            #expect(installed !== placeholder)
            try await installed.restoreUserId("first-install")
            await drainMainQueue()
            #expect(first == ["first-install"])
            let reinitialized = fixture.initialize()
            try await reinitialized.resetUser()
            await drainMainQueue()
            #expect(first == ["first-install", nil])

            reinitialized.setUserIdListener { uid in
                #expect(Thread.isMainThread)
                replacement.append(uid)
            }
            let third = fixture.initialize()
            try await third.restoreUserId("third-install")
            await drainMainQueue()
            #expect(replacement == ["third-install"])
            let fourth = fixture.initialize()
            try await fourth.resetUser()
            await drainMainQueue()
            #expect(replacement == ["third-install", nil])
            #expect(first == ["first-install", nil])
            fourth.setUserIdListener(nil)
            try await fourth.restoreUserId("unsubscribed")
            await drainMainQueue()
            #expect(replacement == ["third-install", nil])
            try await fourth.resetUser()
        }

        @Test(arguments: ["swiftUI", "view", "list"], [true, false])
        @MainActor func contextChangedDuringRequestRetriesWithNewestContext(placement: String, failed: Bool) async throws {
            try await withServer { sdk, server in
                sdk.setUser(userId: "current", sessionId: "session")
                server.holdNextResponse(statusCode: failed ? 500 : 200)
                let loader = AnyView(Text("Loading"))
                let host = inlineHost(placement, loader: loader)
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                #expect(await server.waitFor(1).count == 1)
                let updated = PageContext(type: .other, data: [], location: "/newest-context")
                if let view = host.view as? GravityInlineView { view.initialize(pageContext: updated) }
                else if let view = host.view as? GravityInlineListView { view.initialize(pageContext: updated) }
                else if let swiftUI = host as? UIHostingController<GravityInlineSwiftUIView> {
                    swiftUI.rootView = GravityInlineSwiftUIView(selector: "inline", pageContext: updated) { loader }
                }
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                await drainMainQueue()
                #expect(server.recorded.count == 1)
                server.releaseHeldResponses()
                let requests = await server.waitFor(2)
                #expect(requests.count == 2)
                #expect((requests.last?.body["ctx"] as? [String: Any])?["location"] as? String == "/newest-context")
            }
        }

        @Test(arguments: ["swiftUI", "view", "list"], [true, false])
        @MainActor func newPageContextRetriesEmptyOrFailedInlineResponse(placement: String, failed: Bool) async throws {
            try await withServer { sdk, server in
                sdk.setUser(userId: "current", sessionId: "session")
                server.holdNextResponse(statusCode: failed ? 500 : 200)
                var completed = false
                let loader = AnyView(Text("Loading").onDisappear { completed = true })
                let host = inlineHost(placement, loader: loader)
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                #expect(await server.waitFor(1).count == 1)
                server.releaseHeldResponses()
                let deadline = Date().addingTimeInterval(2)
                while !completed, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
                #expect(completed)
                server.reset()
                let updated = PageContext(type: .other, data: [], location: "/updated-context")
                if let view = host.view as? GravityInlineView { view.initialize(pageContext: updated) }
                else if let view = host.view as? GravityInlineListView { view.initialize(pageContext: updated) }
                else if let swiftUI = host as? UIHostingController<GravityInlineSwiftUIView> {
                    swiftUI.rootView = GravityInlineSwiftUIView(selector: "inline", pageContext: updated) { loader }
                }
                let requests = await server.waitFor(1)
                #expect(requests.count == 1)
                #expect((requests.first?.body["ctx"] as? [String: Any])?["location"] as? String == "/updated-context")
            }
        }

        @Test(arguments: ["swiftUI", "view", "list"], [true, false])
        @MainActor func navigationKeepsCurrentInlineLoad(placement: String, completesWhileHidden: Bool) async throws {
            var loaded = 0
            try await withServer(callback: { if $0 is ContentLoadEvent { loaded += 1 } }) { sdk, server in
                sdk.setUser(userId: "current", sessionId: "current-session")
                server.reset(content: [["payload": [[
                    "campaignId": "inline", "experienceId": "e", "variationId": "v", "decisionId": "d",
                    "contents": [["contentId": "inline-content", "deliveryMethod": "inline", "contentType": "test",
                        "variables": ["frameUI": ["container": ["style": ["size": ["height": 120]]]],
                                      "elements": [["type": "text", "text": "Current inline"]]],
                        "events": [["type": "visible_impression", "urls": [server.url + "/impression"]]]]]
                ]]]])
                server.holdNextResponse()
                let host = inlineHost(placement, loader: AnyView(Text("Loading")))
                let navigation = UINavigationController(rootViewController: host)
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = navigation
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                #expect(await server.waitFor(1).count == 1)
                navigation.pushViewController(UIViewController(), animated: false)
                let pushDeadline = Date().addingTimeInterval(2)
                while host.view.window != nil, Date() < pushDeadline {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                #expect(host.view.window == nil)
                if completesWhileHidden {
                    server.releaseHeldResponses()
                    let loadDeadline = Date().addingTimeInterval(2)
                    while loaded == 0, Date() < loadDeadline {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                    #expect(loaded == 1)
                    await drainMainQueue()
                }
                navigation.popViewController(animated: false)
                let popDeadline = Date().addingTimeInterval(2)
                while host.view.window == nil, Date() < popDeadline {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                #expect(host.view.window != nil)
                if !completesWhileHidden { server.releaseHeldResponses() }
                let retryDeadline = Date().addingTimeInterval(0.5)
                while Date() < retryDeadline {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                #expect(server.recorded.filter { $0.path.hasSuffix("/choose") }.count == 1)
                #expect(loaded == 1)
                if let hosting = host as? UIHostingController<GravityInlineSwiftUIView> {
                    let insets = host.view.safeAreaInsets
                    #expect(hosting.sizeThatFits(in: CGSize(width: 320, height: 1000)).height == 120 + insets.top + insets.bottom)
                } else {
                    #expect(host.view.intrinsicContentSize.height == 120)
                }
            }
        }

        @Test(arguments: ["swiftUI", "view", "list"])
        @MainActor func navigationKeepsEmptyOrFailedInlineLoad(placement: String) async throws {
            for statusCode in [200, 500] {
                try await withServer { sdk, server in
                    sdk.setUser(userId: "current", sessionId: "current-session")
                    server.holdNextResponse(statusCode: statusCode)
                    var loaderStarts = 0
                    let loader = AnyView(Text("Loading").onAppear { loaderStarts += 1 })
                    let host = inlineHost(placement, loader: loader)
                    let navigation = UINavigationController(rootViewController: host)
                    let window = UIWindow(frame: UIScreen.main.bounds)
                    window.rootViewController = navigation
                    window.makeKeyAndVisible()
                    defer { window.isHidden = true; window.rootViewController = nil }
                    #expect(await server.waitFor(1).count == 1)
                    navigation.pushViewController(UIViewController(), animated: false)
                    let pushDeadline = Date().addingTimeInterval(2)
                    while host.view.window != nil, Date() < pushDeadline {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                    #expect(host.view.window == nil)
                    server.releaseHeldResponses()
                    // Observe a quiet interval for the empty/error response to finish offscreen.
                    #expect(await server.waitFor(2, timeout: 0.3).count == 1)
                    navigation.popViewController(animated: false)
                    let popDeadline = Date().addingTimeInterval(2)
                    while host.view.window == nil, Date() < popDeadline {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                    #expect(host.view.window != nil)
                    #expect(await server.waitFor(2, timeout: 0.5).count == 1, "placement=\(placement), status=\(statusCode)")
                    #expect(loaderStarts == 1, "placement=\(placement), status=\(statusCode)")
                }
            }
        }

        @Test(arguments: ["swiftUI", "view", "list"])
        @MainActor func removedInlineDoesNotReloadUntilItReappears(placement: String) async throws {
            try await withServer { sdk, server in
                sdk.setUser(userId: "previous", sessionId: "previous-session")
                server.holdNextResponse()
                var loaderVisible = false
                let loader = AnyView(Text("Loading")
                    .onAppear { loaderVisible = true }
                    .onDisappear { loaderVisible = false })
                let host = inlineHost(placement, loader: loader)
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                #expect(await server.waitFor(1).count == 1)
                #expect(loaderVisible)
                host.beginAppearanceTransition(false, animated: false)
                window.isHidden = true
                window.rootViewController = nil
                host.view.removeFromSuperview()
                host.endAppearanceTransition()
                #expect(host.view.window == nil)
                try await sdk.resetUser()
                server.releaseHeldResponses()
                #expect(await server.waitFor(2, timeout: 1).count == 1)
                #expect(await sdk.getUserId() == nil)

                // The same host must load again even if its page context has not changed.
                host.beginAppearanceTransition(true, animated: false)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.endAppearanceTransition()
                let requests = await server.waitFor(2, timeout: 2)
                #expect(requests.count == 2)
                #expect(user(try #require(requests.last)).isEmpty)
                #expect(await sdk.getUserId() == "server-uid")
                let completeDeadline = Date().addingTimeInterval(2)
                while loaderVisible, Date() < completeDeadline {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                #expect(!loaderVisible)
            }
        }

        @Test(arguments: ["swiftUI", "view", "list"], ["setUser", "reset", "restore", "resetAfterError"])
        @MainActor func inlineReloadsForCurrentIdentity(placement: String, change: String) async throws {
            try await withServer { sdk, server in
                sdk.setUser(userId: "previous", sessionId: "previous-session")
                server.holdNextResponse(statusCode: change == "resetAfterError" ? 500 : 200)
                var finishedLoading = false
                let loader = Text("Loading").onDisappear { finishedLoading = true }
                let host = inlineHost(placement, loader: AnyView(loader))
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                #expect(await server.waitFor(1).count == 1)
                switch change {
                case "setUser": sdk.setUser(userId: "current", sessionId: "current-session")
                case "reset", "resetAfterError": try await sdk.resetUser()
                default: try await sdk.restoreUserId("restored")
                }
                server.releaseHeldResponses()
                let requests = await server.waitFor(2, timeout: 2)
                #expect(requests.count == 2)
                guard requests.count == 2 else { return }
                #expect(user(requests[0])["custom"] == "previous")
                switch change {
                case "setUser": #expect(user(requests[1]) == ["custom": "current", "ses": "current-session"])
                case "reset", "resetAfterError": #expect(user(requests[1]).isEmpty)
                default: #expect(user(requests[1]) == ["uid": "restored"])
                }
                // Wait for the current response to commit before disposing this placement.
                let deadline = Date().addingTimeInterval(2)
                while !finishedLoading, Date() < deadline {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                #expect(finishedLoading)
            }
        }

        @Test(arguments: ["visit", "event", "campaign", "selector", "group"])
        func cancelledReceivedResponseStillSavesServerIdentity(method: String) async throws {
            try await withServer { sdk, server in
                let previousLevel = GravityLogger.logLevel
                GravityLogger.configure(.debug)
                sdk.setLogListener { _, message in
                    if message.hasPrefix("[HTTP] RESPONSE: 200") {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
                defer {
                    sdk.setLogListener(nil)
                    GravityLogger.configure(previousLevel)
                }
                let cancelled = await Task {
                    let repository = GravityRepository.instance
                    let returnedNothing: Bool
                    switch method {
                    case "visit":
                        returnedNothing = await repository.visit(pageContext: page, options: Options(), customerUser: nil) == nil
                    case "event":
                        returnedNothing = await repository.event(events: [], raisedAt: Date(), pageContext: page,
                            options: Options(), customerUser: nil) == nil
                    case "campaign":
                        returnedNothing = await repository.chooseByCampaignIdWithDetails(campaignId: "campaign",
                            options: Options(), contentSettings: ContentSettings(), pageContext: page) == nil
                    case "selector":
                        returnedNothing = await repository.chooseBySelectorWithDetails(selector: "selector",
                            options: Options(), contentSettings: ContentSettings(), pageContext: page) == nil
                    default:
                        returnedNothing = await repository.chooseByGroup(group: "group", options: Options(),
                            contentSettings: ContentSettings(), pageContext: page) == nil
                    }
                    #expect(Task.isCancelled)
                    return returnedNothing
                }.value
                #expect(cancelled)
                #expect(server.recorded.count == 1)
                #expect(await sdk.getUserId() == "server-uid")
                let cached = GravityRepository.instance.sessionManager.cachedUser(customUser: nil)
                #expect(cached.uid == "server-uid")
                #expect(cached.ses == "server-ses")
                #expect(UserDefaults.standard.string(forKey: "gravity_user_id") == "server-uid")
            }
        }

        @Test func parallelColdRequestsShareOneServerSession() async throws {
            try await withServer { sdk, server in
                await withTaskGroup(of: Void.self) { group in
                    for index in 0..<12 {
                        group.addTask { _ = await sdk.getContentBySelector(selector: "\(index)", pageContext: page) }
                    }
                }
                let users = server.recorded.map(user)
                #expect(users.count == 12)
                #expect(users.filter { $0["ses"] == nil }.count == 1)
                #expect(users.dropFirst().allSatisfy { $0["uid"] == "server-uid" && $0["ses"] == "server-ses" })
                #expect(await sdk.getUserId() == "server-uid")
            }
        }

        @Test func visitEventAndAllChooseVariantsShareInitialization() async throws {
            try await withServer { sdk, server in
                server.holdNextResponse()
                let first = Task { await sdk.getContentBySelector(selector: "first", pageContext: page) }
                #expect(await server.waitFor(1).count == 1)
                sdk.trackView(pageContext: page)
                sdk.triggerEvent(events: [CustomEvent(type: "test", name: "Test")], pageContext: page)
                let campaign = Task { await sdk.getContentByCampaignId("campaign", page) }
                let group = Task { await sdk.getContentByGroupSelector(groupSelector: "group", pageContext: page) }
                server.releaseHeldResponses()
                _ = await (first.value, campaign.value, group.value)
                let requests = await server.waitFor(5)
                #expect(requests.count == 5)
                #expect(requests.filter { user($0)["ses"] == nil }.count == 1)
                #expect(requests.dropFirst().allSatisfy { user($0)["ses"] == "server-ses" })
            }
        }

        @Test @MainActor func publicGetterListenerResetRestoreAndCustomUserAgree() async throws {
            try await withServer { sdk, server in
                var changes: [String?] = []
                sdk.setUserIdListener { changes.append($0) }
                #expect(await sdk.getUserId() == nil)
                _ = await sdk.getContentBySelector(selector: "one", pageContext: page)
                _ = await sdk.getContentByCampaignId("two", page)
                sdk.setUser(userId: "customer", sessionId: "customer-session")
                #expect(await sdk.getUserId() == "server-uid")
                try await sdk.resetUser()
                #expect(sdk.user == nil)
                #expect(await sdk.getUserId() == nil)
                _ = await sdk.getContentByGroupSelector(groupSelector: "anonymous", pageContext: page)
                let anonymous = try #require(server.recorded.last)
                #expect(user(anonymous).isEmpty)
                sdk.setUser(userId: "customer", sessionId: "customer-session")
                try await sdk.restoreUserId("recovered")
                #expect(sdk.user == nil)
                #expect(await sdk.getUserId() == "recovered")
                #expect(UserDefaults.standard.string(forKey: "gravity_user_id") == "recovered")
                server.reset(responseUser: ["uid": "recovered", "ses": "new-session"])
                _ = await sdk.getContentBySelector(selector: "restored", pageContext: page)
                let restored = try #require(server.recorded.first)
                #expect(user(restored) == ["uid": "recovered"])
                await drainMainQueue()
                #expect(changes == ["server-uid", nil, "server-uid", "recovered"])
                sdk.setUserIdListener(nil)
            }
        }

        @Test func restoreAndResetDuringRequestsDiscardOldIdentityAndContent() async throws {
            try await withServer { sdk, server in
                server.holdNextResponse()
                let old = Task { await sdk.getContentBySelectorWithDetails(selector: "old", pageContext: page) }
                #expect(await server.waitFor(1).count == 1)
                let getter = Task { await sdk.getUserId() }
                try await sdk.restoreUserId("restored")
                #expect(await getter.value == "restored")
                server.reset(responseUser: ["uid": "restored", "ses": "restored-session"])
                let fresh = await sdk.getContentBySelector(selector: "fresh", pageContext: page)
                #expect(fresh != nil)
                #expect(user(try #require(server.recorded.first)) == ["uid": "restored"])
                server.releaseHeldResponses()
                #expect(await old.value == nil)
                #expect(await sdk.getUserId() == "restored")
                server.holdNextResponse()
                let beforeReset = Task { await sdk.getContentByCampaignId("old", page) }
                #expect(await server.waitFor(2).count == 2)
                try await sdk.resetUser()
                server.releaseHeldResponses()
                #expect(await beforeReset.value == nil)
                #expect(await sdk.getUserId() == nil)
                #expect(UserDefaults.standard.string(forKey: "gravity_user_id") == nil)
            }
        }

        @Test func setUserDuringRequestRejectsOldResponseAndKeepsServerUidSeparate() async throws {
            try await withServer { sdk, server in
                try await sdk.restoreUserId("anonymous")
                sdk.setUser(userId: "customer-A", sessionId: "session-A")
                server.holdNextResponse()
                let old = Task { await sdk.getContentByGroupSelector(groupSelector: "old", pageContext: page) }
                #expect(await server.waitFor(1).count == 1)
                sdk.setUser(userId: "customer-B", sessionId: "session-B")
                server.releaseHeldResponses()
                #expect(await old.value == nil)
                #expect(await sdk.getUserId() == "anonymous")
                _ = await sdk.getContentByCampaignId("new", page)
                #expect(user(try #require(server.recorded.last)) == ["custom": "customer-B", "ses": "session-B"])
            }
        }

        @Test func lateAutomaticVisitCannotChooseForResetUser() async throws {
            try await withServer { sdk, server in
                server.reset(campaigns: [["campaignId": "old", "trigger": "view", "priority": 1]])
                server.holdNextResponse()
                let pending = try #require(sdk.trackViewTask(pageContext: page, viewController: await UIViewController()))
                #expect(await server.waitFor(1).count == 1)
                try await sdk.resetUser()
                server.releaseHeldResponses()
                await pending.value
                #expect(server.recorded.filter { $0.path.hasSuffix("/choose") }.isEmpty)
            }
        }

        @Test func emptyRestoreDoesNotClearTheExistingCustomUser() async throws {
            try await withServer { sdk, _ in
                sdk.setUser(userId: "customer", sessionId: "session")
                do {
                    try await sdk.restoreUserId(" \n")
                    Issue.record("Empty UID was accepted")
                } catch {
                    #expect(error as? GravityUserIdError == .invalidUserId)
                }
                #expect(sdk.user?.custom == "customer")
            }
        }

        @Test @MainActor func restoreTrimsUidForStorageGetterListenerAndNextRequest() async throws {
            try await withServer { sdk, server in
                var changes: [String?] = []
                sdk.setUserIdListener { changes.append($0) }
                sdk.setUser(userId: "custom", sessionId: "custom-session")
                try await sdk.restoreUserId(" \t\nrecovered\r ")
                #expect(sdk.user == nil)
                #expect(await sdk.getUserId() == "recovered")
                #expect(UserDefaults.standard.string(forKey: "gravity_user_id") == "recovered")
                await drainMainQueue()
                #expect(changes == ["recovered"])
                server.reset(responseUser: ["uid": "recovered", "ses": "restored-session"])
                _ = await sdk.getContentBySelector(selector: "trimmed", pageContext: page)
                #expect(user(try #require(server.recorded.first)) == ["uid": "recovered"])
                await drainMainQueue()
                #expect(changes == ["recovered"])
                sdk.setUserIdListener(nil)
            }
        }

        @Test func raisedCustomEventsAndVisitsAreSentAfterResetRestoreOrSetUser() async throws {
            try await withServer { sdk, server in
                let repository = GravityRepository.instance
                for change in 0..<3 {
                    sdk.setUser(userId: "raised-customer", sessionId: "raised-session")
                    let generation = repository.sessionManager.generation
                    let raised = sdk.user
                    if change == 0 { try await sdk.resetUser() }
                    else if change == 1 { try await sdk.restoreUserId("restored") }
                    else { sdk.setUser(userId: "next-customer", sessionId: "next-session") }
                    let before = server.recorded.count
                    let event = await repository.event(events: [CustomEvent(type: "logout", name: "Logout")],
                        raisedAt: Date(), pageContext: page, options: Options(), customerUser: raised,
                        identityGeneration: generation)
                    let visit = await repository.visit(pageContext: page, options: Options(),
                        customerUser: raised, identityGeneration: generation)
                    #expect(server.recorded.count == before + 2)
                    #expect(event == nil)
                    #expect(visit == nil)
                    for request in server.recorded.dropFirst(before) {
                        #expect(user(request) == ["custom": "raised-customer", "ses": "raised-session"])
                    }
                    #expect(await sdk.getUserId() != "server-uid")
                }
            }
        }

        @Test func eventWaitingForColdStartSurvivesSetUser() async throws {
            try await withServer { sdk, server in
                server.holdNextResponse()
                let first = Task { await sdk.getContentBySelector(selector: "cold", pageContext: page) }
                #expect(await server.waitFor(1).count == 1)
                let pending = try #require(await MainActor.run {
                    let pending = sdk.triggerEventTask(events: [CustomEvent(type: "login", name: "Login")], pageContext: page)
                    sdk.setUser(userId: "customer", sessionId: "custom-session")
                    return pending
                })
                server.releaseHeldResponses()
                #expect(await first.value == nil)
                await pending.value
                let requests = server.recorded
                let event = requests.first { $0.path.hasSuffix("/event") }
                #expect(event != nil)
                if let event { #expect(user(event) == ["uid": "server-uid", "ses": "server-ses"]) }
            }
        }

        @Test @MainActor func setUserDuringColdStartKeepsServerUidWithoutReturningOldContent() async throws {
            try await withServer { sdk, server in
                var changes: [String?] = []
                sdk.setUserIdListener { changes.append($0) }
                server.holdNextResponse()
                let first = Task { await sdk.getContentBySelector(selector: "cold", pageContext: page) }
                #expect(await server.waitFor(1).count == 1)
                sdk.setUser(userId: "customer", sessionId: "custom-session")
                server.releaseHeldResponses()
                #expect(await first.value == nil)
                #expect(await sdk.getUserId() == "server-uid")
                #expect(UserDefaults.standard.string(forKey: "gravity_user_id") == "server-uid")
                await drainMainQueue()
                #expect(changes == ["server-uid"])
                sdk.setUserIdListener(nil)
            }
        }

        @Test func reinitializeDuringColdStartKeepsServerUid() async throws {
            try await withServer { sdk, server in
                server.holdNextResponse()
                let first = Task { await sdk.getContentBySelector(selector: "cold", pageContext: page) }
                #expect(await server.waitFor(1).count == 1)
                GravitySDK.initialize(apiKey: "identity-key", section: "identity")
                server.releaseHeldResponses()
                #expect(await first.value == nil)
                #expect(await GravitySDK.instance.getUserId() == "server-uid")
            }
        }

        @Test func raisedAnonymousAnalyticsKeepTheirKnownUidAfterResetOrRestore() async throws {
            for restore in [false, true] {
                try await withServer { sdk, server in
                    try await sdk.restoreUserId("raised-uid")
                    server.holdNextResponse()
                    let first = Task { await sdk.getContentBySelector(selector: "cold", pageContext: page) }
                    #expect(await server.waitFor(1).count == 1)
                    let event = try #require(sdk.triggerEventTask(events: [CustomEvent(type: "logout", name: "Logout")], pageContext: page))
                    let visit = try #require(sdk.trackViewTask(pageContext: page))
                    if restore { try await sdk.restoreUserId("restored") }
                    else { try await sdk.resetUser() }
                    server.releaseHeldResponses()
                    #expect(await first.value == nil)
                    await event.value
                    await visit.value
                    let analytics = server.recorded.filter { !$0.path.hasSuffix("/choose") }
                    #expect(analytics.count == 2)
                    for request in analytics { #expect(user(request) == ["uid": "raised-uid"]) }
                    #expect(await sdk.getUserId() == (restore ? "restored" : nil))
                }
            }
        }

        @MainActor private func drainMainQueue() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}
