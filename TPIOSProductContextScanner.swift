import UIKit
import WebKit

struct TPIOSProductContextScanResult {
    let url: String?
    let title: String?
    let productName: String?
    let productID: String?
    let shopID: String?
    let price: Double?
    let shopName: String?
    let visibleMatches: [String]

    func displayText() -> String {
        var lines = ["PRODUCT CONTEXT", ""]

        lines.append("URL: \(url ?? "—")")
        lines.append("Tên: \(productName ?? title ?? "—")")
        lines.append("Giá: \(price.map { TPIOSProductContextScanner.formatMoney($0) } ?? "—")")
        lines.append("Product ID: \(productID ?? "—")")
        lines.append("Shop ID: \(shopID ?? "—")")
        lines.append("Shop: \(shopName ?? "—")")

        if !visibleMatches.isEmpty {
            lines.append("")
            lines.append("DỮ LIỆU LIÊN QUAN:")
            lines.append(contentsOf: visibleMatches.prefix(20).map { "• \($0)" })
        }

        return lines.joined(separator: "\n")
    }
}

enum TPIOSProductContextScanner {

    static func scanCurrentApp(
        completion: @escaping (TPIOSProductContextScanResult) -> Void
    ) {
        let windows = visibleAppWindows()
        let webViews = uniqueWebViews(from: windows)

        guard !webViews.isEmpty else {
            let native = collectNativeText(from: windows)
            completion(
                TPIOSProductContextScanResult(
                    url: nil,
                    title: nil,
                    productName: nil,
                    productID: nil,
                    shopID: nil,
                    price: firstPrice(in: native),
                    shopName: nil,
                    visibleMatches: native
                )
            )
            return
        }

        let group = DispatchGroup()
        var results: [[String: Any]] = []
        let lock = NSLock()

        for webView in webViews {
            group.enter()

            let script = webScript()

            webView.evaluateJavaScript(script) { value, error in
                defer { group.leave() }

                if let error {
                    TPIOSLog.shared.log(
                        "SaleProduct: JS error \(error.localizedDescription)"
                    )
                    return
                }

                guard let json = value as? String,
                      let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let dictionary = object as? [String: Any] else {
                    return
                }

                lock.lock()
                results.append(dictionary)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let result = mergeResults(results)
            completion(result)

            TPIOSLog.shared.log(
                "SaleProduct: \(result.displayText().replacingOccurrences(of: "\n", with: " | "))"
            )
        }
    }

    private static func visibleAppWindows() -> [UIWindow] {
        let scenes = UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }

        var windows: [UIWindow] = []

        for scene in scenes where scene.activationState != .unattached {
            for window in scene.windows {
                guard !window.isHidden,
                      window.alpha > 0.01,
                      window.bounds.width > 0,
                      window.bounds.height > 0 else {
                    continue
                }

                let className = NSStringFromClass(type(of: window))
                if className.contains("TPIOS") {
                    continue
                }

                windows.append(window)
            }
        }

        return windows
    }

    private static func uniqueWebViews(from windows: [UIWindow]) -> [WKWebView] {
        var result: [WKWebView] = []
        var identifiers = Set<ObjectIdentifier>()

        for window in windows {
            collectWebViews(
                from: window,
                result: &result,
                identifiers: &identifiers
            )
        }

        return result
    }

    private static func collectWebViews(
        from view: UIView,
        result: inout [WKWebView],
        identifiers: inout Set<ObjectIdentifier>
    ) {
        if let webView = view as? WKWebView {
            let identifier = ObjectIdentifier(webView)
            if identifiers.insert(identifier).inserted {
                result.append(webView)
            }
        }

        for child in view.subviews {
            collectWebViews(
                from: child,
                result: &result,
                identifiers: &identifiers
            )
        }
    }

    private static func collectNativeText(from windows: [UIWindow]) -> [String] {
        var values: [String] = []

        for window in windows {
            collectNativeText(from: window, into: &values)
        }

        return filtered(values)
    }

    private static func collectNativeText(
        from view: UIView,
        into values: inout [String]
    ) {
        if let label = view as? UILabel, let text = label.text {
            values.append(text)
        } else if let field = view as? UITextField, let text = field.text {
            values.append(text)
        } else if let textView = view as? UITextView, let text = textView.text {
            values.append(text)
        } else if let button = view as? UIButton, let text = button.title(for: .normal) {
            values.append(text)
        }

        for child in view.subviews {
            collectNativeText(from: child, into: &values)
        }
    }

    private static func filtered(_ values: [String]) -> [String] {
        var output: [String] = []
        var seen = Set<String>()

        let keywords = [
            "₫", "đ", "voucher", "freeship", "giảm", "sale",
            "shop", "mua", "sản phẩm", "product", "price"
        ]

        for raw in values {
            let text = raw
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty, text.count <= 220 else {
                continue
            }

            let lower = text.lowercased()
            guard keywords.contains(where: { lower.contains($0) }) else {
                continue
            }

            if seen.insert(text).inserted {
                output.append(text)
            }

            if output.count >= 30 {
                break
            }
        }

        return output
    }

    private static func webScript() -> String {
        return """
        (function() {
            function clean(value) {
                return String(value || "")
                    .replace(/\\s+/g, " ")
                    .trim()
                    .slice(0, 500);
            }

            function first(values) {
                for (const value of values) {
                    const cleaned = clean(value);
                    if (cleaned) return cleaned;
                }
                return "";
            }

            function numberValue(value) {
                if (value === null || value === undefined) return null;
                const raw = String(value).replace(/[^0-9.,-]/g, "");
                if (!raw) return null;

                let normalized = raw;
                if (raw.includes(".") && raw.includes(",")) {
                    normalized = raw.replace(/\\./g, "").replace(",", ".");
                } else if (raw.includes(",")) {
                    normalized = raw.replace(/,/g, "");
                } else if ((raw.match(/\\./g) || []).length > 1) {
                    normalized = raw.replace(/\\./g, "");
                }

                const number = Number(normalized);
                return Number.isFinite(number) ? number : null;
            }

            function meta(name) {
                const node = document.querySelector(
                    'meta[property="' + name + '"], meta[name="' + name + '"]'
                );
                return node ? clean(node.content) : "";
            }

            const href = location.href || "";
            const title = clean(document.title);
            const body = document.body ? document.body.innerText : "";

            let productName = first([
                meta("og:title"),
                meta("twitter:title")
            ]);

            let price = numberValue(
                first([
                    meta("product:price:amount"),
                    meta("og:price:amount")
                ])
            );

            let productID = first([
                meta("product:retailer_item_id"),
                meta("product:item_group_id")
            ]);

            let shopID = first([
                meta("product:brand")
            ]);

            let shopName = "";

            const jsonLD = Array.from(
                document.querySelectorAll('script[type="application/ld+json"]')
            );

            for (const node of jsonLD) {
                try {
                    const data = JSON.parse(node.textContent || "");
                    const items = Array.isArray(data) ? data : [data];

                    for (const item of items) {
                        const products = item && item["@type"] === "Product"
                            ? [item]
                            : [];

                        for (const product of products) {
                            if (!productName) {
                                productName = clean(product.name);
                            }

                            if (price === null && product.offers) {
                                const offers = Array.isArray(product.offers)
                                    ? product.offers
                                    : [product.offers];

                                for (const offer of offers) {
                                    const candidate = numberValue(offer && offer.price);
                                    if (candidate !== null) {
                                        price = candidate;
                                        break;
                                    }
                                }
                            }

                            if (!shopName && product.brand) {
                                shopName = clean(
                                    typeof product.brand === "string"
                                        ? product.brand
                                        : product.brand.name
                                );
                            }

                            if (!productID && product.sku) {
                                productID = clean(product.sku);
                            }
                        }
                    }
                } catch (_) {}
            }

            const idPatterns = [
                /[?&](?:itemId|item_id|productId|product_id)=(\\d+)/i,
                /(?:item|product)[/_-](\\d{5,})/i
            ];

            if (!productID) {
                for (const pattern of idPatterns) {
                    const match = href.match(pattern);
                    if (match) {
                        productID = match[1];
                        break;
                    }
                }
            }

            if (!shopID) {
                const match = href.match(/[?&](?:shopId|shop_id)=(\\d+)/i);
                if (match) {
                    shopID = match[1];
                }
            }

            const lines = body
                .split(/\\n+/)
                .map(clean)
                .filter(Boolean);

            const keywords = [
                "₫", "đ", "voucher", "freeship", "giảm",
                "sale", "shop", "sản phẩm", "product", "price"
            ];

            const matches = [];
            const seen = new Set();

            for (const line of lines) {
                const lower = line.toLowerCase();
                if (!keywords.some(keyword => lower.includes(keyword))) continue;
                if (line.length > 220) continue;
                if (seen.has(line)) continue;

                seen.add(line);
                matches.push(line);

                if (matches.length >= 30) break;
            }

            return JSON.stringify({
                url: href,
                title: title,
                productName: productName,
                productID: productID,
                shopID: shopID,
                shopName: shopName,
                price: price,
                matches: matches
            });
        })();
        """
    }

    private static func mergeResults(
        _ results: [[String: Any]]
    ) -> TPIOSProductContextScanResult {
        var best: [String: Any] = [:]
        var matches: [String] = []
        var seen = Set<String>()

        for result in results {
            let keys = [
                "url", "title", "productName", "productID",
                "shopID", "shopName", "price"
            ]

            for key in keys {
                if best[key] == nil,
                   let value = result[key],
                   !(value is NSNull) {
                    best[key] = value
                }
            }

            if let values = result["matches"] as? [String] {
                for value in values where seen.insert(value).inserted {
                    matches.append(value)
                }
            }
        }

        return TPIOSProductContextScanResult(
            url: best["url"] as? String,
            title: best["title"] as? String,
            productName: best["productName"] as? String,
            productID: best["productID"] as? String,
            shopID: best["shopID"] as? String,
            price: best["price"] as? Double ?? (best["price"] as? NSNumber)?.doubleValue,
            shopName: best["shopName"] as? String,
            visibleMatches: Array(matches.prefix(30))
        )
    }

    private static func firstPrice(in values: [String]) -> Double? {
        let pattern = #"(?<![0-9])([0-9]{2,3}(?:[.,][0-9]{3})+)(?:\\s*)?(?:₫|đ)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        for value in values {
            let range = NSRange(value.startIndex..., in: value)
            guard let match = regex.firstMatch(in: value, range: range),
                  let numberRange = Range(match.range(at: 1), in: value) else {
                continue
            }

            let raw = String(value[numberRange])
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "")

            if let number = Double(raw) {
                return number
            }
        }

        return nil
    }

    static func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: value)) ?? "0")đ"
    }
}
