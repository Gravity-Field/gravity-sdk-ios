import SwiftUI

struct GravityFullScreenContent: View {
    let content: CampaignContent
    let campaign: Campaign
    let onClickCallback: (OnClickModel) -> Void
    
    private var frameUi: FrameUI? {
        content.variables.frameUI
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
    
    private var close: Close? {
        frameUi?.close
    }
    
    var body: some View {
        ZStack {
            VStack(alignment: horizontalAlignment) {
                GravityElements(
                    content: content,
                    campaign: campaign,
                    onClickCallback: onClickCallback
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .applyIf(padding != nil) {
                $0.padding(.init(
                    top: padding!.top,
                    leading: padding!.left,
                    bottom: padding!.bottom,
                    trailing: padding!.right
                ))
            }
            .background(style?.backgroundColor)
            
            if let close = close {
                CloseButton(close: close, onClickCallback: onClickCallback)
            }
        }
    }
}
