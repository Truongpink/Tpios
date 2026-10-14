import UIKit
import Foundation
import Darwin

final class TPIOSAutoClickEngine {
    static let shared = TPIOSAutoClickEngine()
    private init() {}

    func tap(at point: CGPoint) -> Bool {
        TPIOSLog.shared.log("TapEngine: request point=\(point)")
        guard let window = Self.appWindow() else {
            TPIOSLog.shared.log("TapEngine: appWindow=nil")
            return false
        }

        let windowPoint = window.convert(point, from: nil) // nil = screen coordinate space
        guard let hit = window.hitTest(windowPoint, with: nil) else {
            TPIOSLog.shared.log("TapEngine: hitTest=nil point=\(windowPoint)")
            return false
        }

        // The TPIOS panel is an overlay in the same application window. Never
        // treat one of its own views as the Shopee target.
        if hit is TPIOSAutoClickPanel || hit.isDescendant(of: TPIOSAutoClickPanel.self) {
            TPIOSLog.shared.log("TapEngine: hit landed on TPIOS panel; ignoring overlay")
            return false
        }

        TPIOSLog.shared.log("TapEngine: hit=\(NSStringFromClass(type(of: hit)))")

        // 1) Standard UIKit control dispatch.
        var view: UIView? = hit
        while let current = view {
            if let control = current as? UIControl,
               control.isEnabled, !control.isHidden, control.alpha > 0 {
                TPIOSLog.shared.log("TapEngine: UIControl=\(NSStringFromClass(type(of: control)))")
                control.sendActions(for: .touchUpInside)
                return true
            }
            view = current.superview
        }

        // 2) Accessibility activation for accessible native elements.
        view = hit
        while let current = view {
            if current.isAccessibilityElement, current.accessibilityActivate() {
                TPIOSLog.shared.log("TapEngine: accessibility activated \(NSStringFromClass(type(of: current)))")
                return true
            }
            view = current.superview
        }

        // 3) Walk the complete view subtree at the exact point. React Native
        // containers and ordinary UIView wrappers commonly contain the actual
        // actionable control, so this must not be limited to RCTView roots.
        if let descendant = deepestActionableDescendant(of: hit, windowPoint: windowPoint, window: window) {
            TPIOSLog.shared.log("TapEngine: descendant target \(NSStringFromClass(type(of: descendant)))")
            if let control = descendant as? UIControl,
               control.isEnabled, !control.isHidden, control.alpha > 0 {
                control.sendActions(for: .touchUpInside)
                return true
            }
            if descendant.isAccessibilityElement, descendant.accessibilityActivate() {
                return true
            }
        }

        // A genuine UITouch cannot be constructed through the public UIKit API.
        // Do not report success for a synthetic action that was never delivered.
        TPIOSLog.shared.log("TapEngine: no public actionable target hit=\(NSStringFromClass(type(of: hit)))")
        return false
    }

    private func deepestActionableDescendant(of root: UIView, windowPoint: CGPoint, window: UIWindow) -> UIView? {
        var best: UIView?
        func walk(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0, view.isUserInteractionEnabled else { return }
            let local = view.convert(windowPoint, from: window)
            guard view.bounds.contains(local) else { return }
            for child in view.subviews.reversed() {
                if child is TPIOSAutoClickPanel { continue }
                walk(child)
                if best != nil { return }
            }
            if view !== root && (view is UIControl || view.isAccessibilityElement) {
                best = view
            }
        }
        walk(root)
        return best
    }

    static func appWindow() -> UIWindow? {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var windows: [UIWindow] = []
        for scene in scenes { windows.append(contentsOf: scene.windows) }
        for window in windows {
            let className = NSStringFromClass(type(of: window))
            if !window.isHidden &&
                window.alpha > 0 &&
                window.windowLevel == .normal &&
                window.rootViewController != nil &&
                !className.contains("TPIOS") {
                return window
            }
        }
        return nil
    }
}

private extension UIView {
    func isDescendant(of type: UIView.Type) -> Bool {
        var current: UIView? = self
        while let view = current {
            if type(of: view) == type { return true }
            current = view.superview
        }
        return false
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
        p.onBack = { [weak self] in self?.finish(restoreMenu: true) }
        p.onClose = { [weak self] in
            self?.finish(restoreMenu: false)
            NotificationCenter.default.post(name: .tpiosCloseMenu, object: nil)
        }
        window.addSubview(p)
        panel = p
        TPIOSLog.shared.log("TapPanel: opened")
    }

    private func finish(restoreMenu: Bool) {
        if let panel {
            panel.cleanup()
            panel.removeFromSuperview()
        }
        panel = nil
        let completion = onFinish
        onFinish = nil
        if restoreMenu { completion?() }
        TPIOSLog.shared.log("TapPanel: closed restoreMenu=\(restoreMenu)")
    }
}
