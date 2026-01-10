import StoreKit
import SwiftUI

@Observable
class StoreManager {
    var products: [Product] = []
    
    // Placeholder Product IDs based on user request.
    // The user needs to create these in App Store Connect.
    let productIDs = ["com.haesslon.coffee.2000", "com.haesslon.coffee.2020", "com.haesslon.coffee.2040"]
    
    init() {
        // Start listening for transactions
        Task {
            for await _ in Transaction.updates {
                // Handle future transactions if needed, but for consumables/donations 
                // we mainly just care that the purchase succeeded.
            }
        }
    }
    
    func loadProducts() async {
        do {
            self.products = try await Product.products(for: productIDs)
            self.products.sort { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                case .unverified:
                    break
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }
}
