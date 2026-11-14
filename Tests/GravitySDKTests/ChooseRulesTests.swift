import XCTest
import SwiftUI
import UIKit
@testable import GravitySDK

final class ChooseRulesTests: XCTestCase {
    private let page = PageContext(type: .other, data: [], location: "/catalog")

    /// The app filtered the catalog to 1000...5000; recommendations must use the same filter.
    private let priceRules = [
        RtRule(type: "filter", conditions: [
            RtRuleCondition(field: "price", arguments: [
                RtRuleArgument(action: "gte", value: ["1000"]),
                RtRuleArgument(action: "lte", value: ["5000"])
            ])
        ])
    ]
    private let priceJSON: [[String: Any]] = [
        ["id": NSNull(), "type": "filter", "slots": NSNull(), "conditions": [
            ["field": "price", "arguments": [
                ["action": "gte", "value": ["1000"]],
                ["action": "lte", "value": ["5000"]]
            ]]
        ]]
    ]

    private func withServer(_ body: (GravitySDK, RecordingServer) async throws -> Void) async throws {
        let savedUID = UserDefaults.standard.string(forKey: "gravity_user_id")
        defer { UserDefaults.standard.set(savedUID, forKey: "gravity_user_id") }
        let fixture = TemporarySDKFixture(apiKey: "rules", section: "rules")
        let server = try RecordingServer()
        try await server.start()
        defer { server.stop() }
        let sdk = fixture.initialize()
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        try await body(sdk, server)
        withExtendedLifetime(fixture) {}
    }

    private func chooseItems(_ server: RecordingServer) throws -> [[String: Any]] {
        try server.recorded.filter { $0.path == "/choose" }.map { request in
            let data = try XCTUnwrap(request.body["data"] as? [[String: Any]])
            XCTAssertEqual(data.count, 1)
            XCTAssertNil(request.body["rules"], "rules belong to the data[] item, not the envelope")
            return try XCTUnwrap(data.first)
        }
    }

    private func content(_ id: String) -> [[String: Any]] {
        [["payload": [["campaignId": id, "experienceId": "e", "variationId": "v", "decisionId": "d",
            "contents": [["contentId": id, "contentType": "native", "deliveryMethod": "inline",
                "templateSystemName": "inline-1",
                "variables": ["elements": [["type": "text", "text": id]]]]]]]]]
    }

    private func ruleTag(_ request: RecordingServer.Request) -> String? {
        let item = (request.body["data"] as? [[String: Any]])?.first
        let rules = item?["rules"] as? [[String: Any]]
        let condition = (rules?.first?["conditions"] as? [[String: Any]])?.first
        return ((condition?["arguments"] as? [[String: Any]])?.first?["value"] as? [String])?.first
    }

    private func tagRules(_ tag: String) -> [RtRule] {
        [RtRule(type: "filter", conditions: [
            RtRuleCondition(field: "category", arguments: [RtRuleArgument(action: "in", value: [tag])])
        ])]
    }

    // MARK: - Model

    func testRuleModelEncodesFlutterJSON() throws {
        let rule = RtRule(id: 7, type: "include", slots: [1, 3], conditions: [
            RtRuleCondition(field: "sku", arguments: [RtRuleArgument(action: "in", value: ["001", "true", ""])])
        ])
        let full = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? NSDictionary
        XCTAssertEqual(full, ["id": 7, "type": "include", "slots": [1, 3], "conditions": [
            ["field": "sku", "arguments": [["action": "in", "value": ["001", "true", ""]]]]
        ]] as NSDictionary)
        // json_serializable in Flutter writes absent optionals as explicit nulls.
        let minimal = try JSONSerialization.jsonObject(with: JSONEncoder().encode(priceRules)) as? NSArray
        XCTAssertEqual(minimal, priceJSON as NSArray)
        XCTAssertEqual(try JSONDecoder().decode([RtRule].self, from: JSONEncoder().encode(priceRules)), priceRules)
    }

    // MARK: - Content requests

    func testEveryContentEntryPointSendsPriceRulesInItsDataItem() async throws {
        try await withServer { sdk, server in
            _ = await sdk.getContentBySelector(selector: "s", pageContext: page, rules: priceRules)
            _ = await sdk.getContentBySelectorWithDetails(selector: "s", pageContext: page, rules: priceRules)
            _ = await sdk.getContentByCampaignId("c", page, rules: priceRules)
            _ = await sdk.getContentByCampaignIdWithDetails("c", page, rules: priceRules)
            _ = await sdk.getContentByGroupSelector(groupSelector: "g", pageContext: page, rules: priceRules)
            let items = try chooseItems(server)
            let identifiers = ["selector", "selector", "campaignId", "campaignId", "group"]
            XCTAssertEqual(items.count, identifiers.count)
            for (item, identifier) in zip(items, identifiers) {
                XCTAssertEqual(Set(item.keys), [identifier, "option", "rules"], identifier)
                XCTAssertEqual(item["rules"] as? NSArray, priceJSON as NSArray, identifier)
            }
        }
    }

    func testCallsWithoutRulesDoNotSendTheKey() async throws {
        try await withServer { sdk, server in
            _ = await sdk.getContentBySelector(selector: "s", pageContext: page)
            _ = await sdk.getContentBySelectorWithDetails(selector: "s", pageContext: page)
            _ = await sdk.getContentByCampaignId("c", page)
            _ = await sdk.getContentByCampaignIdWithDetails("c", page)
            _ = await sdk.getContentByGroupSelector(groupSelector: "g", pageContext: page)
            _ = await sdk.getContentBySelector(selector: "s", pageContext: page, rules: nil)
            _ = await sdk.getContentByCampaignId("c", page, rules: nil)
            _ = await sdk.getContentByGroupSelector(groupSelector: "g", pageContext: page, rules: nil)
            let items = try chooseItems(server)
            XCTAssertEqual(items.count, 8)
            for item in items {
                XCTAssertNil(item["rules"])
                XCTAssertEqual(item.count, 2, "\(item.keys)")
            }
            // An empty list is a value the app passed, so it is sent as-is.
            server.reset()
            _ = await sdk.getContentBySelector(selector: "s", pageContext: page, rules: [])
            XCTAssertEqual(try chooseItems(server).first?["rules"] as? NSArray, [] as NSArray)
        }
    }

    func testConcurrentCallsWithDifferentRulesGetTheirOwnResults() async throws {
        try await withServer { sdk, server in
            server.setResponseHandler { [self] request in
                guard request.path == "/choose", let tag = ruleTag(request) else { return .init(json: ["data": []]) }
                // The first-sent filter answers last, so a crossed or shared reply would show.
                return .init(json: ["data": content(tag)], delay: tag.hasSuffix("-slow") ? 0.4 : 0)
            }
            async let a = sdk.getContentBySelector(selector: "s", pageContext: page, rules: tagRules("a-slow"))
            async let b = sdk.getContentBySelector(selector: "s", pageContext: page, rules: tagRules("b"))
            async let c = sdk.getContentByCampaignIdWithDetails("c", page, rules: tagRules("c-slow"))
            async let d = sdk.getContentByCampaignId("c", page, rules: tagRules("d"))
            async let e = sdk.getContentByGroupSelector(groupSelector: "g", pageContext: page, rules: tagRules("e-slow"))
            async let f = sdk.getContentByGroupSelector(groupSelector: "g", pageContext: page, rules: tagRules("f"))
            let results = await [a, b, c?.data, d, e, f]
            let ids = results.map { $0?.data.first?.payload.first?.contents.first?.contentId }
            XCTAssertEqual(ids, ["a-slow", "b", "c-slow", "d", "e-slow", "f"])
            XCTAssertEqual(Set(server.recorded.filter { $0.path == "/choose" }.compactMap(ruleTag)),
                           ["a-slow", "b", "c-slow", "d", "e-slow", "f"])
        }
    }

    // MARK: - Inline placements

    private enum Placement: CaseIterable { case uikit, list, swiftui }

    private final class Mounted {
        let window = UIWindow(frame: UIScreen.main.bounds)
        var update: ([RtRule]?) -> Void = { _ in }
        deinit {
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    @MainActor private func mount(_ placement: Placement, rules: [RtRule]?, page: PageContext) -> Mounted {
        let mounted = Mounted()
        let host: UIViewController
        switch placement {
        case .swiftui:
            let hosting = UIHostingController(rootView: GravityInlineSwiftUIView(selector: "s", pageContext: page, rules: rules))
            mounted.update = { hosting.rootView = GravityInlineSwiftUIView(selector: "s", pageContext: page, rules: $0) }
            host = hosting
        case .uikit, .list:
            host = UIViewController()
            let view: UIView
            if placement == .uikit {
                let inline = GravityInlineView(selector: "s", rules: rules)
                inline.initialize(pageContext: page)
                mounted.update = { inline.rules = $0 }
                view = inline
            } else {
                let inline = GravityInlineListView(groupSelector: "g", rules: rules)
                inline.initialize(pageContext: page)
                mounted.update = { inline.rules = $0 }
                view = inline
            }
            view.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
            host.view.addSubview(view)
        }
        mounted.window.rootViewController = host
        mounted.window.makeKeyAndVisible()
        return mounted
    }

    @MainActor func testEveryInlinePlacementSendsItsRules() async throws {
        try await withServer { _, server in
            for placement in Placement.allCases {
                for rules in [priceRules, nil] {
                    server.reset()
                    let mounted = mount(placement, rules: rules, page: page)
                    let requests = await server.waitFor(1)
                    let item = try XCTUnwrap((requests.first?.body["data"] as? [[String: Any]])?.first)
                    XCTAssertNotNil(item[placement == .list ? "group" : "selector"], "\(placement)")
                    if rules == nil {
                        XCTAssertNil(item["rules"], "\(placement)")
                    } else {
                        XCTAssertEqual(item["rules"] as? NSArray, priceJSON as NSArray, "\(placement)")
                    }
                    withExtendedLifetime(mounted) {}
                }
            }
        }
    }

    @MainActor func testChangingRulesReloadsRenderedInlineContent() async throws {
        try await withServer { _, server in
            for placement in Placement.allCases {
                server.reset()
                server.setResponseHandler { [self] request in
                    .init(json: ["data": content(ruleTag(request) ?? "none")])
                }
                let mounted = mount(placement, rules: tagRules("before"), page: page)
                _ = await server.waitFor(1)
                // Let the first answer render before the filter changes.
                try await Task.sleep(nanoseconds: 300_000_000)
                mounted.update(tagRules("before"))
                mounted.update(tagRules("after"))
                var requests = await server.waitFor(2)
                mounted.update(nil)
                requests = await server.waitFor(3)
                try await Task.sleep(nanoseconds: 300_000_000)
                requests = server.recorded
                XCTAssertEqual(requests.map(ruleTag), ["before", "after", nil], "\(placement)")
                withExtendedLifetime(mounted) {}
            }
        }
    }

    @MainActor func testRulesSetBeforeMountAreUsedForTheFirstLoad() async throws {
        try await withServer { _, server in
            let inline = GravityInlineView(selector: "s")
            inline.rules = tagRules("early")
            inline.initialize(pageContext: page)
            let list = GravityInlineListView(groupSelector: "g")
            list.initialize(pageContext: page)
            list.rules = tagRules("late-but-before-mount")
            let host = UIViewController()
            inline.frame = CGRect(x: 0, y: 0, width: 320, height: 100)
            list.frame = CGRect(x: 0, y: 100, width: 320, height: 100)
            host.view.addSubview(inline)
            host.view.addSubview(list)
            let window = UIWindow(frame: UIScreen.main.bounds)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            _ = await server.waitFor(2)
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(Set(server.recorded.compactMap(ruleTag)), ["early", "late-but-before-mount"])
            XCTAssertEqual(server.recorded.count, 2)
        }
    }
}
