import UIKit

// Dữ liệu săn sale: định dạng, mã giảm giá (model + đọc từ chữ + tính tổ hợp),
// lưu trữ sản phẩm và các lần quét.

enum TPIOSSaleFormat {

    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: value)) ?? "0") + "đ"
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "chưa có" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter.string(from: date)
    }

    static func delta(current: Double, previous: Double) -> (text: String, color: UIColor) {
        let diff = current - previous

        if abs(diff) < 1 {
            return ("= không đổi", UIColor.white.withAlphaComponent(0.6))
        }

        let percent = previous > 0 ? abs(diff) / previous * 100 : 0
        let percentText = String(format: "%.1f%%", percent)

        if diff < 0 {
            return (
                "▼ " + money(abs(diff)) + " (" + percentText + ")",
                UIColor(red: 0.35, green: 0.85, blue: 0.5, alpha: 1)
            )
        }

        return (
            "▲ " + money(diff) + " (" + percentText + ")",
            UIColor(red: 1.0, green: 0.45, blue: 0.4, alpha: 1)
        )
    }
}

enum TPIOSSaleKind {

    static let order = ["shop", "platform", "freeship"]

    static func name(_ kind: String) -> String {
        switch kind {
        case "platform": return "Sàn"
        case "freeship": return "Ship"
        default: return "Shop"
        }
    }

    static func color(_ kind: String) -> UIColor {
        switch kind {
        case "platform": return UIColor(red: 0.85, green: 0.30, blue: 0.20, alpha: 1)
        case "freeship": return UIColor(red: 0.10, green: 0.60, blue: 0.55, alpha: 1)
        default: return UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)
        }
    }

    static func next(_ kind: String) -> String {
        guard let index = order.firstIndex(of: kind) else { return order[0] }
        return order[(index + 1) % order.count]
    }
}

struct TPIOSSaleVoucher: Codable {
    let id: String
    var title: String
    var kind: String
    var isPercent: Bool
    var value: Double
    var minSpend: Double
    var maxDiscount: Double?
    var expiryText: String?
}

struct TPIOSSalePick {
    let voucher: TPIOSSaleVoucher
    let amount: Double
}

struct TPIOSSaleVoucherResult {
    let picks: [TPIOSSalePick]
    let totalOnPrice: Double
    let freeshipAmount: Double
    let finalPrice: Double
    let ineligibleCount: Int
}

// Quy tắc đơn giản hoá: mỗi loại (Shop / Sàn / Freeship) chỉ áp tối đa 1
// mã, chọn mã giảm nhiều nhất cho giá hiện tại. Mã Shop và mã Sàn cộng dồn
// vào giá sản phẩm, mã Freeship tính riêng (giảm phí ship). Mọi mức giảm
// tính trên giá gốc của 1 sản phẩm, không xét số lượng hay thứ tự áp mã nên
// chỉ là ước tính.
enum TPIOSSaleVoucherMath {

    static func discount(_ voucher: TPIOSSaleVoucher, price: Double) -> Double? {
        guard price >= voucher.minSpend else { return nil }

        var amount = voucher.isPercent ? price * voucher.value / 100 : voucher.value

        if let cap = voucher.maxDiscount, cap > 0 {
            amount = min(amount, cap)
        }

        return max(0, amount)
    }

    static func best(vouchers: [TPIOSSaleVoucher], price: Double) -> TPIOSSaleVoucherResult {
        var picks: [TPIOSSalePick] = []
        var ineligible = 0

        for kind in TPIOSSaleKind.order {
            var bestPick: TPIOSSalePick?

            for voucher in vouchers where voucher.kind == kind {
                guard let amount = discount(voucher, price: price) else {
                    ineligible += 1
                    continue
                }

                if amount > (bestPick?.amount ?? 0) {
                    bestPick = TPIOSSalePick(voucher: voucher, amount: amount)
                }
            }

            if let bestPick {
                picks.append(bestPick)
            }
        }

        let onPrice = picks
            .filter { $0.voucher.kind != "freeship" }
            .reduce(0) { $0 + $1.amount }

        let freeship = picks
            .filter { $0.voucher.kind == "freeship" }
            .reduce(0) { $0 + $1.amount }

        let cappedOnPrice = min(onPrice, price)

        return TPIOSSaleVoucherResult(
            picks: picks,
            totalOnPrice: cappedOnPrice,
            freeshipAmount: freeship,
            finalPrice: price - cappedOnPrice,
            ineligibleCount: ineligible
        )
    }
}

struct TPIOSSaleParsedVoucher {
    var title: String
    var kind: String
    var isPercent: Bool
    var value: Double
    var minSpend: Double
    var maxDiscount: Double?
    var expiryText: String?
}

enum TPIOSSaleVoucherParser {

    static func parse(lines: [String]) -> TPIOSSaleParsedVoucher? {
        guard lines.isEmpty == false else { return nil }

        var text = lines.joined(separator: " | ")
            .replacingOccurrences(of: "₫", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        // "50.000đ" → "50.000" (chỉ bỏ chữ đ ngay sau chữ số, giữ nguyên
        // các từ như "đơn", "tối đa").
        text = text.replacingOccurrences(
            of: "(?<=\\d)[đĐ]",
            with: "",
            options: .regularExpression
        )

        let lower = text.lowercased()

        let isFreeship =
            lower.contains("miễn phí vận chuyển") ||
            lower.contains("freeship") ||
            lower.contains("free ship") ||
            lower.range(of: "giảm[^|]{0,14}phí (vận chuyển|ship)", options: .regularExpression) != nil

        var isPercent = false
        var value: Double?

        if let groups = capture(#"giảm(?:\s+giá)?\s+(\d[\d.,]*)\s*(%|k\b|tr\b|nghìn|triệu)?"#, in: lower),
           let parsed = number(groups[0], suffix: groups[1]),
           parsed.value > 0 {
            isPercent = parsed.isPercent
            value = parsed.value
        }

        if isPercent, let current = value, current > 100 {
            value = nil
        }

        if value == nil && isFreeship == false {
            return nil
        }

        var maxDiscount: Double?
        if let groups = capture(#"tối\s*đa\s*(\d[\d.,]*)\s*(k\b|tr\b|nghìn|triệu)?"#, in: lower),
           let parsed = number(groups[0], suffix: groups[1]),
           parsed.hasUnit || parsed.value >= 1000 {
            maxDiscount = parsed.value
        }

        var minSpend = 0.0
        if let groups = capture(
            #"(?:đơn\s*tối\s*thiểu|tối\s*thiểu|đơn(?:\s*hàng)?\s*từ|chi\s*tiêu\s*tối\s*thiểu)\s*(\d[\d.,]*)\s*(k\b|tr\b|nghìn|triệu)?"#,
            in: lower
        ),
           let parsed = number(groups[0], suffix: groups[1]),
           parsed.hasUnit || parsed.value >= 1000 {
            minSpend = parsed.value
        }

        var expiry: String?
        if let groups = capture(#"((?:hsd|hết hạn|hạn dùng)[^|]{0,28})"#, in: text) {
            expiry = groups[0].trimmingCharacters(in: .whitespaces)
        }

        let kind: String
        if isFreeship {
            kind = "freeship"
        } else if lower.contains("shopee voucher") ||
                    lower.contains("voucher shopee") ||
                    lower.contains("mã shopee") ||
                    lower.contains("toàn sàn") {
            kind = "platform"
        } else {
            kind = "shop"
        }

        let amountValue = value ?? 0

        var title: String
        if isPercent {
            title = "Giảm " + trimmed(amountValue) + "%"
        } else if amountValue > 0 {
            title = "Giảm " + TPIOSSaleFormat.money(amountValue)
        } else {
            title = "Miễn phí vận chuyển"
        }

        if let maxDiscount {
            title += " tối đa " + TPIOSSaleFormat.money(maxDiscount)
        }

        if minSpend > 0 {
            title += " · đơn từ " + TPIOSSaleFormat.money(minSpend)
        }

        return TPIOSSaleParsedVoucher(
            title: title,
            kind: kind,
            isPercent: isPercent,
            value: amountValue,
            minSpend: minSpend,
            maxDiscount: maxDiscount,
            expiryText: expiry
        )
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func capture(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)

        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        var groups: [String] = []

        for index in 1..<match.numberOfRanges {
            if let groupRange = Range(match.range(at: index), in: text) {
                groups.append(String(text[groupRange]))
            } else {
                groups.append("")
            }
        }

        return groups
    }

    private static func number(
        _ token: String,
        suffix: String
    ) -> (value: Double, isPercent: Bool, hasUnit: Bool)? {

        let unit = suffix.lowercased()

        if unit == "%" {
            guard let value = Double(token.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return (value, true, true)
        }

        if unit == "k" || unit == "nghìn" {
            guard let value = Double(token.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return (value * 1_000, false, true)
        }

        if unit == "tr" || unit == "triệu" {
            guard let value = Double(token.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return (value * 1_000_000, false, true)
        }

        let digits = token
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")

        guard let value = Double(digits) else { return nil }
        return (value, false, false)
    }
}

extension TPIOSSaleVoucher {
    func sameAs(_ other: TPIOSSaleVoucher) -> Bool {
        kind == other.kind &&
        isPercent == other.isPercent &&
        value == other.value &&
        minSpend == other.minSpend &&
        maxDiscount == other.maxDiscount
    }
}


// MARK: - Lưu trữ

// 1 lần quét. Dữ liệu đã lưu từ các bản trước vẫn đọc được (khóa thừa bị bỏ
// qua, khóa mới là optional).
struct TPIOSSaleSnapshot: Codable {
    let timestamp: Date
    let price: Double?
    var finalPrice: Double?
    var vouchers: [TPIOSSaleVoucher]?

    // Giá dùng để so sánh các lần: giá sau mã nếu có, không thì giá niêm yết.
    var effectivePrice: Double? { finalPrice ?? price }
    var voucherList: [TPIOSSaleVoucher] { vouchers ?? [] }
}

struct TPIOSWatchedSale: Codable {
    let id: UUID
    var title: String
    var createdAt: Date
    var lastCheckedAt: Date?
    var snapshots: [TPIOSSaleSnapshot]
    // Mã định danh của Shopee (itemid, modelid, shopid). Có sau khi lưu bằng
    // chế độ đọc giỏ; các mục cũ không có thì để nil và khớp theo tên.
    var itemID: Int64? = nil
    var modelID: Int64? = nil
    var shopID: Int64? = nil
}

enum TPIOSSaleMatcher {

    static func normalize(_ text: String) -> String {
        var value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        while value.hasSuffix("…") || value.hasSuffix(".") {
            value.removeLast()
        }

        return value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // Cùng sản phẩm nếu tên trùng, hoặc 1 tên là phần đầu của tên kia (tên bị
    // cắt "…" ở giỏ hàng nhưng đầy đủ ở trang sản phẩm).
    static func same(_ a: String, _ b: String) -> Bool {
        let na = normalize(a)
        let nb = normalize(b)

        guard na.isEmpty == false, nb.isEmpty == false else { return false }

        let shorter = na.count <= nb.count ? na : nb
        let longer = na.count <= nb.count ? nb : na

        return na == nb || (shorter.count >= 12 && longer.hasPrefix(shorter))
    }
}

final class TPIOSSaleStore {

    static let shared = TPIOSSaleStore()

    private let key = "TPIOS.Sale.WatchedProducts.v1"

    private init() {}

    func load() -> [TPIOSWatchedSale] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return (try? decoder.decode([TPIOSWatchedSale].self, from: data)) ?? []
    }

    private func save(_ products: [TPIOSWatchedSale]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(products) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // Thêm 1 lần quét: cùng tên thì vào lịch sử sản phẩm đó, khác tên thì tạo
    // sản phẩm mới. previous = giá so sánh của lần quét trước (nếu có).
    func record(
        name: String,
        price: Double,
        finalPrice: Double,
        vouchers: [TPIOSSaleVoucher],
        itemID: Int64? = nil,
        modelID: Int64? = nil,
        shopID: Int64? = nil
    ) -> (product: TPIOSWatchedSale, previous: Double?) {

        var products = load()
        let snapshot = TPIOSSaleSnapshot(timestamp: Date(), price: price, finalPrice: finalPrice, vouchers: vouchers)

        // Ưu tiên khớp theo định danh; mục cũ chưa có định danh thì khớp theo tên
        // rồi gán định danh cho mục đó.
        var index: Int?
        if let itemID, let modelID {
            index = products.firstIndex { $0.itemID == itemID && $0.modelID == modelID }
            if index == nil {
                index = products.firstIndex { $0.itemID == nil && TPIOSSaleMatcher.same($0.title, name) }
            }
        } else {
            index = products.firstIndex { TPIOSSaleMatcher.same($0.title, name) }
        }

        if let index {
            let previous = products[index].snapshots.compactMap { $0.effectivePrice }.last

            products[index].snapshots.append(snapshot)
            products[index].lastCheckedAt = snapshot.timestamp

            if name.count > products[index].title.count {
                products[index].title = name
            }
            if products[index].itemID == nil {
                products[index].itemID = itemID
                products[index].modelID = modelID
                products[index].shopID = shopID
            }

            save(products)
            return (products[index], previous)
        }

        var product = TPIOSWatchedSale(
            id: UUID(),
            title: name,
            createdAt: snapshot.timestamp,
            lastCheckedAt: snapshot.timestamp,
            snapshots: [snapshot]
        )
        product.itemID = itemID
        product.modelID = modelID
        product.shopID = shopID

        products.insert(product, at: 0)
        save(products)
        return (product, nil)
    }

    func deleteProduct(_ id: UUID) {
        var products = load()
        products.removeAll { $0.id == id }
        save(products)
    }

    func deleteSnapshot(productID: UUID, index: Int) {
        var products = load()

        guard let productIndex = products.firstIndex(where: { $0.id == productID }),
              index >= 0,
              index < products[productIndex].snapshots.count else {
            return
        }

        products[productIndex].snapshots.remove(at: index)
        products[productIndex].lastCheckedAt = products[productIndex].snapshots.last?.timestamp
        save(products)
    }
}
