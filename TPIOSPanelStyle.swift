import UIKit

// Kiểu nền chung cho mọi khung nổi của TPIOS — nền kính mờ nhìn xuyên app
// phía sau, thay cho màu đặc trước đây. Gom 1 chỗ để đồng bộ toàn bộ panel.
enum TPIOSPanelStyle {

    @discardableResult
    static func applyGlassBackground(
        to view: UIView,
        cornerRadius: CGFloat = 24
    ) -> UIVisualEffectView {

        view.backgroundColor = .clear
        view.layer.cornerRadius = cornerRadius
        view.layer.borderWidth = 1
        view.layer.borderColor =
            UIColor.white.withAlphaComponent(0.14).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.42
        view.layer.shadowRadius = 20
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.clipsToBounds = false

        let blur = UIVisualEffectView(
            effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
        )
        blur.frame = view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.layer.cornerRadius = cornerRadius
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false

        let tint = UIView(frame: blur.bounds)
        tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tint.backgroundColor = UIColor(white: 0.04, alpha: 0.38)
        tint.isUserInteractionEnabled = false
        blur.contentView.addSubview(tint)

        view.insertSubview(blur, at: 0)

        return blur
    }

    private static let gradientLayerName = "tpios.iconGradient"

    static func applyGradientFill(
        to view: UIView,
        colors: [UIColor],
        cornerRadius: CGFloat
    ) {

        view.backgroundColor = .clear
        view.layer.cornerRadius = cornerRadius
        view.layer.borderWidth = 1
        view.layer.borderColor =
            UIColor.white.withAlphaComponent(0.28).cgColor

        let gradient: CAGradientLayer

        if let existing = view.layer.sublayers?.first(where: {
            $0.name == gradientLayerName
        }) as? CAGradientLayer {
            gradient = existing
        } else {
            gradient = CAGradientLayer()
            gradient.name = gradientLayerName
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            view.layer.insertSublayer(gradient, at: 0)
        }

        gradient.colors = colors.map { $0.cgColor }
        gradient.frame = view.bounds
        gradient.cornerRadius = cornerRadius
    }

    static func syncFrames(in view: UIView) {

        for subview in view.subviews {
            if let blur = subview as? UIVisualEffectView {
                blur.frame = view.bounds
                blur.layer.cornerRadius = view.layer.cornerRadius
            }
        }

        for sublayer in view.layer.sublayers ?? [] {
            if sublayer.name == gradientLayerName {
                sublayer.frame = view.bounds
                sublayer.cornerRadius = view.layer.cornerRadius
            }
        }
    }
}
