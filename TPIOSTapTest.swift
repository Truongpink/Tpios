import UIKit
import Foundation
import Darwin

// Auto Clicker / Touch: thay thế hoàn toàn chức năng "Chạm thử" cũ.
// Phạm vi hiện tại: TAP, SEQ (1→N), POINT, CLEAR, SPEED, START/STOP.
final class TPIOSTapTest: NSObject {

    static let shared = TPIOSTapTest()
    var onFinish: (() -> Void)?
    private var menu: TPIOSAutoClickMenu?

    func start() {
        stop()
        guard let host = keyWindow() else {
            onFinish?()
            return
        }

        let width = min(320, max(280, host.bounds.width - 24))
        let height = min(max(420, host.bounds.height - 80), 500)
        let frame = CGRect(
            x: max(12, (host.bounds.width - width) / 2),
            y: max(24, (host.bounds.height - height) / 2),
            width: width,
            height: height
        )
        let panel = TPIOSAutoClickMenu(frame: frame)
        panel.onClose = { [weak self] in
            self?.stop()
            self?.onFinish?()
        }
        panel.onBack = { [weak self] in
            self?.stop()
            self?.onFinish?()
        }
        host.addSubview(panel)
        host.bringSubviewToFront(panel)
        menu = panel
    }

    func stop() {
        menu?.stop()
        menu?.removeFromSuperview()
        menu = nil
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}

private final class TPIOSAutoClickMenu: UIView, UIGestureRecognizerDelegate {

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private enum Mode { case tap, sequence }
    private struct Point {
        var location: CGPoint
        var marker: UIView
    }

    private let headerHeight: CGFloat = 54
    private let handleSize: CGFloat = 32
    private let minWidth: CGFloat = 270
    private let minHeight: CGFloat = 390

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let tapButton = UIButton(type: .system)
    private let sequenceButton = UIButton(type: .system)
    private let pointButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)
    private let tapCaption = UILabel()
    private let sequenceCaption = UILabel()
    private let pointCaption = UILabel()
    private let clearCaption = UILabel()
    private let speedTitle = UILabel()
    private let speedValue = UILabel()
    private let speedSlider = UISlider()
    private let statusBackground = UIView()
    private let statusLabel = UILabel()
    private let resizeHandle = UILabel()

    private var mode: Mode = .tap
    private var points: [Point] = []
    private var pickerOverlay: UIView?
    private var pickerDone: UIButton?
    private var timer: DispatchSourceTimer?
    private var tapCount = 0
    private var sequenceIndex = 0
    private var running = false
    private var speed = 2.0
    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        TPIOSPanelStyle.applyGlassBackground(to: self, cornerRadius: 24)
        setupHeader()
        setupModeButtons()
        setupControls()
        setupMove()
        setupResize()
        updateModeUI()
        updateStatus()
    }

    private func setupHeader() {
        headerView.backgroundColor = UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1)
        headerView.layer.cornerRadius = 24
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(headerView)

        backButton.setTitle("‹", for: .normal)
        backButton.setTitleColor(.white, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 30, weight: .medium)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        headerView.addSubview(backButton)

        titleLabel.text = "CHẠM"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        closeButton.layer.cornerRadius = 17
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addSubview(closeButton)
    }

    private func setupModeButtons() {
        configureIconButton(tapButton, icon: "hand.tap.fill", colors: [
            UIColor(red: 0.25, green: 0.62, blue: 1, alpha: 1),
            UIColor(red: 0.08, green: 0.30, blue: 0.82, alpha: 1)
        ], action: #selector(tapModeTapped))
        configureCaption(tapCaption, text: "TAP")

        configureIconButton(sequenceButton, icon: "arrow.right.to.line.compact", colors: [
            UIColor(red: 0.68, green: 0.47, blue: 1, alpha: 1),
            UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)
        ], action: #selector(sequenceModeTapped))
        configureCaption(sequenceCaption, text: "SEQ")

        configureIconButton(pointButton, icon: "plus", colors: [
            UIColor(red: 1, green: 0.65, blue: 0.25, alpha: 1),
            UIColor(red: 0.85, green: 0.25, blue: 0.08, alpha: 1)
        ], action: #selector(pointTapped))
        configureCaption(pointCaption, text: "POINT")

        configureIconButton(clearButton, icon: "trash.fill", colors: [
            UIColor(red: 1, green: 0.35, blue: 0.27, alpha: 1),
            UIColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)
        ], action: #selector(clearTapped))
        configureCaption(clearCaption, text: "CLEAR")

        [tapButton, sequenceButton, pointButton, clearButton].forEach { addSubview($0) }
        [tapCaption, sequenceCaption, pointCaption, clearCaption].forEach { addSubview($0) }
    }

    private func setupControls() {
        startButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        startButton.tintColor = .white
        startButton.setTitle(" START", for: .normal)
        startButton.setTitleColor(.white, for: .normal)
        startButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        applyStartStyle()
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        addSubview(startButton)

        speedTitle.text = "SPEED"
        speedTitle.textColor = UIColor.white.withAlphaComponent(0.72)
        speedTitle.font = .systemFont(ofSize: 12, weight: .bold)
        addSubview(speedTitle)

        speedValue.textColor = UIColor(red: 0.28, green: 0.65, blue: 1, alpha: 1)
        speedValue.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        speedValue.textAlignment = .right
        addSubview(speedValue)

        speedSlider.minimumValue = 0.05
        speedSlider.maximumValue = 5
        speedSlider.value = Float(speed)
        speedSlider.minimumTrackTintColor = UIColor(red: 0.22, green: 0.60, blue: 1, alpha: 1)
        speedSlider.addTarget(self, action: #selector(speedChanged(_:)), for: .valueChanged)
        addSubview(speedSlider)
        updateSpeedLabel()

        statusBackground.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        statusBackground.layer.cornerRadius = 12
        addSubview(statusBackground)

        statusLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.7
        statusBackground.addSubview(statusLabel)
    }

    private func configureIconButton(_ button: UIButton, icon: String, colors: [UIColor], action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.tintColor = .white
        TPIOSPanelStyle.applyGradientFill(to: button, colors: colors, cornerRadius: 18)
        button.layer.cornerRadius = 18
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func configureCaption(_ label: UILabel, text: String) {
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
    }

    private func setupMove() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(movePanned(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        headerView.addGestureRecognizer(pan)
    }

    private func setupResize() {
        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.5)
        resizeHandle.font = .systemFont(ofSize: 18, weight: .medium)
        resizeHandle.textAlignment = .center
        resizeHandle.isUserInteractionEnabled = true
        addSubview(resizeHandle)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(resizePanned(_:)))
        pan.cancelsTouchesInView = false
        resizeHandle.addGestureRecognizer(pan)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        backButton.frame = CGRect(x: 3, y: 3, width: 40, height: 42)
        titleLabel.frame = CGRect(x: 45, y: 0, width: max(0, bounds.width - 90), height: headerHeight)
        closeButton.frame = CGRect(x: bounds.width - 46, y: 7, width: 36, height: 36)

        let side: CGFloat = 14
        let gap: CGFloat = 10
        let top = headerHeight + 14
        let width = max(0, bounds.width - side * 2)
        let col = (width - gap * 3) / 4
        let icon = min(58, col)
        let buttons = [tapButton, sequenceButton, pointButton, clearButton]
        let captions = [tapCaption, sequenceCaption, pointCaption, clearCaption]

        for index in 0..<buttons.count {
            let x = side + CGFloat(index) * (col + gap) + max(0, (col - icon) / 2)
            buttons[index].frame = CGRect(x: x, y: top, width: icon, height: icon)
            buttons[index].layer.cornerRadius = icon * 0.28
            TPIOSPanelStyle.syncFrames(in: buttons[index])
            captions[index].frame = CGRect(x: side + CGFloat(index) * (col + gap), y: top + icon + 5, width: col, height: 16)
        }

        let actionY = top + icon + 32
        startButton.frame = CGRect(x: side, y: actionY, width: width, height: 54)
        TPIOSPanelStyle.syncFrames(in: startButton)

        let speedY = actionY + 72
        speedTitle.frame = CGRect(x: side, y: speedY, width: 80, height: 18)
        speedValue.frame = CGRect(x: bounds.width - side - 82, y: speedY, width: 82, height: 18)
        speedSlider.frame = CGRect(x: side, y: speedY + 23, width: width, height: 28)

        let statusY = bounds.height - 54
        statusBackground.frame = CGRect(x: side, y: statusY, width: width, height: 38)
        statusLabel.frame = statusBackground.bounds.insetBy(dx: 10, dy: 0)
        resizeHandle.frame = CGRect(x: bounds.width - handleSize, y: bounds.height - handleSize, width: handleSize, height: handleSize)
    }

    @objc private func tapModeTapped() {
        guard !running else { return }
        mode = .tap
        updateModeUI()
    }

    @objc private func sequenceModeTapped() {
        guard !running else { return }
        mode = .sequence
        updateModeUI()
    }

    @objc private func pointTapped() {
        guard !running else { return }
        beginPointPicker()
    }

    @objc private func clearTapped() {
        guard !running else { return }
        points.forEach { $0.marker.removeFromSuperview() }
        points.removeAll()
        sequenceIndex = 0
        tapCount = 0
        updateStatus()
    }

    @objc private func startTapped() {
        if running {
            stop()
            return
        }
        guard !points.isEmpty else {
            statusLabel.text = "● CHƯA CÓ ĐIỂM — bấm POINT"
            return
        }

        running = true
        sequenceIndex = 0
        tapCount = 0
        applyStartStyle()
        updateStatus()
        performNextTap()

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + speed, repeating: speed, leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in self?.performNextTap() }
        source.resume()
        timer = source
    }

    @objc private func speedChanged(_ sender: UISlider) {
        speed = Double(sender.value)
        updateSpeedLabel()
        guard running else { return }
        stopTimerOnly()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + speed, repeating: speed, leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in self?.performNextTap() }
        source.resume()
        timer = source
    }

    private func performNextTap() {
        guard running, !points.isEmpty else { return }
        let point: CGPoint
        switch mode {
        case .tap:
            point = points[0].location
        case .sequence:
            point = points[sequenceIndex % points.count].location
            sequenceIndex = (sequenceIndex + 1) % points.count
        }
        if TPIOSAutoClickEngine.shared.tap(at: point) { tapCount += 1 }
        updateStatus()
    }

    private func stopTimerOnly() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    func stop() {
        running = false
        stopTimerOnly()
        removePicker()
        applyStartStyle()
        updateStatus()
    }

    private func applyStartStyle() {
        if running {
            startButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
            startButton.setTitle(" STOP", for: .normal)
            TPIOSPanelStyle.applyGradientFill(to: startButton, colors: [
                UIColor(red: 1, green: 0.35, blue: 0.27, alpha: 1),
                UIColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)
            ], cornerRadius: 16)
        } else {
            startButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            startButton.setTitle(" START", for: .normal)
            TPIOSPanelStyle.applyGradientFill(to: startButton, colors: [
                UIColor(red: 0.20, green: 0.65, blue: 1, alpha: 1),
                UIColor(red: 0.06, green: 0.36, blue: 0.92, alpha: 1)
            ], cornerRadius: 16)
        }
        startButton.tintColor = .white
        TPIOSPanelStyle.syncFrames(in: startButton)
    }

    private func updateModeUI() {
        setSelected(tapButton, selected: mode == .tap)
        setSelected(sequenceButton, selected: mode == .sequence)
        updateStatus()
    }

    private func setSelected(_ button: UIButton, selected: Bool) {
        button.layer.borderWidth = selected ? 2 : 1
        button.layer.borderColor = selected
            ? UIColor.white.withAlphaComponent(0.8).cgColor
            : UIColor.white.withAlphaComponent(0.28).cgColor
    }

    private func updateSpeedLabel() {
        speedValue.text = String(format: "%.3fs", speed)
    }

    private func updateStatus() {
        let state = running ? "● RUNNING" : "● IDLE"
        statusLabel.text = "\(state)     \(tapCount) taps     \(points.count) pts"
    }

    // MARK: Point picker

    private func beginPointPicker() {
        removePicker()
        guard let host = window else { return }

        let overlay = UIView(frame: host.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.01)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let hint = UILabel()
        hint.text = "Chạm màn hình để thêm điểm"
        hint.textColor = .white
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textAlignment = .center
        hint.layer.cornerRadius = 12
        hint.clipsToBounds = true
        hint.frame = CGRect(x: 20, y: host.safeAreaInsets.top + 12, width: host.bounds.width - 120, height: 40)
        overlay.addSubview(hint)

        let done = UIButton(type: .system)
        done.setTitle("Xong", for: .normal)
        done.setTitleColor(.white, for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        done.backgroundColor = UIColor(red: 0.20, green: 0.65, blue: 1, alpha: 1)
        done.layer.cornerRadius = 12
        done.frame = CGRect(x: host.bounds.width - 88, y: host.safeAreaInsets.top + 12, width: 68, height: 40)
        done.addTarget(self, action: #selector(donePicking), for: .touchUpInside)
        overlay.addSubview(done)

        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickerTapped(_:))))
        host.addSubview(overlay)
        host.bringSubviewToFront(overlay)
        pickerOverlay = overlay
        pickerDone = done
    }

    @objc private func pickerTapped(_ gesture: UITapGestureRecognizer) {
        guard let overlay = pickerOverlay else { return }
        let point = gesture.location(in: overlay)
        if let done = pickerDone,
           done.frame.insetBy(dx: -10, dy: -10).contains(point) { return }
        addPoint(at: point)
    }

    @objc private func donePicking() {
        removePicker()
    }

    private func addPoint(at point: CGPoint) {
        guard let host = window else { return }
        let index = points.count + 1
        let size: CGFloat = 30
        let marker = UIView(frame: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
        marker.backgroundColor = UIColor(red: 0.20, green: 0.65, blue: 1, alpha: 1)
        marker.layer.cornerRadius = size / 2
        marker.layer.borderWidth = 2
        marker.layer.borderColor = UIColor.white.cgColor
        marker.isUserInteractionEnabled = true

        let label = UILabel(frame: marker.bounds)
        label.text = "\(index)"
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textAlignment = .center
        marker.addSubview(label)

        marker.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(markerPanned(_:))))
        host.addSubview(marker)
        host.bringSubviewToFront(marker)
        points.append(Point(location: point, marker: marker))
        updateStatus()
    }

    @objc private func markerPanned(_ gesture: UIPanGestureRecognizer) {
        guard let marker = gesture.view,
              let index = points.firstIndex(where: { $0.marker === marker }),
              let host = window else { return }
        let point = gesture.location(in: host)
        let radius = marker.bounds.width / 2
        let x = max(radius, min(point.x, host.bounds.width - radius))
        let y = max(radius, min(point.y, host.bounds.height - radius))
        let newPoint = CGPoint(x: x, y: y)
        marker.center = newPoint
        points[index].location = newPoint
    }

    private func removePicker() {
        pickerOverlay?.removeFromSuperview()
        pickerOverlay = nil
        pickerDone = nil
    }

    @objc private func movePanned(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview,
              gesture.state == .began || gesture.state == .changed else { return }
        let delta = gesture.translation(in: parent)
        var newFrame = frame
        newFrame.origin.x = max(0, min(newFrame.origin.x + delta.x, max(0, parent.bounds.width - newFrame.width)))
        newFrame.origin.y = max(0, min(newFrame.origin.y + delta.y, max(0, parent.bounds.height - newFrame.height)))
        frame = newFrame
        gesture.setTranslation(.zero, in: parent)
    }

    @objc private func resizePanned(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else { return }
        switch gesture.state {
        case .began:
            resizeStartFrame = frame
            resizeStartPoint = gesture.location(in: parent)
        case .changed:
            let point = gesture.location(in: parent)
            let width = max(minWidth, min(resizeStartFrame.width + point.x - resizeStartPoint.x, parent.bounds.width - resizeStartFrame.origin.x))
            let height = max(minHeight, min(resizeStartFrame.height + point.y - resizeStartPoint.y, parent.bounds.height - resizeStartFrame.origin.y))
            frame = CGRect(x: resizeStartFrame.origin.x, y: resizeStartFrame.origin.y, width: width, height: height)
        default:
            break
        }
    }

    @objc private func backTapped() { onBack?() }
    @objc private func closeTapped() { onClose?() }
}

private final class TPIOSAutoClickEngine {

    static let shared = TPIOSAutoClickEngine()

    private typealias CreateDigitizerFn = @convention(c) (
        UnsafeRawPointer?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32,
        Double, Double, Double, Double, Double, DarwinBoolean, DarwinBoolean, UInt32
    ) -> OpaquePointer?
    private typealias CreateFingerFn = @convention(c) (
        UnsafeRawPointer?, UInt64, UInt32, UInt32, UInt32,
        Double, Double, Double, Double, Double, DarwinBoolean, DarwinBoolean, UInt32
    ) -> OpaquePointer?
    private typealias CreateClientFn = @convention(c) (UnsafeRawPointer?) -> OpaquePointer?
    private typealias AppendFn = @convention(c) (OpaquePointer, OpaquePointer, UInt32) -> Void
    private typealias SetIntegerFn = @convention(c) (OpaquePointer, UInt32, Int64) -> Void
    private typealias SetSenderFn = @convention(c) (OpaquePointer, UInt64) -> Void
    private typealias DispatchFn = @convention(c) (OpaquePointer, OpaquePointer) -> Void
    private typealias SetDigitizerInfoFn = @convention(c) (
        OpaquePointer, UInt32, DarwinBoolean, DarwinBoolean, CFString?, CFTimeInterval, Float
    ) -> Void

    private let lock = NSLock()
    private var loaded = false
    private var createDigitizer: CreateDigitizerFn?
    private var createFinger: CreateFingerFn?
    private var createClient: CreateClientFn?
    private var appendEvent: AppendFn?
    private var setInteger: SetIntegerFn?
    private var setSender: SetSenderFn?
    private var dispatchEvent: DispatchFn?
    private var setDigitizerInfo: SetDigitizerInfoFn?
    private var client: OpaquePointer?

    private let eventRange: UInt32 = 1 << 0
    private let eventTouch: UInt32 = 1 << 1
    private let eventIdentity: UInt32 = 1 << 5
    private let displayIntegratedField: UInt32 = (11 << 16) + 25
    private let senderID: UInt64 = 0x8000000817319375

    private init() {}

    func tap(at point: CGPoint) -> Bool {
        guard prepare() else {
            TPIOSLog.shared.log("AutoClick: không tải được IOHID")
            return false
        }
        guard let window = activeAppWindow() ?? activeKeyWindow(), let client else {
            TPIOSLog.shared.log("AutoClick: không tìm thấy cửa sổ đích")
            return false
        }

        let width = max(window.bounds.width, 1)
        let height = max(window.bounds.height, 1)
        let x = max(0, min(1, Double(point.x / width)))
        let y = max(0, min(1, Double(point.y / height)))

        guard dispatchTouch(client: client, window: window, x: x, y: y, touching: true),
              dispatchTouch(client: client, window: window, x: x, y: y, touching: false) else {
            return false
        }
        return true
    }

    private func dispatchTouch(client: OpaquePointer, window: UIWindow, x: Double, y: Double, touching: Bool) -> Bool {
        let timestamp = mach_absolute_time()
        let parentMask = touching ? (eventTouch | eventIdentity) : (eventRange | eventTouch | eventIdentity)

        guard let parent = createDigitizer?(
            nil, timestamp, 3, 0, 0, parentMask, 0,
            0, 0, 0, 0, 0,
            false, touching, 0
        ),
        let child = createFinger?(
            nil, timestamp, 1, 2, eventRange | eventTouch,
            x, y, 0, 0, 0,
            touching, touching, 0
        ) else {
            return false
        }

        setInteger?(parent, displayIntegratedField, 1)
        setSender?(parent, senderID)
        appendEvent?(parent, child, 0)

        if let setDigitizerInfo {
            let contextID = (window.value(forKey: "_contextId") as? NSNumber)?.uint32Value ?? 0
            setDigitizerInfo(parent, contextID, false, false, nil, 0, 0)
        }

        dispatchEvent(client, parent)
        CFRelease(child)
        CFRelease(parent)

        if touching == false {
            usleep(2000)
        }
        return true
    }

    private func prepare() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if loaded {
            return createDigitizer != nil && createFinger != nil && client != nil && dispatchEvent != nil
        }
        loaded = true

        var ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_GLOBAL)
        if ioKit == nil {
            ioKit = dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_GLOBAL)
        }
        guard let ioKit else { return false }

        createDigitizer = load("IOHIDEventCreateDigitizerEvent", from: ioKit)
        createFinger = load("IOHIDEventCreateDigitizerFingerEvent", from: ioKit)
        createClient = load("IOHIDEventSystemClientCreate", from: ioKit)
        appendEvent = load("IOHIDEventAppendEvent", from: ioKit)
        setInteger = load("IOHIDEventSetIntegerValue", from: ioKit)
        setSender = load("IOHIDEventSetSenderID", from: ioKit)
        dispatchEvent = load("IOHIDEventSystemClientDispatchEvent", from: ioKit)

        if let backBoard = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW | RTLD_GLOBAL) {
            setDigitizerInfo = load("BKSHIDEventSetDigitizerInfo", from: backBoard)
        }
        client = createClient?(nil)

        return createDigitizer != nil && createFinger != nil && createClient != nil &&
            appendEvent != nil && setInteger != nil && setSender != nil && dispatchEvent != nil && client != nil
    }

    private func load<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    private func activeKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }

    private func activeAppWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter {
                !$0.isHidden &&
                NSStringFromClass(type(of: $0)).contains("TPIOS") == false &&
                $0.rootViewController != nil
            }
            .first(where: { $0.windowLevel == .normal })
    }
}
