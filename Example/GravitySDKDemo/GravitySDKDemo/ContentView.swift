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

            }.frame(maxHeight: .infinity, alignment: .top)
                .padding()
        }
    }
}
