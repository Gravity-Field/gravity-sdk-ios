import SwiftUI

struct GravityModalContent: View {
    let content: CampaignContent
    let campaign: Campaign
    let onClickCallback: (OnClickModel) -> Void
    let onDismiss: () -> Void

    @State private var contentHeight: CGFloat = 0

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

    private var close: Close? {
        frameUi?.close
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onDismiss()
                }
            ContentVisibilityTracker(content: content, campaign: campaign) {
                ZStack {
                    RoundedRectangle(cornerRadius: style?.cornerRadius ?? 0)
                        .fill(style?.backgroundColor ?? Color.white)

                    GeometryReader { geometry in
                        ScrollView {
                            VStack(alignment: horizontalAlignment) {
                                GravityElements(
                                    content: content,
                                    campaign: campaign,
                                    onClickCallback: onClickCallback
                                )
                            }
                            .applyIf(padding != nil) {
                                $0.padding(
                                    .init(
                                        top: padding!.top,
                                        leading: padding!.left,
                                        bottom: padding!.bottom,
                                        trailing: padding!.right
                                    )
                                )
                            }
                            .frame(maxWidth: .infinity)
                            .background(
                                GeometryReader { innerGeometry in
                                    Color.clear
                                        .onAppear {
                                            contentHeight =
                                                innerGeometry.size.height
                                        }
                                        .onChange(of: innerGeometry.size.height) {
                                            newHeight in
                                            contentHeight = newHeight
                                        }
                                }
                            )
                        }
                    }
                    if let close = close {
                        CloseButton(close: close, onClickCallback: onClickCallback)
                    }
                }
            }
            .frame(width: UIScreen.main.bounds.width - 48)
            .frame(
                height: min(contentHeight, UIScreen.main.bounds.height * 0.8)
            )
        }
        .onAppear {
            ContentEventService.instance.sendContentImpression(content, campaign)
        }
    }
}
