import SwiftUI

struct GravityFullScreenContent: View {
    let content: CampaignContent
    let campaign: Campaign
    let impressionSession: ModalImpressionSession
    let onClickCallback: (OnClickModel) -> Void
    var item: Item? = nil

    private var frameUi: FrameUI? {
        content.variables?.frameUI
    }
    
    private var container: Container? {
        frameUi?.container
    }
    
    private var style: Style? {
        container?.style
    }
    
    private var padding: GravityPadding? {
        style?.padding
    }
    
    private var horizontalAlignment: HorizontalAlignment {
        style?.contentAlignment?.toHorizontalAlignment()
                                ?? HorizontalAlignment.center
    }

    private var verticalAlignment: Alignment {
        style?.verticalAlignment?.toAlignment() ?? .top
    }
    
    private var close: Close? {
        frameUi?.close
    }

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ModalContentVisibilityTracker(session: impressionSession) {
            ZStack {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: horizontalAlignment) {
                            GravityElements(
                                content: content,
                                campaign: campaign,
                                onClickCallback: onClickCallback,
                                item: item
                            )
                        }
                        .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - (padding?.top ?? 0) - (padding?.bottom ?? 0)), alignment: verticalAlignment)
                        .background(
                            GeometryReader { contentGeometry in
                                Color.clear
                                    .onAppear { contentHeight = contentGeometry.size.height }
                                    .onChange(of: contentGeometry.size.height) { contentHeight = $0 }
                            }
                        )
                        .background(GravityScrollConfiguration(isEnabled: contentHeight > max(0, geometry.size.height - (padding?.top ?? 0) - (padding?.bottom ?? 0)) + 0.5))
                        .gravityScrollContent()
                    }
                    .gravityScrollBehavior(isEnabled: contentHeight > max(0, geometry.size.height - (padding?.top ?? 0) - (padding?.bottom ?? 0)) + 0.5)
                    .padding(EdgeInsets(top: padding?.top ?? 0, leading: padding?.left ?? 0,
                                        bottom: padding?.bottom ?? 0, trailing: padding?.right ?? 0))
                }
                .clipped()
                .background(
                    GravityBackgroundView(
                        backgroundColor: style?.backgroundColor ?? Color(.systemBackground),
                        backgroundImage: style?.backgroundImage,
                        backgroundFit: style?.backgroundFit
                    )
                    .ignoresSafeArea()
                )

                if let close = close {
                    CloseButton(close: close, onClickCallback: onClickCallback)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            ContentEventService.instance.sendContentImpression(content, campaign)
        }
    }
}
