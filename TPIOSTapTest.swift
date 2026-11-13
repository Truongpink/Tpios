import UIKit
import Foundation
import Darwin

@_silgen_name("TPIOSCHMTouchAvailable") private func TPIOSCHMTouchAvailable() -> Bool
@_silgen_name("TPIOSCHMTouchDispatch") private func TPIOSCHMTouchDispatch(_ x: Double, _ y: Double, _ phase: Int32) -> Bool

final class TPIOSRealTouchProbe: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var lastPoint: CGPoint = .zero

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view = view {
            lastPoint = touch.location(in: view)
            let targetView = touch.view.map { NSStringFromClass(type(of: $0)) } ?? "nil"
            
        }
        // Keep the recognizer in .possible while the finger is down.
        // This observes the real touch without recognizing/cancelling it early.
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view = view else { return }
        let point = touch.location(in: view)
        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        lastPoint = point
        
        // Do not recognize a tap until the finger is lifted.
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view = view {
            let point = touch.location(in: view)
            
        }
        state = .recognized
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view = view {
            let point = touch.location(in: view)
            
        } else {
            
        }
        state = .cancelled
    }

    override func reset() {
        lastPoint = .zero
        super.reset()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

final class TPIOSAutoClickEngine {
    static let shared = TPIOSAutoClickEngine()
    private var touchProbe: TPIOSRealTouchProbe?
    private init() {}
    func startTouchProbe(on window: UIWindow) {
        guard touchProbe == nil else { return }
        let probe = TPIOSRealTouchProbe(target: nil, action: nil)
        window.addGestureRecognizer(probe)
        touchProbe = probe
        TPIOSLog.shared.log("TapProbe: installed on window=\(NSStringFromClass(type(of: window)))")
    }
    func stopTouchProbe() {
        guard let probe = touchProbe else { return }
        probe.view?.removeGestureRecognizer(probe)
        touchProbe = nil
        TPIOSLog.shared.log("TapProbe: removed")
    }
    func dispatchTouch(at point: CGPoint, down: Bool) -> Bool {
        TPIOSCHMTouchDispatch(point.x, point.y, down ? 0 : 3)
    }
    static func backendAvailable() -> Bool { TPIOSCHMTouchAvailable() }
    static func appWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            let appWindows = scene.windows.filter {
                !$0.isHidden &&
                $0.alpha > 0.01 &&
                !NSStringFromClass(type(of: $0)).hasSuffix("TPIOSPassThroughWindow") &&
                $0.windowLevel < .alert &&
                $0.rootViewController != nil
            }
            if let keyWindow = appWindows.first(where: \\.isKeyWindow) { return keyWindow }
            if let appWindow = appWindows.first { return appWindow }
        }
        return nil
    }
}
final class TPIOSTapTest {
    static let shared = TPIOSTapTest()
    var onFinish: (() -> Void)?
    private var panel: TPIOSAutoClickPanel?
    private init() {}

    func start() {
        guard panel == nil, let window = TPIOSAutoClickEngine.appWindow() else { return }
        let size = CGSize(width: 230, height: 320)
        let frame = CGRect(x: (window.bounds.width - size.width) / 2, y: (window.bounds.height - size.height) / 2, width: size.width, height: size.height)
        let p = TPIOSAutoClickPanel(frame: frame)
        p.tag = 0x5450494F
        p.onBack = { [weak self] in self?.finish(restoreMenu: true) }
        p.onClose = { [weak self] in
            self?.finish(restoreMenu: false)
            NotificationCenter.default.post(name: .tpiosCloseMenu, object: nil)
        }
        window.addSubview(p)
        panel = p
        TPIOSAutoClickEngine.shared.startTouchProbe(on: window)
        TPIOSLog.shared.log("TapPanel: opened")
    }

    private func finish(restoreMenu: Bool) {
        TPIOSAutoClickEngine.shared.stopTouchProbe()
        if let panel { panel.cleanup(); panel.removeFromSuperview() }
        panel = nil
        let completion = onFinish
        onFinish = nil
        if restoreMenu { completion?() }
        TPIOSLog.shared.log("TapPanel: closed restoreMenu=\(restoreMenu)")
    }
}
