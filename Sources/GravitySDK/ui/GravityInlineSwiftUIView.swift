import SwiftUI
import UIKit

private final class PresentingViewControllerHolder {
    weak var viewController: UIViewController?
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

    @State private var campaign: Campaign?
    @State private var contentHeight: CGFloat?
    @State private var isLoading = true
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
        .onAppear(perform: loadContent)
        .onChange(of: selector) { _ in
            campaign = nil
            loadContent()
        }
        .background(
            ViewControllerResolver { viewController in
                presentingViewControllerHolder.viewController = viewController
            }
        )
    }

    private func loadContent() {
        guard campaign == nil else { return }
        isLoading = true
        Task {
            do {
                let result = try await GravitySDK.instance.getContentBySelector(
                    selector: selector,
                    pageContext: pageContext
                )
                await MainActor.run {
                    isLoading = false
                    campaign = result?.data.first
                    let payload = campaign?.payload.first
                    let content = payload?.contents.firstByStep()
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


