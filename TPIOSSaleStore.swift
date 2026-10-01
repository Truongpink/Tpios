import Foundation

struct TPIOSSaleSnapshot: Codable {
    let timestamp: Date
    let productName: String?
    let itemID: String?
    let shopID: String?
    let price: Double?
    let finalPrice: Double?
    let analysisNote: String
    let requestEvidence: [String]
}

struct TPIOSWatchedSale: Codable {
    let id: UUID
    var url: String
    var title: String
    var itemID: String?
    var shopID: String?
    var createdAt: Date
    var lastCheckedAt: Date?
    var bestFinalPrice: Double?
    var snapshots: [TPIOSSaleSnapshot]
}

final class TPIOSSaleStore {

    static let shared = TPIOSSaleStore()

    private let key = "TPIOS.Sale.WatchedProducts.v1"
    private let defaults = UserDefaults.standard

    private init() {}

    func load() -> [TPIOSWatchedSale] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        return (try? JSONDecoder().withDateDecodingStrategy.decode(
            [TPIOSWatchedSale].self,
            from: data
        )) ?? []
    }

    func save(_ products: [TPIOSWatchedSale]) {
        guard let data = try? JSONEncoder().withDateEncodingStrategy.encode(products) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    @discardableResult
    func add(url: String, title: String, itemID: String?, shopID: String?) -> TPIOSWatchedSale {
        var products = load()

        if let existingIndex = products.firstIndex(where: {
            normalizedURL($0.url) == normalizedURL(url)
        }) {
            return products[existingIndex]
        }

        let product = TPIOSWatchedSale(
            id: UUID(),
            url: url,
            title: title,
            itemID: itemID,
            shopID: shopID,
            createdAt: Date(),
            lastCheckedAt: nil,
            bestFinalPrice: nil,
            snapshots: []
        )

        products.insert(product, at: 0)
        save(products)
        return product
    }

    func analyze(
        productID: UUID,
        snapshot: TPIOSSaleSnapshot
    ) {
        var products = load()

        guard let index = products.firstIndex(where: { $0.id == productID }) else {
            return
        }

        products[index].lastCheckedAt = snapshot.timestamp
        products[index].snapshots.append(snapshot)

        if let finalPrice = snapshot.finalPrice {
            if let best = products[index].bestFinalPrice {
                products[index].bestFinalPrice = min(best, finalPrice)
            } else {
                products[index].bestFinalPrice = finalPrice
            }
        }

        save(products)
    }

    func remove(productID: UUID) {
        var products = load()
        products.removeAll { $0.id == productID }
        save(products)
    }

    private func normalizedURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension JSONEncoder {
    var withDateEncodingStrategy: JSONEncoder {
        dateEncodingStrategy = .iso8601
        return self
    }
}

private extension JSONDecoder {
    var withDateDecodingStrategy: JSONDecoder {
        dateDecodingStrategy = .iso8601
        return self
    }
}
