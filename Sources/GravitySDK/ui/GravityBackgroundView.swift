import SwiftUI

struct GravityBackgroundView: View {
    let backgroundColor: Color?
    let backgroundImage: String?
    let backgroundFit: GravityContentScale?

    var body: some View {
        if backgroundColor != nil || backgroundImage != nil {
            ZStack {
                backgroundColor
                if let backgroundImage, let url = URL(string: backgroundImage) {
                    AsyncUIImage(url: url) { uiImage in
                        if let uiImage {
                            GravityScaledImageView(
                                uiImage: uiImage,
                                fit: backgroundFit ?? .crop
                            )
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
