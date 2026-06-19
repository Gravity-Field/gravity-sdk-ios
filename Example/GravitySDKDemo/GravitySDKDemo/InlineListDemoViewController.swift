import GravitySDK
import SwiftUI
import UIKit

class InlineListDemoViewController: UIViewController, UITableViewDataSource,
    UITableViewDelegate
{

    private let pageContext = PageContext(
        type: .homepage,
        data: [],
        location: "recycler_view"
    )

    private let tableView = UITableView()
    private let itemCount = 20

    private enum CellType: Int {
        case inlineList = 0
        case text = 1
        case rectangle = 2
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "InlineListView Demo"
        view.backgroundColor = .white

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.register(
            InlineListCell.self,
            forCellReuseIdentifier: InlineListCell.reuseId
        )
        tableView.register(
            ListTextCell.self,
            forCellReuseIdentifier: ListTextCell.reuseId
        )
        tableView.register(
            ListRectangleCell.self,
            forCellReuseIdentifier: ListRectangleCell.reuseId
        )

        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func cellType(for indexPath: IndexPath) -> CellType {
        if indexPath.row == 0 { return .inlineList }
        return indexPath.row % 2 == 0 ? .rectangle : .text
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int)
        -> Int
    {
        itemCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
        -> UITableViewCell
    {
        switch cellType(for: indexPath) {
        case .inlineList:
            let cell =
                tableView.dequeueReusableCell(
                    withIdentifier: InlineListCell.reuseId,
                    for: indexPath
                ) as! InlineListCell
            cell.configure(pageContext: pageContext)
            return cell
        case .text:
            let cell =
                tableView.dequeueReusableCell(
                    withIdentifier: ListTextCell.reuseId,
                    for: indexPath
                ) as! ListTextCell
            cell.configure(title: "Title \(indexPath.row)")
            return cell
        case .rectangle:
            return tableView.dequeueReusableCell(
                withIdentifier: ListRectangleCell.reuseId,
                for: indexPath
            )
        }
    }

    func tableView(
        _ tableView: UITableView,
        heightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        switch cellType(for: indexPath) {
        case .inlineList: return 172
        case .text: return UITableView.automaticDimension
        case .rectangle: return 150
        }
    }
}

private class InlineListCell: UITableViewCell {
    static let reuseId = "InlineListCell"

    private let inlineListView = GravityInlineListView(
        groupSelector: "slider_banner"
    )

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        inlineListView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(inlineListView)
        NSLayoutConstraint.activate([
            inlineListView.topAnchor.constraint(equalTo: contentView.topAnchor),
            inlineListView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor
            ),
            inlineListView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor
            ),
            inlineListView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(pageContext: PageContext) {
        inlineListView.initialize(pageContext: pageContext) {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private class ListTextCell: UITableViewCell {
    static let reuseId = "ListTextCell"

    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 16
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 16
            ),
            titleLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -16
            ),
            titleLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -16
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
    }
}

private class ListRectangleCell: UITableViewCell {
    static let reuseId = "ListRectangleCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        let colorView = UIView()
        colorView.backgroundColor = UIColor.systemPurple
        colorView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(colorView)
        NSLayoutConstraint.activate([
            colorView.topAnchor.constraint(equalTo: contentView.topAnchor),
            colorView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor
            ),
            colorView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor
            ),
            colorView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct InlineListDemoViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> InlineListDemoViewController {
        InlineListDemoViewController()
    }

    func updateUIViewController(
        _ uiViewController: InlineListDemoViewController,
        context: Context
    ) {}
}
