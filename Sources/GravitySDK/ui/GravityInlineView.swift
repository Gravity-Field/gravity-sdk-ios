import SwiftUI
import UIKit

public class GravityInlineView: UIView {

    @IBInspectable public var selector: String = ""

    private var hostingController: UIHostingController<GravityInlineContentView>?
    private let pageContextProvider = PageContextProvider()
    private var heightConstraint: NSLayoutConstraint?

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
            hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor),
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
    let changeHeight: (CGFloat) -> Void

    @State private var campaign: Campaign?
    @State private var isLoading = false

    private var style: Style? {
        guard let campaign = campaign,
              let content = campaign.payload.first?.contents.first
        else { return nil }
        return content.variables?.frameUI?.container.style
    }

    private var horizontalAlignment: HorizontalAlignment {
        style?.contentAlignment?.toHorizontalAlignment() ?? .center
    }

    var body: some View {
        Group {
            if let campaign = campaign,
               let content = campaign.payload.first?.contents.first
            {
                ContentVisibilityTracker(content: content, campaign: campaign) {
                    VStack(alignment: horizontalAlignment) {
                        GravityElements(
                            content: content,
                            campaign: campaign,
                            onClickCallback: { onClickModel in
                                GravitySDK.instance.onClickHandler(
                                    onClickModel: onClickModel,
                                    content: content,
                                    campaign: campaign
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
                .applyIf(style?.backgroundColor != nil) {
                    $0.background(style!.backgroundColor!)
                }
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
        .onReceive(pageContextProvider.$pageContext) { newContext in
            if let pageContext = newContext {
                loadContent(pageContext: pageContext)
            }
        }
    }

    private func loadContent(pageContext: PageContext) {
        guard campaign == nil else { return }
        isLoading = true
        Task {
            do {
                let result = try await GravitySDK.instance.getContentBySelector(
                    selector: selector,
                    pageContext: pageContext,
                )
                await MainActor.run {
                    isLoading = false
                    campaign = result?.data.first
                    let payload = campaign?.payload.first
                    let content = payload?.contents.first
                    if content == nil {
                        changeHeight(0)
                    } else if let height = content?.variables?.frameUI?.container
                        .style?.size?.height
                    {
                        changeHeight(height)
                    }
                }
            } catch {
                await MainActor.run {
                    changeHeight(0)
                    isLoading = false
                }
            }
        }
    }

    private func sendImpression(content: CampaignContent, campaign: Campaign) {
        ContentEventService.instance.sendContentImpression(content, campaign)
    }
}
