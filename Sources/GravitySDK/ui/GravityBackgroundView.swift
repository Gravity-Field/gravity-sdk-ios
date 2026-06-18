import SwiftUI

struct GravityBackgroundView: View {
    let backgroundColor: Color?
    let backgroundImage: String?
    let backgroundFit: GravityContentScale?

    var body: some View {
        if backgroundColor != nil || backgroundImage != nil {
            ZStack {
                backgroundColor
                if let backgroundImage {
                    GravityBackgroundImage(
                        src: backgroundImage,
                        fit: backgroundFit ?? .crop
                    )
                }
            }
        }
    }
}

private struct GravityBackgroundImage: View {
    let src: String
    let fit: GravityContentScale

    private var url: URL? {
        URL(string: src)
    }

    var body: some View {
        if let url = url {
            GeometryReader { geometry in
                AsyncImage(url: url) { image in
                    if let image = image {
                        styledImage(image, geometry.size)
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func styledImage(_ image: Image, _ size: CGSize) -> some View {
        switch fit {
        case .crop, .fillWidth, .fillHeight:
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        case .fit, .inside:
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)
        case .fillBounds:
            image
                .resizable()
                .frame(width: size.width, height: size.height)
        case .none:
            image
        }
    }
}
