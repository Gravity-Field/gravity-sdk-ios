import Foundation
import SwiftUI
import UIKit

public typealias ProductFilter = (Slot) -> Bool
public typealias GravityEventCallback = (TrackingEvent) -> Void

public class GravitySDK {
    internal let apiKey: String
    internal let section: String
    private let gravityEventCallback: GravityEventCallback
    internal let productViewBuilder: ProductViewBuilder?
    internal let productFilter: ProductFilter?

    private init(
        apiKey: String,
        section: String,
        gravityEventCallback: @escaping GravityEventCallback,
        productViewBuilder: ProductViewBuilder?,
        productFilter: ProductFilter?
    ) {
        self.apiKey = apiKey
        self.section = section
        self.gravityEventCallback = gravityEventCallback
        self.productViewBuilder = productViewBuilder
        self.productFilter = productFilter
    }

    private static var _instance: GravitySDK?

    public static var instance: GravitySDK {
        guard let instance = _instance else {
            fatalError("GravitySDK has not been initialized")
        }
        return instance
    }

    public static func initialize(
        apiKey: String,
        section: String,
        gravityEventCallback: @escaping GravityEventCallback,
        productViewBuilder: ProductViewBuilder? = nil,
        productFilter: ProductFilter? = nil,
        logLevel: LogLevel = .none
    ) {
        GravityLogger.configure(logLevel)
        _instance = GravitySDK(
            apiKey: apiKey,
            section: section,
            gravityEventCallback: gravityEventCallback,
            productViewBuilder: productViewBuilder,
            productFilter: productFilter
        )
    }

    private var user: User?
    private var options = Options()
    private var contentSettings = ContentSettings()
    internal var proxyUrl: String?
    internal var notificationPermissionStatus = NotificationPermissionStatus
        .unknown

    private let repository = GravityRepository.instance
    private let contentEventService = ContentEventService.instance
    private let productEventService = ProductEventService.instance

    public func setOptions(
        options: Options?,
        contentSettings: ContentSettings?,
        proxyUrl: String?
    ) {
        self.options = options ?? Options()
        self.contentSettings = contentSettings ?? ContentSettings()
        self.proxyUrl = proxyUrl
    }

    public func setUser(userId: String, sessionId: String) {
        user = User(custom: userId, ses: sessionId)
    }

    public func setNotificationPermissionStatus(
        status: NotificationPermissionStatus
    ) {
        notificationPermissionStatus = status
    }

    public func trackView(
        pageContext: PageContext,
        viewController: UIViewController? = nil,
    ) {
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
                    viewController
                )
            } catch {}
        }
    }

    public func triggerEvent(
        events: [TriggerEvent],
        pageContext: PageContext,
        viewController: UIViewController? = nil,
    ) {
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
                    viewController
                )
            } catch {}
        }
    }

    public func getContentBySelector(
        selector: String,
        pageContext: PageContext
    ) async -> ContentResponse? {
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

    private func handleCampaignIdsResponse(
        _ response: CampaignIdsResponse,
        _ pageContext: PageContext,
        _ viewController: UIViewController? = nil
    ) async throws {
        guard let viewController = viewController ?? self.getTopViewController()
        else {
            return
        }

        let sortedByPriority = response.campaigns.sorted {
            $0.priority ?? 0 > $1.priority ?? 0
        }

        for campaignId in sortedByPriority {
            guard
                let result = await getContentByCampaignId(
                    campaignId.campaignId,
                    pageContext
                )
            else { continue }

            guard let campaign = result.data.first,
                let payload = campaign.payload.first,
                let content = payload.contents.first(where: { $0.step != nil })
                    ?? payload.contents.first
            else {
                continue
            }

            if let delayTime = campaignId.delayTime {
                try? await Task.sleep(
                    nanoseconds: UInt64(delayTime) * 1_000_000
                )
            }

            guard viewController.view.window != nil,
                await !viewController.isBeingDismissed,
                await !viewController.isMovingFromParent
            else {
                return
            }

            await MainActor.run {
                showBackendContent(viewController, content, campaign)
            }
        }
    }

    public func sendContentEngagement(engagement: ContentEngagement) {
        switch engagement {
        case let engagement as ContentImpressionEngagement:
            contentEventService.sendContentImpression(
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false,
            )
        case let engagement as ContentVisibleImpressionEngagement:
            contentEventService.sendContentVisibleImpression(
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false,
            )
        case let engagement as ContentCloseEngagement:
            contentEventService.sendContentClosed(
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false,
            )
        default:
            break
        }
    }

    public func sendProductEngagement(engagement: ProductEngagement) {
        switch engagement {
        case let engagement as ProductClickEngagement:
            productEventService.sendProductClick(
                engagement.slot,
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false,
            )
        case let engagement as ProductVisibleImpressionEngagement:
            productEventService.sendProductVisibleImpression(
                engagement.slot,
                engagement.content,
                engagement.campaign,
                callbackTrackingEvent: false,
            )
        default:
            break
        }
    }

    public func getContentByCampaignId(
        _ campaignId: String,
        _ pageContext: PageContext
    ) async -> ContentResponse? {
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

    public func showBackendContent(
        _ viewController: UIViewController,
        _ content: CampaignContent,
        _ campaign: Campaign,
    ) {
        switch content.deliveryMethod {
        case .fullScreen: showFullScreen(content, campaign, viewController)
        case .modal: showModal(content, campaign, viewController)
        case .bottomSheet: showBottomSheet(content, campaign, viewController)
        case .snackBar: showSnackbar(content, campaign, viewController)
        case .inline: break
        case .unknown: break
        }
    }

    private func showFullScreen(
        _ content: CampaignContent,
        _ campaign: Campaign,
        _ viewController: UIViewController
    ) {
        func dismiss() {
            viewController.dismiss(animated: true)
        }

        let fullScreenView = GravityFullScreenContent(
            content: content,
            campaign: campaign,
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    dismissCallback: dismiss,
                )
            }
        )

        let hostingController = UIHostingController(rootView: fullScreenView)
        hostingController.modalPresentationStyle = .fullScreen

        viewController.present(hostingController, animated: true)
    }

    private func showModal(
        _ content: CampaignContent,
        _ campaign: Campaign,
        _ viewController: UIViewController
    ) {
        func dismiss() {
            viewController.dismiss(animated: true)
        }

        let modalView = GravityModalContent(
            content: content,
            campaign: campaign,
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    dismissCallback: dismiss,
                )
            },
            onDismiss: dismiss
        )

        let hostingController = UIHostingController(rootView: modalView)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.modalTransitionStyle = .crossDissolve
        hostingController.view.backgroundColor = .clear

        viewController.present(hostingController, animated: true)
    }

    private func showBottomSheet(
        _ content: CampaignContent,
        _ campaign: Campaign,
        _ viewController: UIViewController,
    ) {
        var hostingController: UIHostingController<GravityBottomSheetContent>? =
            nil

        func dismiss() {
            UIView.animate(
                withDuration: 0.3,
                animations: {
                    hostingController?.view.alpha = 0
                },
                completion: { _ in
                    viewController.dismiss(animated: false)
                }
            )
        }

        let fullScreenView = GravityBottomSheetContent(
            content: content,
            campaign: campaign,
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    dismissCallback: dismiss,
                )
            },
            onDismiss: dismiss
        )

        hostingController = UIHostingController(rootView: fullScreenView)

        guard let hostingController = hostingController else { return }

        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = .clear
        hostingController.view.alpha = 0

        viewController.present(hostingController, animated: false) {
            UIView.animate(withDuration: 0.3) {
                hostingController.view.alpha = 1
            }
        }
    }

    private func showSnackbar(
        _ content: CampaignContent,
        _ campaign: Campaign,
        _ viewController: UIViewController,
    ) {
        let template = content.templateSystemName
        if template == nil || template == TemplateSystemName.unknown { return }

        var controllerView: UIView? = nil
        var hostingController: UIHostingController<GravitySnackbarContent>? =
            nil

        func dismiss() {
            controllerView?.removeFromSuperview()
        }

        let snackbarView = GravitySnackbarContent(
            content: content,
            campaign: campaign,
            onClickCallback: { onClickModel in
                self.onClickHandler(
                    onClickModel: onClickModel,
                    content: content,
                    campaign: campaign,
                    dismissCallback: dismiss,
                )
            },
            onDismiss: dismiss
        )
        hostingController = UIHostingController(rootView: snackbarView)

        guard let hostingController = hostingController else { return }

        controllerView = hostingController.view
        let view = viewController.view!

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        viewController.view.addSubview(hostingController.view)

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
            ),
        ])
    }

    internal func onClickHandler(
        onClickModel: OnClickModel,
        content: CampaignContent,
        campaign: Campaign,
        dismissCallback: (() -> Void)? = nil
    ) {
        let action = onClickModel.action
        let closeOnClick = onClickModel.closeOnClick ?? true

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
                .alert, .sound, .badge,
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
                gravityEventCallback(event)
            }
        }
    }

    private func getTopViewController() -> UIViewController? {
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
}
