import Foundation
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
    private let presentationRevision = PresentationRevision()
    private let inAppPresentations = InAppPresentationRegistry()

    private init(
        apiKey: String,
        section: String,
        gravityEventCallback: GravityEventCallback?,
        productViewBuilder: ProductViewBuilder?,
        productFilter: ProductFilter?,
        uiSettings: UISettings?,
        inAppPreparation: InAppPreparation? = nil
    ) {
        self.apiKey = apiKey
        self.section = section
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
    }

    private static var _instance: GravitySDK?

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
        _instance = GravitySDK(
            apiKey: apiKey,
            section: section,
            gravityEventCallback: gravityEventCallback,
            productViewBuilder: productViewBuilder,
            productFilter: productFilter,
            uiSettings: uiSettings,
            inAppPreparation: inAppPreparation
        )
    }

    internal var user: User?
    private var options = Options()
    private var contentSettings = ContentSettings()
    internal var logListener: GravityLogListener?
    internal var proxyUrl: String?
    internal var notificationPermissionStatus = NotificationPermissionStatus
        .unknown

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

        user = User(custom: userId, ses: sessionId)
        presentationRevision.invalidate()
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
        guard checkInitialized() else { return }

        let revision = presentationRevision.current

        Task {
            do {
                guard
                    let campaignIdsResponse = await repository.visit(
                        pageContext: pageContext,
                        options: options,
                        customerUser: user
                    )
                else { return }
                try await handleCampaignIdsResponse(
                    campaignIdsResponse,
                    pageContext,
                    viewController,
                    revision: revision
                )
            } catch {
                GravityLogger.e(Self.TAG, "trackView error:  \(error)")
            }
        }
    }

    public func triggerEvent(
        events: [TriggerEvent],
        pageContext: PageContext,
        viewController: UIViewController? = nil
    ) {
        guard checkInitialized() else { return }

        let revision = presentationRevision.current

        Task {
            do {
                guard
                    let campaignIdsResponse = await repository.event(
                        events: events,
                        pageContext: pageContext,
                        options: options,
                        customerUser: user
                    )
                else { return }
                try await handleCampaignIdsResponse(
                    campaignIdsResponse,
                    pageContext,
                    viewController,
                    revision: revision
                )
            } catch {
                GravityLogger.e(Self.TAG, "triggerEvent error:  \(error)")
            }
        }
    }

    public func getContentBySelector(
        selector: String,
        pageContext: PageContext
    ) async -> ContentResponse? {
        guard checkInitialized() else { return nil }

        guard
            let response = await repository.chooseBySelector(
                selector: selector,
                options: options,
                contentSettings: contentSettings,
                pageContext: pageContext
            )
        else { return nil }

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

        return response
    }

    public func getContentByGroupSelector(
        groupSelector: String,
        pageContext: PageContext
    ) async -> ContentResponse? {
        guard checkInitialized() else { return nil }

        guard
            let response = await repository.chooseByGroup(
                group: groupSelector,
                options: options,
                contentSettings: contentSettings,
                pageContext: pageContext
            )
        else { return nil }

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

        return response
    }

    private func handleCampaignIdsResponse(
        _ response: CampaignIdsResponse,
        _ pageContext: PageContext,
        _ viewController: UIViewController? = nil,
        revision: UInt64
    ) async throws {
        let targetViewController: UIViewController?
        if let viewController {
            targetViewController = viewController
        } else {
            targetViewController = await self.getTopViewController()
        }
        guard let targetViewController = targetViewController else {
            return
        }

        let sortedByPriority = response.campaigns.sorted {
            $0.priority ?? 0 > $1.priority ?? 0
        }

        for campaignId in sortedByPriority {
            guard presentationRevision.current == revision else { return }
            guard
                let result = await getContentByCampaignId(
                    campaignId.campaignId,
                    pageContext
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

            if let delayTime = campaignId.delayTime {
                try? await Task.sleep(
                    nanoseconds: UInt64(delayTime) * 1_000_000
                )
            }

            guard await isViewControllerActive(targetViewController) else {
                return
            }

            if isPresentationLocked {
                GravityLogger.i(
                    prefix: Self.TAG,
                    "Presentation is locked, skipped content for campaign \(campaignId.campaignId)"
                )
                return
            }

            if await prepareAndShowBackendContent(
                targetViewController, content, campaign, revision: revision
            ) {
                return
            }
        }
    }

    @MainActor private func prepareAndShowBackendContent(
        _ viewController: UIViewController,
        _ content: CampaignContent,
        _ campaign: Campaign,
        revision: UInt64,
        item: Item? = nil
    ) async -> Bool {
        guard canPresent(viewController, revision: revision) else { return false }

        let prepared: CampaignContent
        if let preparation = inAppPreparation {
            guard let result = await preparation.prepare(content, campaign) else {
                GravityLogger.i(prefix: Self.TAG, "In-app preparation skipped content \(content.contentId)")
                return false
            }
            prepared = result
        } else {
            prepared = content
        }

        // Revalidate on the UI actor immediately before presenting, after the asynchronous work.
        guard canPresent(viewController, revision: revision) else { return false }
        showBackendContent(viewController, prepared, campaign, item: item)
        return true
    }

    @MainActor private func canPresent(_ viewController: UIViewController, revision: UInt64) -> Bool {
        presentationRevision.canPresent(expected: revision,
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
        performDismiss: @escaping (@escaping (Bool) -> Void) -> Void
    ) -> InAppPresentation {
        weak var registered: InAppPresentation?
        let presentation = InAppPresentation(performDismiss: performDismiss) { [weak self] success in
            guard let self = self else { return }
            self.inAppPresentations.remove(registered, contentId: content.contentId)
            if success { self.contentEventService.sendContentClosed(content, campaign) }
        }
        registered = presentation
        inAppPresentations.register(presentation, contentId: content.contentId)
        return presentation
    }

    public func getContentByCampaignId(
        _ campaignId: String,
        _ pageContext: PageContext
    ) async -> ContentResponse? {
        guard checkInitialized() else { return nil }

        guard
            let response = await repository.chooseByCampaignId(
                campaignId: campaignId,
                options: options,
                contentSettings: contentSettings,
                pageContext: pageContext
            )
        else { return nil }

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

        return response
    }

    @MainActor private func showBackendContent(
        _ viewController: UIViewController,
        _ content: CampaignContent,
        _ campaign: Campaign,
        item: Item? = nil
    ) {
        switch content.deliveryMethod {
        case .fullScreen: showFullScreen(content, campaign, viewController, item: item)
        case .modal: showModal(content, campaign, viewController, item: item)
        case .bottomSheet: showBottomSheet(content, campaign, viewController, item: item)
        case .snackBar: showSnackbar(content, campaign, viewController)
        case .inline: break
        case .unknown: break
        }
    }

    @MainActor private func showFullScreen(
        _ content: CampaignContent,
        _ campaign: Campaign,
        _ viewController: UIViewController,
        item: Item? = nil
    ) {
        weak var presentedController: UIViewController?
        let presentation = registerInApp(content, campaign) { complete in
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
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    viewController: viewController,
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
        item: Item? = nil
    ) {
        weak var presentedController: UIViewController?
        let presentation = registerInApp(content, campaign) { complete in
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
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    viewController: viewController,
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
        item: Item? = nil
    ) {
        var requestClose: (() -> Void)?
        weak var presentedController: UIViewController?
        var animationFinished = false
        var pendingCompletion: ((Bool) -> Void)?
        let presentation = registerInApp(content, campaign) { complete in
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
            onBindClose: { requestClose = $0 },
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    viewController: viewController,
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
        _ viewController: UIViewController
    ) {
        let template = content.templateSystemName
        if template == nil || template == TemplateSystemName.unknown { return }

        weak var weakHostingController:
            UIHostingController<GravitySnackbarContent>?

        let presentation = registerInApp(content, campaign) { complete in
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
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    viewController: viewController,
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
        dismissCallback: (() -> Void)? = nil
    ) {
        let action = onClickModel.action
        let closeOnClick = onClickModel.closeOnClick

        trackEngagementEvent(action, content.events)

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
            guard let url = onClickModel.url,
                let type = onClickModel.type
            else { return }

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
