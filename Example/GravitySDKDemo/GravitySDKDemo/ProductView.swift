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
        CGSize(width: 164, height: 250)
    }

    private func setup(slot: Slot) {
        backgroundColor = .clear

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 164),
            heightAnchor.constraint(equalToConstant: 250)
        ])

        let imageUrl = slot.item["image_url"] as? String
        let name = slot.item["name"] as? String ?? ""
        let price = slot.item["price"] as? String ?? ""
        let inStock = slot.item["in_stock"] as? Bool ?? false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        loadImage(from: imageUrl, into: imageView)

        let imageContainer = UIView()
        imageContainer.backgroundColor = .white
        imageContainer.layer.cornerRadius = 16
        imageContainer.layer.borderWidth = 1
        imageContainer.layer.borderColor = UIColor(white: 0.88, alpha: 1).cgColor
        imageContainer.layer.masksToBounds = true
        imageContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageContainer.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor)
        ])

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        nameLabel.textColor = .black
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail

        let priceLabel = UILabel()
        priceLabel.text = "\(price) ₽"
        priceLabel.font = .boldSystemFont(ofSize: 16)
        priceLabel.textColor = inStock
            ? UIColor(red: 1.0, green: 0.30, blue: 0.30, alpha: 1)
            : UIColor(white: 0.46, alpha: 1)

        let cartIcon = UIImageView(image: UIImage(systemName: "cart"))
        cartIcon.tintColor = .systemRed
        cartIcon.contentMode = .scaleAspectFit
        cartIcon.setContentHuggingPriority(.required, for: .horizontal)

        let chipContent = UIStackView(arrangedSubviews: [priceLabel, cartIcon])
        chipContent.axis = .horizontal
        chipContent.spacing = 8
        chipContent.alignment = .center
        chipContent.translatesAutoresizingMaskIntoConstraints = false

        let chip = UIView()
        chip.backgroundColor = inStock
            ? UIColor(red: 1.0, green: 0.90, blue: 0.90, alpha: 1)
            : UIColor(white: 0.93, alpha: 1)
        chip.layer.cornerRadius = 12
        chip.layer.masksToBounds = true
        chip.addSubview(chipContent)
        NSLayoutConstraint.activate([
            chipContent.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 10),
            chipContent.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -10),
            chipContent.topAnchor.constraint(equalTo: chip.topAnchor, constant: 4),
            chipContent.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -4)
        ])

        let chipRow = UIStackView(arrangedSubviews: [chip, UIView()])
        chipRow.axis = .horizontal

        let stack = UIStackView(arrangedSubviews: [
            imageContainer,
            spacer(height: 8),
            nameLabel,
            spacer(height: 8),
            chipRow
        ])
        stack.axis = .vertical
        stack.alignment = .fill
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
