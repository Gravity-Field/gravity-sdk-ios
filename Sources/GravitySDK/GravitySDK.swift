import Foundation
import CryptoKit
import SwiftUI
import UIKit

public typealias ProductFilter = (Slot) -> Bool
public typealias GravityEventCallback = (TrackingEvent) -> Void
public typealias GravityLogListener = @Sendable (LogLevel, String) -> Void


public class GravitySDK {
    internal let apiKey: String
    internal let section: String
    private let gravityEventCallback: GravityEventCallback?
    internal let productViewBuilder: ProductViewBuilder?
    internal let productFilter: ProductFilter?
    internal let customFont: UIFont?
    private let inAppPreparation: InAppPreparation?
    private let presentationTiming: PresentationTiming
    private let presentationRevision = PresentationRevision()
    private let inAppPresentations = InAppPresentationRegistry()
    internal var campaignDelayTiming = CampaignDelayTiming()

    internal init(
        apiKey: String,
        section: String,
        gravityEventCallback: GravityEventCallback?,
        productViewBuilder: ProductViewBuilder?,
        productFilter: ProductFilter?,
        uiSettings: UISettings?,
        inAppPreparation: InAppPreparation? = nil,
        visibleImpressionStore: VisibleImpressionStore? = nil,
        presentationTiming: PresentationTiming = PresentationTiming()
    ) {
        self.presentationTiming = presentationTiming
        self.apiKey = apiKey
        self.section = section
        let store = visibleImpressionStore ?? Self.impressionStore(apiKey: apiKey, section: section)
        let gate = InAppPresentationGate()
        self.presentationGate = gate
        self.visibleImpressionDelivery = VisibleImpressionDelivery(
            send: { try await GravityRepository.instance.trackEngagementEvent(urls: [$0], apiKey: apiKey) },
            retryable: EngagementTransport.isRetryable,
            store: store,
            startsSuspended: true,
            discarded: { [weak gate] entry in
                gate?.discardDelivery(scope: entry.scope, campaignId: entry.campaignId, contentId: entry.contentId)
            },
            acknowledged: { [weak gate] entry in
                gate?.acknowledgeDelivery(scope: entry.scope, campaignId: entry.campaignId, contentId: entry.contentId)
            }
        )
        self.gravityEventCallback = gravityEventCallback
        self.productViewBuilder = productViewBuilder
        self.productFilter = productFilter
        self.inAppPreparation = inAppPreparation

        if let fontName = uiSettings?.fontName {
            let font = UIFont(name: fontName, size: UIFont.labelFontSize)
            if font == nil {
                GravityLogger.e(
                    Self.TAG,
                    "Failed to load font '\(fontName)', using system font"
                )
            }
            self.customFont = font
        } else {
            self.customFont = nil
        }
        gate.deliveryPending = { [weak self] campaignId in
            guard let self else { return false }
            return store.protects(scope: self.impressionScope, campaignId: campaignId)
        }
        gate.deliveryScope = { [weak self] in self?.impressionScope ?? "" }
        store.observeInsert { [weak delivery = visibleImpressionDelivery] in
            Task { await delivery?.resumePending() }
        }
    }

    private static var _instance: GravitySDK?
    private static var deliveryTransition: Task<Void, Never>?

    private static let uninitializedInstance: GravitySDK = {
        GravityLogger.configure(.error)
        return GravitySDK(
            apiKey: "",
            section: "",
            gravityEventCallback: nil,
            productViewBuilder: nil,
            productFilter: nil,
            uiSettings: nil
        )
    }()

    public static var isInitialized: Bool { _instance != nil }

    public static var instance: GravitySDK {
        _instance ?? uninitializedInstance
    }

    private static let TAG = "SDK"

    public static func initialize(
        apiKey: String,
        section: String,
        gravityEventCallback: GravityEventCallback? = nil,
        productViewBuilder: ProductViewBuilder? = nil,
        productFilter: ProductFilter? = nil,
        uiSettings: UISettings? = nil,
        logLevel: LogLevel = .error
    ) {
        initialize(apiKey: apiKey, section: section, gravityEventCallback: gravityEventCallback,
                   productViewBuilder: productViewBuilder, productFilter: productFilter,
                   uiSettings: uiSettings, logLevel: logLevel, inAppPreparation: nil)
    }

    public static func initialize(
        apiKey: String,
        section: String,
        gravityEventCallback: GravityEventCallback? = nil,
        productViewBuilder: ProductViewBuilder? = nil,
        productFilter: ProductFilter? = nil,
        uiSettings: UISettings? = nil,
        logLevel: LogLevel = .error,
        inAppPreparation: InAppPreparation?
    ) {
        GravityLogger.configure(logLevel)
        let next = GravitySDK(
            apiKey: apiKey,
            section: section,
            gravityEventCallback: gravityEventCallback,
            productViewBuilder: productViewBuilder,
            productFilter: productFilter,
            uiSettings: uiSettings,
            inAppPreparation: inAppPreparation
        )
        initialize(next, logLevel: logLevel)
    }

    internal static func initialize(_ next: GravitySDK, logLevel: LogLevel = .error) {
        GravityLogger.configure(logLevel)
        let previous = _instance
        previous?.presentationGate.scoped {
            previous?.presentationGate.reset()
            previous?.repository.sessionManager.invalidate()
        }
        _instance = next
        let predecessor = deliveryTransition
        deliveryTransition = Task {
            // Serialize rapid A → B → C reinitializations, even before B has started.
            await predecessor?.value
            if let previous { await previous.visibleImpressionDelivery.stop() }
            await next.visibleImpressionDelivery.start()
        }
    }

    private static let impressionStoreLock = NSLock()
    private static var impressionStores: [String: VisibleImpressionStore] = [:]

    private static func impressionStore(apiKey: String, section: String) -> VisibleImpressionStore {
        impressionStoreLock.lock(); defer { impressionStoreLock.unlock() }
        let namespace = SHA256.hash(data: Data((apiKey + "\n" + section).utf8))
            .map { String(format: "%02x", $0) }.joined()
        if let store = impressionStores[namespace] { return store }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GravitySDK/visible-impressions", isDirectory: true)
        let store = VisibleImpressionStore(fileURL: root.appendingPathComponent(namespace + ".json"), log: logImpressionStore, loadsAsynchronously: true)
        impressionStores[namespace] = store
        return store
    }

    internal static func logImpressionStore(_ message: String) {
        // Store construction can occur before _instance exists. Defer logging to avoid
        // recursively initializing the singleton through GravityLogger's host listener.
        Task { @MainActor in GravityLogger.e("WRIMPStore", message, sendToBack: false) }
    }

    internal var impressionScope: String {
        let snapshot = repository.userForRequest(user)
        return (try? String(data: JSONEncoder().encode([section, snapshot.custom ?? "", snapshot.custom == nil ? snapshot.uid ?? "" : ""]), encoding: .utf8)) ?? ""
    }

    internal let presentationGate: InAppPresentationGate
    internal let visibleImpressionDelivery: VisibleImpressionDelivery
    private var _user: User?
    internal var user: User? { presentationGate.scoped { _user } }

    private func automaticRequest(_ pageContext: PageContext, newScreen: Bool)
        -> (InAppPresentationGate.Request, User?, UInt64, SessionManager.Snapshot) {
        presentationGate.scoped {
            if newScreen { presentationRevision.invalidate() }
            return (presentationGate.beginRequest(location: pageContext.location, newScreen: newScreen),
                    _user, presentationRevision.current, repository.sessionManager.snapshot(customUser: _user))
        }
    }
    // These process-wide settings also apply to the pre-initialize placeholder.
    private static let trackingConfiguration = TrackingConfiguration()

    /// Controls NoShow content fetching; tracking is always sent.
    public var isFetchContentOnTrack: Bool {
        get { Self.trackingConfiguration.fetchContent }
        set { Self.trackingConfiguration.fetchContent = newValue }
    }

    /// Maximum NoShow request age in seconds; negative values become zero.
    /// Settings survive initialize(), including values set before initialization.
    public var staleContentTimeout: TimeInterval {
        get { Self.trackingConfiguration.timeout }
        set { Self.trackingConfiguration.timeout = max(0, newValue) }
    }

    private var options = Options()
    private var contentSettings = ContentSettings()
    internal var logListener: GravityLogListener?
    internal var proxyUrl: String?
    private let notificationPermissionLock = NSLock()
    private var _notificationPermissionStatus = NotificationPermissionStatus.unknown
    internal var notificationPermissionStatus: NotificationPermissionStatus {
        get {
            notificationPermissionLock.lock()
            defer { notificationPermissionLock.unlock() }
            return _notificationPermissionStatus
        }
        set {
            notificationPermissionLock.lock()
            defer { notificationPermissionLock.unlock() }
            _notificationPermissionStatus = newValue
        }
    }

    private let presentationLock = NSLock()
    private var _isPresentationLocked = false
    private var isPresentationLocked: Bool {
        get {
            presentationLock.lock()
            defer { presentationLock.unlock() }
            return _isPresentationLocked
        }
        set {
            presentationLock.lock()
            defer { presentationLock.unlock() }
            _isPresentationLocked = newValue
        }
    }
    private var presentationLockListener: ((Bool) -> Void)?

    private let repository = GravityRepository.instance
    private let contentEventService = ContentEventService.instance
    private let productEventService = ProductEventService.instance

    public func setOptions(
        options: Options?,
        contentSettings: ContentSettings?,
        proxyUrl: String?
    ) {
        guard checkInitialized() else { return }

        self.options = options ?? Options()
        self.contentSettings = contentSettings ?? ContentSettings()
        self.proxyUrl = proxyUrl
    }

    public func setUser(userId: String, sessionId: String) {
        guard checkInitialized() else { return }

        presentationGate.scoped {
            if _user?.custom != userId || _user?.ses != sessionId {
                presentationGate.reset()
                presentationRevision.invalidate()
                repository.sessionManager.invalidate()
            }
            _user = User(custom: userId, ses: sessionId)
        }
    }

    /// The server UID of the anonymous user, independent of `setUser` custom IDs.
    /// Waits for an anonymous session request already in flight; never starts one.
    /// Available before initialization. Reading a stored UID does not notify the listener.
    /// Returns nil if the calling task is cancelled.
    public func getUserId() async -> String? {
        await repository.sessionManager.getUserId()
    }

    /// Observes server UID changes on the main queue, including restore and reset
    /// (`nil`). Repeated server echoes are silent. Pass `nil` to unsubscribe.
    /// Registering does not replay the current UID; use `getUserId` to read it.
    public func setUserIdListener(_ listener: ((String?) -> Void)?) {
        repository.sessionManager.setListener(listener)
    }

    /// Clears the anonymous session, custom user and stored UID. The next request
    /// opens an anonymous session. Throws if storage refuses removal. The session
    /// and custom user remain cleared; the getter returns nil even if storage
    /// still contains the previous UID. Reset of a known UID still notifies the listener with nil.
    /// Pending WRIMP delivery is retained. Available before initialization.
    public func resetUser() async throws {
        try presentationGate.scoped {
            _user = nil
            presentationGate.reset()
            presentationRevision.invalidate()
            try repository.sessionManager.resetUser()
        }
    }

    /// Stores a previously obtained server UID, clears the session and custom
    /// user, and uses that UID on the next request. Surrounding whitespace is
    /// trimmed before storing. Empty/whitespace-only UIDs throw `invalidUserId`
    /// without changing identity. Storage errors are thrown after
    /// clearing the session/custom user; the previous UID remains in use and
    /// the volatile UserDefaults value is rolled back on a failed write.
    /// Pending WRIMP delivery is retained. Available before initialization.
    public func restoreUserId(_ uid: String) async throws {
        let restored = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !restored.isEmpty else {
            throw GravityUserIdError.invalidUserId
        }
        try presentationGate.scoped {
            _user = nil
            presentationGate.reset()
            presentationRevision.invalidate()
            try repository.sessionManager.restoreUserId(restored)
        }
    }

    private func identitySnapshot() -> (User?, UInt64) {
        presentationGate.scoped { (_user, repository.sessionManager.generation) }
    }

    public func setNotificationPermissionStatus(
        status: NotificationPermissionStatus
    ) {
        guard checkInitialized() else { return }

        notificationPermissionStatus = status
    }

    public func setLogListener(_ listener: GravityLogListener?) {
        guard checkInitialized() else { return }

        self.logListener = listener
    }

    public func setPresentationLockListener(_ listener: ((Bool) -> Void)?) {
        guard checkInitialized() else { return }

        presentationLockListener = listener
    }

    public func lockPresentation() {
        guard checkInitialized() else { return }

        isPresentationLocked = true
        presentationRevision.invalidate()
        GravityLogger.i(
            prefix: Self.TAG,
            "Presentation lock called, presentation is now locked"
        )
        notifyPresentationLockListener(true)
    }

    public func unlockPresentation() {
        guard checkInitialized() else { return }

        isPresentationLocked = false
        GravityLogger.i(
            prefix: Self.TAG,
            "Presentation unlock called, presentation is now unlocked"
        )
        notifyPresentationLockListener(false)
    }

    private func notifyPresentationLockListener(_ isLocked: Bool) {
        Task {
            await MainActor.run {
                self.presentationLockListener?(isLocked)
            }
        }
    }

    public func trackView(
        pageContext: PageContext,
        viewController: UIViewController? = nil
    ) {
        trackViewTask(pageContext: pageContext, viewController: viewController)
    }

    /// Automatic tasks must not retain an explicitly supplied host while waiting.
    private final class AutomaticPresentationTarget {
        weak var viewController: UIViewController?
        let wasSupplied: Bool

        init(_ viewController: UIViewController?) {
            self.viewController = viewController
            wasSupplied = viewController != nil
        }
    }

    @discardableResult
    internal func trackViewTask(
        pageContext: PageContext,
        viewController: UIViewController? = nil
    ) -> Task<Void, Never>? {
        guard checkInitialized() else { return nil }

        let (request, requestUser, revision, raisedIdentity) = automaticRequest(pageContext, newScreen: true)
        let target = AutomaticPresentationTarget(viewController)
        return Task {
            do {
                guard
                    let campaignIdsResponse = await repository.visit(
                        pageContext: pageContext,
                        options: options,
                        customerUser: requestUser,
                        identityGeneration: raisedIdentity.generation,
                        raisedIdentity: raisedIdentity
                    )
                else { return }
                try await handleCampaignIdsResponse(
                    campaignIdsResponse,
                    pageContext,
                    target,
                    request: request,
                    requestUser: requestUser,
                    revision: revision,
                    identityGeneration: raisedIdentity.generation
                )
            } catch {
                if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                GravityLogger.e(Self.TAG, "trackView error:  \(error)")
            }
        }
    }

    public func triggerEvent(
        events: [TriggerEvent],
        pageContext: PageContext,
        viewController: UIViewController? = nil
    ) {
        triggerEventTask(events: events, pageContext: pageContext, viewController: viewController)
    }

    @discardableResult
    internal func triggerEventTask(
        events: [TriggerEvent],
        pageContext: PageContext,
        viewController: UIViewController? = nil
    ) -> Task<Void, Never>? {
        guard checkInitialized() else { return nil }
        // The event happened now; events without their own eventTime are sent with it
        let raisedAt = Date()

        let (request, requestUser, revision, raisedIdentity) = automaticRequest(pageContext, newScreen: false)
        let target = AutomaticPresentationTarget(viewController)
        return Task {
            do {
                guard
                    let campaignIdsResponse = await repository.event(
                        events: events,
                        raisedAt: raisedAt,
                        pageContext: pageContext,
                        options: options,
                        customerUser: requestUser,
                        identityGeneration: raisedIdentity.generation,
                        raisedIdentity: raisedIdentity
                    )
                else { return }
                try await handleCampaignIdsResponse(
                    campaignIdsResponse,
                    pageContext,
                    target,
                    request: request,
                    requestUser: requestUser,
                    revision: revision,
                    identityGeneration: raisedIdentity.generation
                )
            } catch {
                if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                GravityLogger.e(Self.TAG, "triggerEvent error:  \(error)")
            }
        }
    }

    /// Tracks a screen and tries campaigns by descending priority until one has root content.
    /// Failed content requests are logged and skipped. Only the returned response emits
    /// ContentLoadEvent callbacks and configured onLoad tracking URLs, as getContent does.
    /// No UI or impression/visible-impression events are sent automatically.
    /// Returns immediately after loading; delayTime is the chosen campaign's
    /// nonnegative delay in milliseconds for the host to wait before rendering.
    /// The load callback observes the same delay; json remains the raw /choose body.
    /// Returns nil if tracking fails, no candidate yields content, or the request becomes
    /// stale or its identity changes; task cancellation throws CancellationError.
    public func trackViewNoShow(
        pageContext: PageContext
    ) async throws -> GravityDataResponse<ContentResponse>? {
        try await fetchCampaignWithoutPresentation(pageContext: pageContext, events: nil)
    }

    /// Sends events and resolves content with the same semantics as trackViewNoShow.
    /// Returns loaded content immediately with the chosen campaign's delayTime in
    /// milliseconds (zero when absent or negative). The host waits and renders it.
    public func triggerEventNoShow(
        events: [TriggerEvent],
        pageContext: PageContext
    ) async throws -> GravityDataResponse<ContentResponse>? {
        try await fetchCampaignWithoutPresentation(pageContext: pageContext, events: events)
    }

    private struct HeadlessRequest {
        let user: User?
        let identity: SessionManager.Snapshot
        let startedAt: TimeInterval
        let options: Options
    }

    private func isHeadlessRequestCurrent(_ request: HeadlessRequest) -> Bool {
        presentationGate.scoped {
            Self._instance === self && repository.sessionManager.isCurrent(request.identity.generation)
                && ProcessInfo.processInfo.systemUptime - request.startedAt <= staleContentTimeout
        }
    }

    private func fetchCampaignWithoutPresentation(
        pageContext: PageContext,
        events: [TriggerEvent]?
    ) async throws -> GravityDataResponse<ContentResponse>? {
        try Task.checkCancellation()
        guard checkInitialized(), Self._instance === self else { return nil }
        let raisedAt = Date()
        let request = presentationGate.scoped {
            HeadlessRequest(
                user: _user, identity: repository.sessionManager.snapshot(customUser: _user),
                startedAt: ProcessInfo.processInfo.systemUptime,
                options: options
            )
        }
        let response: CampaignIdsResponse?
        if let events {
            response = await repository.event(events: events, raisedAt: raisedAt,
                pageContext: pageContext, options: request.options, customerUser: request.user,
                raisedIdentity: request.identity)
        } else {
            response = await repository.visit(pageContext: pageContext,
                options: request.options, customerUser: request.user,
                raisedIdentity: request.identity)
        }
        try Task.checkCancellation()
        guard let response, isFetchContentOnTrack, isHeadlessRequestCurrent(request) else { return nil }

        let campaigns = response.campaigns.enumerated().sorted { lhs, rhs in
            let left = lhs.element.priority ?? 0
            let right = rhs.element.priority ?? 0
            return left == right ? lhs.offset < rhs.offset : left > right
        }
        for candidate in campaigns {
            try Task.checkCancellation()
            guard isFetchContentOnTrack, isHeadlessRequestCurrent(request) else { return nil }
            let result = await getContentByCampaignIdWithDetails(
                candidate.element.campaignId, pageContext,
                requestUser: request.user, identityGeneration: request.identity.generation,
                notifyContentLoaded: false
            )
            try Task.checkCancellation()
            guard isHeadlessRequestCurrent(request), isFetchContentOnTrack else { return nil }
            guard let result,
                  result.data.data.first?.payload.first?.contents.contains(where: { $0.step == nil }) == true
            else { continue }
            let accepted = GravityDataResponse(data: result.data, json: result.json,
                delayTime: candidate.element.delayTime ?? 0)
            // Acceptance is final before notifying the host, as in Flutter. Do not
            // suspend or recheck the deadline after emitting load side effects.
            for campaign in result.data.data {
                for payload in campaign.payload {
                    for content in payload.contents {
                        contentEventService.sendContentLoaded(content, campaign, delayTime: accepted.delayTime)
                    }
                }
            }
            return accepted
        }
        return nil
    }

    public func getContentBySelector(
        selector: String,
        pageContext: PageContext
    ) async -> ContentResponse? {
        await getContentBySelectorWithDetails(selector: selector, pageContext: pageContext)?.data
    }

    /// Same as `getContentBySelector`, plus the raw JSON of the same response,
    /// for rendering the content yourself. Does not show anything. delayTime is 0.
    public func getContentBySelectorWithDetails(
        selector: String,
        pageContext: PageContext
    ) async -> GravityDataResponse<ContentResponse>? {
        guard checkInitialized() else { return nil }

        let (requestUser, identityGeneration) = identitySnapshot()
        guard
            let response = await repository.chooseBySelectorWithDetails(
                selector: selector,
                options: options,
                contentSettings: contentSettings,
                customerUser: requestUser,
                pageContext: pageContext,
                identityGeneration: identityGeneration
            )
        else { return nil }

        guard repository.sessionManager.isCurrent(identityGeneration) else { return nil }
        await sendContentLoaded(response.data)
        guard repository.sessionManager.isCurrent(identityGeneration) else { return nil }
        return response
    }

    public func getContentByGroupSelector(
        groupSelector: String,
        pageContext: PageContext
    ) async -> ContentResponse? {
        guard checkInitialized() else { return nil }

        let (requestUser, identityGeneration) = identitySnapshot()
        guard
            let response = await repository.chooseByGroup(
                group: groupSelector,
                options: options,
                contentSettings: contentSettings,
                customerUser: requestUser,
                pageContext: pageContext,
                identityGeneration: identityGeneration
            )
        else { return nil }

        guard repository.sessionManager.isCurrent(identityGeneration) else { return nil }
        await sendContentLoaded(response)
        guard repository.sessionManager.isCurrent(identityGeneration) else { return nil }
        return response
    }

    private func handleCampaignIdsResponse(
        _ response: CampaignIdsResponse,
        _ pageContext: PageContext,
        _ target: AutomaticPresentationTarget,
        request: InAppPresentationGate.Request,
        requestUser: User?,
        revision: UInt64,
        identityGeneration: UInt64
    ) async throws {
        guard presentationGate.isCurrent(request), !response.campaigns.isEmpty else { return }
        if let store = visibleImpressionDelivery.store, !(await store.waitUntilLoaded()) {
            try Task.checkCancellation()
            GravityLogger.e(Self.TAG, "WRIMP restore timed out; automatic presentation request ended without a protection decision", sendToBack: false)
            return
        }
        try Task.checkCancellation()
        guard presentationGate.isCurrent(request) else { return }
        weak var targetViewController: UIViewController?
        if target.wasSupplied {
            targetViewController = target.viewController
        } else {
            targetViewController = await self.getTopViewController()
        }
        guard targetViewController != nil else { return }

        let sortedByPriority = response.campaigns.sorted {
            $0.priority ?? 0 > $1.priority ?? 0
        }

        for campaignId in sortedByPriority {
            guard presentationGate.isCurrent(request) else { return }
            guard let reservation = presentationGate.reserve(campaignId: campaignId.campaignId, request: request) else { continue }
            var shown = false
            defer { if !shown { presentationGate.cancel(reservation) } }
            guard
                let result = await getContentByCampaignId(
                    campaignId.campaignId,
                    pageContext,
                    requestUser: requestUser,
                    identityGeneration: identityGeneration
                )
            else { continue }

            guard let campaign = result.data.first,
                let payload = campaign.payload.first
            else {
                continue
            }

            let sortedContents = payload.contents.sorted { lhs, rhs in
                switch (lhs.step, rhs.step) {
                case let (lStep?, rStep?): return lStep < rStep
                case (nil, nil): return false
                case (nil, _): return true
                case (_, nil): return false
                }
            }
            guard let content = sortedContents.first else {
                continue
            }

            guard let elements = content.variables?.elements,
                !elements.isEmpty
            else {
                return
            }

            if let duration = campaignDelayNanoseconds(campaignId.delayTime) {
                let timing = campaignDelayTiming
                let sum = timing.now().addingReportingOverflow(duration)
                let deadline = sum.overflow ? UInt64.max : sum.partialValue
                while true {
                    let now = timing.now()
                    guard now < deadline else { break }
                    let interval = min(deadline - now, 100_000_000)
                    try await timing.sleep(interval)
                    // Invalidated waits release their reservation through defer,
                    // rather than retaining loaded content for the entire delay.
                    guard Self._instance === self,
                          presentationRevision.current == revision,
                          presentationGate.isCurrent(request), !isPresentationLocked,
                          repository.sessionManager.isCurrent(identityGeneration),
                          targetViewController != nil else { return }
                }
            }

            guard let targetViewController,
                  await isViewControllerActive(targetViewController) else {
                return
            }

            if isPresentationLocked {
                GravityLogger.i(
                    prefix: Self.TAG,
                    "Presentation is locked, skipped content for campaign \(campaignId.campaignId)"
                )
                return
            }

            try Task.checkCancellation()
            shown = await prepareAndShowBackendContent(
                targetViewController, content, campaign, revision: revision,
                reservation: reservation, contentIds: payload.contents.map { $0.contentId }
            )
            if shown { return }
        }
    }

    @MainActor private func prepareAndShowBackendContent(
        _ viewController: UIViewController,
        _ content: CampaignContent,
        _ campaign: Campaign,
        revision: UInt64,
        reservation: InAppPresentationGate.Reservation? = nil,
        contentIds: [String] = [],
        impressionSession: ModalImpressionSession? = nil,
        item: Item? = nil
    ) async -> Bool {
        guard canPresent(viewController, revision: revision) else { return false }

        guard let prepared = await Self.resolvedContent(content, campaign, preparation: inAppPreparation) else {
            GravityLogger.i(prefix: Self.TAG, "In-app preparation skipped content \(content.contentId)")
            return false
        }

        // Revalidate on the UI actor immediately before presenting, after the asynchronous work.
        guard canPresent(viewController, revision: revision) else { return false }
        if let reservation {
            guard !viewController.isBeingPresented,
                  prepared.deliveryMethod == .snackBar || viewController.presentedViewController == nil else { return false }
            return presentationGate.present(reservation, contentIds: contentIds) {
                self.showBackendContent(viewController, prepared, campaign, impressionSession: impressionSession, item: item)
            }
        }
        return showBackendContent(viewController, prepared, campaign, impressionSession: impressionSession, item: item)
    }

    /// Without a preparation handler, campaigns pass through unchanged — existing campaigns and
    /// `productFilter` keep their current behavior. Extracted as a pure, static function so the
    /// no-handler passthrough and the delegation to `InAppPreparation.prepare` are directly
    /// testable without the surrounding network/presentation pipeline.
    internal static func resolvedContent(
        _ content: CampaignContent,
        _ campaign: Campaign,
        preparation: InAppPreparation?
    ) async -> CampaignContent? {
        guard let preparation else { return content }
        return await preparation.prepare(content, campaign)
    }

    @MainActor private func canPresent(_ viewController: UIViewController, revision: UInt64) -> Bool {
        GravitySDK.instance === self && presentationRevision.canPresent(expected: revision,
            active: isViewControllerActive(viewController), locked: isPresentationLocked,
            cancelled: Task.isCancelled)
    }

    public func sendContentEngagement(engagement: ContentEngagement) {
        guard checkInitialized() else { return }

        switch engagement {
        case let engagement as ContentImpressionEngagement:
            contentEventService.sendContentImpression(
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false
            )
        case let engagement as ContentVisibleImpressionEngagement:
            contentEventService.sendContentVisibleImpression(
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false
            )
        case let engagement as ContentCloseEngagement:
            contentEventService.sendContentClosed(
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false
            )
        default:
            break
        }
    }

    public func sendProductEngagement(engagement: ProductEngagement) {
        guard checkInitialized() else { return }

        switch engagement {
        case let engagement as ProductClickEngagement:
            productEventService.sendProductClick(
                engagement.slot,
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false
            )
        case let engagement as ProductVisibleImpressionEngagement:
            productEventService.sendProductVisibleImpression(
                engagement.slot,
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false
            )
        default:
            break
        }
    }

    /// Closes the visible SDK in-app with this contentId. Completion runs on the UI thread
    /// after dismissal; false means no matching presentation was available. Inline widgets are unaffected.
    public func dismissInApp(contentId: String, completion: @escaping (Bool) -> Void = { _ in }) {
        guard checkInitialized() else {
            Task { @MainActor in completion(false) }
            return
        }
        Task { @MainActor in
            self.inAppPresentations.dismiss(contentId: contentId, completion: completion)
        }
    }

    @MainActor private func registerInApp(
        _ content: CampaignContent, _ campaign: Campaign,
        impressionSession: ModalImpressionSession? = nil,
        shouldTrackClose: @escaping () -> Bool = { true },
        performDismiss: @escaping (@escaping (Bool) -> Void) -> Void
    ) -> InAppPresentation {
        weak var registered: InAppPresentation?
        let presentation = InAppPresentation(willClose: {
            impressionSession?.explicitClose()
        }, performDismiss: performDismiss) { [weak self] success in
            guard let self = self else { return }
            self.inAppPresentations.remove(registered, contentId: content.contentId)
            if success && shouldTrackClose() { self.contentEventService.sendContentClosed(content, campaign) }
            else { self.presentationGate.closed(contentId: content.contentId) }
        }
        registered = presentation
        inAppPresentations.register(presentation, contentId: content.contentId)
        return presentation
    }

    public func getContentByCampaignId(
        _ campaignId: String,
        _ pageContext: PageContext
    ) async -> ContentResponse? {
        await getContentByCampaignIdWithDetails(campaignId, pageContext)?.data
    }

    /// Same as `getContentByCampaignId`, plus the raw JSON of the same response,
    /// for rendering the content yourself. Does not show anything. delayTime is 0.
    public func getContentByCampaignIdWithDetails(
        _ campaignId: String,
        _ pageContext: PageContext
    ) async -> GravityDataResponse<ContentResponse>? {
        let (requestUser, identityGeneration) = identitySnapshot()
        return await getContentByCampaignIdWithDetails(campaignId, pageContext,
            requestUser: requestUser, identityGeneration: identityGeneration)
    }

    private func getContentByCampaignId(
        _ campaignId: String,
        _ pageContext: PageContext,
        requestUser: User?,
        identityGeneration: UInt64
    ) async -> ContentResponse? {
        await getContentByCampaignIdWithDetails(campaignId, pageContext,
            requestUser: requestUser, identityGeneration: identityGeneration)?.data
    }

    private func getContentByCampaignIdWithDetails(
        _ campaignId: String,
        _ pageContext: PageContext,
        requestUser: User?,
        identityGeneration: UInt64,
        notifyContentLoaded: Bool = true
    ) async -> GravityDataResponse<ContentResponse>? {
        guard checkInitialized() else { return nil }

        guard
            let response = await repository.chooseByCampaignIdWithDetails(
                campaignId: campaignId,
                options: options,
                contentSettings: contentSettings,
                customerUser: requestUser,
                pageContext: pageContext,
                identityGeneration: identityGeneration
            )
        else { return nil }

        guard repository.sessionManager.isCurrent(identityGeneration) else { return nil }
        if notifyContentLoaded { await sendContentLoaded(response.data) }
        guard repository.sessionManager.isCurrent(identityGeneration) else { return nil }
        return response
    }

    private func sendContentLoaded(_ response: ContentResponse) async {
        await withTaskGroup(of: Void.self) { group in
            for campaign in response.data {
                for payload in campaign.payload {
                    for content in payload.contents {
                        group.addTask {
                            self.contentEventService.sendContentLoaded(
                                content,
                                campaign
                            )
                        }
                    }
                }
            }
        }
    }

    @discardableResult
    @MainActor internal func showBackendContent(
        _ viewController: UIViewController,
        _ content: CampaignContent,
        _ campaign: Campaign,
        impressionSession: ModalImpressionSession? = nil,
        item: Item? = nil
    ) -> Bool {
        let opening = impressionSession ?? makeModalImpressionSession(content, campaign)
        switch content.deliveryMethod {
        case .fullScreen: showFullScreen(content, campaign, viewController, impressionSession: opening, item: item)
        case .modal: showModal(content, campaign, viewController, impressionSession: opening, item: item)
        case .bottomSheet: showBottomSheet(content, campaign, viewController, impressionSession: opening, item: item)
        case .snackBar:
            guard let template = content.templateSystemName, template != .unknown,
                  content.variables?.frameUI != nil, viewController.viewIfLoaded?.window != nil else { return false }
            showSnackbar(content, campaign, viewController, impressionSession: opening)
        case .inline, .unknown: return false
        }
        return true
    }

    @MainActor internal func makeModalImpressionSession(
        _ content: CampaignContent, _ campaign: Campaign
    ) -> ModalImpressionSession {
        let identityGeneration = presentationGate.scoped { repository.sessionManager.generation }
        let openingId = UUID()
        return ModalImpressionSession(confirm: { [self] in
            presentationGate.scoped {
                guard repository.sessionManager.isCurrent(identityGeneration) else { return false }
                return contentEventService.sendModalVisibleImpression(content, campaign, sdk: self,
                    openingId: openingId, scope: impressionScope)
            }
        }, release: { [weak self] in self?.presentationGate.closed(contentId: content.contentId) }, valid: { [weak self] in
            guard let self else { return false }
            return self.presentationGate.scoped {
                self.repository.sessionManager.isCurrent(identityGeneration)
            }
        })
    }

    @MainActor private func showFullScreen(
        _ content: CampaignContent,
        _ campaign: Campaign,
        _ viewController: UIViewController,
        impressionSession: ModalImpressionSession,
        item: Item? = nil
    ) {
        weak var presentedController: UIViewController?
        let presentation = registerInApp(content, campaign, impressionSession: impressionSession) { complete in
            guard let controller = presentedController, controller.presentingViewController != nil else {
                complete(false); return
            }
            controller.dismiss(animated: true) { complete(true) }
        }
        func dismiss() {
            presentation.close()
        }

        let fullScreenView = GravityFullScreenContent(
            content: content,
            campaign: campaign,
            impressionSession: impressionSession,
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    viewController: viewController,
                    impressionSession: impressionSession,
                    dismissCallback: dismiss
                )
            },
            item: item
        )

        let hostingController = UIHostingController(rootView: fullScreenView)
        presentedController = hostingController
        hostingController.modalPresentationStyle = .fullScreen

        viewController.present(hostingController, animated: true)
    }

    @MainActor private func showModal(
        _ content: CampaignContent,
        _ campaign: Campaign,
        _ viewController: UIViewController,
        impressionSession: ModalImpressionSession,
        item: Item? = nil
    ) {
        weak var presentedController: UIViewController?
        let presentation = registerInApp(content, campaign, impressionSession: impressionSession) { complete in
            guard let controller = presentedController, controller.presentingViewController != nil else {
                complete(false); return
            }
            controller.dismiss(animated: true) { complete(true) }
        }
        func dismiss() {
            presentation.close()
        }

        let modalView = GravityModalContent(
            content: content,
            campaign: campaign,
            impressionSession: impressionSession,
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    viewController: viewController,
                    impressionSession: impressionSession,
                    dismissCallback: dismiss
                )
            },
            onDismiss: dismiss,
            item: item
        )

        let hostingController = UIHostingController(rootView: modalView)
        presentedController = hostingController
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.modalTransitionStyle = .crossDissolve
        hostingController.view.backgroundColor = .clear

        viewController.present(hostingController, animated: true)
    }

    @MainActor private func showBottomSheet(
        _ content: CampaignContent,
        _ campaign: Campaign,
        _ viewController: UIViewController,
        impressionSession: ModalImpressionSession,
        item: Item? = nil
    ) {
        var requestClose: (() -> Void)?
        weak var presentedController: UIViewController?
        var animationFinished = false
        var pendingCompletion: ((Bool) -> Void)?
        let presentation = registerInApp(content, campaign, impressionSession: impressionSession) { complete in
            guard let controller = presentedController, controller.presentingViewController != nil else {
                complete(false); return
            }
            if !animationFinished, let close = requestClose {
                pendingCompletion = complete
                close()
            } else {
                controller.dismiss(animated: false) { complete(true) }
            }
        }

        func finishDismiss() {
            animationFinished = true
            if let complete = pendingCompletion {
                pendingCompletion = nil
                guard let controller = presentedController, controller.presentingViewController != nil else {
                    complete(false); return
                }
                controller.dismiss(animated: false) { complete(true) }
            } else {
                // Drag/backdrop dismissal has already finished the sheet animation.
                presentation.close()
            }
        }

        let fullScreenView = GravityBottomSheetContent(
            content: content,
            campaign: campaign,
            impressionSession: impressionSession,
            onBindClose: { requestClose = $0 },
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    viewController: viewController,
                    impressionSession: impressionSession,
                    dismissCallback: { presentation.close() }
                )
            },
            onDismiss: finishDismiss,
            item: item
        )

        let hostingController = UIHostingController(rootView: fullScreenView)
        presentedController = hostingController
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = .clear

        viewController.present(hostingController, animated: false)
    }

    @MainActor private func showSnackbar(
        _ content: CampaignContent,
        _ campaign: Campaign,
        _ viewController: UIViewController,
        impressionSession: ModalImpressionSession
    ) {
        let template = content.templateSystemName
        if template == nil || template == TemplateSystemName.unknown { return }

        weak var weakHostingController:
            UIHostingController<GravitySnackbarContent>?

        var hasAppeared = false
        let presentation = registerInApp(content, campaign, impressionSession: impressionSession,
            shouldTrackClose: { hasAppeared }) { complete in
            guard let hostingController = weakHostingController,
                  hostingController.view.superview != nil else { complete(false); return }
            hostingController.willMove(toParent: nil)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
            complete(true)
        }
        func dismiss() {
            presentation.close()
        }

        let snackbarView = GravitySnackbarContent(
            content: content,
            campaign: campaign,
            impressionSession: impressionSession,
            visibilityClock: presentationTiming.now,
            onImpression: { hasAppeared = true },
            onClickCallback: { onClickModel in
                guard presentation.isOpen else { return }
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    viewController: viewController,
                    impressionSession: impressionSession,
                    closeTrackedOnDismiss: true,
                    dismissCallback: dismiss
                )
            },
            onDismiss: dismiss
        )

        let hostingController = UIHostingController(rootView: snackbarView)
        weakHostingController = hostingController

        guard let view = viewController.view else { return }

        viewController.addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leftAnchor.constraint(
                equalTo: view.leftAnchor,
                constant: 16
            ),
            hostingController.view.rightAnchor.constraint(
                equalTo: view.rightAnchor,
                constant: -16
            ),
            hostingController.view.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            )
        ])

        hostingController.didMove(toParent: viewController)
    }

    internal func onClickHandler(
        onClickModel: OnClickModel,
        content: CampaignContent,
        campaign: Campaign,
        viewController: UIViewController,
        impressionSession: ModalImpressionSession? = nil,
        closeTrackedOnDismiss: Bool = false,
        dismissCallback: (() -> Void)? = nil
    ) {
        let action = onClickModel.action
        let closeOnClick = onClickModel.closeOnClick

        if !(closeTrackedOnDismiss && action == .close && content.variables?.onClose?.action == .close) {
            trackEngagementEvent(action, content.events)
        }

        if action != .close && closeOnClick {
            dismissCallback?()
        }

        switch action {
        case .copy:
            guard let textToCopy = onClickModel.copyData else { return }
            let pasteboard = UIPasteboard.general
            pasteboard.string = textToCopy

            callbackTrackingEvent(
                CopyEvent(
                    copiedValue: textToCopy,
                    content: content,
                    campaign: campaign
                )
            )

        case .close:
            dismissCallback?()

        case .cancel:
            dismissCallback?()

            callbackTrackingEvent(
                CancelEvent(content: content, campaign: campaign)
            )

        case .followUrl:
            guard let url = onClickModel.url else { return }
            let type = onClickModel.type ?? .browser

            callbackTrackingEvent(
                FollowUrlEvent(
                    url: url,
                    type: type,
                    content: content,
                    campaign: campaign
                )
            )

        case .followDeeplink:
            guard let deeplink = onClickModel.deeplink else { return }

            callbackTrackingEvent(
                FollowDeeplinkEvent(
                    deeplink: deeplink,
                    content: content,
                    campaign: campaign
                )
            )

        case .requestPush:
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.requestAuthorization(options: [
                .alert, .sound, .badge
            ]) {
                granted,
                error in
                DispatchQueue.main.async {
                    if !granted {
                        UIApplication.shared.registerForRemoteNotifications()

                        if let settingsUrl = URL(
                            string: UIApplication.openSettingsURLString
                        ) {
                            UIApplication.shared.open(settingsUrl)
                        }
                    }
                }
            }

            callbackTrackingEvent(
                RequestPushEvent(content: content, campaign: campaign)
            )

        case .openStep:
            guard let nextStep = onClickModel.step,
                let targetContent = campaign.payload.first?.contents.first(
                    where: { $0.step == nextStep }
                )
            else { return }

            let item: Item?
            if let itemId = onClickModel.itemId {
                item = content.items?.first(where: { $0.id == itemId })
            } else {
                item = nil
            }

            if isPresentationLocked {
                GravityLogger.i(
                    prefix: Self.TAG,
                    "Presentation is locked, skipped content for campaign \(campaign.payload.first?.campaignId ?? "unknown")"
                )
                return
            }

            let revision = presentationRevision.current
            Task { @MainActor in
                await self.prepareAndShowBackendContent(
                    viewController,
                    targetContent,
                    campaign,
                    revision: revision,
                    impressionSession: impressionSession,
                    item: item
                )
            }

        @unknown default:
            break
        }
    }

    private func trackEngagementEvent(_ action: Action, _ events: [Event]?) {
        guard let event = events?.first(where: { $0.type == action }) else {
            return
        }

        Task {
            do {
                try await repository.trackEngagementEvent(urls: event.urls)
            } catch {}
        }
    }

    internal func callbackTrackingEvent(_ event: TrackingEvent) {
        Task {
            await MainActor.run {
                gravityEventCallback?(event)
            }
        }
    }

    @MainActor private func isViewControllerActive(_ viewController: UIViewController) -> Bool {
        viewController.view.window != nil
            && !viewController.isBeingDismissed
            && !viewController.isMovingFromParent
    }

    @MainActor private func getTopViewController() -> UIViewController? {
        guard
            let windowScene = UIApplication.shared.connectedScenes.first
                as? UIWindowScene,
            let rootViewController = windowScene.windows.first(where: {
                $0.isKeyWindow
            })?.rootViewController
        else {
            return nil
        }

        var topController = rootViewController
        while let presentedViewController = topController
            .presentedViewController
        {
            topController = presentedViewController
        }
        return topController
    }
    
    @discardableResult
    private func checkInitialized(_ caller: String = #function) -> Bool {
        guard Self.isInitialized else {
            GravityLogger.e(
                Self.TAG,
                "\(caller) called before GravitySDK.initialize() — call ignored",
                sendToBack: false
            )
            return false
        }
        return true
    }
}

/// Converts a campaign delay in milliseconds for Task.sleep. Missing, zero and
/// negative delays mean no wait; positive values saturate to the maximum supported
/// sleep (Int64.max ns). Older supported iOS runtimes return immediately for larger
/// nanosecond durations, so even nonoverflowing UInt64 values must be capped.
internal func campaignDelayNanoseconds(_ delayTime: Int?) -> UInt64? {
    guard let delayTime, delayTime > 0 else { return nil }
    let (nanoseconds, overflow) = UInt64(delayTime).multipliedReportingOverflow(by: 1_000_000)
    let cap = UInt64(Int64.max)
    return overflow ? cap : min(nanoseconds, cap)
}
