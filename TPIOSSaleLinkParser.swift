import Foundation

struct TPIOSSaleLinkInfo {
    let url: String
    let itemID: String?
    let shopID: String?
}

enum TPIOSSaleLinkParser {

    static func parse(_ rawURL: String) -> TPIOSSaleLinkInfo? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let value = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"

        guard
            let url = URL(string: value),
            let host = url.host?.lowercased(),
            host.contains("shopee")
        else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        var itemID: String?
        var shopID: String?

        if let productsIndex = components.firstIndex(where: {
            $0.lowercased() == "product"
        }), productsIndex + 2 < components.count {
            shopID = components[productsIndex + 1]
            itemID = components[productsIndex + 2]
        }

        if itemID == nil {
            let queryItems = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )?.queryItems ?? []

            itemID = queryItems.first(where: {
                ["itemid", "item_id", "item"].contains($0.name.lowercased())
            })?.value

            shopID = queryItems.first(where: {
                ["shopid", "shop_id", "shop"].contains($0.name.lowercased())
            })?.value
        }

        return TPIOSSaleLinkInfo(
            url: url.absoluteString,
            itemID: itemID,
            shopID: shopID
        )
    }
}
