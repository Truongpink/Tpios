import UIKit

struct TPIOSSaleScanValue {
    let text: String
    let amount: Double
}

enum TPIOSSaleScanner {

    static func scanVisibleApp(in root: UIView) -> [TPIOSSaleScanValue] {
        var texts: [String] = []
        collectText(from: root, into: &texts)

        var values: [TPIOSSaleScanValue] = []
        var seen = Set<String>()

        for text in texts {
            for amount in extractAmounts(from: text) {
                let key = "\(text)|\(amount)"
                guard seen.insert(key).inserted else { continue }

                values.append(
                    TPIOSSaleScanValue(
                        text: text,
                        amount: amount
                    )
                )
            }
        }

        return values
            .sorted { $0.amount > $1.amount }
            .prefix(30)
            .map { $0 }
    }

    static func summary(_ values: [TPIOSSaleScanValue]) -> String {
        var output = "ĐÃ QUÉT MÀN HÌNH\n\n"
        output += "Các giá trị tiền tìm thấy:\n"

        for value in values {
            output += "• \(formatMoney(value.amount))"
            if value.text != formatMoney(value.amount) {
                output += "  —  \(value.text)"
            }
            output += "\n"
        }

        output += "\nBước này chỉ đọc text đang hiển thị trên màn hình."
        output += "\nChưa tự áp dụng voucher hay gọi API Shopee."

        return output
    }

    private static func collectText(
        from view: UIView,
        into texts: inout [String]
    ) {
        if let label = view as? UILabel, let text = label.text, !text.isEmpty {
            texts.append(text)
        }

        if let field = view as? UITextField {
            if let text = field.text, !text.isEmpty {
                texts.append(text)
            }
            if let placeholder = field.placeholder, !placeholder.isEmpty {
                texts.append(placeholder)
            }
        }

        if let textView = view as? UITextView, let text = textView.text, !text.isEmpty {
            texts.append(text)
        }

        if let button = view as? UIButton {
            if let title = button.currentTitle, !title.isEmpty {
                texts.append(title)
            }
            if let accessibilityLabel = button.accessibilityLabel,
               !accessibilityLabel.isEmpty {
                texts.append(accessibilityLabel)
            }
        }

        if let accessibilityLabel = view.accessibilityLabel,
           !accessibilityLabel.isEmpty {
            texts.append(accessibilityLabel)
        }

        for child in view.subviews {
            collectText(from: child, into: &texts)
        }
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

    private static func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0

        return "\(formatter.string(from: NSNumber(value: value)) ?? "0")đ"
    }
}
