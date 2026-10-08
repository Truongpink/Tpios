import Foundation
import ObjectiveC

// Ghi nội dung trả về của request giỏ hàng (URL chứa "cart/get") vào log, với
// tiền tố "CartBody:". Cách làm: hook lúc tạo URLSession có delegate, rồi chen
// vào 2 hàm của delegate đó (nhận dữ liệu, kết thúc). Request khác không bị đụng.

typealias TPIOSReceiveFn = @convention(c) (AnyObject, Selector, URLSession, URLSessionDataTask, NSData) -> Void
typealias TPIOSCompleteFn = @convention(c) (AnyObject, Selector, URLSession, URLSessionTask, NSError?) -> Void

extension URLSession {

    @objc(tpios_sessionWithConfiguration:delegate:delegateQueue:)
    class func tpios_sessionWithConfiguration(
        _ configuration: URLSessionConfiguration,
        delegate: URLSessionDelegate?,
        delegateQueue queue: OperationQueue?
    ) -> URLSession {
        let session = tpios_sessionWithConfiguration(configuration, delegate: delegate, delegateQueue: queue)
        TPIOSCartBody.shared.hookDelegate(delegate)
        return session
    }
}

final class TPIOSCartBody {

    static let shared = TPIOSCartBody()

    static let receiveSelector = NSSelectorFromString("URLSession:dataTask:didReceiveData:")
    static let completeSelector = NSSelectorFromString("URLSession:task:didCompleteWithError:")
    static let methodTypes = "v40@0:8@16@24@32"

    private var didInstall = false
    private var hookedClasses = Set<String>()
    private var previousReceive: [String: IMP] = [:]
    private var previousComplete: [String: IMP] = [:]
    private var buffers: [Int: Data] = [:]

    private init() {}

    func install() {
        guard didInstall == false else { return }
        didInstall = true

        guard
            let original = class_getClassMethod(URLSession.self, NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:")),
            let swizzled = class_getClassMethod(URLSession.self, NSSelectorFromString("tpios_sessionWithConfiguration:delegate:delegateQueue:"))
        else {
            TPIOSLog.shared.log("CartBody: không lấy được method tạo session")
            return
        }

        method_exchangeImplementations(original, swizzled)
        TPIOSLog.shared.log("CartBody: đã hook tạo URLSession, sẽ ghi nội dung cart/get")
    }

    func hookDelegate(_ delegate: URLSessionDelegate?) {
        guard let object = delegate as AnyObject?, let cls = object_getClass(object) else { return }

        let name = NSStringFromClass(cls)
        guard hookedClasses.insert(name).inserted else { return }

        let receiveBlock: @convention(block) (AnyObject, URLSession, URLSessionDataTask, NSData) -> Void = { obj, session, task, data in
            TPIOSCartBody.shared.receive(task: task, data: data as Data)

            if let imp = TPIOSCartBody.shared.previousReceive[name] {
                unsafeBitCast(imp, to: TPIOSReceiveFn.self)(obj, TPIOSCartBody.receiveSelector, session, task, data)
            }
        }

        let completeBlock: @convention(block) (AnyObject, URLSession, URLSessionTask, NSError?) -> Void = { obj, session, task, error in
            TPIOSCartBody.shared.finish(task: task)

            if let imp = TPIOSCartBody.shared.previousComplete[name] {
                unsafeBitCast(imp, to: TPIOSCompleteFn.self)(obj, TPIOSCartBody.completeSelector, session, task, error)
            }
        }

        if class_respondsToSelector(cls, TPIOSCartBody.receiveSelector),
           let imp = class_getMethodImplementation(cls, TPIOSCartBody.receiveSelector) {
            previousReceive[name] = imp
        }

        if class_respondsToSelector(cls, TPIOSCartBody.completeSelector),
           let imp = class_getMethodImplementation(cls, TPIOSCartBody.completeSelector) {
            previousComplete[name] = imp
        }

        _ = class_replaceMethod(cls, TPIOSCartBody.receiveSelector, imp_implementationWithBlock(receiveBlock), TPIOSCartBody.methodTypes)
        _ = class_replaceMethod(cls, TPIOSCartBody.completeSelector, imp_implementationWithBlock(completeBlock), TPIOSCartBody.methodTypes)
    }

    private func receive(task: URLSessionDataTask, data: Data) {
        guard isWatched(task) else { return }
        buffers[task.taskIdentifier, default: Data()].append(data)
    }

    private func finish(task: URLSessionTask) {
        let data = buffers.removeValue(forKey: task.taskIdentifier) ?? Data()
        guard isWatched(task) else { return }

        let url = task.currentRequest?.url?.absoluteString ?? ""
        let method = task.originalRequest?.httpMethod ?? "GET"
        TPIOSLog.shared.log("CartBody: \(method) \(url)")

        if let body = task.originalRequest?.httpBody {
            TPIOSLog.shared.log("CartReq(\(body.count) byte): " + oneLine(body))
        } else if task.originalRequest?.httpBodyStream != nil {
            TPIOSLog.shared.log("CartReq: body dạng stream, không đọc được")
        }

        TPIOSLog.shared.log("CartBody(\(data.count) byte): " + oneLine(data))
        TPIOSCartState.shared.ingest(url: url, data: data)
    }

    private func isWatched(_ task: URLSessionTask) -> Bool {
        let url = task.currentRequest?.url?.absoluteString ?? ""
        return ["cart", "voucher", "checkout"].contains { url.contains($0) }
    }

    private func oneLine(_ data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "không đọc được UTF-8 (\(data.count) byte)"
        return String(text.replacingOccurrences(of: "\n", with: " ").prefix(30000))
    }
}


// MARK: - Trạng thái giỏ đọc từ phản hồi của app (không đọc màn hình)

struct TPIOSCartLine {
    let itemID: Int64
    let modelID: Int64
    let shopID: Int64
    let name: String
    let checked: Bool
    let price: Double          // giá sản phẩm sau giảm của shop (VND)
}

struct TPIOSCartSnapshot {
    let lines: [TPIOSCartLine]
    let total: Double?         // tổng các sản phẩm đang tích, sau mọi mã (VND)
    let platformPromoID: Int64 // 0 = chưa áp mã Shopee
    let receivedAt: Date
}

final class TPIOSCartState {

    static let shared = TPIOSCartState()

    private(set) var latest: TPIOSCartSnapshot?

    private init() {}

    // Đọc phản hồi cart/get hoặc cart/update. Giá trong phản hồi nhân 100.000.
    func ingest(url: String, data: Data) {
        guard url.contains("cart/update") || url.contains("cart/get"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any] else {
            return
        }

        var merged: [String: [String: Any]] = [:]
        var order: [String] = []

        for block in payload["cart_blocks"] as? [[String: Any]] ?? [] {
            for item in block["items"] as? [[String: Any]] ?? [] {
                let key = "\(number(item["itemid"]) ?? 0)-\(number(item["modelid"]) ?? 0)"
                if merged[key] == nil { order.append(key) }
                merged[key] = item
            }
            for item in block["updated_items"] as? [[String: Any]] ?? [] {
                let key = "\(number(item["itemid"]) ?? 0)-\(number(item["modelid"]) ?? 0)"
                if merged[key] == nil { order.append(key) }
                merged[key] = item
            }
        }

        let lines: [TPIOSCartLine] = order.compactMap { key in
            guard let item = merged[key],
                  let itemID = number(item["itemid"]),
                  let modelID = number(item["modelid"]),
                  let shopID = number(item["shopid"]) else {
                return nil
            }

            return TPIOSCartLine(
                itemID: itemID,
                modelID: modelID,
                shopID: shopID,
                name: item["name"] as? String ?? "",
                checked: item["checkout"] as? Bool ?? false,
                price: Double(number(item["display_final_price"]) ?? 0) / 100_000
            )
        }

        let discount = payload["discount_detail"] as? [String: Any]
        let totalValue = (discount?["total"] as? [String: Any]).flatMap { number($0["value"]) }
        let total = totalValue.map { Double($0) / 100_000 }

        let preCheckout = payload["pre_checkout_data"] as? String ?? ""
        let promoID = firstMatch(in: preCheckout, pattern: #""platform_voucher":\{"promotion_id":(\d+)"#)
            .flatMap { Int64($0) } ?? 0

        let snapshot = TPIOSCartSnapshot(lines: lines, total: total, platformPromoID: promoID, receivedAt: Date())

        DispatchQueue.main.async {
            TPIOSCartState.shared.latest = snapshot
        }
    }

    private func number(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
