import Foundation
import SwiftUI

/// Assistant greeting from the campaign matched by `assistantSelector`.
internal struct AssistantStartScreen: Equatable {
    let title: String
    let subtitle: String
    let suggests: [String]
}

/// User identity and page context sent with questions. Fixed on the first question of a dialog.
internal struct AssistantDialogContext {
    /// Canonical Gravity uid, not the id passed to `setUser`.
    let uid: String
    let pageContext: PageContext

    /// Campaign of the start screen, reported in dialog analytics.
    let campaignId: String?

    /// User on whose behalf dialog events are sent, with the canonical `uid`.
    let eventUser: User
}

/// Result of the latest successful preparation: the start screen and the context for the next dialog.
internal struct AssistantConfig {
    let startScreen: AssistantStartScreen
    let context: AssistantDialogContext
}

/// Outcome of a product action check: the result for the app, the action for the handler,
/// and whether to close the chat first.
internal struct AssistantProductActionPlan {
    let result: AssistantInteractionResult
    let action: AssistantAction?
    let closeChat: Bool

    init(result: AssistantInteractionResult, action: AssistantAction? = nil, closeChat: Bool = false) {
        self.result = result
        self.action = action
        self.closeChat = closeChat
    }
}

/// Assistant preparation and dialog state. Preparation only affects the start screen;
/// an ongoing dialog keeps its own context.
@MainActor
internal final class AssistantController: ObservableObject {

    private static let TAG = "Assistant"
    private static let defaultTitle = "Помощник"

    private static let eventClick = "click"
    private static let eventVisibleImpression = "visible_impression"

    /// Event types that mark the whole response as shown: the SDK name and the Shopping API name.
    private static let responseShownEvents = [eventVisibleImpression, "WRIMP"]

    private static let requestError = "Не удалось получить ответ, попробуйте ещё раз"
    private static let prepareError = "Не удалось загрузить ассистента, попробуйте позже"

    private struct TrackedProduct {
        let product: AssistantProduct
        let events: [ShoppingEngagementEvent]
    }

    private let repository = GravityRepository.instance
    private let assistantRepository = AssistantRepository.instance
    private let eventService = AssistantEventService.instance
    private let analytics = AssistantAnalytics.instance

    /// Preparation counter; an older preparation must not overwrite the result of a newer one.
    private var generation: Int64 = 0

    /// Reset counter; a preparation interrupted by a reset ends with `cancelled` instead of `superseded`.
    private var resets: Int64 = 0

    /// Dialog epoch; incremented on a new chat or identity change to invalidate product refs.
    private var epoch: Int64 = 0

    /// In-flight assistant request; cancelled when the dialog is cleared.
    private var requestTask: Task<Void, Never>?

    /// Dialog step number, used to keep message and block ids unique.
    private var turn: Int64 = 0
    private var threadId: String?

    /// Last question, resent by retry after an error.
    private var lastQuestion: String?

    /// Block ids already used in this dialog; `shelf_id` may repeat across steps.
    private var usedBlockIds: Set<String> = []

    /// Displayed products by itemId, used to resolve product refs.
    private var trackedProducts: [String: TrackedProduct] = [:]

    /// Impressions already sent during the current chat opening, keyed by epoch and itemId.
    private var reportedImpressions: Set<String> = []

    /// Product whose transition is already in progress; repeated taps on it are ignored.
    private var pendingTap: String?

    /// Whether the chat is on screen.
    private var isPresented = false

    /// Event sends deferred until the chat is shown.
    private var pendingDisplay: [() -> Void] = []

    /// Current start screen configuration; cleared as soon as a new preparation starts.
    @Published private(set) var config: AssistantConfig?

    @Published private(set) var isPreparing = false

    /// Error text shown instead of the greeting when preparation fails.
    @Published private(set) var startScreenError: String?

    @Published private(set) var dialogState = AssistantDialogState()

    /// Context of the current dialog; fixed on the first question.
    private var dialogContext: AssistantDialogContext?

    /// Context captured when the chat was opened; used for events before the first question.
    private var openContext: AssistantDialogContext?

    var productBlockBuilder: AssistantProductBlockBuilder?
    var actionHandler: AssistantActionHandler?

    nonisolated init() {}

    /// Fully resets the assistant on identity change or dispose.
    func reset() {
        resets += 1
        config = nil
        isPreparing = false
        startScreenError = nil
        endDialog()
        turn = 0
    }

    /// Called when the chat is shown. Resets impression tracking and sends events deferred while it was closed.
    func onAssistantOpened() {
        reportedImpressions.removeAll()
        pendingTap = nil
        isPresented = true

        openContext = dialogContext ?? config?.context

        track(.dialogOpen)

        let pending = pendingDisplay
        pendingDisplay.removeAll()
        pending.forEach { $0() }
    }

    /// Called when the chat is hidden. The dialog is kept.
    func onAssistantClosed() {
        isPresented = false
        track(.dialogClose)
        openContext = nil
    }

    /// Clears the dialog and returns to the start screen.
    func startNewChat() {
        endDialog()
    }

    /// Sends `dialogEnd` if a question was asked, then clears the dialog.
    private func endDialog() {
        if threadId != nil { track(.dialogEnd) }
        clearDialog()
    }

    /// Clears the dialog, cancels the pending request and invalidates issued product refs.
    private func clearDialog() {
        requestTask?.cancel()
        requestTask = nil

        epoch += 1
        threadId = nil
        lastQuestion = nil
        dialogContext = nil
        usedBlockIds.removeAll()
        trackedProducts.removeAll()
        pendingDisplay.removeAll()
        dialogState = AssistantDialogState()
    }

    /// Analytics scope from the dialog context, else the opening context, else the preparation context.
    private func eventScope() -> AssistantEventScope? {
        guard let context = dialogContext ?? openContext ?? config?.context else { return nil }
        return AssistantEventScope(
            pageContext: context.pageContext,
            customerUser: context.eventUser,
            campaignId: context.campaignId,
            threadId: threadId
        )
    }

    private func track(_ event: AssistantLifecycleEvent, messageId: String? = nil) {
        guard let scope = eventScope() else {
            GravityLogger.i(prefix: Self.TAG, "No dialog context for \(event.eventName)")
            return
        }
        analytics.track(event, scope: scope, messageId: messageId)
    }

    /// Tracks the event on first display: now if the chat is open, otherwise on the next opening.
    /// The scope is captured at call time.
    private func trackOnDisplay(_ event: AssistantLifecycleEvent, messageId: String? = nil) {
        guard let scope = eventScope() else {
            GravityLogger.i(prefix: Self.TAG, "No dialog context for \(event.eventName)")
            return
        }
        onDisplay { self.analytics.track(event, scope: scope, messageId: messageId) }
    }

    /// Runs `send` now if the chat is shown, otherwise on the next opening.
    private func onDisplay(_ send: @escaping () -> Void) {
        if isPresented { send() } else { pendingDisplay.append(send) }
    }

    func sendMessage(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !dialogState.isSending else { return }

        let messageId = UUID().uuidString
        lastQuestion = message
        dialogState.items.append(.userMessage(id: messageId, text: message))
        dialogState.suggests = []
        dialogState.isSending = true
        dialogState.errorText = nil

        // Track only after request(): it sets threadId and the dialog context used by the event.
        if request(message) {
            track(.messageSent, messageId: messageId)
        }
    }

    /// Resends the last question after an error without adding it to the dialog or tracking a new message.
    func retryLastQuestion() {
        guard let message = lastQuestion, !dialogState.isSending else { return }

        dialogState.isSending = true
        dialogState.errorText = nil
        _ = request(message)
    }

    /// Sends the question to the assistant. Returns `false` if there is no prepared context.
    private func request(_ message: String) -> Bool {
        guard let context = dialogContext ?? config?.context else {
            GravityLogger.i(prefix: Self.TAG, "Message is sent without prepared context")
            failRequest()
            return false
        }
        dialogContext = context

        let currentThreadId = threadId ?? UUID().uuidString
        threadId = currentThreadId

        let requestEpoch = epoch
        turn += 1
        let requestTurn = turn

        let payload = ShoppingGenerateRequest(
            threadId: currentThreadId,
            resourceId: context.uid,
            messages: [ShoppingMessage(role: "user", content: message)],
            runtimeContext: ShoppingRuntimeContext(
                tenantId: GravitySDK.instance.section,
                uid: context.uid,
                ctx: context.pageContext
            )
        )

        requestTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.assistantRepository.generate(payload)

            if Task.isCancelled { return }

            guard requestEpoch == self.epoch else { return }

            guard case let .success(response) = outcome else {
                self.failRequest()
                return
            }

            let items = self.chatItems(from: response.contents, refEpoch: requestEpoch, turn: requestTurn)
            if items.isEmpty {
                GravityLogger.i(prefix: Self.TAG, "Assistant response has nothing to render")
                self.failRequest()
                return
            }

            self.dialogState.items.append(contentsOf: items)
            self.dialogState.suggests = response.suggests
            self.dialogState.isSending = false

            let messageId = response.assistantMessageId
            self.trackOnDisplay(.responseReceived, messageId: messageId)

            let hasProducts = items.contains { item in
                if case let .productBlock(_, block) = item { return !block.products.isEmpty }
                return false
            }
            if hasProducts {
                self.trackOnDisplay(.productSelectionReceived, messageId: messageId)
            }

            let responseEvents = response.events
            self.onDisplay { self.eventService.track(responseEvents, Self.responseShownEvents) }
        }

        return true
    }

    /// Ends sending with an error, unblocking input.
    private func failRequest() {
        dialogState.isSending = false
        dialogState.errorText = Self.requestError
        trackOnDisplay(.error)
    }

    private func chatItems(
        from contents: [ShoppingContent],
        refEpoch: Int64,
        turn: Int64
    ) -> [AssistantChatItem] {
        contents.enumerated().compactMap { index, content in
            switch content {
            case let .message(value):
                return .assistantMessage(id: "message-\(turn)-\(index)", text: value)

            case let .products(title, shelfId, products):
                let blockId: String
                if let shelfId, !shelfId.isEmpty, usedBlockIds.insert(shelfId).inserted {
                    blockId = shelfId
                } else {
                    blockId = "block-\(turn)-\(index)"
                }

                return .productBlock(
                    id: blockId,
                    block: AssistantProductBlock(
                        blockId: blockId,
                        title: title,
                        products: assistantProducts(from: products, refEpoch: refEpoch, blockId: blockId)
                    )
                )

            case let .button(_, action, _):
                GravityLogger.i(prefix: Self.TAG, "Button content \(action) is not rendered yet")
                return nil
            }
        }
    }

    private func assistantProducts(
        from products: [ShoppingProduct],
        refEpoch: Int64,
        blockId: String
    ) -> [AssistantProduct] {
        products.enumerated().map { index, product in
            let itemId = "\(blockId):\(index)"

            let assistantProduct = AssistantProduct(
                itemId: itemId,
                ref: AssistantProductRef(epoch: refEpoch, itemId: itemId),
                name: product.name,
                sku: product.sku,
                url: product.url,
                imageUrl: product.imageUrl,
                price: product.price,
                brand: product.brand,
                features: product.features,
                categoryId: product.categoryId,
                isStm: product.isStm
            )

            let resolved = assistantProduct.withCanOpen(canOpen(assistantProduct))
            trackedProducts[itemId] = TrackedProduct(product: resolved, events: product.events)
            return resolved
        }
    }

    /// Validates a product action and, if accepted, sends its tracking.
    /// Closing the chat and invoking the handler are left to the caller.
    func planProductAction(
        _ ref: AssistantProductRef,
        _ action: AssistantProductAction
    ) -> AssistantProductActionPlan {
        guard ref.epoch == epoch else {
            GravityLogger.i(prefix: Self.TAG, "Product ref from epoch \(ref.epoch) is stale")
            return AssistantProductActionPlan(result: .staleReference)
        }

        guard let tracked = trackedProducts[ref.itemId] else {
            GravityLogger.i(prefix: Self.TAG, "Unknown product ref \(ref.itemId)")
            return AssistantProductActionPlan(result: .staleReference)
        }

        if action == .visibleImpression {
            guard reportedImpressions.insert("\(ref.epoch):\(ref.itemId)").inserted else {
                GravityLogger.d(prefix: Self.TAG, "Product \(ref.itemId) is already seen in this chat")
                return AssistantProductActionPlan(result: .duplicate)
            }

            GravityLogger.d(prefix: Self.TAG, "Product \(ref.itemId) became visible")
            eventService.track(tracked.events, [Self.eventVisibleImpression])
            return AssistantProductActionPlan(result: .accepted)
        }

        if pendingTap == ref.itemId {
            GravityLogger.d(prefix: Self.TAG, "Transition to product \(ref.itemId) is already started")
            return AssistantProductActionPlan(result: .duplicate)
        }

        let assistantAction = AssistantAction.openProduct(tracked.product)

        guard let handler = actionHandler, handler.canHandle(assistantAction) else {
            GravityLogger.i(prefix: Self.TAG, "No handler for \(action) on \(ref.itemId)")
            return AssistantProductActionPlan(result: .notActionable)
        }

        GravityLogger.d(prefix: Self.TAG, "Product \(ref.itemId) is tapped")
        pendingTap = ref.itemId
        eventService.track(tracked.events, [Self.eventClick])

        return AssistantProductActionPlan(
            result: .accepted,
            action: assistantAction,
            closeChat: true
        )
    }

    private func canOpen(_ product: AssistantProduct) -> Bool {
        let hasTarget = !(product.sku ?? "").isEmpty || isHttpUrl(product.url)
        guard hasTarget else { return false }

        guard let handler = actionHandler else { return false }
        return handler.canHandle(.openProduct(product))
    }

    private func isHttpUrl(_ url: String?) -> Bool {
        guard let url, !url.isEmpty else { return false }
        return url.hasPrefix("http://") || url.hasPrefix("https://")
    }

    func prepare(
        assistantSelector: String,
        pageContext: PageContext,
        timeoutMillis: Int64,
        options: Options,
        contentSettings: ContentSettings,
        customerUser: User?
    ) async -> AssistantPrepareResult {
        if assistantSelector.trimmingCharacters(in: .whitespaces).isEmpty {
            return invalidConfiguration("assistantSelector is blank")
        }
        if timeoutMillis <= 0 {
            return invalidConfiguration("timeoutMillis must be positive")
        }

        generation += 1
        let myGeneration = generation
        let myResets = resets
        config = nil
        startScreenError = nil
        isPreparing = true

        defer {
            if myGeneration == generation { isPreparing = false }
        }

        /// Must stay free of suspension points so that a reset cannot run between
        /// the staleness check and the result.
        func finish(_ result: () -> AssistantPrepareResult) -> AssistantPrepareResult {
            if let stale = outdated(myGeneration, myResets) { return stale }
            let value = result()
            reportPrepareFailure(value, pageContext: pageContext, customerUser: customerUser)
            return value
        }

        let outcome: GravityDataResponse<ContentResponse>?? = await PreparationDeadline.run(
            timeout: Double(timeoutMillis) / 1000
        ) {
            await GravityRepository.instance.chooseBySelectorWithDetails(
                selector: assistantSelector,
                options: options,
                contentSettings: contentSettings,
                customerUser: customerUser,
                pageContext: pageContext
            )
        }

        if Task.isCancelled { return .cancelled }

        if let stale = outdated(myGeneration, myResets) { return stale }

        guard let chosen = outcome else {
            return finish {
                .failure(AssistantError(code: .timeout, message: "Preparation timed out"))
            }
        }

        guard let response = chosen?.data else {
            return finish {
                .failure(AssistantError(code: .network, message: "No response for \(assistantSelector)"))
            }
        }

        let variations = response.data.flatMap { $0.payload }
        let rawConfigs = variations.flatMap { $0.contents }.compactMap { $0.custom?.json }

        if rawConfigs.isEmpty {
            return finish { .unavailable(.noMatchingConfiguration) }
        }

        if Set(rawConfigs).count > 1 {
            return finish {
                self.invalidConfiguration("Several different configurations for \(assistantSelector)")
            }
        }

        guard let rawConfig = rawConfigs.first?.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: rawConfig),
              let settings = json.objectValue
        else {
            return finish { self.invalidConfiguration("Malformed assistant custom.json") }
        }

        guard let enabled = settings["enabled"] else {
            return finish { self.invalidConfiguration("Assistant configuration has no enabled flag") }
        }

        if enabled.boolValue != true {
            return finish { .unavailable(.disabled) }
        }

        let knownUser = repository.userForRequest(customerUser)
        let responseUid = response.user?.uid
        let knownUid = knownUser.uid
        let uid = (responseUid?.isEmpty == false ? responseUid : nil)
            ?? (knownUid?.isEmpty == false ? knownUid : nil)
        guard let uid else {
            return finish {
                .failure(AssistantError(
                    code: .invalidResponse,
                    message: "No user uid for \(assistantSelector)"
                ))
            }
        }

        let suggests = (settings["suggests"]?.arrayValue ?? [])
            .compactMap { $0.stringValue }
            .filter { !$0.isEmpty }

        let campaignId = variations
            .first { variation in variation.contents.contains { $0.custom?.json != nil } }?
            .campaignId

        let title = settings["title"]?.stringValue
        let prepared = AssistantConfig(
            startScreen: AssistantStartScreen(
                title: (title?.isEmpty == false ? title : nil) ?? Self.defaultTitle,
                subtitle: settings["subtitle"]?.stringValue ?? "",
                suggests: suggests
            ),
            context: AssistantDialogContext(
                uid: uid,
                pageContext: pageContext,
                campaignId: campaignId,
                eventUser: User(
                    uid: uid,
                    custom: customerUser?.custom,
                    ses: customerUser?.ses ?? response.user?.ses ?? knownUser.ses
                )
            )
        )

        return finish {
            self.config = prepared
            self.isPreparing = false
            return .ready
        }
    }

    /// Shows the preparation error on the start screen and tracks it while the greeting is visible.
    private func reportPrepareFailure(
        _ result: AssistantPrepareResult,
        pageContext: PageContext,
        customerUser: User?
    ) {
        guard case .failure = result else { return }

        startScreenError = Self.prepareError

        guard isPresented, dialogState.items.isEmpty else { return }

        analytics.track(
            .error,
            scope: AssistantEventScope(
                pageContext: pageContext,
                customerUser: customerUser,
                campaignId: nil,
                threadId: nil
            )
        )
    }

    /// Returns `cancelled` after a reset, `superseded` if a newer preparation started, or `nil` if still current.
    private func outdated(_ myGeneration: Int64, _ myResets: Int64) -> AssistantPrepareResult? {
        if resets != myResets { return .cancelled }
        if generation != myGeneration { return .superseded }
        return nil
    }

    private func invalidConfiguration(_ message: String) -> AssistantPrepareResult {
        GravityLogger.i(prefix: Self.TAG, message)
        return .failure(AssistantError(code: .invalidConfiguration, message: message))
    }
}
