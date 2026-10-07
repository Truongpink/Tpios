import Foundation
import StoreKit

// Chẩn đoán thanh toán hợp lệ: đọc receipt và trạng thái StoreKit hiện có.
// Không sửa receipt, entitlement hoặc kết quả giao dịch.
final class TPIOSPaymentScanner {

    static func receiptInfo() -> String {
        guard let url = Bundle.main.appStoreReceiptURL else {
            return "Receipt URL: không có"
        }

        let exists = FileManager.default.fileExists(atPath: url.path)
        let size: Int64

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let value = attributes[.size] as? NSNumber {
            size = value.int64Value
        } else {
            size = 0
        }

        return [
            "Receipt: \(exists ? "Có" : "Không")",
            "Kích thước: \(size) bytes",
            "Đường dẫn: \(url.path)"
        ].joined(separator: "\n")
    }

    static func storeKit1Status() -> String {
        let queue = SKPaymentQueue.default()
        return "SKPaymentQueue: \(queue.transactions.count) giao dịch đang có"
    }

    @available(iOS 15.0, *)
    static func storeKit2Status() async -> String {
        var count = 0

        for await _ in Transaction.currentEntitlements {
            count += 1
        }

        return "StoreKit 2: \(count) entitlement hợp lệ hiện tại"
    }

    static func summary() -> String {
        var lines = [receiptInfo(), storeKit1Status()]

        if #available(iOS 15.0, *) {
            lines.append("StoreKit 2: hỗ trợ API")
        } else {
            lines.append("StoreKit 2: không hỗ trợ trên iOS này")
        }

        return lines.joined(separator: "\n")
    }
}
