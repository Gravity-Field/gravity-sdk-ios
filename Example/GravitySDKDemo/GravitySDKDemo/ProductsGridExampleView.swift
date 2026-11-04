import GravitySDK
import SwiftUI

// Configure this selector with a productsContainer whose productContainerType is grid.
struct ProductsGridExampleView: View {
    var selector = "grid"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Products grid")
                    .font(.title2)
                GravityInlineSwiftUIView(
                    selector: selector,
                    pageContext: PageContext(type: .other, data: [], location: "products_grid_example")
                ) {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                Text("More content below the grid")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("Products grid")
    }
}
