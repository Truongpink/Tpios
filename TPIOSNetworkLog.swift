import Foundation

struct TPIOSSaleRequestEvidence: Codable {
    let url: String
    let timestamp: Date
}

final class TPIOSNetworkLog {

    static let shared = TPIOSNetworkLog()

    private var didInstall = false
    private var recentRequests: [TPIOSSaleRequestEvidence] = []
    private var lazadaCaptureHandler: ((String) -> Void)?
    private let lock = NSLock()
    private let maxRecentRequests = 120

    private init() {}

    @discardableResult
    func startLazadaCapture(onRequest: @escaping (String) -> Void) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier,
              bundleID.caseInsensitiveCompare("com.lazadaSEA.lazada") == .orderedSame else {
            return false
        }

        lock.lock()
        lazadaCaptureHandler = onRequest
        lock.unlock()

        install()
        guard didInstall else {
            lock.lock()
            lazadaCaptureHandler = nil
            lock.unlock()
            return false
        }

        TPIOSLog.shared.log("NetLog: bắt request Lazada đã bật")
        return true
    }

    func stopLazadaCapture() {
        lock.lock()
        lazadaCaptureHandler = nil
        lock.unlock()
        TPIOSLog.shared.log("NetLog: đã dừng bắt request Lazada")
    }

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
        if isRelevantShopeeRequest(url) {
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

        guard let safeURL = sanitizedLazadaURL(url) else { return }
        lock.lock()
        let handler = lazadaCaptureHandler
        lock.unlock()

        if let handler {
            DispatchQueue.main.async {
                handler(safeURL)
            }
        }
    }

    private func sanitizedLazadaURL(_ rawURL: String) -> String? {
        guard let url = URL(string: rawURL),
              let host = url.host?.lowercased(),
              host.contains("lazada") else {
            return nil
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? "\(host)\(url.path)"
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
        let requestURL = self.originalRequest?.url ?? self.currentRequest?.url
        let rawURL = requestURL?.absoluteString ?? "<không rõ URL>"
        let safeURL: String

        if let requestURL,
           var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) {
            components.query = nil
            components.fragment = nil
            safeURL = components.string ?? requestURL.host ?? "<không rõ URL>"
        } else {
            safeURL = "<không rõ URL>"
        }

        TPIOSLog.shared.log("NetLog: \(safeURL)")
        TPIOSNetworkLog.shared.recordRequest(rawURL)

        self.tpios_resume()
    }
}
