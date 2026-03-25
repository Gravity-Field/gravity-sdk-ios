import SwiftUI

struct GravitySnackbarContent: View {
    let content: CampaignContent
    let campaign: Campaign
    let onClickCallback: (OnClickModel) -> Void
    let onDismiss: () -> Void

    @State private var hasSentImpression = false

    @State var showSnackbar = false

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

    private var onClick: OnClickModel? {
        container?.onClick
    }

    private var elements: [Element] {
        content.variables.elements ?? []
    }

    private var texts: [Element] {
        elements.filter { $0.type == .text }
    }

    private var images: [Element] {
        elements.filter { $0.type == .image }
    }

    var body: some View {
        return Group {
            if let frameUi = frameUi, showSnackbar {
                contentView(frameUi: frameUi)
            }
        }
        .onAppear {

            withAnimation(.default) {
                showSnackbar = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                animateWithCompletion(
                    {
                        showSnackbar = false
                    },
                    {
                        onDismiss()
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func contentView(frameUi: FrameUI) -> some View {
        let container = frameUi.container
        let style = container.style
        let view: any View =
            switch content.templateSystemName {
            case .snackbar1: elementsContentView1()
            case .snackbar2: elementsContentView2()
            default: EmptyView()
            }

        ZStack {
            AnyView(view)
                .applyIf(padding != nil) { view in
                    view.padding(
                        EdgeInsets(
                            top: padding!.top,
                            leading: padding!.left,
                            bottom: padding!.bottom,
                            trailing: padding!.right
                        )
                    )
                }
                .frame(maxWidth: .infinity)
                .background(style.backgroundColor ?? Color.white)
                .cornerRadius(style.cornerRadius ?? 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .applyIf(onClick != nil) { view in
            view.onTapGesture {
                onClickCallback(onClick!)
            }
        }
    }

    @ViewBuilder
    private func elementsContentView1() -> some View {
        HStack(alignment: .center) {
            if let firstImage = images.first {
                GravityImage(
                    element: firstImage,
                    onClickCallback: onClickCallback
                )
                Spacer().frame(width: 12)
            }

            VStack(alignment: .leading) {
                if let firstText = texts.first {
                    GravityText(
                        element: firstText,
                        onClickCallback: onClickCallback
                    )
                }

                if texts.count > 1, let secondText = texts.dropFirst().first {
                    Spacer().frame(height: 4)
                    GravityText(
                        element: secondText,
                        onClickCallback: onClickCallback
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if images.count > 1, let secondImage = images.dropFirst().first {
                Spacer().frame(width: 8)
                GravityImage(
                    element: secondImage,
                    onClickCallback: onClickCallback
                )
            }
        }
    }

    @ViewBuilder
    private func elementsContentView2() -> some View {

        let texts = elements.filter { $0.type == .text }

        let image = elements.first { $0.type == .image }

        let button = elements.first { $0.type == .button }

        HStack(alignment: .top) {
            if let image = image {
                GravityImage(element: image, onClickCallback: onClickCallback)
                Spacer().frame(width: 12)
            }

            VStack(alignment: .leading) {
                if let firstText = texts.first {
                    GravityText(
                        element: firstText,
                        onClickCallback: onClickCallback
                    )
                }

                if texts.count > 1, let secondText = texts.dropFirst().first {
                    Spacer().frame(height: 4)
                    GravityText(
                        element: secondText,
                        onClickCallback: onClickCallback
                    )
                }

                if let button = button {
                    Spacer().frame(height: 8)
                    GravityButton(
                        element: button,
                        onClickCallback: onClickCallback
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

func animateWithCompletion(
    _ body: () -> Void,
    _ completion: @escaping () -> Void
) {
    withAnimation(.easeInOut(duration: 0.5)) {
        body()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        completion()
    }
}
