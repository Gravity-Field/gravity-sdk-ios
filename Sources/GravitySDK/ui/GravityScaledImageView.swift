import SwiftUI

extension GravityContentScale {
    struct ScaledLayout {
        let width: CGFloat
        let height: CGFloat
        let resizable: Bool
    }

    func scaledLayout(imageSize: CGSize, containerSize: CGSize) -> ScaledLayout {
        guard imageSize.width > 0, imageSize.height > 0,
            containerSize.width > 0, containerSize.height > 0
        else {
            return ScaledLayout(
                width: containerSize.width,
                height: containerSize.height,
                resizable: true
            )
        }

        switch self {
        case .crop:
            let scale = max(
                containerSize.width / imageSize.width,
                containerSize.height / imageSize.height
            )
            return ScaledLayout(
                width: imageSize.width * scale,
                height: imageSize.height * scale,
                resizable: true
            )
        case .fit:
            let scale = min(
                containerSize.width / imageSize.width,
                containerSize.height / imageSize.height
            )
            return ScaledLayout(
                width: imageSize.width * scale,
                height: imageSize.height * scale,
                resizable: true
            )
        case .inside:
            let scale = min(
                containerSize.width / imageSize.width,
                containerSize.height / imageSize.height,
                1
            )
            return ScaledLayout(
                width: imageSize.width * scale,
                height: imageSize.height * scale,
                resizable: true
            )
        case .fillWidth:
            let scale = containerSize.width / imageSize.width
            return ScaledLayout(
                width: imageSize.width * scale,
                height: imageSize.height * scale,
                resizable: true
            )
        case .fillHeight:
            let scale = containerSize.height / imageSize.height
            return ScaledLayout(
                width: imageSize.width * scale,
                height: imageSize.height * scale,
                resizable: true
            )
        case .fillBounds:
            return ScaledLayout(
                width: containerSize.width,
                height: containerSize.height,
                resizable: true
            )
        case .none:
            return ScaledLayout(
                width: imageSize.width,
                height: imageSize.height,
                resizable: false
            )
        }
    }
}

struct GravityScaledImageView: View {
    let uiImage: UIImage
    let fit: GravityContentScale

    var body: some View {
        GeometryReader { geometry in
            let layout = fit.scaledLayout(
                imageSize: uiImage.size,
                containerSize: geometry.size
            )

            ZStack {
                if layout.resizable {
                    Image(uiImage: uiImage)
                        .resizable()
                        .frame(width: layout.width, height: layout.height)
                } else {
                    Image(uiImage: uiImage)
                        .frame(width: layout.width, height: layout.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

struct AsyncUIImage<Content: View>: View {
    private let url: URL
    private let content: (UIImage?) -> Content
    @StateObject private var imageLoader = UIImageLoader()

    init(
        url: URL,
        @ViewBuilder content: @escaping (UIImage?) -> Content
    ) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(imageLoader.uiImage)
            .onAppear {
                imageLoader.load(url: url)
            }
            .onChange(of: url) { url in
                imageLoader.load(url: url)
            }
    }
}

final class UIImageLoader: ObservableObject {
    @Published var uiImage: UIImage?

    private static let cache = NSCache<NSURL, UIImage>()

    func load(url: URL) {
        if let cached = Self.cache.object(forKey: url as NSURL) {
            uiImage = cached
            return
        }

        if url.isFileURL {
            if let image =
                UIImage(contentsOfFile: url.path)
                ?? (try? Data(contentsOf: url)).flatMap({ UIImage(data: $0) })
            {
                Self.cache.setObject(image, forKey: url as NSURL)
                uiImage = image
            }
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            Self.cache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async { [weak self] in
                self?.uiImage = image
            }
        }
        .resume()
    }
}
