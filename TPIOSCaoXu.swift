import UIKit

final class TPIOSCaoXu: UIView, UIGestureRecognizerDelegate {

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private let headerHeight: CGFloat = 54
    private let minWidth: CGFloat = 280
    private let minHeight: CGFloat = 420

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let logTitleLabel = UILabel()
    private let logView = UITextView()
    private let copyButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let resizeHandle = UILabel()

    private var taskNames: [String] = []
    private var currentTaskIndex = 0
    private var sessionActive = false
    private var logs: [String] = []
    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero

    private let stateKey = "TPIOSCaoXuState"
    private let logKey = "TPIOSCaoXuLogs"
    private static let logUpdatedNotification = Notification.Name("TPIOSCaoXuLogUpdated")

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadState()
        setup()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(capturedLogUpdated),
            name: Self.logUpdatedNotification,
            object: nil
        )
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: Self.logUpdatedNotification, object: nil)
    }

    static func recordCapturedRequest(_ url: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        var savedLogs = UserDefaults.standard.stringArray(forKey: "TPIOSCaoXuLogs") ?? []
        savedLogs.append("[\(formatter.string(from: Date()))] Lazada: \(url)")
        if savedLogs.count > 500 {
            savedLogs.removeFirst(savedLogs.count - 500)
        }
        UserDefaults.standard.set(savedLogs, forKey: "TPIOSCaoXuLogs")
        NotificationCenter.default.post(name: logUpdatedNotification, object: nil)
    }

    @objc private func capturedLogUpdated() {
        logs = UserDefaults.standard.stringArray(forKey: logKey) ?? []
        refreshLog()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        TPIOSPanelStyle.applyGlassBackground(to: self, cornerRadius: 24)

        headerView.backgroundColor = UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1)
        headerView.layer.cornerRadius = 24
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(headerView)

        styleHeaderButton(backButton, title: "‹", size: 30, action: #selector(backTapped))
        styleHeaderButton(closeButton, title: "×", size: 27, action: #selector(closeTapped))
        headerView.addSubview(backButton)
        headerView.addSubview(closeButton)

        titleLabel.text = "CÀO XU LAZADA"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)

        statusLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .center
        addSubview(statusLabel)

        progressLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        progressLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        progressLabel.textAlignment = .center
        addSubview(progressLabel)

        progressView.progressTintColor = UIColor(red: 0.25, green: 0.82, blue: 0.55, alpha: 1)
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.12)
        addSubview(progressView)

        configureActionButton(startButton, title: "Bắt đầu / Tiếp tục", color: UIColor(red: 0.10, green: 0.57, blue: 0.38, alpha: 1), action: #selector(startTapped))
        configureActionButton(stopButton, title: "Kết thúc / Tạm dừng", color: UIColor(red: 0.68, green: 0.24, blue: 0.22, alpha: 1), action: #selector(stopTapped))
        addSubview(startButton)
        addSubview(stopButton)

        logTitleLabel.text = "LOG CÀO XU"
        logTitleLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        logTitleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        addSubview(logTitleLabel)

        logView.backgroundColor = UIColor(red: 0.055, green: 0.065, blue: 0.08, alpha: 1)
        logView.textColor = UIColor.white.withAlphaComponent(0.88)
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.layer.cornerRadius = 12
        logView.isEditable = false
        logView.alwaysBounceVertical = true
        logView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        addSubview(logView)

        configureSmallButton(copyButton, title: "Sao chép log", action: #selector(copyTapped))
        configureSmallButton(clearButton, title: "Xóa log", action: #selector(clearTapped))
        addSubview(copyButton)
        addSubview(clearButton)

        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.58)
        resizeHandle.font = .systemFont(ofSize: 19, weight: .medium)
        resizeHandle.textAlignment = .center
        resizeHandle.isUserInteractionEnabled = true
        addSubview(resizeHandle)

        let move = UIPanGestureRecognizer(target: self, action: #selector(movePanned(_:)))
        move.delegate = self
        move.cancelsTouchesInView = false
        headerView.addGestureRecognizer(move)

        let resize = UIPanGestureRecognizer(target: self, action: #selector(resizePanned(_:)))
        resize.cancelsTouchesInView = false
        resizeHandle.addGestureRecognizer(resize)
    }

    private func styleHeaderButton(_ button: UIButton, title: String, size: CGFloat, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: size, weight: .regular)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func configureActionButton(_ button: UIButton, title: String, color: UIColor, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.backgroundColor = color
        button.layer.cornerRadius = 11
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func configureSmallButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.88), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        button.layer.cornerRadius = 9
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        backButton.frame = CGRect(x: 4, y: 4, width: 42, height: 44)
        closeButton.frame = CGRect(x: bounds.width - 44, y: 4, width: 40, height: 44)
        titleLabel.frame = CGRect(x: 48, y: 0, width: max(0, bounds.width - 96), height: headerHeight)

        let inset: CGFloat = 14
        let width = max(0, bounds.width - inset * 2)
        statusLabel.frame = CGRect(x: inset, y: 64, width: width, height: 38)
        progressLabel.frame = CGRect(x: inset, y: 105, width: width, height: 20)
        progressView.frame = CGRect(x: inset, y: 130, width: width, height: 5)

        startButton.frame = CGRect(x: inset, y: 148, width: width, height: 42)
        stopButton.frame = CGRect(x: inset, y: 198, width: width, height: 42)

        logTitleLabel.frame = CGRect(x: inset, y: 252, width: width, height: 18)
        let buttonY = bounds.height - 48
        copyButton.frame = CGRect(x: inset, y: buttonY, width: (width - 8) / 2, height: 34)
        clearButton.frame = CGRect(x: inset + (width + 8) / 2, y: buttonY, width: (width - 8) / 2, height: 34)
        logView.frame = CGRect(x: inset, y: 276, width: width, height: max(50, buttonY - 284))
        resizeHandle.frame = CGRect(x: bounds.width - 38, y: bounds.height - 38, width: 36, height: 36)
    }

    private func loadState() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: stateKey),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            taskNames = state["tasks"] as? [String] ?? []
            currentTaskIndex = max(0, state["currentIndex"] as? Int ?? 0)
        }
        logs = defaults.stringArray(forKey: logKey) ?? []
        sessionActive = false
    }

    private func saveState() {
        let state: [String: Any] = [
            "tasks": taskNames,
            "currentIndex": currentTaskIndex
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
        UserDefaults.standard.set(logs, forKey: logKey)
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.append("[\(formatter.string(from: Date()))] \(message)")
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
        saveState()
        refreshLog()
    }

    private func refresh() {
        let hostBundleID = Bundle.main.bundleIdentifier ?? "không rõ bundle"

        if taskNames.isEmpty {
            progressLabel.text = "0/0  •  Chưa nhận diện nhiệm vụ"
            progressView.progress = 0
            let state = sessionActive
                ? "Phiên đã mở — đang chờ dữ liệu nhiệm vụ"
                : "Chưa có dữ liệu nhiệm vụ"
            statusLabel.text = "\(state)\nAPP: \(hostBundleID)"
        } else {
            let total = taskNames.count
            currentTaskIndex = min(currentTaskIndex, total)
            progressLabel.text = "\(min(currentTaskIndex + 1, total))/\(total)  •  \(currentTaskIndex >= total ? "Hoàn tất" : "Chờ chạy")"
            progressView.progress = total == 0 ? 0 : Float(currentTaskIndex) / Float(total)
            let task = currentTaskIndex < total ? taskNames[currentTaskIndex] : "Đã hoàn tất danh sách"
            let state = sessionActive ? "Đang tiếp tục: \(task)" : "Đã tạm dừng: \(task)"
            statusLabel.text = "\(state)\nAPP: \(hostBundleID)"
        }
        refreshLog()
    }

    private func refreshLog() {
        logView.text = logs.joined(separator: "\n")
        if !logs.isEmpty {
            logView.scrollRangeToVisible(NSRange(location: max(0, logView.text.count - 1), length: 1))
        }
    }

    // Được gọi khi bộ đọc nhiệm vụ Lazada được bổ sung.
    func updateTasks(_ names: [String]) {
        taskNames = names
        currentTaskIndex = min(currentTaskIndex, taskNames.count)
        appendLog("Đã cập nhật danh sách nhiệm vụ: \(names.count)")
        refresh()
    }

    // Được gọi khi một kịch bản nhiệm vụ đã xác nhận hoàn thành.
    func markCurrentTaskCompleted() {
        guard currentTaskIndex < taskNames.count else { return }
        appendLog("Hoàn thành: \(taskNames[currentTaskIndex])")
        currentTaskIndex += 1
        saveState()
        refresh()
    }

    @objc private func startTapped() {
        let captureStarted = TPIOSNetworkLog.shared.startLazadaCapture { url in
            TPIOSCaoXu.recordCapturedRequest(url)
        }
        if captureStarted {
            appendLog("Đã bật ghi nhận request Lazada; query/token được loại khỏi log")
        } else {
            appendLog("Không bật bắt mạng: APP hiện tại không phải com.lazadaSEA.lazada")
        }

        guard taskNames.isEmpty == false else {
            sessionActive = true
            statusLabel.text = "Chưa có nhiệm vụ/kịch bản. Chưa thực hiện thao tác tự động."
            appendLog("Bắt đầu phiên — chưa có dữ liệu nhiệm vụ; chờ ghi nhận Lazada")
            refresh()
            return
        }

        guard currentTaskIndex < taskNames.count else {
            statusLabel.text = "Danh sách nhiệm vụ đã hoàn tất"
            appendLog("Không còn nhiệm vụ để tiếp tục")
            return
        }

        sessionActive = true
        appendLog("Tiếp tục tại \(currentTaskIndex + 1)/\(taskNames.count): \(taskNames[currentTaskIndex])")
        refresh()
    }

    @objc private func stopTapped() {
        sessionActive = false
        TPIOSNetworkLog.shared.stopLazadaCapture()
        appendLog("Đã kết thúc/tạm dừng phiên tại nhiệm vụ \(currentTaskIndex + 1)")
        saveState()
        refresh()
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = logs.joined(separator: "\n")
        appendLog("Đã sao chép log")
    }

    @objc private func clearTapped() {
        logs.removeAll()
        saveState()
        refreshLog()
    }

    @objc private func backTapped() {
        saveState()
        onBack?()
    }

    @objc private func closeTapped() {
        saveState()
        onClose?()
    }

    @objc private func movePanned(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview,
              gesture.state == .began || gesture.state == .changed else { return }
        let delta = gesture.translation(in: parent)
        var next = frame
        next.origin.x += delta.x
        next.origin.y += delta.y
        next.origin.x = max(0, min(next.origin.x, max(0, parent.bounds.width - next.width)))
        next.origin.y = max(0, min(next.origin.y, max(0, parent.bounds.height - next.height)))
        frame = next
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
            let width = max(minWidth, min(resizeStartFrame.width + point.x - resizeStartPoint.x,
                                          parent.bounds.width - resizeStartFrame.origin.x))
            let height = max(minHeight, min(resizeStartFrame.height + point.y - resizeStartPoint.y,
                                           parent.bounds.height - resizeStartFrame.origin.y))
            frame = CGRect(x: resizeStartFrame.origin.x, y: resizeStartFrame.origin.y, width: width, height: height)
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        true
    }
}
