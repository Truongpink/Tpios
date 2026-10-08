import UIKit

final class TPIOSLog {

static let shared = TPIOSLog()

private let queue = DispatchQueue(
    label: "com.tpios.logger",
    qos: .utility
)

private var lines: [String] = []
private let maxLines = 2000

private weak var logView: UITextView?
private weak var logWindow: UIView?
private weak var logController: UIViewController?

private weak var filterField: UITextField?
private weak var hideCandidatesButton: UIButton?

private var hideCandidateLines = true
private var filterText = ""

private var logStartFrame = CGRect.zero
private var resizeStartFrame = CGRect.zero
private var resizeStartPoint = CGPoint.zero
private weak var resizeHandle: UIView?

private init() {}

func log(
    _ message: String
) {

    let text =
        "[\(Self.time())] \(message)"

    queue.async { [weak self] in

        guard let self else {
            return
        }

        self.lines.append(text)

        if self.lines.count > self.maxLines {
            self.lines.removeFirst(
                self.lines.count - self.maxLines
            )
        }

        DispatchQueue.main.async {
            self.refreshView()
        }
    }
}

func error(
    _ message: String
) {
    log("ERROR: \(message)")
}

func clear() {

    queue.async { [weak self] in

        guard let self else {
            return
        }

        self.lines.removeAll()

        DispatchQueue.main.async {
            self.refreshView()
        }
    }
}

func show() {

    DispatchQueue.main.async { [weak self] in

        guard let self else {
            return
        }

        if self.logView != nil {
            self.refreshView()
            return
        }

        guard
            let windowScene =
                UIApplication.shared.connectedScenes
                    .compactMap({
                        $0 as? UIWindowScene
                    })
                    .first(where: {
                        $0.activationState != .unattached
                    })
        else {
            self.log(
                "ERROR: Không tìm thấy UIWindowScene"
            )
            return
        }

        let window =
            UIView(
                frame: windowScene.coordinateSpace.bounds
            )

        TPIOSPanelStyle.applyGlassBackground(to: window, cornerRadius: 24)

        let title =
            UILabel()

        title.text = "TPIOS LOG"
        title.textColor = .white
        title.font =
            .monospacedSystemFont(
                ofSize: 17,
                weight: .bold
            )
        title.textAlignment = .center

        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(moveLog(_:))
        )
        title.isUserInteractionEnabled = true
        title.addGestureRecognizer(pan)

        window.addSubview(title)

        let close =
            UIButton(type: .system)

        close.setTitle("×", for: .normal)
        close.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        close.titleLabel?.font =
            .systemFont(
                ofSize: 30,
                weight: .regular
            )

        close.addAction(
            UIAction { [weak self] _ in
                self?.hide()
            },
            for: .touchUpInside
        )

        window.addSubview(close)

        let saveLog = UIButton(type: .system)
        saveLog.setTitle("Lưu", for: .normal)
        saveLog.setTitleColor(UIColor.white.withAlphaComponent(0.85), for: .normal)
        saveLog.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        saveLog.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        saveLog.layer.cornerRadius = 10
        saveLog.translatesAutoresizingMaskIntoConstraints = false
        saveLog.addAction(
            UIAction { [weak self] _ in
                self?.saveLogToFile()
            },
            for: .touchUpInside
        )
        window.addSubview(saveLog)

        let clear =
            UIButton(type: .system)

        clear.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        clear.layer.cornerRadius = 10

        clear.setTitle(
            "Xóa log",
            for: .normal
        )

        clear.setTitleColor(UIColor.white.withAlphaComponent(0.70), for: .normal)

        clear.titleLabel?.font =
            .monospacedSystemFont(
                ofSize: 13,
                weight: .medium
            )

        clear.addAction(
            UIAction { [weak self] _ in
                self?.clear()
            },
            for: .touchUpInside
        )

        window.addSubview(clear)

        let capture =
            UIButton(type: .system)

        capture.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        capture.layer.cornerRadius = 10

        capture.setTitle(
            "Bắt mạng",
            for: .normal
        )

        capture.setTitleColor(UIColor.white.withAlphaComponent(0.70), for: .normal)

        capture.titleLabel?.font =
            .monospacedSystemFont(
                ofSize: 12,
                weight: .medium
            )

        capture.addAction(
            UIAction { [weak capture] _ in
                TPIOSNetworkLog.shared.install()
                capture?.setTitle("Đang bắt mạng", for: .normal)
            },
            for: .touchUpInside
        )

        window.addSubview(capture)

        let hideCandidates =
            UIButton(type: .system)

        hideCandidates.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        hideCandidates.layer.cornerRadius = 10

        hideCandidates.setTitleColor(UIColor.white.withAlphaComponent(0.70), for: .normal)

        hideCandidates.titleLabel?.font =
            .monospacedSystemFont(
                ofSize: 12,
                weight: .medium
            )

        hideCandidates.addAction(
            UIAction { [weak self] _ in
                self?.toggleHideCandidates()
            },
            for: .touchUpInside
        )

        window.addSubview(hideCandidates)
        self.hideCandidatesButton = hideCandidates
        updateHideCandidatesTitle()

        let filterField =
            UITextField()

        filterField.placeholder = "Lọc log (vd: Reload, WKWebView...)"
        filterField.text = filterText
        filterField.textColor = .white
        filterField.tintColor = .white
        filterField.attributedPlaceholder = NSAttributedString(
            string: "Lọc log (vd: Reload, WKWebView...)",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.35)]
        )
        filterField.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        filterField.layer.cornerRadius = 8
        filterField.font =
            .monospacedSystemFont(
                ofSize: 12,
                weight: .regular
            )
        filterField.autocorrectionType = .no
        filterField.autocapitalizationType = .none
        filterField.clearButtonMode = .whileEditing

        let leftPad = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        filterField.leftView = leftPad
        filterField.leftViewMode = .always

        filterField.addAction(
            UIAction { [weak self, weak filterField] _ in
                self?.filterText = filterField?.text ?? ""
                self?.refreshView()
            },
            for: .editingChanged
        )

        window.addSubview(filterField)
        self.filterField = filterField

        let textView =
            UITextView()

        textView.backgroundColor = UIColor(
            red: 0.075,
            green: 0.085,
            blue: 0.105,
            alpha: 1
        )
        textView.textColor = UIColor.white.withAlphaComponent(0.90)
        textView.layer.cornerRadius = 16
        textView.font =
            .monospacedSystemFont(
                ofSize: 12,
                weight: .regular
            )

        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.textContainerInset =
            UIEdgeInsets(
                top: 8,
                left: 8,
                bottom: 8,
                right: 8
            )

        window.addSubview(textView)

        let resizeHandle = UIView()
        resizeHandle.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        resizeHandle.layer.cornerRadius = 10
        resizeHandle.isUserInteractionEnabled = true

        let resizeIcon = UILabel()
        resizeIcon.text = "↘"
        resizeIcon.textColor = UIColor.white.withAlphaComponent(0.85)
        resizeIcon.font = .systemFont(ofSize: 20, weight: .bold)
        resizeIcon.textAlignment = .center
        resizeIcon.isUserInteractionEnabled = false
        resizeHandle.addSubview(resizeIcon)

        window.addSubview(resizeHandle)
        self.resizeHandle = resizeHandle

        let resizePan = UIPanGestureRecognizer(
            target: self,
            action: #selector(resizeLog(_:))
        )
        resizePan.cancelsTouchesInView = false
        resizeHandle.addGestureRecognizer(resizePan)

        title.translatesAutoresizingMaskIntoConstraints = false
        close.translatesAutoresizingMaskIntoConstraints = false
        clear.translatesAutoresizingMaskIntoConstraints = false
        capture.translatesAutoresizingMaskIntoConstraints = false
        hideCandidates.translatesAutoresizingMaskIntoConstraints = false
        filterField.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeIcon.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([

            title.topAnchor.constraint(
                equalTo: window.topAnchor,
                constant: 8
            ),

            title.centerXAnchor.constraint(
                equalTo: window.centerXAnchor
            ),

            title.heightAnchor.constraint(
                equalToConstant: 30
            ),

            saveLog.trailingAnchor.constraint(
                equalTo: close.leadingAnchor,
                constant: -4
            ),

            saveLog.topAnchor.constraint(
                equalTo: close.topAnchor,
                constant: 6
            ),

            saveLog.widthAnchor.constraint(
                equalToConstant: 56
            ),

            saveLog.heightAnchor.constraint(
                equalToConstant: 28
            ),

            close.trailingAnchor.constraint(
                equalTo: window.trailingAnchor,
                constant: -6
            ),

            close.topAnchor.constraint(
                equalTo: window.topAnchor,
                constant: 2
            ),

            close.widthAnchor.constraint(
                equalToConstant: 40
            ),

            close.heightAnchor.constraint(
                equalToConstant: 40
            ),

            clear.leadingAnchor.constraint(
                equalTo: window.leadingAnchor,
                constant: 8
            ),

            clear.topAnchor.constraint(
                equalTo: window.topAnchor,
                constant: 6
            ),

            clear.widthAnchor.constraint(
                equalToConstant: 65
            ),

            clear.heightAnchor.constraint(
                equalToConstant: 32
            ),

            capture.leadingAnchor.constraint(
                equalTo: window.leadingAnchor,
                constant: 8
            ),

            capture.topAnchor.constraint(
                equalTo: clear.bottomAnchor,
                constant: 6
            ),

            capture.heightAnchor.constraint(
                equalToConstant: 28
            ),

            capture.widthAnchor.constraint(
                equalToConstant: 78
            ),

            hideCandidates.leadingAnchor.constraint(
                equalTo: capture.trailingAnchor,
                constant: 6
            ),

            hideCandidates.topAnchor.constraint(
                equalTo: capture.topAnchor
            ),

            hideCandidates.widthAnchor.constraint(
                equalToConstant: 90
            ),

            hideCandidates.heightAnchor.constraint(
                equalToConstant: 28
            ),

            filterField.leadingAnchor.constraint(
                equalTo: window.leadingAnchor,
                constant: 8
            ),

            filterField.topAnchor.constraint(
                equalTo: capture.bottomAnchor,
                constant: 6
            ),

            filterField.trailingAnchor.constraint(
                equalTo: window.trailingAnchor,
                constant: -8
            ),

            filterField.heightAnchor.constraint(
                equalToConstant: 28
            ),

            textView.topAnchor.constraint(
                equalTo: filterField.bottomAnchor,
                constant: 6
            ),

            textView.leadingAnchor.constraint(
                equalTo: window.leadingAnchor
            ),

            textView.trailingAnchor.constraint(
                equalTo: window.trailingAnchor
            ),

            textView.bottomAnchor.constraint(
                equalTo: window.bottomAnchor
            ),

            resizeHandle.trailingAnchor.constraint(
                equalTo: window.trailingAnchor,
                constant: -2
            ),

            resizeHandle.bottomAnchor.constraint(
                equalTo: window.bottomAnchor,
                constant: -2
            ),

            resizeHandle.widthAnchor.constraint(
                equalToConstant: 38
            ),

            resizeHandle.heightAnchor.constraint(
                equalToConstant: 38
            ),

            resizeIcon.centerXAnchor.constraint(
                equalTo: resizeHandle.centerXAnchor
            ),

            resizeIcon.centerYAnchor.constraint(
                equalTo: resizeHandle.centerYAnchor
            )
        ])

        if let hostWindow = windowScene.windows.first {

            hostWindow.addSubview(window)

            let safe =
                hostWindow.safeAreaInsets

            let width: CGFloat =
                min(190, hostWindow.bounds.width - 20)
            let height: CGFloat =
                min(
                    230,
                    hostWindow.bounds.height
                    - safe.top
                    - safe.bottom
                    - 20
                )

            window.frame =
                CGRect(
                    x:
                        max(
                            10,
                            (hostWindow.bounds.width - width) / 2
                        ),
                    y: safe.top + 10,
                    width: max(180, width),
                    height: max(220, height)
                )
        }

        self.logView = textView
        self.logWindow = window

        self.refreshView()
    }
}

@objc private func moveLog(
    _ gesture: UIPanGestureRecognizer
) {

    guard
        let window = logWindow,
        let host = window.superview
    else {
        return
    }

    switch gesture.state {

    case .began:
        logStartFrame = window.frame

    case .changed, .ended:

        let translation =
            gesture.translation(in: host)

        var frame = logStartFrame

        frame.origin.x += translation.x
        frame.origin.y += translation.y

        let margin: CGFloat = 10
        let safe = host.safeAreaInsets

        let minX = margin
        let maxX =
            max(
                minX,
                host.bounds.width
                - frame.width
                - margin
            )

        let minY =
            safe.top + margin

        let maxY =
            max(
                minY,
                host.bounds.height
                - safe.bottom
                - frame.height
                - margin
            )

        frame.origin.x =
            min(
                max(frame.origin.x, minX),
                maxX
            )

        frame.origin.y =
            min(
                max(frame.origin.y, minY),
                maxY
            )

        window.frame = frame

    default:
        break
    }
}

@objc private func resizeLog(
    _ gesture: UIPanGestureRecognizer
) {
    guard
        let window = logWindow,
        let host = window.superview
    else {
        return
    }

    switch gesture.state {
    case .began:
        resizeStartFrame = window.frame
        resizeStartPoint = gesture.location(in: host)

    case .changed, .ended:
        let point = gesture.location(in: host)
        let dx = point.x - resizeStartPoint.x
        let dy = point.y - resizeStartPoint.y

        let safe = host.safeAreaInsets
        let minWidth: CGFloat = 160
        let minHeight: CGFloat = 180

        let maxWidth = max(
            minWidth,
            host.bounds.width - resizeStartFrame.origin.x - 10
        )

        let maxHeight = max(
            minHeight,
            host.bounds.height
            - safe.bottom
            - resizeStartFrame.origin.y
            - 10
        )

        let width = min(
            max(minWidth, resizeStartFrame.width + dx),
            maxWidth
        )

        let height = min(
            max(minHeight, resizeStartFrame.height + dy),
            maxHeight
        )

        window.frame = CGRect(
            x: resizeStartFrame.origin.x,
            y: resizeStartFrame.origin.y,
            width: width,
            height: height
        )

    default:
        break
    }
}

func hide() {

    DispatchQueue.main.async { [weak self] in

        guard let self else {
            return
        }

        self.logWindow?.removeFromSuperview()

        self.logWindow = nil
        self.logView = nil
        self.logController = nil
    }
}

private func toggleHideCandidates() {
    hideCandidateLines.toggle()
    updateHideCandidatesTitle()
    refreshView()
}

private func updateHideCandidatesTitle() {
    hideCandidatesButton?.setTitle(
        hideCandidateLines ? "Hiện candidate" : "Ẩn candidate",
        for: .normal
    )
}

// Lưu nội dung đang hiện trong khung log (theo bộ lọc hiện tại) thành file
// .txt rồi mở bảng chia sẻ của iOS, chọn "Lưu vào Tệp" hoặc gửi đi luôn.
// Muốn lưu toàn bộ log thì xoá ô lọc trước khi bấm Lưu.
private func saveLogToFile() {
    let text = logView?.text ?? ""

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let name = "TPIOS-log-\(formatter.string(from: Date())).txt"

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        return
    }

    let root = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?
        .rootViewController

    var top = root
    while let presented = top?.presentedViewController {
        top = presented
    }

    guard let presenter = top else { return }

    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = presenter.view
    presenter.present(sheet, animated: true)
}

private func refreshView() {

    guard
        let textView = logView
    else {
        return
    }

    queue.async { [weak self] in

        guard let self else {
            return
        }

        let snapshot = self.lines

        DispatchQueue.main.async {

            let filter = self.filterText
            let hideCandidates = self.hideCandidateLines

            let filtered =
                snapshot.filter { line in
                    if hideCandidates,
                       line.contains("ReloadCandidate:") {
                        return false
                    }
                    if filter.isEmpty {
                        return true
                    }
                    return line.localizedCaseInsensitiveContains(filter)
                }

            let text =
                filtered.joined(separator: "\n")

            textView.text = text

            if !text.isEmpty {

                let range =
                    NSRange(
                        location:
                            max(
                                0,
                                textView.text.count - 1
                            ),
                        length: 1
                    )

                textView.scrollRangeToVisible(
                    range
                )
            }
        }
    }
}

private static func time() -> String {

    let formatter =
        DateFormatter()

    formatter.dateFormat =
        "HH:mm:ss.SSS"

    return formatter.string(
        from: Date()
    )
}
}
