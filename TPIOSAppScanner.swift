import Foundation
import UIKit

// Quét chẩn đoán các thành phần StoreKit đang có trong app hiện tại.
// Chỉ đọc runtime/bundle, không can thiệp giao dịch.
final class TPIOSAppScanner {

    struct Result {
        let bundleID: String
        let appVersion: String
        let storeKit1: Bool
        let storeKit2: Bool
        let classes: [String]
    }

    static func scan() -> Result {
        let bundle = Bundle.main
        let allClasses = runtimeClasses()

        let storeKit1 = NSClassFromString("SKPaymentQueue") != nil ||
            allClasses.contains(where: { $0.hasPrefix("SK") })

        let storeKit2 = NSClassFromString("StoreKit.Transaction") != nil ||
            allClasses.contains(where: { $0.contains("StoreKit.Transaction") })

        let classes = allClasses
            .filter {
                $0.hasPrefix("SK") ||
                $0.contains("StoreKit") ||
                $0.contains("Product") ||
                $0.contains("Transaction") ||
                $0.contains("Receipt")
            }
            .sorted()

        return Result(
            bundleID: bundle.bundleIdentifier ?? "-",
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-",
            storeKit1: storeKit1,
            storeKit2: storeKit2,
            classes: classes
        )
    }

    static func summary() -> String {
        let result = scan()
        return [
            "Bundle: \(result.bundleID)",
            "Version: \(result.appVersion)",
            "StoreKit 1: \(result.storeKit1 ? "Có" : "Không")",
            "StoreKit 2: \(result.storeKit2 ? "Có" : "Không")",
            "Lớp liên quan: \(result.classes.count)"
        ].joined(separator: "\n")
    }

    private static func runtimeClasses() -> [String] {
        var count: UInt32 = 0
        guard let names = objc_copyClassNames(&count) else { return [] }
        defer { free(names) }

        return (0..<Int(count)).compactMap {
            names[$0].map { String(cString: $0) }
        }
    }
}
