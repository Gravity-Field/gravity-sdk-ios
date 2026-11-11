import Foundation

/// Chat lifecycle analytics events sent by the SDK. Raw values are the public event names.
internal enum AssistantLifecycleEvent: String {

    case dialogOpen = "chat_dialog_open"

    /// A new question was sent. Retrying the same question is not reported.
    case messageSent = "assistant_message_sent"

    /// A received answer was shown for the first time, including after reopening the chat.
    case responseReceived = "assistant_response_received"

    /// Sent with the first display of an answer that contains a non-empty product block.
    case productSelectionReceived = "assistant_product_selection_received"

    /// An error was shown in the open chat. Cancellation and supersession are not reported.
    case error = "chat_error"

    /// The chat was removed from the screen; the conversation continues.
    case dialogClose = "chat_dialog_close"

    /// The conversation ended: an explicit new chat or an identity reset.
    case dialogEnd = "chat_dialog_end"

    var eventName: String { rawValue }
}

/// Snapshot of the page, customer and campaign an event belongs to, taken when the event occurs.
internal struct AssistantEventScope {
    let pageContext: PageContext
    let customerUser: User?
    let campaignId: String?
    let threadId: String?
}

/// Sends chat lifecycle events as custom events without awaiting the result.
/// Events carry identifiers only, never message text.
internal final class AssistantAnalytics {

    static let instance = AssistantAnalytics()

    private static let TAG = "AssistantAnalytics"

    private init() {}

    private let repository = GravityRepository.instance

    func track(
        _ event: AssistantLifecycleEvent,
        scope: AssistantEventScope,
        messageId: String? = nil
    ) {
        let raisedAt = Date()
        let options = GravitySDK.instance.currentOptions

        // Resolve the anonymous user now: by send time prefs may already hold another user.
        let customerUser = scope.customerUser ?? repository.userForRequest(nil)

        var props: [String: String] = [:]
        if let threadId = scope.threadId { props["threadId"] = threadId }
        if let messageId { props["messageId"] = messageId }
        if let campaignId = scope.campaignId { props["campaignId"] = campaignId }

        let customEvent = CustomEvent(
            type: event.eventName,
            name: event.eventName,
            customProps: props.isEmpty ? nil : props
        )

        Task { [repository] in
            let response = await repository.event(
                events: [customEvent],
                raisedAt: raisedAt,
                pageContext: scope.pageContext,
                options: options,
                customerUser: customerUser
            )

            let outcome = response != nil ? "sent" : "failed"
            GravityLogger.d(prefix: Self.TAG, "\(event.eventName) \(props) \(outcome)")
        }
    }
}
