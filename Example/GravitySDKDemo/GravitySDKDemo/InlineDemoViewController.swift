import GravitySDK
import SwiftUI
import UIKit

class InlineDemoViewController: UIViewController, UITableViewDataSource,
    UITableViewDelegate
{

    private let pageContext = PageContext(
        type: .homepage,
        data: [],
        location: "table_view"
    )

    private let tableView = UITableView()
    private let itemCount = 20

    private enum CellType: Int {
        case inline = 0
        case text = 1
        case rectangle = 2
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "InlineView Demo"
        view.backgroundColor = .white

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.register(
            InlineCell.self,
            forCellReuseIdentifier: InlineCell.reuseId
        )
        tableView.register(
            TextCell.self,
            forCellReuseIdentifier: TextCell.reuseId
        )
        tableView.register(
            RectangleCell.self,
            forCellReuseIdentifier: RectangleCell.reuseId
        )

        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func cellType(for indexPath: IndexPath) -> CellType {
        if indexPath.row == 0 { return .inline }
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
        case .inline:
            let cell =
                tableView.dequeueReusableCell(
                    withIdentifier: InlineCell.reuseId,
                    for: indexPath
                ) as! InlineCell
            cell.configure(pageContext: pageContext)
            return cell
        case .text:
            let cell =
                tableView.dequeueReusableCell(
                    withIdentifier: TextCell.reuseId,
                    for: indexPath
                ) as! TextCell
            cell.configure(title: "Title \(indexPath.row)")
            return cell
        case .rectangle:
            return tableView.dequeueReusableCell(
                withIdentifier: RectangleCell.reuseId,
                for: indexPath
            )
        }
    }

    func tableView(
        _ tableView: UITableView,
        heightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        switch cellType(for: indexPath) {
        case .inline: return 140
        case .text: return UITableView.automaticDimension
        case .rectangle: return 150
        }
    }
}

private class InlineCell: UITableViewCell {
    static let reuseId = "InlineCell"

    private let inlineView = GravityInlineView(
        selector: "homepage_inline_banner"
    )

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        inlineView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(inlineView)
        NSLayoutConstraint.activate([
            inlineView.topAnchor.constraint(equalTo: contentView.topAnchor),
            inlineView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor
            ),
            inlineView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor
            ),
            inlineView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor
            ),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(pageContext: PageContext) {
        inlineView.initialize(pageContext: pageContext)
    }
}

private class TextCell: UITableViewCell {
    static let reuseId = "TextCell"

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
            ),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
    }
}

private class RectangleCell: UITableViewCell {
    static let reuseId = "RectangleCell"

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
            ),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct InlineDemoViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> InlineDemoViewController {
        InlineDemoViewController()
    }

    func updateUIViewController(
        _ uiViewController: InlineDemoViewController,
        context: Context
    ) {}
}
