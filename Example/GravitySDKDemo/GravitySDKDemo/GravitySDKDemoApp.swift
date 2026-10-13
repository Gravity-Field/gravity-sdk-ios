import GravitySDK
import SwiftUI
import UIKit

@main
struct GravitySDKDemoApp: App {

    init() {
        GravitySDK.initialize(
            apiKey:"your-api-key",
           section: "your-section-id",
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
