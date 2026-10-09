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
        let size = CGSize(width: 240, height: 350)
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
    private var points: [CGPoint] = []
    private var markers: [UIView] = []
    private var timer: DispatchSourceTimer?
    private var tapCount = 0
    private var running = false
    private var speed: TimeInterval = 2.0
    private var picker: UIView?

    private let header = UIView()
    private let content = UIView()
    private let statusLabel = UILabel()
    private let countLabel = UILabel()
    private let pointLabel = UILabel()
    private let speedLabel = UILabel()
    private let speedSlider = UISlider()
    private let tapButton = UIButton(type: .system)
    private let pointButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)
    private let resizeHandle = UILabel()

    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func iconButton(_ button: UIButton, icon: String, colors: [UIColor], action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = icon
        button.showsTouchWhenHighlighted = true
        button.adjustsImageWhenHighlighted = true
        TPIOSPanelStyle.applyGradientFill(to: button, colors: colors, cornerRadius: 18)
        button.layer.cornerRadius = 18
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

        iconButton(tapButton, icon: "hand.tap.fill", colors: [UIColor(red: 0.95, green: 0.30, blue: 0.60, alpha: 1), UIColor(red: 0.55, green: 0.10, blue: 0.45, alpha: 1)], action: #selector(tapMode))
        iconButton(pointButton, icon: "scope", colors: [UIColor(red: 0.36, green: 0.71, blue: 1.00, alpha: 1), UIColor(red: 0.09, green: 0.39, blue: 0.80, alpha: 1)], action: #selector(pointMode))
        iconButton(clearButton, icon: "trash.fill", colors: [UIColor(red: 1.00, green: 0.35, blue: 0.27, alpha: 1), UIColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)], action: #selector(clearPoints))
        iconButton(startButton, icon: "play.fill", colors: [UIColor(red: 0.36, green: 0.88, blue: 0.55, alpha: 1), UIColor(red: 0.06, green: 0.52, blue: 0.33, alpha: 1)], action: #selector(startStop))

        let tapLabel = UILabel()
        let pointCaption = UILabel()
        let clearLabel = UILabel()
        let startLabel = UILabel()
        caption(tapLabel, text: "Chạm")
        caption(pointCaption, text: "Điểm")
        caption(clearLabel, text: "Xóa")
        caption(startLabel, text: "Bắt đầu")

        statusLabel.text = "IDLE"
        countLabel.text = "TAP: 0"
        pointLabel.text = "POINT: 0"
        for label in [statusLabel, countLabel, pointLabel] {
            label.textColor = UIColor.white.withAlphaComponent(0.82)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            content.addSubview(label)
        }

        speedLabel.text = "Tốc độ  2.0s"
        speedLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        speedLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        speedLabel.textAlignment = .center
        content.addSubview(speedLabel)

        speedSlider.minimumValue = 0.05
        speedSlider.maximumValue = 5.0
        speedSlider.value = Float(speed)
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
        content.addSubview(speedSlider)

        addSubview(content)

        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.42)
        resizeHandle.font = .systemFont(ofSize: 19, weight: .medium)
        resizeHandle.textAlignment = .center
        resizeHandle.isUserInteractionEnabled = true
        addSubview(resizeHandle)

        header.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(movePanel(_:))))
        resizeHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizePanel(_:))))
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let scale = min(bounds.width / 240, bounds.height / 350)
        let headerHeight = 66 * scale
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        content.frame = CGRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))

        let backSize = 34 * scale
        let closeSize = 34 * scale
        let side = 16 * scale
        if let back = header.subviews.first(where: { $0 is UIButton }) as? UIButton {
            back.frame = CGRect(x: side, y: 16 * scale, width: backSize, height: backSize)
        }
        if let close = header.subviews.compactMap({ $0 as? UIButton }).last {
            close.frame = CGRect(x: bounds.width - side - closeSize, y: 16 * scale, width: closeSize, height: closeSize)
        }
        if let title = header.viewWithTag(1001) as? UILabel {
            title.frame = CGRect(x: 56 * scale, y: 12 * scale, width: max(0, bounds.width - 112 * scale), height: 42 * scale)
            title.font = .systemFont(ofSize: max(12, 19 * scale), weight: .bold)
        }

        let sidePadding = 14 * scale
        let columnGap = 10 * scale
        let contentWidth = max(0, bounds.width - sidePadding * 2)
        let columnWidth = max(0, (contentWidth - columnGap * 2) / 3)
        let iconSize = min(columnWidth, 58 * scale)
        let iconInset = max(0, (columnWidth - iconSize) / 2)
        let labelHeight = 15 * scale
        let iconLabelGap = 3 * scale
        let rowHeight = iconSize + iconLabelGap + labelHeight
        let rowGap = 7 * scale
        let top = 10 * scale

        let buttons = [tapButton, pointButton, clearButton]
        let labels = content.subviews.compactMap { $0 as? UILabel }.filter { $0 !== statusLabel && $0 !== countLabel && $0 !== pointLabel && $0 !== speedLabel }
        for index in 0..<buttons.count {
            let x = sidePadding + CGFloat(index) * (columnWidth + columnGap) + iconInset
            buttons[index].frame = CGRect(x: x, y: top, width: iconSize, height: iconSize)
            buttons[index].layer.cornerRadius = iconSize * 0.28
            TPIOSPanelStyle.syncFrames(in: buttons[index])
            if index < labels.count {
                labels[index].frame = CGRect(x: sidePadding + CGFloat(index) * (columnWidth + columnGap), y: top + iconSize + iconLabelGap, width: columnWidth, height: labelHeight)
                labels[index].font = .systemFont(ofSize: max(8, 13 * scale), weight: .semibold)
            }
        }

        let secondY = top + rowHeight + rowGap
        let startIndex = 3
        startButton.frame = CGRect(x: sidePadding + iconInset, y: secondY, width: iconSize, height: iconSize)
        startButton.layer.cornerRadius = iconSize * 0.28
        TPIOSPanelStyle.syncFrames(in: startButton)
        if labels.count > startIndex {
            labels[startIndex].frame = CGRect(x: sidePadding, y: secondY + iconSize + iconLabelGap, width: columnWidth, height: labelHeight)
            labels[startIndex].font = .systemFont(ofSize: max(8, 13 * scale), weight: .semibold)
        }

        let infoY = secondY + rowHeight + 3 * scale
        statusLabel.frame = CGRect(x: sidePadding, y: infoY, width: bounds.width - sidePadding * 2, height: 15 * scale)
        countLabel.frame = CGRect(x: sidePadding, y: infoY + 16 * scale, width: (bounds.width - sidePadding * 2) / 2 - 4 * scale, height: 15 * scale)
        pointLabel.frame = CGRect(x: bounds.midX + 4 * scale, y: infoY + 16 * scale, width: (bounds.width - sidePadding * 2) / 2 - 4 * scale, height: 15 * scale)
        speedLabel.frame = CGRect(x: sidePadding, y: infoY + 35 * scale, width: bounds.width - sidePadding * 2, height: 15 * scale)
        speedLabel.font = .systemFont(ofSize: max(8, 11 * scale), weight: .semibold)
        speedSlider.frame = CGRect(x: sidePadding, y: infoY + 48 * scale, width: bounds.width - sidePadding * 2, height: 24 * scale)

        resizeHandle.frame = CGRect(x: bounds.width - 44 * scale, y: bounds.height - 44 * scale, width: 44 * scale, height: 44 * scale)
        resizeHandle.font = .systemFont(ofSize: 19 * scale, weight: .medium)
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
        switch gesture.state {
        case .began:
            resizeStartFrame = frame
            resizeStartPoint = gesture.location(in: superview)
        case .changed:
            let point = gesture.location(in: superview)
            let dx = point.x - resizeStartPoint.x
            let dy = point.y - resizeStartPoint.y
            let width = min(max(240, resizeStartFrame.width + dx), superview.bounds.width - resizeStartFrame.minX)
            let height = min(max(330, resizeStartFrame.height + dy), superview.bounds.height - resizeStartFrame.minY)
            frame = CGRect(x: resizeStartFrame.minX, y: resizeStartFrame.minY, width: width, height: height)
        default:
            break
        }
    }

    @objc private func backTap() { onBack?() }
    @objc private func closeTap() { onClose?() }

    @objc private func tapMode() {
        guard let point = points.first else {
            statusLabel.text = "CHƯA CÓ ĐIỂM"
            return
        }
        if TPIOSAutoClickEngine.shared.tap(at: point) {
            tapCount += 1
            countLabel.text = "TAP: \(tapCount)"
            statusLabel.text = "ĐÃ CHẠM"
        } else {
            statusLabel.text = "CHẠM LỖI"
        }
    }

    @objc private func pointMode() {
        statusLabel.text = "CHỌN ĐIỂM"
        showPicker()
    }

    @objc private func clearPoints() {
        stop()
        points.removeAll()
        markers.forEach { $0.removeFromSuperview() }
        markers.removeAll()
        tapCount = 0
        countLabel.text = "TAP: 0"
        pointLabel.text = "POINT: 0"
        statusLabel.text = "ĐÃ XÓA"
    }

    @objc private func speedChanged() {
        speed = TimeInterval(speedSlider.value)
        speedLabel.text = String(format: "Tốc độ  %.2fs", speed)
        statusLabel.text = String(format: "TỐC ĐỘ %.2fs", speed)
        if running { restartTimer() }
    }

    @objc private func startStop() {
        if running {
            stop()
            statusLabel.text = "ĐÃ DỪNG"
            return
        }
        guard !points.isEmpty else {
            statusLabel.text = "CHƯA CÓ ĐIỂM"
            return
        }
        running = true
        statusLabel.text = "ĐANG CHẠM"
        startButton.setImage(UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
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
        startButton.setImage(UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
    }

    private func performTap() {
        guard !points.isEmpty else {
            stop()
            return
        }
        if TPIOSAutoClickEngine.shared.tap(at: points[0]) {
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

        let done = UIButton(type: .system)
        done.setTitle("Xong", for: .normal)
        done.setTitleColor(.white, for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        TPIOSPanelStyle.applyGradientFill(to: done, colors: [.systemBlue, .systemIndigo], cornerRadius: 18)
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
        statusLabel.text = "ĐÃ CHỌN \(points.count)"
    }

    @objc private func closePicker() {
        picker?.removeFromSuperview()
        picker = nil
        statusLabel.text = points.isEmpty ? "CHƯA CÓ ĐIỂM" : "POINT READY"
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
        statusLabel.text = "ĐÃ DI CHUYỂN"
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