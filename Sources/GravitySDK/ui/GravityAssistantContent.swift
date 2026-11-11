import SwiftUI
import UIKit

private let titleColor = Color(red: 0x10 / 255, green: 0x18 / 255, blue: 0x28 / 255)
private let subtitleColor = Color(red: 0x66 / 255, green: 0x70 / 255, blue: 0x85 / 255)
private let suggestBackground = Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF7 / 255)
private let suggestTextColor = Color(red: 0x34 / 255, green: 0x40 / 255, blue: 0x54 / 255)
private let avatarColor = Color(red: 0xFF / 255, green: 0x8A / 255, blue: 0x00 / 255)
private let userBubbleColor = Color(red: 0x7F / 255, green: 0x56 / 255, blue: 0xD9 / 255)
private let assistantBubbleColor = Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF7 / 255)
private let loaderColor = Color(red: 0xFE / 255, green: 0x73 / 255, blue: 0x16 / 255)
private let errorColor = Color(red: 0xB4 / 255, green: 0x23 / 255, blue: 0x18 / 255)
private let errorBubbleColor = Color(red: 0xFE / 255, green: 0xE4 / 255, blue: 0xE2 / 255)
private let retryIconColor = Color(red: 0xF0 / 255, green: 0x44 / 255, blue: 0x38 / 255)
private let dividerColor = Color(red: 0xEA / 255, green: 0xEC / 255, blue: 0xF0 / 255)

private let contentPadding: CGFloat = 16
private let itemSpacing: CGFloat = 12

/// Extra bottom scroll inset so the last message does not touch the edge.
private let bottomScrollExtra: CGFloat = 16
private let welcomeAvatarSize: CGFloat = 88
private let messageAvatarSize: CGFloat = 28

/// Fallback loader height until the chat suggestions have been measured.
private let loaderMinHeight: CGFloat = 40

private let suggestFontSize: CGFloat = 14
private let suggestSpacing: CGFloat = 8

/// Assistant screen: the start page before the first message and the conversation after it.
/// Product blocks are rendered by the app via `AssistantProductBlockBuilder`.
internal struct GravityAssistantContent: View {

    @ObservedObject var controller: AssistantController
    let onClose: () -> Void

    private var startScreen: AssistantStartScreen? { controller.config?.startScreen }
    private var state: AssistantDialogState { controller.dialogState }

    var body: some View {
        VStack(spacing: 0) {
            AssistantHeader(
                showNewChat: !state.items.isEmpty && startScreen != nil,
                onNewChat: { controller.startNewChat() },
                onClose: onClose
            )

            AssistantDivider()

            if state.items.isEmpty {
                AssistantWelcome(
                    startScreen: startScreen,
                    isPreparing: controller.isPreparing,
                    errorText: controller.startScreenError,
                    onSuggestTap: { controller.sendMessage($0) }
                )
            } else {
                AssistantDialogList(
                    state: state,
                    productBlockBuilder: controller.productBlockBuilder,
                    onSuggestTap: { controller.sendMessage($0) },
                    onRetry: { controller.retryLastQuestion() }
                )
            }

            AssistantDivider()

            AssistantInput(
                enabled: !state.isSending
                    && state.errorText == nil
                    && (!state.items.isEmpty || startScreen != nil),
                onSend: { controller.sendMessage($0) }
            )
        }
        .background(Color.white.ignoresSafeArea())
    }
}

private struct AssistantDivider: View {
    var body: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
    }
}

private struct AssistantHeader: View {
    let showNewChat: Bool
    let onNewChat: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack {
            if showNewChat {
                Button(action: onNewChat) {
                    Image(systemName: "plus")
                        .foregroundColor(titleColor)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("New chat")
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundColor(titleColor)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 8)
    }
}

private struct AssistantWelcome: View {
    let startScreen: AssistantStartScreen?
    let isPreparing: Bool
    let errorText: String?
    let onSuggestTap: (String) -> Void

    var body: some View {
        if isPreparing {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: loaderColor))
            Spacer()
        } else if startScreen == nil, let errorText {
            Spacer()
            Text(errorText)
                .font(.system(size: 15))
                .foregroundColor(errorColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(errorBubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
            Spacer()
        } else if let startScreen {
            ScrollView {
                VStack(spacing: 0) {
                    AssistantAvatar(size: welcomeAvatarSize)

                    if !startScreen.title.isEmpty {
                        Text(startScreen.title)
                            .font(.system(size: 22))
                            .foregroundColor(titleColor)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
                    }

                    if !startScreen.subtitle.isEmpty {
                        Text(startScreen.subtitle)
                            .font(.system(size: 16))
                            .foregroundColor(subtitleColor)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }

                    if !startScreen.suggests.isEmpty {
                        AssistantSuggests(
                            suggests: startScreen.suggests,
                            centered: true,
                            onSuggestTap: onSuggestTap
                        )
                        .padding(.top, 24)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
            }
        } else {
            Spacer()
        }
    }
}

private struct AssistantDialogList: View {
    let state: AssistantDialogState
    let productBlockBuilder: AssistantProductBlockBuilder?
    let onSuggestTap: (String) -> Void
    let onRetry: () -> Void

    /// Measured heights are kept here because the lazy list may remove the measured rows.
    @State private var suggestsHeight: CGFloat = 0
    @State private var lastQuestionHeight: CGFloat = 0
    @State private var isRestored = false
    @State private var contentWidth: CGFloat = 0

    private var lastQuestionId: String? {
        state.items.last { if case .userMessage = $0 { return true } else { return false } }?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Spacing is top padding of each row, so scrolling to a question keeps the gap above it.
                LazyVStack(spacing: 0) {
                    ForEach(state.items) { item in
                        row(for: item)
                            .padding(.top, item.id == state.items.first?.id ? 0 : itemSpacing)
                            .id(item.id)
                    }

                    if state.isSending {
                        sendingRow
                            .padding(.top, itemSpacing)
                            .id("sending")
                    }

                    if let error = state.errorText, !state.isSending {
                        ErrorRow(text: error, onRetry: onRetry)
                            .padding(.top, itemSpacing)
                            .id("error")
                    }

                    if !state.suggests.isEmpty, !state.isSending {
                        AssistantSuggests(
                            suggests: state.suggests,
                            centered: false,
                            onSuggestTap: onSuggestTap
                        )
                        .padding(.horizontal, contentPadding)
                        .background(HeightReader(height: $suggestsHeight))
                        .padding(.top, itemSpacing)
                        .id("suggests")
                    }
                }
                .padding(.top, contentPadding)
                .padding(.bottom, contentPadding + bottomScrollExtra)
                .background(WidthReader(width: $contentWidth))
            }
            .onAppear {
                if let id = lastQuestionId { proxy.scrollTo(id, anchor: .top) }
                isRestored = true
            }
            // Use the new value, not `lastQuestionId`: the closure still sees the previous render.
            .onChange(of: ScrollTrigger(lastQuestionId: lastQuestionId, isSending: state.isSending)) {
                scroll(proxy, to: $0.lastQuestionId)
            }
        }
    }

    private struct ScrollTrigger: Equatable {
        let lastQuestionId: String?
        let isSending: Bool
    }

    /// Scrolls the given question to the top so its answer is read from the beginning.
    private func scroll(_ proxy: ScrollViewProxy, to id: String?) {
        guard isRestored, let id else { return }
        withAnimation { proxy.scrollTo(id, anchor: .top) }
    }

    @ViewBuilder
    private func row(for item: AssistantChatItem) -> some View {
        switch item {
        case let .userMessage(id, text):
            MessageBubble(
                text: text,
                alignment: .trailing,
                backgroundColor: userBubbleColor,
                textColor: .white
            )
            .background(
                id == lastQuestionId ? HeightReader(height: $lastQuestionHeight) : nil
            )

        case let .assistantMessage(_, text):
            AssistantMessageRow(text: text)

        case let .productBlock(_, block):
            ProductBlockRow(
                block: block,
                productBlockBuilder: productBlockBuilder,
                availableWidth: contentWidth
            )
        }
    }

    /// Loader row that fills the space freed by the suggestions, minus the new question.
    private var sendingRow: some View {
        HStack(spacing: itemSpacing) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: loaderColor))

            Text("Изучаю вопрос...")
                .font(.system(size: 15))
                .foregroundColor(subtitleColor)

            Spacer()
        }
        .frame(minHeight: loaderMinHeight)
        .padding(.horizontal, contentPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: max(suggestsHeight - lastQuestionHeight - itemSpacing, loaderMinHeight),
            alignment: .topLeading
        )
    }
}

/// Product block spanning the full chat width; horizontal insets are left to the app.
private struct ProductBlockRow: View {
    let block: AssistantProductBlock
    let productBlockBuilder: AssistantProductBlockBuilder?
    let availableWidth: CGFloat

    var body: some View {
        if let productBlockBuilder {
            if availableWidth > 0 {
                productBlockBuilder.build(
                    block: block,
                    layout: AssistantProductLayout(availableWidth: availableWidth)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Не удалось показать подборку товаров")
                .font(.system(size: 14))
                .foregroundColor(errorColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, contentPadding)
        }
    }
}

/// Assistant reply: avatar on the left and a text bubble.
private struct AssistantMessageRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AssistantAvatar(size: messageAvatarSize)

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(titleColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(assistantBubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, contentPadding)
    }
}

/// Request error: a red message bubble with a retry button in place of the avatar.
private struct ErrorRow: View {
    let text: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(retryIconColor)
                    .frame(width: messageAvatarSize, height: messageAvatarSize)
            }
            .accessibilityLabel("Retry")

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(errorColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(errorBubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, contentPadding)
    }
}

private struct AssistantInput: View {
    let enabled: Bool
    let onSend: (String) -> Void

    /// Kept local so that typing does not re-render the whole conversation.
    @State private var draft = ""

    private var canSend: Bool {
        enabled && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField("Спросите ассистента", text: $draft, onCommit: send)
                .font(.system(size: 15))
                .foregroundColor(titleColor)
                .accentColor(userBubbleColor)
                .disabled(!enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(suggestBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(canSend ? userBubbleColor : subtitleColor)
                    .frame(width: 48, height: 48)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.leading, contentPadding)
        .padding(.trailing, 8)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func send() {
        guard canSend else { return }
        onSend(draft)
        draft = ""
    }
}

private struct AssistantAvatar: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "face.smiling")
            .resizable()
            .scaledToFit()
            .foregroundColor(.white)
            .frame(width: size * 0.6, height: size * 0.6)
            .frame(width: size, height: size)
            .background(avatarColor)
            .clipShape(Circle())
    }
}

private struct MessageBubble: View {
    let text: String
    let alignment: HorizontalAlignment
    let backgroundColor: Color
    let textColor: Color

    var body: some View {
        HStack(spacing: 0) {
            if alignment == .trailing { Spacer(minLength: 0) }

            Text(text)
                .font(.system(size: 15))
                .foregroundColor(textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if alignment == .leading { Spacer(minLength: 0) }
        }
        .padding(.horizontal, contentPadding)
    }
}

/// Suggestion chips wrapped into rows. Laid out manually because `Layout` requires iOS 16.
private struct AssistantSuggests: View {
    let suggests: [String]
    let centered: Bool
    let onSuggestTap: (String) -> Void

    @State private var availableWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: suggestSpacing) {
            ForEach(Array(rows().enumerated()), id: \.offset) { _, row in
                HStack(spacing: suggestSpacing) {
                    ForEach(row, id: \.self) { suggest in
                        chip(suggest)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .background(WidthReader(width: $availableWidth))
    }

    private func chip(_ suggest: String) -> some View {
        Button(action: { onSuggestTap(suggest) }) {
            Text(suggest)
                .font(.system(size: suggestFontSize))
                .foregroundColor(suggestTextColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(suggestBackground)
                .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Splits suggestions into rows greedily, wrapping a chip that does not fit the remaining width.
    private func rows() -> [[String]] {
        guard availableWidth > 0 else { return suggests.map { [$0] } }

        var rows: [[String]] = []
        var current: [String] = []
        var currentWidth: CGFloat = 0

        for suggest in suggests {
            let width = Self.chipWidth(suggest)
            let needed = current.isEmpty ? width : currentWidth + suggestSpacing + width

            if !current.isEmpty, needed > availableWidth {
                rows.append(current)
                current = [suggest]
                currentWidth = width
            } else {
                current.append(suggest)
                currentWidth = needed
            }
        }

        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private static func chipWidth(_ suggest: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: suggestFontSize)
        let textWidth = (suggest as NSString)
            .size(withAttributes: [.font: font])
            .width
        // Must match the chip's horizontal padding.
        return ceil(textWidth) + 32
    }
}

/// Writes the non-zero height of the view it is attached to into `height`.
private struct HeightReader: View {
    @Binding var height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size.height)
        }
        .onPreferenceChange(SizePreferenceKey.self) { value in
            if value > 0 { height = value }
        }
    }
}

/// Writes the non-zero width of the view it is attached to into `width`.
private struct WidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size.width)
        }
        .onPreferenceChange(SizePreferenceKey.self) { value in
            if value > 0 { width = value }
        }
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
