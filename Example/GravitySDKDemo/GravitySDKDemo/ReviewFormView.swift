import SwiftUI

/// The client app's own review screen — opened by `ReviewPromptCoordinator` after
/// `dismissInApp` succeeds. Submitting calls `onSubmit`, which is responsible for updating the
/// client's review status (`ReviewStatusStore`) so the SKU is excluded from future shows; opening
/// the screen or cancelling out of it must NOT count as a submitted review.
struct ReviewFormView: View {
    let sku: String
    let onSubmit: (String, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating = 5
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Товар") {
                    Text(sku)
                        .foregroundColor(.secondary)
                }
                Section("Оценка") {
                    Picker("Рейтинг", selection: $rating) {
                        ForEach(1...5, id: \.self) { value in
                            Text(String(repeating: "★", count: value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Отзыв") {
                    TextField("Что понравилось или не понравилось?", text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Оставить отзыв")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") {
                        onSubmit(sku, rating, comment)
                        dismiss()
                    }
                }
            }
        }
    }
}
