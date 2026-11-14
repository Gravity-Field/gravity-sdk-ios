import SwiftUI
import UIKit

public class GravityInlineListView: UIView {

    @IBInspectable public var groupSelector: String = ""
    @IBInspectable public var color: UIColor = .clear
    @IBInspectable public var cornerRadius: CGFloat = 0

    private var hostingController: UIHostingController<GravityInlineListContentView>?
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

    /// Recommendation rules sent with this placement's content request, for example
    /// the catalog filters the user applied. Changing them reloads the content.
    public var rules: [RtRule]? {
        get { pageContextProvider.rules }
        set { pageContextProvider.provide(rules: newValue) }
    }

    public convenience init(groupSelector: String, rules: [RtRule]? = nil) {
        self.init(frame: .zero)
        self.groupSelector = groupSelector
        self.rules = rules
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

        let contentView = GravityInlineListContentView(
            groupSelector: groupSelector,
            pageContextProvider: pageContextProvider,
            color: Color(color),
            cornerRadius: cornerRadius,
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

private struct InlineListViewItem: Identifiable {
    let id = UUID()
    let campaign: Campaign
    let content: CampaignContent
}

private struct GravityInlineListContentView: View {
    let groupSelector: String
    @ObservedObject var pageContextProvider: PageContextProvider
    let color: Color
    let cornerRadius: CGFloat
    let loader: AnyView?
    let presentingViewController: () -> UIViewController?
    let changeHeight: (CGFloat) -> Void

    @StateObject private var contentState = InlineContentState<[InlineListViewItem]>()
    private var items: [InlineListViewItem]? { contentState.value }
    private var isLoading: Bool { contentState.isLoading }

    var body: some View {
        Group {
            if isLoading, let loader = loader {
                loader
            } else if let items = items {
                ItemListView(
                    items: items,
                    presentingViewController: presentingViewController
                )
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color)
        .applyIf(cornerRadius > 0) {
            $0.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .onReceive(contentState.$height) { height in
            if let height { changeHeight(height) }
        }
        .background(InlinePlacementLifecycle(onMount: {
            contentState.appear()
            if let pageContext = pageContextProvider.pageContext {
                loadContent(pageContext: pageContext, rules: pageContextProvider.rules)
            }
        }, onUnmount: { contentState.disappear() }))
        .onReceive(pageContextProvider.$pageContext.dropFirst()) { newContext in
            if let pageContext = newContext {
                contentState.pageContextChanged()
                loadContent(pageContext: pageContext, rules: pageContextProvider.rules)
            }
        }
        .onReceive(pageContextProvider.$rules.dropFirst()) { newRules in
            // New filters make the shown content stale, unlike a new page context.
            // Published emits before the property changes, so use the emitted value.
            contentState.clear()
            if let pageContext = pageContextProvider.pageContext {
                loadContent(pageContext: pageContext, rules: newRules)
            }
        }
    }

    private func loadContent(pageContext: PageContext, rules: [RtRule]?) {
        guard let load = contentState.begin() else { return }
        let sdk = GravitySDK.instance
        Task {
            let result = await sdk.getContentByGroupSelector(
                groupSelector: groupSelector, pageContext: pageContext, rules: rules)
            await MainActor.run {
                guard let result else {
                    if contentState.complete(load, value: nil, height: 0) {
                        loadContent(pageContext: pageContextProvider.pageContext ?? pageContext,
                                rules: pageContextProvider.rules)
                    }
                    return
                }
                var contentItems: [InlineListViewItem] = []
                for campaign in result.data {
                    guard let payload = campaign.payload.first,
                          let content = payload.contents.firstByStepNullsFirst() else { continue }
                    contentItems.append(InlineListViewItem(campaign: campaign, content: content))
                }
                let maxHeight = contentItems.compactMap {
                    $0.content.variables?.frameUI?.container.style?.size?.height
                }.max()
                if contentState.complete(load, value: contentItems.isEmpty ? nil : contentItems, height: CGFloat(maxHeight ?? 0)) {
                    loadContent(pageContext: pageContextProvider.pageContext ?? pageContext,
                                rules: pageContextProvider.rules)
                }
            }
        }
    }

}

private struct ItemListView: View {
    let items: [InlineListViewItem]
    let presentingViewController: () -> UIViewController?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    GravityInlineListItemView(
                        item: item,
                        presentingViewController: presentingViewController
                    )
                }
            }
        }
    }
}

private struct GravityInlineListItemView: View {
    let item: InlineListViewItem
    let presentingViewController: () -> UIViewController?

    private var content: CampaignContent { item.content }
    private var campaign: Campaign { item.campaign }

    private var style: Style? {
        content.variables?.frameUI?.container.style
    }

    private var horizontalAlignment: HorizontalAlignment {
        style?.contentAlignment?.toHorizontalAlignment() ?? .center
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
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
            .frame(maxWidth: .infinity)
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
        }
        .applyIf(style?.size?.width != nil) {
            $0.frame(width: style!.size!.width!)
        }
        .applyIf(style?.size?.height != nil) {
            $0.frame(height: style!.size!.height!)
        }
        .applyIf(style?.layoutWidth == .matchParent) {
            $0.frame(width: UIScreen.main.bounds.width)
        }
        .background(
            GravityBackgroundView(
                backgroundColor: style?.backgroundColor ?? Color(.systemBackground),
                backgroundImage: style?.backgroundImage,
                backgroundFit: style?.backgroundFit
            )
        )
        .applyIf(style?.cornerRadius != nil) {
            $0.clipShape(
                RoundedRectangle(cornerRadius: style!.cornerRadius!)
            )
        }
    }
}
