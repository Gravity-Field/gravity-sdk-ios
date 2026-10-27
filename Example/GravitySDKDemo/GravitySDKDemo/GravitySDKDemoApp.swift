import Foundation
import GravitySDK
import SwiftUI
import UIKit

@main
struct GravitySDKDemoApp: App {

    private static var demoConfiguration: (apiKey: String, section: String)? {
        let environment = ProcessInfo.processInfo.environment
        guard let apiKey = environment["GRAVITY_DEMO_API_KEY"], !apiKey.isEmpty,
              let section = environment["GRAVITY_DEMO_SECTION"], !section.isEmpty else {
            return nil
        }
        return (apiKey, section)
    }

    init() {
        guard let configuration = Self.demoConfiguration else { return }
        GravitySDK.initialize(
            apiKey: configuration.apiKey,
            section: configuration.section,
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
            if Self.demoConfiguration != nil {
                ContentView()
            } else {
                Text("Set GRAVITY_DEMO_API_KEY and GRAVITY_DEMO_SECTION in your local Xcode Run scheme to start the demo.")
                    .padding()
            }
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
