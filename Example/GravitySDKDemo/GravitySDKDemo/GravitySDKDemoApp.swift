import GravitySDK
import SwiftUI
import UIKit

@main
struct GravitySDKDemoApp: App {

    init() {
        GravitySDK.initialize(
            apiKey:"",
            section: "",
            gravityEventCallback: { event in },
            productViewBuilder: DemoProductViewBuilder(),
            logLevel: LogLevel.debug
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct DemoProductViewBuilder: LegacyProductViewBuilder {
    func createView(
        slot: Slot,
        content: CampaignContent,
        campaign: Campaign
    ) -> UIView {
        ProductView(slot: slot)
    }
}
