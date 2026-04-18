import SwiftUI

public struct GravityInlineSwiftUIView: View {
    let selector: String
    let pageContext: PageContext

    public init(selector: String, pageContext: PageContext) {
        self.selector = selector
        self.pageContext = pageContext
    }

    @State private var campaign: Campaign?
    @State private var contentHeight: CGFloat?
    @State private var isLoading = false

    private var style: Style? {
        guard let campaign = campaign,
            let content = campaign.payload.first?.contents.first
        else { return nil }
        return content.variables?.frameUI?.container.style
    }

    private var horizontalAlignment: HorizontalAlignment {
        style?.contentAlignment?.toHorizontalAlignment() ?? .center
    }

    public var body: some View {
        Group {
            if let campaign = campaign,
                let content = campaign.payload.first?.contents.first
            {
                ContentVisibilityTracker(content: content, campaign: campaign) {
                    VStack(alignment: horizontalAlignment) {
                        GravityElements(
                            content: content,
                            campaign: campaign,
                            onClickCallback: { onClickModel in
                                GravitySDK.instance.onClickHandler(
                                    onClickModel: onClickModel,
                                    content: content,
                                    campaign: campaign
                                )
                            }
                        )
                    }
                }
                .applyIf(style?.layoutWidth == .matchParent) {
                    $0.frame(maxWidth: .infinity)
                }
                .applyIf(style?.padding != nil) {
                    $0.padding(
                        .init(
                            top: style!.padding!.top,
                            leading: style!.padding!.left,
                            bottom: style!.padding!.bottom,
                            trailing: style!.padding!.right
                        )
                    )
                }
                .applyIf(style?.backgroundColor != nil) {
                    $0.background(style!.backgroundColor!)
                }
                .applyIf(style?.cornerRadius != nil) {
                    $0.clipShape(
                        RoundedRectangle(cornerRadius: style!.cornerRadius!)
                    )
                }
                .applyIf(style?.margin != nil) {
                    $0.padding(
                        .init(
                            top: style!.margin!.top,
                            leading: style!.margin!.left,
                            bottom: style!.margin!.bottom,
                            trailing: style!.margin!.right
                        )
                    )
                }
                .onAppear {
                    sendImpression(content: content, campaign: campaign)
                }
            } else {
                Color.clear
            }
        }
        .applyIf(contentHeight != nil) {
            $0.forceFrame(height: contentHeight!)
        }
        .onAppear(perform: loadContent)
        .onChange(of: selector) { _ in
            campaign = nil
            loadContent()
        }
    }

    private func loadContent() {
        guard campaign == nil else { return }
        isLoading = true
        Task {
            do {
                let result = try await GravitySDK.instance.getContentBySelector(
                    selector: selector,
                    pageContext: pageContext,
                )
                await MainActor.run {
                    isLoading = false
                    campaign = result?.data.first
                    let payload = campaign?.payload.first
                    let content = payload?.contents.first
                    if content == nil {
                        contentHeight = 0.0
                    } else if let height = content?.variables?.frameUI?.container
                        .style?.size?.height
                    {
                        contentHeight = height
                    }
                }
            } catch {
                await MainActor.run {
                    contentHeight = 0.0
                    isLoading = false
                }
            }
        }
    }

    private func sendImpression(content: CampaignContent, campaign: Campaign) {
        ContentEventService.instance.sendContentImpression(content, campaign)
    }
}


