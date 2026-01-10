import SwiftUI
import StoreKit

struct AboutView: View {
    @State private var storeManager = StoreManager()
    
    // Data definition for sources to keep the view body clean (DRY)
    private let sources: [SourceLink] = [
        .init(title: "Fat, Sugar, Salt & Protein: DGE", url: "https://www.dge.de"),
        .init(title: "PAL: Institute of Medicine", url: "https://www.ncbi.nlm.nih.gov/books/NBK221839/"),
        .init(title: "VO2Max: Garmin", url: "https://www.garmin.com/en-MY/blog/vo2-max-is-connected-to-health-performance-and-longevity/")
    ]
    
    var body: some View {
        Form {
            Section(header: Text("Philosophy")) {
                Text("Haesslon is built on the principles of The Hacker's Diet: treating weight management as a simple engineering problem of inputs and outputs, focusing on long-term trends rather than daily fluctuations.")
                
                Text("Advanced food tracking is omitted. Instead, simple 'helper' foods are provided to make hitting your caloric goals easier, minimizing the thinking required for your diet.")
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inspired by:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("The Hacker's Diet", destination: URL(string: "https://www.fourmilab.ch/hackdiet/")!)
                        .font(.footnote)
                }
                .padding(.top, 4)
            }
            
            Section(header: Text("Sources")) {
                ForEach(sources) { source in
                    Link(source.title, destination: source.url)
                }
            }
            
            Section(header: Text("Support Development")) {
                Text("Donations are completely optional. If you like the app, feel free to buy me a coffee!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if storeManager.products.isEmpty {
                    ContentUnavailableView("Loading Store...", systemImage: "cart")
                } else {
                    ForEach(storeManager.products) { product in
                        Button {
                            Task { await storeManager.purchase(product) }
                        } label: {
                            DonationRow(product: product)
                        }
                    }
                }
            }
        }
        .navigationTitle("About")
        .task {
            await storeManager.loadProducts()
        }
    }
}

// MARK: - Subviews & Helpers

struct SourceLink: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    
    init(title: String, url: String) {
        self.title = title
        self.url = URL(string: url)!
    }
}

struct DonationRow: View {
    let product: Product
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(coffeeTitle(for: product.id))
                    .foregroundStyle(.primary)
                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(product.displayPrice)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private func coffeeTitle(for id: String) -> String {
        // Safe fallbacks to avoid crashes or weird UI if IDs change
        if id.contains("2000") { return "Buy me a coffee in 2000" }
        if id.contains("2020") { return "Buy me a coffee in 2020" }
        if id.contains("2040") { return "Buy me a coffee in 2040" }
        return "Buy me a coffee"
    }
}
