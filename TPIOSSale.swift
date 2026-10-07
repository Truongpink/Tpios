import UIKit

// Săn sale Shopee: mỗi lần quét = 1 "ảnh chụp" sản phẩm (giá + mã giảm giá)
// tại thời điểm đó, lưu lại để so sánh các lần với nhau.
//   - TPIOSSale.swift         : giao diện + luồng (file này)
//   - TPIOSSaleScanner.swift  : đọc chữ trên màn hình Shopee
//   - TPIOSSaleData.swift     : lưu trữ, mã giảm giá (đọc + tính), định dạng
// Chạm giữ nút "Quét" = dump chữ màn hình vào log (tiền tố SaleDump:).
final class TPIOSSale: UIView, UIGestureRecognizerDelegate {

    var onBack: (() -> Void)?
    var onClose: (() -> Void)?

    private struct Block {
        let view: UIView
        let top: CGFloat
        let height: (CGFloat) -> CGFloat
    }

    private struct Draft {
        var names: [String]
        var nameIndex = 0
        var prices: [Double]
        var priceIndex = 0
        var vouchers: [TPIOSSaleVoucher]
    }

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
    private let scanButton = UIButton(type: .system)
    private let scanCaption = UILabel()
    private let resizeHandle = UILabel()

    private var blocks: [Block] = []
    private var selectedID: UUID?
    private var expandedIndex: Int?
    private var confirmDelete = false
    private var status = ""
    private var draft: Draft?
    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero
    private var pickOverlay: UIView?
    private weak var pickCancel: UIButton?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Khung

    private func setup() {
        TPIOSPanelStyle.applyGlassBackground(to: self, cornerRadius: 24)

        headerView.backgroundColor = UIColor(red: 0.075, green: 0.085, blue: 0.105, alpha: 1)
        headerView.layer.cornerRadius = 24
        headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(headerView)

        styleHeaderButton(backButton, "‹", size: 30, action: #selector(backTapped))
        styleHeaderButton(closeButton, "×", size: 28, action: #selector(closeTapped))
        headerView.addSubview(backButton)
        headerView.addSubview(closeButton)

        titleLabel.text = "SALE"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)

        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)
        scrollView.addSubview(contentView)

        let config = UIImage.SymbolConfiguration(pointSize: 23, weight: .semibold)
        scanButton.setImage(UIImage(systemName: "text.viewfinder", withConfiguration: config), for: .normal)
        scanButton.tintColor = .white
        TPIOSPanelStyle.applyGradientFill(
            to: scanButton,
            colors: [
                UIColor(red: 0.68, green: 0.47, blue: 1.00, alpha: 1),
                UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)
            ],
            cornerRadius: 18
        )
        scanButton.layer.cornerRadius = 18
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        if let imageView = scanButton.imageView {
            scanButton.bringSubviewToFront(imageView)
        }
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(dumpTapped(_:)))
        longPress.minimumPressDuration = 0.7
        scanButton.addGestureRecognizer(longPress)
        contentView.addSubview(scanButton)

        scanCaption.text = "Quét"
        scanCaption.textColor = .white
        scanCaption.font = .systemFont(ofSize: 12.5, weight: .semibold)
        scanCaption.textAlignment = .center
        contentView.addSubview(scanCaption)

        resizeHandle.text = "↘"
        resizeHandle.textColor = UIColor.white.withAlphaComponent(0.65)
        resizeHandle.font = .systemFont(ofSize: 20)
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

        render()
    }

    private func styleHeaderButton(_ button: UIButton, _ title: String, size: CGFloat, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: size)
        button.addTarget(self, action: action, for: .touchUpInside)
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

        default:
            break
        }
    }

    @objc private func movePanned(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview,
              gesture.state == .began || gesture.state == .changed else {
            return
        }

        let delta = gesture.translation(in: parent)
        var newFrame = frame
        newFrame.origin.x = max(0, min(newFrame.origin.x + delta.x, max(0, parent.bounds.width - newFrame.width)))
        newFrame.origin.y = max(0, min(newFrame.origin.y + delta.y, max(0, parent.bounds.height - newFrame.height)))

        frame = newFrame
        gesture.setTranslation(.zero, in: parent)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        backButton.frame = CGRect(x: 4, y: 3, width: 40, height: 38)
        titleLabel.frame = CGRect(x: 46, y: 0, width: max(0, bounds.width - 92), height: headerHeight)
        closeButton.frame = CGRect(x: bounds.width - 46, y: 4, width: 42, height: 36)

        scrollView.frame = CGRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))

        let icon: CGFloat = 62
        scanButton.frame = CGRect(x: (bounds.width - icon) / 2, y: 8, width: icon, height: icon)
        TPIOSPanelStyle.syncFrames(in: scanButton)
        scanCaption.frame = CGRect(x: (bounds.width - icon - 24) / 2, y: 8 + icon + 5, width: icon + 24, height: 18)

        let width = max(0, bounds.width - 28)
        var y: CGFloat = 8 + icon + 5 + 18 + 6

        for block in blocks {
            y += block.top
            let height = block.height(width)
            block.view.frame = CGRect(x: 14, y: y, width: width, height: height)
            y += height
        }

        y += 36
        contentView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: y)
        scrollView.contentSize = contentView.bounds.size

        resizeHandle.frame = CGRect(x: bounds.width - handleSize, y: bounds.height - handleSize, width: handleSize, height: handleSize)
    }

    private func setBlocks(_ new: [Block]) {
        blocks.forEach { $0.view.removeFromSuperview() }
        blocks = new
        new.forEach { contentView.addSubview($0.view) }
        setNeedsLayout()
    }

    // MARK: Dựng giao diện

    private func render() {
        let products = TPIOSSaleStore.shared.load()

        if let id = selectedID, products.contains(where: { $0.id == id }) == false {
            selectedID = nil
        }

        var list: [Block] = []

        if status.isEmpty == false {
            list.append(text(status, top: 4, alpha: 0.95))
        }

        if let current = draft {
            list.append(contentsOf: draftBlocks(current))
        }

        if let id = selectedID, let product = products.first(where: { $0.id == id }) {
            list.append(contentsOf: detailBlocks(product))
        } else {
            list.append(contentsOf: listBlocks(products))
        }

        setBlocks(list)
    }

    private func text(
        _ string: String,
        top: CGFloat = 6,
        size: CGFloat = 12.5,
        weight: UIFont.Weight = .regular,
        alpha: CGFloat = 0.82,
        mono: Bool = false
    ) -> Block {
        let label = UILabel()
        label.text = string
        label.numberOfLines = 0
        label.textColor = UIColor.white.withAlphaComponent(alpha)
        label.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        return autoBlock(label, top: top)
    }

    private func autoBlock(_ label: UILabel, top: CGFloat) -> Block {
        Block(view: label, top: top, height: { width in
            ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        })
    }

    private func fixed(_ view: UIView, _ height: CGFloat, top: CGFloat) -> Block {
        Block(view: view, top: top, height: { _ in height })
    }

    private func rowButton(_ title: String, selected: Bool, tag: Int, action: Selector) -> UIButton {
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

    private func pill(_ title: String, _ color: UIColor, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .semibold)
        button.backgroundColor = color
        button.layer.cornerRadius = 10
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func attributed(_ parts: [(String, UIColor)], size: CGFloat = 11.5) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let out = NSMutableAttributedString()

        for (string, color) in parts {
            out.append(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]))
        }

        return out
    }

    // MARK: Danh sách sản phẩm

    private func listBlocks(_ products: [TPIOSWatchedSale]) -> [Block] {
        var b: [Block] = [text("SẢN PHẨM ĐÃ THEO DÕI (\(products.count))", top: 14, weight: .semibold)]

        if products.isEmpty {
            b.append(text("Chưa có sản phẩm. Mở giỏ hàng Shopee, bấm Quét rồi chạm vào sản phẩm.", size: 12, alpha: 0.6))
        }

        let sorted = products.sorted {
            ($0.lastCheckedAt ?? $0.createdAt) > ($1.lastCheckedAt ?? $1.createdAt)
        }

        for product in sorted {
            let row = TPIOSSaleProductRow(frame: .zero)
            row.configure(name: product.title, info: productInfo(product))
            row.accessibilityIdentifier = product.id.uuidString
            row.addTarget(self, action: #selector(productTapped(_:)), for: .touchUpInside)
            b.append(fixed(row, 56, top: 6))
        }

        return b
    }

    private func productInfo(_ product: TPIOSWatchedSale) -> NSAttributedString {
        let white = UIColor.white.withAlphaComponent(0.85)
        let prices = product.snapshots.compactMap { $0.effectivePrice }

        guard let last = prices.last else {
            return attributed([("chưa có giá", white)])
        }

        var parts: [(String, UIColor)] = [(TPIOSSaleFormat.money(last), white)]

        if prices.count >= 2 {
            let delta = TPIOSSaleFormat.delta(current: last, previous: prices[prices.count - 2])
            parts.append(("  " + delta.text, delta.color))
        }

        if let low = prices.min() {
            parts.append(("  · rẻ nhất " + TPIOSSaleFormat.money(low), white.withAlphaComponent(0.6)))
        }

        return attributed(parts)
    }

    // MARK: Chi tiết sản phẩm = các lần quét

    private func detailBlocks(_ product: TPIOSWatchedSale) -> [Block] {
        var b: [Block] = [text(product.title, top: 16, size: 14, weight: .bold, alpha: 1)]

        var valued: [(index: Int, price: Double)] = []
        for (index, snapshot) in product.snapshots.enumerated() {
            if let price = snapshot.effectivePrice {
                valued.append((index, price))
            }
        }

        let cheapest = valued.min(by: { $0.price < $1.price })

        var summary = "Đã quét \(product.snapshots.count) lần"
        if let cheapest {
            summary += "\nRẻ nhất: " + TPIOSSaleFormat.money(cheapest.price) +
                " (" + TPIOSSaleFormat.date(product.snapshots[cheapest.index].timestamp) + ")"

            if let last = valued.last, last.index != cheapest.index {
                summary += "\nLần gần nhất cao hơn " + TPIOSSaleFormat.money(last.price - cheapest.price)
            } else if valued.count >= 2 {
                summary += "\nLần gần nhất đang là RẺ NHẤT"
            }
        }
        b.append(text(summary, top: 6, size: 12, alpha: 0.9, mono: true))

        b.append(text("CÁC LẦN QUÉT (chạm để xem mã)", top: 14, weight: .semibold))

        for (index, snapshot) in Array(product.snapshots.enumerated()).reversed().prefix(20) {
            let previous: Double? = index > 0 ? product.snapshots[index - 1].effectivePrice : nil
            let isCheapest = cheapest?.index == index

            let row = rowButton("", selected: expandedIndex == index, tag: index, action: #selector(snapshotTapped(_:)))
            row.setAttributedTitle(snapshotTitle(snapshot, previous: previous, cheapest: isCheapest), for: .normal)
            b.append(fixed(row, 34, top: 4))

            if expandedIndex == index {
                b.append(contentsOf: expandedBlocks(snapshot, index: index))
            }
        }

        let deleteTitle = confirmDelete ? "Chạm lần nữa để xoá sản phẩm" : "Xoá sản phẩm này"
        b.append(fixed(pill(deleteTitle, UIColor(red: 0.70, green: 0.15, blue: 0.12, alpha: 0.9), #selector(deleteProductTapped)), 38, top: 18))

        return b
    }

    private func snapshotTitle(_ snapshot: TPIOSSaleSnapshot, previous: Double?, cheapest: Bool) -> NSAttributedString {
        let gold = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        let white = UIColor.white.withAlphaComponent(0.9)
        let priceText = snapshot.effectivePrice.map { TPIOSSaleFormat.money($0) } ?? "-"

        var parts: [(String, UIColor)] = [(
            "  " + (cheapest ? "★ " : "") + TPIOSSaleFormat.date(snapshot.timestamp) + "  " + priceText,
            cheapest ? gold : white
        )]

        if let price = snapshot.effectivePrice, let previous {
            let delta = TPIOSSaleFormat.delta(current: price, previous: previous)
            parts.append(("  " + delta.text, delta.color))
        }

        return attributed(parts)
    }

    private func expandedBlocks(_ snapshot: TPIOSSaleSnapshot, index: Int) -> [Block] {
        var lines = [
            "Giá niêm yết: " + (snapshot.price.map { TPIOSSaleFormat.money($0) } ?? "-"),
            "Giá sau mã:   " + (snapshot.effectivePrice.map { TPIOSSaleFormat.money($0) } ?? "-")
        ]

        let vouchers = snapshot.voucherList

        if vouchers.isEmpty {
            lines.append("Không có mã giảm giá lúc đó.")
        } else {
            lines.append("Mã lúc đó:")
            for voucher in vouchers {
                lines.append("  • " + TPIOSSaleKind.name(voucher.kind) + ": " + voucher.title)
            }
        }

        let delete = pill("Xoá lần quét này", UIColor.white.withAlphaComponent(0.12), #selector(deleteSnapshotTapped(_:)))
        delete.tag = index

        return [
            text(lines.joined(separator: "\n"), top: 4, size: 11.5, alpha: 0.85, mono: true),
            fixed(delete, 32, top: 6)
        ]
    }

    // MARK: Kết quả quét đang chờ lưu

    private func draftBlocks(_ d: Draft) -> [Block] {
        var b: [Block] = [text("Sản phẩm (chạm để đổi sang tên khác):", top: 12, weight: .semibold)]

        let name = d.names.indices.contains(d.nameIndex) ? d.names[d.nameIndex] : "(không đọc được tên, sẽ lưu tên tạm)"
        b.append(fixed(rowButton(name, selected: true, tag: 0, action: #selector(nameTapped)), 36, top: 4))

        b.append(text("Giá (chạm đúng giá sản phẩm):", top: 10, weight: .semibold))

        for (index, price) in d.prices.prefix(6).enumerated() {
            let row = rowButton(TPIOSSaleFormat.money(price), selected: index == d.priceIndex, tag: index, action: #selector(priceTapped(_:)))
            b.append(fixed(row, 32, top: 4))
        }

        b.append(text("Mã giảm giá đọc được (\(d.vouchers.count)):", top: 12, weight: .semibold))

        if d.vouchers.isEmpty {
            b.append(text("Không thấy mã nào. Shop không có mã thì bỏ qua. Muốn thêm mã Shopee / free ship: mở màn đó rồi bấm + Quét mã.", top: 4, size: 11.5, alpha: 0.6))
        }

        for (index, voucher) in d.vouchers.enumerated() {
            b.append(fixed(voucherRow(voucher, tag: index), 38, top: 6))
        }

        if d.prices.indices.contains(d.priceIndex) {
            let result = TPIOSSaleVoucherMath.best(vouchers: d.vouchers, price: d.prices[d.priceIndex])
            var line = "Giá sau mã (ước tính): " + TPIOSSaleFormat.money(result.finalPrice)

            if result.freeshipAmount > 0 {
                line += "\nFree ship giảm thêm: -" + TPIOSSaleFormat.money(result.freeshipAmount)
            }

            b.append(text(line, top: 10, weight: .semibold, alpha: 0.95))
        }

        let add = pill("+ Quét mã", UIColor(red: 0.85, green: 0.35, blue: 0.15, alpha: 1), #selector(addVouchersTapped))
        let save = pill("Lưu", UIColor(red: 0.10, green: 0.55, blue: 0.40, alpha: 1), #selector(saveTapped))
        let cancel = pill("Huỷ", UIColor.white.withAlphaComponent(0.12), #selector(cancelDraftTapped))
        b.append(fixed(TPIOSSaleButtonRow(buttons: [add, save, cancel]), 38, top: 12))

        return b
    }

    private func voucherRow(_ voucher: TPIOSSaleVoucher, tag: Int) -> UIView {
        let row = UIView()
        row.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        row.layer.cornerRadius = 8

        let label = UILabel()
        label.text = voucher.title
        label.textColor = .white
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.lineBreakMode = .byTruncatingTail

        let kind = UIButton(type: .system)
        kind.setTitle(TPIOSSaleKind.name(voucher.kind), for: .normal)
        kind.setTitleColor(.white, for: .normal)
        kind.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        kind.backgroundColor = TPIOSSaleKind.color(voucher.kind)
        kind.layer.cornerRadius = 8
        kind.tag = tag
        kind.addTarget(self, action: #selector(draftKindTapped(_:)), for: .touchUpInside)

        let trash = UIButton(type: .system)
        trash.setImage(UIImage(systemName: "trash"), for: .normal)
        trash.tintColor = UIColor.systemRed.withAlphaComponent(0.85)
        trash.tag = tag
        trash.addTarget(self, action: #selector(draftVoucherDeleteTapped(_:)), for: .touchUpInside)

        [label, kind, trash].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: kind.leadingAnchor, constant: -6),

            kind.trailingAnchor.constraint(equalTo: trash.leadingAnchor, constant: -4),
            kind.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            kind.widthAnchor.constraint(equalToConstant: 46),
            kind.heightAnchor.constraint(equalToConstant: 24),

            trash.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
            trash.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            trash.widthAnchor.constraint(equalToConstant: 30)
        ])

        return row
    }

    // MARK: Hành động

    @objc private func productTapped(_ sender: UIButton) {
        guard let idString = sender.accessibilityIdentifier,
              let id = UUID(uuidString: idString) else {
            return
        }

        selectedID = id
        expandedIndex = nil
        confirmDelete = false
        status = ""
        render()
        scrollView.setContentOffset(.zero, animated: false)
    }

    @objc private func snapshotTapped(_ sender: UIButton) {
        expandedIndex = expandedIndex == sender.tag ? nil : sender.tag
        render()
    }

    @objc private func deleteSnapshotTapped(_ sender: UIButton) {
        guard let id = selectedID else { return }

        TPIOSSaleStore.shared.deleteSnapshot(productID: id, index: sender.tag)
        expandedIndex = nil
        render()
    }

    @objc private func deleteProductTapped() {
        guard let id = selectedID else { return }

        if confirmDelete == false {
            confirmDelete = true
            render()
            return
        }

        TPIOSSaleStore.shared.deleteProduct(id)
        confirmDelete = false
        selectedID = nil
        status = "Đã xoá sản phẩm."
        render()
    }

    @objc private func nameTapped() {
        guard var d = draft, d.names.isEmpty == false else { return }

        d.nameIndex = (d.nameIndex + 1) % d.names.count
        draft = d
        render()
    }

    @objc private func priceTapped(_ sender: UIButton) {
        draft?.priceIndex = sender.tag
        render()
    }

    @objc private func draftKindTapped(_ sender: UIButton) {
        guard var d = draft, d.vouchers.indices.contains(sender.tag) else { return }

        d.vouchers[sender.tag].kind = TPIOSSaleKind.next(d.vouchers[sender.tag].kind)
        draft = d
        render()
    }

    @objc private func draftVoucherDeleteTapped(_ sender: UIButton) {
        guard var d = draft, d.vouchers.indices.contains(sender.tag) else { return }

        d.vouchers.remove(at: sender.tag)
        draft = d
        render()
    }

    @objc private func cancelDraftTapped() {
        draft = nil
        render()
    }

    // Đọc thêm mã giảm giá của màn đang hiển thị (vd màn kho mã) vào bản nháp.
    @objc private func addVouchersTapped() {
        guard var d = draft,
              let root = TPIOSSaleScanner.visibleAppRoot(excluding: window) else {
            return
        }

        let found = TPIOSSaleScanner.vouchers(in: TPIOSSaleScanner.collectItems(in: root), near: nil)
        var added = 0

        for voucher in found where d.vouchers.contains(where: { $0.sameAs(voucher) }) == false {
            d.vouchers.append(voucher)
            added += 1
        }

        draft = d
        status = added > 0 ? "Thêm \(added) mã từ màn hiện tại." : "Màn hiện tại không có mã mới."
        render()
    }

    @objc private func saveTapped() {
        guard let d = draft, d.prices.indices.contains(d.priceIndex) else { return }

        let price = d.prices[d.priceIndex]
        let name = d.names.indices.contains(d.nameIndex)
            ? d.names[d.nameIndex]
            : "SP không rõ tên " + TPIOSSaleFormat.date(Date())
        let final = TPIOSSaleVoucherMath.best(vouchers: d.vouchers, price: price).finalPrice

        let result = TPIOSSaleStore.shared.record(name: name, price: price, finalPrice: final, vouchers: d.vouchers)

        var message = "Đã lưu " + TPIOSSaleFormat.money(price)

        if d.vouchers.isEmpty == false {
            message += ", sau mã " + TPIOSSaleFormat.money(final)
        }

        if let previous = result.previous {
            message += "\n" + TPIOSSaleFormat.delta(current: final, previous: previous).text + " so với lần trước."
        } else {
            message += " (sản phẩm mới)"
        }

        draft = nil
        selectedID = result.product.id
        expandedIndex = nil
        confirmDelete = false
        status = message
        render()
        scrollView.setContentOffset(.zero, animated: false)

        TPIOSLog.shared.log("Sale: lưu \(Int(price)) sau mã \(Int(final)), \(d.vouchers.count) mã")
    }

    @objc private func backTapped() {
        if draft != nil {
            draft = nil
        } else if selectedID != nil {
            selectedID = nil
            confirmDelete = false
            status = ""
        } else {
            onBack?()
            return
        }

        render()
    }

    @objc private func closeTapped() {
        onClose?()
    }

    // MARK: Chạm để quét

    @objc private func scanTapped() {
        endEditing(true)

        guard let hostWindow = window else { return }

        isHidden = true

        let overlay = UIView(frame: hostWindow.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.001)

        let safeTop = hostWindow.safeAreaInsets.top

        let hint = UILabel()
        hint.text = "Chạm vào sản phẩm cần quét (tên hoặc giá)"
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        hint.layer.cornerRadius = 10
        hint.clipsToBounds = true
        hint.frame = CGRect(x: 20, y: safeTop + 14, width: hostWindow.bounds.width - 100, height: 44)
        overlay.addSubview(hint)

        let cancel = UIButton(type: .system)
        cancel.setTitle("Huỷ", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        cancel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        cancel.layer.cornerRadius = 8
        cancel.frame = CGRect(x: hostWindow.bounds.width - 72, y: safeTop + 14, width: 56, height: 44)
        cancel.addTarget(self, action: #selector(cancelPick), for: .touchUpInside)
        overlay.addSubview(cancel)
        pickCancel = cancel

        let tap = UITapGestureRecognizer(target: self, action: #selector(picked(_:)))
        tap.delegate = self
        overlay.addGestureRecognizer(tap)

        hostWindow.addSubview(overlay)
        pickOverlay = overlay
    }

    private func finishPick() {
        pickOverlay?.removeFromSuperview()
        pickOverlay = nil
        pickCancel = nil
        isHidden = false
    }

    @objc private func cancelPick() {
        finishPick()
    }

    @objc private func picked(_ gesture: UITapGestureRecognizer) {
        guard let overlay = pickOverlay else { return }

        let point = gesture.location(in: overlay)
        finishPick()
        readScreen(at: point)
    }

    private func readScreen(at point: CGPoint) {
        guard let root = TPIOSSaleScanner.visibleAppRoot(excluding: window) else {
            status = "Không tìm thấy màn hình app để quét."
            render()
            return
        }

        let items = TPIOSSaleScanner.collectItems(in: root)

        var prices = TPIOSSaleScanner.prices(in: items, near: point, radius: 140)
        if prices.isEmpty {
            prices = TPIOSSaleScanner.prices(in: items, near: nil, radius: 0)
        }

        guard prices.isEmpty == false else {
            status = "Không đọc được giá nào. Mở giỏ hàng / trang sản phẩm rồi quét lại."
            render()
            return
        }

        var names = TPIOSSaleScanner.nameCandidates(in: items, near: point, radius: 260)
        if names.isEmpty {
            names = TPIOSSaleScanner.nameCandidates(in: items, near: nil, radius: 0)
        }

        let vouchers = TPIOSSaleScanner.vouchers(in: items, near: point)

        draft = Draft(names: names, prices: prices, vouchers: vouchers)
        status = ""
        render()
        scrollView.setContentOffset(.zero, animated: false)

        TPIOSLog.shared.log("Sale: quét, \(prices.count) giá, \(names.count) tên, \(vouchers.count) mã")
    }

    // Nghiên cứu: chạm giữ nút Quét → ghi mọi chữ đang hiện (kèm loại view,
    // vị trí) vào log với tiền tố "SaleDump:".
    @objc private func dumpTapped(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }

        guard let root = TPIOSSaleScanner.visibleAppRoot(excluding: window) else {
            status = "Không tìm thấy màn hình app để dump."
            render()
            return
        }

        var controllers: [String] = []
        var responder: UIResponder? = root

        while let current = responder, controllers.count < 6 {
            if let controller = current as? UIViewController {
                controllers.append(NSStringFromClass(type(of: controller)))
            }
            responder = current.next
        }

        let lines = TPIOSSaleScanner.dumpLines(in: root)

        TPIOSLog.shared.log("SaleDump: ===== \(lines.count) dòng | controller: " + controllers.joined(separator: " -> ") + " =====")

        for line in lines.prefix(250) {
            TPIOSLog.shared.log("SaleDump: " + line)
        }

        status = "Đã dump \(min(lines.count, 250)) dòng vào log. Mở Xem log, gõ SaleDump: vào ô lọc."
        render()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view === backButton ||
           touch.view === closeButton ||
           touch.view === resizeHandle ||
           touch.view === pickCancel {
            return false
        }

        return true
    }
}


// MARK: - View phụ

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
            button.frame = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: bounds.height)
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
