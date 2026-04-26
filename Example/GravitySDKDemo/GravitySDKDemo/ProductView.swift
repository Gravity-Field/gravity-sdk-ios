import GravitySDK
import UIKit

final class ProductView: UIView {

    init(slot: Slot) {
        super.init(frame: .zero)
        setup(slot: slot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 160, height: 210)
    }

    private func setup(slot: Slot) {
        backgroundColor = .white
        layer.cornerRadius = 4
        layer.masksToBounds = true

        let imageUrl = slot.item["imageUrl"] as? String
        let name = slot.item["name"] as? String ?? ""
        let price = slot.item["price"] as? String ?? ""
        let oldPrice = slot.item["oldPrice"] as? String

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.heightAnchor.constraint(equalToConstant: 112).isActive = true
        loadImage(from: imageUrl, into: imageView)

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.textColor = .black
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail

        let oldPriceLabel = UILabel()
        oldPriceLabel.font = .systemFont(ofSize: 11)
        oldPriceLabel.textColor = UIColor(red: 83.0 / 255.0, green: 88.0 / 255.0, blue: 98.0 / 255.0, alpha: 1)
        oldPriceLabel.attributedText = NSAttributedString(
            string: oldPrice ?? "",
            attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        )

        let priceLabel = UILabel()
        priceLabel.text = price
        priceLabel.font = .boldSystemFont(ofSize: 12)
        priceLabel.textColor = .black

        let priceColumn = UIStackView(arrangedSubviews: [oldPriceLabel, priceLabel])
        priceColumn.axis = .vertical

        let priceRow = UIStackView(arrangedSubviews: [priceColumn, UIView()])
        priceRow.axis = .horizontal

        let stack = UIStackView(arrangedSubviews: [
            imageView,
            spacer(height: 6),
            wrap(nameLabel, horizontalPadding: 12),
            spacer(height: 8),
            wrap(priceRow, horizontalPadding: 12),
            UIView()
        ])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func spacer(height: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func wrap(_ view: UIView, horizontalPadding: CGFloat) -> UIView {
        let container = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func loadImage(from urlString: String?, into imageView: UIImageView) {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            return
        }
        Task { [weak imageView] in
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = UIImage(data: data)
            else { return }
            await MainActor.run {
                imageView?.image = image
            }
        }
    }
}
