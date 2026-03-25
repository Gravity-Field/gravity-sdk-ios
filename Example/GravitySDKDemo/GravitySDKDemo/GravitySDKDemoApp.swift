import GravitySDK
import SwiftUI

@main
struct GravitySDKDemoApp: App {

    init() {
        GravitySDK.initialize(
            apiKey:"",
            section: "",
            gravityEventCallback: { event in },
            logLevel: LogLevel.debug
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
