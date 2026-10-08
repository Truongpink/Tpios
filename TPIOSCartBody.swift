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
        guard isCartRequest(task) else { return }
        buffers[task.taskIdentifier, default: Data()].append(data)
    }

    private func finish(task: URLSessionTask) {
        let data = buffers.removeValue(forKey: task.taskIdentifier) ?? Data()
        guard isCartRequest(task) else { return }

        let url = task.currentRequest?.url?.absoluteString ?? ""
        let text = String(data: data, encoding: .utf8) ?? "không đọc được UTF-8 (\(data.count) byte)"
        let oneLine = String(text.replacingOccurrences(of: "\n", with: " ").prefix(30000))

        TPIOSLog.shared.log("CartBody: " + url)
        TPIOSLog.shared.log("CartBody(\(data.count) byte): " + oneLine)
    }

    private func isCartRequest(_ task: URLSessionTask) -> Bool {
        task.currentRequest?.url?.absoluteString.contains("cart/get") == true
    }
}

// Cài hook ngay khi tweak được nạp vào app, không chờ bấm Bắt mạng.
// Lý do: session mạng của app thường được tạo từ lúc mở app, trước khi bấm
// nút, nên nếu hook cài muộn thì không bắt được session đó.
@objc(TPIOSCartBootstrap)
final class TPIOSCartBootstrap: NSObject {

    override class func load() {
        TPIOSCartBody.shared.install()
    }
}
