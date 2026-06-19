import SwiftUI
import WebKit

struct GravityWebview: View {
    let element: Element

    private var style: Style {
        element.style
    }

    private var url: URL? {
        guard let src = element.src else { return nil }
        return URL(string: src)
    }

    var body: some View {
        WebView(url: url)
            .applyIf(style.size?.width != nil) {
                $0.frame(width: style.size!.width!)
            }
            .applyIf(style.size?.height != nil) {
                $0.frame(height: style.size!.height!)
            }
            .applyIf(style.layoutWidth == .matchParent) {
                $0.frame(maxWidth: .infinity)
            }
            .applyIf(style.cornerRadius != nil) {
                $0.clipShape(
                    RoundedRectangle(cornerRadius: style.cornerRadius!)
                )
            }
            .applyIf(style.margin != nil) {
                $0.padding(
                    .init(
                        top: style.margin!.top,
                        leading: style.margin!.left,
                        bottom: style.margin!.bottom,
                        trailing: style.margin!.right
                    )
                )
            }
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.backgroundColor = .clear
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = url, webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
