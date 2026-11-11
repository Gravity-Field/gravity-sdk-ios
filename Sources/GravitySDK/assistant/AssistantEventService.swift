import Foundation

/// Sends tracking URLs from Shopping API responses without awaiting the result; failures are ignored.
internal final class AssistantEventService {

    static let instance = AssistantEventService()

    private static let TAG = "AssistantEventService"

    private init() {}

    private let repository = GravityRepository.instance

    /// Sends the unique URLs of all events whose type matches any of `types`, case-insensitively.
    func track(_ events: [ShoppingEngagementEvent], _ types: [String]) {
        let type = types.joined(separator: "/")
        var urls: [String] = []
        for event in events where types.contains(where: { event.type.lowercased() == $0.lowercased() }) {
            for url in event.urls where !urls.contains(url) {
                urls.append(url)
            }
        }

        guard !urls.isEmpty else {
            GravityLogger.d(prefix: Self.TAG, "No \(type) urls in response")
            return
        }

        Task { [repository] in
            do {
                try await repository.trackEngagementEvent(urls: urls)
                GravityLogger.d(prefix: Self.TAG, "Sent \(type): \(urls)")
            } catch {
                GravityLogger.d(prefix: Self.TAG, "Failed to send \(type): \(error)")
            }
        }
    }
}
