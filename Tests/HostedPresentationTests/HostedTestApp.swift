import SwiftUI

@main struct HostedTestApp: App {
    var body: some Scene {
        WindowGroup {
            // Not .task: SwiftUI cancels it when a fullscreen presentation covers this
            // view, and every later Task.sleep would then return immediately.
            Text("Hosted UIKit regression tests").onAppear { Task { @MainActor in await HostedPresentationTests.run() } }
        }
    }
}
