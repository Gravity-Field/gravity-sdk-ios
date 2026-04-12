import GravitySDK
import SwiftUI

struct ContentView: View {

    var body: some View {
        ZStack {
            VStack(spacing: 20) {

                Button("Track view") {
                    GravitySDK.instance.trackView(
                        pageContext: PageContext(
                            type: .homepage,
                            data: [],
                            location: "homepage",
                        )
                    )
                }

                Button("Trigger event") {
                    GravitySDK.instance.triggerEvent(
                        events: [
                            CustomEvent(
                                type: "tapbar_clicked",
                                name: "tapbar_clicked",
                            )

                        ],
                        pageContext: PageContext(
                            type: .homepage,
                            data: [],
                            location: "homepage",
                        )
                    )
                }

                Button("Get content by selector") {
                    Task {
                        let response = await GravitySDK.instance
                            .getContentBySelector(
                                selector: "sdk_cart_reco",
                                pageContext: PageContext(
                                    type: .cart,
                                    data: [],
                                    location: "homepage",
                                )
                            )
                        print("response: \(String(describing: response))")
                    }
                }

                GravityInlineSwiftUIView(
                    selector: "homepage_inline_banner",
                    pageContext: PageContext(
                        type: .homepage,
                        data: [],
                        location: "homepage",
                    )
                )

            }.frame(maxHeight: .infinity, alignment: .top)
                .padding()
        }
    }
}
