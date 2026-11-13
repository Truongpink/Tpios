import UIKit

final class TPIOSAutoClickPanel: UIView {
    private struct SavedPoint: Codable {
        let x: Double
        let y: Double
    }

    private struct SavedSettings: Codable {
        let points: [SavedPoint]
        let speed: Double
    }

    private static let settingsKey = "TPIOSAutoClickSettings"
    private var points: [CGPoint] = []
    private var markers: [UIView] = []
    private var timer: DispatchSourceTimer?
    private var tapCount = 0
    private var running = false
    private var speed: TimeInterval = 0.15
    private var picker: UIView?
    private var currentPointIndex = 0
    private var touchIsDown = false
    private var activePoint = CGPoint.zero
    private let pressDuration: TimeInterval = 0.06

    private let header = UIView()
    private let content = UIView()
    private let statusLabel = UILabel()
    private let countLabel = UILabel()
    private let pointLabel = UILabel()
    private let speedLabel = UILabel()
    private let speedSlider = UISlider()
    private let speedMinusButton = UIButton(type: .system)
    private let speedPlusButton = UIButton(type: .system)
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
        loadSettings()
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        markers.forEach { $0.removeFromSuperview() }
        markers.removeAll()
        points.forEach { addMarker(at: $0) }
        pointLabel.text = "POINT: \(points.count)"
        speedSlider.value = Float(speed)
        speedLabel.text = String(format: "Tốc độ  %.2fs", speed)
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey),
              let saved = try? JSONDecoder().decode(SavedSettings.self, from: data) else { return }
        points = saved.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        speed = min(5.0, max(0.05, saved.speed))
    }

    private func saveSettings() {
        let saved = SavedSettings(
            points: points.map { SavedPoint(x: Double($0.x), y: Double($0.y)) },
            speed: speed
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }

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

        iconButton(pointButton, icon: "scope", colors: [UIColor(red: 0.36, green: 0.71, blue: 1.00, alpha: 1), UIColor(red: 0.09, green: 0.39, blue: 0.80, alpha: 1)], action: #selector(pointMode))
        iconButton(clearButton, icon: "trash.fill", colors: [UIColor(red: 1.00, green: 0.35, blue: 0.27, alpha: 1), UIColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)], action: #selector(clearPoints))
        iconButton(startButton, icon: "play.fill", colors: [UIColor(red: 0.36, green: 0.88, blue: 0.55, alpha: 1), UIColor(red: 0.06, green: 0.52, blue: 0.33, alpha: 1)], action: #selector(startStop))

        let pointCaption = UILabel(), clearLabel = UILabel(), startLabel = UILabel()
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
        speedButton(speedMinusButton, icon: "chevron.left", action: #selector(decreaseSpeed))
        speedButton(speedPlusButton, icon: "chevron.right", action: #selector(increaseSpeed))
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
        let backSize = 34 * scale, closeSize = 34 * scale, side = 16 * scale
        if let back = header.subviews.first(where: { $0 is UIButton }) as? UIButton { back.frame = CGRect(x: side, y: 16 * scale, width: backSize, height: backSize) }
        if let close = header.subviews.compactMap({ $0 as? UIButton }).last { close.frame = CGRect(x: bounds.width - side - closeSize, y: 16 * scale, width: closeSize, height: closeSize) }
        if let title = header.viewWithTag(1001) as? UILabel {
            title.frame = CGRect(x: 56 * scale, y: 12 * scale, width: max(0, bounds.width - 112 * scale), height: 42 * scale)
            title.font = .systemFont(ofSize: max(12, 19 * scale), weight: .bold)
        }
        let sidePadding = 14 * scale, columnGap = 10 * scale
        let contentWidth = max(0, bounds.width - sidePadding * 2)
        let columnWidth = max(0, (contentWidth - columnGap * 2) / 3)
        let iconSize = min(columnWidth, 58 * scale), iconInset = max(0, (columnWidth - iconSize) / 2)
        let labelHeight = 15 * scale, iconLabelGap = 3 * scale, rowHeight = iconSize + iconLabelGap + labelHeight, rowGap = 7 * scale, top = 10 * scale
        let buttons = [pointButton, clearButton]
        let actionColumnWidth = (contentWidth - columnGap) / 2
        let labels = content.subviews.compactMap { $0 as? UILabel }.filter { $0 !== statusLabel && $0 !== countLabel && $0 !== pointLabel && $0 !== speedLabel }
        for index in 0..<buttons.count {
            let centerX = sidePadding + (CGFloat(index) + 0.5) * (actionColumnWidth + columnGap)
            buttons[index].frame = CGRect(x: centerX - iconSize / 2, y: top, width: iconSize, height: iconSize)
            buttons[index].layer.cornerRadius = iconSize * 0.28
            TPIOSPanelStyle.syncFrames(in: buttons[index])
            if index < labels.count {
                labels[index].frame = CGRect(x: centerX - actionColumnWidth / 2, y: top + iconSize + iconLabelGap, width: actionColumnWidth, height: labelHeight)
                labels[index].font = .systemFont(ofSize: max(8, 13 * scale), weight: .semibold)
            }
        }
        let secondY = top + rowHeight + rowGap
        startButton.frame = CGRect(x: sidePadding + iconInset, y: secondY, width: iconSize, height: iconSize)
        startButton.layer.cornerRadius = iconSize * 0.28
        TPIOSPanelStyle.syncFrames(in: startButton)
        if labels.count > 2 {
            labels[2].frame = CGRect(x: sidePadding, y: secondY + iconSize + iconLabelGap, width: columnWidth, height: labelHeight)
            labels[2].font = .systemFont(ofSize: max(8, 13 * scale), weight: .semibold)
        }
        let infoY = secondY + rowHeight + 3 * scale
        statusLabel.frame = CGRect(x: sidePadding, y: infoY, width: bounds.width - sidePadding * 2, height: 15 * scale)
        countLabel.frame = CGRect(x: sidePadding, y: infoY + 16 * scale, width: (bounds.width - sidePadding * 2) / 2 - 4 * scale, height: 15 * scale)
        pointLabel.frame = CGRect(x: bounds.midX + 4 * scale, y: infoY + 16 * scale, width: (bounds.width - sidePadding * 2) / 2 - 4 * scale, height: 15 * scale)
        speedLabel.frame = CGRect(x: sidePadding, y: infoY + 35 * scale, width: bounds.width - sidePadding * 2, height: 15 * scale)
        speedLabel.font = .systemFont(ofSize: max(8, 11 * scale), weight: .semibold)
        let controlY = infoY + 48 * scale, controlHeight = 24 * scale, arrowSize = 26 * scale, arrowGap = 4 * scale
        speedMinusButton.frame = CGRect(x: sidePadding, y: controlY, width: arrowSize, height: controlHeight)
        speedPlusButton.frame = CGRect(x: bounds.width - sidePadding - arrowSize, y: controlY, width: arrowSize, height: controlHeight)
        speedMinusButton.layer.cornerRadius = 10 * scale
        speedPlusButton.layer.cornerRadius = 10 * scale
        speedSlider.frame = CGRect(x: sidePadding + arrowSize + arrowGap, y: controlY, width: max(20, bounds.width - sidePadding * 2 - (arrowSize + arrowGap) * 2), height: controlHeight)
        resizeHandle.frame = CGRect(x: bounds.width - 44 * scale, y: bounds.height - 44 * scale, width: 44 * scale, height: 44 * scale)
        resizeHandle.font = .systemFont(ofSize: 19 * scale, weight: .medium)
    }

    @objc private func movePanel(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        let translation = gesture.translation(in: superview)
        center.x += translation.x; center.y += translation.y
        gesture.setTranslation(.zero, in: superview)
        center.x = min(max(center.x, bounds.width / 2), superview.bounds.width - bounds.width / 2)
        center.y = min(max(center.y, bounds.height / 2), superview.bounds.height - bounds.height / 2)
    }

    @objc private func resizePanel(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        switch gesture.state {
        case .began:
            resizeStartFrame = frame; resizeStartPoint = gesture.location(in: superview)
        case .changed:
            let point = gesture.location(in: superview)
            let dx = point.x - resizeStartPoint.x, dy = point.y - resizeStartPoint.y
            let width = min(max(220, resizeStartFrame.width + dx), superview.bounds.width - resizeStartFrame.minX)
            let height = min(max(300, resizeStartFrame.height + dy), superview.bounds.height - resizeStartFrame.minY)
            frame = CGRect(x: resizeStartFrame.minX, y: resizeStartFrame.minY, width: width, height: height)
        default: break
        }
    }

    @objc private func backTap() { onBack?() }
    @objc private func closeTap() { onClose?() }

    @objc private func pointMode() {
        picker?.removeFromSuperview()
        guard let window = superview as? UIWindow else { return }

        let overlay = UIView(frame: window.bounds)
        overlay.backgroundColor = .clear
        let tapArea = UIView(frame: overlay.bounds)
        tapArea.backgroundColor = .clear
        tapArea.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickerTap(_:))))
        overlay.addSubview(tapArea)

        let doneButton = UIButton(type: .system)
        doneButton.setTitle("XONG", for: .normal)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        doneButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.95)
        doneButton.layer.cornerRadius = 18
        doneButton.frame = CGRect(x: (window.bounds.width - 104) / 2, y: window.safeAreaInsets.top + 12, width: 104, height: 40)
        doneButton.addTarget(self, action: #selector(finishPointMode), for: .touchUpInside)
        overlay.addSubview(doneButton)

        window.addSubview(overlay)
        picker = overlay
        isHidden = true
        statusLabel.text = "CHỌN NHIỀU ĐIỂM · NHẤN XONG"
    }

    @objc private func pickerTap(_ gesture: UITapGestureRecognizer) {
        guard let overlay = picker, let window = overlay.superview as? UIWindow else { return }
        let windowPoint = gesture.location(in: window)
        points.append(windowPoint)
        addMarker(at: windowPoint)
        pointLabel.text = "POINT: \(points.count)"
        saveSettings()
    }

    @objc private func finishPointMode() {
        picker?.removeFromSuperview()
        picker = nil
        isHidden = false
        statusLabel.text = "ĐÃ LƯU \(points.count) ĐIỂM"
        saveSettings()
    }

    private func addMarker(at point: CGPoint) {
        guard let window = superview as? UIWindow else { return }
        let marker = UIView(frame: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
        marker.tag = 0x5450494F
        marker.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        marker.layer.cornerRadius = 12
        marker.layer.borderWidth = 2
        marker.layer.borderColor = UIColor.white.cgColor
        marker.isUserInteractionEnabled = true
        marker.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(moveMarker(_:))))
        window.addSubview(marker)
        markers.append(marker)
    }

    @objc private func moveMarker(_ gesture: UIPanGestureRecognizer) {
        guard let marker = gesture.view,
              let window = superview as? UIWindow,
              let index = markers.firstIndex(of: marker),
              index < points.count else { return }
        let location = gesture.location(in: window)
        marker.center = location
        points[index] = location
        pointLabel.text = "POINT: \(points.count)"
        if gesture.state == .ended || gesture.state == .cancelled { saveSettings() }
    }

    @objc private func clearPoints() {
        stop()
        points.removeAll(); markers.forEach { $0.removeFromSuperview() }; markers.removeAll()
        pointLabel.text = "POINT: 0"; countLabel.text = "TAP: 0"; statusLabel.text = "IDLE"
        saveSettings()
        TPIOSLog.shared.log("TapPanel: points cleared")
    }

    @objc private func speedChanged() {
        speed = TimeInterval(speedSlider.value)
        speedLabel.text = String(format: "Tốc độ  %.2fs", speed)
        saveSettings()
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
        if running { stop(); return }
        guard !touchIsDown else {
            statusLabel.text = "CHƯA NHẢ ĐƯỢC TOUCH"
            TPIOSLog.shared.log("TapPanel: start blocked - previous UP unconfirmed")
            return
        }
        guard TPIOSAutoClickEngine.backendAvailable() else {
            statusLabel.text = "HID KHÔNG SẴN SÀNG"
            TPIOSLog.shared.log("TapPanel: HID backend unavailable")
            return
        }
        running = true
        currentPointIndex = 0
        startButton.setImage(UIImage(systemName: "stop.fill"), for: .normal)
        statusLabel.text = "RUNNING"
        TPIOSLog.shared.log("TapPanel: auto START points=\(points.count)")
        // Avoid injecting DOWN re-entrantly while UIKit is handling the START button.
        DispatchQueue.main.async { [weak self] in self?.performDown() }
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + max(0.0001, delay), leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in self?.timer = nil; action() }
        timer = source
        source.resume()
    }

    private func performDown() {
        guard running, !touchIsDown, !points.isEmpty else { return }
        let point = points[currentPointIndex % points.count]
        guard TPIOSAutoClickEngine.shared.dispatchTouch(at: point, down: true) else {
            TPIOSLog.shared.log("TapPanel: DOWN failed")
            stop()
            statusLabel.text = "DOWN LỖI"
            return
        }
        activePoint = point
        touchIsDown = true
        schedule(after: pressDuration) { [weak self] in self?.performUp() }
    }

    private func performUp() {
        guard touchIsDown else { return }
        guard TPIOSAutoClickEngine.shared.dispatchTouch(at: activePoint, down: false) else {
            TPIOSLog.shared.log("TapPanel: UP failed; blocking next DOWN")
            stop()
            statusLabel.text = "UP LỖI - ĐÃ KHÓA"
            return
        }
        touchIsDown = false
        tapCount += 1
        countLabel.text = "TAP: \(tapCount)"
        currentPointIndex = (currentPointIndex + 1) % points.count
        if running { schedule(after: speed) { [weak self] in self?.performDown() } }
        else { statusLabel.text = "STOPPED" }
    }

    func cleanup() {
        stop()
        picker?.removeFromSuperview()
        picker = nil
        markers.forEach { $0.removeFromSuperview() }
        markers.removeAll()
        tapCount = 0
        currentPointIndex = 0
        saveSettings()
        TPIOSLog.shared.log("TapPanel: cleanup panel exit - marker/picker/timer removed")
    }

    func stop() {
        running = false
        timer?.cancel()
        timer = nil
        if touchIsDown { releaseTouch() }
        startButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        if !touchIsDown { statusLabel.text = "STOPPED" }
        TPIOSLog.shared.log("TapPanel: stopped touchDown=\(touchIsDown)")
    }
}
