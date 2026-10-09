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
    private let tapTestLabel = UILabel()

    private let bypassLabel = UILabel()
    private let saleLabel = UILabel()
    private let logLabel = UILabel()
    private let adBlockLabel = UILabel()
    private let clockLabel = UILabel()
    private let reloadLabel = UILabel()
    private let buyAllLabel = UILabel()

    private var saleClock: TPIOSSaleClock?
    private var buyAllView: TPIOSMuaAll?
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

        for view in [bypassButton, saleButton, logButton, adBlockButton, clockButton, reloadButton, buyAllButton, tapTestButton] as [UIView] {
            addSubview(view)
        }
        for label in [bypassLabel, saleLabel, logLabel, adBlockLabel, clockLabel, reloadLabel, buyAllLabel, tapTestLabel] {
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

        let icons = [bypassButton, saleButton, logButton, adBlockButton, clockButton, reloadButton, buyAllButton, tapTestButton]
        let labels = [bypassLabel, saleLabel, logLabel, adBlockLabel, clockLabel, reloadLabel, buyAllLabel, tapTestLabel]
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
        parent.bringSubviewToFront(clock)
        saleClock = clock
        clock.start()
    }

    @objc private func locationTapped() {
        guard let parent = superview else { return }
        if locationView != nil { closeLocation(); return }
        let width = min(340, max(260, parent.bounds.width - 24))
        let height = min(560, max(390, parent.bounds.height - 60))
        let x = max(12, (parent.bounds.width - width) / 2)
        let y = max(20, min(frame.maxY + 14, parent.bounds.height - height - 20))
        let view = TPIOSLocation(frame: CGRect(x: x, y: y, width: width, height: height))
        view.onBack = { [weak self] in self?.closeLocation() }
        view.onClose = { [weak self] in self?.closeLocation() }
        parent.addSubview(view)
        parent.bringSubviewToFront(view)
        locationView = view
    }

    private func closeLocation() {
        locationView?.removeFromSuperview()
        locationView = nil
    }

    @objc private func saleTapped() {
        guard let parent = superview else { return }
        if saleView != nil { closeSale(); return }
        let width = min(350, max(280, parent.bounds.width - 20))
        let height = min(620, max(400, parent.bounds.height - 40))
        let x = max(10, (parent.bounds.width - width) / 2)
        let y = max(10, min(frame.maxY + 12, parent.bounds.height - height - 10))
        let view = TPIOSSale(frame: CGRect(x: x, y: y, width: width, height: height))
        view.onBack = { [weak self] in self?.closeSale() }
        view.onClose = { [weak self] in self?.closeSale() }
        parent.addSubview(view)
        parent.bringSubviewToFront(view)
        saleView = view
    }

    private func closeSale() {
        saleView?.removeFromSuperview()
        saleView = nil
    }

    @objc private func adBlockTapped() {
        guard let parent = superview else { return }
        if adBlocker != nil { closeAdBlock(); return }
        let width = min(350, max(280, parent.bounds.width - 20))
        let height = min(560, max(380, parent.bounds.height - 40))
        let x = max(10, (parent.bounds.width - width) / 2)
        let y = max(10, min(frame.maxY + 12, parent.bounds.height - height - 10))
        let view = TPIOSAdBlock(frame: CGRect(x: x, y: y, width: width, height: height))
        view.onBack = { [weak self] in self?.closeAdBlock() }
        view.onClose = { [weak self] in self?.closeAdBlock() }
        parent.addSubview(view)
        parent.bringSubviewToFront(view)
        adBlocker = view
    }

    private func closeAdBlock() {
        adBlocker?.removeFromSuperview()
        adBlocker = nil
    }

    @objc private func reloadTapped() {
        TPIOSReload.shared.reloadCurrentPage()
    }

    @objc private func buyAllTapped() {
        guard let parent = superview else { return }
        if buyAllView != nil { closeBuyAll(); return }
        let width = min(340, max(280, parent.bounds.width - 20))
        let height = min(560, max(390, parent.bounds.height - 40))
        let x = max(10, (parent.bounds.width - width) / 2)
        let y = max(10, min(frame.maxY + 12, parent.bounds.height - height - 10))
        let view = TPIOSMuaAll(frame: CGRect(x: x, y: y, width: width, height: height))
        view.onBack = { [weak self] in self?.closeBuyAll() }
        view.onClose = { [weak self] in self?.closeBuyAll() }
        parent.addSubview(view)
        parent.bringSubviewToFront(view)
        buyAllView = view
    }

    private func closeBuyAll() {
        buyAllView?.removeFromSuperview()
        buyAllView = nil
    }

    private func closeSaleClock() {
        saleClock?.stop()
        saleClock?.removeFromSuperview()
        saleClock = nil
    }

    private func clamp(_ rect: inout CGRect, in parent: UIView) {
        rect.origin.x = max(0, min(rect.origin.x, max(0, parent.bounds.width - rect.width)))
        rect.origin.y = max(0, min(rect.origin.y, max(0, parent.bounds.height - rect.height)))
    }
}
