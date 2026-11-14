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
    private var taskDetails: [String] = []
    private var taskURLs: [String] = []
    private var observedPageURLs: [String] = []
    private var sessionActive = false
    private var lastObservedPageURL: String?
    private var lastObservedScreenSignature: String?

    private var logs: [String] = []
    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero
    private var moveStartFrame = CGRect.zero
    private var moveStartedTucked = false
    private var isTuckedToEdge = false
    private var tuckedToLeft = false
    private var expandedFrame = CGRect.zero
    private var observerTimer: DispatchSourceTimer?
    private var didLogObserverDiagnostics = false
    private var automationEnabled = false
    private enum AutomationPhase { case selecting, waitingForPage, scrolling, returning }
    private var automationPhase: AutomationPhase = .selecting
    private var automationTaskIndex: Int?
    private var automationStartedAt: Date?
    private var automationDuration: TimeInterval = 15
    private var attemptedTaskIndices = Set<Int>()
    private var automationScanCursor = 0
    private var lastAutomationLogIndex: Int?
    private var visibleWebMissionTitles: [String] = []

    private let stateKey = "TPIOSCaoXuObservedState"
    private let logKey = "TPIOSCaoXuLogs"

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadState()
        setup()
        refresh()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        sessionActive = true
        startObserver()
        appendLog("Tự động bắt đầu ghi nhận khi mở Cào xu; chờ anh bấm Bắt đầu để chạy nhiệm vụ")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopObserver()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appWillResignActive() {
        guard sessionActive else { return }
        stopObserver()
        appendLog("Lazada tạm mất trạng thái hoạt động; đã dừng quan sát và giữ tiến trình")
    }

    @objc private func appDidBecomeActive() {
        guard sessionActive, observerTimer == nil else { return }
        appendLog("Lazada hoạt động trở lại; tiếp tục quan sát")
        startObserver()
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
            taskDetails = state["details"] as? [String] ?? []
            taskURLs = state["urls"] as? [String] ?? []
            observedPageURLs = state["pageURLs"] as? [String] ?? []
        }
        if completedTasks.count < taskNames.count {
            completedTasks.append(contentsOf: repeatElement(false, count: taskNames.count - completedTasks.count))
        } else if completedTasks.count > taskNames.count {
            completedTasks = Array(completedTasks.prefix(taskNames.count))
        }
        // Remove known UI headings/CTA labels and product metadata left by earlier observer versions.
        let validIndices = taskNames.indices.filter { isLikelyTaskName(taskNames[$0]) }
        if validIndices.count != taskNames.count {
            let oldDetails = taskDetails
            let oldURLs = taskURLs
            taskNames = validIndices.map { taskNames[$0] }
            completedTasks = validIndices.map { completedTasks[$0] }
            taskDetails = validIndices.map { $0 < oldDetails.count ? oldDetails[$0] : "" }
            taskURLs = validIndices.map { $0 < oldURLs.count ? oldURLs[$0] : "" }
        }
        if taskDetails.count < taskNames.count {
            taskDetails.append(contentsOf: repeatElement("", count: taskNames.count - taskDetails.count))
        } else if taskDetails.count > taskNames.count {
            taskDetails = Array(taskDetails.prefix(taskNames.count))
        }
        if taskURLs.count < taskNames.count {
            taskURLs.append(contentsOf: repeatElement("", count: taskNames.count - taskURLs.count))
        } else if taskURLs.count > taskNames.count {
            taskURLs = Array(taskURLs.prefix(taskNames.count))
        }
        logs = defaults.stringArray(forKey: logKey) ?? []
        sessionActive = false
    }

    private func saveState() {
        let state: [String: Any] = [
            "tasks": taskNames, "completed": completedTasks,
            "details": taskDetails, "urls": taskURLs,
            "pageURLs": observedPageURLs
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
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
        saveState()
        refreshLog()
    }

    private func refresh() {
        let total = taskNames.count
        let completed = completedTasks.filter { $0 }.count
        progressLabel.text = "\(completed)/\(total) hoàn thành · còn \(max(0, total - completed))"
        startCaption.text = sessionActive ? "Đang theo dõi" : "Tiếp tục"
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
        guard !automationEnabled else { return }
        sessionActive = true
        automationEnabled = true
        automationPhase = .selecting
        automationTaskIndex = nil
        automationScanCursor = 0
        lastAutomationLogIndex = nil
        didLogObserverDiagnostics = false
        appendLog("Bật tự động Cào xu; ưu tiên nhiệm vụ lướt có thời lượng xác định")
        startObserver()
        refresh()
    }

    @objc private func stopTapped() {
        sessionActive = false
        automationEnabled = false
        stopObserver()
        appendLog("Đã tạm dừng tự động; tiến độ được giữ lại")
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
        guard sessionActive else { return }
        guard let root = visibleAppRoot() else {
            if !didLogObserverDiagnostics {
                didLogObserverDiagnostics = true
                appendLog("Chẩn đoán: không tìm thấy cửa sổ app đang hiển thị")
            }
            return
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let isLazadaProcess = bundleID.lowercased().contains("lazada")
        let webViews = findWebViews(in: root)
        let lazadaWebView = webViews.first {
            $0.window != nil && !$0.isHidden && $0.alpha > 0.01 &&
            ($0.url?.host?.lowercased().contains("lazada") == true)
        }
        let pageURL = lazadaWebView.flatMap { sanitizedPageURL($0.url) }
        let isLazadaTarget = isLazadaProcess || lazadaWebView != nil

        var lines: [String] = []
        var nativeViewCount = 0
        var accessibilityCount = 0
        if isLazadaProcess {
            let snapshot = nativeVisibleLines(in: root)
            lines = snapshot.lines
            nativeViewCount = snapshot.viewCount
            accessibilityCount = snapshot.accessibilityCount
        }

        if !didLogObserverDiagnostics {
            didLogObserverDiagnostics = true
            let windowName = root.window.map { NSStringFromClass(type(of: $0)) } ?? "none"
            let rootName = NSStringFromClass(type(of: root))
            appendLog("Chẩn đoán: app=\(bundleID) window=\(windowName) root=\(rootName) nativeViews=\(nativeViewCount) accessibility=\(accessibilityCount) webViews=\(webViews.count) Lazada=\(isLazadaTarget ? "yes" : "no")")
        }

        // Không đọc nội dung app khác: Cào xu chỉ hoạt động trong tiến trình Lazada
        // hoặc WebView đang mở host Lazada. Sale Shopee không bị quét ở đây.
        guard isLazadaTarget else { return }

        guard let webView = lazadaWebView else {
            processObservedLines(lines, pageURL: pageURL)
            if isLazadaProcess { driveNativeAutomation(in: root) }
            return
        }

        let script = """
        (function() {
          const visible = e => {
            const r = e.getBoundingClientRect(), s = getComputedStyle(e);
            return r.width > 0 && r.height > 0 &&
              r.bottom > 0 && r.right > 0 &&
              r.top < window.innerHeight && r.left < window.innerWidth &&
              s.display !== 'none' && s.visibility !== 'hidden';
          };
          const missionTitles = Array.from(document.querySelectorAll('.mission-item-center'))
            .filter(e => visible(e) && !e.parentElement?.closest('.mission-item-center'))
            .map(card => {
              const raw = (card.innerText || card.textContent || '').replace(/\\s+/g, ' ').trim();
              const progress = raw.match(/\\b(\\d+)\\s*\\/\\s*(\\d+)\\b/);
              if (progress && Number(progress[1]) >= Number(progress[2])) return '';
              return raw.replace(/\\b\\d+\\s*\\/\\s*\\d+\\b[\\s\\S]*$/, '')
                .replace(/\\b(làm ngay|thực hiện|đi ngay|xem ngay|bắt đầu|tham gia|tìm kiếm)\\b/gi, ' ')
                .replace(/\\s+/g, ' ').trim();
            })
            .filter(t => t.length >= 12 && t.length <= 140);
          const bodyLines = (document.body ? document.body.innerText : '').split(/\\n+/);
          const leafLines = Array.from(document.querySelectorAll('body *'))
            .filter(e => e.children.length === 0 && visible(e))
            .map(e => (e.innerText || e.textContent || '').trim());
          return {
            lines: bodyLines.concat(leafLines)
              .map(t => t.trim())
              .filter(t => t.length > 1 && t.length < 180)
              .slice(0, 700),
            missionTitles: missionTitles
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, self.sessionActive else { return }
            if let payload = result as? [String: Any] {
                if let webLines = payload["lines"] as? [String] {
                    lines.append(contentsOf: webLines)
                }
                self.visibleWebMissionTitles = payload["missionTitles"] as? [String] ?? []
            } else if let webLines = result as? [String] {
                lines.append(contentsOf: webLines)
                self.visibleWebMissionTitles = []
            }
            self.processObservedLines(lines, pageURL: pageURL)
            self.driveAutomation(in: webView)
        }
    }

    private func driveNativeAutomation(in root: UIView) {
        guard sessionActive, automationEnabled else { return }
        guard let window = root.window else { return }

        if automationTaskIndex == nil {
            let count = taskNames.count
            guard count > 0 else { return }
            let next = (0..<count).map { (automationScanCursor + $0) % count }.first {
                !completedTasks[$0] && !attemptedTaskIndices.contains($0) &&
                taskNames[$0].localizedCaseInsensitiveContains("lướt")
            }
            guard let next else { return }
            automationTaskIndex = next
            let name = taskNames[next]
            automationDuration = min(180, max(5, secondsRequired(in: name + " " + taskDetails[next]) ?? 15))
            automationPhase = .selecting
        }

        guard let index = automationTaskIndex, taskNames.indices.contains(index) else {
            automationTaskIndex = nil
            automationPhase = .selecting
            return
        }
        let taskName = taskNames[index]

        switch automationPhase {
        case .selecting:
            let actionLabels = ["làm ngay", "thực hiện", "đi ngay", "xem ngay", "bắt đầu", "tham gia"]
            var matches: [(UIButton, String)] = []
            func visit(_ view: UIView) {
                guard !view.isHidden, view.alpha > 0.01 else { return }
                if let button = view as? UIButton {
                    let label = normalizedTaskText([button.currentTitle, button.accessibilityLabel].compactMap { $0 }.joined(separator: " "))
                    if actionLabels.contains(where: { label.localizedCaseInsensitiveContains($0) }) {
                        var ancestor: UIView? = button
                        for _ in 0..<7 {
                            guard let card = ancestor else { break }
                            let cardText = nativeText(in: card)
                            if cardText.localizedCaseInsensitiveContains(taskName) {
                                matches.append((button, cardText))
                                break
                            }
                            ancestor = card.superview
                        }
                    }
                }
                view.subviews.forEach(visit)
            }
            visit(root)

            guard matches.count == 1, let button = matches.first?.0,
                  button.window === window, button.bounds.width > 0, button.bounds.height > 0,
                  TPIOSAutoClickEngine.backendAvailable() else {
                if lastAutomationLogIndex != index {
                    lastAutomationLogIndex = index
                    appendLog("Native: chưa tìm thấy duy nhất nút hành động thuộc thẻ nhiệm vụ: \(taskName) · khớp=\(matches.count)")
                }
                return
            }

            let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
            guard TPIOSAutoClickEngine.shared.dispatchTouch(at: point, down: true) else {
                appendLog("Native: HID không gửi được chạm DOWN: \(taskName)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { _ = TPIOSAutoClickEngine.shared.dispatchTouch(at: point, down: false); return }
                let released = TPIOSAutoClickEngine.shared.dispatchTouch(at: point, down: false)
                guard released, self.sessionActive, self.automationEnabled else {
                    self.appendLog("Native: không xác nhận được chạm UP; dừng để tránh kẹt touch")
                    self.automationEnabled = false
                    self.automationPhase = .selecting
                    return
                }
                self.automationPhase = .waitingForPage
                self.automationStartedAt = Date()
                self.lastAutomationLogIndex = nil
                self.appendLog("Native: đã chạm nút mở nhiệm vụ: \(taskName)")
            }

        case .waitingForPage:
            guard let started = automationStartedAt, Date().timeIntervalSince(started) >= 2 else { return }
            guard let scrollView = findScrollableView(in: root) else {
                if lastAutomationLogIndex != index {
                    lastAutomationLogIndex = index
                    appendLog("Native: đã mở nhiệm vụ nhưng chưa tìm thấy vùng cuộn; giữ tiến độ, không đánh dấu hoàn thành")
                }
                automationStartedAt = Date()
                return
            }
            nativeAutomationScrollView = scrollView
            automationPhase = .scrolling
            automationStartedAt = Date()
            appendLog("Native: bắt đầu cuộn nhiệm vụ trong \(Int(automationDuration)) giây: \(taskName)")

        case .scrolling:
            guard let started = automationStartedAt else { return }
            if Date().timeIntervalSince(started) >= automationDuration {
                automationPhase = .returning
                automationStartedAt = Date()
                appendLog("Native: đã đủ thời lượng cuộn; tìm nút quay lại danh sách nhiệm vụ")
            } else if let scrollView = nativeAutomationScrollView, scrollView.window === window {
                let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                let nextY = min(maxY, scrollView.contentOffset.y + max(220, scrollView.bounds.height * 0.72))
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: nextY), animated: true)
            } else {
                appendLog("Native: vùng cuộn không còn hợp lệ; dừng nhiệm vụ để giữ an toàn")
                automationPhase = .selecting
                automationTaskIndex = nil
                nativeAutomationScrollView = nil
            }

        case .returning:
            let backLabels = ["quay lại", "back", "trở về"]
            let buttons = allButtons(in: root).filter { button in
                let label = normalizedTaskText([button.currentTitle, button.accessibilityLabel].compactMap { $0 }.joined(separator: " ")).lowercased()
                return backLabels.contains(where: { label == $0 || label.contains($0) })
            }
            guard buttons.count == 1, let button = buttons.first else {
                if lastAutomationLogIndex != index {
                    lastAutomationLogIndex = index
                    appendLog("Native: không tìm thấy duy nhất nút quay lại; chưa xác nhận kết thúc nhiệm vụ")
                }
                return
            }
            let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
            guard TPIOSAutoClickEngine.shared.dispatchTouch(at: point, down: true) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                let released = TPIOSAutoClickEngine.shared.dispatchTouch(at: point, down: false)
                guard let self, released, self.sessionActive, self.automationEnabled else { return }
                self.attemptedTaskIndices.insert(index)
                self.automationScanCursor = (index + 1) % max(1, self.taskNames.count)
                self.automationTaskIndex = nil
                self.automationStartedAt = nil
                self.nativeAutomationScrollView = nil
                self.automationPhase = .selecting
                self.lastAutomationLogIndex = nil
                self.appendLog("Native: đã cuộn đủ thời lượng và chạm quay lại; chờ Lazada xác nhận: \(taskName)")
            }
        }
    }

    private weak var nativeAutomationScrollView: UIScrollView?

    private func nativeText(in view: UIView) -> String {
        var values: [String] = []
        func collect(_ node: UIView) {
            guard !node.isHidden, node.alpha > 0.01 else { return }
            if let label = node as? UILabel, let text = label.text, !text.isEmpty { values.append(text) }
            if let button = node as? UIButton {
                if let title = button.currentTitle, !title.isEmpty { values.append(title) }
                if let label = button.accessibilityLabel, !label.isEmpty { values.append(label) }
            }
            if let text = node.accessibilityLabel, !text.isEmpty { values.append(text) }
            node.subviews.forEach(collect)
        }
        collect(view)
        return values.joined(separator: " ").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func allButtons(in root: UIView) -> [UIButton] {
        var result: [UIButton] = []
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let button = view as? UIButton, button.isEnabled, button.window != nil { result.append(button) }
            view.subviews.forEach(visit)
        }
        visit(root)
        return result
    }

    private func findScrollableView(in root: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let scroll = view as? UIScrollView,
               scroll.contentSize.height > scroll.bounds.height + 30,
               scroll.bounds.width > 100, scroll.bounds.height > 100 {
                candidates.append(scroll)
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return candidates.max { ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height) }
    }

    private func driveAutomation(in webView: WKWebView) {
        guard sessionActive, automationEnabled else { return }

        if automationTaskIndex == nil {
            let count = taskNames.count
            let visibleKeys = Set(visibleWebMissionTitles.map {
                normalizedTaskText($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            })
            let next = (0..<count).map { (automationScanCursor + $0) % count }.first {
                let key = normalizedTaskText(taskNames[$0])
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                return !completedTasks[$0] && !attemptedTaskIndices.contains($0) &&
                    visibleKeys.contains(key) && taskNames[$0].localizedCaseInsensitiveContains("lướt")
            }
            guard let next else {
                if lastAutomationLogIndex != -1 {
                    lastAutomationLogIndex = -1
                    appendLog("WebView: không có nhiệm vụ lướt đang hiển thị/chưa hoàn thành trong .mission-item-center; bỏ qua tên cũ đã lưu")
                }
                return
            }
            automationTaskIndex = next
            let name = taskNames[next]
            let duration = secondsRequired(in: name + " " + taskDetails[next])
            automationDuration = min(180, max(5, duration ?? 15))
            automationPhase = .selecting
        }

        guard let index = automationTaskIndex, taskNames.indices.contains(index) else {
            automationTaskIndex = nil
            automationPhase = .selecting
            return
        }

        let taskName = taskNames[index]
        switch automationPhase {
        case .selecting:
            guard let encoded = try? JSONSerialization.data(withJSONObject: [taskName]),
                  let json = String(data: encoded, encoding: .utf8) else { return }
            let script = """
            (function(){
              const title = \(json)[0].normalize('NFC').toLowerCase();
              const norm = s => (s || '').replace(/\\s+/g,' ').trim().normalize('NFC').toLowerCase();
              const visible = e => {
                const r=e.getBoundingClientRect(),s=getComputedStyle(e);
                return r.width>0&&r.height>0&&r.bottom>0&&r.right>0&&r.top<innerHeight&&r.left<innerWidth&&s.display!=='none'&&s.visibility!=='hidden';
              };
              const center = e => {
                const r=e.getBoundingClientRect();
                return {status:'ready',x:r.left+r.width/2,y:r.top+r.height/2};
              };
              const cards = Array.from(document.querySelectorAll('.mission-item-center'))
                .filter(e => visible(e) && !e.parentElement?.closest('.mission-item-center'));
              if (cards.length) {
                const matches = cards.filter(card => {
                  const raw = norm(card.innerText || card.textContent);
                  const cardTitle = raw.replace(/\\b\\d+\\s*\\/\\s*\\d+\\b[\\s\\S]*$/, '')
                    .replace(/\\b(làm ngay|thực hiện|đi ngay|xem ngay|bắt đầu|tham gia|tìm kiếm)\\b/gi, ' ')
                    .replace(/\\s+/g, ' ').trim();
                  return cardTitle === title || cardTitle.includes(title) || title.includes(cardTitle);
                });
                if (!matches.length) return {status:'mission_not_found'};
                if (matches.length !== 1) return {status:'mission_ambiguous'};
                const card = matches[0];
                const go = card.querySelector('.mission-item-btn-go');
                if (go && visible(go) && norm(go.innerText || go.textContent) !== 'tìm kiếm') return center(go);
                const action = Array.from(card.querySelectorAll('a,button,[role="button"],[onclick]'))
                  .find(e => visible(e) && /làm ngay|thực hiện|đi ngay|xem ngay|tham gia|bắt đầu/i.test(norm(e.innerText || e.textContent)));
                return action ? center(action) : {status:'mission_action_not_found'};
              }
              const clickable = 'a,button,[role="button"],[onclick]';
              const titleNodes = Array.from(document.querySelectorAll('body *')).filter(e => {
                if (!visible(e)) return false;
                const t = norm(e.innerText || e.textContent);
                return t && t.includes(title) && t.length <= title.length + 100;
              }).sort((a,b) => (a.innerText || a.textContent || '').length - (b.innerText || b.textContent || '').length);
              if (!titleNodes.length) return {status:'title_not_found'};
              const titleNode = titleNodes[0];
              const direct = titleNode.closest(clickable);
              if (direct && visible(direct)) return center(direct);
              let card = titleNode;
              for (let depth=0; depth<6 && card; depth++, card=card.parentElement) {
                const actions = Array.from(card.querySelectorAll(clickable)).filter(visible);
                const action = actions.find(e => /làm ngay|thực hiện|đi ngay|xem ngay|tham gia|bắt đầu/i.test(norm(e.innerText || e.textContent)));
                if (action) return center(action);
              }
              return {status:'title_found_no_action'};
            })();
            """
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self, self.sessionActive, self.automationEnabled else { return }
                let payload = result as? [String: Any]
                let clickResult = payload?["status"] as? String ?? "no_result"
                if clickResult == "ready",
                   let x = payload?["x"] as? Double,
                   let y = payload?["y"] as? Double,
                   let window = webView.window,
                   TPIOSAutoClickEngine.backendAvailable() {
                    let webPoint = CGPoint(x: x, y: y)
                    guard webView.bounds.insetBy(dx: 1, dy: 1).contains(webPoint) else {
                        self.appendLog("WebView: tọa độ nút nhiệm vụ nằm ngoài vùng hiển thị; bỏ qua chạm")
                        self.automationTaskIndex = nil
                        self.automationPhase = .selecting
                        return
                    }
                    let windowPoint = webView.convert(webPoint, to: window)
                    guard TPIOSAutoClickEngine.shared.dispatchTouch(at: windowPoint, down: true) else {
                        self.appendLog("WebView: HID không gửi được chạm DOWN: \(taskName)")
                        self.automationTaskIndex = nil
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                        let released = TPIOSAutoClickEngine.shared.dispatchTouch(at: windowPoint, down: false)
                        guard let self else { return }
                        guard released, self.sessionActive, self.automationEnabled else {
                            self.appendLog("WebView: không xác nhận được chạm UP; dừng tự động để tránh kẹt touch")
                            self.automationEnabled = false
                            self.automationPhase = .selecting
                            return
                        }
                        self.automationPhase = .waitingForPage
                        self.automationStartedAt = Date()
                        self.lastAutomationLogIndex = nil
                        self.appendLog("Đã chạm nút nhiệm vụ bằng DOM + HID: \(taskName)")
                    }
                } else {
                    if clickResult == "ready" {
                        self.appendLog("WebView: đã tìm thấy nút nhưng HID chưa sẵn sàng hoặc WebView không còn cửa sổ")
                    } else if self.lastAutomationLogIndex != index {
                        self.lastAutomationLogIndex = index
                        self.appendLog("Chưa mở được nhiệm vụ: \(taskName) · kết quả=\(clickResult)")
                    }
                    self.automationScanCursor = (index + 1) % max(1, self.taskNames.count)
                    self.automationTaskIndex = nil
                    self.automationPhase = .selecting
                }
                if let error { self.appendLog("Lỗi mở nhiệm vụ: \(error.localizedDescription)") }
            }
        case .waitingForPage:
            guard let started = automationStartedAt, Date().timeIntervalSince(started) >= 2 else { return }
            automationPhase = .scrolling
            automationStartedAt = Date()
            appendLog("Bắt đầu lướt nhiệm vụ trong \(Int(automationDuration)) giây: \(taskName)")
        case .scrolling:
            guard let started = automationStartedAt else { return }
            if Date().timeIntervalSince(started) >= automationDuration {
                webView.evaluateJavaScript("window.history.back();") { [weak self] _, _ in
                    guard let self, self.sessionActive, self.automationEnabled else { return }
                    self.automationPhase = .returning
                    self.automationStartedAt = Date()
                    self.appendLog("Đã kết thúc thời gian lướt; quay lại danh sách nhiệm vụ: \(taskName)")
                }
            } else {
                webView.evaluateJavaScript("window.scrollBy({top: Math.max(240, window.innerHeight * 0.72), behavior: 'smooth'});", completionHandler: nil)
            }
        case .returning:
            guard let started = automationStartedAt, Date().timeIntervalSince(started) >= 2 else { return }
            attemptedTaskIndices.insert(index)
            automationScanCursor = (index + 1) % max(1, taskNames.count)
            automationTaskIndex = nil
            automationStartedAt = nil
            automationPhase = .selecting
            lastAutomationLogIndex = nil
            appendLog("Đã chạy xong thao tác lướt; chờ Lazada xác nhận hoàn thành: \(taskName)")
        }
    }

    private func secondsRequired(in text: String) -> TimeInterval? {
        let pattern = #"(?i)(\d{1,3})\s*(giây|giây nữa|seconds?|s)\b"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = text[range].prefix { $0.isNumber }
        return TimeInterval(digits)
    }

    private func sanitizedPageURL(_ url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased(),
              host.contains("lazada") else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        guard let components else { return nil }
        return "\(components.scheme ?? "https")://\(host)\(components.path)"
    }

    private func visibleAppRoot() -> UIView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }

        let appWindow = windows
            .filter {
                $0 !== self.window &&
                !$0.isHidden &&
                $0.alpha > 0.01 &&
                $0.windowLevel == .normal &&
                $0.rootViewController != nil
            }
            .sorted {
                if $0.isKeyWindow != $1.isKeyWindow {
                    return $0.isKeyWindow
                }
                return $0.bounds.width * $0.bounds.height >
                    $1.bounds.width * $1.bounds.height
            }
            .first

        var controller = appWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller?.view ?? appWindow
    }

    private func findWebViews(in view: UIView) -> [WKWebView] {
        var result: [WKWebView] = []
        if let webView = view as? WKWebView { result.append(webView) }
        for child in view.subviews { result.append(contentsOf: findWebViews(in: child)) }
        return result
    }

    private func nativeVisibleLines(in root: UIView) -> (lines: [String], viewCount: Int, accessibilityCount: Int) {
        var result: [String] = []
        var seen = Set<String>()
        var viewCount = 0
        var accessibilityCount = 0

        func append(_ raw: String?) {
            guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.count > 1 else { return }
            let key = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seen.insert(key).inserted { result.append(text) }
        }

        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            viewCount += 1

            if let label = view as? UILabel { append(label.text) }
            if let button = view as? UIButton {
                append(button.currentTitle)
                append(button.accessibilityLabel)
            }
            if let textView = view as? UITextView, !textView.isEditable {
                append(textView.text)
            }
            if !(view is UITextField), !(view is UISearchBar) {
                append(view.accessibilityLabel)
            }

            if let elements = view.accessibilityElements {
                for element in elements {
                    if let accessible = element as? UIAccessibilityElement {
                        accessibilityCount += 1
                        append(accessible.accessibilityLabel)
                    } else if let accessibleView = element as? UIView {
                        accessibilityCount += 1
                        append(accessibleView.accessibilityLabel)
                    }
                }
            }

            for child in view.subviews { visit(child) }
        }

        visit(root)
        return (result, viewCount, accessibilityCount)
    }

    private func normalizedTaskText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Some Lazada views expose the same title twice with no separator.
        text = text.replacingOccurrences(of: #"(.{4,80})\1"#, with: "$1",
                                         options: [.regularExpression, .caseInsensitive])
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func isLikelyTaskName(_ raw: String) -> Bool {
        let name = normalizedTaskText(raw)
        let lower = name.lowercased()
        guard name.count >= 12, name.count <= 140 else { return false }

        let excludedLabels: Set<String> = [
            "nhiệm vụ hôm nay", "nhiệm vụ", "tìm kiếm", "đánh giá",
            "thêm vào giỏ", "check-in ngay", "nhận xu"
        ]
        guard !excludedLabels.contains(lower) else { return false }

        // Exclude seller/product counters such as "200+ đánh giá có hình ảnh".
        let metadataPattern = #"^\d+[\d.,]*\s*\+?\s*(đánh giá|người theo dõi|lượt theo dõi|reviews?|followers?)"#
        if lower.range(of: metadataPattern, options: .regularExpression) != nil { return false }

        // This is a page/category slogan, not an individual task card.
        if lower.hasPrefix("tìm kiếm & xem hot deal") { return false }

        let taskWords = [
            "điểm danh", "livestream", "live", "theo dõi", "xem sản phẩm", "xem 3 sản phẩm",
            "xem video", "chia sẻ", "thêm vào giỏ", "mua hàng", "đánh giá", "tìm kiếm",
            "tìm ", "nhận xu", "check-in", "watch", "share", "visit", "lướt xem",
            "lướt", "siêu tiết kiệm", "vào game", "trò chơi"
        ]
        return taskWords.contains(where: { lower.contains($0) })
    }

    private func processObservedLines(_ rawLines: [String], pageURL: String? = nil) {
        let uniqueLines = rawLines.reduce(into: [String]()) { result, line in
            let normalized = normalizedTaskText(line)
            guard !normalized.isEmpty,
                  !result.contains(where: {
                      $0.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                  }) else { return }
            result.append(normalized)
        }
        let candidateNames = uniqueLines.filter { isLikelyTaskName($0) }
        let screenSignature = uniqueLines.prefix(14).joined(separator: "|")
        let signature = String(screenSignature.hashValue)
        if pageURL != lastObservedPageURL || signature != lastObservedScreenSignature {
            lastObservedPageURL = pageURL
            lastObservedScreenSignature = signature
            if let pageURL, !observedPageURLs.contains(pageURL) {
                observedPageURLs.append(pageURL)
                if observedPageURLs.count > 100 { observedPageURLs.removeFirst(observedPageURLs.count - 100) }
                appendLog("Đã lưu URL trang Lazada: \(pageURL)")
            }
            let pageDescription = pageURL ?? "URL chưa đọc được"
            appendLog("Màn hình thay đổi: \(pageDescription) · text=\(uniqueLines.count) · ứng viên nhiệm vụ=\(candidateNames.count)")
        }

        let doneWords = [
            "đã hoàn thành", "hoàn thành", "đã nhận", "nhận thành công",
            "completed", "claimed", "done"
        ]
        var changed = false
        var seenThisPass = Set<String>()

        for (lineIndex, raw) in uniqueLines.enumerated() {
            let name = normalizedTaskText(raw)
            guard isLikelyTaskName(name) else { continue }
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seenThisPass.insert(key).inserted else { continue }

            if !taskNames.contains(where: {
                normalizedTaskText($0).compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                taskNames.append(name)
                completedTasks.append(false)
                taskDetails.append("")
                taskURLs.append("")
                changed = true
                appendLog("Nhận diện nhiệm vụ trên màn hình: \(name)")
            }

            if let index = taskNames.firstIndex(where: {
                normalizedTaskText($0).compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                let detailLines = uniqueLines.dropFirst(lineIndex + 1)
                    .prefix(while: { !isLikelyTaskName($0) })
                    .prefix(3)
                    .filter {
                        !$0.isEmpty && !$0.lowercased().contains("nhận xu") &&
                        !$0.lowercased().contains("kiếm thêm") && !$0.lowercased().contains("làm ngay")
                    }
                let detail = detailLines.joined(separator: " · ").prefix(240).description
                if !detail.isEmpty && taskDetails[index] != detail {
                    taskDetails[index] = detail
                    changed = true
                    appendLog("Đã lưu hướng dẫn cho nhiệm vụ: \(name)")
                }
                if candidateNames.count == 1, let pageURL, taskURLs[index] != pageURL {
                    taskURLs[index] = pageURL
                    changed = true
                    appendLog("Đã gắn URL trang nhiệm vụ: \(name) → \(pageURL)")
                }
            }

            let lower = raw.lowercased()
            if doneWords.contains(where: { lower.contains($0) }),
               let index = taskNames.firstIndex(where: {
                   normalizedTaskText($0).compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
               }),
               !completedTasks[index] {
                completedTasks[index] = true
                changed = true
                appendLog("Giao diện báo hoàn thành: \(name)")
            }
        }

        // Persist only when the task list or completion state actually changes.
        if changed { saveObservedTasks() }
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
        automationEnabled = false
        saveState()
        onBack?()
    }

    @objc private func closeTapped() {
        stopObserver()
        sessionActive = false
        automationEnabled = false
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
