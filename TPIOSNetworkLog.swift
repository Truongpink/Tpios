import Foundation

struct TPIOSSaleRequestEvidence: Codable {
    let url: String
    let timestamp: Date
}

final class TPIOSNetworkLog {

    static let shared = TPIOSNetworkLog()

    private var didInstall = false
    private var recentRequests: [TPIOSSaleRequestEvidence] = []
    private let lock = NSLock()
    private let maxRecentRequests = 120

    private init() {}

    func install() {
        guard didInstall == false else {
            return
        }
        didInstall = true

        let probeSession = URLSession(configuration: .ephemeral)
        let probeTask = probeSession.dataTask(
            with: URL(string: "https://www.apple.com")!
        )
        let targetClass: AnyClass = type(of: probeTask)
        probeTask.cancel()

        TPIOSLog.shared.log(
            "NetLog: class thật của NSURLSessionTask = \(NSStringFromClass(targetClass))"
        )

        let originalSelector = NSSelectorFromString("resume")
        let swizzledSelector = #selector(URLSessionTask.tpios_resume)

        guard
            let originalMethod = class_getInstanceMethod(targetClass, originalSelector),
            let swizzledMethod = class_getInstanceMethod(URLSessionTask.self, swizzledSelector)
        else {
            TPIOSLog.shared.log("NetLog: không lấy được method resume để swizzle")
            didInstall = false
            return
        }

        let didAddMethod = class_addMethod(
            targetClass,
            swizzledSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )

        if didAddMethod,
           let addedMethod = class_getInstanceMethod(targetClass, swizzledSelector) {
            method_exchangeImplementations(originalMethod, addedMethod)
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }

        TPIOSLog.shared.log(
            "NetLog: đã hook \(NSStringFromClass(targetClass)).resume — request mới sẽ log ở đây"
        )
    }

    func recentSaleRequestEvidence() -> [TPIOSSaleRequestEvidence] {
        lock.lock()
        defer { lock.unlock() }
        return recentRequests
    }

    func recentSaleRequestURLs() -> [String] {
        recentSaleRequestEvidence().map(\.url)
    }

    fileprivate func recordRequest(_ url: String) {
        guard isRelevantShopeeRequest(url) else {
            return
        }

        let evidence = TPIOSSaleRequestEvidence(
            url: url,
            timestamp: Date()
        )

        lock.lock()
        recentRequests.append(evidence)
        if recentRequests.count > maxRecentRequests {
            recentRequests.removeFirst(recentRequests.count - maxRecentRequests)
        }
        lock.unlock()
    }

    private func isRelevantShopeeRequest(_ url: String) -> Bool {
        let lower = url.lowercased()
        guard lower.contains("shopee") else {
            return false
        }

        return lower.contains("item") ||
            lower.contains("product") ||
            lower.contains("voucher") ||
            lower.contains("discount") ||
            lower.contains("shipping") ||
            lower.contains("flash")
    }
}

extension URLSessionTask {

    @objc fileprivate func tpios_resume() {
        let url = self.originalRequest?.url?.absoluteString
            ?? self.currentRequest?.url?.absoluteString
            ?? "<không rõ URL>"

        TPIOSLog.shared.log("NetLog: \(url)")
        TPIOSNetworkLog.shared.recordRequest(url)

        self.tpios_resume()
    }
}
