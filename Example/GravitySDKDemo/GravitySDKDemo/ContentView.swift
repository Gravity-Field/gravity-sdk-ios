import GravitySDK
import SwiftUI

struct ContentView: View {
    
    @State private var showInlineDemo = false
    @State private var showInlineListDemo = false
    @State private var abButtonColor: Color?
    @State private var showReviewPromptTestConsole = false
    @ObservedObject private var reviewPromptCoordinator = ReviewPromptCoordinator.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                
                Button("Track view homepage") {
                    GravitySDK.instance.trackView(
                        pageContext: PageContext(
                            type: .homepage,
                            data: [],
                            location: "homepage"
                        )
                    )
                }
                
                Button("Track view other") {
                    GravitySDK.instance.trackView(
                        pageContext: PageContext(
                            type: .other,
                            data: [],
                            location: "other"
                        )
                    )
                }
                
                Button("Track view search") {
                    GravitySDK.instance.trackView(
                        pageContext: PageContext(
                            type: .search,
                            data: [],
                            location: "search"
                        )
                    )
                }

                Button("Trigger event") {
                    GravitySDK.instance.triggerEvent(
                        events: [
                            CustomEvent(
                                type: "tapbar_clicked",
                                name: "tapbar_clicked"
                            )
                            
                        ],
                        pageContext: PageContext(
                            type: .homepage,
                            data: [],
                            location: "homepage"
                        )
                    )
                }
                
                Button("Get content by selector") {
                    Task {
                        let response = await GravitySDK.instance
                            .getContentBySelector(
                                selector: "sdk_cart_reco",
                                pageContext: PageContext(
                                    type: .cart,
                                    data: [],
                                    location: "homepage"
                                )
                            )
                        print("response: \(String(describing: response))")
                    }
                }

                // Own rendering with an A/B parameter: reads an arbitrary key of the
                // campaign variables ("ab_button_color") from rawVariables, applies it
                // to this button and reports the impression, since the SDK shows nothing itself.
                Button("A/B parameter from rawVariables") {
                    Task {
                        guard
                            let response = await GravitySDK.instance.getContentBySelectorWithDetails(
                                selector: "homepage_inline_banner",
                                pageContext: PageContext(type: .homepage, data: [], location: "homepage")
                            )
                        else { return }
                        print("raw response: \(response.json)")
                        guard let campaign = response.data.data.first,
                            let content = campaign.payload.first?.contents.first,
                            let hex = content.rawVariables["ab_button_color"]?.stringValue,
                            let color = abColor(hex)
                        else { return }
                        abButtonColor = color
                        GravitySDK.instance.sendContentEngagement(
                            engagement: ContentImpressionEngagement(content: content, campaign: campaign)
                        )
                    }
                }
                .tint(abButtonColor ?? .accentColor)
                
                Button("Show UITableView with InlineView") {
                    showInlineDemo = true
                }
                
                Button("Show UITableView with InlineListView") {
                    showInlineListDemo = true
                }

                Button("Review Prompt Test Console") {
                    showReviewPromptTestConsole = true
                }
                
                GravityInlineSwiftUIView(
                    selector: "homepage_inline_banner",
                    pageContext: PageContext(
                        type: .homepage,
                        data: [],
                        location: "homepage"
                    )
                ) {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
            }.frame(maxHeight: .infinity, alignment: .top)
                .padding()
                .navigationDestination(isPresented: $showInlineDemo) {
                    InlineDemoViewControllerRepresentable()
                        .navigationTitle("Inline Demo")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .navigationDestination(isPresented: $showInlineListDemo) {
                    InlineListDemoViewControllerRepresentable()
                        .navigationTitle("Inline List Demo")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .navigationDestination(isPresented: $showReviewPromptTestConsole) {
                    ReviewPromptTestConsoleView()
                }
        }
        .sheet(isPresented: Binding(
            get: { reviewPromptCoordinator.reviewFormSKU != nil },
            set: { isPresented in
                if !isPresented { reviewPromptCoordinator.reviewFormSKU = nil }
            }
        )) {
            if let sku = reviewPromptCoordinator.reviewFormSKU {
                ReviewFormView(sku: sku) { sku, rating, comment in
                    ReviewPromptCoordinator.shared.didSubmitReview(sku: sku, rating: rating, comment: comment)
                }
            }
        }
    }
}

/// "#RRGGBB" from an A/B parameter to a SwiftUI color.
private func abColor(_ hex: String) -> Color? {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
    return Color(
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255
    )
}
