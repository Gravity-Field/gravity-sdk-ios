import SwiftUI
import UIKit

private final class PresentingViewControllerHolder {
    weak var viewController: UIViewController?
}

private final class InlinePageContextHolder {
    var latest: PageContext?
}

public struct GravityInlineSwiftUIView: View {
    let selector: String
    let pageContext: PageContext
    let loader: AnyView?

    public init(selector: String, pageContext: PageContext) {
        self.selector = selector
        self.pageContext = pageContext
        self.loader = nil
    }

    public init<Loader: View>(
        selector: String,
        pageContext: PageContext,
        @ViewBuilder loader: () -> Loader
    ) {
        self.selector = selector
        self.pageContext = pageContext
        self.loader = AnyView(loader())
    }

    @StateObject private var contentState = InlineContentState<Campaign>()
    @State private var pageContextHolder = InlinePageContextHolder()
    private var campaign: Campaign? { contentState.value }
    private var contentHeight: CGFloat? { contentState.height }
    private var isLoading: Bool { contentState.isLoading }
    @State private var presentingViewControllerHolder = PresentingViewControllerHolder()

    private var style: Style? {
        guard let campaign = campaign,
            let content = campaign.payload.first?.contents.firstByStep()
        else { return nil }
        return content.variables?.frameUI?.container.style
    }

    private var horizontalAlignment: HorizontalAlignment {
        style?.contentAlignment?.toHorizontalAlignment() ?? .center
    }

    private var verticalAlignment: Alignment {
        style?.verticalAlignment?.toAlignment() ?? .top
    }

    public var body: some View {
        Group {
            if isLoading, let loader = loader {
                loader
            } else if let campaign = campaign,
                let content = campaign.payload.first?.contents.firstByStep()
            {
                ContentVisibilityTracker(content: content, campaign: campaign) {
                    VStack(alignment: horizontalAlignment) {
                        GravityElements(
                            content: content,
                            campaign: campaign,
                            onClickCallback: { onClickModel in
                                guard
                                    let viewController =
                                        presentingViewControllerHolder.viewController
                                else {
                                    return
                                }
                                GravitySDK.instance.onClickHandler(
                                    onClickModel: onClickModel,
                                    content: content,
                                    campaign: campaign,
                                    viewController: viewController
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
                .background(
                    GravityBackgroundView(
                        backgroundColor: style?.backgroundColor,
                        backgroundImage: style?.backgroundImage,
                        backgroundFit: style?.backgroundFit
                    )
                )
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
            $0.forceFrame(height: contentHeight!, alignment: verticalAlignment)
        }
        .background(InlinePlacementLifecycle(onMount: {
            contentState.appear()
            loadContent()
        }, onUnmount: { contentState.disappear() }))
        .onChange(of: pageContext) { newContext in
            pageContextHolder.latest = newContext
            contentState.pageContextChanged()
            loadContent()
        }
        .onChange(of: selector) { _ in
            contentState.clear()
            loadContent()
        }
        .background(
            ViewControllerResolver { viewController in
                presentingViewControllerHolder.viewController = viewController
            }
        )
    }

    private func loadContent() {
        guard let load = contentState.begin() else { return }
        let sdk = GravitySDK.instance
        Task {
            let result = await sdk.getContentBySelector(selector: selector, pageContext: pageContextHolder.latest ?? pageContext)
            await MainActor.run {
                let campaign = result?.data.first
                let content = campaign?.payload.first?.contents.firstByStep()
                let backendHeight = content?.variables?.frameUI?.container.style?.size?.height
                let height: CGFloat? = content == nil ? 0 : backendHeight.map { CGFloat($0) }
                if contentState.complete(load, value: campaign, height: height) {
                    loadContent()
                }
            }
        }
    }

    private func sendImpression(content: CampaignContent, campaign: Campaign) {
        ContentEventService.instance.sendContentImpression(content, campaign)
    }
}

private struct ViewControllerResolver: UIViewControllerRepresentable {
    let onResolve: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> ResolverViewController {
        ResolverViewController(onResolve: onResolve)
    }

    func updateUIViewController(
        _ uiViewController: ResolverViewController,
        context: Context
    ) {
        uiViewController.onResolve = onResolve
        uiViewController.resolveIfNeeded()
    }
}

private final class ResolverViewController: UIViewController {
    var onResolve: (UIViewController) -> Void

    init(onResolve: @escaping (UIViewController) -> Void) {
        self.onResolve = onResolve
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        resolveIfNeeded()
    }

    func resolveIfNeeded() {
        if let parent = parent {
            onResolve(parent)
        }
    }
}


