import UIKit

final class TPIOSSale: UIView, UIGestureRecognizerDelegate {

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private let headerHeight: CGFloat = 54
    private let handleSize: CGFloat = 30
    private let minWidth: CGFloat = 260
    private let minHeight: CGFloat = 300

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    private let priceField = UITextField()
    private let shopVoucherField = UITextField()
    private let shopeeVoucherField = UITextField()
    private let shippingField = UITextField()
    private let freeshipField = UITextField()

    private let calculateButton = UIButton(type: .system)
    private let calculateLabel = UILabel()
    private let scanButton = UIButton(type: .system)
    private let scanLabel = UILabel()
    private let resultLabel = UILabel()
    private let noteLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let resizeHandle = UILabel()

    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = UIColor(
            red: 0.045,
            green: 0.05,
            blue: 0.065,
            alpha: 0.98
        )

        layer.cornerRadius = 24
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.42
        layer.shadowRadius = 20
        layer.shadowOffset = CGSize(width: 0, height: 8)

        clipsToBounds = true

        setupHeader()
        setupContent()
        setupResize()
        setupMove()
    }

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

        backButton.setTitle("‹", for: .normal)
        backButton.setTitleColor(.white, for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 30)
        backButton.addTarget(
            self,
            action: #selector(backTapped),
            for: .touchUpInside
        )
        headerView.addSubview(backButton)

        titleLabel.text = "SALE"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)

        closeButton.setTitle("×", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 28)
        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )
        headerView.addSubview(closeButton)
    }

    private func setupContent() {
        addSubview(scrollView)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true

        scrollView.addSubview(contentView)

        addField(
            priceField,
            title: "Giá sản phẩm",
            placeholder: "Ví dụ: 299000"
        )

        addField(
            shopVoucherField,
            title: "Shop Voucher",
            placeholder: "Số tiền giảm, ví dụ: 30000"
        )

        addField(
            shopeeVoucherField,
            title: "Shopee Voucher",
            placeholder: "Số tiền giảm, ví dụ: 50000"
        )

        addField(
            shippingField,
            title: "Phí vận chuyển",
            placeholder: "Ví dụ: 25000"
        )

        addField(
            freeshipField,
            title: "Freeship",
            placeholder: "Số tiền được giảm, ví dụ: 25000"
        )

        configureActionButton(
            calculateButton,
            icon: "dollarsign.circle.fill",
            color: UIColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1),
            label: calculateLabel,
            text: "Giá cuối",
            action: #selector(calculateTapped)
        )

        configureActionButton(
            scanButton,
            icon: "magnifyingglass",
            color: UIColor(red: 0.12, green: 0.55, blue: 0.95, alpha: 1),
            label: scanLabel,
            text: "Quét",
            action: #selector(scanShopeeTapped)
        )

        resultLabel.text = "Giá thực trả: —"
        resultLabel.textColor = .white
        resultLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        resultLabel.numberOfLines = 0
        contentView.addSubview(resultLabel)

        noteLabel.text = "Quét: chỉ kiểm tra cấu trúc màn hình hiện tại để nghiên cứu cách lấy dữ liệu. Chưa tự lấy voucher."
        noteLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        noteLabel.font = .systemFont(ofSize: 12)
        noteLabel.numberOfLines = 0
        contentView.addSubview(noteLabel)
    }

    private func configureActionButton(
        _ button: UIButton,
        icon: String,
        color: UIColor,
        label: UILabel,
        text: String,
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
        button.backgroundColor = color
        button.layer.cornerRadius = 14
        button.addTarget(
            self,
            action: action,
            for: .touchUpInside
        )
        contentView.addSubview(button)

        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        contentView.addSubview(label)
    }

    private func addField(
        _ field: UITextField,
        title: String,
        placeholder: String
    ) {
        let label = UILabel()
        label.text = title
        label.textColor = UIColor.white.withAlphaComponent(0.82)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.tag = field.hash
        contentView.addSubview(label)

        field.textColor = .white
        field.tintColor = .white
        field.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        field.layer.cornerRadius = 10
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        field.font = .systemFont(ofSize: 15)
        field.placeholder = placeholder
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.3)
            ]
        )
        field.keyboardType = .decimalPad
        field.textAlignment = .right
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.leftViewMode = .always
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.rightViewMode = .always
        contentView.addSubview(field)
    }

    private func setupResize() {
        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.65)
        resizeHandle.font = .systemFont(ofSize: 20)
        resizeHandle.textAlignment = .center
        resizeHandle.isUserInteractionEnabled = true
        addSubview(resizeHandle)

        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(resize(_:))
        )
        pan.cancelsTouchesInView = false
        resizeHandle.addGestureRecognizer(pan)
    }

    @objc private func resize(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else {
            return
        }

        switch gesture.state {
        case .began:
            resizeStartFrame = frame
            resizeStartPoint = gesture.location(in: parent)

        case .changed:
            let point = gesture.location(in: parent)
            let dx = point.x - resizeStartPoint.x
            let dy = point.y - resizeStartPoint.y

            let width = max(
                minWidth,
                min(
                    resizeStartFrame.width + dx,
                    parent.bounds.width - resizeStartFrame.origin.x
                )
            )

            let height = max(
                minHeight,
                min(
                    resizeStartFrame.height + dy,
                    parent.bounds.height - resizeStartFrame.origin.y
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

    private func setupMove() {
        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(moveSale(_:))
        )
        pan.delegate = self
        pan.cancelsTouchesInView = false
        headerView.addGestureRecognizer(pan)
    }

    @objc private func moveSale(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else {
            return
        }

        guard gesture.state == .began || gesture.state == .changed else {
            return
        }

        let delta = gesture.translation(in: parent)
        var newFrame = frame

        newFrame.origin.x += delta.x
        newFrame.origin.y += delta.y

        let maxX = max(0, parent.bounds.width - newFrame.width)
        let maxY = max(0, parent.bounds.height - newFrame.height)

        newFrame.origin.x = max(0, min(newFrame.origin.x, maxX))
        newFrame.origin.y = max(0, min(newFrame.origin.y, maxY))

        frame = newFrame
        gesture.setTranslation(.zero, in: parent)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        headerView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: headerHeight
        )

        backButton.frame = CGRect(
            x: 4,
            y: 3,
            width: 40,
            height: 38
        )

        titleLabel.frame = CGRect(
            x: 46,
            y: 0,
            width: max(0, bounds.width - 92),
            height: headerHeight
        )

        closeButton.frame = CGRect(
            x: bounds.width - 46,
            y: 4,
            width: 42,
            height: 36
        )

        scrollView.frame = CGRect(
            x: 0,
            y: headerHeight,
            width: bounds.width,
            height: max(0, bounds.height - headerHeight)
        )

        let contentWidth = max(0, bounds.width - 28)
        let x: CGFloat = 14
        var y: CGFloat = 12
        let fieldHeight: CGFloat = 38
        let labelHeight: CGFloat = 18
        let gap: CGFloat = 8

        // Action buttons luôn nằm trên cùng, vuông gọn để dễ bấm và dễ thu nhỏ.
        let actionSize: CGFloat = min(54, max(44, (contentWidth - 12) / 2))
        let actionLabelHeight: CGFloat = 16

        calculateButton.frame = CGRect(
            x: x,
            y: y,
            width: actionSize,
            height: actionSize
        )
        calculateButton.layer.cornerRadius = actionSize * 0.26

        calculateLabel.frame = CGRect(
            x: x - 4,
            y: y + actionSize + 3,
            width: actionSize + 8,
            height: actionLabelHeight
        )

        let scanX = x + contentWidth - actionSize
        scanButton.frame = CGRect(
            x: scanX,
            y: y,
            width: actionSize,
            height: actionSize
        )
        scanButton.layer.cornerRadius = actionSize * 0.26

        scanLabel.frame = CGRect(
            x: scanX - 4,
            y: y + actionSize + 3,
            width: actionSize + 8,
            height: actionLabelHeight
        )

        y += actionSize + actionLabelHeight + 14

        let fields = [
            priceField,
            shopVoucherField,
            shopeeVoucherField,
            shippingField,
            freeshipField
        ]

        var labels: [UILabel] = []
        for view in contentView.subviews {
            if let label = view as? UILabel,
               label.tag != 0,
               label !== calculateLabel,
               label !== scanLabel,
               label !== resultLabel,
               label !== noteLabel {
                labels.append(label)
            }
        }

        labels.sort { $0.frame.minY < $1.frame.minY }

        for index in 0..<fields.count {
            let field = fields[index]
            let label = labels[index]

            label.frame = CGRect(
                x: x,
                y: y,
                width: contentWidth,
                height: labelHeight
            )

            field.frame = CGRect(
                x: x,
                y: y + labelHeight,
                width: contentWidth,
                height: fieldHeight
            )

            y += labelHeight + fieldHeight + gap
        }

        y += 4

        resultLabel.frame = CGRect(
            x: x,
            y: y,
            width: contentWidth,
            height: 600
        )

        y += 620

        noteLabel.frame = CGRect(
            x: x,
            y: y,
            width: contentWidth,
            height: 50
        )

        y += 70

        contentView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: y
        )

        scrollView.contentSize = contentView.bounds.size

        resizeHandle.frame = CGRect(
            x: bounds.width - handleSize,
            y: bounds.height - handleSize,
            width: handleSize,
            height: handleSize
        )
    }

    @objc private func scanShopeeTapped() {
        viewEndEditing()

        guard superview != nil else {
            return
        }

        let originalFrame = frame
        let originalHidden = isHidden

        isHidden = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else {
                return
            }

            let diagnostic = TPIOSSaleRuntimeDiagnostics.inspectCurrentApp()

            self.frame = originalFrame
            self.isHidden = originalHidden

            self.resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            self.resultLabel.text = diagnostic

            TPIOSLog.shared.log(
                "Sale diagnostic hoàn tất. Xem log để đối chiếu tầng render."
            )
        }
    }

    @objc private func calculateTapped() {
        viewEndEditing()

        let price = amount(priceField)
        let shop = amount(shopVoucherField)
        let shopee = amount(shopeeVoucherField)
        let shipping = amount(shippingField)
        let freeship = amount(freeshipField)

        let productAfterShop = max(0, price - shop)
        let productAfterShopee = max(0, productAfterShop - shopee)
        let shippingAfterVoucher = max(0, shipping - freeship)
        let total = productAfterShopee + shippingAfterVoucher
        let saved = max(0, price + shipping - total)

        resultLabel.text = """
        Giá thực trả: \(formatMoney(total))
        Tiết kiệm: \(formatMoney(saved))
        """

        TPIOSLog.shared.log(
            "Sale Calculator: \(formatMoney(total))"
        )
    }

    private func amount(_ field: UITextField) -> Double {
        let raw = field.text?
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return Double(raw) ?? 0
    }

    private func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0

        return "\(formatter.string(from: NSNumber(value: value)) ?? "0")đ"
    }

    private func viewEndEditing() {
        endEditing(true)
    }

    @objc private func backTapped() {
        onBack?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        if touch.view === backButton ||
           touch.view === closeButton ||
           touch.view === resizeHandle ||
           touch.view === scanButton ||
           touch.view is UITextField ||
           touch.view === calculateButton {
            return false
        }

        return true
    }
}
