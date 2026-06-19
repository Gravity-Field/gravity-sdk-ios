import SwiftUI

struct GravityFullScreenContent: View {
    let content: CampaignContent
    let campaign: Campaign
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

    var body: some View {
        ContentVisibilityTracker(content: content, campaign: campaign) {
            ZStack {
                VStack(alignment: horizontalAlignment) {
                    GravityElements(
                        content: content,
                        campaign: campaign,
                        onClickCallback: onClickCallback,
                        item: item
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: verticalAlignment)
                .applyIf(padding != nil) {
                    $0.padding(.init(
                        top: padding!.top,
                        leading: padding!.left,
                        bottom: padding!.bottom,
                        trailing: padding!.right
                    ))
                }
                .background(
                    GravityBackgroundView(
                        backgroundColor: style?.backgroundColor ?? Color(.systemBackground),
                        backgroundImage: style?.backgroundImage,
                        backgroundFit: style?.backgroundFit
                    )
                )

                if let close = close {
                    CloseButton(close: close, onClickCallback: onClickCallback)
                }
            }
        }
        .onAppear {
            ContentEventService.instance.sendContentImpression(content, campaign)
        }
    }
}
