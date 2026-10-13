import GravitySDK
import SwiftUI

struct ContentView: View {
    
    @State private var showInlineDemo = false
    @State private var showInlineListDemo = false
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
