import UIKit
import Foundation
import ObjectiveC

private final class TPIOSTapFixState: NSObject {
    weak var panel: TPIOSAutoClickPanel?
    weak var marker: UIView?
    weak var picker: UIView?
    var point: CGPoint?
    var timer: DispatchSourceTimer?
    var running = false
    var count = 0
}

private final class TPIOSTapFixPickerTarget: NSObject {
    weak var panel: TPIOSAutoClickPanel?
    init(panel: TPIOSAutoClickPanel) { self.panel = panel }

    @objc func pick(_ gesture: UITapGestureRecognizer) {
        guard let panel, let window = panel.window, let overlay = gesture.view else { return }
        let point = gesture.location(in: overlay)
        let windowPoint = overlay.convert(point, to: window)
        let state = TPIOSTapFix.state(for: panel)

        state.marker?.removeFromSuperview()
        let marker = UIView(frame: CGRect(x: windowPoint.x - 12, y: windowPoint.y - 12, width: 24, height: 24))
        marker.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        marker.layer.cornerRadius = 12
        marker.layer.borderWidth = 2
        marker.layer.borderColor = UIColor.white.cgColor
        marker.isUserInteractionEnabled = false
        window.insertSubview(marker, belowSubview: panel)
        state.marker = marker
        state.point = windowPoint

        overlay.removeFromSuperview()
        state.picker = nil
        panel.isHidden = false
        window.bringSubviewToFront(panel)

        TPIOSLog.shared.log("TapFix: point saved window=\(windowPoint)")
    }
}

enum TPIOSTapFix {
    private static var stateKey: UInt8 = 0
    private static var installed = false

    static func state(for panel: TPIOSAutoClickPanel) -> TPIOSTapFixState {
        if let state = objc_getAssociatedObject(panel, &stateKey) as? TPIOSTapFixState { return state }
        let state = TPIOSTapFixState()
        state.panel = panel
        objc_setAssociatedObject(panel, &stateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }

    static func install() {
        guard !installed else { return }
        installed = true
        let cls: AnyClass = TPIOSAutoClickPanel.self
        exchange(cls, "pointMode", #selector(TPIOSAutoClickPanel.tpfix_pointMode))
        exchange(cls, "tapMode", #selector(TPIOSAutoClickPanel.tpfix_tapMode))
        exchange(cls, "clearPoints", #selector(TPIOSAutoClickPanel.tpfix_clearPoints))
        exchange(cls, "startStop", #selector(TPIOSAutoClickPanel.tpfix_startStop))
        exchange(cls, "stop", #selector(TPIOSAutoClickPanel.tpfix_stop))
        TPIOSLog.shared.log("TapFix: installed")
    }

    private static func exchange(_ cls: AnyClass, _ originalName: String, _ replacement: Selector) {
        let original = NSSelectorFromString(originalName)
        guard let originalMethod = class_getInstanceMethod(cls, original),
              let replacementMethod = class_getInstanceMethod(cls, replacement) else {
            TPIOSLog.shared.log("TapFix: swizzle missing \(originalName)")
            return
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }

    static func pointMode(_ panel: TPIOSAutoClickPanel) {
        let state = state(for: panel)
        state.picker?.removeFromSuperview()
        state.marker?.removeFromSuperview()
        state.marker = nil
        state.point = nil

        guard let window = panel.window else {
            TPIOSLog.shared.log("TapFix: point picker failed - no window")
            return
        }
        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = UIColor.clear
        overlay.isUserInteractionEnabled = true
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let target = TPIOSTapFixPickerTarget(panel: panel)
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: target, action: #selector(TPIOSTapFixPickerTarget.pick(_:))))
        objc_setAssociatedObject(overlay, Unmanaged.passUnretained(panel).toOpaque(), target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        window.addSubview(overlay)
        window.bringSubviewToFront(overlay)
        state.picker = overlay
        panel.isHidden = true
        TPIOSLog.shared.log("TapFix: full-screen point picker opened")
    }

    static func tapMode(_ panel: TPIOSAutoClickPanel) {
        guard let point = state(for: panel).point else {
            TPIOSLog.shared.log("TapFix: manual tap rejected - no point")
            return
        }
        let ok = tapControl(at: point)
        TPIOSLog.shared.log("TapFix: manual tap result=\(ok) point=\(point)")
    }

    static func clearPoints(_ panel: TPIOSAutoClickPanel) {
        let state = state(for: panel)
        state.timer?.cancel(); state.timer = nil
        state.running = false
        state.count = 0
        state.point = nil
        state.picker?.removeFromSuperview(); state.picker = nil
        state.marker?.removeFromSuperview(); state.marker = nil
        TPIOSLog.shared.log("TapFix: points cleared")
    }

    static func startStop(_ panel: TPIOSAutoClickPanel) {
        let state = state(for: panel)
        guard let point = state.point else {
            TPIOSLog.shared.log("TapFix: auto start rejected - no point")
            return
        }
        if state.running {
            stop(panel)
            return
        }

        let speed = max(0.05, min(5.0, sliderValue(in: panel) ?? 0.15))
        state.running = true
        state.count = 0
        setButtonImage(in: panel, name: "stop.fill")
        setStatus(in: panel, text: "RUNNING")
        TPIOSLog.shared.log("TapFix: auto START point=\(point) speed=\(speed)")
        perform(panel)

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + speed, repeating: speed, leeway: .milliseconds(5))
        timer.setEventHandler { [weak panel] in
            guard let panel else { return }
            perform(panel)
        }
        timer.resume()
        state.timer = timer
    }

    static func stop(_ panel: TPIOSAutoClickPanel) {
        let state = state(for: panel)
        state.running = false
        state.timer?.cancel(); state.timer = nil
        setButtonImage(in: panel, name: "play.fill")
        setStatus(in: panel, text: "STOPPED")
        TPIOSLog.shared.log("TapFix: stopped")
    }

    static func cleanup(_ panel: TPIOSAutoClickPanel) {
        let state = state(for: panel)
        state.running = false
        state.timer?.cancel(); state.timer = nil
        state.picker?.removeFromSuperview()
        state.picker = nil
        state.marker?.removeFromSuperview()
        state.marker = nil
        state.point = nil
        TPIOSLog.shared.log("TapFix: cleanup panel exit - marker/picker/timer removed")
    }

    private static func perform(_ panel: TPIOSAutoClickPanel) {
        let state = state(for: panel)
        guard state.running, let point = state.point else { return }
        let ok = tapControl(at: point)
        if ok {
            state.count += 1
            setCount(in: panel, value: state.count)
            TPIOSLog.shared.log("TapFix: performTap SUCCESS count=\(state.count)")
        } else {
            state.running = false
            state.timer?.cancel(); state.timer = nil
            setButtonImage(in: panel, name: "play.fill")
            setStatus(in: panel, text: "TAP LỖI")
            TPIOSLog.shared.log("TapFix: performTap FAILED point=\(point); stopped because target is not actionable")
        }
    }

    private static func tapControl(at windowPoint: CGPoint) -> Bool {
        guard let window = TPIOSAutoClickEngine.appWindow(),
              let root = window.rootViewController?.view else {
            TPIOSLog.shared.log("TapFix: root view unavailable")
            return false
        }
        let localPoint = root.convert(windowPoint, from: window)
        guard let hit = root.hitTest(localPoint, with: nil) else {
            TPIOSLog.shared.log("TapFix: hitTest=nil point=\(windowPoint)")
            return false
        }
        var view: UIView? = hit
        while let current = view {
            if let control = current as? UIControl, control.isEnabled, !control.isHidden, control.alpha > 0 {
                control.sendActions(for: .touchUpInside)
                TPIOSLog.shared.log("TapFix: UIControl dispatched class=\(NSStringFromClass(type(of: control)))")
                return true
            }
            view = current.superview
        }
        var accessible: UIView? = hit
        while let current = accessible {
            if current.isAccessibilityElement, current.accessibilityActivate() {
                TPIOSLog.shared.log("TapFix: accessibility activated class=\(NSStringFromClass(type(of: current)))")
                return true
            }
            accessible = current.superview
        }
        TPIOSLog.shared.log("TapFix: no actionable control hit=\(NSStringFromClass(type(of: hit)))")
        return false
    }

    private static func sliderValue(in panel: UIView) -> Double? {
        var result: Double?
        func walk(_ view: UIView) {
            if result != nil { return }
            if let slider = view as? UISlider { result = Double(slider.value); return }
            view.subviews.forEach(walk)
        }
        walk(panel)
        return result
    }

    private static func setStatus(in panel: UIView, text: String) {
        findLabels(in: panel).first(where: { $0.text == "IDLE" || $0.text == "RUNNING" || $0.text == "STOPPED" || $0.text == "TAPPED" || $0.text == "TAP LỖI" || $0.text == "CHƯA CÓ ĐIỂM" })?.text = text
    }

    private static func setCount(in panel: UIView, value: Int) {
        findLabels(in: panel).first(where: { $0.text?.hasPrefix("TAP:") == true })?.text = "TAP: \(value)"
    }

    private static func findLabels(in panel: UIView) -> [UILabel] {
        var result: [UILabel] = []
        func walk(_ view: UIView) {
            if let label = view as? UILabel { result.append(label) }
            view.subviews.forEach(walk)
        }
        walk(panel)
        return result
    }

    private static func setButtonImage(in panel: UIView, name: String) {
        func walk(_ view: UIView) {
            if let button = view as? UIButton, button.accessibilityLabel == "play.fill" || button.accessibilityLabel == "stop.fill" {
                button.setImage(UIImage(systemName: name), for: .normal)
                button.accessibilityLabel = name
            }
            view.subviews.forEach(walk)
        }
        walk(panel)
    }
}

extension TPIOSAutoClickPanel {
    @objc dynamic func tpfix_pointMode() { TPIOSTapFix.pointMode(self) }
    @objc dynamic func tpfix_tapMode() { TPIOSTapFix.tapMode(self) }
    @objc dynamic func tpfix_clearPoints() { TPIOSTapFix.clearPoints(self) }
    @objc dynamic func tpfix_startStop() { TPIOSTapFix.startStop(self) }
    @objc dynamic func tpfix_stop() { TPIOSTapFix.stop(self) }
}

@_cdecl("TPIOSTapFixInstall")
public func TPIOSTapFixInstall() {
    TPIOSTapFix.install()
}
