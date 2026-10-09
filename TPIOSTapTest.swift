import UIKit
import Foundation
import Darwin

// Auto Clicker / Touch
// Chỉ giữ các chức năng cần thiết: TAP, SEQ, POINT, CLEAR, SPEED, START/STOP.
final class TPIOSTapTest: NSObject {
    static let shared = TPIOSTapTest()
    var onFinish: (() -> Void)?
    private var panel: TPIOSAutoClickPanel?

    func start() {
        stop()
        guard let window = keyWindow() else { onFinish?(); return }
        let width = min(320, max(280, window.bounds.width - 24))
        let height = min(max(410, window.bounds.height - 80), 500)
        let frame = CGRect(
            x: max(12, (window.bounds.width - width) / 2),
            y: max(20, (window.bounds.height - height) / 2),
            width: width,
            height: height
        )
        let view = TPIOSAutoClickPanel(frame: frame)
        view.onBack = { [weak self] in self?.finish() }
        view.onClose = { [weak self] in self?.finish() }
        window.addSubview(view)
        window.bringSubviewToFront(view)
        panel = view
    }

    func stop() {
        panel?.stop()
        panel?.removeFromSuperview()
        panel = nil
    }

    private func finish() {
        stop()
        onFinish?()
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}

private final class TPIOSAutoClickPanel: UIView {
    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private enum Mode { case tap, sequence }
    private struct Point { var location: CGPoint; var marker: UIView }

    private let header = UIView()
    private let back = UIButton(type: .system)
    private let close = UIButton(type: .system)
    private let title = UILabel()
    private let tap = UIButton(type: .system)
    private let seq = UIButton(type: .system)
    private let point = UIButton(type: .system)
    private let clear = UIButton(type: .system)
    private let tapLabel = UILabel()
    private let seqLabel = UILabel()
    private let pointLabel = UILabel()
    private let clearLabel = UILabel()
    private let start = UIButton(type: .system)
    private let speedTitle = UILabel()
    private let speedValue = UILabel()
    private let slider = UISlider()
    private let status = UILabel()
    private let resize = UILabel()

    private var mode: Mode = .tap
    private var points: [Point] = []
    private var picker: UIView?
    private var timer: DispatchSourceTimer?
    private var running = false
    private var speed = 2.0
    private var tapCount = 0
    private var sequenceIndex = 0
    private var resizeFrame = CGRect.zero
    private var resizePoint = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        TPIOSPanelStyle.applyGlassBackground(to: self, cornerRadius: 24)
        header.backgroundColor = UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1)
        header.layer.cornerRadius = 24
        header.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(header)

        back.setTitle("‹", for: .normal)
        back.setTitleColor(.white, for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 30)
        back.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        header.addSubview(back)

        title.text = "CHẠM"
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textAlignment = .center
        header.addSubview(title)

        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = .white
        close.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        close.layer.cornerRadius = 17
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        header.addSubview(close)

        configure(tap, "hand.tap.fill", [UIColor(red: 0.25, green: 0.62, blue: 1, alpha: 1), UIColor(red: 0.08, green: 0.30, blue: 0.82, alpha: 1)], #selector(tapTapped))
        configure(seq, "arrow.right.to.line.compact", [UIColor(red: 0.68, green: 0.47, blue: 1, alpha: 1), UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)], #selector(seqTapped))
        configure(point, "plus", [UIColor(red: 1, green: 0.65, blue: 0.25, alpha: 1), UIColor(red: 0.85, green: 0.25, blue: 0.08, alpha: 1)], #selector(pointTapped))
        configure(clear, "trash.fill", [UIColor(red: 1, green: 0.35, blue: 0.27, alpha: 1), UIColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)], #selector(clearTapped))
        caption(tapLabel, "TAP")
        caption(seqLabel, "SEQ")
        caption(pointLabel, "POINT")
        caption(clearLabel, "CLEAR")
        [tap, seq, point, clear].forEach(addSubview)
        [tapLabel, seqLabel, pointLabel, clearLabel].forEach(addSubview)

        start.setImage(UIImage(systemName: "play.fill"), for: .normal)
        start.setTitle(" START", for: .normal)
        start.setTitleColor(.white, for: .normal)
        start.tintColor = .white
        start.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        start.layer.cornerRadius = 16
        start.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        addSubview(start)
        startStyle()

        speedTitle.text = "SPEED"
        speedTitle.textColor = UIColor.white.withAlphaComponent(0.72)
        speedTitle.font = .systemFont(ofSize: 12, weight: .bold)
        addSubview(speedTitle)

        speedValue.textColor = UIColor(red: 0.28, green: 0.65, blue: 1, alpha: 1)
        speedValue.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        speedValue.textAlignment = .right
        addSubview(speedValue)

        slider.minimumValue = 0.05
        slider.maximumValue = 5
        slider.value = Float(speed)
        slider.minimumTrackTintColor = UIColor(red: 0.22, green: 0.60, blue: 1, alpha: 1)
        slider.addTarget(self, action: #selector(speedChanged(_:)), for: .valueChanged)
        addSubview(slider)
        updateSpeed()

        status.textColor = UIColor.white.withAlphaComponent(0.88)
        status.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        status.layer.cornerRadius = 12
        status.textAlignment = .center
        status.font = .systemFont(ofSize: 12, weight: .semibold)
        status.adjustsFontSizeToFitWidth = true
        status.minimumScaleFactor = 0.65
        addSubview(status)

        resize.text = "↘"
        resize.textColor = UIColor.white.withAlphaComponent(0.45)
        resize.textAlignment = .center
        resize.isUserInteractionEnabled = true
        addSubview(resize)
        resize.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizePanned(_:))))

        header.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(movePanned(_:))))
        updateMode()
        updateStatus()
    }

    private func configure(_ button: UIButton, _ icon: String, _ colors: [UIColor], _ action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.tintColor = .white
        TPIOSPanelStyle.applyGradientFill(to: button, colors: colors, cornerRadius: 18)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func caption(_ label: UILabel, _ text: String) {
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 54)
        back.frame = CGRect(x: 3, y: 3, width: 40, height: 42)
        title.frame = CGRect(x: 45, y: 0, width: max(0, bounds.width - 90), height: 54)
        close.frame = CGRect(x: bounds.width - 46, y: 7, width: 36, height: 36)

        let side: CGFloat = 14
        let gap: CGFloat = 10
        let width = bounds.width - side * 2
        let col = (width - gap * 3) / 4
        let icon = min(58, col)
        let y = CGFloat(68)
        let buttons = [tap, seq, point, clear]
        let labels = [tapLabel, seqLabel, pointLabel, clearLabel]
        for i in 0..<4 {
            let x = side + CGFloat(i) * (col + gap) + max(0, (col - icon) / 2)
            buttons[i].frame = CGRect(x: x, y: y, width: icon, height: icon)
            buttons[i].layer.cornerRadius = icon * 0.28
            TPIOSPanelStyle.syncFrames(in: buttons[i])
            labels[i].frame = CGRect(x: side + CGFloat(i) * (col + gap), y: y + icon + 5, width: col, height: 16)
        }

        let actionY = y + icon + 34
        start.frame = CGRect(x: side, y: actionY, width: width, height: 54)
        TPIOSPanelStyle.syncFrames(in: start)
        speedTitle.frame = CGRect(x: side, y: actionY + 70, width: 70, height: 18)
        speedValue.frame = CGRect(x: bounds.width - side - 82, y: actionY + 70, width: 82, height: 18)
        slider.frame = CGRect(x: side, y: actionY + 93, width: width, height: 28)
        status.frame = CGRect(x: side, y: bounds.height - 52, width: width, height: 38)
        resize.frame = CGRect(x: bounds.width - 32, y: bounds.height - 32, width: 32, height: 32)
    }

    @objc private func tapTapped() { guard !running else { return }; mode = .tap; updateMode() }
    @objc private func seqTapped() { guard !running else { return }; mode = .sequence; updateMode() }
    @objc private func pointTapped() { guard !running else { return }; beginPicker() }
    @objc private func clearTapped() {
        guard !running else { return }
        points.forEach { $0.marker.removeFromSuperview() }
        points.removeAll()
        tapCount = 0
        sequenceIndex = 0
        updateStatus()
    }

    @objc private func startTapped() {
        if running { stop(); return }
        guard !points.isEmpty else { status.text = "● CHƯA CÓ ĐIỂM — bấm POINT"; return }
        running = true
        tapCount = 0
        sequenceIndex = 0
        startStyle()
        performTap()
        scheduleTimer()
        updateStatus()
    }

    @objc private func speedChanged(_ sender: UISlider) {
        speed = Double(sender.value)
        updateSpeed()
        if running { scheduleTimer() }
    }

    private func scheduleTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + speed, repeating: speed, leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in self?.performTap() }
        source.resume()
        timer = source
    }

    private func performTap() {
        guard running, !points.isEmpty else { return }
        let target: CGPoint
        switch mode {
        case .tap: target = points[0].location
        case .sequence:
            target = points[sequenceIndex % points.count].location
            sequenceIndex = (sequenceIndex + 1) % points.count
        }
        if TPIOSAutoClickEngine.shared.tap(at: target) { tapCount += 1 }
        updateStatus()
    }

    func stop() {
        running = false
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        picker?.removeFromSuperview()
        picker = nil
        startStyle()
        updateStatus()
    }

    private func startStyle() {
        if running {
            start.setImage(UIImage(systemName: "stop.fill"), for: .normal)
            start.setTitle(" STOP", for: .normal)
            TPIOSPanelStyle.applyGradientFill(to: start, colors: [UIColor(red: 1, green: 0.35, blue: 0.27, alpha: 1), UIColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)], cornerRadius: 16)
        } else {
            start.setImage(UIImage(systemName: "play.fill"), for: .normal)
            start.setTitle(" START", for: .normal)
            TPIOSPanelStyle.applyGradientFill(to: start, colors: [UIColor(red: 0.20, green: 0.65, blue: 1, alpha: 1), UIColor(red: 0.06, green: 0.36, blue: 0.92, alpha: 1)], cornerRadius: 16)
        }
        start.tintColor = .white
    }

    private func updateMode() {
        tap.layer.borderWidth = mode == .tap ? 2 : 1
        seq.layer.borderWidth = mode == .sequence ? 2 : 1
        tap.layer.borderColor = (mode == .tap ? UIColor.white : UIColor.white.withAlphaComponent(0.28)).cgColor
        seq.layer.borderColor = (mode == .sequence ? UIColor.white : UIColor.white.withAlphaComponent(0.28)).cgColor
    }

    private func updateSpeed() { speedValue.text = String(format: "%.3fs", speed) }
    private func updateStatus() {
        status.text = "\(running ? "● RUNNING" : "● IDLE")     \(tapCount) taps     \(points.count) pts"
    }

    // MARK: Point picker

    private func beginPicker() {
        picker?.removeFromSuperview()
        guard let host = window else { return }
        let overlay = UIView(frame: host.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.01)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let hint = UILabel(frame: CGRect(x: 16, y: host.safeAreaInsets.top + 10, width: host.bounds.width - 112, height: 40))
        hint.text = "Chạm màn hình để thêm điểm"
        hint.textColor = .white
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        hint.textAlignment = .center
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.layer.cornerRadius = 12
        hint.clipsToBounds = true
        overlay.addSubview(hint)

        let done = UIButton(type: .system)
        done.frame = CGRect(x: host.bounds.width - 88, y: host.safeAreaInsets.top + 10, width: 68, height: 40)
        done.setTitle("Xong", for: .normal)
        done.setTitleColor(.white, for: .normal)
        done.backgroundColor = UIColor(red: 0.20, green: 0.65, blue: 1, alpha: 1)
        done.layer.cornerRadius = 12
        done.addTarget(self, action: #selector(donePicker), for: .touchUpInside)
        overlay.addSubview(done)

        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickerTapped(_:))))
        host.addSubview(overlay)
        host.bringSubviewToFront(overlay)
        picker = overlay
    }

    @objc private func pickerTapped(_ gesture: UITapGestureRecognizer) {
        guard let overlay = picker else { return }
        let p = gesture.location(in: overlay)
        if p.y < 60 && p.x > overlay.bounds.width - 110 { return }
        addPoint(p)
    }

    @objc private func donePicker() {
        picker?.removeFromSuperview()
        picker = nil
    }

    private func addPoint(_ p: CGPoint) {
        guard let host = window else { return }
        let n = points.count + 1
        let size: CGFloat = 30
        let marker = UIView(frame: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
        marker.backgroundColor = UIColor(red: 0.20, green: 0.65, blue: 1, alpha: 1)
        marker.layer.cornerRadius = size / 2
        marker.layer.borderWidth = 2
        marker.layer.borderColor = UIColor.white.cgColor
        marker.isUserInteractionEnabled = true
        let label = UILabel(frame: marker.bounds)
        label.text = "\(n)"
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textAlignment = .center
        marker.addSubview(label)
        marker.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(markerPanned(_:))))
        host.addSubview(marker)
        host.bringSubviewToFront(marker)
        points.append(Point(location: p, marker: marker))
        updateStatus()
    }

    @objc private func markerPanned(_ gesture: UIPanGestureRecognizer) {
        guard let marker = gesture.view,
              let index = points.firstIndex(where: { $0.marker === marker }),
              let host = window else { return }
        let p = gesture.location(in: host)
        let r = marker.bounds.width / 2
        let x = max(r, min(p.x, host.bounds.width - r))
        let y = max(r, min(p.y, host.bounds.height - r))
        let location = CGPoint(x: x, y: y)
        marker.center = location
        points[index].location = location
    }

    // MARK: Move / resize

    @objc private func movePanned(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview, gesture.state == .began || gesture.state == .changed else { return }
        let d = gesture.translation(in: parent)
        var f = frame
        f.origin.x = max(0, min(f.origin.x + d.x, max(0, parent.bounds.width - f.width)))
        f.origin.y = max(0, min(f.origin.y + d.y, max(0, parent.bounds.height - f.height)))
        frame = f
        gesture.setTranslation(.zero, in: parent)
    }

    @objc private func resizePanned(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else { return }
        switch gesture.state {
        case .began:
            resizeFrame = frame
            resizePoint = gesture.location(in: parent)
        case .changed:
            let p = gesture.location(in: parent)
            let w = max(270, min(resizeFrame.width + p.x - resizePoint.x, parent.bounds.width - resizeFrame.origin.x))
            let h = max(390, min(resizeFrame.height + p.y - resizePoint.y, parent.bounds.height - resizeFrame.origin.y))
            frame = CGRect(x: resizeFrame.origin.x, y: resizeFrame.origin.y, width: w, height: h)
        default: break
        }
    }

    @objc private func backTapped() { onBack?() }
    @objc private func closeTapped() { onClose?() }
}

// MARK: IOHID touch engine

private final class TPIOSAutoClickEngine {
    static let shared = TPIOSAutoClickEngine()

    private typealias CreateDigitizer = @convention(c) (
        UnsafeRawPointer?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32,
        Double, Double, Double, Double, Double, DarwinBoolean, DarwinBoolean, UInt32
    ) -> OpaquePointer?
    private typealias CreateFinger = @convention(c) (
        UnsafeRawPointer?, UInt64, UInt32, UInt32, UInt32,
        Double, Double, Double, Double, Double, DarwinBoolean, DarwinBoolean, UInt32
    ) -> OpaquePointer?
    private typealias CreateClient = @convention(c) (UnsafeRawPointer?) -> OpaquePointer?
    private typealias Append = @convention(c) (OpaquePointer, OpaquePointer, UInt32) -> Void
    private typealias SetInteger = @convention(c) (OpaquePointer, UInt32, Int64) -> Void
    private typealias SetSender = @convention(c) (OpaquePointer, UInt64) -> Void
    private typealias Dispatch = @convention(c) (OpaquePointer, OpaquePointer) -> Void
    private typealias SetDigitizerInfo = @convention(c) (
        OpaquePointer, UInt32, DarwinBoolean, DarwinBoolean, CFString?, CFTimeInterval, Float
    ) -> Void

    private var createDigitizer: CreateDigitizer?
    private var createFinger: CreateFinger?
    private var createClient: CreateClient?
    private var append: Append?
    private var setInteger: SetInteger?
    private var setSender: SetSender?
    private var dispatch: Dispatch?
    private var setInfo: SetDigitizerInfo?
    private var client: OpaquePointer?
    private var prepared = false
    private let lock = NSLock()

    private let range: UInt32 = 1 << 0
    private let touch: UInt32 = 1 << 1
    private let identity: UInt32 = 1 << 5
    private let displayIntegrated: UInt32 = (11 << 16) + 25
    private let senderID: UInt64 = 0x8000000817319375

    private init() {}

    func tap(at point: CGPoint) -> Bool {
        guard prepare(), let client, let window = appWindow() else { return false }
        let w = max(window.bounds.width, 1)
        let h = max(window.bounds.height, 1)
        let x = max(0, min(1, Double(point.x / w)))
        let y = max(0, min(1, Double(point.y / h)))
        guard send(client, window, x, y, true) else { return false }
        usleep(2000)
        return send(client, window, x, y, false)
    }

    private func send(_ client: OpaquePointer, _ window: UIWindow, _ x: Double, _ y: Double, _ touching: Bool) -> Bool {
        let mask = touching ? (touch | identity) : (range | touch | identity)
        guard let parent = createDigitizer?(nil, mach_absolute_time(), 3, 0, 0, mask, 0, 0, 0, 0, 0, 0, DarwinBoolean(false), DarwinBoolean(touching), 0),
              let child = createFinger?(nil, mach_absolute_time(), 1, 2, range | touch, x, y, 0, 0, 0, DarwinBoolean(touching), DarwinBoolean(touching), 0),
              let append,
              let dispatch else { return false }

        setInteger?(parent, displayIntegrated, 1)
        setSender?(parent, senderID)
        append(parent, child, 0)

        if let setInfo {
            let context = (window.value(forKey: "_contextId") as? NSNumber)?.uint32Value ?? 0
            setInfo(parent, context, DarwinBoolean(false), DarwinBoolean(false), nil, 0, 0)
        }
        dispatch(client, parent)
        CFRelease(child)
        CFRelease(parent)
        return true
    }

    private func prepare() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if prepared { return client != nil && dispatch != nil }
        prepared = true

        guard let ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_GLOBAL)
                ?? dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_GLOBAL) else { return false }

        createDigitizer = load("IOHIDEventCreateDigitizerEvent", ioKit)
        createFinger = load("IOHIDEventCreateDigitizerFingerEvent", ioKit)
        createClient = load("IOHIDEventSystemClientCreate", ioKit)
        append = load("IOHIDEventAppendEvent", ioKit)
        setInteger = load("IOHIDEventSetIntegerValue", ioKit)
        setSender = load("IOHIDEventSetSenderID", ioKit)
        dispatch = load("IOHIDEventSystemClientDispatchEvent", ioKit)

        if let bks = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW | RTLD_GLOBAL) {
            setInfo = load("BKSHIDEventSetDigitizerInfo", bks)
        }
        client = createClient?(nil)
        return createDigitizer != nil && createFinger != nil && append != nil && setInteger != nil && setSender != nil && dispatch != nil && client != nil
    }

    private func load<T>(_ name: String, _ handle: UnsafeMutableRawPointer) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    private func appWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { !$0.isHidden && $0.rootViewController != nil && !NSStringFromClass(type(of: $0)).contains("TPIOS") }
            .first(where: { $0.windowLevel == .normal })
    }
}
