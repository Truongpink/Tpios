import UIKit
import Foundation
import Darwin

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
        super.init(coder: coder)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view = view {
            lastPoint = touch.location(in: view)
            let targetView = touch.view.map { NSStringFromClass(type(of: $0)) } ?? "nil"
            TPIOSLog.shared.log("TapProbe: began count=\(touches.count) point=\(lastPoint) target=\(targetView)")
        }
        state = .began
        state = .changed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view = view else { return }
        let point = touch.location(in: view)
        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        lastPoint = point
        TPIOSLog.shared.log("TapProbe: moved count=\(touches.count) point=\(point) delta=(\(dx), \(dy)) target=\(NSStringFromClass(type(of: touch.view ?? view)))")
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view = view {
            let point = touch.location(in: view)
            TPIOSLog.shared.log("TapProbe: ended count=\(touches.count) point=\(point) target=\(NSStringFromClass(type(of: touch.view ?? view)))")
        }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view = view {
            let point = touch.location(in: view)
            TPIOSLog.shared.log("TapProbe: cancelled count=\(touches.count) point=\(point) target=\(NSStringFromClass(type(of: touch.view ?? view)))")
        } else {
            TPIOSLog.shared.log("TapProbe: cancelled count=\(touches.count)")
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

    func tap(at point: CGPoint) -> Bool {
        TPIOSLog.shared.log("TapEngine: request point=\(point)")
        guard let window = Self.appWindow() else {
            TPIOSLog.shared.log("TapEngine: appWindow=nil")
            return false
        }
        let windowPoint = window.convert(point, from: nil)
        TPIOSLog.shared.log("TapEngine: windowPoint=\(windowPoint) window=\(NSStringFromClass(type(of: window)))")
        guard let hit = window.hitTest(windowPoint, with: nil) else {
            TPIOSLog.shared.log("TapEngine: hitTest=nil point=\(windowPoint)")
            return false
        }
        var ancestor: UIView? = hit
        while let current = ancestor {
            if current is TPIOSAutoClickPanel {
                TPIOSLog.shared.log("TapEngine: hit landed on TPIOS panel; ignoring overlay")
                return false
            }
            ancestor = current.superview
        }
        TPIOSLog.shared.log("TapEngine: hit=\(NSStringFromClass(type(of: hit)))")
        logHitHierarchy(from: hit, windowPoint: windowPoint, window: window)
        var view: UIView? = hit
        while let current = view {
            if let control = current as? UIControl, control.isEnabled, !control.isHidden, control.alpha > 0 {
                TPIOSLog.shared.log("TapEngine: UIControl=\(NSStringFromClass(type(of: control)))")
                control.sendActions(for: .touchUpInside)
                return true
            }
            view = current.superview
        }
        view = hit
        while let current = view {
            if current.isAccessibilityElement, current.accessibilityActivate() {
                TPIOSLog.shared.log("TapEngine: accessibility activated \(NSStringFromClass(type(of: current)))")
                return true
            }
            view = current.superview
        }
        if let descendant = deepestActionableDescendant(of: hit, windowPoint: windowPoint, window: window) {
            TPIOSLog.shared.log("TapEngine: descendant target \(NSStringFromClass(type(of: descendant)))")
            if let control = descendant as? UIControl, control.isEnabled, !control.isHidden, control.alpha > 0 {
                control.sendActions(for: .touchUpInside)
                return true
            }
            if descendant.isAccessibilityElement, descendant.accessibilityActivate() { return true }
        }
        TPIOSLog.shared.log("TapEngine: no public actionable target hit=\(NSStringFromClass(type(of: hit)))")
        return false
    }

    private func logHitHierarchy(from hit: UIView, windowPoint: CGPoint, window: UIWindow) {
        var current: UIView? = hit
        var level = 0
        while let view = current, level < 12 {
            let frame = view.convert(view.bounds, to: window)
            let gestures = view.gestureRecognizers?.map { NSStringFromClass(type(of: $0)) }.joined(separator: ",") ?? "none"
            TPIOSLog.shared.log("TapDebug: level=\(level) class=\(NSStringFromClass(type(of: view))) frame=\(frame) userInteraction=\(view.isUserInteractionEnabled) hidden=\(view.isHidden) alpha=\(view.alpha) accessibility=\(view.isAccessibilityElement) gestures=[\(gestures)] subviews=\(view.subviews.count)")
            if let gestureRecognizers = view.gestureRecognizers {
                for (index, gesture) in gestureRecognizers.enumerated() {
                    let delegate = gesture.delegate.map { NSStringFromClass(type(of: $0)) } ?? "nil"
                    let gestureView = gesture.view.map { NSStringFromClass(type(of: $0)) } ?? "nil"
                    var touchInfo = ""
                    if let pan = gesture as? UIPanGestureRecognizer {
                        touchInfo = " minTouches=\(pan.minimumNumberOfTouches) maxTouches=\(pan.maximumNumberOfTouches) numberOfTouches=\(pan.numberOfTouches) translation=\(pan.translation(in: view)) velocity=\(pan.velocity(in: view))"
                    }
                    TPIOSLog.shared.log("TapDebug: gesture level=\(level) index=\(index) class=\(NSStringFromClass(type(of: gesture))) state=\(gesture.state.rawValue) enabled=\(gesture.isEnabled) cancels=\(gesture.cancelsTouchesInView) delaysTouches=\(gesture.delaysTouchesBegan) delaysEnded=\(gesture.delaysTouchesEnded)\(touchInfo) delegate=\(delegate) view=\(gestureView)")
                }
            }
            current = view.superview
            level += 1
        }
        logContainingSubviews(from: hit, windowPoint: windowPoint, window: window)
    }

    private func logContainingSubviews(from root: UIView, windowPoint: CGPoint, window: UIWindow) {
        var queue: [(UIView, Int)] = [(root, 0)]
        var count = 0
        while !queue.isEmpty && count < 40 {
            let (view, depth) = queue.removeFirst()
            for child in view.subviews.reversed() {
                let local = child.convert(windowPoint, from: window)
                guard !child.isHidden, child.alpha > 0, child.bounds.contains(local) else { continue }
                let gestures = child.gestureRecognizers?.map { NSStringFromClass(type(of: $0)) }.joined(separator: ",") ?? "none"
                TPIOSLog.shared.log("TapDebug: childDepth=\(depth + 1) class=\(NSStringFromClass(type(of: child))) frame=\(child.convert(child.bounds, to: window)) control=\(child is UIControl) accessibility=\(child.isAccessibilityElement) userInteraction=\(child.isUserInteractionEnabled) gestures=[\(gestures)]")
                queue.append((child, depth + 1))
                count += 1
                if count >= 40 { break }
            }
        }
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
            if view !== root && (view is UIControl || view.isAccessibilityElement) { best = view }
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
            if !window.isHidden && window.alpha > 0 && window.windowLevel == .normal && window.rootViewController != nil && !className.contains("TPIOS") { return window }
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
