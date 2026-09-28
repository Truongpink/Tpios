import UIKit

final class TPIOSSale: UIView,
                       UIGestureRecognizerDelegate {

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private let headerHeight: CGFloat = 66
    private let handleSize: CGFloat = 30
    private let minWidth: CGFloat = 260
    private let minHeight: CGFloat = 300

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let infoLabel = UILabel()
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
        layer.borderColor =
            UIColor.white.withAlphaComponent(0.12).cgColor

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
        backButton.titleLabel?.font = .systemFont(
            ofSize: 30,
            weight: .regular
        )
        backButton.addTarget(
            self,
            action: #selector(backTapped),
            for: .touchUpInside
        )
        headerView.addSubview(backButton)

        titleLabel.text = "SALE"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(
            ofSize: 17,
            weight: .bold
        )
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)

        closeButton.setTitle("×", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(
            ofSize: 28,
            weight: .regular
        )
        closeButton.addTarget(
            self,
            action: #selector(closeTapped),
            for: .touchUpInside
        )
        headerView.addSubview(closeButton)
    }

    private func setupContent() {
        infoLabel.text = """
        SALE

        Module săn sale đang được nghiên cứu.

        Mục tiêu:
        • Theo dõi sản phẩm muốn mua
        • Tìm voucher phù hợp
        • Tính giá thực trả
        • Tối ưu ưu đãi ShopeeVIP/SVIP
        • Theo dõi lịch sử giá

        Chưa thực hiện quét hoặc tự động mua hàng.
        """

        infoLabel.textColor =
            UIColor.white.withAlphaComponent(0.9)
        infoLabel.font = .monospacedSystemFont(
            ofSize: 13,
            weight: .regular
        )
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .left

        addSubview(infoLabel)
    }

    private func setupResize() {
        resizeHandle.text = "↘"
        resizeHandle.textColor =
            UIColor.white.withAlphaComponent(0.65)
        resizeHandle.font = .systemFont(
            ofSize: 20,
            weight: .medium
        )
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

    @objc private func resize(
        _ gesture: UIPanGestureRecognizer
    ) {
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

    @objc private func moveSale(
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

        let maxX = max(
            0,
            parent.bounds.width - newFrame.width
        )
        let maxY = max(
            0,
            parent.bounds.height - newFrame.height
        )

        newFrame.origin.x = max(
            0,
            min(newFrame.origin.x, maxX)
        )
        newFrame.origin.y = max(
            0,
            min(newFrame.origin.y, maxY)
        )

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

        infoLabel.frame = CGRect(
            x: 18,
            y: headerHeight + 20,
            width: max(0, bounds.width - 36),
            height: max(
                0,
                bounds.height - headerHeight - 40
            )
        )

        resizeHandle.frame = CGRect(
            x: bounds.width - handleSize,
            y: bounds.height - handleSize,
            width: handleSize,
            height: handleSize
        )
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
           touch.view === resizeHandle {
            return false
        }

        return true
    }
}
