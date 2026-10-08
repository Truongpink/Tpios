import UIKit

//tap1
// Bước thử chạm, chỉ với nút UIKit (không chạm xuyên tầng).
// Bấm "Chạm thử" → chạm một điểm trên màn → tool tìm view dưới điểm đó, nếu là
// nút UIKit (UIControl) thì gửi hành động chạm → ghi kết quả vào log "TapTest:".
// Nút React Native của Shopee không phải UIControl nên sẽ được báo là không chạm được.
// Chặn các nút có chữ liên quan đặt hàng/thanh toán để không chạm nhầm.
final class TPIOSTapTest: NSObject {

    static let shared = TPIOSTapTest()

    private let blockedWords = ["mua", "đặt", "thanh toán", "xác nhận", "buy", "checkout", "order"]
    private var pickOverlay: UIView?

    func start() {
        guard let host = keyWindow() else { return }

        let overlay = UIView(frame: host.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.001)

        let hint = UILabel()
        hint.text = "Chạm vào điểm cần thử (chỉ nút UIKit)"
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textAlignment = .center
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        hint.layer.cornerRadius = 10
        hint.clipsToBounds = true
        hint.frame = CGRect(x: 20, y: host.safeAreaInsets.top + 14, width: host.bounds.width - 40, height: 40)
        overlay.addSubview(hint)

        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(picked(_:))))
        host.addSubview(overlay)
        pickOverlay = overlay
    }

    @objc private func picked(_ gesture: UITapGestureRecognizer) {
        guard let overlay = pickOverlay, let host = overlay.window else { return }

        let point = gesture.location(in: overlay)
        overlay.removeFromSuperview()
        pickOverlay = nil

        showDot(at: point, in: host)
        test(point: point, in: host)
    }

    private func test(point: CGPoint, in host: UIWindow) {
        let hit = host.hitTest(point, with: nil)
        let hitName = hit.map { NSStringFromClass(type(of: $0)) } ?? "nil"

        var current = hit
        var control: UIControl?
        var depth = 0

        while let view = current, depth < 8 {
            if let found = view as? UIControl {
                control = found
                break
            }
            current = view.superview
            depth += 1
        }

        guard let target = control else {
            TPIOSLog.shared.log("TapTest: không có nút UIKit tại \(Int(point.x)),\(Int(point.y)). View: \(hitName)")
            return
        }

        let label = ((target as? UIButton)?.currentTitle ?? target.accessibilityLabel ?? "").lowercased()

        if blockedWords.contains(where: { label.contains($0) }) {
            TPIOSLog.shared.log("TapTest: bỏ qua nút \"\(label)\" vì có chữ liên quan đặt hàng/thanh toán")
            return
        }

        target.sendActions(for: .touchUpInside)
        TPIOSLog.shared.log("TapTest: đã chạm \(NSStringFromClass(type(of: target))) \"\(label)\" tại \(Int(point.x)),\(Int(point.y))")
    }

    // Chấm nhỏ đánh dấu điểm vừa chạm, tự biến mất sau 3 giây, không nhận chạm.
    private func showDot(at point: CGPoint, in host: UIWindow) {
        let dot = UIView(frame: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
        dot.backgroundColor = UIColor(red: 1.0, green: 0.3, blue: 0.7, alpha: 0.95)
        dot.layer.cornerRadius = 5
        dot.isUserInteractionEnabled = false
        host.addSubview(dot)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            dot.removeFromSuperview()
        }
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}
