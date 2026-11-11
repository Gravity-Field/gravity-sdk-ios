import Foundation

internal enum AssistantChatItem: Identifiable {
    case userMessage(id: String, text: String)
    case assistantMessage(id: String, text: String)
    case productBlock(id: String, block: AssistantProductBlock)

    var id: String {
        switch self {
        case let .userMessage(id, _): return id
        case let .assistantMessage(id, _): return id
        case let .productBlock(id, _): return id
        }
    }
}

internal struct AssistantDialogState {
    var items: [AssistantChatItem] = []
    var suggests: [String] = []
    var isSending: Bool = false
    var errorText: String?
}
