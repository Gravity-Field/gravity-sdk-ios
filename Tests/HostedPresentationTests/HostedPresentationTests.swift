import Foundation
import SwiftUI
import UIKit
@testable import GravitySDK

/// Runs in an application process: unlike package XCTest, UIKit completes real
/// presentation/dismissal transitions and SwiftUI receives cover/uncover events.
@MainActor enum HostedPresentationTests {
    static var started = false
    static var failures: [String] = []
    static var cases = 0
    static var events: [String] = []
    static var lines: [String] = []
    static var prefix = ""
    static func paths(_ server: RecordingServer) -> [String] {
        server.recorded.map(\.path).filter { $0.contains(prefix) }.map { $0.replacingOccurrences(of: prefix, with: "") }
    }
    static func recordContent(_ kind: String, _ id: String) {
        guard id.hasPrefix(prefix) else { return }
        events.append(kind + ":" + id.dropFirst(prefix.count))
    }
    static let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let methods: [DeliveryMethod] = [.modal, .fullScreen, .bottomSheet]

    static func log(_ message: String) {
        lines.append("\(Date().timeIntervalSince1970) " + message)
        try? lines.joined(separator: "\n").write(to: directory.appendingPathComponent("hosted.log"), atomically: true, encoding: .utf8)
    }
    static func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
        log("\(condition ? "PASS" : "FAIL") \(message)")
    }
    static func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    static func wait(_ seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { await pause(0.02) }
        return condition()
    }
    static func record(_ event: TrackingEvent) {
        switch event {
        case let e as ContentImpressionEvent: recordContent("impression", e.content.contentId)
        case let e as ContentVisibleImpressionEvent: recordContent("visible", e.content.contentId)
        case let e as ContentCloseEvent: recordContent("close", e.content.contentId)
        case let e as ContentLoadEvent: recordContent("load", e.content.contentId)
        default: events.append(String(describing: type(of: event)))
        }
    }
    static func content(_ id: String, _ step: Int?, _ method: DeliveryMethod, _ base: String) -> CampaignContent {
        let id = prefix + id
        return CampaignContent(contentId: id, templateSystemName: method == .snackBar ? .snackbar1 : nil,
            deliveryMethod: method, contentType: "native", step: step,
            variables: Variables(frameUI: FrameUI(container: Container()),
                elements: [Element(type: .text, text: "Hosted step \(id)")],
                onImpression: ContentActionModel(action: .impression), onClose: ContentActionModel(action: .close)),
            events: [Event(type: .impression, urls: [base + "/impression/" + id]),
                Event(type: .visibleImpression, urls: [base + "/visible/" + id]),
                Event(type: .close, urls: [base + "/close/" + id]),
                Event(type: .openStep, urls: [base + "/openStep/" + id])])
    }
    static func id(_ host: UIViewController?) -> String? {
        if let h = host as? UIHostingController<GravityModalContent> { return String(h.rootView.content.contentId.dropFirst(prefix.count)) }
        if let h = host as? UIHostingController<GravityFullScreenContent> { return String(h.rootView.content.contentId.dropFirst(prefix.count)) }
        if let h = host as? UIHostingController<GravityBottomSheetContent> { return String(h.rootView.content.contentId.dropFirst(prefix.count)) }
        if let h = host as? UIHostingController<GravitySnackbarContent> { return String(h.rootView.content.contentId.dropFirst(prefix.count)) }
        return nil
    }
    static func session(_ host: UIViewController?) -> ModalImpressionSession? {
        if let h = host as? UIHostingController<GravityModalContent> { return h.rootView.impressionSession }
        if let h = host as? UIHostingController<GravityFullScreenContent> { return h.rootView.impressionSession }
        if let h = host as? UIHostingController<GravityBottomSheetContent> { return h.rootView.impressionSession }
        if let h = host as? UIHostingController<GravitySnackbarContent> { return h.rootView.impressionSession }
        return nil
    }
    static func click(_ host: UIViewController, _ action: OnClickModel) {
        if let h = host as? UIHostingController<GravityModalContent> { h.rootView.onClickCallback(action) }
        if let h = host as? UIHostingController<GravityFullScreenContent> { h.rootView.onClickCallback(action) }
        if let h = host as? UIHostingController<GravityBottomSheetContent> { h.rootView.onClickCallback(action) }
        if let h = host as? UIHostingController<GravitySnackbarContent> { h.rootView.onClickCallback(action) }
    }
    static func target(_ root: UIViewController, _ method: DeliveryMethod) -> UIViewController? {
        method == .snackBar ? root.children.first(where: { id($0) != nil }) : root.presentedViewController
    }
    static func sdk(_ server: RecordingServer) -> GravitySDK {
        prefix = UUID().uuidString + "-"
        let store = VisibleImpressionStore(fileURL: directory.appendingPathComponent(UUID().uuidString + ".json"))
        let sdk = GravitySDK(apiKey: "hosted-test", section: "hosted-test", gravityEventCallback: record,
            productViewBuilder: nil, productFilter: nil, uiSettings: nil, visibleImpressionStore: store)
        GravitySDK.initialize(sdk)
        sdk.setOptions(options: nil, contentSettings: nil, proxyUrl: server.url)
        return sdk
    }
    static func cleanup(_ root: UIViewController, _ sdk: GravitySDK) async {
        for host in root.children where id(host) != nil {
            if let contentId = id(host) { sdk.dismissInApp(contentId: prefix + contentId) }
        }
        if root.presentedViewController != nil {
            await withCheckedContinuation { continuation in root.dismiss(animated: false) { continuation.resume() } }
        }
        await pause(0.15)
    }

    static func step(_ root: UIViewController, _ server: RecordingServer, from: DeliveryMethod,
                     to: DeliveryMethod, close: Bool) async {
        cases += 1
        let label = "step \(from)->\(to) closeOnClick=\(close)"
        log("START " + label)
        server.reset(); events = []
        let sdk = sdk(server)
        let first = content("first", nil, from, server.url)
        let second = content("second", 2, to, server.url)
        let campaign = Campaign(payload: [CampaignVariation(campaignId: "step-campaign", experienceId: "e", variationId: "v", decisionId: "d", contents: [first, second])])
        let opening = sdk.makeModalImpressionSession(first, campaign)
        let acknowledgement = DispatchGroup()
        acknowledgement.enter()
        var released = false
        defer { if !released { acknowledgement.leave() } }
        server.setResponseHandler { request in
            .init(json: [:], sendAfter: request.path.contains("/visible/") ? acknowledgement : nil)
        }
        let request = sdk.presentationGate.beginRequest(location: "step", newScreen: true)
        guard let reservation = sdk.presentationGate.reserve(campaignId: "step-campaign", request: request) else {
            check(false, label + " initial reservation"); return
        }
        check(sdk.presentationGate.present(reservation, contentIds: [first.contentId, second.contentId]) {
            sdk.showBackendContent(root, first, campaign, impressionSession: opening)
        }, label + " reserved presentation")
        let ready = await wait { opening.hasFired && root.presentedViewController?.isBeingPresented == false && paths(server).count >= 2 }
        check(ready, label + " first appeared")
        await pause(0.2)
        guard let host = root.presentedViewController else { check(false, label + " missing first host"); return }
        click(host, OnClickModel(action: .openStep, step: 2, closeOnClick: close))
        // The next step replaces the current one regardless of closeOnClick, within one showing.
        let shown = await wait { id(target(root, to)) == "second" && events.contains("impression:second") }
        check(shown, label + " second appeared after physical dismissal")
        check(session(target(root, to)) === opening, label + " shared opening session")
        check(host.presentingViewController == nil, label + " first physically removed")
        if let next = target(root, to), id(next) == "second" {
            sdk.dismissInApp(contentId: prefix + "second")
            _ = await wait { events.contains("close:second") }
        }
        _ = await wait { paths(server).count >= 5 }
        await pause(0.3)
        let expected = ["impression:first", "visible:first", "impression:second", "close:second"]
        check(events == expected, label + " callbacks \(events)")
        let wirePaths = paths(server).sorted()
        check(wirePaths == ["/impression/first", "/visible/first", "/openStep/first", "/impression/second", "/close/second"].sorted(), label + " wire \(wirePaths)")
        let overlapping = sdk.presentationGate.beginRequest(location: "step", newScreen: false)
        let duplicate = sdk.presentationGate.reserve(campaignId: "step-campaign", request: overlapping)
        check(duplicate == nil, label + " opening protected until WRIMP acknowledgement")
        if let duplicate { sdk.presentationGate.cancel(duplicate) }
        acknowledgement.leave()
        released = true
        // Real acknowledgement must leave no stale campaign reservation.
        _ = await wait { sdk.visibleImpressionDelivery.store?.entries.isEmpty == true }
        let fresh = sdk.presentationGate.beginRequest(location: "after-step", newScreen: false)
        if let reservation = sdk.presentationGate.reserve(campaignId: "step-campaign", request: fresh) {
            sdk.presentationGate.cancel(reservation)
        } else { check(false, label + " gate stuck") }
        await cleanup(root, sdk)
    }

    static func cancellation(_ root: UIViewController, _ server: RecordingServer, reason: String) async {
        cases += 1
        let label = "cancel sheet step during dismissal: " + reason
        log("START " + label)
        server.reset(); events = []
        let sdk = sdk(server)
        let first = content("first", nil, .bottomSheet, server.url)
        let second = content("second", 2, .modal, server.url)
        let campaign = Campaign(payload: [CampaignVariation(campaignId: "cancel-campaign", experienceId: "e", variationId: "v", decisionId: "d", contents: [first, second])])
        let acknowledgement = DispatchGroup()
        acknowledgement.enter()
        var released = false
        defer { if !released { acknowledgement.leave() } }
        server.setResponseHandler { request in
            .init(json: [:], sendAfter: request.path.contains("/visible/") ? acknowledgement : nil)
        }
        let initialRequest = sdk.presentationGate.beginRequest(location: "cancellation", newScreen: true)
        guard let initial = sdk.presentationGate.reserve(campaignId: "cancel-campaign", request: initialRequest) else {
            check(false, label + " initial reservation"); return
        }
        check(sdk.presentationGate.present(initial, contentIds: [first.contentId, second.contentId]) {
            sdk.showBackendContent(root, first, campaign)
        }, label + " reserved presentation")
        _ = await wait { session(root.presentedViewController)?.hasFired == true && paths(server).count >= 2 }
        await pause(0.2)
        let overlapping = sdk.presentationGate.beginRequest(location: "cancellation", newScreen: false)
        let duplicate = sdk.presentationGate.reserve(campaignId: "cancel-campaign", request: overlapping)
        check(duplicate == nil, label + " starts with an active protected reservation")
        if let duplicate { sdk.presentationGate.cancel(duplicate) }
        guard let host = root.presentedViewController else { check(false, label + " first missing"); return }
        var resignedDuringDismissal = false
        let startedDismissal = Date()
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { _ in
            resignedDuringDismissal = host.presentingViewController != nil
                && Date().timeIntervalSince(startedDismissal) < 0.35
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        click(host, OnClickModel(action: .openStep, step: 2))
        if reason == "background" {
            try? "resume".write(to: directory.appendingPathComponent("background-request"), atomically: true, encoding: .utf8)
            // Test-host-only lifecycle control: simctl launching another app can
            // take longer than 0.35 s. This selector backgrounds the real app;
            // the driver relaunches it, and assertions verify the lifecycle.
            let suspend = NSSelectorFromString("suspend")
            check(UIApplication.shared.responds(to: suspend), label + " background control available")
            UIApplication.shared.perform(suspend)
            let inactive = await wait { UIApplication.shared.applicationState != .active }
            check(inactive, label + " app actually left foreground")
            check(resignedDuringDismissal, label + " resigned during the 0.35 second dismissal")
            _ = await wait(8) { UIApplication.shared.applicationState == .active }
        } else {
            await pause(0.1)
            check(host.presentingViewController != nil, label + " inside 0.35 second window")
            if reason == "user" { sdk.setUser(userId: "changed", sessionId: "changed") }
            if reason == "invalidation" { sdk.lockPresentation(); sdk.unlockPresentation() }
        }
        _ = await wait { root.presentedViewController == nil }
        await pause(0.2)
        log(label + " events=\(events) paths=\(paths(server)) state=\(UIApplication.shared.applicationState.rawValue)")
        check(root.presentedViewController == nil, label + " no second host (remaining=\(id(root.presentedViewController) ?? "none"))")
        check(!events.contains("impression:second"), label + " no second impression")
        acknowledgement.leave()
        released = true
        _ = await wait { sdk.visibleImpressionDelivery.store?.entries.isEmpty == true }
        let request = sdk.presentationGate.beginRequest(location: "recovery", newScreen: true)
        let reservation = sdk.presentationGate.reserve(campaignId: "cancel-campaign", request: request)
        check(reservation != nil, label + " gate released")
        if let reservation { sdk.presentationGate.cancel(reservation) }
        _ = sdk.showBackendContent(root, content("recovery", nil, .modal, server.url), Campaign())
        check(await wait { id(root.presentedViewController) == "recovery" }, label + " later presentation works")
        await cleanup(root, sdk)
    }

    static func run() async {
        guard !started else { return }; started = true
        await pause(0.5)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController,
              let server = try? RecordingServer() else { return }
        do { try await server.start() } catch { return }
        defer { server.stop() }
        let mode = ProcessInfo.processInfo.environment["HOSTED_TEST_MODE"] ?? "steps"
        if mode != "cancellation" {
            for from in methods {
                for to in methods + [.snackBar] {
                    await step(root, server, from: from, to: to, close: true)
                    await step(root, server, from: from, to: to, close: false)
                }
            }
        }
        for reason in ["user", "invalidation", "background"] { await cancellation(root, server, reason: reason) }
        log("COMPLETE cases=\(cases) failures=\(failures.count)")
        let result: [String: Any] = ["cases": cases, "failures": failures, "os": UIDevice.current.systemVersion]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("hosted-results.json"), options: .atomic)
        }
    }
}
