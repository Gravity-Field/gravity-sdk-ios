import XCTest
import UIKit
@testable import GravitySDK

final class HeadlessCampaignWireTests: XCTestCase {
    private let page = PageContext(type: .other, data: [], location: "/headless")

    private func withServer(callback: GravityEventCallback? = nil, _ body: (GravitySDK, RecordingServer) async throws -> Void) async throws {
        let savedFetch = GravitySDK.instance.isFetchContentOnTrack
        let savedTimeout = GravitySDK.instance.staleContentTimeout
        defer {
            GravitySDK.instance.isFetchContentOnTrack = savedFetch
            GravitySDK.instance.staleContentTimeout = savedTimeout
        }
        let savedUID = UserDefaults.standard.string(forKey: "gravity_user_id")
        defer { UserDefaults.standard.set(savedUID, forKey: "gravity_user_id") }
        let fixture = TemporarySDKFixture(apiKey: "headless", section: "headless")
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        let sdk = fixture.initialize(callback: callback)
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        try await body(sdk, server)
    }

    private func expectNil(_ value: GravityDataResponse<ContentResponse>?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(value, file: file, line: line)
    }

    private func campaign(_ id: String, _ priority: Int? = nil) -> [String: Any] {
        var result: [String: Any] = ["campaignId": id]
        if let priority { result["priority"] = priority }
        return result
    }

    private func content(_ id: String, step: Int? = nil, method: String = "modal", trackingBase: String? = nil) -> [[String: Any]] {
        var content: [String: Any] = ["contentId": id, "contentType": "native", "deliveryMethod": method,
            "templateSystemName": "snackbar-1",
            "variables": ["title": "Own UI", "elements": [["type": "text", "text": "Own UI"]],
                "onLoad": ["action": "load"], "onImpression": ["action": "impression"],
                "onVisibleImpression": ["action": "visible_impression"]]]
        if let step { content["step"] = step }
        if let trackingBase {
            content["events"] = [["type": "load", "urls": [trackingBase + "/" + id + "/load"]],
                                 ["type": "impression", "urls": [trackingBase + "/impression"]],
                                 ["type": "visible_impression", "urls": [trackingBase + "/visible"]]]
        }
        return [["payload": [["campaignId": id, "experienceId": "e", "variationId": "v", "decisionId": "d", "contents": [content]]]]]
    }

    private func chosen(_ server: RecordingServer) -> [String] {
        server.recorded.filter { $0.path == "/choose" }.compactMap {
            ($0.body["data"] as? [[String: Any]])?.first?["campaignId"] as? String
        }
    }

    func testResetAndRestoreDiscardPendingTrackingAndChooseForBothAPIs() async throws {
        for event in [false, true] {
            for duringChoose in [false, true] {
                for restore in [false, true] {
                    let callbacks = HeadlessCallbackRecorder()
                    try await withServer(callback: { callbacks.record($0) }) { sdk, server in
                        try await sdk.restoreUserId("previous-user")
                        let ids = [campaign("c")]
                        let answer = content("c", trackingBase: server.url)
                        server.setResponseHandler { request in
                            let tracking = request.path == "/visit" || request.path == "/event"
                            return .init(json: tracking
                                ? ["campaigns": ids, "user": ["uid": "previous-user", "ses": "old-session"]]
                                : ["data": answer, "user": ["uid": "previous-user", "ses": "old-session"]],
                                delay: tracking == !duringChoose ? 0.15 : 0)
                        }
                        let pending = Task { try await fetch(sdk, event: event) }
                        _ = await server.waitFor(duringChoose ? 2 : 1)
                        if restore { try await sdk.restoreUserId("restored-user") }
                        else { try await sdk.resetUser() }
                        expectNil(try await pending.value)
                        let uid = await sdk.getUserId()
                        XCTAssertEqual(uid, restore ? "restored-user" : nil)
                        XCTAssertEqual(server.recorded.map(\.path),
                            duringChoose ? [event ? "/event" : "/visit", "/choose"] : [event ? "/event" : "/visit"])
                        XCTAssertTrue(callbacks.events.isEmpty)
                    }
                }
            }
        }
    }

    func testSlowLoadCallbackPreservesAcceptedContent() async throws {
        for event in [false, true] {
            let callbacks = HeadlessCallbackRecorder()
            let loaded = expectation(description: "Load callback completed")
            try await withServer(callback: { tracking in
                callbacks.record(tracking)
                if tracking is ContentLoadEvent {
                    Thread.sleep(forTimeInterval: 0.6)
                    loaded.fulfill()
                }
            }) { sdk, server in
                sdk.staleContentTimeout = 0.5
                server.reset(campaigns: [campaign("accepted")], content: content("accepted"))
                let result = try await fetch(sdk, event: event)
                XCTAssertNotNil(result, "Once content is accepted and load is emitted, return that content")
                await fulfillment(of: [loaded], timeout: 5)
                XCTAssertEqual(callbacks.events.count, 1)
                XCTAssertTrue(callbacks.events.first is ContentLoadEvent)
            }
        }
    }

    func testHostOptionsAreUnchangedForBothAPIs() async throws {
        for event in [false, true] {
            for implicit in [false, true] {
                try await withServer { sdk, server in
                    sdk.setOptions(options: Options(isReturnCounter: true, isImplicitImpression: implicit), contentSettings: nil, proxyUrl: server.url)
                    server.reset(campaigns: [campaign("c")], content: content("c"))
                    _ = try await fetch(sdk, event: event)
                    for request in server.recorded {
                        let options = request.body["options"] as? [String: Any]
                        XCTAssertEqual(options?["isImplicitImpression"] as? Bool, implicit)
                        XCTAssertEqual(options?["isReturnCounter"] as? Bool, true)
                    }
                }
            }
        }
    }

    func testChooseReadsCurrentOptionsAndContentSettingsForBothAPIs() async throws {
        for event in [false, true] {
            try await withServer { sdk, server in
                let trackingRelease = DispatchGroup()
                let firstChooseRelease = DispatchGroup()
                trackingRelease.enter()
                firstChooseRelease.enter()
                let ids = [campaign("empty", 2), campaign("winner", 1)]
                let answer = content("winner")
                server.setResponseHandler { request in
                    if request.path != "/choose" {
                        return .init(json: ["campaigns": ids], sendAfter: trackingRelease)
                    }
                    let id = (request.body["data"] as? [[String: Any]])?.first?["campaignId"] as? String
                    return .init(json: ["data": id == "winner" ? answer : []],
                                 sendAfter: id == "empty" ? firstChooseRelease : nil)
                }
                sdk.setOptions(options: Options(isReturnCounter: false, isImplicitImpression: true),
                    contentSettings: ContentSettings(skusOnly: false, fields: ["initial"]), proxyUrl: server.url)
                let pending = Task { try await fetch(sdk, event: event) }
                let tracking = await server.waitFor(1)
                XCTAssertEqual(tracking.count, 1)
                sdk.setOptions(options: Options(isReturnCounter: true, isImplicitImpression: false),
                    contentSettings: ContentSettings(skusOnly: true, fields: ["first"]), proxyUrl: server.url)
                trackingRelease.leave()
                let firstChoose = await server.waitFor(2)
                XCTAssertEqual(firstChoose.count, 2)
                sdk.setOptions(options: Options(isReturnCounter: false, isImplicitImpression: true),
                    contentSettings: ContentSettings(skusOnly: false, fields: ["second"]), proxyUrl: server.url)
                firstChooseRelease.leave()
                let result = try await pending.value
                XCTAssertEqual(result?.data.data.first?.payload.first?.contents.first?.contentId, "winner")
                let requests = server.recorded.filter { $0.path == "/choose" }
                XCTAssertEqual(requests.count, 2)
                for (index, request) in requests.enumerated() {
                    let options = request.body["options"] as? [String: Any]
                    let data = (request.body["data"] as? [[String: Any]])?.first
                    let settings = data?["option"] as? [String: Any]
                    XCTAssertEqual(options?["isReturnCounter"] as? Bool, index == 0)
                    XCTAssertEqual(options?["isImplicitImpression"] as? Bool, index != 0)
                    XCTAssertEqual(settings?["skusOnly"] as? Bool, index == 0)
                    XCTAssertEqual(settings?["fields"] as? [String], [index == 0 ? "first" : "second"])
                }
            }
        }
    }

    func testCurrentTimeoutIsReadBeforeAndAfterChoose() async throws {
        for event in [false, true] {
            for holdChoose in [false, true] {
                try await withServer { sdk, server in
                    let release = DispatchGroup()
                    release.enter()
                    let ids = [campaign("c")]
                    let answer = content("c")
                    sdk.staleContentTimeout = 10
                    server.setResponseHandler { request in
                        let choosing = request.path == "/choose"
                        return .init(json: choosing ? ["data": answer] : ["campaigns": ids],
                                     sendAfter: choosing == holdChoose ? release : nil)
                    }
                    let pending = Task { try await fetch(sdk, event: event) }
                    _ = await server.waitFor(holdChoose ? 2 : 1)
                    sdk.staleContentTimeout = 0
                    release.leave()
                    expectNil(try await pending.value)
                    XCTAssertEqual(chosen(server), holdChoose ? ["c"] : [])
                }
            }
        }
    }

    func testNoCampaignsReturnNilWithoutChooseForVisitAndEvent() async throws {
        try await withServer { sdk, server in
            let visit = try await sdk.trackViewNoShow(pageContext: page)
            let event = try await sdk.triggerEventNoShow(events: [CustomEvent(type: "tap", name: "Tap")], pageContext: page)
            XCTAssertNil(visit)
            XCTAssertNil(event)
            XCTAssertEqual(server.recorded.map(\.path), ["/visit", "/event"])
        }
    }

    func testPriorityFallbackSkipsEmptyMissingRootAndFailedChoose() async throws {
        try await withServer { sdk, server in
            let answer = content("winner")
            let stepOnly = content("step-only", step: 0)
            let ids = [campaign("low", -1), campaign("winner"), campaign("empty", 20), campaign("error", 10), campaign("step-only", 5)]
            server.setResponseHandler { request in
                if request.path == "/visit" { return .init(json: ["campaigns": ids]) }
                let id = (request.body["data"] as? [[String: Any]])?.first?["campaignId"] as? String
                if id == "error" { return .init(json: [:], status: 500) }
                return .init(json: ["data": id == "step-only" ? stepOnly : id == "winner" ? answer : []])
            }
            let fetched = try await sdk.trackViewNoShow(pageContext: page)
            let result = try XCTUnwrap(fetched)
            XCTAssertEqual(chosen(server), ["empty", "error", "step-only", "winner"])
            XCTAssertEqual(result.data.data.first?.payload.first?.contents.first?.contentId, "winner")
            XCTAssertEqual(result.json["data"]?[0]?["payload"]?[0]?["contents"]?[0]?["variables"]?["title"]?.stringValue, "Own UI")
        }
    }

    func testEqualAndMissingPrioritiesKeepServerOrder() async throws {
        try await withServer { sdk, server in
            server.reset(campaigns: [campaign("first"), campaign("second", 0), campaign("third")])
            expectNil(try await sdk.trackViewNoShow(pageContext: page))
            XCTAssertEqual(chosen(server), ["first", "second", "third"])
        }
    }

    @MainActor func testEveryDeliveryMethodReturnsWithoutPresentationOrImpressions() async throws {
        for method in ["modal", "fullScreen", "bottomSheet", "snackbar", "inline"] {
            let callbacks = HeadlessCallbackRecorder()
            try await withServer(callback: { callbacks.record($0) }) { sdk, server in
                let host = UIViewController()
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                let baselineSubviews = host.view.subviews.count
                let answer = content("c", method: method, trackingBase: server.url)
                server.reset(campaigns: [campaign("c", 1)], content: answer)
                let result = try await sdk.triggerEventNoShow(events: [CustomEvent(type: "tap", name: "Tap")], pageContext: page)
                XCTAssertNotNil(result, method)
                _ = await server.waitFor(3)
                try await Task.sleep(nanoseconds: 50_000_000)
                XCTAssertNil(host.presentedViewController)
                XCTAssertTrue(host.children.isEmpty)
                XCTAssertEqual(host.view.subviews.count, baselineSubviews)
                XCTAssertEqual(callbacks.events.count, 1)
                XCTAssertTrue(callbacks.events.allSatisfy { $0 is ContentLoadEvent })
                XCTAssertEqual(server.recorded.map(\.path), ["/event", "/choose", "/c/load"])
                XCTAssertNotNil(sdk.presentationGate.reserve(campaignId: "c", request: sdk.presentationGate.beginRequest(location: "other", newScreen: true)))
                XCTAssertTrue(sdk.visibleImpressionDelivery.store?.entries.isEmpty ?? true)
            }
        }
    }

    @MainActor func testOnlyAcceptedResponseEmitsCallbackAndOnLoadOncePerContent() async throws {
        for event in [false, true] {
            let callbacks = HeadlessCallbackRecorder()
            try await withServer(callback: { callbacks.record($0) }) { sdk, server in
                let ids = [campaign("rejected", 2), campaign("accepted", 1)]
                let rejected = content("rejected", step: 1, trackingBase: server.url)
                var accepted = content("root", trackingBase: server.url)
                let stepPayload = content("step", step: 1, trackingBase: server.url)[0]["payload"] as! [[String: Any]]
                accepted[0]["payload"] = (accepted[0]["payload"] as! [[String: Any]]) + stepPayload
                accepted += content("extra", trackingBase: server.url)
                let answer = accepted
                server.setResponseHandler { request in
                    if request.path == "/visit" || request.path == "/event" { return .init(json: ["campaigns": ids]) }
                    let id = (request.body["data"] as? [[String: Any]])?.first?["campaignId"] as? String
                    return .init(json: ["data": id == "rejected" ? rejected : answer])
                }
                let result = try await fetch(sdk, event: event)
                XCTAssertNotNil(result)
                _ = await server.waitFor(6)
                try await Task.sleep(nanoseconds: 50_000_000)
                let events = callbacks.events
                XCTAssertEqual(events.count, 3)
                XCTAssertTrue(events.allSatisfy { $0 is ContentLoadEvent })
                XCTAssertEqual(Set(events.compactMap { ($0 as? ContentLoadEvent)?.content.contentId }), ["root", "step", "extra"])
                XCTAssertEqual(Set(events.compactMap { $0.campaign.payload.first?.campaignId }), ["root", "extra"])
                XCTAssertEqual(Array(server.recorded.map(\.path).prefix(3)), [event ? "/event" : "/visit", "/choose", "/choose"])
                XCTAssertEqual(server.recorded.map(\.path).filter { $0.hasSuffix("/load") }.sorted(),
                               ["/extra/load", "/root/load", "/step/load"])
                XCTAssertEqual(server.recorded.count, 6)
            }
        }
    }

    func testFailedChooseTriesNextCandidateForBothAPIs() async throws {
        for event in [false, true] {
            for failure in ["network", "http", "json", "decode"] {
                let callbacks = HeadlessCallbackRecorder()
                try await withServer(callback: { callbacks.record($0) }) { sdk, server in
                    let ids = [campaign("failed", 2), campaign("winner", 1)]
                    let answer = content("winner", trackingBase: server.url)
                    server.setResponseHandler { request in
                        if request.path == "/visit" || request.path == "/event" { return .init(json: ["campaigns": ids]) }
                        let id = (request.body["data"] as? [[String: Any]])?.first?["campaignId"] as? String
                        if id == "failed" { return self.failedChoose(failure) }
                        return .init(json: ["data": answer])
                    }
                    let result = try await fetch(sdk, event: event)
                    XCTAssertEqual(result?.data.data.first?.payload.first?.contents.first?.contentId, "winner", failure)
                    _ = await server.waitFor(4)
                    try await Task.sleep(nanoseconds: 50_000_000)
                    XCTAssertEqual(chosen(server), ["failed", "winner"], failure)
                    XCTAssertEqual(server.recorded.filter { $0.path.hasSuffix("/load") }.map(\.path), ["/winner/load"], failure)
                    XCTAssertEqual(callbacks.events.count, 1, failure)
                    XCTAssertTrue(callbacks.events.first is ContentLoadEvent, failure)
                }
            }
        }
    }

    func testAllFailedCandidatesReturnNilWithoutLoadEventsForBothAPIs() async throws {
        for event in [false, true] {
            let callbacks = HeadlessCallbackRecorder()
            try await withServer(callback: { callbacks.record($0) }) { sdk, server in
                let ids = [campaign("network", 4), campaign("http", 3), campaign("json", 2), campaign("decode", 1)]
                server.setResponseHandler { request in
                    if request.path == "/visit" || request.path == "/event" { return .init(json: ["campaigns": ids]) }
                    let id = (request.body["data"] as? [[String: Any]])?.first?["campaignId"] as? String ?? "http"
                    return self.failedChoose(id)
                }
                expectNil(try await fetch(sdk, event: event))
                XCTAssertEqual(chosen(server), ["network", "http", "json", "decode"])
                XCTAssertTrue(callbacks.events.isEmpty)
                XCTAssertTrue(server.recorded.allSatisfy { ["/visit", "/event", "/choose"].contains($0.path) })
            }
        }
    }

    private func failedChoose(_ failure: String) -> RecordingServer.Response {
        switch failure {
        case "network": return .init(json: [:], disconnect: true)
        case "json": return .init(json: [:], rawBody: Data("{broken".utf8))
        case "decode": return .init(json: ["data": "invalid-content"])
        default: return .init(json: [:], status: 503)
        }
    }

    func testCancellationDuringChoosePropagatesWithoutFallbackOrLoadEventsForBothAPIs() async throws {
        for event in [false, true] {
            let callbacks = HeadlessCallbackRecorder()
            try await withServer(callback: { callbacks.record($0) }) { sdk, server in
                let ids = [campaign("first", 2), campaign("second", 1)]
                let answer = content("first", trackingBase: server.url)
                server.setResponseHandler { request in
                    if request.path == "/visit" || request.path == "/event" { return .init(json: ["campaigns": ids]) }
                    return .init(json: ["data": answer], delay: 0.2)
                }
                let task = Task { try await self.fetch(sdk, event: event) }
                let requests = await server.waitFor(2)
                XCTAssertEqual(requests.count, 2)
                task.cancel()
                do { _ = try await task.value; XCTFail("Expected cancellation") }
                catch is CancellationError { }
                try await Task.sleep(nanoseconds: 50_000_000)
                XCTAssertEqual(chosen(server), ["first"])
                XCTAssertTrue(callbacks.events.isEmpty)
                XCTAssertEqual(server.recorded.count, 2)
            }
        }
    }

    func testMalformedChooseFallsBack() async throws {
        try await withServer { sdk, server in
            let ids = [campaign("malformed", 2), campaign("winner", 1)]
            let answer = content("winner")
            server.setResponseHandler { request in
                if request.path == "/visit" { return .init(json: ["campaigns": ids]) }
                let id = (request.body["data"] as? [[String: Any]])?.first?["campaignId"] as? String
                return id == "malformed" ? .init(json: [:], rawBody: Data("{broken".utf8)) : .init(json: ["data": answer])
            }
            let result = try await sdk.trackViewNoShow(pageContext: page)
            XCTAssertNotNil(result)
            XCTAssertEqual(chosen(server), ["malformed", "winner"])
        }
    }

    func testZeroAndNegativeTimeoutStillTrackWithoutChoose() async throws {
        try await withServer { sdk, server in
            for timeout: TimeInterval in [0, -1] {
                sdk.staleContentTimeout = timeout
                XCTAssertEqual(sdk.staleContentTimeout, 0)
                server.reset(campaigns: [campaign("c")], content: content("c"))
                expectNil(try await sdk.trackViewNoShow(pageContext: page))
                expectNil(try await sdk.triggerEventNoShow(events: [], pageContext: page))
                XCTAssertEqual(server.recorded.map(\.path), ["/visit", "/event"])
            }
        }
    }

    func testSettingsSurviveReinitialize() async throws {
        try await withServer { sdk, _ in
            XCTAssertTrue(sdk.isFetchContentOnTrack)
            XCTAssertEqual(sdk.staleContentTimeout, 10)
            sdk.isFetchContentOnTrack = false
            sdk.staleContentTimeout = 25
            let replacement = TemporarySDKFixture()
            let next = replacement.initialize()
            XCTAssertFalse(next.isFetchContentOnTrack)
            XCTAssertEqual(next.staleContentTimeout, 25)
        }
    }

    func testSameUserDuringChooseKeepsResponseValid() async throws {
        try await withServer { sdk, server in
            sdk.setUser(userId: "A", sessionId: "session-A")
            let ids = [campaign("c")]
            let answer = content("c")
            server.setResponseHandler { request in
                request.path == "/visit" ? .init(json: ["campaigns": ids]) : .init(json: ["data": answer], delay: 0.15)
            }
            let task = Task { try await sdk.trackViewNoShow(pageContext: page) }
            let requests = await server.waitFor(2)
            XCTAssertEqual(requests.count, 2)
            sdk.setUser(userId: "A", sessionId: "session-A")
            let result = try await task.value
            XCTAssertNotNil(result)
            XCTAssertEqual(chosen(server), ["c"])
        }
    }

    func testFetchDisabledStillSendsBothTrackingRequests() async throws {
        try await withServer { sdk, server in
            sdk.isFetchContentOnTrack = false
            server.reset(campaigns: [campaign("c")], content: content("c"))
            expectNil(try await sdk.trackViewNoShow(pageContext: page))
            expectNil(try await sdk.triggerEventNoShow(events: [CustomEvent(type: "tap", name: "Tap")], pageContext: page))
            XCTAssertEqual(server.recorded.map(\.path), ["/visit", "/event"])
        }
    }

    func testVisitAndEventErrorsReturnNilWithoutChoose() async throws {
        try await withServer { sdk, server in
            server.setResponseHandler { _ in .init(json: [:], status: 503) }
            expectNil(try await sdk.trackViewNoShow(pageContext: page))
            expectNil(try await sdk.triggerEventNoShow(events: [], pageContext: page))
            XCTAssertEqual(server.recorded.map(\.path), ["/visit", "/event"])
        }
    }

    func testConnectionFailureReturnsNil() async throws {
        try await withServer { sdk, server in
            server.stop()
            expectNil(try await sdk.trackViewNoShow(pageContext: page))
            XCTAssertTrue(server.recorded.isEmpty)
        }
    }

    func testStaleTrackingResponsesNeverChoose() async throws {
        try await withServer { sdk, server in
            sdk.staleContentTimeout = 0.02
            let ids = [campaign("c")]
            server.setResponseHandler { _ in .init(json: ["campaigns": ids], delay: 0.06) }
            expectNil(try await sdk.trackViewNoShow(pageContext: page))
            expectNil(try await sdk.triggerEventNoShow(events: [], pageContext: page))
            XCTAssertTrue(chosen(server).isEmpty)
        }
    }

    func testStaleChooseIsDiscardedWithoutTryingNextCampaign() async throws {
        for event in [false, true] {
            let callbacks = HeadlessCallbackRecorder()
            let unexpected = expectation(description: "Stale choose must not emit a callback")
            unexpected.isInverted = true
            try await withServer(callback: { callbacks.record($0); unexpected.fulfill() }) { sdk, server in
                sdk.staleContentTimeout = 60
                let release = DispatchGroup()
                release.enter()
                let ids = [campaign("first", 2), campaign("second", 1)]
                let answer = content("first", trackingBase: server.url)
                server.setResponseHandler { request in
                    if request.path == "/visit" || request.path == "/event" { return .init(json: ["campaigns": ids]) }
                    return .init(json: ["data": answer], sendAfter: release)
                }
                let pending = Task { try await fetch(sdk, event: event) }
                defer { pending.cancel() }
                _ = await server.waitFor(2)
                sdk.staleContentTimeout = 0
                release.leave()
                expectNil(try await pending.value)
                await fulfillment(of: [unexpected], timeout: 1)
                XCTAssertEqual(chosen(server), ["first"])
                XCTAssertEqual(server.recorded.count, 2)
                XCTAssertTrue(callbacks.events.isEmpty)
            }
        }
    }

    func testUserChangeDuringVisitDiscardsResponse() async throws {
        try await withServer { sdk, server in
            sdk.setUser(userId: "A", sessionId: "session-A")
            let ids = [campaign("c")]
            server.setResponseHandler { _ in .init(json: ["campaigns": ids], delay: 0.15) }
            let task = Task { try await sdk.trackViewNoShow(pageContext: page) }
            _ = await server.waitFor(1)
            sdk.setUser(userId: "B", sessionId: "session-B")
            expectNil(try await task.value)
            XCTAssertTrue(chosen(server).isEmpty)
        }
    }

    func testCustomUserIsIdenticalInTrackingAndChoose() async throws {
        try await withServer { sdk, server in
            sdk.setUser(userId: "A", sessionId: "session-A")
            server.reset(campaigns: [campaign("c")], content: content("c"))
            _ = try await sdk.trackViewNoShow(pageContext: page)
            _ = try await sdk.triggerEventNoShow(events: [CustomEvent(type: "tap", name: "Tap")], pageContext: page)
            XCTAssertEqual(server.recorded.count, 4)
            for request in server.recorded {
                XCTAssertEqual((request.body["user"] as? [String: String])?["custom"], "A")
                XCTAssertEqual((request.body["user"] as? [String: String])?["ses"], "session-A")
                XCTAssertNil((request.body["user"] as? [String: String])?["uid"])
            }
        }
    }

    func testAnonymousChooseSendsSessionSavedFromVisitAndEvent() async throws {
        for event in [false, true] {
            try await withServer { sdk, server in
                server.reset(campaigns: [campaign("c")], content: content("c"),
                    responseUser: ["uid": "tracking-user", "ses": "tracking-session"])
                let result = try await fetch(sdk, event: event)
                XCTAssertNotNil(result)
                XCTAssertEqual(server.recorded.map(\.path), [event ? "/event" : "/visit", "/choose"])
                let user = try XCTUnwrap(server.recorded.last?.body["user"] as? [String: String])
                XCTAssertEqual(user["uid"], "tracking-user")
                XCTAssertEqual(user["ses"], "tracking-session")
                XCTAssertNil(user["custom"])
            }
        }
    }

    func testAnonymousChooseResponseUserIsSavedForSubsequentRequests() async throws {
        for event in [false, true] {
            try await withServer { sdk, server in
                let ids = [campaign("c")]
                let answer = content("c")
                server.setResponseHandler { request in
                    if request.path == "/choose" {
                        return .init(json: ["data": answer, "user": ["uid": "choose-user", "ses": "choose-session"]])
                    }
                    return .init(json: ["campaigns": ids, "user": ["uid": "tracking-user", "ses": "tracking-session"]])
                }
                let result = try await fetch(sdk, event: event)
                XCTAssertNotNil(result)
                let subsequent = await sdk.getContentByCampaignIdWithDetails("c", page)
                XCTAssertNotNil(subsequent)
                XCTAssertEqual(server.recorded.map(\.path), [event ? "/event" : "/visit", "/choose", "/choose"])
                let user = try XCTUnwrap(server.recorded.last?.body["user"] as? [String: String])
                XCTAssertEqual(user["uid"], "choose-user")
                XCTAssertEqual(user["ses"], "choose-session")
                XCTAssertNil(user["custom"])
            }
        }
    }

    func testMissingResponseSessionUsesStoredSessionForSameUid() async throws {
        for event in [false, true] {
            try await withServer { sdk, server in
                server.reset(responseUser: ["uid": "same-user", "ses": "stored-session"])
                expectNil(try await sdk.trackViewNoShow(pageContext: page))
                server.reset(campaigns: [campaign("c")], content: content("c"), responseUser: ["uid": "same-user"])
                let result = try await fetch(sdk, event: event)
                XCTAssertNotNil(result)
                let user = try XCTUnwrap(server.recorded.last?.body["user"] as? [String: String])
                XCTAssertEqual(user["uid"], "same-user")
                XCTAssertEqual(user["ses"], "stored-session")
            }
        }
    }

    func testMissingResponseSessionPreservesStoredSessionAfterUidChanges() async throws {
        for event in [false, true] {
            try await withServer { sdk, server in
                server.reset(responseUser: ["uid": "previous-user", "ses": "previous-session"])
                expectNil(try await sdk.trackViewNoShow(pageContext: page))
                server.reset(campaigns: [campaign("c")], content: content("c"), responseUser: ["uid": "new-anonymous"])
                let result = try await fetch(sdk, event: event)
                XCTAssertNotNil(result)
                let user = try XCTUnwrap(server.recorded.last?.body["user"] as? [String: String])
                XCTAssertEqual(user["uid"], "new-anonymous")
                XCTAssertEqual(user["ses"], "previous-session")
            }
        }
    }

    func testMissingResponseUidUsesStoredUidAndKeepsExplicitSession() async throws {
        try await withServer { sdk, server in
            server.reset(responseUser: ["uid": "stored-user", "ses": "stored-session"])
            expectNil(try await sdk.trackViewNoShow(pageContext: page))
            server.reset(campaigns: [campaign("c")], content: content("c"), responseUser: ["ses": "response-session"])
            let result = try await sdk.triggerEventNoShow(events: [], pageContext: page)
            XCTAssertNotNil(result)
            let user = try XCTUnwrap(server.recorded.last?.body["user"] as? [String: String])
            XCTAssertEqual(user["uid"], "stored-user")
            XCTAssertEqual(user["ses"], "response-session")
        }
    }

    func testMissingResponseSessionUsesStoreAtResponseAcceptance() async throws {
        try await withServer { sdk, server in
            server.reset(responseUser: ["uid": "same-user", "ses": "initial-session"])
            expectNil(try await sdk.trackViewNoShow(pageContext: page))
            let release = DispatchGroup()
            release.enter()
            let ids = [campaign("c")]
            let answer = content("c")
            server.reset()
            server.setResponseHandler { request in
                switch request.path {
                case "/visit": return .init(json: ["campaigns": ids, "user": ["uid": "same-user"]], sendAfter: release)
                case "/event": return .init(json: ["campaigns": [], "user": ["uid": "same-user", "ses": "accepted-session"]])
                default: return .init(json: ["data": answer])
                }
            }
            let pending = Task { try await sdk.trackViewNoShow(pageContext: page) }
            let requests = await server.waitFor(1)
            XCTAssertEqual(requests.count, 1)
            let parallel = await GravityRepository.instance.event(events: [], raisedAt: Date(), pageContext: page,
                options: Options(), customerUser: nil)
            XCTAssertNotNil(parallel)
            release.leave()
            let result = try await pending.value
            XCTAssertNotNil(result)
            let user = try XCTUnwrap(server.recorded.last?.body["user"] as? [String: String])
            XCTAssertEqual(user["uid"], "same-user")
            XCTAssertEqual(user["ses"], "accepted-session")
        }
    }

    func testAnonymousFallbackChooseUsesCurrentSessionAfterParallelTracking() async throws {
        try await withServer { sdk, server in
            let release = DispatchGroup()
            release.enter()
            let ids = [campaign("first", 2), campaign("second", 1)]
            let answer = content("second")
            server.setResponseHandler { request in
                switch request.path {
                case "/visit": return .init(json: ["campaigns": ids, "user": ["uid": "first-user", "ses": "first-session"]])
                case "/event": return .init(json: ["campaigns": [], "user": ["uid": "parallel-user", "ses": "parallel-session"]])
                default:
                    let id = (request.body["data"] as? [[String: Any]])?.first?["campaignId"] as? String
                    return id == "first" ? .init(json: ["data": []], sendAfter: release) : .init(json: ["data": answer])
                }
            }
            let pending = Task { try await sdk.trackViewNoShow(pageContext: page) }
            let requests = await server.waitFor(2)
            XCTAssertEqual(requests.map(\.path), ["/visit", "/choose"])
            let parallel = await GravityRepository.instance.event(events: [], raisedAt: Date(), pageContext: page,
                options: Options(), customerUser: nil)
            XCTAssertNotNil(parallel)
            XCTAssertEqual(GravityRepository.instance.userForRequest(nil).uid, "parallel-user")
            XCTAssertEqual(GravityRepository.instance.userForRequest(nil).ses, "parallel-session")
            release.leave()
            let result = try await pending.value
            XCTAssertNotNil(result)
            XCTAssertEqual(chosen(server), ["first", "second"])
            let choices = server.recorded.filter { $0.path == "/choose" }
            XCTAssertEqual(choices.count, 2)
            let firstUser = try XCTUnwrap(choices.first?.body["user"] as? [String: String])
            XCTAssertEqual(firstUser["uid"], "first-user")
            XCTAssertEqual(firstUser["ses"], "first-session")
            let secondUser = try XCTUnwrap(choices.last?.body["user"] as? [String: String])
            XCTAssertEqual(secondUser["uid"], "parallel-user")
            XCTAssertEqual(secondUser["ses"], "parallel-session")
        }
    }

    func testExplicitResponseIdentityWinsOverStoredIdentity() async throws {
        try await withServer { sdk, server in
            server.reset(responseUser: ["uid": "same-user", "ses": "stored-session"])
            expectNil(try await sdk.trackViewNoShow(pageContext: page))
            server.reset(campaigns: [campaign("c")], content: content("c"),
                responseUser: ["uid": "same-user", "ses": "explicit-session"])
            let result = try await sdk.trackViewNoShow(pageContext: page)
            XCTAssertNotNil(result)
            let user = try XCTUnwrap(server.recorded.last?.body["user"] as? [String: String])
            XCTAssertEqual(user["uid"], "same-user")
            XCTAssertEqual(user["ses"], "explicit-session")
        }
    }

    private func fetch(_ sdk: GravitySDK, event: Bool) async throws -> GravityDataResponse<ContentResponse>? {
        if event { return try await sdk.triggerEventNoShow(events: [], pageContext: page) }
        return try await sdk.trackViewNoShow(pageContext: page)
    }

    func testCancellationPropagatesWithoutChoose() async throws {
        try await withServer { sdk, server in
            let ids = [campaign("c")]
            server.setResponseHandler { _ in .init(json: ["campaigns": ids], delay: 0.15) }
            let task = Task { try await sdk.trackViewNoShow(pageContext: page) }
            _ = await server.waitFor(1)
            task.cancel()
            do { _ = try await task.value; XCTFail("Expected cancellation") }
            catch is CancellationError { }
            XCTAssertTrue(chosen(server).isEmpty)
        }
    }
    func testPresentationLockAndExistingReservationDoNotBlockHeadlessOrGetInvalidated() async throws {
        try await withServer { sdk, server in
            sdk.lockPresentation()
            let automatic = sdk.presentationGate.beginRequest(location: "old-screen", newScreen: true)
            let reservation = try XCTUnwrap(sdk.presentationGate.reserve(campaignId: "c", request: automatic))
            defer { sdk.presentationGate.cancel(reservation) }
            server.reset(campaigns: [campaign("c")], content: content("c"))
            let result = try await sdk.trackViewNoShow(pageContext: page)
            XCTAssertNotNil(result)
            XCTAssertTrue(sdk.presentationGate.isCurrent(automatic))
            XCTAssertNil(sdk.presentationGate.reserve(campaignId: "c", request: automatic))
        }
    }

    func testUserChangeAndReinitializationDuringChooseDiscardResponse() async throws {
        for reinitialize in [false, true] {
            let callbacks = HeadlessCallbackRecorder()
            try await withServer(callback: { callbacks.record($0) }) { sdk, server in
                let replacement = TemporarySDKFixture()
                sdk.setUser(userId: "A", sessionId: "session-A")
                let ids = [campaign("c")]
                let answer = content("c", trackingBase: server.url)
                server.setResponseHandler { request in
                    request.path == "/visit" ? .init(json: ["campaigns": ids]) : .init(json: ["data": answer], delay: 0.15)
                }
                let task = Task { try await sdk.trackViewNoShow(pageContext: page) }
                _ = await server.waitFor(2)
                if reinitialize { replacement.initialize(callback: { callbacks.record($0) }) }
                else { sdk.setUser(userId: "B", sessionId: "session-B") }
                expectNil(try await task.value)
                try await Task.sleep(nanoseconds: 50_000_000)
                XCTAssertEqual(chosen(server), ["c"])
                XCTAssertEqual((server.recorded.last(where: { $0.path == "/choose" })?.body["user"] as? [String: String])?["custom"], "A")
                XCTAssertTrue(callbacks.events.isEmpty)
                XCTAssertEqual(server.recorded.map(\.path), ["/visit", "/choose"])
            }
        }
    }

}

private final class HeadlessCallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [TrackingEvent] = []
    func record(_ event: TrackingEvent) { lock.lock(); defer { lock.unlock() }; value.append(event) }
    var events: [TrackingEvent] { lock.lock(); defer { lock.unlock() }; return value }
}
