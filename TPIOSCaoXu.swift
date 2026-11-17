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
    private var checkInPageURL: String?
    private var missionsPageURL: String?
    private var lastMissionEntryPromptURL: String?
    private var lastMissionEntryTapURL: String?
    private var missionEntryTapStartedAt: Date?
    private var missionEntryTapAttempts = 0
    private var missionEntryTapFailureLogged = false
    private var missionEntryNotBefore: Date?
    private var lastCheckInTapURL: String?
    private var checkInTapStartedAt: Date?
    private var sessionActive = false
    private var lastObservedPageURL: String?
    private var lastObservedScreenSignature: String?
    private var lastDOMDiagnosticSignature: String?
    private var lastNativeDiagnosticSignature: String?

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
    private var automationEnteredTaskPage = false
    private var automationDuration: TimeInterval = 15
    private var attemptedTaskIndices = Set<Int>()
    private var automationScanCursor = 0
    private var lastAutomationLogIndex: Int?
    private var lastClaimScanSignature: String?
    private var claimRetryBlockedTitles = Set<String>()
    private var taskLookupFailures = [String: Int]()
    private var lastBottomScanSignature: String?
    private var bottomScanCount = 0
    private var visibleWebMissionTitles: [String] = []
    private var collectedMissionNames: [String] = []
    private var hasCurrentMissionSnapshot = false

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
        appendLog("Đang quan sát Lazada; chờ anh bấm Bắt đầu để chạy nhiệm vụ")
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
        sessionActive = false
        automationEnabled = false
        stopObserver()
        resetAutomationPosition()
        refresh()
        appendLog("Lazada mất trạng thái foreground; đã tạm dừng và giữ tiến độ")
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

        logTitleLabel.text = "LOG CHẠM ĐIỂM DANH / NHẬN XU"
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
            checkInPageURL = state["checkInPageURL"] as? String
            missionsPageURL = state["missionsPageURL"] as? String
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
            "pageURLs": observedPageURLs,
            "checkInPageURL": checkInPageURL ?? "",
            "missionsPageURL": missionsPageURL ?? ""
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
        progressLabel.text = hasCurrentMissionSnapshot
            ? "\(completed)/\(total) hoàn thành · còn \(max(0, total - completed))"
            : "Chờ đồng bộ danh sách nhiệm vụ Lazada"
        startCaption.text = automationEnabled ? "Đang chạy" : (sessionActive ? "Bắt đầu" : "Tiếp tục")
        progressView.progress = !hasCurrentMissionSnapshot || total == 0 ? 0 : Float(completed) / Float(total)
        if !sessionActive {
            statusLabel.text = "Đã tạm dừng · tiến độ đã lưu"
        } else if automationEnabled {
            statusLabel.text = hasCurrentMissionSnapshot && total > 0
                ? "Đang tự động · \(total - completed) nhiệm vụ còn lại"
                : "Đang chạy · chờ danh sách nhiệm vụ Lazada"
        } else {
            statusLabel.text = "Đang quan sát Lazada · chờ bấm Bắt đầu"
        }
        refreshLog()
    }

    private func refreshLog() {
        let visibleLogs = logs.filter { $0.contains("[CHẠM TAY]") }
        logView.text = visibleLogs.joined(separator: "\n")
        if !visibleLogs.isEmpty {
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
        attemptedTaskIndices.removeAll()
        claimRetryBlockedTitles.removeAll()
        taskLookupFailures.removeAll()
        lastClaimScanSignature = nil
        lastBottomScanSignature = nil
        bottomScanCount = 0
        automationScanCursor = 0
        resetAutomationPosition()
        missionEntryNotBefore = Date().addingTimeInterval(2)
        lastCheckInTapURL = nil
        checkInTapStartedAt = nil
        lastAutomationLogIndex = nil
        didLogObserverDiagnostics = false
        appendLog("Bật tự động Cào xu; xử lý nhiệm vụ theo danh sách Lazada")
        startObserver()
        refresh()
    }

    @objc private func stopTapped() {
        sessionActive = false
        automationEnabled = false
        stopObserver()
        resetAutomationPosition()
        appendLog("Đã tạm dừng tự động; tiến độ đã xác nhận được giữ lại")
        refresh()
    }

    private func resetAutomationPosition() {
        automationPhase = .selecting
        automationTaskIndex = nil
        automationStartedAt = nil
        nativeAutomationScrollView = nil
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
            if isLazadaProcess {
                let diagnostic = nativeDiagnostic(in: root)
                let signature = String(diagnostic.hashValue)
                if !diagnostic.isEmpty, signature != lastNativeDiagnosticSignature {
                    lastNativeDiagnosticSignature = signature
                    appendLog("Native UI: " + diagnostic)
                }
                driveNativeAutomation(in: root)
            }
            return
        }

        let script = """
        (function() {
          const normTap = s => (s || '').replace(/\\s+/g, ' ').trim().normalize('NFC').toLocaleLowerCase();
          if (!window.__tpiManualTargetTapListener) {
            window.__tpiManualTargetTapListener = true;
            window.__tpiManualTargetTaps = [];
            document.addEventListener('click', event => {
              if (!event.isTrusted || Date.now() < (window.__tpiAutoTouchUntil || 0)) return;
              const path = event.composedPath ? event.composedPath() : [event.target];
              const elements = path.filter(node => node instanceof Element);
              const matches = [];
              for (const element of elements) {
                const label = normTap(element.innerText || element.textContent ||
                  element.getAttribute('aria-label') || element.getAttribute('title'));
                const kind = /^điểm danh(?:\\s+ngay)?$/.test(label) ? 'Điểm danh' :
                  /^nhận(?:\\s+xu)?$/.test(label) ? 'Nhận xu' : '';
                if (kind) matches.push({element, label, kind});
              }
              if (!matches.length) return;
              matches.sort((a, b) => a.label.length - b.label.length);
              const {element, label, kind} = matches[0];
              const describe = node => {
                const cls = typeof node.className === 'string' ? node.className.trim().replace(/\\s+/g, '.').slice(0, 140) : '';
                return node.tagName.toLowerCase() + (node.id ? '#' + node.id : '') + (cls ? '.' + cls : '');
              };
              const chain = [];
              for (let node = element, depth = 0; node && depth < 5; node = node.parentElement, depth++) {
                chain.push(describe(node));
              }
              window.__tpiManualTargetTaps.push({
                kind, label, tag: element.tagName.toLowerCase(),
                className: typeof element.className === 'string' ? element.className.slice(0, 180) : '',
                id: element.id || '', href: element.getAttribute('href') || '',
                chain: chain.join(' > '),
                html: (element.outerHTML || '').replace(/\\s+/g, ' ').slice(0, 500)
              });
              if (window.__tpiManualTargetTaps.length > 8) window.__tpiManualTargetTaps.shift();
            }, true);
          }
          const manualTargetTaps = (window.__tpiManualTargetTaps || []).splice(0, 8);
          const visible = e => {
            const r = e.getBoundingClientRect(), s = getComputedStyle(e);
            return r.width > 0 && r.height > 0 &&
              r.bottom > 0 && r.right > 0 &&
              r.top < window.innerHeight && r.left < window.innerWidth &&
              s.display !== 'none' && s.visibility !== 'hidden';
          };
          const missionCards = Array.from(document.querySelectorAll('.mission-item-center'))
            .filter(e => {
              const r = e.getBoundingClientRect(), s = getComputedStyle(e);
              return r.width > 0 && r.height > 0 && s.display !== 'none' &&
                s.visibility !== 'hidden' && !e.parentElement?.closest('.mission-item-center');
            });
          const missionTitle = card => {
            const raw = (card.innerText || card.textContent || '').replace(/\\s+/g, ' ').trim();
            return raw.replace(/\\b\\d+\\s*\\/\\s*\\d+\\b[\\s\\S]*$/, '')
              .replace(/\\b(làm ngay|thực hiện|đi ngay|xem ngay|bắt đầu|tham gia|tìm kiếm)\\b/gi, ' ')
              .replace(/\\s+/g, ' ').trim();
          };
          const missionTitles = missionCards.map(missionTitle)
            .filter(t => t.length >= 12 && t.length <= 140);
          const visibleMissionTitles = missionCards.filter(visible).map(missionTitle)
            .filter(t => t.length >= 12 && t.length <= 140);
          const compact = s => (s || '').replace(/\\s+/g, ' ').trim().slice(0, 100);
          const missionActions = missionCards.map(card => {
            const title = missionTitle(card);
            if (!title) return null;
            let container = card;
            for (let depth = 0; depth < 4 && container.parentElement; depth++) {
              const parent = container.parentElement;
              if (parent.querySelectorAll('.mission-item-center').length > 1) break;
              container = parent;
            }
            const controls = Array.from(container.querySelectorAll('a,button,[role="button"],[tabindex],[onclick],.mission-item-btn-go'))
              .filter(e => visible(e) && !e.contains(card) && !card.contains(e))
              .map(e => {
                const tag = e.tagName.toLowerCase();
                const cls = typeof e.className === 'string' ? e.className.split(/\\s+/).slice(0, 3).join('.') : '';
                const text = compact(e.innerText || e.textContent || e.getAttribute('aria-label') || e.getAttribute('title'));
                const href = e.getAttribute('href') || e.closest('a')?.getAttribute('href') || '';
                return [tag, cls, text, href ? 'href=' + href.slice(0, 100) : ''].filter(Boolean).join(':');
              }).filter(Boolean).slice(0, 5);
            return {title:title, controls:controls};
          }).filter(Boolean);
          const missionScroll = {found:false, top:0, max:0};
          const bodyLines = (document.body ? document.body.innerText : '').split(/\\n+/);
          const leafLines = Array.from(document.querySelectorAll('body *'))
            .filter(e => e.children.length === 0 && visible(e))
            .map(e => (e.innerText || e.textContent || '').trim());
          const interactive = Array.from(document.querySelectorAll('input,textarea,button,a,[role="button"],[contenteditable="true"]'))
            .filter(visible).slice(0, 45).map(e => {
              const tag = e.tagName.toLowerCase();
              const cls = typeof e.className === 'string' ? e.className.split(/\\s+/).slice(0, 3).join('.') : '';
              const text = compact(e.innerText || e.textContent);
              const label = compact(e.getAttribute('aria-label') || e.getAttribute('title'));
              const placeholder = compact(e.getAttribute('placeholder'));
              return [tag, cls, text, label, placeholder].filter(Boolean).join(' | ');
            }).filter(Boolean);
          const productCards = Array.from(document.querySelectorAll('[class*="product"],[class*="goods"],[class*="item-card"]'))
            .filter(e => visible(e) && !e.parentElement?.closest('[class*="product"],[class*="goods"],[class*="item-card"]'))
            .map(e => compact(e.innerText || e.textContent))
            .filter(t => t.length >= 8 && t.length <= 180).slice(0, 12);
          const headings = Array.from(document.querySelectorAll('h1,h2,h3,[role="heading"]'))
            .filter(visible).map(e => compact(e.innerText || e.textContent)).filter(Boolean).slice(0, 8);
          return {
            manualTargetTaps: manualTargetTaps,
            pageTitle: compact(document.title),
            headings: headings,
            interactive: interactive,
            productCards: productCards,
            lines: bodyLines.concat(leafLines)
              .map(t => t.trim())
              .filter(t => t.length > 1 && t.length < 180)
              .slice(0, 700),
            missionTitles: missionTitles,
            visibleMissionTitles: visibleMissionTitles,
            missionCardCount: missionCards.length,
            missionScroll: missionScroll,
            checkInEntryPoint: (() => {
              const button = document.querySelector('#lazcoins-check-in-button');
              if (!button || !visible(button)) return {count: 0};
              const r = button.getBoundingClientRect();
              const x = r.left + r.width / 2, y = r.top + r.height / 2;
              const hit = document.elementFromPoint(x, y);
              return {count: 1, x: x, y: y, tag: button.tagName.toLowerCase(), hitTag: hit ? hit.tagName.toLowerCase() : ''};
            })(),
            hasCheckInCard: (() => {
              const bodyText = document.body ? document.body.innerText : '';
              return (document.querySelector('#lazcoins-check-in-button') && visible(document.querySelector('#lazcoins-check-in-button'))) || Array.from(document.querySelectorAll('.lazcoins-checkin-card')).some(visible) ||
                (/điểm danh/i.test(bodyText) && /nhận xu/i.test(bodyText));
            })(),
            hasMissionsPage: Array.from(document.querySelectorAll('.mission-item-center')).some(visible),
            hasOpenMissionsControl: (() => {
              const controls = Array.from(document.querySelectorAll('.lazcoins-check-in-date,a,button,[role="button"],[tabindex]'));
              return controls.some(e => {
                const label = (e.innerText || e.textContent || '').replace(/\\s+/g, ' ').trim().toLocaleLowerCase();
                return visible(e) && (label === 'kiếm thêm' || label === 'kiếm thêm xu');
              });
            })(),
            missionEntryPoint: (() => {
              const controls = Array.from(document.querySelectorAll('.lazcoins-check-in-date,a,button,[role="button"],[tabindex]'))
                .filter(e => {
                  const label = (e.innerText || e.textContent || '').replace(/\\s+/g, ' ').trim().toLocaleLowerCase();
                  return visible(e) && (label === 'kiếm thêm' || label === 'kiếm thêm xu');
                });
              if (controls.length !== 1) return {count: controls.length};
              const control = controls[0];
              const exactLabels = [control, ...control.querySelectorAll('*')]
                .filter(e => {
                  const label = (e.innerText || e.textContent || '').replace(/\\s+/g, ' ').trim().toLocaleLowerCase();
                  return visible(e) && (label === 'kiếm thêm' || label === 'kiếm thêm xu');
                })
                .sort((a, b) => {
                  const ar = a.getBoundingClientRect(), br = b.getBoundingClientRect();
                  return ar.width * ar.height - br.width * br.height;
                });
              const labelNode = exactLabels[0] || control;
              const r = labelNode.getBoundingClientRect();
              const x = r.left + r.width / 2, y = r.top + r.height / 2;
              const hit = document.elementFromPoint(x, y);
              const clickable = hit && hit.closest('a,button,[role="button"],[tabindex],[onclick],.lazcoins-check-in-date');
              return {
                count: 1, x: x, y: y,
                labelTag: labelNode.tagName.toLowerCase(),
                hitTag: hit ? hit.tagName.toLowerCase() : '',
                hitClass: hit && typeof hit.className === 'string' ? hit.className.split(/\\s+/).slice(0, 3).join('.') : '',
                clickableTag: clickable ? clickable.tagName.toLowerCase() : ''
              };
            })()
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, self.sessionActive else { return }
            var hasMissionsPage = false
            if let payload = result as? [String: Any] {
                let manualTaps = payload["manualTargetTaps"] as? [[String: Any]] ?? []
                for tap in manualTaps {
                    let kind = tap["kind"] as? String ?? "Nút mục tiêu"
                    let label = tap["label"] as? String ?? ""
                    let chain = tap["chain"] as? String ?? ""
                    let html = tap["html"] as? String ?? ""
                    let href = tap["href"] as? String ?? ""
                    self.appendLog("[CHẠM TAY] \(kind) · nhãn=\(label) · DOM=\(chain) · href=\(href) · HTML=\(html)")
                }
                if let webLines = payload["lines"] as? [String] {
                    lines.append(contentsOf: webLines)
                }
                self.visibleWebMissionTitles = payload["visibleMissionTitles"] as? [String] ?? []
                let hasCheckInCard = payload["hasCheckInCard"] as? Bool ?? false
                hasMissionsPage = payload["hasMissionsPage"] as? Bool ?? false
                let hasOpenMissionsControl = payload["hasOpenMissionsControl"] as? Bool ?? false
                let activeTaskName = self.automationTaskIndex.flatMap { self.taskNames.indices.contains($0) ? self.taskNames[$0] : nil }
                let activeTaskKind = self.automationTaskIndex.flatMap { self.taskNames.indices.contains($0) ? self.missionKind(for: self.taskNames[$0]) : nil }
                let diagnosticParts: [String]
                if hasMissionsPage {
                    diagnosticParts = [
                        "Danh sách nhiệm vụ: \(payload["missionCardCount"] as? Int ?? 0) thẻ · \((payload["missionTitles"] as? [String] ?? []).count) nhiệm vụ"
                    ]
                } else if activeTaskName != nil {
                    let relevantPageLines = (payload["lines"] as? [String] ?? []).filter { line in
                        let value = line.lowercased()
                        return value.contains("tìm") || value.contains("search") || value.contains("sản phẩm") ||
                            value.contains("xem") || value.contains("video") || value.contains("giây") ||
                            value.contains("nhận xu") || value.contains("làm ngay") || value.contains("tiếp tục")
                    }.prefix(18).joined(separator: " | ")
                    diagnosticParts = [
                        "activeTask=\(activeTaskName ?? "none") kind=\(activeTaskKind ?? "none")",
                        "page=\(payload["pageTitle"] as? String ?? "")",
                        "headings=\((payload["headings"] as? [String] ?? []).joined(separator: " | "))",
                        "controls=\((payload["interactive"] as? [String] ?? []).prefix(18).joined(separator: " || "))",
                        "pageText=\(relevantPageLines)"
                    ]
                } else {
                    diagnosticParts = []
                }
                let diagnostic = diagnosticParts.joined(separator: " ## ")
                let diagnosticSignature = String(diagnostic.hashValue)
                if !diagnostic.isEmpty, diagnosticSignature != self.lastDOMDiagnosticSignature {
                    self.lastDOMDiagnosticSignature = diagnosticSignature
                    let clipped = String(diagnostic.prefix(hasMissionsPage ? 120 : 600))
                    self.appendLog(hasMissionsPage ? clipped : "DOM trang nhiệm vụ: \(clipped)")
                }
                self.captureLazadaPageURLs(
                    pageURL: pageURL,
                    hasCheckInCard: hasCheckInCard,
                    hasMissionsPage: hasMissionsPage,
                    hasOpenMissionsControl: hasOpenMissionsControl
                )
                if hasMissionsPage {
                    self.syncMissionTasks(payload["missionTitles"] as? [String] ?? [])
                }
                self.tapCheckInIfNeeded(
                    in: webView,
                    pageURL: pageURL,
                    hasCheckInCard: hasCheckInCard,
                    entryPoint: payload["checkInEntryPoint"] as? [String: Any]
                )
                self.tapMissionEntryIfNeeded(
                    in: webView,
                    pageURL: pageURL,
                    hasCheckInCard: hasCheckInCard,
                    hasMissionsPage: hasMissionsPage,
                    hasOpenMissionsControl: hasOpenMissionsControl,
                    entryPoint: payload["missionEntryPoint"] as? [String: Any]
                )
            } else if let webLines = result as? [String] {
                lines.append(contentsOf: webLines)
                self.visibleWebMissionTitles = []
            }
            self.processObservedLines(
                lines,
                pageURL: pageURL,
                authoritativeMissionTitles: hasMissionsPage ? self.visibleWebMissionTitles : nil
            )
            self.driveAutomation(in: webView)
        }
    }

    private func captureLazadaPageURLs(pageURL: String?, hasCheckInCard: Bool,
                                        hasMissionsPage: Bool, hasOpenMissionsControl: Bool) {
        guard let pageURL else { return }
        var changed = false

        if hasCheckInCard, checkInPageURL != pageURL {
            checkInPageURL = pageURL
            lastCheckInTapURL = nil
            checkInTapStartedAt = nil
            lastMissionEntryTapURL = nil
            missionEntryTapStartedAt = nil
            missionEntryTapAttempts = 0
            missionEntryTapFailureLogged = false
            changed = true
            appendLog("Đã xác nhận và lưu URL trang Điểm danh nhận xu: \(pageURL)")
        }

        if hasMissionsPage, missionsPageURL != pageURL {
            missionsPageURL = pageURL
            changed = true
            lastMissionEntryPromptURL = nil
            appendLog("Đã xác nhận và lưu URL trang Kiếm thêm (có thẻ nhiệm vụ): \(pageURL)")
        } else if hasOpenMissionsControl, missionsPageURL == nil,
                  lastMissionEntryPromptURL != pageURL {
            lastMissionEntryPromptURL = pageURL
            appendLog("Đã thấy nút mở Kiếm thêm; đang chờ danh sách .mission-item-center tải xong")
        }

        if hasMissionsPage {
            lastMissionEntryTapURL = nil
            missionEntryTapStartedAt = nil
            missionEntryTapAttempts = 0
            missionEntryTapFailureLogged = false
        }
        if changed { saveState() }
    }

    private func tapCheckInIfNeeded(in webView: WKWebView, pageURL: String?,
                                    hasCheckInCard: Bool, entryPoint: [String: Any]?) {
        guard sessionActive, automationEnabled, hasCheckInCard,
              let pageURL, pageURL == checkInPageURL,
              lastCheckInTapURL != pageURL else { return }
        guard let entryPoint, (entryPoint["count"] as? Int) == 1,
              let x = entryPoint["x"] as? Double,
              let y = entryPoint["y"] as? Double else {
            if lastMissionEntryPromptURL != pageURL {
                lastMissionEntryPromptURL = pageURL
                appendLog("Điểm danh: không tìm thấy duy nhất #lazcoins-check-in-button; chưa tự chạm")
            }
            return
        }
        guard let window = webView.window,
              let hidWindow = TPIOSAutoClickEngine.appWindow(),
              hidWindow === window,
              TPIOSAutoClickEngine.backendAvailable() else {
            appendLog("Điểm danh: WebView/HID chưa sẵn sàng hoặc không cùng cửa sổ; chưa chạm")
            return
        }
        let webPoint = CGPoint(x: x, y: y)
        guard webView.bounds.insetBy(dx: 1, dy: 1).contains(webPoint) else {
            appendLog("Điểm danh: tọa độ #lazcoins-check-in-button nằm ngoài WebView")
            return
        }
        let windowPoint = webView.convert(webPoint, to: window)
        guard window.bounds.insetBy(dx: 1, dy: 1).contains(windowPoint) else {
            appendLog("Điểm danh: tọa độ sau convert nằm ngoài cửa sổ; chưa chạm")
            return
        }
        lastCheckInTapURL = pageURL
        checkInTapStartedAt = Date()
        webView.evaluateJavaScript("window.__tpiAutoTouchUntil = Date.now() + 1500")
        guard TPIOSAutoClickEngine.shared.dispatchTouch(at: windowPoint, down: true) else {
            lastCheckInTapURL = nil
            checkInTapStartedAt = nil
            appendLog("Điểm danh: HID DOWN lỗi · " + TPIOSAutoClickEngine.lastDiagnostic())
            return
        }
        appendLog("Điểm danh: đã chạm HID #lazcoins-check-in-button")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            let released = TPIOSAutoClickEngine.shared.dispatchTouch(at: windowPoint, down: false)
            guard let self else { return }
            guard released else {
                self.lastCheckInTapURL = nil
                self.checkInTapStartedAt = nil
                self.appendLog("Điểm danh: HID UP lỗi · " + TPIOSAutoClickEngine.lastDiagnostic() + "; tạm dừng tự động")
                self.automationEnabled = false
                self.automationPhase = .selecting
                return
            }
            self.appendLog("Điểm danh: đã gửi HID UP; chờ Lazada cập nhật")
        }
    }

    private func tapMissionEntryIfNeeded(in webView: WKWebView, pageURL: String?,
                                         hasCheckInCard: Bool, hasMissionsPage: Bool,
                                         hasOpenMissionsControl: Bool, entryPoint: [String: Any]?) {
        guard sessionActive, automationEnabled, !hasMissionsPage,
              let pageURL, pageURL == checkInPageURL,
              lastCheckInTapURL == pageURL,
              let checkInTapStartedAt,
              Date().timeIntervalSince(checkInTapStartedAt) >= 2 else { return }

        if let notBefore = missionEntryNotBefore {
            guard Date() >= notBefore else { return }
            missionEntryNotBefore = nil
            appendLog("Kiếm thêm: đã chờ 2 giây sau khi bắt đầu; chuẩn bị chạm nút")
        }

        if lastMissionEntryTapURL == pageURL {
            let elapsed = missionEntryTapStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            guard elapsed >= 20 else { return }
            guard missionEntryTapAttempts < 3 else {
                if !missionEntryTapFailureLogged {
                    missionEntryTapFailureLogged = true
                    appendLog("Kiếm thêm: Lazada chưa chuyển sang danh sách sau 3 lần thử; dừng thử tự động")
                }
                return
            }
            missionEntryTapStartedAt = Date()
            appendLog("Kiếm thêm: chưa thấy danh sách sau 20 giây; thử chạm lại lần \(missionEntryTapAttempts + 1)/3")
        } else {
            missionEntryTapAttempts = 0
            missionEntryTapFailureLogged = false
        }

        guard hasCheckInCard else {
            if lastMissionEntryPromptURL != pageURL {
                lastMissionEntryPromptURL = pageURL
                appendLog("Kiếm thêm: chưa xác nhận được màn hình Điểm danh nhận xu; không tự chạm")
            }
            return
        }
        guard hasOpenMissionsControl, let entryPoint,
              (entryPoint["count"] as? Int) == 1,
              let x = entryPoint["x"] as? Double,
              let y = entryPoint["y"] as? Double else {
            if lastMissionEntryPromptURL != pageURL {
                lastMissionEntryPromptURL = pageURL
                let count = entryPoint?["count"] as? Int ?? 0
                appendLog("Kiếm thêm: không tìm thấy duy nhất nút có nhãn chính xác; số nút khớp=\(count)")
            }
            return
        }
        guard let window = webView.window else {
            appendLog("Kiếm thêm: WebView chưa gắn với UIWindow; không thể xác định tọa độ chạm")
            return
        }
        guard let hidWindow = TPIOSAutoClickEngine.appWindow() else {
            appendLog("Kiếm thêm: Chạm không tìm thấy cửa sổ app để phát HID")
            return
        }
        guard hidWindow === window else {
            let webAddress = String(describing: Unmanaged.passUnretained(window).toOpaque())
            let hidAddress = String(describing: Unmanaged.passUnretained(hidWindow).toOpaque())
            appendLog("Kiếm thêm: SAI CỬA SỔ · WebView=\(webAddress) Chạm=\(hidAddress); không gửi touch")
            return
        }
        guard TPIOSAutoClickEngine.backendAvailable() else {
            if lastMissionEntryPromptURL != pageURL {
                lastMissionEntryPromptURL = pageURL
                appendLog("Kiếm thêm: HID backend chưa sẵn sàng; chưa thể tự chạm")
            }
            return
        }

        let webPoint = CGPoint(x: x, y: y)
        guard webView.bounds.insetBy(dx: 1, dy: 1).contains(webPoint) else {
            appendLog("Kiếm thêm: tọa độ nút nằm ngoài WebView; không chạm")
            return
        }

        let windowPoint = webView.convert(webPoint, to: window)
        let webWindowAddress = String(describing: Unmanaged.passUnretained(window).toOpaque())
        let webViewFrameInWindow = webView.convert(webView.bounds, to: window)
        let contentOffset = webView.scrollView.contentOffset
        let labelTag = entryPoint["labelTag"] as? String ?? "?"
        let hitTag = entryPoint["hitTag"] as? String ?? "?"
        let clickableTag = entryPoint["clickableTag"] as? String ?? "?"
        appendLog(String(format: "Kiếm thêm: DOM=(%.1f,%.1f) label=%@ hit=%@ clickable=%@ WebView=(%.1f×%.1f) zoom=%.3f scale=%.2f webWindow=%@ frame=(%.1f,%.1f %.1fx%.1f) offset=(%.1f,%.1f) inset=(%.1f,%.1f,%.1f,%.1f) window=(%.1f×%.1f) point=(%.1f,%.1f)",
                         webPoint.x, webPoint.y, labelTag, hitTag, clickableTag,
                         webView.bounds.width, webView.bounds.height, webView.scrollView.zoomScale,
                         window.screen.scale, webWindowAddress,
                         webViewFrameInWindow.origin.x, webViewFrameInWindow.origin.y,
                         webViewFrameInWindow.size.width, webViewFrameInWindow.size.height,
                         contentOffset.x, contentOffset.y,
                         webView.scrollView.contentInset.top, webView.scrollView.contentInset.left,
                         webView.scrollView.contentInset.bottom, webView.scrollView.contentInset.right,
                         window.bounds.width, window.bounds.height, windowPoint.x, windowPoint.y))
        guard window.bounds.insetBy(dx: 1, dy: 1).contains(windowPoint) else {
            appendLog("Kiếm thêm: tọa độ sau convert nằm ngoài cửa sổ app; không gửi touch")
            return
        }

        lastMissionEntryTapURL = pageURL
        missionEntryTapStartedAt = Date()
        missionEntryTapAttempts += 1

        // Mark the automated touch so the manual-touch recorder does not log it.
        webView.evaluateJavaScript("window.__tpiAutoTouchUntil = Date.now() + 1500")
        // Use the same real HID DOWN/UP path as the working Chạm panel.
        guard TPIOSAutoClickEngine.shared.dispatchTouch(at: windowPoint, down: true) else {
            appendLog("Kiếm thêm: HID DOWN lỗi · \(TPIOSAutoClickEngine.lastDiagnostic())")
            return
        }
        appendLog("Kiếm thêm: HID DOWN · \(TPIOSAutoClickEngine.lastDiagnostic())")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            let released = TPIOSAutoClickEngine.shared.dispatchTouch(at: windowPoint, down: false)
            guard let self else { return }
            guard released else {
                self.appendLog("Kiếm thêm: HID UP lỗi · \(TPIOSAutoClickEngine.lastDiagnostic()); tạm dừng tự động")
                self.automationEnabled = false
                self.automationPhase = .selecting
                return
            }
            self.appendLog("Kiếm thêm: đã gửi HID UP; chờ Lazada mở danh sách nhiệm vụ")
        }
    }

    private func missionKind(for raw: String) -> String {
        let text = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        if text.contains("tim '") || text.contains("tim kiem") || text.contains("tim \"") { return "search" }
        if text.contains("choi ") || text.contains("vao game") || text.contains("tro choi") || text.contains("mini game") { return "game" }
        if text.contains("video") || text.contains("livestream") || text.contains("live stream") { return "video" }
        if text.contains("thong bao") { return "notification" }
        if text.contains("view any") || (text.contains("tim san pham") && text.contains("deals")) ||
           (text.contains("xem") && text.contains("san pham")) { return "product" }
        if text.contains("luot") || text.contains("ghe tham") || text.contains("visit") ||
           text.contains("xem trang") || text.contains("thu thach dang nhap") { return "scroll" }
        return "other"
    }

    private func syncMissionTasks(_ rawNames: [String]) {
        var names = collectedMissionNames
        var seen = Set(collectedMissionNames.map {
            normalizedTaskText($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        })
        for raw in rawNames {
            let name = normalizedTaskText(raw)
            guard isLikelyTaskName(name) else { continue }
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seen.insert(key).inserted { names.append(name) }
        }

        guard !names.isEmpty else { return }
        var old: [String: (Bool, String, String, Bool)] = [:]
        for (index, name) in taskNames.enumerated() {
            let key = normalizedTaskText(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            old[key] = (completedTasks.indices.contains(index) ? completedTasks[index] : false,
                        taskDetails.indices.contains(index) ? taskDetails[index] : "",
                        taskURLs.indices.contains(index) ? taskURLs[index] : "",
                        attemptedTaskIndices.contains(index))
        }
        let previousCount = taskNames.count
        let changed = names != taskNames
        collectedMissionNames = names
        taskNames = names
        completedTasks = names.map { name in
            let key = normalizedTaskText(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return old[key]?.0 ?? false
        }
        taskDetails = names.map { name in
            let key = normalizedTaskText(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return old[key]?.1 ?? ""
        }
        taskURLs = names.map { name in
            let key = normalizedTaskText(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return old[key]?.2 ?? ""
        }
        attemptedTaskIndices = Set(names.indices.filter { index in
            let key = normalizedTaskText(names[index]).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return old[key]?.3 ?? false
        })
        hasCurrentMissionSnapshot = true
        if changed {
            automationScanCursor = 0
            lastAutomationLogIndex = nil
            lastClaimScanSignature = nil
            lastBottomScanSignature = nil
            bottomScanCount = 0
            resetAutomationPosition()
            appendLog("Đã bổ sung nhiệm vụ từ Lazada: tổng \(names.count), mới \(names.count - previousCount)")
            saveObservedTasks()
        } else {
            refresh()
        }
    }

    private func driveNativeAutomation(in root: UIView) {
        guard sessionActive, automationEnabled else { return }
        guard let window = root.window else { return }

        if automationTaskIndex == nil {
            let count = taskNames.count
            guard count > 0 else { return }
            let visibleText = normalizedTaskText(nativeText(in: root)).folding(
                options: [.caseInsensitive, .diacriticInsensitive], locale: .current
            )
            let next = taskNames.indices.first {
                let key = normalizedTaskText(taskNames[$0]).folding(
                    options: [.caseInsensitive, .diacriticInsensitive], locale: .current
                )
                return !completedTasks[$0] && !attemptedTaskIndices.contains($0) &&
                    key.count >= 12 && visibleText.contains(key)
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
            let actionLabels = ["nhận xu", "nhận", "làm ngay", "thực hiện", "đi ngay", "xem ngay", "bắt đầu", "tham gia"]
            var matches: [(UIView, String)] = []
            func visit(_ view: UIView) {
                guard !view.isHidden, view.alpha > 0.01 else { return }
                let isActionControl = view is UIControl ||
                    view.accessibilityTraits.contains(.button) ||
                    !(view.gestureRecognizers ?? []).isEmpty
                if isActionControl {
                    let label = normalizedTaskText(nativeText(in: view))
                    if actionLabels.contains(where: { label.localizedCaseInsensitiveContains($0) }) {
                        var ancestor: UIView? = view
                        for _ in 0..<7 {
                            guard let card = ancestor else { break }
                            let cardText = nativeText(in: card)
                            if cardText.localizedCaseInsensitiveContains(taskName) {
                                if !matches.contains(where: { $0.0 === view }) {
                                    matches.append((view, cardText))
                                }
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

            let actionLabel = normalizedTaskText(nativeText(in: button)).lowercased()
            let isClaim = actionLabel == "nhận" || actionLabel == "nhận xu"
            guard isClaim || missionKind(for: taskName) == "scroll" else {
                attemptedTaskIndices.insert(index)
                automationScanCursor = (index + 1) % max(1, taskNames.count)
                automationTaskIndex = nil
                automationStartedAt = nil
                automationPhase = .selecting
                lastAutomationLogIndex = nil
                appendLog("Native: bỏ qua nhiệm vụ \(missionKind(for: taskName)) chưa có bộ xử lý riêng; tiếp tục tìm nhiệm vụ hỗ trợ")
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
                self.automationPhase = isClaim ? .returning : .waitingForPage
                self.automationStartedAt = Date()
                self.lastAutomationLogIndex = isClaim ? -2 : nil
                self.appendLog(isClaim
                    ? "Native: đã chạm HID Nhận xu trên danh sách; chờ Lazada cập nhật"
                    : "Native: đã chạm nút mở nhiệm vụ: \(taskName)")
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
            if lastAutomationLogIndex == -2 {
                guard let started = automationStartedAt, Date().timeIntervalSince(started) >= 3 else { return }
                attemptedTaskIndices.insert(index)
                automationScanCursor = (index + 1) % max(1, taskNames.count)
                automationTaskIndex = nil
                automationStartedAt = nil
                nativeAutomationScrollView = nil
                automationPhase = .selecting
                lastAutomationLogIndex = nil
                appendLog("Native: đã chờ Lazada cập nhật sau khi nhận xu; tiếp tục xét nhiệm vụ")
                return
            }

            if lastAutomationLogIndex == -4 {
                let visibleText = normalizedTaskText(nativeText(in: root)).folding(
                    options: [.caseInsensitive, .diacriticInsensitive], locale: .current
                )
                let matchingTasks = taskNames.filter { name in
                    let key = normalizedTaskText(name).folding(
                        options: [.caseInsensitive, .diacriticInsensitive], locale: .current
                    )
                    return key.count >= 12 && visibleText.contains(key)
                }
                if matchingTasks.count >= 2 {
                    automationTaskIndex = nil
                    automationStartedAt = nil
                    nativeAutomationScrollView = nil
                    automationPhase = .selecting
                    lastAutomationLogIndex = nil
                    appendLog("Native: đã xác nhận danh sách nhiệm vụ trở lại; tiếp tục xử lý")
                } else if let started = automationStartedAt, Date().timeIntervalSince(started) >= 12,
                          lastAutomationLogIndex != -6 {
                    lastAutomationLogIndex = -6
                    appendLog("Native: đã điều hướng nhưng chưa xác nhận được danh sách nhiệm vụ; giữ tiến độ")
                }
                return
            }

            guard lastAutomationLogIndex != -5 else { return }
            let candidates = findWebViews(in: root).filter { $0.window === window }
            guard candidates.count == 1, let missionWebView = candidates.first else {
                lastAutomationLogIndex = -5
                appendLog("Native: không xác định duy nhất WebView để quay lại danh sách; không chạm Back giao diện")
                return
            }
            if missionWebView.canGoBack {
                missionWebView.goBack()
                appendLog("Native: gọi lịch sử WebView để trở về danh sách; chờ xác nhận")
            } else if let listURL = missionsPageURL.flatMap(URL.init(string:)) {
                missionWebView.load(URLRequest(url: listURL))
                appendLog("Native: mở lại URL danh sách nhiệm vụ đã xác nhận")
            } else {
                lastAutomationLogIndex = -5
                appendLog("Native: thiếu lịch sử và URL danh sách; giữ nhiệm vụ")
                return
            }
            lastAutomationLogIndex = -4
            automationStartedAt = Date()
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
        guard sessionActive, automationEnabled,
              let pageURL = sanitizedPageURL(webView.url) else { return }
        if missionsPageURL != pageURL && automationPhase != .returning && automationPhase != .waitingForPage { return }

        if automationTaskIndex == nil && automationPhase == .selecting && lastClaimScanSignature == nil {
            let blocked = claimRetryBlockedTitles.sorted()
            guard let blockedData = try? JSONSerialization.data(withJSONObject: blocked),
                  let blockedJSON = String(data: blockedData, encoding: .utf8) else { return }
            let claimScanScript = """
            (function(){
              const norm=s=>(s||'').replace(/\\s+/g,' ').trim().normalize('NFC').toLowerCase();
              const visible=e=>{
                const r=e.getBoundingClientRect(),s=getComputedStyle(e);
                return r.width>0&&r.height>0&&r.bottom>0&&r.right>0&&r.top<innerHeight&&r.left<innerWidth&&s.display!=='none'&&s.visibility!=='hidden';
              };
              const titleOf=card=>norm(card.innerText||card.textContent)
                .replace(/\\b\\d+\\s*\\/\\s*\\d+\\b[\\s\\S]*$/,'')
                .replace(/\\b(làm ngay|thực hiện|đi ngay|xem ngay|bắt đầu|tham gia|tìm kiếm)\\b/gi,' ')
                .replace(/\\s+/g,' ').trim();
              const blocked=\(blockedJSON).map(norm);
              const cards=Array.from(document.querySelectorAll('.mission-item-center'))
                .filter(e=>!e.parentElement?.closest('.mission-item-center'));
              const visibleCards=cards.filter(visible);
              const controlLabels=[];
              const signature=visibleCards.map(c=>titleOf(c)).join('|')+'@'+
                (document.scrollingElement?.scrollTop||0);
              for(const card of visibleCards){
                const title=titleOf(card);
                if(!title||blocked.includes(title))continue;
                let container=card;
                for(let depth=0;depth<4&&container.parentElement;depth++){
                  const parent=container.parentElement;
                  if(parent.querySelectorAll('.mission-item-center').length>1)break;
                  container=parent;
                }
                const controls=Array.from(container.querySelectorAll('.mission-item-btn-claim,.mission-item-btn-go,a,button,[role="button"],[tabindex],[onclick]'))
                  .filter(e=>!e.contains(card)&&!card.contains(e));
                for(const control of controls){
                  const label=norm(control.innerText||control.textContent||control.getAttribute('aria-label')||control.getAttribute('title'));
                  if(label)controlLabels.push(label.slice(0,50));
                  if(visible(control)&&(/^nhận(?: xu)?$/.test(label)||control.matches('.mission-item-btn-claim'))){
                    const r=control.getBoundingClientRect();
                    return {status:'claim',title:title,x:r.left+r.width/2,y:r.top+r.height/2,signature:signature};
                  }
                }
              }
              return {status:'none',signature:signature,cards:visibleCards.length,controls:Array.from(new Set(controlLabels)).slice(0,12)};
            })();
            """
            webView.evaluateJavaScript(claimScanScript) { [weak self] result, _ in
                guard let self, self.sessionActive, self.automationEnabled else { return }
                guard let payload = result as? [String: Any] else { return }
                let status = payload["status"] as? String ?? "unknown"
                let signature = payload["signature"] as? String ?? "empty"
                if status == "none" {
                    self.lastClaimScanSignature = signature
                    let count = payload["cards"] as? Int ?? 0
                    let controls = (payload["controls"] as? [String] ?? []).joined(separator: " | ")
                    self.appendLog("Quét nút Nhận: thẻ=\(count) · nút cạnh thẻ=\(controls.isEmpty ? "không thấy" : controls)")
                    self.driveAutomation(in: webView)
                    return
                }
                guard status == "claim",
                      let title = payload["title"] as? String,
                      let x = payload["x"] as? Double,
                      let y = payload["y"] as? Double,
                      let index = self.taskNames.firstIndex(where: {
                          let task = self.normalizedTaskText($0)
                          let card = self.normalizedTaskText(title)
                          return task.compare(card, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ||
                              task.localizedCaseInsensitiveContains(card) || card.localizedCaseInsensitiveContains(task)
                      }),
                      let window = webView.window,
                      TPIOSAutoClickEngine.backendAvailable() else {
                    self.lastClaimScanSignature = signature
                    self.appendLog("Quét nút Nhận: chưa ghép được thẻ với nhiệm vụ hoặc HID chưa sẵn sàng")
                    self.driveAutomation(in: webView)
                    return
                }
                let point = CGPoint(x: x, y: y)
                guard webView.bounds.insetBy(dx: 1, dy: 1).contains(point) else {
                    self.lastClaimScanSignature = signature
                    self.appendLog("Nút Nhận nằm ngoài vùng WebView; chưa chạm")
                    self.driveAutomation(in: webView)
                    return
                }
                let windowPoint = webView.convert(point, to: window)
                webView.evaluateJavaScript("window.__tpiAutoTouchUntil = Date.now() + 1500")
                guard TPIOSAutoClickEngine.shared.dispatchTouch(at: windowPoint, down: true) else {
                    self.lastClaimScanSignature = signature
                    self.appendLog("HID không gửi được DOWN cho nút Nhận: " + title)
                    self.driveAutomation(in: webView)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    let released = TPIOSAutoClickEngine.shared.dispatchTouch(at: windowPoint, down: false)
                    guard let self, self.sessionActive, self.automationEnabled, released else {
                        self?.automationEnabled = false
                        self?.appendLog("Không xác nhận được HID UP khi nhận xu; đã dừng tự động")
                        return
                    }
                    self.automationTaskIndex = index
                    self.automationPhase = .returning
                    self.automationStartedAt = Date()
                    self.lastAutomationLogIndex = -2
                    self.lastClaimScanSignature = nil
                    self.appendLog("Đã chạm HID nút Nhận trên danh sách: " + title + " · đang xác minh Lazada")
                }
            }
            return
        }

        if automationTaskIndex == nil {
            guard hasCurrentMissionSnapshot, !taskNames.isEmpty else { return }
            let next = taskNames.indices.first {
                !completedTasks[$0] && !attemptedTaskIndices.contains($0)
            }
            guard let next else {
                guard lastAutomationLogIndex != -7 else { return }
                let scanScript = """
                (function(){
                  const cards=Array.from(document.querySelectorAll('.mission-item-center'));
                  const card=cards.find(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0;});
                  if(!card)return {state:'no_mission_cards'};
                  const root=document.scrollingElement||document.documentElement;
                  const checkIn=document.querySelector('#lazcoins-check-in-button');
                  const checkInVisible=!!(checkIn&&(()=>{const r=checkIn.getBoundingClientRect(),s=getComputedStyle(checkIn);return r.width>0&&r.height>0&&r.bottom>0&&r.top<innerHeight&&s.display!=='none'&&s.visibility!=='hidden';})());
                  const candidates=[];
                  for(let p=card.parentElement;p&&p!==document.body;p=p.parentElement){
                    const st=getComputedStyle(p);
                    const cardCount=p.querySelectorAll('.mission-item-center').length;
                    if(cardCount>=2&&p.scrollHeight-p.clientHeight>40&&/(auto|scroll|overlay)/.test(st.overflowY))candidates.push(p);
                  }
                  // Only use document scrolling when the check-in control is no longer visible.
                  if(!candidates.length&&!checkInVisible&&root.scrollHeight-root.clientHeight>40)candidates.push(root);
                  const describe=e=>e===root?'document':e.tagName.toLowerCase()+(typeof e.className==='string'&&e.className.trim()?'.'+e.className.trim().split(/\\s+/).slice(0,2).join('.'): '');
                  for(const target of candidates){
                    const max=Math.max(0,target.scrollHeight-target.clientHeight),before=target.scrollTop;
                    if(before>=max-4)continue;
                    const after=Math.min(max,before+Math.max(240,innerHeight*0.72));
                    target.scrollTop=after;
                    const actual=target.scrollTop;
                    if(actual>before+2)return {state:'moved',target:describe(target),before:before,after:actual,max:max};
                  }
                  const pending=candidates.some(e=>e.scrollTop<e.scrollHeight-e.clientHeight-4);
                  const signature=cards.filter(e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0&&r.bottom>0&&r.top<innerHeight;})
                    .map(e=>(e.innerText||e.textContent||'').replace(/\\s+/g,' ').trim()).join('|')+'@'+
                    candidates.map(e=>Math.round(e.scrollTop)).join(',');
                  const detail=candidates.map(e=>describe(e)+':'+Math.round(e.scrollTop)+'/'+Math.max(0,e.scrollHeight-e.clientHeight)).join(';');
                  if(!candidates.length)return {state:'no_mission_scroller',signature:signature,checkInVisible:checkInVisible};
                  return {state:pending?'stuck':'end',signature:signature,candidates:detail};
                })();
                """
                webView.evaluateJavaScript(scanScript) { [weak self] result, _ in
                    guard let self, self.sessionActive, self.automationEnabled else { return }
                    let state=(result as? [String:Any])?["state"] as? String ?? "unknown"
                    if state == "moved" {
                        self.lastAutomationLogIndex = nil
                        self.lastClaimScanSignature = nil
                        self.lastBottomScanSignature = nil
                        self.bottomScanCount = 0
                        let target = (result as? [String: Any])?["target"] as? String ?? "vùng cuộn"
                        self.appendLog("Đã cuộn " + target + "; tiếp tục quét nhiệm vụ")
                    } else if state == "end" {
                        let signature = (result as? [String: Any])?["signature"] as? String ?? "empty"
                        if signature == self.lastBottomScanSignature {
                            self.bottomScanCount += 1
                        } else {
                            self.lastBottomScanSignature = signature
                            self.bottomScanCount = 1
                        }
                        if self.bottomScanCount >= 2 {
                            self.lastAutomationLogIndex = -7
                            self.appendLog("Đã xác nhận cuối danh sách qua 2 lần quét; không còn vùng cuộn hoặc thẻ mới")
                        } else {
                            self.appendLog("Đã tới đáy tạm thời; chờ Lazada tải thêm rồi kiểm tra lại")
                        }
                    } else if state == "no_mission_cards" || state == "no_mission_scroller" {
                        self.lastAutomationLogIndex = -7
                        let checkInVisible = (result as? [String: Any])?["checkInVisible"] as? Bool ?? false
                        self.appendLog(checkInVisible
                            ? "Chặn cuộn: nút Điểm danh vẫn hiện; không cuộn trang ngoài danh sách nhiệm vụ"
                            : "Chặn cuộn: chưa tìm thấy vùng cuộn thuộc danh sách nhiệm vụ")
                    } else if state == "stuck" {
                        self.lastAutomationLogIndex = -7
                        let detail = (result as? [String: Any])?["candidates"] as? String ?? "không xác định"
                        self.appendLog("Vùng cuộn không di chuyển; dừng để tránh báo hết danh sách sai: " + detail)
                    }
                }
                return
            }
            automationTaskIndex = next
            automationEnteredTaskPage = false
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
              const center = (e, action='perform', taskTitle='') => {
                const r=e.getBoundingClientRect();
                return {status:'ready',action:action,taskTitle:taskTitle,x:r.left+r.width/2,y:r.top+r.height/2};
              };
              const cardTitle = card => norm(card.innerText || card.textContent)
                .replace(/\\b\\d+\\s*\\/\\s*\\d+\\b[\\s\\S]*$/, '')
                .replace(/\\b(làm ngay|thực hiện|đi ngay|xem ngay|bắt đầu|tham gia|tìm kiếm)\\b/gi, ' ')
                .replace(/\\s+/g, ' ').trim();
              // Nút Nhận đã được quét độc lập trước khi chọn nhiệm vụ chưa hoàn thành.
              const cards = Array.from(document.querySelectorAll('.mission-item-center'))
                .filter(e => {
                  const r=e.getBoundingClientRect(),s=getComputedStyle(e);
                  return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden'&&!e.parentElement?.closest('.mission-item-center');
                });
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
                if (!visible(card)) {
                  card.scrollIntoView({block:'center',behavior:'auto'});
                  return {status:'scrolled'};
                }
                let container = card, go = null;
                for (let depth = 0; container && depth < 5; depth++, container = container.parentElement) {
                  if (container.querySelectorAll('.mission-item-center').length > 1) break;
                  go = Array.from(container.querySelectorAll('.mission-item-btn-go')).find(visible) || null;
                  if (go) break;
                }
                if (go && visible(go)) {
                  const label = norm(go.innerText || go.textContent || go.getAttribute('aria-label'));
                  if (/^nhận(?: xu)?$/.test(label)) return center(go, 'claim', cardTitle(card));
                  return center(go, 'perform', cardTitle(card));
                }
                container = card;
                for (let depth = 0; container && depth < 5; depth++, container = container.parentElement) {
                  if (container.querySelectorAll('.mission-item-center').length > 1) break;
                  const actions = Array.from(container.querySelectorAll('.mission-item-btn-claim,a,button,[role="button"],[onclick],.mission-item-btn-go'))
                    .filter(e => visible(e) && !e.contains(card));
                  const action = actions.find(e => /^nhận(?: xu)?$|làm ngay|thực hiện|đi ngay|xem ngay|tham gia|bắt đầu|tìm kiếm|đi xem|khám phá/i.test(norm(e.innerText || e.textContent)));
                  if (action) return center(action);
                }
                return {status:'mission_action_not_found'};
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
                if clickResult == "scrolled" {
                    self.lastAutomationLogIndex = -6
                    return
                }
                if clickResult == "ready",
                   let x = payload?["x"] as? Double,
                   let y = payload?["y"] as? Double,
                   let window = webView.window,
                   TPIOSAutoClickEngine.backendAvailable() {
                    let action = payload?["action"] as? String ?? "perform"
                    let clickedTaskName = (payload?["taskTitle"] as? String).flatMap { title in
                        self.taskNames.first(where: {
                            self.normalizedTaskText($0).compare(self.normalizedTaskText(title), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                        })
                    } ?? taskName
                    let clickedTaskIndex = self.taskNames.firstIndex(of: clickedTaskName) ?? index
                    guard action == "claim" || self.missionKind(for: clickedTaskName) == "scroll" else {
                        self.attemptedTaskIndices.insert(clickedTaskIndex)
                        self.automationScanCursor = (clickedTaskIndex + 1) % max(1, self.taskNames.count)
                        self.automationTaskIndex = nil
                        self.automationStartedAt = nil
                        self.automationPhase = .selecting
                        self.lastAutomationLogIndex = nil
                        self.appendLog("Bỏ qua nhiệm vụ \(self.missionKind(for: taskName)) chưa có bộ xử lý riêng; tiếp tục tìm nhiệm vụ hỗ trợ")
                        return
                    }
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
                        let action = payload?["action"] as? String ?? "perform"
                        self.automationPhase = action == "claim" ? .returning : .waitingForPage
                        self.automationStartedAt = Date()
                        self.lastAutomationLogIndex = action == "claim" ? -2 : nil
                        self.automationTaskIndex = clickedTaskIndex
                        self.appendLog(action == "claim"
                            ? "Đã chạm HID nút Nhận xu: \(clickedTaskName)"
                            : "Đã chạm nút nhiệm vụ bằng DOM + HID: \(clickedTaskName)")
                    }
                } else {
                    if clickResult == "ready" {
                        self.appendLog("Tìm thấy nút nhưng HID chưa sẵn sàng; tạm dừng để không bỏ nhiệm vụ: " + taskName)
                        self.automationEnabled = false
                        self.automationTaskIndex = nil
                        self.automationPhase = .selecting
                        self.refresh()
                        return
                    }
                    let retryable: Set<String> = [
                        "title_not_found", "mission_not_found", "mission_ambiguous",
                        "mission_action_not_found", "title_found_no_action", "no_result"
                    ]
                    if retryable.contains(clickResult) {
                        let key = self.normalizedTaskText(taskName).lowercased()
                        let failures = (self.taskLookupFailures[key] ?? 0) + 1
                        self.taskLookupFailures[key] = failures
                        if failures < 3 {
                            self.lastAutomationLogIndex = nil
                            self.automationTaskIndex = nil
                            self.automationStartedAt = nil
                            self.automationPhase = .selecting
                            self.appendLog("Chưa nhận diện được thẻ nhiệm vụ; sẽ thử lại (\(failures)/3): " + taskName)
                            return
                        }
                        self.appendLog("Đã thử nhận diện 3 lần nhưng chưa thấy thẻ; tạm bỏ qua để tiếp tục quét/cuộn: " + taskName)
                    } else if let error {
                        self.appendLog("Không thực hiện được nhiệm vụ do lỗi WebView: " + error.localizedDescription)
                    }
                    self.attemptedTaskIndices.insert(index)
                    self.automationScanCursor = (index + 1) % max(1, self.taskNames.count)
                    self.automationTaskIndex = nil
                    self.automationStartedAt = nil
                    self.automationPhase = .selecting
                }
                if let error { self.appendLog("Lỗi mở nhiệm vụ: \(error.localizedDescription)") }
            }
        case .waitingForPage:
            guard let started = automationStartedAt, Date().timeIntervalSince(started) >= 2 else { return }
            guard let expectedData = try? JSONSerialization.data(withJSONObject: [missionsPageURL ?? ""]),
                  let expectedJSON = String(data: expectedData, encoding: .utf8) else { return }
            let pageCheckScript = """
            (function(){
              const expected=\(expectedJSON)[0];
              const cards=Array.from(document.querySelectorAll('.mission-item-center')).filter(e=>{
                const r=e.getBoundingClientRect(),s=getComputedStyle(e);
                return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden';
              });
              const current=location.href;
              const clean=u=>{try{const v=new URL(u,location.href);return v.protocol+'//'+v.host.toLowerCase()+v.pathname;}catch(_){return u;}};
              return {url:current,cards:cards.length,stillList:clean(current)===clean(expected)&&cards.length>0,
                title:(document.title||'').slice(0,100)};
            })();
            """
            webView.evaluateJavaScript(pageCheckScript) { [weak self] result, error in
                guard let self, self.sessionActive, self.automationEnabled else { return }
                let payload=result as? [String:Any] ?? [:]
                let stillList=payload["stillList"] as? Bool ?? true
                if stillList {
                    self.attemptedTaskIndices.insert(index)
                    self.automationTaskIndex=nil
                    self.automationStartedAt=nil
                    self.automationEnteredTaskPage=false
                    self.automationPhase = .selecting
                    self.lastAutomationLogIndex=nil
                    self.appendLog("Nhiệm vụ không mở trang chi tiết (vẫn còn \(payload["cards"] as? Int ?? 0) thẻ trong danh sách); không cuộn và không Back: " + taskName)
                    return
                }
                self.automationEnteredTaskPage=true
                self.automationPhase = .scrolling
                self.automationStartedAt = Date()
                self.appendLog("Đã xác nhận rời danh sách nhiệm vụ; bắt đầu lướt trang nhiệm vụ trong \(Int(self.automationDuration)) giây: " + taskName)
            }
            return
        case .scrolling:
            guard let started = automationStartedAt else { return }
            if Date().timeIntervalSince(started) >= automationDuration {
                automationPhase = .returning
                automationStartedAt = Date()
                appendLog("Đã đủ thời lượng lướt; đang tìm nút Nhận xu: \(taskName)")
            } else {
                webView.evaluateJavaScript("window.scrollBy({top: Math.max(240, window.innerHeight * 0.72), behavior: 'smooth'});", completionHandler: nil)
            }
        case .returning:
            guard let started = automationStartedAt else { return }
            if lastAutomationLogIndex == -2 {
                guard Date().timeIntervalSince(started) >= 3 else { return }
                let title = taskNames[index]
                let encoded = (try? JSONSerialization.data(withJSONObject: [title]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                let verifyScript = """
                (function(){
                  const wanted=\(encoded)[0];
                  const norm=s=>(s||'').replace(/\\s+/g,' ').trim().normalize('NFC').toLowerCase();
                  const titleOf=card=>norm(card.innerText||card.textContent)
                    .replace(/\\b\\d+\\s*\\/\\s*\\d+\\b[\\s\\S]*$/,'')
                    .replace(/\\b(làm ngay|thực hiện|đi ngay|xem ngay|bắt đầu|tham gia|tìm kiếm|nhận xu?)\\b/gi,' ')
                    .replace(/\\s+/g,' ').trim();
                  const cards=Array.from(document.querySelectorAll('.mission-item-center'));
                  const card=cards.find(e=>titleOf(e)===norm(wanted)||titleOf(e).includes(norm(wanted))||norm(wanted).includes(titleOf(e)));
                  if(!card)return {state:'card_missing'};
                  const claim=Array.from(card.querySelectorAll('.mission-item-btn-claim,.mission-item-btn-go,a,button,[role="button"]'))
                    .some(e=>/^nhận(?: xu)?$/.test(norm(e.innerText||e.textContent||e.getAttribute('aria-label')||e.getAttribute('title'))));
                  return {state:claim?'still_claimable':'claimed'};
                })();
                """
                webView.evaluateJavaScript(verifyScript) { [weak self] result, _ in
                    guard let self, self.sessionActive, self.automationEnabled else { return }
                    let state=(result as? [String:Any])?["state"] as? String ?? "unknown"
                    if state == "claimed" {
                        if self.completedTasks.indices.contains(index) { self.completedTasks[index] = true }
                        self.saveObservedTasks()
                        self.appendLog("Lazada đã đổi trạng thái nút Nhận; xác nhận nhận xu: " + title)
                    } else {
                        self.claimRetryBlockedTitles.insert(self.normalizedTaskText(title).lowercased())
                        self.attemptedTaskIndices.insert(index)
                        self.appendLog("Chưa xác nhận được nhận xu (" + state + "); không đánh dấu hoàn thành: " + title)
                    }
                    self.automationScanCursor = (index + 1) % max(1, self.taskNames.count)
                    self.automationTaskIndex = nil
                    self.automationStartedAt = nil
                    self.automationPhase = .selecting
                    self.lastAutomationLogIndex = nil
                    self.lastClaimScanSignature = nil
                }
                return
            }
            if lastAutomationLogIndex == -4 {
                guard pageURL == missionsPageURL else { return }
                webView.evaluateJavaScript("Array.from(document.querySelectorAll('.mission-item-center')).some(e => { const r=e.getBoundingClientRect(); return r.width>0 && r.height>0 && r.bottom>0 && r.top<innerHeight; })") { [weak self] result, _ in
                    guard let self, self.sessionActive, self.automationEnabled,
                          (result as? Bool) == true else { return }
                    self.automationTaskIndex = nil
                    self.automationStartedAt = nil
                    self.automationEnteredTaskPage = false
                    self.automationPhase = .selecting
                    self.lastAutomationLogIndex = nil
                    self.lastClaimScanSignature = nil
                    self.appendLog("Đã xác nhận danh sách nhiệm vụ trở lại; quét nút Nhận trước")
                }
                return
            }
            guard Date().timeIntervalSince(started) >= 2 else { return }
            guard automationEnteredTaskPage else {
                attemptedTaskIndices.insert(index)
                automationTaskIndex = nil
                automationStartedAt = nil
                automationPhase = .selecting
                lastAutomationLogIndex = nil
                appendLog("Chặn điều hướng Back: chưa xác nhận đã mở trang chi tiết nhiệm vụ")
                return
            }
            if webView.canGoBack {
                lastAutomationLogIndex = -4
                webView.goBack()
                automationStartedAt = Date()
                appendLog("Đã điều hướng WebView về danh sách; chờ xác nhận")
            } else if let listURL = missionsPageURL.flatMap(URL.init(string:)) {
                lastAutomationLogIndex = -4
                webView.load(URLRequest(url: listURL))
                automationStartedAt = Date()
                appendLog("Đã mở lại URL danh sách nhiệm vụ; chờ xác nhận")
            } else {
                if lastAutomationLogIndex != -5 {
                    lastAutomationLogIndex = -5
                    appendLog("Không có lịch sử hoặc URL danh sách nhiệm vụ; giữ nhiệm vụ, không chạm Back")
                }
                return
            }
            lastAutomationLogIndex = -4
            automationStartedAt = Date()
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

    private func nativeDiagnostic(in root: UIView) -> String {
        var texts: [String] = []
        var buttons: [String] = []
        var fields: [String] = []
        var scrolls: [String] = []
        var seen = Set<String>()

        func add(_ raw: String?, to values: inout [String], limit: Int) {
            guard values.count < limit,
                  let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  value.count >= 2, value.count <= 120 else { return }
            let normalized = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let lower = normalized.lowercased()
            guard !lower.contains("đánh giá"), !lower.contains("đã bán"),
                  !lower.contains("freeship"), !lower.contains("₫") else { return }
            if seen.insert(normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted {
                values.append(normalized)
            }
        }

        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let label = view as? UILabel { add(label.text, to: &texts, limit: 8) }
            if let button = view as? UIButton {
                let label = [button.currentTitle, button.accessibilityLabel].compactMap { $0 }.joined(separator: " / ")
                add(label, to: &buttons, limit: 10)
            }
            if let field = view as? UITextField {
                add(field.placeholder ?? field.accessibilityLabel, to: &fields, limit: 4)
            } else if let search = view as? UISearchBar {
                add(search.placeholder ?? search.text, to: &fields, limit: 4)
            }
            if let scroll = view as? UIScrollView,
               scroll.contentSize.height > scroll.bounds.height + 30,
               scroll.bounds.width > 100, scroll.bounds.height > 100,
               scrolls.count < 3 {
                scrolls.append("\(NSStringFromClass(type(of: scroll))):\(Int(scroll.bounds.width))x\(Int(scroll.bounds.height)) content=\(Int(scroll.contentSize.height))")
            }
            view.subviews.forEach(visit)
        }
        visit(root)

        var parts: [String] = []
        if !texts.isEmpty { parts.append("text=[" + texts.joined(separator: " | ") + "]") }
        if !buttons.isEmpty { parts.append("buttons=[" + buttons.joined(separator: " | ") + "]") }
        if !fields.isEmpty { parts.append("fields=[" + fields.joined(separator: " | ") + "]") }
        if !scrolls.isEmpty { parts.append("scroll=[" + scrolls.joined(separator: " | ") + "]") }
        return String(parts.joined(separator: " · ").prefix(850))
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
        let metadataPattern = #"^\d+[\d.,]*\s*[kmb]?\s*\+?\s*(đánh giá|người theo dõi|lượt theo dõi|reviews?|followers?)"#
        if lower.range(of: metadataPattern, options: .regularExpression) != nil { return false }

        // This is a page/category slogan, not an individual task card.
        if lower.hasPrefix("tìm kiếm & xem hot deal") { return false }

        let taskWords = [
            "điểm danh", "livestream", "live", "theo dõi", "xem sản phẩm", "xem 3 sản phẩm",
            "xem video", "xem trang", "thử thách đăng nhập", "thông báo điểm danh",
            "dailyrewards", "lazmall", "chia sẻ", "thêm vào giỏ", "mua hàng", "đánh giá",
            "tìm kiếm", "tìm ", "nhận xu", "check-in", "watch", "view any", "share",
            "visit", "lướt xem", "lướt", "siêu tiết kiệm", "chơi ", "vào game", "trò chơi"
        ]
        return taskWords.contains(where: { lower.contains($0) })
    }

    private func processObservedLines(_ rawLines: [String], pageURL: String? = nil,
                                      authoritativeMissionTitles: [String]? = nil) {
        let uniqueLines = rawLines.reduce(into: [String]()) { result, line in
            let normalized = normalizedTaskText(line)
            guard !normalized.isEmpty,
                  !result.contains(where: {
                      $0.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                  }) else { return }
            result.append(normalized)
        }
        let candidateNames = authoritativeMissionTitles ?? uniqueLines.filter { isLikelyTaskName($0) }
        let authoritativeKeys = authoritativeMissionTitles.map {
            Set($0.map { normalizedTaskText($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
        }
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
            if let authoritativeKeys, !authoritativeKeys.contains(key) { continue }
            guard seenThisPass.insert(key).inserted else { continue }

            if !taskNames.contains(where: {
                normalizedTaskText($0).compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                taskNames.append(name)
                completedTasks.append(false)
                taskDetails.append("")
                taskURLs.append("")
                changed = true
                if !automationEnabled {
                    appendLog("Nhận diện nhiệm vụ trên màn hình: \(name)")
                }
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
                    if !automationEnabled {
                        appendLog("Đã lưu hướng dẫn cho nhiệm vụ: \(name)")
                    }
                }
                if candidateNames.count == 1, let pageURL, taskURLs[index] != pageURL {
                    taskURLs[index] = pageURL
                    changed = true
                    if !automationEnabled {
                        appendLog("Đã gắn URL trang nhiệm vụ: \(name) → \(pageURL)")
                    }
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
        UIPasteboard.general.string = logs.filter { $0.contains("[CHẠM TAY]") }.joined(separator: "\n")
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
        resetAutomationPosition()
        saveState()
        onBack?()
    }

    @objc private func closeTapped() {
        stopObserver()
        sessionActive = false
        automationEnabled = false
        resetAutomationPosition()
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