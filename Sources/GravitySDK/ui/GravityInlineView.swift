import SwiftUI
import UIKit

public class GravityInlineView: UIView {

    @IBInspectable public var selector: String = ""

    private var hostingController: UIHostingController<GravityInlineContentView>?
    private let pageContextProvider = PageContextProvider()
    private var heightConstraint: NSLayoutConstraint?
    private var loader: AnyView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupConstraints()
    }

    public convenience init(selector: String) {
        self.init(frame: .zero)
        self.selector = selector
    }

    public func initialize(pageContext: PageContext) {
        setupHostingIfNeeded()
        pageContextProvider.provide(pageContext)
    }

    public func initialize<Loader: View>(
        pageContext: PageContext,
        @ViewBuilder loader: () -> Loader
    ) {
        self.loader = AnyView(loader())
        setupHostingIfNeeded()
        pageContextProvider.provide(pageContext)
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: heightConstraint?.constant ?? 0)
    }

    private func setupConstraints() {
        let heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        self.heightConstraint = heightConstraint
    }

    private func setupHostingIfNeeded() {
        guard hostingController == nil else { return }

        let contentView = GravityInlineContentView(
            selector: selector,
            pageContextProvider: pageContextProvider,
            loader: loader,
            presentingViewController: { [weak self] in
                self?.findPresentingViewController()
            },
            changeHeight: { [weak self] height in
                guard let self else { return }
                self.heightConstraint?.constant = height
                self.invalidateIntrinsicContentSize()
                self.updateParentTableView()
            }
        )
        let hosting = UIHostingController(rootView: contentView)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        self.hostingController = hosting
    }

    private func updateParentTableView() {
        var view: UIView? = superview
        while view != nil {
            if let tableView = view as? UITableView {
                guard tableView.window != nil else { return }
                tableView.beginUpdates()
                tableView.endUpdates()
                return
            }
            view = view?.superview
        }
    }
}


internal class PageContextProvider: ObservableObject {
    @Published var pageContext: PageContext?

    func provide(_ pageContext: PageContext) {
        guard self.pageContext != pageContext else { return }
        self.pageContext = pageContext
    }
}

private struct GravityInlineContentView: View {
    let selector: String
    @ObservedObject var pageContextProvider: PageContextProvider
    let loader: AnyView?
    let presentingViewController: () -> UIViewController?
    let changeHeight: (CGFloat) -> Void

    @StateObject private var contentState = InlineContentState<Campaign>()
    private var campaign: Campaign? { contentState.value }
    private var isLoading: Bool { contentState.isLoading }

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

    var body: some View {
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
                                guard let viewController = presentingViewController() else {
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
                .frame(maxHeight: .infinity, alignment: verticalAlignment)
            } else {
                Color.clear
            }
        }
        .onReceive(contentState.$height) { height in
            if let height { changeHeight(height) }
        }
        .background(InlinePlacementLifecycle(onMount: {
            contentState.appear()
            if let pageContext = pageContextProvider.pageContext {
                loadContent(pageContext: pageContext)
            }
        }, onUnmount: { contentState.disappear() }))
        .onReceive(pageContextProvider.$pageContext.dropFirst()) { newContext in
            if let pageContext = newContext {
                contentState.pageContextChanged()
                loadContent(pageContext: pageContext)
            }
        }
    }

    private func loadContent(pageContext: PageContext) {
        guard let load = contentState.begin() else { return }
        let sdk = GravitySDK.instance
        Task {
            let result = await sdk.getContentBySelector(selector: selector, pageContext: pageContext)
            await MainActor.run {
                let campaign = result?.data.first
                let content = campaign?.payload.first?.contents.firstByStep()
                let backendHeight = content?.variables?.frameUI?.container.style?.size?.height
                let height: CGFloat? = content == nil ? 0 : backendHeight.map { CGFloat($0) }
                if contentState.complete(load, value: campaign, height: height) {
                    loadContent(pageContext: pageContextProvider.pageContext ?? pageContext)
                }
            }
        }
    }

    private func sendImpression(content: CampaignContent, campaign: Campaign) {
        ContentEventService.instance.sendContentImpression(content, campaign)
    }
}

extension UIView {
    func findPresentingViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}
