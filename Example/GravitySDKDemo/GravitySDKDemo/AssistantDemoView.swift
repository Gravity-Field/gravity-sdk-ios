import GravitySDK
import SwiftUI

private let logTag = "GravitySDK"

private let snackbarBackground = Color(red: 0x99 / 255, green: 0xE2 / 255, blue: 0xB4 / 255)
private let snackbarContentColor = Color(red: 0x05 / 255, green: 0x4F / 255, blue: 0x31 / 255)

private let assistantEntrySelector = "assistant_sdk_entry"
private let assistantSelector = "assistant_sdk_gate"

/// Demo screen that prepares the assistant on appear and shows the entry button once it is ready.
struct AssistantDemoView: View {

    @State private var assistantEntryTitle: String?
    @State private var snackbarMessage: String?
    @State private var snackbarDismiss: Task<Void, Never>?

    var body: some View {
        ZStack {
            Text("Ваш экран с ассистентом")

            if let title = assistantEntryTitle {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        AssistantEntryButton(title: title) {
                            GravitySDK.instance.openAssistant()
                        }
                    }
                }
                .padding(16)
            }

            if let message = snackbarMessage {
                VStack {
                    Spacer()
                    AssistantSnackbar(message: message)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Assistant demo")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            assistantEntryTitle = await prepareAssistantEntry()
        }
        .onReceive(AssistantActionHandlerImpl.shared.messages) { message in
            snackbarDismiss?.cancel()
            snackbarMessage = message
            snackbarDismiss = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                snackbarMessage = nil
            }
        }
    }
}

private struct AssistantEntryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "face.smiling")
                Text(title)
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(red: 0x7F / 255, green: 0x56 / 255, blue: 0xD9 / 255))
            .clipShape(Capsule())
        }
    }
}

private struct AssistantSnackbar: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
            Spacer(minLength: 0)
        }
        .foregroundColor(snackbarContentColor)
        .padding(16)
        .background(snackbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Loads the entry button campaign, then prepares the assistant.
/// Returns the button title only if the entry is enabled and the assistant is ready.
@MainActor
private func prepareAssistantEntry() async -> String? {
    let pageContext = PageContext(
        type: .homepage,
        data: [],
        location: "homepage"
    )

    let entryResponse = await GravitySDK.instance.getContentBySelector(
        selector: assistantEntrySelector,
        pageContext: pageContext
    )

    guard let entry = parseAssistantEntry(entryResponse), entry.enabled else {
        print("\(logTag): Assistant entry is disabled")
        return nil
    }

    let result = await GravitySDK.instance.prepareAssistant(
        assistantSelector: assistantSelector,
        pageContext: pageContext
    )
    print("\(logTag): prepareAssistant: \(result)")

    return result == .ready ? entry.title : nil
}

private func parseAssistantEntry(_ response: ContentResponse?) -> AssistantEntry? {
    guard let raw = response?.data
        .first?
        .payload
        .first?
        .contents
        .first?
        .custom?
        .json,
        let data = raw.data(using: .utf8)
    else { return nil }

    guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
        print("\(logTag): Failed to parse assistant entry")
        return nil
    }

    return AssistantEntry(
        enabled: json["enabled"]?.boolValue ?? false,
        title: json["title"]?.stringValue ?? ""
    )
}

private struct AssistantEntry {
    let enabled: Bool
    let title: String
}
