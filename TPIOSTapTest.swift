import UIKit
import Foundation
import Darwin

final class TPIOSTapTest {
    static let shared = TPIOSTapTest()
    var onFinish: (() -> Void)?
    private var panel: TPIOSAutoClickPanel?

    private init() {}

    func start() {
        guard panel == nil, let window = TPIOSAutoClickEngine.appWindow() else { return }
        let size = CGSize(width: min(320, window.bounds.width - 24), height: min(500, window.bounds.height - 80))
        let frame = CGRect(x: (window.bounds.width - size.width) / 2, y: (window.bounds.height - size.height) / 2, width: size.width, height: size.height)
        let p = TPIOSAutoClickPanel(frame: frame)
        p.onBack = { [weak self] in self?.finish() }
        p.onClose = { [weak self] in self?.finish() }
        window.addSubview(p)
        panel = p
    }

    private func finish() {
        panel?.stop()
        panel?.removeFromSuperview()
        panel = nil
        onFinish?()
    }
}

final class TPIOSAutoClickPanel: UIView {
    private enum Mode { case tap, sequence }
    private var mode: Mode = .tap
    private var points: [CGPoint] = []
    private var markers: [UIView] = []
    private var timer: DispatchSourceTimer?
    private var sequenceIndex = 0
    private var tapCount = 0
    private var running = false
    private var speed: TimeInterval = 2.0
    private var picker: UIView?
    private let header = UIView()
    private let content = UIView()
    private let statusLabel = UILabel()
    private let countLabel = UILabel()
    private let pointLabel = UILabel()
    private let speedSlider = UISlider()
    private let startButton = UIButton(type: .system)
    private let resizeHandle = UIView()
    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func button(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        TPIOSPanelStyle.applyGradientFill(to: b, colors: [.systemBlue, .systemIndigo], cornerRadius: 12)
        return b
    }

    private func setup() {
        layer.cornerRadius = 18
        clipsToBounds = true
        TPIOSPanelStyle.applyGlassBackground(to: self)

        addSubview(header)
        let back = button("‹")
        back.frame = CGRect(x: 8, y: 6, width: 40, height: 32)
        back.addTarget(self, action: #selector(backTap), for: .touchUpInside)
        header.addSubview(back)

        let title = UILabel()
        title.text = "AUTO CLICKER"
        title.textColor = .white
        title.font = .systemFont(ofSize: 15, weight: .bold)
        title.textAlignment = .center
        title.tag = 1001
        header.addSubview(title)

        let close = button("×")
        close.addTarget(self, action: #selector(closeTap), for: .touchUpInside)
        header.addSubview(close)
        close.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            close.topAnchor.constraint(equalTo: header.topAnchor, constant: 6),
            close.widthAnchor.constraint(equalToConstant: 40),
            close.heightAnchor.constraint(equalToConstant: 32)
        ])

        let tap = button("TAP")
        tap.addTarget(self, action: #selector(tapMode), for: .touchUpInside)
        let seq = button("SEQ")
        seq.addTarget(self, action: #selector(seqMode), for: .touchUpInside)
        let point = button("POINT")
        point.addTarget(self, action: #selector(pointMode), for: .touchUpInside)
        let clear = button("CLEAR")
        clear.addTarget(self, action: #selector(clearPoints), for: .touchUpInside)
        [tap, seq, point, clear].enumerated().forEach { i, b in
            b.frame = CGRect(x: 12 + CGFloat(i) * 66, y: 10, width: 60, height: 36)
            content.addSubview(b)
        }

        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.text = "IDLE"
        countLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 13)
        countLabel.text = "TAP: 0"
        pointLabel.textColor = .white
        pointLabel.font = .systemFont(ofSize: 13)
        pointLabel.text = "POINT: 0"
        [statusLabel, countLabel, pointLabel].enumerated().forEach { i, label in
            label.frame = CGRect(x: 14, y: 60 + CGFloat(i) * 24, width: 240, height: 20)
            content.addSubview(label)
        }

        speedSlider.minimumValue = 0.05
        speedSlider.maximumValue = 5.0
        speedSlider.value = Float(speed)
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
        content.addSubview(speedSlider)

        startButton.setTitle("START", for: .normal)
        startButton.setTitleColor(.white, for: .normal)
        TPIOSPanelStyle.applyGradientFill(to: startButton, colors: [.systemBlue, .systemIndigo], cornerRadius: 12)
        startButton.addTarget(self, action: #selector(startStop), for: .touchUpInside)
        content.addSubview(startButton)

        resizeHandle.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        resizeHandle.layer.cornerRadius = 4
        addSubview(resizeHandle)
        addSubview(content)

        header.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(movePanel(_:))))
        resizeHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizePanel(_:))))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 44)
        if let title = viewWithTag(1001) as? UILabel {
            title.frame = CGRect(x: 52, y: 6, width: bounds.width - 104, height: 32)
        }
        content.frame = CGRect(x: 0, y: 44, width: bounds.width, height: bounds.height - 44)
        speedSlider.frame = CGRect(x: 14, y: 138, width: bounds.width - 28, height: 30)
        startButton.frame = CGRect(x: 14, y: 180, width: bounds.width - 28, height: 42)
        resizeHandle.frame = CGRect(x: bounds.width - 20, y: bounds.height - 20, width: 14, height: 14)
        TPIOSPanelStyle.syncFrames(in: self)
    }

    @objc private func movePanel(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let translation = gesture.translation(in: superview)
        center.x += translation.x
        center.y += translation.y
        gesture.setTranslation(.zero, in: superview)
        center.x = min(max(center.x, bounds.width / 2), superview.bounds.width - bounds.width / 2)
        center.y = min(max(center.y, bounds.height / 2), superview.bounds.height - bounds.height / 2)
    }

    @objc private func resizePanel(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let translation = gesture.translation(in: superview)
        let width = min(max(260, bounds.width + translation.x), superview.bounds.width - frame.minX)
        let height = min(max(360, bounds.height + translation.y), superview.bounds.height - frame.minY)
        frame.size = CGSize(width: width, height: height)
        gesture.setTranslation(.zero, in: superview)
    }

    @objc private func backTap() { onBack?() }
    @objc private func closeTap() { onClose?() }
    @objc private func tapMode() { mode = .tap; sequenceIndex = 0 }
    @objc private func seqMode() { mode = .sequence; sequenceIndex = 0 }
    @objc private func pointMode() { showPicker() }
    @objc private func clearPoints() {
        points.removeAll()
        markers.forEach { $0.removeFromSuperview() }
        markers.removeAll()
        pointLabel.text = "POINT: 0"
    }
    @objc private func speedChanged() {
        speed = TimeInterval(speedSlider.value)
        if running { restartTimer() }
    }

    @objc private func startStop() {
        if running { stop(); return }
        guard !points.isEmpty else { return }
        running = true
        statusLabel.text = "RUNNING"
        startButton.setTitle("STOP", for: .normal)
        restartTimer()
    }

    private func restartTimer() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + speed, repeating: speed, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.performTap() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        running = false
        statusLabel.text = "IDLE"
        startButton.setTitle("START", for: .normal)
    }

    private func performTap() {
        guard !points.isEmpty else { return }
        let point: CGPoint
        switch mode {
        case .tap:
            point = points[0]
        case .sequence:
            point = points[sequenceIndex % points.count]
            sequenceIndex += 1
        }
        if TPIOSAutoClickEngine.shared.tap(at: point) {
            tapCount += 1
            countLabel.text = "TAP: \(tapCount)"
        }
    }

    private func showPicker() {
        guard let window = TPIOSAutoClickEngine.appWindow(), picker == nil else { return }
        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        let label = UILabel(frame: CGRect(x: 20, y: 70, width: window.bounds.width - 40, height: 40))
        label.text = "Chạm màn hình để thêm điểm"
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        overlay.addSubview(label)
        let done = button("Xong")
        done.frame = CGRect(x: window.bounds.width - 90, y: 70, width: 70, height: 36)
        done.addTarget(self, action: #selector(closePicker), for: .touchUpInside)
        overlay.addSubview(done)
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickerTap(_:))))
        window.addSubview(overlay)
        picker = overlay
    }

    @objc private func pickerTap(_ gesture: UITapGestureRecognizer) {
        guard let window = picker?.superview else { return }
        let point = gesture.location(in: window)
        guard point.y >= 120 else { return }
        points.append(point)
        addMarker(at: point)
        pointLabel.text = "POINT: \(points.count)"
    }

    @objc private func closePicker() {
        picker?.removeFromSuperview()
        picker = nil
    }

    private func addMarker(at point: CGPoint) {
        guard let window = picker?.superview else { return }
        let marker = UILabel(frame: CGRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32))
        marker.text = "\(points.count)"
        marker.textAlignment = .center
        marker.textColor = .white
        marker.backgroundColor = .black.withAlphaComponent(0.65)
        marker.layer.cornerRadius = 16
        marker.clipsToBounds = true
        marker.isUserInteractionEnabled = true
        marker.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(moveMarker(_:))))
        window.addSubview(marker)
        markers.append(marker)
    }

    @objc private func moveMarker(_ gesture: UIPanGestureRecognizer) {
        guard let marker = gesture.view, let window = marker.superview, let index = markers.firstIndex(of: marker) else { return }
        let translation = gesture.translation(in: window)
        marker.center.x += translation.x
        marker.center.y += translation.y
        points[index] = marker.center
        gesture.setTranslation(.zero, in: window)
    }
}

final class TPIOSAutoClickEngine {
    static let shared = TPIOSAutoClickEngine()
    private init() {}

    private typealias CreateDigitizer = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32, Double, Double, Double, Double, Double, DarwinBoolean, DarwinBoolean, UInt32) -> OpaquePointer?
    private typealias CreateFinger = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, Double, Double, Double, Double, Double, DarwinBoolean, DarwinBoolean, UInt32) -> OpaquePointer?
    private typealias CreateClient = @convention(c) (CFAllocator?, UInt32) -> OpaquePointer?
    private typealias Append = @convention(c) (OpaquePointer, OpaquePointer, UInt32) -> Void
    private typealias SetInteger = @convention(c) (OpaquePointer, UInt32, Int64) -> Void
    private typealias SetSender = @convention(c) (OpaquePointer, UInt64) -> Void
    private typealias Dispatch = @convention(c) (OpaquePointer, OpaquePointer) -> Void
    private typealias SetDigitizerInfo = @convention(c) (OpaquePointer, UInt32, DarwinBoolean, DarwinBoolean, UnsafeMutableRawPointer?, UInt32, UInt32) -> Void

    private var handle: UnsafeMutableRawPointer?
    private var client: OpaquePointer?
    private var createDigitizer: CreateDigitizer?
    private var createFinger: CreateFinger?
    private var createClient: CreateClient?
    private var append: Append?
    private var setInteger: SetInteger?
    private var setSender: SetSender?
    private var dispatch: Dispatch?
    private var setInfo: SetDigitizerInfo?
    private var prepared = false
    private let lock = NSLock()

    private let range: UInt32 = 1 << 0
    private let touch: UInt32 = 1 << 1
    private let identity: UInt32 = 1 << 5
    private let displayIntegrated: UInt32 = (11 << 16) + 25
    private let senderID: UInt64 = 0x8000000817319375

    func tap(at point: CGPoint) -> Bool {
        guard prepare(), let client, let window = Self.appWindow() else { return false }
        let x = max(0, min(Double(window.bounds.width), Double(point.x)))
        let y = max(0, min(Double(window.bounds.height), Double(point.y)))
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
        return true
    }

    private func prepare() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if prepared { return client != nil && dispatch != nil }
        prepared = true
        guard let h = dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_NOW) else { return false }
        handle = h

        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let pointer = dlsym(h, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        createDigitizer = sym("IOHIDEventCreateDigitizerEvent", CreateDigitizer.self)
        createFinger = sym("IOHIDEventCreateDigitizerFingerEvent", CreateFinger.self)
        createClient = sym("IOHIDEventSystemClientCreate", CreateClient.self)
        append = sym("IOHIDEventAppendEvent", Append.self)
        setInteger = sym("IOHIDEventSetIntegerValue", SetInteger.self)
        setSender = sym("IOHIDEventSetSenderID", SetSender.self)
        dispatch = sym("IOHIDEventSystemClientDispatchEvent", Dispatch.self)
        setInfo = sym("BKSHIDEventSetDigitizerInfo", SetDigitizerInfo.self)

        guard let createClient, let createdClient = createClient(nil, 0) else { return false }
        client = createdClient
        return createDigitizer != nil && createFinger != nil && append != nil && dispatch != nil
    }

    static func appWindow() -> UIWindow? {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var windows: [UIWindow] = []
        for scene in scenes {
            windows.append(contentsOf: scene.windows)
        }
        for window in windows {
            let className = NSStringFromClass(type(of: window))
            if !window.isHidden && window.alpha > 0 && window.windowLevel == .normal && window.rootViewController != nil && !className.contains("TPIOS") {
                return window
            }
        }
        return nil
    }
}
