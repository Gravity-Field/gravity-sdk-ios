import GravitySDK
import SwiftUI
import UIKit

@main
struct GravitySDKDemoApp: App {

    init() {
        GravitySDK.initialize(
            apiKey:"YzYyMTk2YzFmYTMzYmI5YjE0ZGQ3NjAyZjM4MDc1Yzk3ZDRlM2I2ZDZjNjc0MzI3YjViZTcyYTZjODI5ZWQ0YQ==",
           section: "6819e7c0d7303f0f6b0ef263",
            gravityEventCallback: { event in },
            productViewBuilder: ReviewPromptCoordinator.shared.integration.productViewBuilder,
            logLevel: LogLevel.debug,
            inAppPreparation: ReviewPromptCoordinator.shared.integration.preparation()
        )
        GravitySDK.instance.setLogListener { logLevel, message in
            print("GravitySDK \(logLevel): \(message)")
        }
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
