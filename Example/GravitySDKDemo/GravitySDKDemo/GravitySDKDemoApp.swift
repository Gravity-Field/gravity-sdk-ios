import GravitySDK
import SwiftUI

@main
struct GravitySDKDemoApp: App {

    init() {
        GravitySDK.initialize(
            apiKey:"",
            section: "",
            gravityEventCallback: { event in },
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
