import SwiftUI
import UIKit

struct GravityBottomSheetContent: View {
    let content: CampaignContent
    let campaign: Campaign
    let impressionSession: ModalImpressionSession
    let onBindClose: (@escaping () -> Void) -> Void
    let onClickCallback: (OnClickModel) -> Void
    let onDismiss: () -> Void
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
    
    private var close: Close? {
        frameUi?.close
    }

    private var sheetBackgroundColor: Color {
        style?.backgroundColor ?? Color(.systemBackground)
    }

    private var imagePrerollDelay: TimeInterval {
        hasUncachedRemoteImage ? 0.25 : 0
    }

    private var hasUncachedRemoteImage: Bool {
        if let backgroundImage = style?.backgroundImage,
           let url = URL(string: backgroundImage),
           !url.isFileURL,
           !UIImageLoader.isCached(url)
        {
            return true
        }
        guard let elements = content.variables?.elements else { return false }
        return elements.contains { element in
            guard element.type == .image else { return false }
            guard let url = imageURL(for: element), !url.isFileURL else { return false }
            return !UIImageLoader.isCached(url)
        }
    }

    private func imageURL(for element: Element) -> URL? {
        let src: String?
        if let item = item, let key = element.src {
            src = item.values[key]
        } else {
            src = element.src
        }
        guard let src = src else { return nil }
        return URL(string: src)
    }

    @State private var showSheet = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            sheet(maximumContentHeight: geometry.size.height,
                  bottomInset: geometry.safeAreaInsets.bottom)
        }
    }

    private func sheet(maximumContentHeight: CGFloat, bottomInset: CGFloat) -> some View {
        let contentOverflows = contentHeight > maximumContentHeight + 0.5
        return CustomSheet(
                isPresented: $showSheet,
                cornerRadius: style?.cornerRadius ?? 0,
                imagePrerollDelay: imagePrerollDelay,
                onWillDismiss: {
                    impressionSession.explicitClose()
                },
                onDismiss: onDismiss,
                containerHeight: maximumContentHeight + bottomInset
            ) {
                ModalContentVisibilityTracker(session: impressionSession) {
                    VStack(spacing: 0) {
                        ZStack {
                            ScrollView {
                                VStack(alignment: horizontalAlignment) {
                                    GravityElements(
                                        content: content,
                                        campaign: campaign,
                                        onClickCallback: onClickCallback,
                                        item: item
                                    )
                                }
                                .frame(maxWidth: .infinity)
                                .applyIf(padding != nil) {
                                    $0.padding(.init(
                                        top: padding!.top,
                                        leading: padding!.left,
                                        bottom: padding!.bottom,
                                        trailing: padding!.right
                                    ))
                                }
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear
                                            .onAppear { contentHeight = geometry.size.height }
                                            .onChange(of: geometry.size.height) { contentHeight = $0 }
                                    }
                                )
                                .background(GravityScrollConfiguration(isEnabled: contentOverflows))
                                .gravityScrollContent()
                            }
                            .gravityScrollBehavior(isEnabled: contentOverflows)
                            .frame(height: min(contentHeight, maximumContentHeight))

                            if let close = close {
                                CloseButton(close: close, onClickCallback: onClickCallback)
                            }
                        }
                        .background(
                            GravityBackgroundView(
                                backgroundColor: sheetBackgroundColor,
                                backgroundImage: style?.backgroundImage,
                                backgroundFit: style?.backgroundFit
                            )
                        )

                        sheetBackgroundColor
                            .frame(height: bottomInset)
                    }
                    .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear {
                onBindClose {
                    showSheet = false
                }
                ContentEventService.instance.sendContentImpression(content, campaign)
                showSheet = true
            }
    }

}

private let customSheetOpenAnimationDuration: TimeInterval = 0.6

struct CustomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let cornerRadius: CGFloat
    let imagePrerollDelay: TimeInterval
    let onWillDismiss: () -> Void
    let onDismiss: () -> Void
    let containerHeight: CGFloat
    var allowsDrag: Bool = true
    @ViewBuilder let content: () -> Content

    @State private var isVisible = false
    @State private var slideOffset: CGFloat = 0
    @State private var dimOpacity: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var revealWindow: GravityImageRevealWindow?

    private var screenHeight: CGFloat {
        max(1, containerHeight)
    }

    private var currentDimOpacity: CGFloat {
        max(0, dimOpacity - dragOffset / screenHeight)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isVisible {
                Color.black
                    .opacity(Double(currentDimOpacity))
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPresented = false
                    }

                content()
                    .environment(\.gravityImageRevealWindow, revealWindow)
                    .clipShape(
                        CustomCorner(
                            radius: cornerRadius,
                            corners: [.topLeft, .topRight]
                        )
                    )
                    .background(SheetDragGesture(isEnabled: allowsDrag && isPresented, changed: { translation in
                        dragOffset = min(translation, screenHeight * 0.6)
                    }, ended: { translation, velocity in
                        if translation > screenHeight * 0.3 || velocity > 700 {
                            isPresented = false
                        } else {
                            withAnimation(.spring()) { dragOffset = 0 }
                        }
                    }))
                    .offset(y: slideOffset + dragOffset)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: isPresented) { newValue in
            if newValue {
                openSheet()
            } else if isVisible {
                closeSheet()
            }
        }
    }

    private func openSheet() {
        isVisible = true
        slideOffset = screenHeight
        dimOpacity = 0
        dragOffset = 0

        let start = Date().addingTimeInterval(imagePrerollDelay)
        revealWindow = GravityImageRevealWindow(
            animationStart: start,
            animationEnd: start.addingTimeInterval(customSheetOpenAnimationDuration)
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + imagePrerollDelay) {
            guard isPresented, isVisible else { return }
            withAnimation(.spring()) {
                slideOffset = 0
                dimOpacity = 0.3
            }
        }
    }

    private func closeSheet() {
        onWillDismiss()
        withAnimation(.spring()) {
            slideOffset = screenHeight
            dimOpacity = 0
            dragOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isVisible = false
            onDismiss()
        }
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
