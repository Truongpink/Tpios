import UIKit
import WebKit
import ObjectiveC.runtime

// TPIOSSale — theo dõi giá từng sản phẩm Shopee bằng cách quét màn hình.
//
// Luồng:
// 1. "Quét giá": chạm vào sản phẩm (trang sản phẩm / giỏ hàng) → đọc TÊN +
//    các GIÁ gần điểm chạm → chạm đúng giá để lưu. Cùng tên (và phân loại)
//    = cùng sản phẩm, thêm 1 dòng vào lịch sử riêng của nó.
// 2. Danh sách sản phẩm: giá lần gần nhất, ▲▼ so với lần trước, giá thấp
//    nhất của RIÊNG sản phẩm đó. Chạm vào 1 sản phẩm để xem chi tiết.
// 3. Trong chi tiết có "Quét mã": chạm vào 1 thẻ mã giảm giá trên màn hình
//    → đọc mức giảm / đơn tối thiểu / giảm tối đa / loại → lưu theo sản
//    phẩm → tool tính tổ hợp mã cho giá sau mã thấp nhất (ước tính).
//
// Không gọi API Shopee, chỉ đọc chữ đang hiển thị trên màn hình.
final class TPIOSSale: UIView, UIGestureRecognizerDelegate {

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private let headerHeight: CGFloat = 54
    private let handleSize: CGFloat = 30
    private let minWidth: CGFloat = 280
    private let minHeight: CGFloat = 360

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let resizeHandle = UILabel()
    private let actionRow = TPIOSSaleActionRow()

    private var blocks: [TPIOSSaleBlock] = []

    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero

    private var selectedProductID: UUID?
    private var statusText = ""
    private var pendingScan: TPIOSSalePendingScan?
    private var pendingVoucher: TPIOSSalePendingVoucher?
    private var pendingDeleteConfirm = false
    private var pickPurpose: TPIOSSalePickPurpose = .product

    private weak var pickOverlay: UIView?
    private weak var pickCancelButton: UIButton?

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

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        addSubview(scrollView)
        scrollView.addSubview(contentView)

        actionRow.onScanPrice = { [weak self] in
            self?.scanPriceTapped()
        }
        actionRow.onScanVoucher = { [weak self] in
            self?.scanVoucherTapped()
        }

        setupResize()
        setupMove()
        render()
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
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        headerView.addSubview(backButton)

        titleLabel.text = "SALE"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)

        closeButton.setTitle("×", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 28)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addSubview(closeButton)
    }

    private func setupResize() {
        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.65)
        resizeHandle.font = .systemFont(ofSize: 20)
        resizeHandle.textAlignment = .center
        resizeHandle.isUserInteractionEnabled = true
        addSubview(resizeHandle)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(resize(_:)))
        pan.cancelsTouchesInView = false
        resizeHandle.addGestureRecognizer(pan)
    }

    @objc private func resize(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else { return }

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
                min(resizeStartFrame.width + dx, parent.bounds.width - resizeStartFrame.origin.x)
            )

            let height = max(
                minHeight,
                min(resizeStartFrame.height + dy, parent.bounds.height - resizeStartFrame.origin.y)
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
        let pan = UIPanGestureRecognizer(target: self, action: #selector(moveSale(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        headerView.addGestureRecognizer(pan)
    }

    @objc private func moveSale(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else { return }
        guard gesture.state == .began || gesture.state == .changed else { return }

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

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        backButton.frame = CGRect(x: 4, y: 3, width: 40, height: 38)
        titleLabel.frame = CGRect(x: 46, y: 0, width: max(0, bounds.width - 92), height: headerHeight)
        closeButton.frame = CGRect(x: bounds.width - 46, y: 4, width: 42, height: 36)

        scrollView.frame = CGRect(
            x: 0,
            y: headerHeight,
            width: bounds.width,
            height: max(0, bounds.height - headerHeight)
        )

        let x: CGFloat = 14
        let width = max(0, bounds.width - 28)
        var y: CGFloat = 8

        // Mỗi khối tự tính chiều cao theo nội dung — không còn ô chữ cao
        // cố định gây khoảng trống lớn như bản cũ.
        for block in blocks {
            y += block.spacingTop
            let height = block.height(width)
            block.view.frame = CGRect(x: x, y: y, width: width, height: height)
            y += height
        }

        y += 36

        contentView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: y)
        scrollView.contentSize = contentView.bounds.size

        resizeHandle.frame = CGRect(
            x: bounds.width - handleSize,
            y: bounds.height - handleSize,
            width: handleSize,
            height: handleSize
        )
    }

    private func setBlocks(_ new: [TPIOSSaleBlock]) {
        blocks.forEach { $0.view.removeFromSuperview() }
        blocks = new
        new.forEach { contentView.addSubview($0.view) }
        setNeedsLayout()
    }

    // MARK: Render

    private func render() {
        let products = TPIOSSaleStore.shared.load()

        if let id = selectedProductID,
           products.contains(where: { $0.id == id }) == false {
            selectedProductID = nil
        }

        actionRow.showsVoucher = selectedProductID != nil

        var list: [TPIOSSaleBlock] = []
        list.append(fixedBlock(actionRow, height: 96, top: 6))

        if statusText.isEmpty == false {
            list.append(labelBlock(makeLabel(statusText, size: 12.5, alpha: 0.95), top: 8))
        }

        if let pending = pendingScan {
            list.append(contentsOf: pendingScanBlocks(pending))
        } else if let pending = pendingVoucher {
            list.append(contentsOf: pendingVoucherBlocks(pending))
        }

        if let id = selectedProductID,
           let product = products.first(where: { $0.id == id }) {
            list.append(contentsOf: detailBlocks(product))
        } else {
            list.append(contentsOf: listBlocks(products))
        }

        setBlocks(list)
    }

    private func fixedBlock(_ view: UIView, height: CGFloat, top: CGFloat) -> TPIOSSaleBlock {
        TPIOSSaleBlock(view: view, spacingTop: top, height: { _ in height })
    }

    private func labelBlock(_ label: UILabel, top: CGFloat) -> TPIOSSaleBlock {
        TPIOSSaleBlock(view: label, spacingTop: top, height: { width in
            ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        })
    }

    private func makeLabel(
        _ text: String,
        size: CGFloat = 12.5,
        weight: UIFont.Weight = .regular,
        alpha: CGFloat = 0.82,
        mono: Bool = false
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textColor = UIColor.white.withAlphaComponent(alpha)
        label.font = mono
            ? .monospacedSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
        return label
    }

    private func pillButton(_ title: String, color: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        button.backgroundColor = color
        button.layer.cornerRadius = 10
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func choiceRow(title: String, selected: Bool, tag: Int, action: Selector) -> UIButton {
        let row = UIButton(type: .system)
        row.setTitle("  " + title, for: .normal)
        row.contentHorizontalAlignment = .left
        row.setTitleColor(.white, for: .normal)
        row.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        row.titleLabel?.lineBreakMode = .byTruncatingTail
        row.backgroundColor = selected
            ? UIColor(red: 0.10, green: 0.55, blue: 0.40, alpha: 1)
            : UIColor.white.withAlphaComponent(0.07)
        row.layer.cornerRadius = 8
        row.tag = tag
        row.addTarget(self, action: action, for: .touchUpInside)
        return row
    }

    private func noteBlock() -> TPIOSSaleBlock {
        labelBlock(
            makeLabel(
                "Giá và mã đọc từ chữ đang hiển thị trên màn hình Shopee, không gọi API. Giá sau mã chỉ là ước tính cho 1 sản phẩm.",
                size: 11,
                alpha: 0.45
            ),
            top: 18
        )
    }

    // MARK: Khối: kết quả quét đang chờ xác nhận

    private func pendingScanBlocks(_ pending: TPIOSSalePendingScan) -> [TPIOSSaleBlock] {
        var b: [TPIOSSaleBlock] = []

        b.append(labelBlock(makeLabel("Tên sản phẩm (chạm để chọn đúng):", weight: .semibold), top: 14))

        if pending.names.isEmpty {
            b.append(labelBlock(
                makeLabel("Không đọc được tên — sẽ lưu tên tạm theo giờ quét.", size: 12, alpha: 0.6),
                top: 4
            ))
        } else {
            for (index, name) in pending.names.enumerated() {
                b.append(fixedBlock(
                    choiceRow(
                        title: name,
                        selected: index == pending.selectedName,
                        tag: index,
                        action: #selector(nameChoiceTapped(_:))
                    ),
                    height: 34,
                    top: 4
                ))
            }
        }

        if let variant = pending.variant {
            b.append(labelBlock(makeLabel("Phân loại: \(variant)", size: 12, alpha: 0.7), top: 6))
        }

        b.append(labelBlock(makeLabel("Chạm đúng giá để lưu:", weight: .semibold), top: 14))

        for (index, value) in pending.prices.prefix(12).enumerated() {
            var text = TPIOSSaleFormat.money(value.amount)
            if value.text != text {
                let snippet = value.text.count > 34 ? String(value.text.prefix(34)) + "…" : value.text
                text += "   (" + snippet + ")"
            }
            b.append(fixedBlock(
                choiceRow(title: text, selected: false, tag: index, action: #selector(priceChoiceTapped(_:))),
                height: 34,
                top: 4
            ))
        }

        b.append(fixedBlock(
            pillButton("Huỷ quét", color: UIColor.white.withAlphaComponent(0.12), action: #selector(cancelPendingTapped)),
            height: 36,
            top: 10
        ))

        return b
    }

    // MARK: Khối: kết quả đọc mã giảm giá đang chờ xác nhận

    private func pendingVoucherBlocks(_ pending: TPIOSSalePendingVoucher) -> [TPIOSSaleBlock] {
        var b: [TPIOSSaleBlock] = []

        b.append(labelBlock(makeLabel("Đọc được từ thẻ mã:", weight: .semibold), top: 14))

        let raw: String
        if pending.lines.isEmpty {
            raw = "(không đọc được chữ nào quanh điểm chạm)"
        } else {
            raw = pending.lines.prefix(8).map {
                $0.count > 64 ? String($0.prefix(64)) + "…" : $0
            }.joined(separator: "\n")
        }
        b.append(labelBlock(makeLabel(raw, size: 11, alpha: 0.6, mono: true), top: 4))

        if let parsed = pending.parsed {
            var summary = parsed.title + "\nLoại: " + TPIOSSaleKind.name(parsed.kind)
            if let expiry = parsed.expiryText {
                summary += "\n" + expiry
            }
            b.append(labelBlock(makeLabel(summary, size: 12.5, weight: .semibold, alpha: 0.95), top: 8))

            let kindButton = pillButton(
                "Loại: " + TPIOSSaleKind.name(parsed.kind),
                color: TPIOSSaleKind.color(parsed.kind),
                action: #selector(pendingVoucherKindTapped)
            )
            let saveButton = pillButton(
                "Lưu mã",
                color: UIColor(red: 0.10, green: 0.55, blue: 0.40, alpha: 1),
                action: #selector(saveVoucherTapped)
            )
            let cancelButton = pillButton(
                "Bỏ",
                color: UIColor.white.withAlphaComponent(0.12),
                action: #selector(cancelPendingTapped)
            )
            b.append(fixedBlock(
                TPIOSSaleButtonRow(buttons: [kindButton, saveButton, cancelButton]),
                height: 36,
                top: 8
            ))
        } else {
            b.append(labelBlock(
                makeLabel("Không nhận ra mức giảm trong chữ này. Thử chạm lại vào giữa thẻ mã.", size: 12, alpha: 0.7),
                top: 8
            ))
            b.append(fixedBlock(
                pillButton("Đóng", color: UIColor.white.withAlphaComponent(0.12), action: #selector(cancelPendingTapped)),
                height: 36,
                top: 8
            ))
        }

        return b
    }

    // MARK: Khối: danh sách sản phẩm

    private func listBlocks(_ products: [TPIOSWatchedSale]) -> [TPIOSSaleBlock] {
        var b: [TPIOSSaleBlock] = []

        b.append(labelBlock(
            makeLabel("SẢN PHẨM ĐÃ THEO DÕI (\(products.count))", weight: .semibold),
            top: 16
        ))

        if products.isEmpty {
            b.append(labelBlock(
                makeLabel(
                    "Chưa có sản phẩm nào. Mở trang sản phẩm hoặc giỏ hàng Shopee, bấm Quét giá rồi chạm vào sản phẩm.",
                    size: 12,
                    alpha: 0.6
                ),
                top: 6
            ))
        } else {
            let sorted = products.sorted {
                ($0.lastCheckedAt ?? $0.createdAt) > ($1.lastCheckedAt ?? $1.createdAt)
            }

            for product in sorted {
                let row = TPIOSSaleProductRow(frame: .zero)
                row.configure(name: product.title, info: productInfo(product))
                row.accessibilityIdentifier = product.id.uuidString
                row.addTarget(self, action: #selector(productRowTapped(_:)), for: .touchUpInside)
                b.append(fixedBlock(row, height: 56, top: 6))
            }
        }

        b.append(noteBlock())
        return b
    }

    private func productInfo(_ product: TPIOSWatchedSale) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let white = UIColor.white.withAlphaComponent(0.85)
        let out = NSMutableAttributedString()

        func add(_ text: String, _ color: UIColor) {
            out.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }

        let prices = product.snapshots.compactMap { $0.price }

        guard let last = prices.last else {
            add("chưa có giá", white)
            return out
        }

        add(TPIOSSaleFormat.money(last), white)

        if prices.count >= 2 {
            let delta = TPIOSSaleFormat.delta(current: last, previous: prices[prices.count - 2])
            add("  " + delta.text, delta.color)
        }

        if let low = prices.min() {
            add("  · thấp nhất " + TPIOSSaleFormat.money(low), white.withAlphaComponent(0.6))
        }

        return out
    }

    // MARK: Khối: chi tiết 1 sản phẩm

    private func detailBlocks(_ product: TPIOSWatchedSale) -> [TPIOSSaleBlock] {
        var b: [TPIOSSaleBlock] = []

        b.append(labelBlock(makeLabel(product.title, size: 14, weight: .bold, alpha: 1), top: 16))

        if let variant = product.variantName, variant.isEmpty == false {
            b.append(labelBlock(makeLabel("Phân loại: \(variant)", size: 12, alpha: 0.6), top: 2))
        }

        let stats = makeLabel("", size: 12, alpha: 0.9, mono: true)
        stats.attributedText = statsAttributed(product)
        b.append(labelBlock(stats, top: 8))

        b.append(labelBlock(
            makeLabel("MÃ GIẢM GIÁ (\(product.vouchers.count))", weight: .semibold),
            top: 16
        ))
        b.append(labelBlock(
            makeLabel(voucherSummary(product), size: 12, alpha: 0.9, mono: true),
            top: 6
        ))

        for voucher in product.vouchers {
            b.append(fixedBlock(makeVoucherRow(voucher), height: 38, top: 6))
        }

        b.append(labelBlock(makeLabel("LỊCH SỬ GIÁ", weight: .semibold), top: 16))

        let indexed = Array(product.snapshots.enumerated()).suffix(15).reversed()
        for (index, snapshot) in indexed {
            let previous: Double? = index > 0 ? product.snapshots[index - 1].price : nil
            b.append(fixedBlock(
                makeHistoryRow(snapshot: snapshot, index: index, previous: previous),
                height: 34,
                top: 4
            ))
        }

        let deleteTitle = pendingDeleteConfirm
            ? "Chạm lần nữa để xoá sản phẩm"
            : "Xoá sản phẩm này"
        b.append(fixedBlock(
            pillButton(
                deleteTitle,
                color: UIColor(red: 0.70, green: 0.15, blue: 0.12, alpha: 0.9),
                action: #selector(deleteProductTapped)
            ),
            height: 38,
            top: 18
        ))

        b.append(noteBlock())
        return b
    }

    private func statsAttributed(_ product: TPIOSWatchedSale) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let boldFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let white = UIColor.white.withAlphaComponent(0.9)
        let out = NSMutableAttributedString()

        func add(_ text: String, color: UIColor? = nil, bold: Bool = false) {
            out.append(NSAttributedString(
                string: text,
                attributes: [.font: bold ? boldFont : font, .foregroundColor: color ?? white]
            ))
        }

        let entries: [(price: Double, date: Date)] = product.snapshots.compactMap {
            guard let price = $0.price else { return nil }
            return (price, $0.timestamp)
        }

        guard let last = entries.last else {
            add("Chưa có giá nào.")
            return out
        }

        add("Giá hiện tại: " + TPIOSSaleFormat.money(last.price), bold: true)

        if entries.count >= 2 {
            let previous = entries[entries.count - 2].price
            let delta = TPIOSSaleFormat.delta(current: last.price, previous: previous)
            add("\n  " + delta.text, color: delta.color)
            add("  so với lần trước (" + TPIOSSaleFormat.money(previous) + ")")
        }

        if let low = entries.min(by: { $0.price < $1.price }),
           let high = entries.max(by: { $0.price < $1.price }) {
            add("\nThấp nhất: " + TPIOSSaleFormat.money(low.price) + " (" + TPIOSSaleFormat.date(low.date) + ")")
            add("\nCao nhất:  " + TPIOSSaleFormat.money(high.price) + " (" + TPIOSSaleFormat.date(high.date) + ")")

            if entries.count >= 2 {
                if last.price <= low.price {
                    add("\nĐang ở mức THẤP NHẤT từng ghi.", color: UIColor(red: 0.35, green: 0.85, blue: 0.5, alpha: 1), bold: true)
                } else {
                    add("\nCao hơn mức thấp nhất " + TPIOSSaleFormat.money(last.price - low.price))
                }
            }
        }

        add("\nĐã quét \(entries.count) lần, gần nhất " + TPIOSSaleFormat.date(last.date))
        return out
    }

    private func voucherSummary(_ product: TPIOSWatchedSale) -> String {
        guard let price = product.snapshots.compactMap({ $0.price }).last else {
            return ""
        }

        if product.vouchers.isEmpty {
            return "Chưa có mã nào. Bấm \"Quét mã\" rồi chạm vào thẻ mã giảm giá trên màn hình Shopee."
        }

        let result = TPIOSSaleVoucherMath.best(vouchers: product.vouchers, price: price)
        var lines = ["Mã tốt nhất cho giá " + TPIOSSaleFormat.money(price) + ":"]

        if result.picks.isEmpty {
            lines.append("  Chưa có mã nào đủ điều kiện.")
        } else {
            for pick in result.picks {
                lines.append(
                    "  • " + TPIOSSaleKind.name(pick.voucher.kind) + ": " + pick.voucher.title +
                    "  → -" + TPIOSSaleFormat.money(pick.amount)
                )
            }
        }

        lines.append("Giá sau mã (ước tính): " + TPIOSSaleFormat.money(result.finalPrice))

        if result.totalOnPrice > 0, price > 0 {
            let percent = String(format: "%.1f%%", result.totalOnPrice / price * 100)
            lines.append("Tiết kiệm: " + TPIOSSaleFormat.money(result.totalOnPrice) + " (" + percent + ")")
        }

        if result.freeshipAmount > 0 {
            lines.append("Giảm phí ship thêm: -" + TPIOSSaleFormat.money(result.freeshipAmount))
        }

        if result.ineligibleCount > 0 {
            lines.append("Chưa đủ điều kiện: \(result.ineligibleCount) mã (đơn tối thiểu cao hơn giá)")
        }

        return lines.joined(separator: "\n")
    }

    private func makeVoucherRow(_ voucher: TPIOSSaleVoucher) -> UIView {
        let row = UIView()
        row.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        row.layer.cornerRadius = 8

        let label = UILabel()
        label.text = voucher.title
        label.textColor = .white
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail

        let kindButton = UIButton(type: .system)
        kindButton.setTitle(TPIOSSaleKind.name(voucher.kind), for: .normal)
        kindButton.setTitleColor(.white, for: .normal)
        kindButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        kindButton.backgroundColor = TPIOSSaleKind.color(voucher.kind)
        kindButton.layer.cornerRadius = 8
        kindButton.accessibilityIdentifier = voucher.id
        kindButton.addTarget(self, action: #selector(voucherKindTapped(_:)), for: .touchUpInside)

        let trash = UIButton(type: .system)
        trash.setImage(UIImage(systemName: "trash"), for: .normal)
        trash.tintColor = UIColor.systemRed.withAlphaComponent(0.85)
        trash.accessibilityIdentifier = voucher.id
        trash.addTarget(self, action: #selector(voucherDeleteTapped(_:)), for: .touchUpInside)

        [label, kindButton, trash].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: kindButton.leadingAnchor, constant: -6),

            kindButton.trailingAnchor.constraint(equalTo: trash.leadingAnchor, constant: -4),
            kindButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            kindButton.widthAnchor.constraint(equalToConstant: 46),
            kindButton.heightAnchor.constraint(equalToConstant: 24),

            trash.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
            trash.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            trash.widthAnchor.constraint(equalToConstant: 30)
        ])

        return row
    }

    private func makeHistoryRow(snapshot: TPIOSSaleSnapshot, index: Int, previous: Double?) -> UIView {
        let row = UIView()
        row.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        row.layer.cornerRadius = 8

        let font = UIFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let white = UIColor.white.withAlphaComponent(0.88)
        let text = NSMutableAttributedString()

        text.append(NSAttributedString(
            string: TPIOSSaleFormat.date(snapshot.timestamp) + "  " + (snapshot.price.map { TPIOSSaleFormat.money($0) } ?? "-"),
            attributes: [.font: font, .foregroundColor: white]
        ))

        if let price = snapshot.price, let previous {
            let delta = TPIOSSaleFormat.delta(current: price, previous: previous)
            text.append(NSAttributedString(
                string: "  " + delta.text,
                attributes: [.font: font, .foregroundColor: delta.color]
            ))
        }

        let label = UILabel()
        label.attributedText = text
        label.lineBreakMode = .byTruncatingTail

        let trash = UIButton(type: .system)
        trash.setImage(UIImage(systemName: "trash"), for: .normal)
        trash.tintColor = UIColor.systemRed.withAlphaComponent(0.85)
        trash.tag = index
        trash.addTarget(self, action: #selector(historyDeleteTapped(_:)), for: .touchUpInside)

        [label, trash].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trash.leadingAnchor, constant: -6),

            trash.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
            trash.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            trash.widthAnchor.constraint(equalToConstant: 30)
        ])

        return row
    }

    // MARK: Hành động

    @objc private func productRowTapped(_ sender: UIButton) {
        guard let idString = sender.accessibilityIdentifier,
              let id = UUID(uuidString: idString) else {
            return
        }

        selectedProductID = id
        pendingScan = nil
        pendingVoucher = nil
        pendingDeleteConfirm = false
        statusText = ""
        render()
        scrollView.setContentOffset(.zero, animated: false)
    }

    @objc private func nameChoiceTapped(_ sender: UIButton) {
        pendingScan?.selectedName = sender.tag
        render()
    }

    @objc private func priceChoiceTapped(_ sender: UIButton) {
        guard let pending = pendingScan,
              sender.tag < pending.prices.count else {
            return
        }

        let price = pending.prices[sender.tag].amount

        let name: String
        if pending.selectedName < pending.names.count {
            name = pending.names[pending.selectedName]
        } else {
            name = "SP không rõ tên " + TPIOSSaleFormat.date(Date())
        }

        let result = TPIOSSaleStore.shared.recordScan(name: name, variant: pending.variant, price: price)

        selectedProductID = result.product.id
        pendingScan = nil
        pendingVoucher = nil
        pendingDeleteConfirm = false

        var message = "Đã lưu " + TPIOSSaleFormat.money(price)
        if let previous = result.previousPrice {
            let delta = TPIOSSaleFormat.delta(current: price, previous: previous)
            message += " — " + delta.text + " so với lần trước."
        } else {
            message += " — sản phẩm mới."
        }
        statusText = message

        render()
        scrollView.setContentOffset(.zero, animated: false)

        TPIOSLog.shared.log("Sale: lưu giá \(Int(price)) cho sản phẩm \(result.product.id.uuidString)")
    }

    @objc private func cancelPendingTapped() {
        pendingScan = nil
        pendingVoucher = nil
        render()
    }

    @objc private func pendingVoucherKindTapped() {
        guard var parsed = pendingVoucher?.parsed else { return }
        parsed.kind = TPIOSSaleKind.next(parsed.kind)
        pendingVoucher?.parsed = parsed
        render()
    }

    @objc private func saveVoucherTapped() {
        guard let productID = selectedProductID,
              let parsed = pendingVoucher?.parsed else {
            return
        }

        let voucher = TPIOSSaleVoucher(
            id: UUID().uuidString,
            title: parsed.title,
            kind: parsed.kind,
            isPercent: parsed.isPercent,
            value: parsed.value,
            minSpend: parsed.minSpend,
            maxDiscount: parsed.maxDiscount,
            expiryText: parsed.expiryText
        )

        let added = TPIOSSaleStore.shared.addVoucher(productID: productID, voucher: voucher)

        pendingVoucher = nil
        statusText = added ? "Đã lưu mã: " + parsed.title : "Mã này đã có trong danh sách."
        render()
    }

    @objc private func voucherKindTapped(_ sender: UIButton) {
        guard let productID = selectedProductID,
              let voucherID = sender.accessibilityIdentifier else {
            return
        }

        TPIOSSaleStore.shared.cycleVoucherKind(productID: productID, voucherID: voucherID)
        render()
    }

    @objc private func voucherDeleteTapped(_ sender: UIButton) {
        guard let productID = selectedProductID,
              let voucherID = sender.accessibilityIdentifier else {
            return
        }

        TPIOSSaleStore.shared.removeVoucher(productID: productID, voucherID: voucherID)
        render()
    }

    @objc private func historyDeleteTapped(_ sender: UIButton) {
        guard let productID = selectedProductID else { return }

        TPIOSSaleStore.shared.deleteSnapshot(productID: productID, index: sender.tag)
        render()
    }

    @objc private func deleteProductTapped() {
        guard let productID = selectedProductID else { return }

        if pendingDeleteConfirm == false {
            pendingDeleteConfirm = true
            render()
            return
        }

        TPIOSSaleStore.shared.deleteProduct(productID)
        pendingDeleteConfirm = false
        selectedProductID = nil
        statusText = "Đã xoá sản phẩm."
        render()
    }

    @objc private func backTapped() {
        if pendingScan != nil || pendingVoucher != nil {
            pendingScan = nil
            pendingVoucher = nil
            render()
            return
        }

        if selectedProductID != nil {
            selectedProductID = nil
            pendingDeleteConfirm = false
            statusText = ""
            render()
            return
        }

        onBack?()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    // MARK: Chạm để quét

    private func scanPriceTapped() {
        endEditing(true)
        pickPurpose = .product
        startRegionPick(hint: "Chạm vào sản phẩm cần quét giá (tên hoặc giá)")
    }

    private func scanVoucherTapped() {
        endEditing(true)

        guard selectedProductID != nil else {
            statusText = "Mở 1 sản phẩm trước rồi mới quét mã."
            render()
            return
        }

        pickPurpose = .voucher
        startRegionPick(hint: "Chạm vào giữa thẻ mã giảm giá cần đọc")
    }

    private func startRegionPick(hint text: String) {
        guard let hostWindow = self.window else { return }

        isHidden = true

        let overlay = UIView(frame: hostWindow.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.001)

        let hint = UILabel()
        hint.text = text
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        hint.layer.cornerRadius = 10
        hint.clipsToBounds = true
        let safeTop = hostWindow.safeAreaInsets.top
        hint.frame = CGRect(x: 20, y: safeTop + 14, width: hostWindow.bounds.width - 100, height: 44)
        overlay.addSubview(hint)

        let cancel = UIButton(type: .system)
        cancel.setTitle("Huỷ", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        cancel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        cancel.layer.cornerRadius = 8
        cancel.frame = CGRect(x: hostWindow.bounds.width - 72, y: safeTop + 14, width: 56, height: 44)
        cancel.addTarget(self, action: #selector(cancelRegionPick), for: .touchUpInside)
        overlay.addSubview(cancel)
        pickCancelButton = cancel

        let tap = UITapGestureRecognizer(target: self, action: #selector(regionPicked(_:)))
        tap.delegate = self
        overlay.addGestureRecognizer(tap)

        hostWindow.addSubview(overlay)
        pickOverlay = overlay
    }

    @objc private func cancelRegionPick() {
        pickOverlay?.removeFromSuperview()
        pickOverlay = nil
        pickCancelButton = nil
        isHidden = false
    }

    @objc private func regionPicked(_ gesture: UITapGestureRecognizer) {
        guard let overlay = pickOverlay else { return }
        let point = gesture.location(in: overlay)

        overlay.removeFromSuperview()
        pickOverlay = nil
        pickCancelButton = nil
        isHidden = false

        handlePick(at: point)
    }

    private func handlePick(at point: CGPoint) {
        guard let root = TPIOSSaleScanner.visibleAppRoot(excluding: self.window) else {
            statusText = "Không tìm thấy màn hình app để quét."
            render()
            return
        }

        let items = TPIOSSaleScanner.collectItems(in: root)

        switch pickPurpose {
        case .product:
            scanProduct(items: items, point: point)
        case .voucher:
            scanVoucher(items: items, point: point)
        }
    }

    private func scanProduct(items: [TPIOSSaleTextItem], point: CGPoint) {
        var prices = TPIOSSaleScanner.priceValues(in: items, near: point, radius: 140)
        var wholeScreen = false

        if prices.isEmpty {
            prices = TPIOSSaleScanner.priceValues(in: items, near: nil, radius: 0)
            wholeScreen = true
        }

        guard prices.isEmpty == false else {
            pendingScan = nil
            statusText = "Không quét được số tiền nào. Đứng đúng trang sản phẩm hoặc giỏ hàng rồi thử lại."
            render()
            return
        }

        var names = TPIOSSaleScanner.nameCandidates(in: items, near: point, radius: 260)
        if names.isEmpty {
            names = TPIOSSaleScanner.nameCandidates(in: items, near: nil, radius: 0)
        }

        let variant = TPIOSSaleScanner.variantText(in: items, near: point, radius: 260)

        pendingScan = TPIOSSalePendingScan(names: names, selectedName: 0, variant: variant, prices: prices)
        pendingVoucher = nil

        statusText = wholeScreen
            ? "Không thấy giá gần điểm chạm, đang hiện giá toàn màn hình."
            : "Tìm được \(prices.count) giá gần điểm chạm."

        render()
        scrollView.setContentOffset(.zero, animated: false)

        TPIOSLog.shared.log("Sale: quét sản phẩm, \(prices.count) giá, \(names.count) tên")
    }

    private func scanVoucher(items: [TPIOSSaleTextItem], point: CGPoint) {
        let lines = TPIOSSaleScanner.voucherLines(in: items, near: point, bandHalfHeight: 75)

        pendingVoucher = TPIOSSalePendingVoucher(
            lines: lines,
            parsed: TPIOSSaleVoucherParser.parse(lines: lines)
        )
        pendingScan = nil
        statusText = ""

        render()
        scrollView.setContentOffset(.zero, animated: false)

        TPIOSLog.shared.log("Sale: quét thẻ mã, \(lines.count) dòng chữ")
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        if touch.view === backButton ||
           touch.view === closeButton ||
           touch.view === resizeHandle ||
           touch.view === pickCancelButton {
            return false
        }

        return true
    }
}


// MARK: - View phụ

private struct TPIOSSaleBlock {
    let view: UIView
    let spacingTop: CGFloat
    let height: (CGFloat) -> CGFloat
}

private enum TPIOSSalePickPurpose {
    case product
    case voucher
}

private struct TPIOSSalePendingScan {
    var names: [String]
    var selectedName: Int
    var variant: String?
    var prices: [TPIOSSaleScanValue]
}

private struct TPIOSSalePendingVoucher {
    var lines: [String]
    var parsed: TPIOSSaleParsedVoucher?
}

private final class TPIOSSaleActionRow: UIView {

    var onScanPrice: (() -> Void)?
    var onScanVoucher: (() -> Void)?

    var showsVoucher = false {
        didSet {
            setNeedsLayout()
        }
    }

    private let priceButton = UIButton(type: .system)
    private let voucherButton = UIButton(type: .system)
    private let priceLabel = UILabel()
    private let voucherLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        configure(
            priceButton,
            icon: "text.viewfinder",
            colors: [
                UIColor(red: 0.68, green: 0.47, blue: 1.00, alpha: 1),
                UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)
            ],
            action: #selector(priceTapped)
        )

        configure(
            voucherButton,
            icon: "ticket.fill",
            colors: [
                UIColor(red: 1.00, green: 0.65, blue: 0.25, alpha: 1),
                UIColor(red: 0.85, green: 0.25, blue: 0.08, alpha: 1)
            ],
            action: #selector(voucherTapped)
        )

        caption(priceLabel, "Quét giá")
        caption(voucherLabel, "Quét mã")

        addSubview(priceButton)
        addSubview(priceLabel)
        addSubview(voucherButton)
        addSubview(voucherLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(_ button: UIButton, icon: String, colors: [UIColor], action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 23, weight: .semibold)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.tintColor = .white
        TPIOSPanelStyle.applyGradientFill(to: button, colors: colors, cornerRadius: 18)
        button.layer.cornerRadius = 18
        button.addTarget(self, action: action, for: .touchUpInside)

        if let imageView = button.imageView {
            button.bringSubviewToFront(imageView)
        }
    }

    private func caption(_ label: UILabel, _ text: String) {
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 12.5, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
    }

    @objc private func priceTapped() {
        onScanPrice?()
    }

    @objc private func voucherTapped() {
        onScanVoucher?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let icon: CGFloat = 62
        let gap: CGFloat = 26
        let count: CGFloat = showsVoucher ? 2 : 1
        let total = icon * count + gap * (count - 1)
        let startX = max(0, (bounds.width - total) / 2)

        priceButton.frame = CGRect(x: startX, y: 0, width: icon, height: icon)
        priceLabel.frame = CGRect(x: startX - 8, y: icon + 5, width: icon + 16, height: 18)

        voucherButton.isHidden = showsVoucher == false
        voucherLabel.isHidden = showsVoucher == false

        if showsVoucher {
            let x = startX + icon + gap
            voucherButton.frame = CGRect(x: x, y: 0, width: icon, height: icon)
            voucherLabel.frame = CGRect(x: x - 8, y: icon + 5, width: icon + 16, height: 18)
        }

        TPIOSPanelStyle.syncFrames(in: priceButton)
        TPIOSPanelStyle.syncFrames(in: voucherButton)
    }
}

private final class TPIOSSaleButtonRow: UIView {

    private let buttons: [UIButton]

    init(buttons: [UIButton]) {
        self.buttons = buttons
        super.init(frame: .zero)
        buttons.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let gap: CGFloat = 8
        let count = CGFloat(buttons.count)
        let width = (bounds.width - gap * (count - 1)) / max(1, count)

        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(
                x: CGFloat(index) * (width + gap),
                y: 0,
                width: width,
                height: bounds.height
            )
        }
    }
}

private final class TPIOSSaleProductRow: UIButton {

    private let nameLabel = UILabel()
    private let infoLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.white.withAlphaComponent(0.07)
        layer.cornerRadius = 12

        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isUserInteractionEnabled = false

        infoLabel.lineBreakMode = .byTruncatingTail
        infoLabel.isUserInteractionEnabled = false

        addSubview(nameLabel)
        addSubview(infoLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, info: NSAttributedString) {
        nameLabel.text = name
        infoLabel.attributedText = info
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        nameLabel.frame = CGRect(x: 12, y: 8, width: max(0, bounds.width - 24), height: 18)
        infoLabel.frame = CGRect(x: 12, y: 30, width: max(0, bounds.width - 24), height: 18)
    }
}


// MARK: - Định dạng

private enum TPIOSSaleFormat {

    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: value)) ?? "0") + "đ"
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "chưa có" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter.string(from: date)
    }

    static func delta(current: Double, previous: Double) -> (text: String, color: UIColor) {
        let diff = current - previous

        if abs(diff) < 1 {
            return ("= không đổi", UIColor.white.withAlphaComponent(0.6))
        }

        let percent = previous > 0 ? abs(diff) / previous * 100 : 0
        let percentText = String(format: "%.1f%%", percent)

        if diff < 0 {
            return (
                "▼ " + money(abs(diff)) + " (" + percentText + ")",
                UIColor(red: 0.35, green: 0.85, blue: 0.5, alpha: 1)
            )
        }

        return (
            "▲ " + money(diff) + " (" + percentText + ")",
            UIColor(red: 1.0, green: 0.45, blue: 0.4, alpha: 1)
        )
    }
}

private enum TPIOSSaleKind {

    static let order = ["shop", "platform", "freeship"]

    static func name(_ kind: String) -> String {
        switch kind {
        case "platform": return "Sàn"
        case "freeship": return "Ship"
        default: return "Shop"
        }
    }

    static func color(_ kind: String) -> UIColor {
        switch kind {
        case "platform": return UIColor(red: 0.85, green: 0.30, blue: 0.20, alpha: 1)
        case "freeship": return UIColor(red: 0.10, green: 0.60, blue: 0.55, alpha: 1)
        default: return UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)
        }
    }

    static func next(_ kind: String) -> String {
        guard let index = order.firstIndex(of: kind) else { return order[0] }
        return order[(index + 1) % order.count]
    }
}


// MARK: - Dữ liệu lưu trữ

struct TPIOSSaleSnapshot: Codable {
    let timestamp: Date
    let productName: String?
    let itemID: String?
    let shopID: String?
    let variantID: String?
    let variantName: String?
    let price: Double?
    let finalPrice: Double?
    let analysisNote: String
}

struct TPIOSSaleVoucher: Codable {
    let id: String
    var title: String
    var kind: String
    var isPercent: Bool
    var value: Double
    var minSpend: Double
    var maxDiscount: Double?
    var expiryText: String?
}

struct TPIOSWatchedSale: Codable {
    let id: UUID
    var url: String
    var title: String
    var itemID: String?
    var shopID: String?
    var variantID: String?
    var variantName: String?
    var createdAt: Date
    var lastCheckedAt: Date?
    var bestFinalPrice: Double?
    var snapshots: [TPIOSSaleSnapshot]
    var vouchers: [TPIOSSaleVoucher]

    enum CodingKeys: String, CodingKey {
        case id, url, title, itemID, shopID, variantID, variantName
        case createdAt, lastCheckedAt, bestFinalPrice, snapshots, vouchers
    }

    init(
        id: UUID,
        url: String,
        title: String,
        itemID: String?,
        shopID: String?,
        variantID: String?,
        variantName: String?,
        createdAt: Date,
        lastCheckedAt: Date?,
        bestFinalPrice: Double?,
        snapshots: [TPIOSSaleSnapshot],
        vouchers: [TPIOSSaleVoucher]
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.itemID = itemID
        self.shopID = shopID
        self.variantID = variantID
        self.variantName = variantName
        self.createdAt = createdAt
        self.lastCheckedAt = lastCheckedAt
        self.bestFinalPrice = bestFinalPrice
        self.snapshots = snapshots
        self.vouchers = vouchers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        title = try c.decode(String.self, forKey: .title)
        itemID = try c.decodeIfPresent(String.self, forKey: .itemID)
        shopID = try c.decodeIfPresent(String.self, forKey: .shopID)
        variantID = try c.decodeIfPresent(String.self, forKey: .variantID)
        variantName = try c.decodeIfPresent(String.self, forKey: .variantName)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastCheckedAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        bestFinalPrice = try c.decodeIfPresent(Double.self, forKey: .bestFinalPrice)
        snapshots = try c.decodeIfPresent([TPIOSSaleSnapshot].self, forKey: .snapshots) ?? []
        // Bản lưu cũ chưa có mã giảm giá.
        vouchers = try c.decodeIfPresent([TPIOSSaleVoucher].self, forKey: .vouchers) ?? []
    }
}

private enum TPIOSSaleMatcher {

    static func normalize(_ text: String) -> String {
        var value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        while value.hasSuffix("…") || value.hasSuffix(".") {
            value.removeLast()
        }

        return value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // Cùng sản phẩm nếu tên trùng, hoặc 1 tên là phần đầu của tên kia (tên
    // bị cắt "…" ở giỏ hàng nhưng đầy đủ ở trang sản phẩm). Phân loại chỉ
    // so khi cả 2 bên đều có.
    static func same(name a: String, variant va: String?, with b: String, variant vb: String?) -> Bool {
        let na = normalize(a)
        let nb = normalize(b)

        guard na.isEmpty == false, nb.isEmpty == false else { return false }

        let shorter = na.count <= nb.count ? na : nb
        let longer = na.count <= nb.count ? nb : na

        let nameMatches = na == nb || (shorter.count >= 12 && longer.hasPrefix(shorter))
        guard nameMatches else { return false }

        let x = normalize(va ?? "")
        let y = normalize(vb ?? "")

        if x.isEmpty || y.isEmpty {
            return true
        }

        return x == y
    }
}

private final class TPIOSSaleStore {

    static let shared = TPIOSSaleStore()

    private let key = "TPIOS.Sale.WatchedProducts.v1"
    private let defaults = UserDefaults.standard

    private init() {}

    func load() -> [TPIOSWatchedSale] {
        guard let data = defaults.data(forKey: key) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return (try? decoder.decode([TPIOSWatchedSale].self, from: data)) ?? []
    }

    private func save(_ products: [TPIOSWatchedSale]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(products) else { return }
        defaults.set(data, forKey: key)
    }

    func recordScan(
        name: String,
        variant: String?,
        price: Double
    ) -> (product: TPIOSWatchedSale, previousPrice: Double?) {

        var products = load()

        let snapshot = TPIOSSaleSnapshot(
            timestamp: Date(),
            productName: name,
            itemID: nil,
            shopID: nil,
            variantID: nil,
            variantName: variant,
            price: price,
            finalPrice: price,
            analysisNote: "Giá chọn tay từ quét màn hình (chạm theo vùng)."
        )

        if let index = products.firstIndex(where: {
            TPIOSSaleMatcher.same(name: $0.title, variant: $0.variantName, with: name, variant: variant)
        }) {
            let previous = products[index].snapshots.compactMap { $0.price }.last

            products[index].snapshots.append(snapshot)
            products[index].lastCheckedAt = snapshot.timestamp

            if (products[index].variantName ?? "").isEmpty, let variant, variant.isEmpty == false {
                products[index].variantName = variant
            }

            // Tên lần này đầy đủ hơn tên đã lưu (bị cắt "…") thì lấy tên dài.
            if name.count > products[index].title.count {
                products[index].title = name
            }

            save(products)
            return (products[index], previous)
        }

        let product = TPIOSWatchedSale(
            id: UUID(),
            url: "",
            title: name,
            itemID: nil,
            shopID: nil,
            variantID: nil,
            variantName: variant,
            createdAt: Date(),
            lastCheckedAt: snapshot.timestamp,
            bestFinalPrice: nil,
            snapshots: [snapshot],
            vouchers: []
        )

        products.insert(product, at: 0)
        save(products)
        return (product, nil)
    }

    func deleteProduct(_ id: UUID) {
        var products = load()
        products.removeAll { $0.id == id }
        save(products)
    }

    func deleteSnapshot(productID: UUID, index: Int) {
        var products = load()

        guard let productIndex = products.firstIndex(where: { $0.id == productID }),
              index >= 0,
              index < products[productIndex].snapshots.count else {
            return
        }

        products[productIndex].snapshots.remove(at: index)
        products[productIndex].lastCheckedAt = products[productIndex].snapshots.last?.timestamp
        save(products)
    }

    @discardableResult
    func addVoucher(productID: UUID, voucher: TPIOSSaleVoucher) -> Bool {
        var products = load()

        guard let index = products.firstIndex(where: { $0.id == productID }) else {
            return false
        }

        let duplicate = products[index].vouchers.contains {
            $0.kind == voucher.kind &&
            $0.isPercent == voucher.isPercent &&
            $0.value == voucher.value &&
            $0.minSpend == voucher.minSpend &&
            $0.maxDiscount == voucher.maxDiscount
        }

        if duplicate {
            return false
        }

        products[index].vouchers.append(voucher)
        save(products)
        return true
    }

    func removeVoucher(productID: UUID, voucherID: String) {
        var products = load()

        guard let index = products.firstIndex(where: { $0.id == productID }) else { return }

        products[index].vouchers.removeAll { $0.id == voucherID }
        save(products)
    }

    func cycleVoucherKind(productID: UUID, voucherID: String) {
        var products = load()

        guard let productIndex = products.firstIndex(where: { $0.id == productID }),
              let voucherIndex = products[productIndex].vouchers.firstIndex(where: { $0.id == voucherID }) else {
            return
        }

        let current = products[productIndex].vouchers[voucherIndex].kind
        products[productIndex].vouchers[voucherIndex].kind = TPIOSSaleKind.next(current)
        save(products)
    }
}


// MARK: - Tính tổ hợp mã giảm giá

private struct TPIOSSalePick {
    let voucher: TPIOSSaleVoucher
    let amount: Double
}

private struct TPIOSSaleVoucherResult {
    let picks: [TPIOSSalePick]
    let totalOnPrice: Double
    let freeshipAmount: Double
    let finalPrice: Double
    let ineligibleCount: Int
}

// Quy tắc đơn giản hoá: mỗi loại (Shop / Sàn / Freeship) chỉ áp tối đa 1
// mã, chọn mã giảm nhiều nhất cho giá hiện tại. Mã Shop và mã Sàn cộng dồn
// vào giá sản phẩm, mã Freeship tính riêng (giảm phí ship). Mọi mức giảm
// tính trên giá gốc của 1 sản phẩm, không xét số lượng hay thứ tự áp mã nên
// chỉ là ước tính.
private enum TPIOSSaleVoucherMath {

    static func discount(_ voucher: TPIOSSaleVoucher, price: Double) -> Double? {
        guard price >= voucher.minSpend else { return nil }

        var amount = voucher.isPercent ? price * voucher.value / 100 : voucher.value

        if let cap = voucher.maxDiscount, cap > 0 {
            amount = min(amount, cap)
        }

        return max(0, amount)
    }

    static func best(vouchers: [TPIOSSaleVoucher], price: Double) -> TPIOSSaleVoucherResult {
        var picks: [TPIOSSalePick] = []
        var ineligible = 0

        for kind in TPIOSSaleKind.order {
            var bestPick: TPIOSSalePick?

            for voucher in vouchers where voucher.kind == kind {
                guard let amount = discount(voucher, price: price) else {
                    ineligible += 1
                    continue
                }

                if amount > (bestPick?.amount ?? 0) {
                    bestPick = TPIOSSalePick(voucher: voucher, amount: amount)
                }
            }

            if let bestPick {
                picks.append(bestPick)
            }
        }

        let onPrice = picks
            .filter { $0.voucher.kind != "freeship" }
            .reduce(0) { $0 + $1.amount }

        let freeship = picks
            .filter { $0.voucher.kind == "freeship" }
            .reduce(0) { $0 + $1.amount }

        let cappedOnPrice = min(onPrice, price)

        return TPIOSSaleVoucherResult(
            picks: picks,
            totalOnPrice: cappedOnPrice,
            freeshipAmount: freeship,
            finalPrice: price - cappedOnPrice,
            ineligibleCount: ineligible
        )
    }
}


// MARK: - Đọc mã giảm giá từ chữ trên màn hình

private struct TPIOSSaleParsedVoucher {
    var title: String
    var kind: String
    var isPercent: Bool
    var value: Double
    var minSpend: Double
    var maxDiscount: Double?
    var expiryText: String?
}

private enum TPIOSSaleVoucherParser {

    static func parse(lines: [String]) -> TPIOSSaleParsedVoucher? {
        guard lines.isEmpty == false else { return nil }

        var text = lines.joined(separator: " | ")
            .replacingOccurrences(of: "₫", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        // "50.000đ" → "50.000" (chỉ bỏ chữ đ ngay sau chữ số, giữ nguyên
        // các từ như "đơn", "tối đa").
        text = text.replacingOccurrences(
            of: "(?<=\\d)[đĐ]",
            with: "",
            options: .regularExpression
        )

        let lower = text.lowercased()

        let isFreeship =
            lower.contains("miễn phí vận chuyển") ||
            lower.contains("freeship") ||
            lower.contains("free ship") ||
            lower.contains("phí vận chuyển")

        var isPercent = false
        var value: Double?

        if let groups = capture(#"giảm(?:\s+giá)?\s+(\d[\d.,]*)\s*(%|k\b|tr\b|nghìn|triệu)?"#, in: lower),
           let parsed = number(groups[0], suffix: groups[1]),
           parsed.value > 0 {
            isPercent = parsed.isPercent
            value = parsed.value
        }

        if isPercent, let current = value, current > 100 {
            value = nil
        }

        if value == nil && isFreeship == false {
            return nil
        }

        var maxDiscount: Double?
        if let groups = capture(#"tối\s*đa\s*(\d[\d.,]*)\s*(k\b|tr\b|nghìn|triệu)?"#, in: lower),
           let parsed = number(groups[0], suffix: groups[1]),
           parsed.hasUnit || parsed.value >= 1000 {
            maxDiscount = parsed.value
        }

        var minSpend = 0.0
        if let groups = capture(
            #"(?:đơn\s*tối\s*thiểu|tối\s*thiểu|đơn(?:\s*hàng)?\s*từ|chi\s*tiêu\s*tối\s*thiểu)\s*(\d[\d.,]*)\s*(k\b|tr\b|nghìn|triệu)?"#,
            in: lower
        ),
           let parsed = number(groups[0], suffix: groups[1]),
           parsed.hasUnit || parsed.value >= 1000 {
            minSpend = parsed.value
        }

        var expiry: String?
        if let groups = capture(#"((?:hsd|hết hạn|hạn dùng)[^|]{0,28})"#, in: text) {
            expiry = groups[0].trimmingCharacters(in: .whitespaces)
        }

        let kind: String
        if isFreeship {
            kind = "freeship"
        } else if lower.contains("shopee voucher") ||
                    lower.contains("voucher shopee") ||
                    lower.contains("mã shopee") ||
                    lower.contains("toàn sàn") {
            kind = "platform"
        } else {
            kind = "shop"
        }

        let amountValue = value ?? 0

        var title: String
        if isPercent {
            title = "Giảm " + trimmed(amountValue) + "%"
        } else if amountValue > 0 {
            title = "Giảm " + TPIOSSaleFormat.money(amountValue)
        } else {
            title = "Miễn phí vận chuyển"
        }

        if let maxDiscount {
            title += " tối đa " + TPIOSSaleFormat.money(maxDiscount)
        }

        if minSpend > 0 {
            title += " · đơn từ " + TPIOSSaleFormat.money(minSpend)
        }

        return TPIOSSaleParsedVoucher(
            title: title,
            kind: kind,
            isPercent: isPercent,
            value: amountValue,
            minSpend: minSpend,
            maxDiscount: maxDiscount,
            expiryText: expiry
        )
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func capture(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)

        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        var groups: [String] = []

        for index in 1..<match.numberOfRanges {
            if let groupRange = Range(match.range(at: index), in: text) {
                groups.append(String(text[groupRange]))
            } else {
                groups.append("")
            }
        }

        return groups
    }

    private static func number(
        _ token: String,
        suffix: String
    ) -> (value: Double, isPercent: Bool, hasUnit: Bool)? {

        let unit = suffix.lowercased()

        if unit == "%" {
            guard let value = Double(token.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return (value, true, true)
        }

        if unit == "k" || unit == "nghìn" {
            guard let value = Double(token.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return (value * 1_000, false, true)
        }

        if unit == "tr" || unit == "triệu" {
            guard let value = Double(token.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return (value * 1_000_000, false, true)
        }

        let digits = token
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")

        guard let value = Double(digits) else { return nil }
        return (value, false, false)
    }
}


// MARK: - Scanner (đọc chữ đang hiển thị trên màn hình app)

private struct TPIOSSaleTextItem {
    let text: String
    let frame: CGRect
}

private struct TPIOSSaleScanValue {
    let text: String
    let amount: Double
    let frame: CGRect
}

private enum TPIOSSaleScanner {

    // Tìm root view của app phía sau overlay TPIOS — cùng cách
    // TPIOSAdBlock.overlayRootWindow() đã dùng, để nhất quán trong project.
    static func visibleAppRoot(excluding selfWindow: UIWindow?) -> UIView? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first(where: { $0 !== selfWindow })
            ?? UIApplication.shared.windows.first

        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }

        return controller?.view ?? window
    }

    // Đọc 1 lần toàn bộ chữ đang hiển thị (kèm khung hình trên màn hình),
    // bỏ phần nằm ngoài màn hình (ô cuộn chưa lộ ra) và trùng lặp.
    static func collectItems(in root: UIView) -> [TPIOSSaleTextItem] {
        var raw: [TPIOSSaleTextItem] = []
        collect(from: root, into: &raw)

        let screen = UIScreen.main.bounds
        var seen = Set<String>()
        var items: [TPIOSSaleTextItem] = []

        for item in raw {
            guard item.frame.intersects(screen) else { continue }

            let key = "\(item.text)|\(Int(item.frame.origin.x))|\(Int(item.frame.origin.y))"
            guard seen.insert(key).inserted else { continue }

            items.append(item)
        }

        return items
    }

    private static func collect(from view: UIView, into items: inout [TPIOSSaleTextItem]) {
        guard view.isHidden == false, view.alpha > 0.01 else { return }

        func add(_ text: String?) {
            guard let text else { return }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return }

            items.append(
                TPIOSSaleTextItem(text: trimmed, frame: view.convert(view.bounds, to: nil))
            )
        }

        if let label = view as? UILabel { add(label.text) }

        if let field = view as? UITextField {
            add(field.text)
            add(field.placeholder)
        }

        if let textView = view as? UITextView { add(textView.text) }

        if let button = view as? UIButton {
            add(button.currentTitle)
            add(button.accessibilityLabel)
        }

        add(view.accessibilityLabel)

        for child in view.subviews {
            collect(from: child, into: &items)
        }
    }

    // point != nil: chỉ giữ giá có khung cách điểm chạm trong bán kính,
    // gần nhất xếp trước. point == nil: toàn màn hình, số tiền lớn xếp trước.
    static func priceValues(
        in items: [TPIOSSaleTextItem],
        near point: CGPoint?,
        radius: CGFloat
    ) -> [TPIOSSaleScanValue] {

        var values: [TPIOSSaleScanValue] = []
        var seen = Set<String>()

        for item in items {
            for amount in extractAmounts(from: item.text) {
                let key = "\(item.text)|\(amount)|\(Int(item.frame.origin.x))|\(Int(item.frame.origin.y))"
                guard seen.insert(key).inserted else { continue }

                values.append(
                    TPIOSSaleScanValue(text: item.text, amount: amount, frame: item.frame)
                )
            }
        }

        if let point {
            values = values.filter { distance(from: point, to: $0.frame) <= radius }
            values.sort { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
        } else {
            values.sort { $0.amount > $1.amount }
        }

        return Array(values.prefix(20))
    }

    // Tên sản phẩm = dòng chữ dài, nhiều chữ cái, không phải nút/nhãn giao
    // diện, gần điểm chạm nhất.
    static func nameCandidates(
        in items: [TPIOSSaleTextItem],
        near point: CGPoint?,
        radius: CGFloat
    ) -> [String] {

        var scored: [(text: String, dist: CGFloat)] = []

        for item in items {
            guard isLikelyName(item.text) else { continue }

            var dist: CGFloat = 0

            if let point {
                dist = distance(from: point, to: item.frame)
                if dist > radius { continue }
            }

            scored.append((item.text, dist))
        }

        scored.sort {
            $0.dist != $1.dist ? $0.dist < $1.dist : $0.text.count > $1.text.count
        }

        var result: [String] = []
        var seen = Set<String>()

        for entry in scored {
            if seen.insert(entry.text.lowercased()).inserted {
                result.append(entry.text)
            }

            if result.count == 4 { break }
        }

        return result
    }

    private static func isLikelyName(_ text: String) -> Bool {
        let count = text.count
        guard count >= 10, count <= 160 else { return false }

        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 8 else { return false }

        let lower = text.lowercased()

        let strongNoise = [
            "thêm vào giỏ", "mua ngay", "đã bán", "phân loại", "xem thêm",
            "đánh giá", "thanh toán", "đặt hàng", "voucher", "freeship",
            "miễn phí vận chuyển", "lượt thích", "chat ngay", "shopee mall",
            "hoàn tiền", "tổng cộng", "đơn tối thiểu", "hsd", "hết hạn"
        ]

        if strongNoise.contains(where: { lower.contains($0) }) {
            return false
        }

        if count < 40 {
            let weakNoise = [
                "giảm ", "giao ", "xóa", "xoá", "sửa", "chọn", "tất cả",
                "quay lại", "kho", "ship", "ưu đãi", "gợi ý", "tìm kiếm",
                "giỏ hàng", "sản phẩm"
            ]

            if weakNoise.contains(where: { lower.contains($0) }) {
                return false
            }
        }

        if extractAmounts(from: text).isEmpty == false && letters < 14 {
            return false
        }

        return true
    }

    // Phân loại hàng thường hiện dạng "Phân loại: Đen, L".
    static func variantText(
        in items: [TPIOSSaleTextItem],
        near point: CGPoint?,
        radius: CGFloat
    ) -> String? {

        var best: (text: String, dist: CGFloat)?

        for item in items {
            let lower = item.text.lowercased()

            guard lower.hasPrefix("phân loại") ||
                  lower.hasPrefix("loại:") ||
                  lower.hasPrefix("variation") else {
                continue
            }

            var dist: CGFloat = 0

            if let point {
                dist = distance(from: point, to: item.frame)
                if dist > radius { continue }
            }

            let value = item.text.replacingOccurrences(
                of: "^(?i)(phân loại hàng|phân loại|loại|variation)\\s*[:：]?\\s*",
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            guard value.isEmpty == false else { continue }

            if best == nil || dist < (best?.dist ?? .greatestFiniteMagnitude) {
                best = (value, dist)
            }
        }

        return best?.text
    }

    // Các dòng chữ nằm cùng dải ngang với điểm chạm (1 thẻ mã giảm giá
    // thường cao ~100pt, các dòng chữ của thẻ nằm quanh điểm chạm).
    static func voucherLines(
        in items: [TPIOSSaleTextItem],
        near point: CGPoint,
        bandHalfHeight: CGFloat
    ) -> [String] {

        let picked = items
            .filter { abs($0.frame.midY - point.y) <= bandHalfHeight && $0.text.count <= 140 }
            .sorted {
                $0.frame.minY != $1.frame.minY
                    ? $0.frame.minY < $1.frame.minY
                    : $0.frame.minX < $1.frame.minX
            }

        var seen = Set<String>()
        var lines: [String] = []

        for item in picked {
            if seen.insert(item.text).inserted {
                lines.append(item.text)
            }

            if lines.count >= 14 { break }
        }

        return lines
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func extractAmounts(from text: String) -> [Double] {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "₫", with: "")
            .replacingOccurrences(of: "đ", with: "")
            .replacingOccurrences(of: "Đ", with: "")

        let pattern = #"(?<!\d)(\d{1,3}(?:[.,]\d{3})+|\d{4,9})(?!\d)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(normalized.startIndex..., in: normalized)
        let matches = regex.matches(in: normalized, range: range)

        return matches.compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: normalized) else {
                return nil
            }

            let raw = String(normalized[matchRange])
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "")

            guard let value = Double(raw),
                  value >= 1000,
                  value <= 999_999_999 else {
                return nil
            }

            return value
        }
    }
}


// MARK: - Deep diagnostics (gộp từ TPIOSSaleRuntimeDiagnostics.swift,
// công cụ nghiên cứu runtime — chưa nối vào nút nào trong UI, gọi tay khi
// cần đào sâu thêm cấu trúc 1 màn hình Shopee cụ thể)

private enum TPIOSSaleRuntimeDiagnostics {

    static func inspectCurrentApp() -> String {
        let windows = visibleAppWindows()

        guard windows.isEmpty == false else {
            return "SALE DIAGNOSTIC\n\nKhông tìm thấy window ứng dụng."
        }

        var output = "SALE DEEP DIAGNOSTIC\n\n"
        output += "Windows: \(windows.count)\n"

        var webViews: [WKWebView] = []
        var scrollViews: [UIScrollView] = []
        var controllerNames = Set<String>()
        var matchedNativeClasses = Set<String>()
        var matchedSelectors = Set<String>()

        let keywords = [
            "sale", "product", "item", "price", "voucher", "coupon",
            "discount", "promotion", "promo", "shipping", "freeship",
            "refresh", "reload", "home", "detail", "cart", "checkout",
            "shopee"
        ]

        for (index, window) in windows.enumerated() {
            let rootName = window.rootViewController.map {
                NSStringFromClass(type(of: $0))
            } ?? "<nil>"

            output += "\nWINDOW[\(index)] class=\(NSStringFromClass(type(of: window)))\n"
            output += "Root=\(rootName)\n"

            collectControllers(
                from: window.rootViewController,
                into: &controllerNames
            )

            collectRuntimeMatches(
                from: window,
                keywords: keywords,
                classes: &matchedNativeClasses,
                selectors: &matchedSelectors
            )

            collectViews(
                from: window,
                webViews: &webViews,
                scrollViews: &scrollViews
            )
        }

        output += "\n=== CONTROLLERS ===\n"
        if controllerNames.isEmpty {
            output += "Không phát hiện.\n"
        } else {
            for name in controllerNames.sorted().prefix(60) {
                output += "\(name)\n"
            }
        }

        output += "\n=== NATIVE MATCHES ===\n"
        if matchedNativeClasses.isEmpty {
            output += "Không có class khớp từ khóa.\n"
        } else {
            for name in matchedNativeClasses.sorted().prefix(80) {
                output += "\(name)\n"
            }
        }

        output += "\n=== SELECTOR MATCHES ===\n"
        if matchedSelectors.isEmpty {
            output += "Không có selector khớp từ khóa.\n"
        } else {
            for name in matchedSelectors.sorted().prefix(120) {
                output += "\(name)\n"
            }
        }

        output += "\n=== WEBVIEWS: \(webViews.count) ===\n"
        if webViews.isEmpty {
            output += "Không có WKWebView.\n"
        } else {
            for (index, webView) in webViews.prefix(10).enumerated() {
                let url = webView.url?.absoluteString ?? "<nil>"
                let title = webView.title ?? "<nil>"
                output += "WEBVIEW[\(index)] url=\(url) title=\(title)\n"

                inspectWebView(
                    webView,
                    index: index
                )
            }
        }

        output += "\n=== SCROLLVIEWS: \(scrollViews.count) ===\n"
        if scrollViews.isEmpty {
            output += "Không phát hiện UIScrollView.\n"
        } else {
            for (index, scrollView) in scrollViews.prefix(40).enumerated() {
                let className = NSStringFromClass(type(of: scrollView))
                let delegate = scrollView.delegate.map {
                    NSStringFromClass(type(of: $0))
                } ?? "<nil>"

                let refresh = scrollView.refreshControl.map {
                    NSStringFromClass(type(of: $0))
                } ?? "<nil>"

                let frame = scrollView.convert(scrollView.bounds, to: nil)

                output += """
                SCROLL[\(index)] class=\(className)
                delegate=\(delegate)
                refresh=\(refresh)
                frame=\(frame)
                content=\(scrollView.contentSize)
                """

                output += "\n"
            }
        }

        output += """

        === KẾT LUẬN ===
        """

        if !webViews.isEmpty {
            output += "\nCó WKWebView. Bước tiếp theo là đọc DOM có kiểm soát để xác định product/price/voucher và endpoint tài nguyên của màn hình hiện tại."
        } else if !scrollViews.isEmpty {
            output += "\nKhông có WKWebView. Bước tiếp theo là đào sâu Native/RN: class hierarchy, selector refresh/data, delegate và component chứa text/giá/voucher."
        } else {
            output += "\nChưa xác định được tầng render."
        }

        return output
    }

    private static func visibleAppWindows() -> [UIWindow] {
        let scenes = UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }

        var windows: [UIWindow] = []

        for scene in scenes where scene.activationState != .unattached {
            for window in scene.windows {
                guard window.isHidden == false,
                      window.alpha > 0.01,
                      window.bounds.width > 0,
                      window.bounds.height > 0 else {
                    continue
                }

                let className = NSStringFromClass(type(of: window))
                if className.contains("TPIOS") {
                    continue
                }

                windows.append(window)
            }
        }

        return windows
    }

    private static func collectControllers(
        from controller: UIViewController?,
        into names: inout Set<String>
    ) {
        guard let controller else {
            return
        }

        names.insert(NSStringFromClass(type(of: controller)))

        if let presented = controller.presentedViewController {
            collectControllers(from: presented, into: &names)
        }

        for child in controller.children {
            collectControllers(from: child, into: &names)
        }

        if let navigation = controller as? UINavigationController {
            for child in navigation.viewControllers {
                collectControllers(from: child, into: &names)
            }
        }

        if let tab = controller as? UITabBarController {
            for child in tab.viewControllers ?? [] {
                collectControllers(from: child, into: &names)
            }
        }
    }

    private static func collectViews(
        from view: UIView,
        webViews: inout [WKWebView],
        scrollViews: inout [UIScrollView]
    ) {
        if let webView = view as? WKWebView {
            webViews.append(webView)
        }

        if let scrollView = view as? UIScrollView {
            scrollViews.append(scrollView)
        }

        for child in view.subviews {
            collectViews(
                from: child,
                webViews: &webViews,
                scrollViews: &scrollViews
            )
        }
    }

    private static func collectRuntimeMatches(
        from view: UIView,
        keywords: [String],
        classes: inout Set<String>,
        selectors: inout Set<String>
    ) {
        let className = NSStringFromClass(type(of: view))
        let lowerClass = className.lowercased()

        if keywords.contains(where: { lowerClass.contains($0) }) {
            classes.insert(className)
        }

        var methodCount: UInt32 = 0

        if let methods = class_copyMethodList(type(of: view), &methodCount) {
            defer {
                free(methods)
            }

            for index in 0..<Int(methodCount) {
                let selector = method_getName(methods[index])
                let selectorName = NSStringFromSelector(selector)
                let lowerSelector = selectorName.lowercased()

                if keywords.contains(where: { lowerSelector.contains($0) }) {
                    selectors.insert("\(className).\(selectorName)")
                }
            }
        }

        for child in view.subviews {
            collectRuntimeMatches(
                from: child,
                keywords: keywords,
                classes: &classes,
                selectors: &selectors
            )
        }
    }

    private static func inspectWebView(
        _ webView: WKWebView,
        index: Int
    ) {
        let script = """
        (function() {
            const terms = [
                "price", "voucher", "coupon", "discount",
                "promotion", "promo", "freeship", "shipping",
                "product", "item", "sale", "shop"
            ];

            function clean(value) {
                return String(value || "")
                    .replace(/\\s+/g, " ")
                    .trim()
                    .slice(0, 180);
            }

            const nodes = Array.from(
                document.querySelectorAll(
                    "body *"
                )
            ).filter(el => {
                const text = clean(el.innerText);
                if (!text) return false;
                const lower = text.toLowerCase();
                return terms.some(term => lower.includes(term));
            }).slice(0, 80).map(el => ({
                tag: el.tagName,
                id: clean(el.id),
                cls: typeof el.className === "string" ? clean(el.className) : "",
                text: clean(el.innerText)
            }));

            const resources = performance
                .getEntriesByType("resource")
                .map(x => x.name)
                .filter(Boolean)
                .slice(-100);

            return JSON.stringify({
                href: location.href,
                title: document.title,
                htmlLength: document.documentElement
                    ? document.documentElement.outerHTML.length
                    : 0,
                bodyTextLength: document.body
                    ? document.body.innerText.length
                    : 0,
                nodes: nodes,
                resources: resources
            });
        })();
        """

        webView.evaluateJavaScript(script) { result, error in
            if let error {
                TPIOSLog.shared.log(
                    "SaleDeep: WEBVIEW[\(index)] JS ERROR \(error.localizedDescription)"
                )
                return
            }

            guard let value = result as? String else {
                TPIOSLog.shared.log(
                    "SaleDeep: WEBVIEW[\(index)] JS result không phải String"
                )
                return
            }

            TPIOSLog.shared.log(
                "SaleDeep: WEBVIEW[\(index)] DOM \(value)"
            )
        }
    }
}
