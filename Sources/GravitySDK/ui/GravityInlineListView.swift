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

    public convenience init(groupSelector: String) {
        self.init(frame: .zero)
        self.groupSelector = groupSelector
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

    @State private var items: [InlineListViewItem]?
    @State private var isLoading = true

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
        .onReceive(pageContextProvider.$pageContext) { newContext in
            if let pageContext = newContext {
                loadContent(pageContext: pageContext)
            }
        }
    }

    private func loadContent(pageContext: PageContext) {
        guard items == nil else { return }
        isLoading = true
        Task {
            do {
                let result = await GravitySDK.instance.getContentByGroupSelector(
                    groupSelector: groupSelector,
                    pageContext: pageContext
                )
                await MainActor.run {
                    isLoading = false
                    guard let result else {
                        changeHeight(0)
                        return
                    }
                    var contentItems: [InlineListViewItem] = []
                    for campaign in result.data {
                        guard let payload = campaign.payload.first,
                              let content = payload.contents.firstByStepNullsFirst()
                        else { continue }
                        contentItems.append(
                            InlineListViewItem(campaign: campaign, content: content)
                        )
                    }
                    items = contentItems

                    let maxHeight = contentItems
                        .compactMap {
                            $0.content.variables?.frameUI?.container.style?.size?.height
                        }
                        .max()
                    changeHeight(maxHeight ?? 0)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    changeHeight(0)
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
