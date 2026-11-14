import UIKit
import WebKit

final class TPIOSCaoXu: UIView, UIGestureRecognizerDelegate {

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private let headerHeight: CGFloat = 50
    private let minWidth: CGFloat = 220
    private let minHeight: CGFloat = 300

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let startCaption = UILabel()
    private let stopCaption = UILabel()
    private let logTitleLabel = UILabel()
    private let logView = UITextView()
    private let tuckHandle = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let resizeHandle = UILabel()

    private var taskNames: [String] = []
    private var completedTasks: [Bool] = []
    private var sessionActive = false
    private var logs: [String] = []
    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero
    private var moveStartFrame = CGRect.zero
    private var moveStartedTucked = false
    private var isTuckedToEdge = false
    private var tuckedToLeft = false
    private var expandedFrame = CGRect.zero
    private var observerTimer: DispatchSourceTimer?

    private let stateKey = "TPIOSCaoXuObservedState"
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

    deinit {
        stopObserver()
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
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)

        statusLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .center
        addSubview(statusLabel)

        progressLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        progressLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        progressLabel.textAlignment = .center
        addSubview(progressLabel)

        progressView.progressTintColor = UIColor(red: 0.25, green: 0.82, blue: 0.55, alpha: 1)
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.12)
        addSubview(progressView)

        configureRoundAction(startButton, icon: "play.fill",
                             colors: [UIColor(red: 0.36, green: 0.88, blue: 0.55, alpha: 1),
                                      UIColor(red: 0.06, green: 0.52, blue: 0.33, alpha: 1)],
                             action: #selector(startTapped))
        configureRoundAction(stopButton, icon: "pause.fill",
                             colors: [UIColor(red: 1.0, green: 0.48, blue: 0.38, alpha: 1),
                                      UIColor(red: 0.68, green: 0.16, blue: 0.16, alpha: 1)],
                             action: #selector(stopTapped))
        addSubview(startButton)
        addSubview(stopButton)

        startCaption.text = "Bắt đầu"
        stopCaption.text = "Tạm dừng"
        for label in [startCaption, stopCaption] {
            label.textColor = UIColor.white.withAlphaComponent(0.86)
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textAlignment = .center
            addSubview(label)
        }

        logTitleLabel.text = "LOG CÀO XU"
        logTitleLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        logTitleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        addSubview(logTitleLabel)

        logView.backgroundColor = UIColor(red: 0.055, green: 0.065, blue: 0.08, alpha: 1)
        logView.textColor = UIColor.white.withAlphaComponent(0.88)
        logView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        logView.layer.cornerRadius = 10
        logView.isEditable = false
        logView.alwaysBounceVertical = true
        logView.textContainerInset = UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)
        addSubview(logView)

        configureSmallButton(copyButton, title: "Sao chép log", action: #selector(copyTapped))
        configureSmallButton(clearButton, title: "Xóa log", action: #selector(clearTapped))
        addSubview(copyButton)
        addSubview(clearButton)

        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.58)
        resizeHandle.font = .systemFont(ofSize: 18, weight: .medium)
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

    private func configureRoundAction(_ button: UIButton, icon: String, colors: [UIColor], action: Selector) {
        button.setImage(UIImage(systemName: icon), for: .normal)
        button.tintColor = .white
        button.imageView?.contentMode = .scaleAspectFit
        button.addTarget(self, action: action, for: .touchUpInside)
        TPIOSPanelStyle.applyGradientFill(to: button, colors: colors, cornerRadius: 24)
    }

    private func configureSmallButton(_ button: UIButton, title: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.88), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 10, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        button.layer.cornerRadius = 8
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(bounds.width / 240, bounds.height / 350)
        let header = 50 * scale
        let inset = 12 * scale
        let width = max(0, bounds.width - inset * 2)

        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: header)
        backButton.frame = CGRect(x: 3 * scale, y: 2 * scale, width: 40 * scale, height: 44 * scale)
        closeButton.frame = CGRect(x: bounds.width - 43 * scale, y: 2 * scale, width: 40 * scale, height: 44 * scale)
        titleLabel.frame = CGRect(x: 44 * scale, y: 0, width: max(0, bounds.width - 88 * scale), height: header)

        statusLabel.frame = CGRect(x: inset, y: header + 7 * scale, width: width, height: 32 * scale)
        progressLabel.frame = CGRect(x: inset, y: header + 40 * scale, width: width, height: 17 * scale)
        progressView.frame = CGRect(x: inset, y: header + 60 * scale, width: width, height: 4 * scale)

        let buttonSize = min(46 * scale, max(34, width * 0.23))
        let buttonY = header + 72 * scale
        let leftX = bounds.midX - buttonSize - 12 * scale
        let rightX = bounds.midX + 12 * scale
        startButton.frame = CGRect(x: leftX, y: buttonY, width: buttonSize, height: buttonSize)
        stopButton.frame = CGRect(x: rightX, y: buttonY, width: buttonSize, height: buttonSize)
        startButton.layer.cornerRadius = buttonSize / 2
        stopButton.layer.cornerRadius = buttonSize / 2
        TPIOSPanelStyle.syncFrames(in: startButton)
        TPIOSPanelStyle.syncFrames(in: stopButton)
        startCaption.frame = CGRect(x: leftX - 5, y: buttonY + buttonSize + 2 * scale, width: buttonSize + 10, height: 14 * scale)
        stopCaption.frame = CGRect(x: rightX - 5, y: buttonY + buttonSize + 2 * scale, width: buttonSize + 10, height: 14 * scale)

        let logY = buttonY + buttonSize + 22 * scale
        logTitleLabel.frame = CGRect(x: inset, y: logY, width: width, height: 16 * scale)
        let footerY = bounds.height - 40 * scale
        copyButton.frame = CGRect(x: inset, y: footerY, width: (width - 6 * scale) / 2, height: 30 * scale)
        clearButton.frame = CGRect(x: inset + (width + 6 * scale) / 2, y: footerY, width: (width - 6 * scale) / 2, height: 30 * scale)
        logView.frame = CGRect(x: inset, y: logY + 18 * scale, width: width,
                               height: max(20, footerY - logY - 22 * scale))
        resizeHandle.frame = CGRect(x: bounds.width - 36 * scale, y: bounds.height - 36 * scale,
                                    width: 34 * scale, height: 34 * scale)
        resizeHandle.font = .systemFont(ofSize: 18 * scale, weight: .medium)
        tuckHandle.frame = bounds
    }

    private func loadState() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: stateKey),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            taskNames = state["tasks"] as? [String] ?? []
            completedTasks = state["completed"] as? [Bool] ?? []
        }
        if completedTasks.count < taskNames.count {
            completedTasks.append(contentsOf: repeatElement(false, count: taskNames.count - completedTasks.count))
        } else if completedTasks.count > taskNames.count {
            completedTasks = Array(completedTasks.prefix(taskNames.count))
        }
        logs = defaults.stringArray(forKey: logKey) ?? []
        sessionActive = false
    }

    private func saveState() {
        let state: [String: Any] = ["tasks": taskNames, "completed": completedTasks]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
        UserDefaults.standard.set(logs, forKey: logKey)
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.append("[\(formatter.string(from: Date()))] \(message)")
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
        saveState()
        refreshLog()
    }

    private func refresh() {
        let total = taskNames.count
        let completed = completedTasks.filter { $0 }.count
        progressLabel.text = "\(completed)/\(total) nhiệm vụ ghi nhận"
        progressView.progress = total == 0 ? 0 : Float(completed) / Float(total)
        if !sessionActive {
            statusLabel.text = total == 0 ? "Chưa ghi nhận nhiệm vụ · Mở trang nhiệm vụ Lazada" : "Đã tạm dừng · \(total) nhiệm vụ đã nhận diện"
        } else {
            statusLabel.text = total == 0 ? "Đang quan sát màn hình Lazada…" : "Đang quan sát · \(total - completed) nhiệm vụ còn lại"
        }
        refreshLog()
    }

    private func refreshLog() {
        logView.text = logs.joined(separator: "\n")
        if !logs.isEmpty {
            logView.scrollRangeToVisible(NSRange(location: max(0, logView.text.count - 1), length: 1))
        }
    }

    private func saveObservedTasks() {
        saveState()
        refresh()
    }

    @objc private func startTapped() {
        guard !sessionActive else { return }
        sessionActive = true
        appendLog("Bắt đầu quan sát giao diện Lazada — không tự thao tác")
        startObserver()
        refresh()
    }

    @objc private func stopTapped() {
        sessionActive = false
        stopObserver()
        appendLog("Đã tạm dừng quan sát; tiến độ được giữ lại")
        refresh()
    }

    private func startObserver() {
        stopObserver()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 2.0, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.observeVisibleTasks() }
        observerTimer = timer
        timer.resume()
    }

    private func stopObserver() {
        observerTimer?.setEventHandler {}
        observerTimer?.cancel()
        observerTimer = nil
    }

    private func observeVisibleTasks() {
        guard sessionActive, let root = visibleAppRoot() else { return }
        let isLazadaProcess = (Bundle.main.bundleIdentifier ?? "").lowercased().contains("lazada")
        let webViews = findWebViews(in: root)
        let lazadaWebView = webViews.first {
            $0.window != nil && !$0.isHidden && $0.alpha > 0.01 &&
            ($0.url?.host?.lowercased().contains("lazada") == true)
        }

        // Không đọc nội dung app khác: Cào xu chỉ hoạt động trong tiến trình Lazada
        // hoặc WebView đang mở host Lazada. Sale Shopee không bị quét ở đây.
        guard isLazadaProcess || lazadaWebView != nil else { return }
        var lines = isLazadaProcess ? nativeVisibleLines(in: root) : []

        guard let webView = lazadaWebView else {
            processObservedLines(lines)
            return
        }

        let script = """
        (function() {
          const visible = e => {
            const r = e.getBoundingClientRect(), s = getComputedStyle(e);
            return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden';
          };
          const bodyLines = (document.body ? document.body.innerText : '').split(/\\n+/);
          const leafLines = Array.from(document.querySelectorAll('body *'))
            .filter(e => e.children.length === 0 && visible(e))
            .map(e => (e.innerText || e.textContent || '').trim());
          return bodyLines.concat(leafLines)
            .map(t => t.trim())
            .filter(t => t.length > 1 && t.length < 180)
            .slice(0, 700);
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, self.sessionActive else { return }
            if let webLines = result as? [String] {
                lines.append(contentsOf: webLines)
            }
            self.processObservedLines(lines)
        }
    }

    private func visibleAppRoot() -> UIView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
        let appWindow = windows.first { $0 !== self.window && !$0.isHidden }
        var controller = appWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller?.view ?? appWindow
    }

    private func findWebViews(in view: UIView) -> [WKWebView] {
        var result: [WKWebView] = []
        if let webView = view as? WKWebView { result.append(webView) }
        for child in view.subviews { result.append(contentsOf: findWebViews(in: child)) }
        return result
    }

    private func nativeVisibleLines(in root: UIView) -> [String] {
        var result: [String] = []
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let label = view as? UILabel, let text = label.text { result.append(text) }
            if let button = view as? UIButton, let text = button.currentTitle { result.append(text) }
            if let textView = view as? UITextView, !textView.text.isEmpty { result.append(textView.text) }
            for child in view.subviews { visit(child) }
        }
        visit(root)
        return result
    }

    private func processObservedLines(_ rawLines: [String]) {
        let taskWords = ["điểm danh", "livestream", "live", "theo dõi", "xem sản phẩm", "xem video",
                         "chia sẻ", "thêm vào giỏ", "mua hàng", "đánh giá", "tìm kiếm", "nhận xu",
                         "nhiệm vụ", "follow", "check-in", "watch", "share", "visit"]
        let doneWords = ["đã hoàn thành", "hoàn thành", "đã nhận", "nhận thành công", "completed", "claimed", "done"]

        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.count >= 5, line.count <= 180 else { continue }
            let lower = line.lowercased()
            guard taskWords.contains(where: { lower.contains($0) }) else { continue }

            let name = line
                .replacingOccurrences(of: "Đã hoàn thành", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Hoàn thành", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "Đã nhận", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 4 else { continue }

            if !taskNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                taskNames.append(name)
                completedTasks.append(false)
                appendLog("Nhận diện nhiệm vụ trên màn hình: \(name)")
            }

            if doneWords.contains(where: { lower.contains($0) }),
               let index = taskNames.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
               !completedTasks[index] {
                completedTasks[index] = true
                appendLog("Giao diện báo hoàn thành: \(name)")
            }
        }
        saveObservedTasks()
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
        stopObserver()
        sessionActive = false
        saveState()
        onBack?()
    }

    @objc private func closeTapped() {
        stopObserver()
        sessionActive = false
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
                    let restoredWidth = expandedFrame.width > 0 ? expandedFrame.width : 280
                    let restoredHeight = expandedFrame.height > 0 ? expandedFrame.height : 420
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
         startCaption, stopCaption, logTitleLabel, logView, copyButton, clearButton, resizeHandle].forEach {
            $0.isHidden = hidden
        }
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
