// TPIOSTapTest.swift
// Fixed: replaces sendActions() with IOHIDEvent injection (works on all view types).
// Fixed: picker overlay covers full window, not panel bounds.
// Stubs removed — TPIOSLog, TPIOSPanelStyle, Notification.tpiosCloseMenu
// are defined in their own files in this project.

import UIKit
import Foundation
import ObjectiveC.runtime

// ─────────────────────────────────────────────
// MARK: - IOHIDEvent private API
// ─────────────────────────────────────────────

private typealias IOHIDEventRef = OpaquePointer

@_silgen_name("IOHIDEventCreateDigitizerEvent")
private func IOHIDEventCreateDigitizerEvent(
    _ allocator: OpaquePointer?, _ timeStamp: UInt64,
    _ transducerType: UInt32, _ index: UInt32, _ identity: UInt32,
    _ eventMask: UInt32, _ buttonMask: UInt32,
    _ x: Double, _ y: Double, _ z: Double,
    _ tipPressure: Double, _ twist: Double,
    _ range: Bool, _ touch: Bool, _ options: UInt32
) -> IOHIDEventRef

@_silgen_name("IOHIDEventCreateDigitizerFingerEvent")
private func IOHIDEventCreateDigitizerFingerEvent(
    _ allocator: OpaquePointer?, _ timeStamp: UInt64,
    _ index: UInt32, _ identity: UInt32, _ eventMask: UInt32,
    _ x: Double, _ y: Double, _ z: Double,
    _ tipPressure: Double, _ twist: Double,
    _ range: Bool, _ touch: Bool, _ options: UInt32
) -> IOHIDEventRef

@_silgen_name("IOHIDEventAppendEvent")
private func IOHIDEventAppendEvent(_ parent: IOHIDEventRef, _ child: IOHIDEventRef, _ options: UInt32)

@_silgen_name("mach_absolute_time")
private func mach_absolute_time() -> UInt64

// ─────────────────────────────────────────────
// MARK: - Tap Engine
// ─────────────────────────────────────────────
// Strategy (all tiers run on main thread):
//   Tier 1 — IOHIDEvent digitizer (parent+finger) → _enqueueHIDEvent:
//             This is in-process so sandbox cannot block it. Works on all UIKit
//             and React Native / Flutter apps because UIKit parses the raw HID event.
//   Tier 2 — UITouchesEvent KVC build → UIApplication.sendEvent
//             Fallback for apps that skip _enqueueHIDEvent.
//   Tier 3 — hitTest → UIControl.sendActions / gesture recognizer injection
//             Last resort for pure UIKit button apps.

final class TPIOSAutoClickEngine {
    static let shared = TPIOSAutoClickEngine()
    private init() {}

    @discardableResult
    func tap(at point: CGPoint) -> Bool {
        guard let window = Self.appWindow() else {
            TPIOSLog.shared.log("TapEngine: appWindow=nil")
            return false
        }
        TPIOSLog.shared.log("TapEngine: tap \(point) window=\(NSStringFromClass(type(of: window)))")
        tierOneHID(point: point)
        // Run tier 2 in parallel — belt-and-suspenders approach.
        // Whichever arrives first wins; the duplicate is ignored by UIKit.
        tierTwoUITouch(point: point, window: window)
        return true
    }

    // ── Tier 1: IOHIDEvent with parent digitizer event ───────────────────────
    // UIKit requires a "hand" digitizer parent event wrapping the finger child.
    // Without the parent, _enqueueHIDEvent parses the event but drops the touch.
    private func tierOneHID(point: CGPoint) {
        let enqSel = NSSelectorFromString("_enqueueHIDEvent:")
        let app    = UIApplication.shared
        guard app.responds(to: enqSel) else {
            TPIOSLog.shared.log("TapEngine: tier1 _enqueueHIDEvent not found")
            return
        }

        let screen = UIScreen.main.bounds
        let nx = Double(point.x / screen.width)
        let ny = Double(point.y / screen.height)

        // kIOHIDDigitizerTransducerTypeHand = 2
        // eventMask: range=1, touch=2, position=4 → 7
        let mask: UInt32 = 0x00000007

        func dispatch(touch: Bool, pressure: Double, delay: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let ts = mach_absolute_time()
                let parent = IOHIDEventCreateDigitizerEvent(
                    nil, ts, 2, 0, 0, mask, 0,
                    nx, ny, 0.0, pressure, 0.0, touch, touch, 0)
                let finger = IOHIDEventCreateDigitizerFingerEvent(
                    nil, ts, 1, 1, mask,
                    nx, ny, 0.0, pressure, 0.0, touch, touch, 0)
                IOHIDEventAppendEvent(parent, finger, 0)
                app.perform(enqSel, with: parent as AnyObject)
                TPIOSLog.shared.log("TapEngine: tier1 touch=\(touch) delay=\(delay)")
            }
        }

        dispatch(touch: true,  pressure: 1.0, delay: 0.0)
        dispatch(touch: false, pressure: 0.0, delay: 0.08)
    }

    // ── Tier 2: UITouchesEvent + UITouch via objc_msgSend → sendEvent ────────
    // objc_msgSend lets us call setters that take primitives (phase, tapCount, etc.)
    // without going through KVC (which would throw for unknown keys).
    private func tierTwoUITouch(point: CGPoint, window: UIWindow) {
        guard let touchesEventClass = NSClassFromString("UITouchesEvent"),
              let touchClass        = NSClassFromString("UITouch") else { return }

        let event = touchesEventClass.alloc() as AnyObject
        let touch = (touchClass.alloc() as AnyObject)

        // Object-arg setters (safe via perform:with:)
        func objSet(_ obj: AnyObject, _ sel: String, _ val: AnyObject) {
            let s = NSSelectorFromString(sel)
            guard obj.responds(to: s) else { return }
            _ = obj.perform(s, with: val)
        }
        objSet(touch, "setWindow:", window)
        objSet(touch, "setView:",   window)
        objSet(touch, "setLocationInWindow:",         NSValue(cgPoint: point))
        objSet(touch, "setPreviousLocationInWindow:", NSValue(cgPoint: point))

        // Primitive setters via objc_msgSend (fp: id, SEL, primitive)
        typealias MsgSendInt    = @convention(c) (AnyObject, Selector, Int) -> Void
        typealias MsgSendDouble = @convention(c) (AnyObject, Selector, Double) -> Void
        let msgSend = unsafeBitCast(objc_msgSend as Any,
                                    to: MsgSendInt.self)
        let msgSendD = unsafeBitCast(objc_msgSend as Any,
                                     to: MsgSendDouble.self)

        func intSet(_ obj: AnyObject, _ sel: String, _ v: Int) {
            let s = NSSelectorFromString(sel)
            guard obj.responds(to: s) else { return }
            msgSend(obj, s, v)
        }
        func dblSet(_ obj: AnyObject, _ sel: String, _ v: Double) {
            let s = NSSelectorFromString(sel)
            guard obj.responds(to: s) else { return }
            msgSendD(obj, s, v)
        }

        intSet(touch, "setTapCount:", 1)
        dblSet(touch, "setMajorRadius:", 1.0)
        dblSet(touch, "setMajorRadiusTolerance:", 0.0)

        let addSel = NSSelectorFromString("_addTouch:forDelayedDelivery:")
        if event.responds(to: addSel) {
            _ = event.perform(addSel, with: touch, with: false as AnyObject)
        }

        func send(phase: UITouch.Phase, delay: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                intSet(touch, "setPhase:", phase.rawValue)
                dblSet(touch, "setTimestamp:", Date().timeIntervalSinceReferenceDate)
                let sendSel = NSSelectorFromString("sendEvent:")
                // Send to both UIApplication and UIWindow — whichever routes first wins
                _ = UIApplication.shared.perform(sendSel, with: event)
                _ = window.perform(sendSel, with: event)
                TPIOSLog.shared.log("TapEngine: tier2 phase=\(phase.rawValue)")
            }
        }

        send(phase: .began, delay: 0.005)
        send(phase: .ended, delay: 0.085)
    }

    // ── Window finder ─────────────────────────────────────────────────────────
    static func appWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var all: [UIWindow] = []
        for scene in scenes { all.append(contentsOf: scene.windows) }
        // Prefer the key window
        for w in all {
            guard w.isKeyWindow, !w.isHidden, w.alpha > 0,
                  w.rootViewController != nil,
                  !NSStringFromClass(type(of: w)).contains("TPIOS") else { continue }
            return w
        }
        // Fall back to any normal-level window
        for w in all {
            guard !w.isHidden, w.alpha > 0, w.windowLevel == .normal,
                  w.rootViewController != nil,
                  !NSStringFromClass(type(of: w)).contains("TPIOS") else { continue }
            return w
        }
        return nil
    }
}

// ─────────────────────────────────────────────
// MARK: - TPIOSTapTest (controller)
// ─────────────────────────────────────────────

final class TPIOSTapTest {
    static let shared = TPIOSTapTest()
    var onFinish: (() -> Void)?
    private var panel: TPIOSAutoClickPanel?
    private init() {}

    func start() {
        guard panel == nil, let window = TPIOSAutoClickEngine.appWindow() else { return }
        let size = CGSize(width: 230, height: 320)
        let frame = CGRect(
            x: (window.bounds.width  - size.width)  / 2,
            y: (window.bounds.height - size.height) / 2,
            width:  size.width,
            height: size.height
        )
        let p = TPIOSAutoClickPanel(frame: frame)
        p.onBack  = { [weak self] in self?.finish(restoreMenu: true)  }
        p.onClose = { [weak self] in
            self?.finish(restoreMenu: false)
            NotificationCenter.default.post(name: .tpiosCloseMenu, object: nil)
        }
        window.addSubview(p)
        panel = p
        TPIOSLog.shared.log("TapPanel: opened")
    }

    private func finish(restoreMenu: Bool) {
        panel?.stop()
        panel?.cleanupMarkers()
        panel?.removeFromSuperview()
        panel = nil
        let completion = onFinish
        onFinish = nil
        if restoreMenu { completion?() }
        TPIOSLog.shared.log("TapPanel: closed restoreMenu=\(restoreMenu)")
    }
}

// ─────────────────────────────────────────────
// MARK: - TPIOSAutoClickPanel (UI)
// ─────────────────────────────────────────────

final class TPIOSAutoClickPanel: UIView {
    private var points: [CGPoint] = []
    private var markers: [UIView] = []
    private static let markerTag = 0xAC70  // unique tag to find markers on window
    private var timer: DispatchSourceTimer?
    private var tapCount = 0
    private var running = false
    private var speed: TimeInterval = 0.15
    private var picker: UIView?
    private var currentPointIndex = 0

    private let header     = UIView()
    private let content    = UIView()
    private let statusLabel = UILabel()
    private let countLabel  = UILabel()
    private let pointLabel  = UILabel()
    private let speedLabel  = UILabel()
    private let speedSlider = UISlider()
    private let speedMinusButton = UIButton(type: .system)
    private let speedPlusButton  = UIButton(type: .system)
    private let tapButton   = UIButton(type: .system)
    private let pointButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)
    private let resizeHandle = UILabel()

    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero

    var onBack:  (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    // ── Helpers ───────────────────────────────

    private func iconButton(_ button: UIButton, icon: String, colors: [UIColor], action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        button.setTitle(nil, for: .normal)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        button.tintColor = .white
        button.imageView?.tintColor = .white
        button.imageView?.contentMode = .center
        button.accessibilityLabel = icon
        button.showsTouchWhenHighlighted = true
        button.adjustsImageWhenHighlighted = true
        TPIOSPanelStyle.applyGradientFill(to: button, colors: colors, cornerRadius: 18)
        button.layer.cornerRadius = 18
        button.addTarget(self, action: action, for: .touchUpInside)
        content.addSubview(button)
    }

    private func speedButton(_ button: UIButton, icon: String, action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        button.setTitle(nil, for: .normal)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        button.tintColor = UIColor.white.withAlphaComponent(0.9)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        button.layer.cornerRadius = 10
        button.addTarget(self, action: action, for: .touchUpInside)
        content.addSubview(button)
    }

    private func caption(_ label: UILabel, text: String) {
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        content.addSubview(label)
    }

    private func setup() {
        TPIOSPanelStyle.applyGlassBackground(to: self, cornerRadius: 24)
        clipsToBounds = true

        header.backgroundColor = UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1)
        header.layer.cornerRadius = 24
        header.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(header)

        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = UIColor.white.withAlphaComponent(0.75)
        back.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        back.layer.cornerRadius = 17
        back.addTarget(self, action: #selector(backTap), for: .touchUpInside)
        header.addSubview(back)

        let title = UILabel()
        title.text = "CHẠM"
        title.textColor = .white
        title.font = .systemFont(ofSize: 19, weight: .bold)
        title.textAlignment = .center
        title.tag = 1001
        header.addSubview(title)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = UIColor.white.withAlphaComponent(0.75)
        close.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        close.layer.cornerRadius = 17
        close.addTarget(self, action: #selector(closeTap), for: .touchUpInside)
        header.addSubview(close)

        iconButton(tapButton,   icon: "hand.tap.fill",
                   colors: [UIColor(red: 0.95, green: 0.30, blue: 0.60, alpha: 1),
                             UIColor(red: 0.55, green: 0.10, blue: 0.45, alpha: 1)],
                   action: #selector(tapMode))
        iconButton(pointButton, icon: "scope",
                   colors: [UIColor(red: 0.36, green: 0.71, blue: 1.00, alpha: 1),
                             UIColor(red: 0.09, green: 0.39, blue: 0.80, alpha: 1)],
                   action: #selector(pointMode))
        iconButton(clearButton, icon: "trash.fill",
                   colors: [UIColor(red: 1.00, green: 0.35, blue: 0.27, alpha: 1),
                             UIColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)],
                   action: #selector(clearPoints))
        iconButton(startButton, icon: "play.fill",
                   colors: [UIColor(red: 0.36, green: 0.88, blue: 0.55, alpha: 1),
                             UIColor(red: 0.06, green: 0.52, blue: 0.33, alpha: 1)],
                   action: #selector(startStop))

        let tapLabel = UILabel(), pointCaption = UILabel(), clearLabel = UILabel(), startLabel = UILabel()
        caption(tapLabel,     text: "Chạm")
        caption(pointCaption, text: "Điểm")
        caption(clearLabel,   text: "Xóa")
        caption(startLabel,   text: "Bắt đầu")

        for label in [statusLabel, countLabel, pointLabel] {
            label.textColor = UIColor.white.withAlphaComponent(0.82)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            content.addSubview(label)
        }
        statusLabel.text = "IDLE"
        countLabel.text  = "TAP: 0"
        pointLabel.text  = "POINT: 0"

        speedLabel.text = "Tốc độ  0.15s"
        speedLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        speedLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        speedLabel.textAlignment = .center
        content.addSubview(speedLabel)

        speedSlider.minimumValue = 0.05
        speedSlider.maximumValue = 5.0
        speedSlider.value = Float(speed)
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
        content.addSubview(speedSlider)
        speedButton(speedMinusButton, icon: "chevron.left",  action: #selector(decreaseSpeed))
        speedButton(speedPlusButton,  icon: "chevron.right", action: #selector(increaseSpeed))
        addSubview(content)

        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.42)
        resizeHandle.font = .systemFont(ofSize: 19, weight: .medium)
        resizeHandle.textAlignment = .center
        resizeHandle.isUserInteractionEnabled = true
        addSubview(resizeHandle)

        header.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(movePanel(_:))))
        resizeHandle.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(resizePanel(_:))))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale        = min(bounds.width / 240, bounds.height / 350)
        let headerHeight = 66 * scale
        header.frame  = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        content.frame = CGRect(x: 0, y: headerHeight, width: bounds.width,
                               height: max(0, bounds.height - headerHeight))

        let backSize = 34 * scale, side = 16 * scale
        if let back = header.subviews.first(where: { $0 is UIButton }) as? UIButton {
            back.frame = CGRect(x: side, y: 16 * scale, width: backSize, height: backSize)
        }
        if let close = header.subviews.compactMap({ $0 as? UIButton }).last {
            close.frame = CGRect(x: bounds.width - side - backSize, y: 16 * scale,
                                 width: backSize, height: backSize)
        }
        if let title = header.viewWithTag(1001) as? UILabel {
            title.frame = CGRect(x: 56 * scale, y: 12 * scale,
                                 width: max(0, bounds.width - 112 * scale), height: 42 * scale)
            title.font = .systemFont(ofSize: max(12, 19 * scale), weight: .bold)
        }

        let sidePadding  = 14 * scale, columnGap = 10 * scale
        let contentWidth = max(0, bounds.width - sidePadding * 2)
        let columnWidth  = max(0, (contentWidth - columnGap * 2) / 3)
        let iconSize     = min(columnWidth, 58 * scale), iconInset = max(0, (columnWidth - iconSize) / 2)
        let labelHeight  = 15 * scale, iconLabelGap = 3 * scale
        let rowHeight    = iconSize + iconLabelGap + labelHeight, rowGap = 7 * scale, top = 10 * scale

        let buttons = [tapButton, pointButton, clearButton]
        let labels  = content.subviews.compactMap { $0 as? UILabel }
                        .filter { $0 !== statusLabel && $0 !== countLabel &&
                                  $0 !== pointLabel  && $0 !== speedLabel }
        for i in 0..<buttons.count {
            let x = sidePadding + CGFloat(i) * (columnWidth + columnGap) + iconInset
            buttons[i].frame = CGRect(x: x, y: top, width: iconSize, height: iconSize)
            buttons[i].layer.cornerRadius = iconSize * 0.28
            TPIOSPanelStyle.syncFrames(in: buttons[i])
            if i < labels.count {
                labels[i].frame = CGRect(
                    x: sidePadding + CGFloat(i) * (columnWidth + columnGap),
                    y: top + iconSize + iconLabelGap,
                    width: columnWidth, height: labelHeight)
                labels[i].font = .systemFont(ofSize: max(8, 13 * scale), weight: .semibold)
            }
        }

        let secondY = top + rowHeight + rowGap
        startButton.frame = CGRect(x: sidePadding + iconInset, y: secondY, width: iconSize, height: iconSize)
        startButton.layer.cornerRadius = iconSize * 0.28
        TPIOSPanelStyle.syncFrames(in: startButton)
        if labels.count > 3 {
            labels[3].frame = CGRect(x: sidePadding, y: secondY + iconSize + iconLabelGap,
                                     width: columnWidth, height: labelHeight)
            labels[3].font = .systemFont(ofSize: max(8, 13 * scale), weight: .semibold)
        }

        let infoY = secondY + rowHeight + 3 * scale
        statusLabel.frame = CGRect(x: sidePadding, y: infoY,
                                   width: bounds.width - sidePadding * 2, height: 15 * scale)
        countLabel.frame  = CGRect(x: sidePadding, y: infoY + 16 * scale,
                                   width: (bounds.width - sidePadding * 2) / 2 - 4 * scale, height: 15 * scale)
        pointLabel.frame  = CGRect(x: bounds.midX + 4 * scale, y: infoY + 16 * scale,
                                   width: (bounds.width - sidePadding * 2) / 2 - 4 * scale, height: 15 * scale)
        speedLabel.frame  = CGRect(x: sidePadding, y: infoY + 35 * scale,
                                   width: bounds.width - sidePadding * 2, height: 15 * scale)
        speedLabel.font   = .systemFont(ofSize: max(8, 11 * scale), weight: .semibold)

        let controlY = infoY + 48 * scale, controlHeight = 24 * scale
        let arrowSize = 26 * scale, arrowGap = 4 * scale
        speedMinusButton.frame = CGRect(x: sidePadding, y: controlY, width: arrowSize, height: controlHeight)
        speedPlusButton.frame  = CGRect(x: bounds.width - sidePadding - arrowSize, y: controlY,
                                        width: arrowSize, height: controlHeight)
        speedMinusButton.layer.cornerRadius = 10 * scale
        speedPlusButton.layer.cornerRadius  = 10 * scale
        speedSlider.frame = CGRect(
            x: sidePadding + arrowSize + arrowGap, y: controlY,
            width: max(20, bounds.width - sidePadding * 2 - (arrowSize + arrowGap) * 2),
            height: controlHeight)

        resizeHandle.frame = CGRect(x: bounds.width - 44 * scale, y: bounds.height - 44 * scale,
                                    width: 44 * scale, height: 44 * scale)
        resizeHandle.font = .systemFont(ofSize: 19 * scale, weight: .medium)
    }

    // ── Gestures ──────────────────────────────

    @objc private func movePanel(_ g: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        let t = g.translation(in: sv)
        center.x += t.x; center.y += t.y
        g.setTranslation(.zero, in: sv)
        center.x = min(max(center.x, bounds.width  / 2), sv.bounds.width  - bounds.width  / 2)
        center.y = min(max(center.y, bounds.height / 2), sv.bounds.height - bounds.height / 2)
    }

    @objc private func resizePanel(_ g: UIPanGestureRecognizer) {
        guard let sv = superview else { return }
        switch g.state {
        case .began:
            resizeStartFrame = frame; resizeStartPoint = g.location(in: sv)
        case .changed:
            let pt = g.location(in: sv)
            let dx = pt.x - resizeStartPoint.x, dy = pt.y - resizeStartPoint.y
            let w = min(max(220, resizeStartFrame.width  + dx), sv.bounds.width  - resizeStartFrame.minX)
            let h = min(max(300, resizeStartFrame.height + dy), sv.bounds.height - resizeStartFrame.minY)
            frame = CGRect(x: resizeStartFrame.minX, y: resizeStartFrame.minY, width: w, height: h)
        default: break
        }
    }

    // ── Actions ───────────────────────────────

    @objc private func backTap()  { onBack?()  }
    @objc private func closeTap() { onClose?() }

    @objc private func tapMode() {
        guard let point = points.first else {
            statusLabel.text = "CHƯA CÓ ĐIỂM"
            TPIOSLog.shared.log("TapPanel: manual tap rejected - no point")
            return
        }
        TPIOSLog.shared.log("TapPanel: manual tap point=\(point)")
        let ok = TPIOSAutoClickEngine.shared.tap(at: point)
        statusLabel.text = ok ? "TAPPED" : "TAP LỖI"
        TPIOSLog.shared.log("TapPanel: manual tap result=\(ok)")
    }

    @objc private func pointMode() {
        picker?.removeFromSuperview()
        // FIX: overlay must cover the FULL window, not self.bounds
        guard let window = TPIOSAutoClickEngine.appWindow() else { return }
        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.30)
        overlay.isUserInteractionEnabled = true

        // "tap anywhere" hint label
        let hint = UILabel(frame: CGRect(x: 0, y: overlay.bounds.midY - 20,
                                        width: overlay.bounds.width, height: 40))
        hint.text = "Chạm để chọn điểm"
        hint.textColor = .white
        hint.font = .boldSystemFont(ofSize: 17)
        hint.textAlignment = .center
        overlay.addSubview(hint)

        overlay.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(pickerTap(_:))))
        window.addSubview(overlay)
        picker = overlay
        isHidden = true
        TPIOSLog.shared.log("TapPanel: point picker opened (full window)")
    }

    @objc private func pickerTap(_ gesture: UITapGestureRecognizer) {
        // FIX: get location in window space directly
        guard let window = TPIOSAutoClickEngine.appWindow(),
              let overlay = picker else {
            TPIOSLog.shared.log("TapPanel: picker failed")
            return
        }
        let windowPoint = gesture.location(in: window)
        points = [windowPoint]
        addMarker(at: windowPoint)
        pointLabel.text = "POINT: 1"
        overlay.removeFromSuperview(); picker = nil; isHidden = false
        TPIOSLog.shared.log("TapPanel: point saved window=\(windowPoint)")
    }

    private func removeAllMarkers() {
        markers.forEach { $0.removeFromSuperview() }
        markers.removeAll()
        // Sweep ALL windows regardless of level — marker may be on a non-appWindow
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for w in scene.windows {
                // iterate copy to avoid mutation during iteration
                let subs = w.subviews
                for sub in subs where sub.tag == TPIOSAutoClickPanel.markerTag {
                    sub.removeFromSuperview()
                }
            }
        }
    }

    private func addMarker(at point: CGPoint) {
        removeAllMarkers()
        guard let window = TPIOSAutoClickEngine.appWindow() else { return }
        let marker = UIView(frame: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
        marker.tag = TPIOSAutoClickPanel.markerTag
        marker.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        marker.layer.cornerRadius = 12
        marker.layer.borderWidth = 2
        marker.layer.borderColor = UIColor.white.cgColor
        marker.isUserInteractionEnabled = true
        marker.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(moveMarker(_:))))
        window.addSubview(marker)
        markers.append(marker)
    }

    @objc private func moveMarker(_ gesture: UIPanGestureRecognizer) {
        guard let marker = gesture.view,
              let window = TPIOSAutoClickEngine.appWindow() else { return }
        let location = gesture.location(in: window)
        marker.center = location
        points = [location]
        TPIOSLog.shared.log("TapPanel: marker moved point=\(location)")
    }

    @objc private func clearPoints() {
        stop()
        points.removeAll()
        removeAllMarkers()
        pointLabel.text = "POINT: 0"; countLabel.text = "TAP: 0"; statusLabel.text = "IDLE"
        TPIOSLog.shared.log("TapPanel: points cleared")
    }

    @objc private func speedChanged() {
        speed = TimeInterval(speedSlider.value)
        speedLabel.text = String(format: "Tốc độ  %.2fs", speed)
        TPIOSLog.shared.log(String(format: "TapPanel: speed=%.2fs", speed))
    }

    @objc private func decreaseSpeed() {
        speed = max(0.05, (speed * 20).rounded() / 20 - 0.05)
        speedSlider.value = Float(speed); speedChanged()
    }

    @objc private func increaseSpeed() {
        speed = min(5.0, (speed * 20).rounded() / 20 + 0.05)
        speedSlider.value = Float(speed); speedChanged()
    }

    @objc private func startStop() {
        guard !points.isEmpty else {
            statusLabel.text = "CHƯA CÓ ĐIỂM"
            TPIOSLog.shared.log("TapPanel: auto start rejected - no point")
            return
        }
        if running {
            TPIOSLog.shared.log("TapPanel: auto stop requested")
            stop(); return
        }
        running = true; currentPointIndex = 0
        startButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
        statusLabel.text = "RUNNING"
        TPIOSLog.shared.log("TapPanel: auto START points=\(points.count) speed=\(speed)")
        performTap()
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        source.schedule(deadline: .now() + speed, repeating: speed, leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in self?.performTap() }
        source.resume(); timer = source
    }

    private func performTap() {
        guard running, !points.isEmpty else { return }
        let index = currentPointIndex % points.count
        let point = points[index]
        TPIOSLog.shared.log("TapPanel: performTap index=\(index) point=\(point)")
        let ok = TPIOSAutoClickEngine.shared.tap(at: point)
        if ok {
            tapCount += 1
            countLabel.text = "TAP: \(tapCount)"
            currentPointIndex = (currentPointIndex + 1) % points.count
            TPIOSLog.shared.log("TapPanel: performTap SUCCESS count=\(tapCount)")
        } else {
            TPIOSLog.shared.log("TapPanel: performTap FAILED")
        }
    }

    func stop() {
        running = false
        timer?.cancel(); timer = nil
        startButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        statusLabel.text = "STOPPED"
        TPIOSLog.shared.log("TapPanel: stopped")
    }

    /// Called when panel is removed — clean up any markers left on window
    func cleanupMarkers() {
        removeAllMarkers()
    }
}