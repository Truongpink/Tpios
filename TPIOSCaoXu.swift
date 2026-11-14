import UIKit

final class TPIOSCaoXu: UIView, UIGestureRecognizerDelegate {

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private let headerHeight: CGFloat = 54
    private let minWidth: CGFloat = 280
    private let minHeight: CGFloat = 390

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let addTaskButton = UIButton(type: .system)
    private let listTasksButton = UIButton(type: .system)
    private let completeTaskButton = UIButton(type: .system)
    private let logTitleLabel = UILabel()
    private let logView = UITextView()
    private let tuckHandle = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let resizeHandle = UILabel()

    private var taskNames: [String] = []
    private var completedTasks: [Bool] = []
    private var currentTaskIndex = 0
    private var sessionActive = false
    private var logs: [String] = []
    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero
    private var moveStartFrame = CGRect.zero
    private var moveStartedTucked = false
    private var isTuckedToEdge = false
    private var tuckedToLeft = false
    private var expandedFrame = CGRect.zero

    private let stateKey = "TPIOSCaoXuState"
    private let logKey = "TPIOSCaoXuLogs"

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadState()
        setup()
        refresh()
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

        configureSmallButton(addTaskButton, title: "＋ Thêm", action: #selector(addTaskTapped))
        configureSmallButton(listTasksButton, title: "Danh sách", action: #selector(listTasksTapped))
        configureSmallButton(completeTaskButton, title: "✓ Hoàn thành", action: #selector(completeTaskTapped))
        addSubview(addTaskButton)
        addSubview(listTasksButton)
        addSubview(completeTaskButton)

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

        tuckHandle.setTitle("↔", for: .normal)
        tuckHandle.setTitleColor(.white, for: .normal)
        tuckHandle.titleLabel?.font = .systemFont(ofSize: 25, weight: .semibold)
        tuckHandle.backgroundColor = UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1)
        tuckHandle.layer.cornerRadius = 18
        tuckHandle.isHidden = true
        addSubview(tuckHandle)

        let move = UIPanGestureRecognizer(target: self, action: #selector(movePanned(_:)))
        move.delegate = self
        move.cancelsTouchesInView = false
        headerView.addGestureRecognizer(move)

        let tuckedMove = UIPanGestureRecognizer(target: self, action: #selector(movePanned(_:)))
        tuckedMove.delegate = self
        tuckedMove.cancelsTouchesInView = false
        tuckHandle.addGestureRecognizer(tuckedMove)

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

        let controlY: CGFloat = 250
        let controlGap: CGFloat = 6
        let controlWidth = (width - controlGap * 2) / 3
        addTaskButton.frame = CGRect(x: inset, y: controlY, width: controlWidth, height: 32)
        listTasksButton.frame = CGRect(x: inset + controlWidth + controlGap, y: controlY, width: controlWidth, height: 32)
        completeTaskButton.frame = CGRect(x: inset + (controlWidth + controlGap) * 2, y: controlY, width: controlWidth, height: 32)
        logTitleLabel.frame = CGRect(x: inset, y: 290, width: width, height: 18)
        let buttonY = bounds.height - 48
        copyButton.frame = CGRect(x: inset, y: buttonY, width: (width - 8) / 2, height: 34)
        clearButton.frame = CGRect(x: inset + (width + 8) / 2, y: buttonY, width: (width - 8) / 2, height: 34)
        logView.frame = CGRect(x: inset, y: 312, width: width, height: max(24, buttonY - 320))
        resizeHandle.frame = CGRect(x: bounds.width - 38, y: bounds.height - 38, width: 36, height: 36)
        tuckHandle.frame = bounds
    }

    private func loadState() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: stateKey),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            taskNames = state["tasks"] as? [String] ?? []
            completedTasks = state["completed"] as? [Bool] ?? []
            if completedTasks.count < taskNames.count {
                completedTasks.append(contentsOf: repeatElement(false, count: taskNames.count - completedTasks.count))
            } else if completedTasks.count > taskNames.count {
                completedTasks = Array(completedTasks.prefix(taskNames.count))
            }
            currentTaskIndex = max(0, state["currentIndex"] as? Int ?? 0)
        }
        if completedTasks.count < taskNames.count {
            completedTasks.append(contentsOf: repeatElement(false, count: taskNames.count - completedTasks.count))
        }
        currentTaskIndex = firstPendingTaskIndex()
        logs = defaults.stringArray(forKey: logKey) ?? []
        sessionActive = false
    }

    private func saveState() {
        let state: [String: Any] = [
            "tasks": taskNames,
            "completed": completedTasks,
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

        let total = taskNames.count
        let completed = completedTasks.filter { $0 }.count
        currentTaskIndex = firstPendingTaskIndex()
        progressLabel.text = "\(completed)/\(total)  •  \(total > 0 && completed == total ? "Hoàn tất" : "Đã lưu")"
        progressView.progress = total == 0 ? 0 : Float(completed) / Float(total)
        if total == 0 {
            statusLabel.text = "Chưa có nhiệm vụ — nhấn ＋ Thêm để tạo\nAPP: \(hostBundleID)"
        } else {
            let task = currentTaskIndex < total ? taskNames[currentTaskIndex] : "Đã hoàn tất danh sách"
            let state = sessionActive ? "Đang theo dõi: \(task)" : "Nhiệm vụ tiếp theo: \(task)"
            statusLabel.text = "\(state)\nAPP: \(hostBundleID)"
        }
        completeTaskButton.isEnabled = currentTaskIndex < total
        completeTaskButton.alpha = completeTaskButton.isEnabled ? 1 : 0.45
        refreshLog()
    }

    private func refreshLog() {
        logView.text = logs.joined(separator: "\n")
        if !logs.isEmpty {
            logView.scrollRangeToVisible(NSRange(location: max(0, logView.text.count - 1), length: 1))
        }
    }

    private func firstPendingTaskIndex() -> Int {
        completedTasks.firstIndex(of: false) ?? taskNames.count
    }

    func updateTasks(_ names: [String]) {
        taskNames = names
        completedTasks = Array(completedTasks.prefix(names.count))
        if completedTasks.count < names.count {
            completedTasks.append(contentsOf: repeatElement(false, count: names.count - completedTasks.count))
        }
        currentTaskIndex = firstPendingTaskIndex()
        appendLog("Đã cập nhật danh sách nhiệm vụ: \(names.count)")
        refresh()
    }

    func markCurrentTaskCompleted() {
        let index = firstPendingTaskIndex()
        guard index < taskNames.count else { return }
        completedTasks[index] = true
        currentTaskIndex = firstPendingTaskIndex()
        appendLog("Hoàn thành thủ công: \(taskNames[index])")
        saveState()
        refresh()
    }

    @objc private func addTaskTapped() {
        let alert = UIAlertController(title: "Thêm nhiệm vụ Lazada", message: "Nhập tên hoặc nội dung cần tự thực hiện", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Ví dụ: Xem livestream 5 phút"
            field.returnKeyType = .done
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu nhiệm vụ", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return }
            self.taskNames.append(name)
            self.completedTasks.append(false)
            self.currentTaskIndex = self.firstPendingTaskIndex()
            self.appendLog("Đã thêm nhiệm vụ: \(name)")
            self.saveState()
            self.refresh()
        })
        window?.rootViewController?.present(alert, animated: true)
    }

    @objc private func listTasksTapped() {
        guard !taskNames.isEmpty else {
            showTaskAlert("Chưa có nhiệm vụ", message: "Nhấn ＋ Thêm để tạo nhiệm vụ thủ công.")
            return
        }
        let lines = taskNames.enumerated().map { index, name in
            "\(completedTasks.indices.contains(index) && completedTasks[index] ? "✓" : "○") \(index + 1). \(name)"
        }
        showTaskAlert("Danh sách nhiệm vụ", message: lines.joined(separator: "\n"))
    }

    @objc private func completeTaskTapped() {
        markCurrentTaskCompleted()
    }

    private func showTaskAlert(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default))
        window?.rootViewController?.present(alert, animated: true)
    }

    @objc private func startTapped() {
        guard taskNames.isEmpty == false else {
            sessionActive = true
            appendLog("Bắt đầu phiên — chưa có nhiệm vụ nào được thêm")
            refresh()
            return
        }

        guard currentTaskIndex < taskNames.count else {
            statusLabel.text = "Danh sách nhiệm vụ đã hoàn tất"
            appendLog("Không còn nhiệm vụ để tiếp tục")
            return
        }

        sessionActive = true
        appendLog("Tiếp tục tại nhiệm vụ \(currentTaskIndex + 1)/\(taskNames.count): \(taskNames[currentTaskIndex])")
        refresh()
    }

    @objc private func stopTapped() {
        sessionActive = false
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
        guard let parent = superview else { return }
        switch gesture.state {
        case .began:
            moveStartFrame = frame
            moveStartedTucked = isTuckedToEdge
        case .changed:
            let delta = gesture.translation(in: parent)
            var next = frame
            next.origin.x += delta.x
            next.origin.y += delta.y
            next.origin.y = max(0, min(next.origin.y, max(0, parent.bounds.height - next.height)))
            if moveStartedTucked {
                next.origin.x = max(-next.width + 24, min(next.origin.x, parent.bounds.width - 24))
            } else {
                next.origin.x = max(0, min(next.origin.x, max(0, parent.bounds.width - next.width)))
            }
            frame = next
            gesture.setTranslation(.zero, in: parent)
        case .ended, .cancelled, .failed:
            if moveStartedTucked {
                if abs(frame.minX - moveStartFrame.minX) > 40 {
                    isTuckedToEdge = false
                    let restoredWidth = expandedFrame.width > 0 ? expandedFrame.width : 300
                    let restoredHeight = expandedFrame.height > 0 ? expandedFrame.height : 480
                    let y = max(0, min(frame.minY, parent.bounds.height - restoredHeight))
                    frame = CGRect(x: tuckedToLeft ? 12 : max(12, parent.bounds.width - restoredWidth - 12),
                                   y: y, width: restoredWidth, height: restoredHeight)
                    layer.cornerRadius = 24
                    setExpandedContentHidden(false)
                } else {
                    frame.origin.x = tuckedToLeft ? -frame.width + 24 : parent.bounds.width - 24
                }
            } else {
                let edgeDistance = min(frame.minX, parent.bounds.width - frame.maxX)
                let draggedHorizontally = abs(frame.minX - moveStartFrame.minX) > 24
                if draggedHorizontally && edgeDistance <= 12 {
                    tuckToEdge(left: frame.midX < parent.bounds.midX, in: parent)
                }
            }
            moveStartedTucked = false
        default:
            break
        }
    }

    private func setExpandedContentHidden(_ hidden: Bool) {
        [headerView, statusLabel, progressLabel, progressView, startButton, stopButton,
         addTaskButton, listTasksButton, completeTaskButton, logTitleLabel, logView,
         copyButton, clearButton, resizeHandle].forEach { $0.isHidden = hidden }
        tuckHandle.isHidden = !hidden
    }

    private func tuckToEdge(left: Bool, in parent: UIView) {
        expandedFrame = frame
        tuckedToLeft = left
        isTuckedToEdge = true
        let size: CGFloat = 56
        let targetX = left ? -size + 24 : parent.bounds.width - 24
        let targetY = max(0, min(frame.minY, parent.bounds.height - size))
        setExpandedContentHidden(true)
        UIView.animate(withDuration: 0.28, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.frame = CGRect(x: targetX, y: targetY, width: size, height: size)
            self.layer.cornerRadius = 18
        }
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
            expandedFrame = frame
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        true
    }
}
