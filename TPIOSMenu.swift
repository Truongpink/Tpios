import UIKit

extension Notification.Name {
    static let tpiosCloseMenu =
        Notification.Name("tpiosCloseMenu")
}

final class TPIOSMenu: UIView,
                       UIGestureRecognizerDelegate {

    private let headerHeight: CGFloat = 66
    private let handleSize: CGFloat = 30

    private let minWidth: CGFloat = 260
    private let minHeight: CGFloat = 300

    // Kích thước "gốc" dùng làm mốc tính tỉ lệ — khi resize, toàn bộ nội
    // dung bên trong (icon, chữ, khoảng cách) scale theo tỉ lệ này thay vì
    // đứng yên hoặc chỉ bị cắt/kẹp như trước.
    private let designWidth: CGFloat = 310
    private let designHeight: CGFloat = 400

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

    private let bypassLabel = UILabel()
    private let saleLabel = UILabel()
    private let logLabel = UILabel()
    private let adBlockLabel = UILabel()
    private let clockLabel = UILabel()
    private let reloadLabel = UILabel()

    private var saleClock: TPIOSSaleClock?

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

    // MARK: Header

    private func setupHeader() {

        headerView.backgroundColor = UIColor(
            red: 0.075,
            green: 0.085,
            blue: 0.105,
            alpha: 1
        )

        headerView.layer.cornerRadius = 24
        headerView.layer.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner
        ]

        addSubview(headerView)

        statusDot.backgroundColor = UIColor(
            red: 0.30,
            green: 0.95,
            blue: 0.55,
            alpha: 1
        )
        statusDot.layer.cornerRadius = 5

        headerView.addSubview(statusDot)

        titleLabel.text = "TPIOS"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(
            ofSize: 19,
            weight: .bold
        )

        headerView.addSubview(titleLabel)

        subtitleLabel.text = "Design By TRUONGPHONG"
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.48)
        subtitleLabel.font = .systemFont(
            ofSize: 10,
            weight: .semibold
        )

        headerView.addSubview(subtitleLabel)

        closeButton.setImage(
            UIImage(systemName: "xmark"),
            for: .normal
        )
        closeButton.tintColor =
            UIColor.white.withAlphaComponent(0.75)

        closeButton.backgroundColor =
            UIColor.white.withAlphaComponent(0.07)

        closeButton.layer.cornerRadius = 17

        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )

        headerView.addSubview(closeButton)
    }

    // MARK: Buttons

    private func setupButtons() {

        configureIconButton(
            bypassButton,
            icon: "location.fill",
            colors: [UIColor(red: 1.00, green: 0.65, blue: 0.25, alpha: 1), UIColor(red: 0.85, green: 0.25, blue: 0.08, alpha: 1)],
            action: #selector(locationTapped)
        )
        configureCaptionLabel(bypassLabel, text: "Vị trí")

        configureIconButton(
            saleButton,
            icon: "bag.fill",
            colors: [UIColor(red: 0.68, green: 0.47, blue: 1.00, alpha: 1), UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)],
            action: #selector(saleTapped)
        )
        configureCaptionLabel(saleLabel, text: "Sale")

        configureIconButton(
            logButton,
            icon: "doc.text.magnifyingglass",
            colors: [UIColor(red: 0.36, green: 0.71, blue: 1.00, alpha: 1), UIColor(red: 0.09, green: 0.39, blue: 0.80, alpha: 1)],
            action: #selector(logTapped)
        )
        configureCaptionLabel(logLabel, text: "Xem log")

        configureIconButton(
            adBlockButton,
            icon: "shield.fill",
            colors: [UIColor(red: 1.00, green: 0.35, blue: 0.27, alpha: 1), UIColor(red: 0.64, green: 0.06, blue: 0.06, alpha: 1)],
            action: #selector(adBlockTapped)
        )
        configureCaptionLabel(adBlockLabel, text: "Tắt QC")

        configureIconButton(
            clockButton,
            icon: "clock.fill",
            colors: [UIColor(red: 0.36, green: 0.88, blue: 0.55, alpha: 1), UIColor(red: 0.06, green: 0.52, blue: 0.33, alpha: 1)],
            action: #selector(clockTapped)
        )
        configureCaptionLabel(clockLabel, text: "Đồng hồ")

        configureIconButton(
            reloadButton,
            icon: "arrow.clockwise",
            colors: [UIColor(red: 0.27, green: 0.84, blue: 0.84, alpha: 1), UIColor(red: 0.04, green: 0.43, blue: 0.55, alpha: 1)],
            action: #selector(reloadTapped)
        )
        configureCaptionLabel(reloadLabel, text: "Tải lại trang")

        for view in [bypassButton, saleButton, logButton, adBlockButton, clockButton, reloadButton] as [UIView] {
            addSubview(view)
        }
        for label in [bypassLabel, saleLabel, logLabel, adBlockLabel, clockLabel, reloadLabel] {
            addSubview(label)
        }
    }

    // Icon vuông bo góc kiểu app icon — không còn chữ đè lên icon, chữ
    // chú thích nằm ở UILabel riêng bên dưới (configureCaptionLabel).
    private func configureIconButton(
        _ button: UIButton,
        icon: String,
        colors: [UIColor],
        action: Selector
    ) {

        let config = UIImage.SymbolConfiguration(
            pointSize: 22,
            weight: .semibold
        )

        button.setImage(
            UIImage(systemName: icon, withConfiguration: config),
            for: .normal
        )

        button.tintColor = .white
        TPIOSPanelStyle.applyGradientFill(to: button, colors: colors, cornerRadius: 18)
        button.layer.cornerRadius = 18
        button.imageView?.contentMode = .center

        if let imageView = button.imageView {
            button.bringSubviewToFront(imageView)
        }

        button.addTarget(
            self,
            action: action,
            for: .touchUpInside
        )
    }

    private func configureCaptionLabel(_ label: UILabel, text: String) {
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
    }

    // MARK: Footer

    private func setupFooter() {

        footerLabel.textColor =
            UIColor.white.withAlphaComponent(0.5)

        footerLabel.font = .systemFont(
            ofSize: 12,
            weight: .medium
        )

        footerLabel.textAlignment = .center
        footerLabel.adjustsFontSizeToFitWidth = true
        footerLabel.minimumScaleFactor = 0.7

        footerLabel.text = calendarFooterText()

        addSubview(footerLabel)
    }

    // Foundation không có lịch âm Việt Nam riêng — dùng lịch Trung Quốc
    // (.chinese) làm xấp xỉ, cùng gốc lịch âm dương, sai lệch chỉ xảy ra
    // ở vài ngày hiếm gặp quanh giao thừa/tháng nhuận do khác múi giờ neo
    // tính toán. Đủ dùng cho mục đích hiển thị tham khảo ở đây.
    private func calendarFooterText() -> String {

        let now = Date()

        let solarFormatter = DateFormatter()
        solarFormatter.dateFormat = "dd/MM/yyyy"
        let solarText = solarFormatter.string(from: now)

        var lunarCalendar = Calendar(identifier: .chinese)
        lunarCalendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current

        let components = lunarCalendar.dateComponents([.day, .month], from: now)

        guard let day = components.day, let month = components.month else {
            return solarText
        }

        let lunarText = String(format: "%02d/%02d Âm lịch", day, month)

        return "\(solarText)  •  \(lunarText)"
    }

    // MARK: Move

    private func setupMove() {

        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(moveMenu(_:))
        )

        pan.delegate = self
        pan.cancelsTouchesInView = false

        headerView.addGestureRecognizer(pan)
    }

    @objc private func moveMenu(
        _ gesture: UIPanGestureRecognizer
    ) {

        guard let parent = superview else {
            return
        }

        guard gesture.state == .began ||
              gesture.state == .changed else {
            return
        }

        let delta = gesture.translation(in: parent)

        var newFrame = frame

        newFrame.origin.x += delta.x
        newFrame.origin.y += delta.y

        clamp(
            &newFrame,
            in: parent
        )

        frame = newFrame

        gesture.setTranslation(
            .zero,
            in: parent
        )
    }

    // MARK: Resize

    private func setupResize() {

        resizeHandle.text = "↘"
        resizeHandle.textColor =
            UIColor.white.withAlphaComponent(0.42)

        resizeHandle.font = .systemFont(
            ofSize: 19,
            weight: .medium
        )

        resizeHandle.textAlignment = .center
        resizeHandle.isUserInteractionEnabled = true

        addSubview(resizeHandle)

        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(resizeMenu(_:))
        )

        pan.cancelsTouchesInView = false

        resizeHandle.addGestureRecognizer(pan)
    }

    @objc private func resizeMenu(
        _ gesture: UIPanGestureRecognizer
    ) {

        guard let parent = superview else {
            return
        }

        switch gesture.state {

        case .began:

            resizeStartFrame = frame

            resizeStartPoint =
                gesture.location(in: parent)

        case .changed:

            let point =
                gesture.location(in: parent)

            let dx =
                point.x - resizeStartPoint.x

            let dy =
                point.y - resizeStartPoint.y

            let width =
                max(
                    minWidth,
                    min(
                        resizeStartFrame.width + dx,
                        parent.bounds.width -
                        resizeStartFrame.origin.x
                    )
                )

            let height =
                max(
                    minHeight,
                    min(
                        resizeStartFrame.height + dy,
                        parent.bounds.height -
                        resizeStartFrame.origin.y
                    )
                )

            frame = CGRect(
                x: resizeStartFrame.origin.x,
                y: resizeStartFrame.origin.y,
                width: width,
                height: height
            )

        default:
            break
        }
    }

    // MARK: Layout

    override func layoutSubviews() {

        super.layoutSubviews()

        let scale = min(
            bounds.width / designWidth,
            bounds.height / designHeight
        )

        headerView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: headerHeight
        )

        statusDot.frame = CGRect(
            x: 18,
            y: 27,
            width: 10,
            height: 10
        )

        titleLabel.frame = CGRect(
            x: 36,
            y: 12,
            width: max(0, bounds.width - 96),
            height: 25
        )

        subtitleLabel.frame = CGRect(
            x: 36,
            y: 38,
            width: max(0, bounds.width - 96),
            height: 13
        )

        closeButton.frame = CGRect(
            x: bounds.width - 50,
            y: 16,
            width: 34,
            height: 34
        )

        // Lưới 3 cột x 2 hàng, mỗi ô gồm 1 icon vuông + 1 label chữ ngay
        // bên dưới — toàn bộ kích thước/khoảng cách nhân theo "scale" nên
        // khi kéo resize, icon và chữ phóng to/nhỏ theo đúng khung chính
        // thay vì đứng yên.
        let sidePadding = 20 * scale
        let columnGap = 14 * scale
        let rowGap = 20 * scale
        let iconLabelGap = 6 * scale
        let labelHeight = 16 * scale

        let gridTop = headerHeight + 22 * scale
        let contentWidth = max(0, bounds.width - sidePadding * 2)
        let columnWidth = (contentWidth - columnGap * 2) / 3

        let iconSize = min(columnWidth, 74 * scale)
        let iconXInset = max(0, (columnWidth - iconSize) / 2)
        let rowHeight = iconSize + iconLabelGap + labelHeight

        let icons = [bypassButton, saleButton, logButton, adBlockButton, clockButton, reloadButton]
        let labels = [bypassLabel, saleLabel, logLabel, adBlockLabel, clockLabel, reloadLabel]

        for index in 0..<icons.count {
            let column = index % 3
            let row = index / 3

            let columnX = sidePadding + CGFloat(column) * (columnWidth + columnGap)
            let rowY = gridTop + CGFloat(row) * (rowHeight + rowGap)

            icons[index].frame = CGRect(
                x: columnX + iconXInset,
                y: rowY,
                width: iconSize,
                height: iconSize
            )
            icons[index].layer.cornerRadius = iconSize * 0.28
            TPIOSPanelStyle.syncFrames(in: icons[index])

            labels[index].frame = CGRect(
                x: columnX,
                y: rowY + iconSize + iconLabelGap,
                width: columnWidth,
                height: labelHeight
            )
            labels[index].font = .systemFont(
                ofSize: max(9, 13 * scale),
                weight: .semibold
            )
        }

        footerLabel.frame = CGRect(
            x: 14,
            y: bounds.height - 30,
            width: max(0, bounds.width - 28),
            height: 18
        )

        resizeHandle.frame = CGRect(
            x: bounds.width - handleSize,
            y: bounds.height - handleSize,
            width: handleSize,
            height: handleSize
        )
    }

    // MARK: Close

    @objc private func closeTapped() {

        closeLocation()
        closeSale()
        closeAdBlock()

        NotificationCenter.default.post(
            name: .tpiosCloseMenu,
            object: nil
        )
    }

    // MARK: Log

    @objc private func logTapped() {
        TPIOSLog.shared.log("Mở cửa sổ log")
        TPIOSLog.shared.show()
    }

    // MARK: Đồng hồ

    @objc private func clockTapped() {

        guard let parent = superview else {
            return
        }

        // Menu có thể bị đóng/mở nhiều lần. Tìm lại đồng hồ đang tồn tại
        // trên overlay trước khi tạo mới, để nút luôn là bật/tắt.
        if saleClock == nil {
            saleClock = parent.subviews
                .compactMap { $0 as? TPIOSSaleClock }
                .last
        }

        if saleClock != nil {
            closeSaleClock()
            return
        }

        let width = min(
            310,
            max(190, parent.bounds.width - 24)
        )

        let height = width / TPIOSSaleClock.defaultAspectRatio

        let x = max(
            12,
            (parent.bounds.width - width) / 2
        )

        let y = max(
            20,
            min(
                frame.maxY + 20,
                parent.bounds.height - height - 20
            )
        )

        let clock = TPIOSSaleClock(
            frame: CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            )
        )

        clock.onClose = { [weak self, weak clock] in
            clock?.stop()
            clock?.removeFromSuperview()
            self?.saleClock = nil
        }

        parent.addSubview(clock)

        saleClock = clock

        // Đồng hồ mở song song với menu chính.
        // Không ẩn menu để người dùng có thể bật/tắt trực tiếp.
        clock.start()
    }

    private func closeSaleClock() {

        saleClock?.stop()
        saleClock?.removeFromSuperview()
        saleClock = nil
    }

    // MARK: Tải lại trang

    @objc private func reloadTapped() {
        TPIOSReload.shared.reloadCurrentPage()
    }

    // MARK: Tắt QC

    @objc private func adBlockTapped() {

        guard locationView == nil,
              saleView == nil,
              let parent = superview else {
            return
        }

        let blocker = TPIOSAdBlock.shared

        blocker.onClose = { [weak self] in
            self?.closeAdBlock()
        }

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

    // MARK: Vị trí

    @objc private func locationTapped() {

        guard locationView == nil,
              saleView == nil,
              let parent = superview else {
            return
        }

        let width =
            min(
                frame.width,
                parent.bounds.width
            )

        let height =
            min(
                420,
                parent.bounds.height
            )

        let childFrame = CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: width,
            height: height
        )

        let location = TPIOSLocation(
            frame: childFrame
        )

        location.onBack = { [weak self] in
            self?.closeLocation()
        }

        location.onClose = { [weak self] in

            self?.closeLocation()

            NotificationCenter.default.post(
                name: .tpiosCloseMenu,
                object: nil
            )
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

    // MARK: Sale

    @objc private func saleTapped() {

        guard locationView == nil,
              saleView == nil,
              let parent = superview else {
            return
        }

        let sale = TPIOSSale(frame: frame)

        sale.onBack = { [weak self] in
            self?.closeSale()
        }

        sale.onClose = { [weak self] in

            self?.closeSale()

            NotificationCenter.default.post(
                name: .tpiosCloseMenu,
                object: nil
            )
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

    // MARK: Clamp

    private func clamp(
        _ rect: inout CGRect,
        in parent: UIView
    ) {

        let maxX =
            max(
                0,
                parent.bounds.width - rect.width
            )

        let maxY =
            max(
                0,
                parent.bounds.height - rect.height
            )

        rect.origin.x =
            max(
                0,
                min(rect.origin.x, maxX)
            )

        rect.origin.y =
            max(
                0,
                min(rect.origin.y, maxY)
            )
    }

    // MARK: Gesture Delegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        true
    }
}
