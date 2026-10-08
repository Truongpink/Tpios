import UIKit
import WebKit

// Đọc chữ đang hiển thị trên màn hình app: giá, tên sản phẩm, mã giảm giá,
// và dump nghiên cứu.

struct TPIOSSaleTextItem {
    let text: String
    let frame: CGRect
}

enum TPIOSSaleScanner {

    // Tìm root view của app phía sau overlay TPIOS — cùng cách
    // TPIOSAdBlock.overlayRootWindow() đã dùng, để nhất quán trong project.
    static func visibleAppRoot(excluding selfWindow: UIWindow?) -> UIView? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first(where: { $0 !== selfWindow })
            ?? UIApplication.shared.windows.first

        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }

        return controller?.view ?? window
    }

    // Đọc 1 lần toàn bộ chữ đang hiển thị (kèm khung hình trên màn hình),
    // bỏ phần nằm ngoài màn hình (ô cuộn chưa lộ ra) và trùng lặp.
    static func collectItems(in root: UIView) -> [TPIOSSaleTextItem] {
        var raw: [TPIOSSaleTextItem] = []
        collect(from: root, into: &raw)

        let screen = UIScreen.main.bounds
        var seen = Set<String>()
        var items: [TPIOSSaleTextItem] = []

        for item in raw {
            guard item.frame.intersects(screen) else { continue }

            let key = "\(item.text)|\(Int(item.frame.origin.x))|\(Int(item.frame.origin.y))"
            guard seen.insert(key).inserted else { continue }

            items.append(item)
        }

        return items
    }

    private static func collect(from view: UIView, into items: inout [TPIOSSaleTextItem]) {
        guard view.isHidden == false, view.alpha > 0.01 else { return }

        func add(_ text: String?) {
            guard let text else { return }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return }

            items.append(
                TPIOSSaleTextItem(text: trimmed, frame: view.convert(view.bounds, to: nil))
            )
        }

        if let label = view as? UILabel { add(label.text) }

        if let field = view as? UITextField {
            add(field.text)
            add(field.placeholder)
        }

        if let textView = view as? UITextView { add(textView.text) }

        if let button = view as? UIButton {
            add(button.currentTitle)
            add(button.accessibilityLabel)
        }

        add(view.accessibilityLabel)

        for child in view.subviews {
            collect(from: child, into: &items)
        }
    }

    // Tên sản phẩm = dòng chữ dài, nhiều chữ cái, không phải nút/nhãn giao
    // diện, gần điểm chạm nhất.
    static func nameCandidates(
        in items: [TPIOSSaleTextItem],
        near point: CGPoint?,
        radius: CGFloat
    ) -> [String] {

        var scored: [(text: String, dist: CGFloat)] = []

        for item in items {
            guard isLikelyName(item.text) else { continue }

            var dist: CGFloat = 0

            if let point {
                dist = distance(from: point, to: item.frame)
                if dist > radius { continue }
            }

            scored.append((item.text, dist))
        }

        scored.sort {
            $0.dist != $1.dist ? $0.dist < $1.dist : $0.text.count > $1.text.count
        }

        var result: [String] = []
        var seen = Set<String>()

        for entry in scored {
            if seen.insert(entry.text.lowercased()).inserted {
                result.append(entry.text)
            }

            if result.count == 4 { break }
        }

        return result
    }

    private static func isLikelyName(_ text: String) -> Bool {
        let count = text.count
        guard count >= 10, count <= 160 else { return false }

        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 8 else { return false }

        let lower = text.lowercased()

        let strongNoise = [
            "thêm vào giỏ", "mua ngay", "đã bán", "phân loại", "xem thêm",
            "đánh giá", "thanh toán", "đặt hàng", "voucher", "freeship",
            "miễn phí vận chuyển", "lượt thích", "chat ngay", "shopee mall",
            "hoàn tiền", "tổng cộng", "đơn tối thiểu", "hsd", "hết hạn"
        ]

        if strongNoise.contains(where: { lower.contains($0) }) {
            return false
        }

        if count < 40 {
            let weakNoise = [
                "giảm ", "giao ", "xóa", "xoá", "sửa", "chọn", "tất cả",
                "quay lại", "kho", "ship", "ưu đãi", "gợi ý", "tìm kiếm",
                "giỏ hàng", "sản phẩm"
            ]

            if weakNoise.contains(where: { lower.contains($0) }) {
                return false
            }
        }

        if extractAmounts(from: text).isEmpty == false && letters < 14 {
            return false
        }

        return true
    }

    // Dump nghiên cứu: mỗi dòng = vị trí, kích thước, loại view, nguồn chữ,
    // nội dung. Xếp từ trên xuống dưới. Có thêm dòng cho WKWebView (nếu màn
    // render bằng web thì chữ không nằm trong view native).
    static func dumpLines(in root: UIView) -> [String] {
        var rows: [(minY: CGFloat, minX: CGFloat, line: String)] = []
        var seen = Set<String>()
        let screen = UIScreen.main.bounds

        func visit(_ view: UIView) {
            guard view.isHidden == false, view.alpha > 0.01 else { return }

            let frame = view.convert(view.bounds, to: nil)
            let className = NSStringFromClass(type(of: view))

            func add(_ text: String?, _ source: String) {
                guard let text else { return }

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false,
                      trimmed.count <= 160,
                      frame.intersects(screen) else {
                    return
                }

                let key = "\(trimmed)|\(Int(frame.minX))|\(Int(frame.minY))"
                guard seen.insert(key).inserted else { return }

                let position = "y=\(Int(frame.minY)) x=\(Int(frame.minX)) \(Int(frame.width))x\(Int(frame.height))"
                rows.append((frame.minY, frame.minX, position + " [" + className + "/" + source + "] " + trimmed))
            }

            if let web = view as? WKWebView, frame.intersects(screen) {
                let position = "y=\(Int(frame.minY)) x=\(Int(frame.minX)) \(Int(frame.width))x\(Int(frame.height))"
                rows.append((frame.minY, frame.minX, position + " [WKWebView] url=" + (web.url?.absoluteString ?? "-")))
            }

            if let label = view as? UILabel { add(label.text, "text") }

            if let field = view as? UITextField {
                add(field.text, "field")
                add(field.placeholder, "placeholder")
            }

            if let textView = view as? UITextView { add(textView.text, "textview") }
            if let button = view as? UIButton { add(button.currentTitle, "title") }

            add(view.accessibilityLabel, "a11y")

            for child in view.subviews {
                visit(child)
            }
        }

        visit(root)

        rows.sort {
            $0.minY != $1.minY ? $0.minY < $1.minY : $0.minX < $1.minX
        }

        return rows.map { $0.line }
    }

    // Giá dòng sản phẩm trong giỏ có tên khớp tên đã lưu (tên đã lưu là tiền
    // tố của tên trên dòng, hoặc ngược lại). Trả nil nếu không thấy dòng nào.
    static func rowPrice(for title: String, in items: [TPIOSSaleTextItem]) -> Double? {
        let key = TPIOSSaleMatcher.normalize(title)
        guard key.count >= 8 else { return nil }

        let head = String(key.prefix(14))

        let row = items
            .filter { TPIOSSaleMatcher.normalize($0.text).contains(head) }
            .max { $0.text.count < $1.text.count }

        return row.flatMap { extractAmounts(from: $0.text).first }
    }

    // Tổng ở thanh đáy giỏ (dòng có "Mua hàng"): số tiền lớn nhất trong dải
    // ngang của thanh, bỏ dòng "Tiết kiệm". Nil nếu không thấy thanh đáy.
    static func cartTotal(in items: [TPIOSSaleTextItem]) -> Double? {
        guard let bar = items.first(where: { $0.text.contains("Mua hàng") }) else { return nil }

        // Tổng nằm cùng hàng với nút Mua hàng, ở bên trái và sát nút nhất.
        return items
            .filter {
                abs($0.frame.midY - bar.frame.midY) <= 60 &&
                $0.frame.maxX <= bar.frame.minX + 8 &&
                $0.text.lowercased().contains("tiết kiệm") == false
            }
            .flatMap { item in extractAmounts(from: item.text).map { (amount: $0, edge: item.frame.maxX) } }
            .max { $0.edge < $1.edge }?
            .amount
    }

    // Các dòng chữ quanh thanh đáy, dùng để ghi log khi không đọc được tổng.
    static func bottomBarDump(in items: [TPIOSSaleTextItem]) -> String {
        guard let bar = items.first(where: { $0.text.contains("Mua hàng") }) else {
            return "không thấy chữ Mua hàng"
        }

        return items
            .filter { abs($0.frame.midY - bar.frame.midY) <= 120 }
            .prefix(15)
            .map { "[x=\(Int($0.frame.minX))..\(Int($0.frame.maxX)) y=\(Int($0.frame.midY))] \($0.text)" }
            .joined(separator: " | ")
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func extractAmounts(from text: String) -> [Double] {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "₫", with: "")
            .replacingOccurrences(of: "đ", with: "")
            .replacingOccurrences(of: "Đ", with: "")

        let pattern = #"(?<!\d)(\d{1,3}(?:[.,]\d{3})+|\d{4,9})(?!\d)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(normalized.startIndex..., in: normalized)
        let matches = regex.matches(in: normalized, range: range)

        return matches.compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: normalized) else {
                return nil
            }

            let raw = String(normalized[matchRange])
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "")

            guard let value = Double(raw),
                  value >= 1000,
                  value <= 999_999_999 else {
                return nil
            }

            return value
        }
    }

    // Các giá tiền gần điểm chạm (gần nhất xếp trước). near == nil: toàn màn
    // hình, lớn nhất xếp trước. Bỏ chữ về mã giảm giá / phí ship để không lẫn
    // với giá sản phẩm.
    static func prices(in items: [TPIOSSaleTextItem], near point: CGPoint?, radius: CGFloat) -> [Double] {
        let skip = ["giảm", "tối thiểu", "voucher", "vận chuyển", "tiết kiệm", "đã bán"]
        var scored: [(amount: Double, dist: CGFloat)] = []

        for item in items {
            let lower = item.text.lowercased()
            if skip.contains(where: { lower.contains($0) }) { continue }

            for amount in extractAmounts(from: item.text) {
                var dist: CGFloat = 0

                if let point {
                    dist = distance(from: point, to: item.frame)
                    if dist > radius { continue }
                }

                scored.append((amount, dist))
            }
        }

        if point != nil {
            scored.sort { $0.dist < $1.dist }
        } else {
            scored.sort { $0.amount > $1.amount }
        }

        var result: [Double] = []

        for entry in scored {
            if result.contains(entry.amount) == false {
                result.append(entry.amount)
            }

            if result.count == 8 { break }
        }

        return result
    }

    // Mã giảm giá đang hiển thị: mỗi dòng có "giảm <số>" hoặc nhắc miễn phí
    // vận chuyển là 1 mã; ghép các dòng chữ ngay quanh nó (45pt phía trên,
    // 80pt phía dưới) thành 1 "thẻ" rồi đọc mức giảm / đơn tối thiểu / giảm
    // tối đa / loại. Mã loại Shop chỉ lấy khi nằm gần sản phẩm đã chạm.
    static func vouchers(in items: [TPIOSSaleTextItem], near point: CGPoint?) -> [TPIOSSaleVoucher] {
        let discountPattern = try? NSRegularExpression(
            pattern: #"giảm(?:\s+giá)?\s+\d"#,
            options: [.caseInsensitive]
        )

        func isSeed(_ text: String) -> Bool {
            let lower = text.lowercased()

            if lower.contains("miễn phí vận chuyển") || lower.contains("freeship") || lower.contains("free ship") {
                return true
            }

            let range = NSRange(lower.startIndex..., in: lower)
            return discountPattern?.firstMatch(in: lower, range: range) != nil
        }

        let sorted = items
            .filter { $0.text.count <= 140 }
            .sorted { $0.frame.minY < $1.frame.minY }

        var result: [TPIOSSaleVoucher] = []

        for seed in sorted where isSeed(seed.text) {
            let lines = sorted.filter { item in
                let isSelf = item.frame.minY == seed.frame.minY && item.frame.minX == seed.frame.minX
                let inBand = item.frame.minY >= seed.frame.minY - 45 && item.frame.minY <= seed.frame.minY + 80
                return inBand && (isSelf || isSeed(item.text) == false)
            }.map { $0.text }

            guard let parsed = TPIOSSaleVoucherParser.parse(lines: lines) else { continue }

            if let point, parsed.kind == "shop", abs(seed.frame.midY - point.y) > 320 {
                continue
            }

            let voucher = TPIOSSaleVoucher(
                id: UUID().uuidString,
                title: parsed.title,
                kind: parsed.kind,
                isPercent: parsed.isPercent,
                value: parsed.value,
                minSpend: parsed.minSpend,
                maxDiscount: parsed.maxDiscount,
                expiryText: parsed.expiryText
            )

            if result.contains(where: { $0.sameAs(voucher) }) == false {
                result.append(voucher)
            }
        }

        return result
    }
}
