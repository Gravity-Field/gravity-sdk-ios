import SwiftUI

public struct AsyncImage<Content: View>: View {
    private let url: URL
    private let content: (Image?) -> Content
    @StateObject private var imageLoader = ImageLoader()

    public init(
        url: URL,
        @ViewBuilder content: @escaping (Image?) -> Content
    ) {
        self.url = url
        self.content = content
    }

    public var body: some View {
        content(imageLoader.image)
            .onAppear {
                imageLoader.load(url: url)
            }
            .onChange(of: url) { url in
                imageLoader.load(url: url)
            }
    }
}

private final class ImageLoader: ObservableObject {
    @Published var image: Image?

    func load(url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async { [weak self] in
                if let data = data, let uiImage = UIImage(data: data) {
                    self?.image = Image.init(uiImage: uiImage)
                }
            }
        }
        .resume()
    }
}
