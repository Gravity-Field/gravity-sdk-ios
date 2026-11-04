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
                
                NavigationLink("Server user identity") {
                    UserIdentityExampleView()
                }

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

                Button("Trigger event with customProps") {
                    GravitySDK.instance.triggerEvent(
                        events: [
                            AddToCartEvent(
                                value: 99.99,
                                productId: "sku-123",
                                quantity: 1,
                                customProps: ["list": "search"],
                                eventTime: Date()
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

                NavigationLink("Render a triggered campaign myself") {
                    HeadlessCampaignDemo()
                }

                Button("Review Prompt Test Console") {
                    showReviewPromptTestConsole = true
                }
                
                NavigationLink("Products grid") {
                    ProductsGridExampleView()
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

/// Keep a server UID in your own account storage and restore it when needed.
/// The process-wide listener remains installed when the SDK is initialized again.
private struct UserIdentityExampleView: View {
    @State private var currentUid: String?
    @State private var uidToRestore = ""
    @State private var status = ""

    var body: some View {
        Form {
            Section("Server identity") {
                Text(currentUid ?? "No server UID yet")
                Button("Read server UID") {
                    Task { currentUid = await GravitySDK.instance.getUserId() }
                }
                TextField("Saved server UID", text: $uidToRestore)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Restore server UID") {
                    Task {
                        do {
                            try await GravitySDK.instance.restoreUserId(uidToRestore)
                            currentUid = await GravitySDK.instance.getUserId()
                            status = "Restored; the next request opens a session."
                        } catch { status = "Restore failed: \(error)" }
                    }
                }
                Button("Reset user") {
                    Task {
                        do {
                            try await GravitySDK.instance.resetUser()
                            currentUid = await GravitySDK.instance.getUserId()
                            status = "Reset; the next request creates an anonymous user."
                        } catch { status = "Reset failed: \(error)" }
                    }
                }
                Text(status)
            }
        }
        .navigationTitle("User identity")
        .task {
            // One listener per process; replace it here when opening this demo.
            GravitySDK.instance.setUserIdListener { uid in currentUid = uid }
            currentUid = await GravitySDK.instance.getUserId()
        }
        .onDisappear { GravitySDK.instance.setUserIdListener(nil) }
    }
}

private struct HeadlessCampaignDemo: View {
    @State private var response: GravityDataResponse<ContentResponse>?
    @State private var status = "Fetch a campaign to apply its content to your own view."
    @State private var reported = false
    @State private var reportedVisible = false
    @State private var isLoading = false

    @MainActor private func fetch(event: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        response = nil
        reported = false
        reportedVisible = false
        let page = PageContext(type: .homepage, data: [], location: "homepage")
        do {
            if event {
                response = try await GravitySDK.instance.triggerEventNoShow(
                    events: [CustomEvent(type: "tap", name: "Headless demo")], pageContext: page
                )
            } else {
                response = try await GravitySDK.instance.trackViewNoShow(pageContext: page)
            }
            status = response == nil ? "No content returned." : "Campaign fetched."
        } catch is CancellationError {
            status = "Cancelled."
        } catch {
            status = error.localizedDescription
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Button("Track view and fetch without showing") {
                Task { await fetch(event: false) }
            }
            .disabled(isLoading)
            Button("Trigger event and fetch without showing") {
                Task { await fetch(event: true) }
            }
            .disabled(isLoading)
            Text(status)
            if let response,
               let campaign = response.data.data.first,
               let content = campaign.payload.first?.contents.first(where: { $0.step == nil }) {
                // The app owns this view. No Gravity renderer or presentation is invoked.
                VStack {
                    Text(content.rawVariables["title"]?.stringValue
                         ?? content.variables?.elements?.first?.text ?? content.contentId)
                        .font(.title2)
                    Text("Content: \(content.contentId)")
                        .font(.caption)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .onAppear {
                    guard !reported else { return }
                    reported = true
                    // Report only once the app's own view appears, never during fetch.
                    GravitySDK.instance.sendContentEngagement(
                        engagement: ContentImpressionEngagement(content: content, campaign: campaign)
                    )
                }
                Button("Report confirmed visibility") {
                    guard !reportedVisible else { return }
                    reportedVisible = true
                    // Call once when the host confirms its own visibility criteria are met.
                    GravitySDK.instance.sendContentEngagement(
                        engagement: ContentVisibleImpressionEngagement(content: content, campaign: campaign)
                    )
                }
                .disabled(reportedVisible)
                DisclosureGroup("Raw response JSON") {
                    ScrollView {
                        Text(String(describing: response.json)).font(.caption)
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Own campaign rendering")
    }
}
