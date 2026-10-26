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

    var body: some View {

            CustomSheet(
                isPresented: $showSheet,
                cornerRadius: style?.cornerRadius ?? 0,
                imagePrerollDelay: imagePrerollDelay,
                onWillDismiss: {
                    impressionSession.explicitClose(isActive: UIApplication.shared.applicationState == .active)
                },
                onDismiss: onDismiss
            ) {
                ModalContentVisibilityTracker(session: impressionSession) {
                    VStack(spacing: 0) {
                        ZStack {
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
                            .frame(height: Self.bottomSafeAreaInset)
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

    private static var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }
}

private let customSheetOpenAnimationDuration: TimeInterval = 0.6

struct CustomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let cornerRadius: CGFloat
    let imagePrerollDelay: TimeInterval
    let onWillDismiss: () -> Void
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isVisible = false
    @State private var slideOffset: CGFloat = 0
    @State private var dimOpacity: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var revealWindow: GravityImageRevealWindow?

    private var screenHeight: CGFloat {
        UIScreen.main.bounds.height
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
                    .offset(y: slideOffset + dragOffset)
                    .gesture(dragGesture)
            }
        }
        .ignoresSafeArea()
        .onChange(of: isPresented) { newValue in
            if newValue {
                openSheet()
            } else if isVisible {
                closeSheet()
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let newOffset = value.translation.height
                if newOffset > 0 && newOffset < screenHeight * 0.6 {
                    dragOffset = newOffset
                }
            }
            .onEnded { value in
                let velocity =
                    value.predictedEndTranslation.height
                    - value.translation.height

                if dragOffset > screenHeight * 0.3 || velocity > 150 {
                    isPresented = false
                } else {
                    withAnimation(.spring()) {
                        dragOffset = 0
                    }
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
