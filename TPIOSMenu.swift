import UIKit

extension Notification.Name {
    static let tpiosCloseMenu = Notification.Name("tpiosCloseMenu")
}

final class TPIOSMenu: UIView, UIGestureRecognizerDelegate {

    private let headerHeight: CGFloat = 66
    private let handleSize: CGFloat = 44
    private let minWidth: CGFloat = 240
    private let minHeight: CGFloat = 330
    private let designWidth: CGFloat = 240
    private let designHeight: CGFloat = 350

    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let statusDot = UIView()
    private let closeButton = UIButton(type: .system)

    private let bypassButton = UIButton(type: .system)
    private let saleButton = UIButton(type: .system)
    private let logButton = UIButton(type: .system)
    private let adBlockButton = UIButton(type: .system)
    private let clockButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let buyAllButton = UIButton(type: .system)
    private let tapTestButton = UIButton(type: .system)
    private let caoXuButton = UIButton(type: .system)
    private let tapTestLabel = UILabel()
    private let caoXuLabel = UILabel()

    private let bypassLabel = UILabel()
    private let saleLabel = UILabel()
    private let logLabel = UILabel()
    private let adBlockLabel = UILabel()
    private let clockLabel = UILabel()
    private let reloadLabel = UILabel()
    private let buyAllLabel = UILabel()

    private var saleClock: TPIOSSaleClock?
    private var buyAllView: TPIOSMuaAll?
    private var caoXuView: TPIOSCaoXu?
    private let footerLabel = UILabel()
    private let resizeHandle = UILabel()

    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero
    private var locationView: TPIOSLocation?
    private var saleView: TPIOSSale?
    private var adBlocker: TPIOSAdBlock?

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
        setupButtons()
        setupFooter()
        setupResize()
        setupMove()
    }

    private func setupHeader() {
        headerView.backgroundColor = UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1)
        headerView.layer.cornerRadius = 24
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(headerView)

        statusDot.backgroundColor = UIColor(red: 0.30, green: 0.95, blue: 0.55, alpha: 1)
        statusDot.layer.cornerRadius = 5
        headerView.addSubview(statusDot)

        titleLabel.text = "TPIOS"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        headerView.addSubview(titleLabel)

        subtitleLabel.text = "Design By TRUONGPHONG"
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.48)
        subtitleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        headerView.addSubview(subtitleLabel)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.75)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        closeButton.layer.cornerRadius = 17
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addSubview(closeButton)
    }

    private func setupButtons() {
        configureIconButton(bypassButton, icon: "location.fill", colors: [UIColor(red: 1.00, green: 0.65, blue: 0.25, alpha: 1), UIColor(red: 0.85, green: 0.25, blue: 0.08, alpha: 1)], action: #selector(locationTapped))
        configureCaptionLabel(bypassLabel, text: "Vị trí")

        configureIconButton(saleButton, icon: "bag.fill", colors: [UIColor(red: 0.68, green: 0.47, blue: 1.00, alpha: 1), UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)], action: #selector(saleTapped))
        configureCaptionLabel(saleLabel, text: "Sale")

        configureIconButton(logButton, icon: "doc.text.magnifyingglass", colors: [UIColor(red: 0.36, green: 0.71, blue: 1.00, alpha: 1), UIColor(red: 0.09, green: 0.39, blue: 0.80, alpha: 1)], action: #selector(logTapped))
        configureCaptionLabel(logLabel, text: "Xem log")

        configureIconButton(adBlockButton, icon: "shield.fill", colors: [UIColor(red: 1.00, green: 0.35, blue: 0.27, alpha: 1), UIColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)], action: #selector(adBlockTapped))
        configureCaptionLabel(adBlockLabel, text: "Tắt QC")

        configureIconButton(clockButton, icon: "clock.fill", colors: [UIColor(red: 0.36, green: 0.88, blue: 0.55, alpha: 1), UIColor(red: 0.06, green: 0.52, blue: 0.33, alpha: 1)], action: #selector(clockTapped))
        configureCaptionLabel(clockLabel, text: "Đồng hồ")

        configureIconButton(reloadButton, icon: "arrow.clockwise", colors: [UIColor(red: 0.27, green: 0.84, blue: 0.84, alpha: 1), UIColor(red: 0.04, green: 0.43, blue: 0.55, alpha: 1)], action: #selector(reloadTapped))
        configureCaptionLabel(reloadLabel, text: "Tải lại")

        configureIconButton(buyAllButton, icon: "cart.fill", colors: [UIColor(red: 1.00, green: 0.40, blue: 0.70, alpha: 1), UIColor(red: 0.72, green: 0.12, blue: 0.48, alpha: 1)], action: #selector(buyAllTapped))
        configureCaptionLabel(buyAllLabel, text: "Mua all")

        configureIconButton(
            tapTestButton,
            icon: "hand.tap.fill",
            colors: [
                UIColor(red: 0.95, green: 0.30, blue: 0.60, alpha: 1),
                UIColor(red: 0.55, green: 0.10, blue: 0.45, alpha: 1)
            ],
            action: #selector(tapTestTapped)
        )
        configureCaptionLabel(tapTestLabel, text: "Chạm")

        configureIconButton(
            caoXuButton,
            icon: "sparkles",
            colors: [UIColor(red: 1.00, green: 0.68, blue: 0.22, alpha: 1), UIColor(red: 0.86, green: 0.34, blue: 0.08, alpha: 1)],
            action: #selector(caoXuTapped)
        )
        configureCaptionLabel(caoXuLabel, text: "Cào xu")

        for view in [bypassButton, saleButton, logButton, adBlockButton, clockButton, reloadButton, buyAllButton, tapTestButton, caoXuButton] as [UIView] {
            addSubview(view)
        }
        for label in [bypassLabel, saleLabel, logLabel, adBlockLabel, clockLabel, reloadLabel, buyAllLabel, tapTestLabel, caoXuLabel] {
            addSubview(label)
        }
    }

    private func configureIconButton(_ button: UIButton, icon: String, colors: [UIColor], action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.tintColor = .white
        TPIOSPanelStyle.applyGradientFill(to: button, colors: colors, cornerRadius: 18)
        button.layer.cornerRadius = 18
        button.imageView?.contentMode = .center
        if let imageView = button.imageView { button.bringSubviewToFront(imageView) }
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func configureCaptionLabel(_ label: UILabel, text: String) {
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
    }

    private func setupFooter() {
        footerLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        footerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        footerLabel.textAlignment = .center
        footerLabel.adjustsFontSizeToFitWidth = true
        footerLabel.minimumScaleFactor = 0.7
        footerLabel.text = calendarFooterText()
        addSubview(footerLabel)
    }

    private func calendarFooterText() -> String {
        let now = Date()
        let solarFormatter = DateFormatter()
        solarFormatter.dateFormat = "dd/MM/yyyy"
        let solarText = solarFormatter.string(from: now)
        var lunarCalendar = Calendar(identifier: .chinese)
        lunarCalendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current
        let components = lunarCalendar.dateComponents([.day, .month], from: now)
        guard let day = components.day, let month = components.month else { return solarText }
        return "\(solarText)  •  " + String(format: "%02d/%02d Âm lịch", day, month)
    }

    private func setupMove() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(moveMenu(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        headerView.addGestureRecognizer(pan)
    }

    @objc private func moveMenu(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else { return }
        guard gesture.state == .began || gesture.state == .changed else { return }
        let delta = gesture.translation(in: parent)
        var newFrame = frame
        newFrame.origin.x += delta.x
        newFrame.origin.y += delta.y
        clamp(&newFrame, in: parent)
        frame = newFrame
        gesture.setTranslation(.zero, in: parent)
    }

    private func setupResize() {
        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.42)
        resizeHandle.font = .systemFont(ofSize: 19, weight: .medium)
        resizeHandle.textAlignment = .center
        resizeHandle.isUserInteractionEnabled = true
        addSubview(resizeHandle)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(resizeMenu(_:)))
        pan.cancelsTouchesInView = false
        resizeHandle.addGestureRecognizer(pan)
    }

    @objc private func resizeMenu(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else { return }
        switch gesture.state {
        case .began:
            resizeStartFrame = frame
            resizeStartPoint = gesture.location(in: parent)
        case .changed:
            let point = gesture.location(in: parent)
            let dx = point.x - resizeStartPoint.x
            let dy = point.y - resizeStartPoint.y
            let width = max(minWidth, min(resizeStartFrame.width + dx, parent.bounds.width - resizeStartFrame.origin.x))
            let height = max(minHeight, min(resizeStartFrame.height + dy, parent.bounds.height - resizeStartFrame.origin.y))
            frame = CGRect(x: resizeStartFrame.origin.x, y: resizeStartFrame.origin.y, width: width, height: height)
        default:
            break
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let scale = min(bounds.width / designWidth, bounds.height / designHeight)
        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight * scale)
        let header = headerHeight * scale
        statusDot.frame = CGRect(x: 18 * scale, y: 27 * scale, width: 10 * scale, height: 10 * scale)
        titleLabel.frame = CGRect(x: 36 * scale, y: 12 * scale, width: max(0, bounds.width - 96 * scale), height: 25 * scale)
        titleLabel.font = .systemFont(ofSize: max(12, 19 * scale), weight: .bold)
        subtitleLabel.frame = CGRect(x: 36 * scale, y: 38 * scale, width: max(0, bounds.width - 96 * scale), height: 13 * scale)
        subtitleLabel.font = .systemFont(ofSize: max(8, 10 * scale), weight: .semibold)
        closeButton.frame = CGRect(x: bounds.width - 50 * scale, y: 16 * scale, width: 34 * scale, height: 34 * scale)

        let sidePadding = 14 * scale
        let columnGap = 10 * scale
        let rowGap = 8 * scale
        let iconLabelGap = 3 * scale
        let labelHeight = 15 * scale
        let gridTop = header + 12 * scale
        let contentWidth = max(0, bounds.width - sidePadding * 2)
        let columnWidth = max(0, (contentWidth - columnGap * 2) / 3)
        let iconSize = min(columnWidth, 58 * scale)
        let iconXInset = max(0, (columnWidth - iconSize) / 2)
        let rowHeight = iconSize + iconLabelGap + labelHeight

        let icons = [bypassButton, saleButton, logButton, adBlockButton, clockButton, reloadButton, buyAllButton, tapTestButton, caoXuButton]
        let labels = [bypassLabel, saleLabel, logLabel, adBlockLabel, clockLabel, reloadLabel, buyAllLabel, tapTestLabel, caoXuLabel]

        for index in 0..<icons.count {
            let column = index % 3
            let row = index / 3
            let columnX = sidePadding + CGFloat(column) * (columnWidth + columnGap)
            let rowY = gridTop + CGFloat(row) * (rowHeight + rowGap)

            icons[index].frame = CGRect(x: columnX + iconXInset, y: rowY, width: iconSize, height: iconSize)
            icons[index].layer.cornerRadius = iconSize * 0.28
            TPIOSPanelStyle.syncFrames(in: icons[index])
            labels[index].frame = CGRect(x: columnX, y: rowY + iconSize + iconLabelGap, width: columnWidth, height: labelHeight)
            labels[index].font = .systemFont(ofSize: max(8, 13 * scale), weight: .semibold)
        }

        footerLabel.frame = CGRect(x: 14 * scale, y: bounds.height - 30 * scale, width: max(0, bounds.width - 28 * scale), height: 18 * scale)
        footerLabel.isHidden = bounds.height < 270

        resizeHandle.frame = CGRect(x: bounds.width - handleSize, y: bounds.height - handleSize, width: handleSize, height: handleSize)
        resizeHandle.font = .systemFont(ofSize: 19, weight: .medium)
    }

    @objc private func tapTestTapped() {
        TPIOSTapTest.shared.onFinish = { [weak self] in
            self?.isHidden = false
        }
        isHidden = true
        TPIOSTapTest.shared.start()
    }

    @objc private func closeTapped() {
        closeLocation()
        closeSale()
        closeAdBlock()
        closeBuyAll()
        closeCaoXu()
        NotificationCenter.default.post(name: .tpiosCloseMenu, object: nil)
    }

    @objc private func logTapped() {
        TPIOSLog.shared.log("Mở cửa sổ log")
        TPIOSLog.shared.show()
    }

    @objc private func clockTapped() {
        guard let parent = superview else { return }
        if saleClock == nil { saleClock = parent.subviews.compactMap { $0 as? TPIOSSaleClock }.last }
        if saleClock != nil { closeSaleClock(); return }
        let width = min(310, max(190, parent.bounds.width - 24))
        let height = width / TPIOSSaleClock.defaultAspectRatio
        let x = max(12, (parent.bounds.width - width) / 2)
        let y = max(20, min(frame.maxY + 20, parent.bounds.height - height - 20))
        let clock = TPIOSSaleClock(frame: CGRect(x: x, y: y, width: width, height: height))
        clock.onClose = { [weak self, weak clock] in
            clock?.stop()
            clock?.removeFromSuperview()
            self?.saleClock = nil
        }
        parent.addSubview(clock)
        saleClock = clock
        clock.start()
    }

    private func closeSaleClock() {
        saleClock?.stop()
        saleClock?.removeFromSuperview()
        saleClock = nil
    }

    @objc private func reloadTapped() { TPIOSReload.shared.reloadCurrentPage() }

    @objc private func adBlockTapped() {
        guard locationView == nil, saleView == nil, buyAllView == nil, let parent = superview else { return }
        let blocker = TPIOSAdBlock.shared
        blocker.onClose = { [weak self] in self?.closeAdBlock() }
        blocker.prepareForDisplay(frame: frame)
        parent.addSubview(blocker)
        adBlocker = blocker
        isHidden = true
        blocker.beginOrShow()
    }

    private func closeAdBlock() {
        adBlocker?.removeFromSuperview()
        adBlocker = nil
        isHidden = false
    }

    @objc private func locationTapped() {
        guard locationView == nil, saleView == nil, buyAllView == nil, let parent = superview else { return }
        let width = min(frame.width, parent.bounds.width)
        let height = min(420, parent.bounds.height)
        let childFrame = CGRect(x: frame.origin.x, y: frame.origin.y, width: width, height: height)
        let location = TPIOSLocation(frame: childFrame)
        location.onBack = { [weak self] in self?.closeLocation() }
        location.onClose = { [weak self] in
            self?.closeLocation()
            NotificationCenter.default.post(name: .tpiosCloseMenu, object: nil)
        }
        parent.addSubview(location)
        locationView = location
        isHidden = true
    }

    private func closeLocation() {
        locationView?.removeFromSuperview()
        locationView = nil
        isHidden = false
    }

    @objc private func saleTapped() {
        guard locationView == nil, saleView == nil, buyAllView == nil, let parent = superview else { return }
        let sale = TPIOSSale(frame: frame)
        sale.onBack = { [weak self] in self?.closeSale() }
        sale.onClose = { [weak self] in
            self?.closeSale()
            NotificationCenter.default.post(name: .tpiosCloseMenu, object: nil)
        }
        parent.addSubview(sale)
        saleView = sale
        isHidden = true
    }

    private func closeSale() {
        saleView?.removeFromSuperview()
        saleView = nil
        isHidden = false
    }

    @objc private func caoXuTapped() {
        guard locationView == nil, saleView == nil, buyAllView == nil, caoXuView == nil, let parent = superview else { return }
        let width = min(320, max(280, parent.bounds.width - 20))
        let height = min(520, max(420, parent.bounds.height - 40))
        let x = max(10, min(frame.origin.x, parent.bounds.width - width - 10))
        let y = max(10, min(frame.origin.y, parent.bounds.height - height - 10))
        let panel = TPIOSCaoXu(frame: CGRect(x: x, y: y, width: width, height: height))
        panel.onBack = { [weak self] in self?.closeCaoXu() }
        panel.onClose = { [weak self] in
            self?.closeCaoXu()
            NotificationCenter.default.post(name: .tpiosCloseMenu, object: nil)
        }
        parent.addSubview(panel)
        caoXuView = panel
        isHidden = true
    }

    private func closeCaoXu() {
        caoXuView?.removeFromSuperview()
        caoXuView = nil
        isHidden = false
    }

    @objc private func buyAllTapped() {
        guard locationView == nil, saleView == nil, buyAllView == nil, let parent = superview else { return }
        let panel = TPIOSMuaAll(frame: CGRect(x: frame.origin.x, y: frame.origin.y, width: 200, height: 220))
        panel.onBack = { [weak self] in self?.closeBuyAll() }
        panel.onClose = { [weak self] in
            self?.closeBuyAll()
            NotificationCenter.default.post(name: .tpiosCloseMenu, object: nil)
        }
        parent.addSubview(panel)
        buyAllView = panel
        isHidden = true
    }

    private func closeBuyAll() {
        buyAllView?.removeFromSuperview()
        buyAllView = nil
        isHidden = false
    }

    private func clamp(_ rect: inout CGRect, in parent: UIView) {
        let maxX = max(0, parent.bounds.width - rect.width)
        let maxY = max(0, parent.bounds.height - rect.height)
        rect.origin.x = max(0, min(rect.origin.x, maxX))
        rect.origin.y = max(0, min(rect.origin.y, maxY))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
}

// MARK: - Mua all

private final class TPIOSMuaAll: UIView, UIGestureRecognizerDelegate {

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private let headerHeight: CGFloat = 48
    private let handleSize: CGFloat = 44
    private let minWidth: CGFloat = 160
    private let minHeight: CGFloat = 180
    private let designWidth: CGFloat = 200
    private let designHeight: CGFloat = 220

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let resizeHandle = UILabel()
    private let buttons: [UIButton]
    private let labels: [UILabel]
    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero

    override init(frame: CGRect) {
        let titles = ["Quét IAP", "Sản phẩm", "Phân tích", "Giao dịch"]
        let icons = ["viewfinder", "bag", "chart.bar.xaxis", "arrow.left.arrow.right"]
        let colors: [[UIColor]] = [
            [UIColor(red: 0.98, green: 0.45, blue: 0.55, alpha: 1), UIColor(red: 0.78, green: 0.18, blue: 0.35, alpha: 1)],
            [UIColor(red: 0.38, green: 0.65, blue: 1.00, alpha: 1), UIColor(red: 0.15, green: 0.32, blue: 0.78, alpha: 1)],
            [UIColor(red: 0.68, green: 0.47, blue: 1.00, alpha: 1), UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)],
            [UIColor(red: 0.36, green: 0.88, blue: 0.55, alpha: 1), UIColor(red: 0.06, green: 0.52, blue: 0.33, alpha: 1)]
        ]

        var createdButtons: [UIButton] = []
        var createdLabels: [UILabel] = []
        for index in 0..<4 {
            let button = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
            button.setImage(UIImage(systemName: icons[index], withConfiguration: config), for: .normal)
            button.tintColor = .white
            TPIOSPanelStyle.applyGradientFill(to: button, colors: colors[index], cornerRadius: 16)
            button.layer.cornerRadius = 16
            button.tag = index
            createdButtons.append(button)

            let label = UILabel()
            label.text = titles[index]
            label.textColor = .white
            label.font = .systemFont(ofSize: 11.5, weight: .semibold)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.65
            createdLabels.append(label)
        }
        buttons = createdButtons
        labels = createdLabels
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        TPIOSPanelStyle.applyGlassBackground(to: self, cornerRadius: 24)
        headerView.backgroundColor = UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1)
        headerView.layer.cornerRadius = 24
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(headerView)

        backButton.setTitle("‹", for: .normal)
        backButton.setTitleColor(.white, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 30)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        headerView.addSubview(backButton)

        titleLabel.text = "MUA ALL"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)

        closeButton.setTitle("×", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 26)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addSubview(closeButton)

        for index in 0..<4 {
            buttons[index].addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            addSubview(buttons[index])
            addSubview(labels[index])
        }

        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.55)
        resizeHandle.font = .systemFont(ofSize: 19)
        resizeHandle.textAlignment = .center
        resizeHandle.isUserInteractionEnabled = true
        addSubview(resizeHandle)

        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(resizePanned(_:)))
        resizePan.cancelsTouchesInView = false
        resizeHandle.addGestureRecognizer(resizePan)

        let movePan = UIPanGestureRecognizer(target: self, action: #selector(movePanned(_:)))
        movePan.delegate = self
        movePan.cancelsTouchesInView = false
        headerView.addGestureRecognizer(movePan)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(1, min(bounds.width / designWidth, bounds.height / designHeight))
        let header = headerHeight * scale
        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: header)
        backButton.frame = CGRect(x: 2 * scale, y: 2 * scale, width: 40 * scale, height: 38 * scale)
        backButton.titleLabel?.font = .systemFont(ofSize: max(16, 30 * scale))
        titleLabel.frame = CGRect(x: 42 * scale, y: 0, width: max(0, bounds.width - 84 * scale), height: header)
        titleLabel.font = .systemFont(ofSize: max(10, 16 * scale), weight: .bold)
        closeButton.frame = CGRect(x: bounds.width - 42 * scale, y: 3 * scale, width: 38 * scale, height: 36 * scale)
        closeButton.titleLabel?.font = .systemFont(ofSize: max(15, 26 * scale))

        let side = 12 * scale
        let gap = 7 * scale
        let top = header + 9 * scale
        let width = max(0, (bounds.width - side * 2 - gap) / 2)
        let icon = min(width, 52 * scale)
        let labelHeight = 14 * scale
        let rowHeight = icon + 2 * scale + labelHeight
        let rowGap = 4 * scale

        for index in 0..<4 {
            let column = index % 2
            let row = index / 2
            let x = side + CGFloat(column) * (width + gap)
            let y = top + CGFloat(row) * (rowHeight + rowGap)
            let iconX = x + max(0, (width - icon) / 2)
            buttons[index].frame = CGRect(x: iconX, y: y, width: icon, height: icon)
            buttons[index].layer.cornerRadius = icon * 0.28
            TPIOSPanelStyle.syncFrames(in: buttons[index])
            labels[index].frame = CGRect(x: x, y: y + icon + 1 * scale, width: width, height: labelHeight)
            labels[index].font = .systemFont(ofSize: max(8, 11.5 * scale), weight: .semibold)
        }

        resizeHandle.frame = CGRect(x: bounds.width - handleSize, y: bounds.height - handleSize, width: handleSize, height: handleSize)
        resizeHandle.font = .systemFont(ofSize: 19)
    }

    @objc private func optionTapped(_ sender: UIButton) {
        let title = labels[sender.tag].text ?? ""
        let message: String
        switch sender.tag {
        case 0:
            message = TPIOSAppScanner.summary() + "\n\n" + TPIOSPaymentScanner.summary()
        case 1:
            message = "Chẩn đoán sản phẩm StoreKit chưa có Product ID để truy vấn. Có thể bổ sung danh sách ID ở bước sau."
        case 2:
            message = TPIOSPaymentScanner.receiptInfo()
        case 3:
            message = TPIOSPaymentScanner.storeKit1Status()
        default:
            return
        }
        presentAlert(title: title, message: message)
        TPIOSLog.shared.log("Mua all: \(title)")
    }

    private func presentAlert(title: String, message: String) {
        guard let controller = window?.rootViewController else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        controller.present(alert, animated: true)
    }

    @objc private func backTapped() { onBack?() }
    @objc private func closeTapped() { onClose?() }

    @objc private func movePanned(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview, gesture.state == .began || gesture.state == .changed else { return }
        let delta = gesture.translation(in: parent)
        var newFrame = frame
        newFrame.origin.x += delta.x
        newFrame.origin.y += delta.y
        clamp(&newFrame, in: parent)
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

    private func clamp(_ rect: inout CGRect, in parent: UIView) {
        rect.origin.x = max(0, min(rect.origin.x, max(0, parent.bounds.width - rect.width)))
        rect.origin.y = max(0, min(rect.origin.y, max(0, parent.bounds.height - rect.height)))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
}
