import SwiftUI


struct GravityBottomSheetContent: View {
    let content: CampaignContent
    let campaign: Campaign
    let onClickCallback: (OnClickModel) -> Void
    let onDismiss: () -> Void

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
    
    @State private var showSheet = false
    @State private var sheetHeight: CGFloat? = .zero

    var body: some View {

            CustomSheet(isPresented: $showSheet, onDismiss: onDismiss) {
                ContentVisibilityTracker(content: content, campaign: campaign) {
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
                .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear {
                ContentEventService.instance.sendContentImpression(content, campaign)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01)
                {
                    showSheet.toggle()
                }
            }
    }
}

struct CustomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var lastOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black.opacity(0.3 - (offset / UIScreen.main.bounds.height))
                    .onTapGesture {
                        withAnimation(.spring()) {
                            isPresented = false
                            onDismiss()
                        }
                    }
                    .transition(.opacity)
            }
            
            if isPresented {
                content().clipShape(
                    CustomCorner(radius: 20, corners: [.topLeft, .topRight])
                )
                .offset(y: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newOffset = lastOffset + value.translation.height
                            if newOffset > 0 && newOffset < UIScreen.main.bounds.height * 0.6 {
                                offset = newOffset
                            }
                        }
                        .onEnded { value in
                            let velocity = value.predictedEndTranslation.height - value.translation.height
                            
                            if offset > UIScreen.main.bounds.height * 0.3 || velocity > 150 {
                                withAnimation(.spring()) {
                                    isPresented = false
                                    onDismiss()
                                }
                            } else {
                                withAnimation(.spring()) {
                                    offset = 0
                                }
                            }
                            lastOffset = 0
                        }
                )
                .transition(.move(edge: .bottom))
                .onChange(of: isPresented) { newValue in
                    if !newValue {
                        offset = 0
                    }
                }
            }
        }
        .animation(.spring(), value: isPresented)
    }
}

struct CustomCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
