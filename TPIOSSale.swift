import UIKit
import WebKit
import ObjectiveC.runtime

// Gộp 3 file (TPIOSSale + TPIOSSaleScanner + TPIOSSaleRuntimeDiagnostics)
// thành 1 file duy nhất theo yêu cầu, và sửa đúng phần đã chốt:
//
// - Bỏ TPIOSNetworkLog.shared.recentSaleRequestURLs() — hàm này không tồn
//   tại, bản cũ không build được.
// - "KT ngay" trước đây không làm gì thật (giá/finalPrice luôn nil). Giờ
//   đổi thành "Quét giá" — chạm vào đúng vị trí sản phẩm trên màn hình
//   Shopee (hỗ trợ cả giỏ hàng nhiều sản phẩm), chỉ quét số tiền nằm GẦN
//   điểm chạm đó (bán kính ~140pt) thay vì quét toàn màn hình — tránh lẫn
//   giá của sản phẩm khác. Nếu không có gì gần điểm chạm, tự nới ra quét
//   toàn màn hình và báo rõ cho biết.
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

    private let linkField = UITextField()
    private let addButton = UIButton(type: .system)
    private let analyzeButton = UIButton(type: .system)
    private let addLabel = UILabel()
    private let analyzeLabel = UILabel()
    private let resultLabel = UILabel()
    private let scanStack = UIStackView()
    private let historyLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let resizeHandle = UILabel()

    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero
    private var selectedProductID: UUID?
    private var lastScanValues: [TPIOSSaleScanValue] = []

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
        setupContent()
        setupResize()
        setupMove()
        refreshList()
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

    private func setupContent() {
        addSubview(scrollView)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.addSubview(contentView)

        let linkTitle = makeLabel("Link sản phẩm Shopee")
        contentView.addSubview(linkTitle)

        linkField.textColor = .white
        linkField.tintColor = .white
        linkField.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        linkField.layer.cornerRadius = 10
        linkField.layer.borderWidth = 1
        linkField.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        linkField.font = .systemFont(ofSize: 14)
        linkField.placeholder = "Dán link sản phẩm vào đây"
        linkField.attributedPlaceholder = NSAttributedString(
            string: "Dán link sản phẩm vào đây",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.3)]
        )
        linkField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        linkField.leftViewMode = .always
        let clearButton = UIButton(type: .system)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = UIColor.white.withAlphaComponent(0.42)
        clearButton.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        clearButton.addTarget(self, action: #selector(clearLinkTapped), for: .touchUpInside)
        linkField.rightView = clearButton
        linkField.rightViewMode = .always
        contentView.addSubview(linkField)

        configureIconButton(addButton, icon: "plus", action: #selector(addProductTapped))
        configureIconButton(analyzeButton, icon: "text.viewfinder", action: #selector(analyzeTapped))
        configureCaption(addLabel, text: "Thêm SP")
        configureCaption(analyzeLabel, text: "Quét giá")
        contentView.addSubview(addButton)
        contentView.addSubview(addLabel)
        contentView.addSubview(analyzeButton)
        contentView.addSubview(analyzeLabel)

        resultLabel.textColor = .white
        resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultLabel.numberOfLines = 0
        contentView.addSubview(resultLabel)

        scanStack.axis = .vertical
        scanStack.spacing = 6
        contentView.addSubview(scanStack)

        historyLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        historyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        historyLabel.numberOfLines = 0
        contentView.addSubview(historyLabel)

        let note = makeLabel(
            "Quét giá đọc text đang hiển thị trên màn hình Shopee (gần điểm bạn chạm), không gọi API — bạn tự chạm chọn đúng giá."
        )
        note.numberOfLines = 0
        note.textColor = UIColor.white.withAlphaComponent(0.48)
        contentView.addSubview(note)
        note.tag = 999
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor.white.withAlphaComponent(0.82)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func configureIconButton(_ button: UIButton, icon: String, action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 23, weight: .semibold)
        button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
        button.tintColor = .white
        TPIOSPanelStyle.applyGradientFill(
            to: button,
            colors: [
                UIColor(red: 0.68, green: 0.47, blue: 1.00, alpha: 1),
                UIColor(red: 0.31, green: 0.20, blue: 0.82, alpha: 1)
            ],
            cornerRadius: 18
        )
        button.layer.cornerRadius = 18
        button.addTarget(self, action: action, for: .touchUpInside)
        if let imageView = button.imageView {
            button.bringSubviewToFront(imageView)
        }
    }

    private func configureCaption(_ label: UILabel, text: String) {
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
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
        var y: CGFloat = 14

        if let linkTitle = contentView.subviews.first(where: {
            ($0 as? UILabel)?.text == "Link sản phẩm Shopee"
        }) {
            linkTitle.frame = CGRect(x: x, y: y, width: width, height: 20)
            y += 24
        }

        linkField.frame = CGRect(x: x, y: y, width: width, height: 42)
        y += 50

        let scale = min(width / 360, max(0.75, bounds.height / 560))
        let gridGap = max(22, min(34, 26 * scale))
        let iconSize = min(74, max(54, (width - gridGap) / 2))
        let gridWidth = iconSize * 2 + gridGap
        let gridX = x + max(0, (width - gridWidth) / 2)
        let captionGap = max(7, 8 * scale)
        let captionHeight = max(18, 19 * scale)

        addButton.frame = CGRect(x: gridX, y: y, width: iconSize, height: iconSize)
        addLabel.frame = CGRect(x: gridX, y: y + iconSize + captionGap, width: iconSize, height: captionHeight)
        analyzeButton.frame = CGRect(x: gridX + iconSize + gridGap, y: y, width: iconSize, height: iconSize)
        analyzeLabel.frame = CGRect(x: gridX + iconSize + gridGap, y: y + iconSize + captionGap, width: iconSize, height: captionHeight)
        addLabel.font = .systemFont(ofSize: max(10, 13 * scale), weight: .semibold)
        analyzeLabel.font = .systemFont(ofSize: max(10, 13 * scale), weight: .semibold)
        TPIOSPanelStyle.syncFrames(in: addButton)
        TPIOSPanelStyle.syncFrames(in: analyzeButton)
        y += iconSize + captionGap + captionHeight + max(22, 24 * scale)

        resultLabel.frame = CGRect(x: x, y: y, width: width, height: 170)
        y += 180

        let scanRowHeight: CGFloat = 32
        var sy: CGFloat = 0
        for row in scanStack.arrangedSubviews {
            row.frame = CGRect(x: 0, y: sy, width: width, height: scanRowHeight)
            sy += scanRowHeight + 6
        }
        scanStack.frame = CGRect(x: x, y: y, width: width, height: max(0, sy - 6))
        y += sy + (sy > 0 ? 10 : 0)

        historyLabel.frame = CGRect(x: x, y: y, width: width, height: 360)
        y += 370

        if let note = contentView.viewWithTag(999) {
            note.frame = CGRect(x: x, y: y, width: width, height: 80)
            y += 90
        }

        contentView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: y)
        scrollView.contentSize = contentView.bounds.size

        resizeHandle.frame = CGRect(
            x: bounds.width - handleSize,
            y: bounds.height - handleSize,
            width: handleSize,
            height: handleSize
        )
    }

    private func refreshList() {
        let products = TPIOSSaleStore.shared.load()

        if selectedProductID == nil {
            selectedProductID = products.first?.id
        }

        guard !products.isEmpty else {
            resultLabel.text = "Chưa có sản phẩm theo dõi."
            historyLabel.text = "Hãy dán link Shopee và bấm \"Thêm SP\"."
            return
        }

        if let selected = products.first(where: { $0.id == selectedProductID }) {
            linkField.text = selected.url
            showProduct(selected)
        } else {
            selectedProductID = products.first?.id
            if let selected = products.first {
                linkField.text = selected.url
                showProduct(selected)
            }
        }
    }

    private func showProduct(_ product: TPIOSWatchedSale) {
        let best = product.bestFinalPrice.map(formatMoney) ?? "chưa có"
        let last = product.snapshots.last

        resultLabel.text = """
        \(product.title)

        Item ID: \(product.itemID ?? "chưa xác định")
        Shop ID: \(product.shopID ?? "chưa xác định")
        Biến thể/SKU: \(product.variantName ?? "chưa xác nhận")
        Giá đã chọn gần nhất: \(last?.finalPrice.map(formatMoney) ?? "chưa có")
        Giá thấp nhất từng ghi nhận: \(best)
        Lần kiểm tra: \(formatDate(product.lastCheckedAt))
        """

        if product.snapshots.isEmpty {
            historyLabel.text = "Lịch sử: chưa có snapshot."
        } else {
            historyLabel.text = "LỊCH SỬ\n" + product.snapshots.suffix(12).reversed().map {
                let price = $0.finalPrice.map(formatMoney) ?? "chưa có"
                return "\(formatDate($0.timestamp))  →  \(price)"
            }.joined(separator: "\n")
        }
    }

    @objc private func clearLinkTapped() {
        linkField.text = ""
    }

    @objc private func addProductTapped() {
        viewEndEditing()

        let raw = linkField.text ?? ""
        guard let url = TPIOSSaleLinkParser.makeURL(raw) else {
            resultLabel.text = "Link không hợp lệ. Hãy dán link Shopee."
            return
        }

        resultLabel.text = "Đang xác định link sản phẩm…"

        TPIOSSaleLinkParser.resolve(url) { [weak self] resolvedURL in
            DispatchQueue.main.async {
                guard let self,
                      let resolvedURL,
                      let info = TPIOSSaleLinkParser.parse(resolvedURL) else {
                    self?.resultLabel.text = "Không xác định được sản phẩm từ link này."
                    return
                }

                let title = "Shopee item \(info.itemID ?? "chưa xác định")"
                let product = TPIOSSaleStore.shared.add(
                    url: info.url,
                    title: title,
                    itemID: info.itemID,
                    shopID: info.shopID
                )

                self.selectedProductID = product.id
                self.resultLabel.text = info.itemID == nil
                    ? "Đã lưu link. Cần dữ liệu Shopee để xác định sản phẩm/biến thể."
                    : "Đã xác định sản phẩm. Bấm \"Quét giá\" khi đang đứng đúng trang/giỏ hàng có sản phẩm này."
                self.refreshList()

                TPIOSLog.shared.log(
                    "Sale: đã lưu product URL itemID=\(info.itemID ?? "-") shopID=\(info.shopID ?? "-")"
                )
            }
        }
    }

    // MARK: Quét giá theo vùng chạm

    @objc private func analyzeTapped() {
        viewEndEditing()

        guard selectedProductID != nil else {
            resultLabel.text = "Chưa có sản phẩm để quét giá. Thêm sản phẩm trước."
            return
        }

        startRegionPick()
    }

    private func startRegionPick() {
        guard let hostWindow = self.window else { return }

        isHidden = true

        let overlay = UIView(frame: hostWindow.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.001)

        let hint = UILabel()
        hint.text = "Chạm vào đúng sản phẩm/giá cần quét"
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        hint.layer.cornerRadius = 10
        hint.clipsToBounds = true
        let safeTop = hostWindow.safeAreaInsets.top
        hint.frame = CGRect(x: 20, y: safeTop + 14, width: hostWindow.bounds.width - 100, height: 40)
        overlay.addSubview(hint)

        let cancel = UIButton(type: .system)
        cancel.setTitle("Huỷ", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        cancel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        cancel.layer.cornerRadius = 8
        cancel.frame = CGRect(x: hostWindow.bounds.width - 72, y: safeTop + 14, width: 56, height: 40)
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

        performScan(near: point)
    }

    private func performScan(near point: CGPoint?) {
        guard selectedProductID != nil else { return }

        guard let root = TPIOSSaleScanner.visibleAppRoot(excluding: self.window) else {
            resultLabel.text = "Không tìm thấy màn hình app để quét."
            return
        }

        var values: [TPIOSSaleScanValue] = []
        var usedWholeScreen = false

        if let point {
            values = TPIOSSaleScanner.scanVisibleApp(in: root, near: point, radius: 140)
        }

        if values.isEmpty {
            values = TPIOSSaleScanner.scanVisibleApp(in: root)
            usedWholeScreen = true
        }

        rebuildScanRows(values)
        setNeedsLayout()

        if values.isEmpty {
            resultLabel.text = "Không quét được số tiền nào. Đứng đúng trang/giỏ hàng có sản phẩm rồi quét lại."
        } else if usedWholeScreen && point != nil {
            resultLabel.text = "Không thấy giá gần điểm chạm — đang hiện toàn bộ giá tìm được trên màn hình, chạm chọn đúng giá."
        } else {
            resultLabel.text = "Tìm được \(values.count) giá gần điểm chạm — chạm chọn đúng giá sản phẩm."
        }

        TPIOSLog.shared.log(
            "Sale: quét \(usedWholeScreen ? "toàn màn hình" : "theo vùng chạm"), tìm được \(values.count) giá"
        )
    }

    private func rebuildScanRows(_ values: [TPIOSSaleScanValue]) {
        lastScanValues = values

        scanStack.arrangedSubviews.forEach {
            scanStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, value) in values.prefix(12).enumerated() {
            let row = UIButton(type: .system)
            var text = "  \(formatMoney(value.amount))"
            if value.text != formatMoney(value.amount) {
                let snippet = value.text.count > 34 ? String(value.text.prefix(34)) + "…" : value.text
                text += "   (\(snippet))"
            }
            row.setTitle(text, for: .normal)
            row.contentHorizontalAlignment = .left
            row.setTitleColor(.white, for: .normal)
            row.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            row.titleLabel?.numberOfLines = 1
            row.backgroundColor = UIColor.white.withAlphaComponent(0.07)
            row.layer.cornerRadius = 8
            row.tag = index
            row.addTarget(self, action: #selector(scanRowTapped(_:)), for: .touchUpInside)
            scanStack.addArrangedSubview(row)
        }
    }

    @objc private func scanRowTapped(_ sender: UIButton) {
        guard sender.tag < lastScanValues.count,
              let productID = selectedProductID else {
            return
        }

        let picked = lastScanValues[sender.tag]
        let products = TPIOSSaleStore.shared.load()

        guard let product = products.first(where: { $0.id == productID }) else {
            return
        }

        let snapshot = TPIOSSaleSnapshot(
            timestamp: Date(),
            productName: product.title,
            itemID: product.itemID,
            shopID: product.shopID,
            variantID: product.variantID,
            variantName: product.variantName,
            price: picked.amount,
            finalPrice: picked.amount,
            analysisNote: "Giá chọn tay từ quét màn hình (chạm theo vùng)."
        )

        TPIOSSaleStore.shared.analyze(productID: productID, snapshot: snapshot)

        rebuildScanRows([])
        setNeedsLayout()

        let updated = TPIOSSaleStore.shared.load().first(where: { $0.id == productID }) ?? product
        showProduct(updated)
        resultLabel.text = (resultLabel.text ?? "") + "\n\nĐã lưu giá \(formatMoney(picked.amount))."

        TPIOSLog.shared.log("Sale: đã chọn giá \(Int(picked.amount)) cho productID=\(productID)")
    }

    private func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return "\(formatter.string(from: NSNumber(value: value)) ?? "0")đ"
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "chưa có" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm:ss"
        return formatter.string(from: date)
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
           touch.view === addButton ||
           touch.view === analyzeButton ||
           touch.view === linkField ||
           touch.view === linkField.rightView ||
           touch.view === pickCancelButton {
            return false
        }

        return true
    }
}


// MARK: - Sale data/store

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
}

private final class TPIOSSaleStore {
    static let shared = TPIOSSaleStore()
    private let key = "TPIOS.Sale.WatchedProducts.v1"
    private let defaults = UserDefaults.standard
    private init() {}

    func load() -> [TPIOSWatchedSale] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().withDateDecodingStrategy.decode([TPIOSWatchedSale].self, from: data)) ?? []
    }

    private func save(_ products: [TPIOSWatchedSale]) {
        guard let data = try? JSONEncoder().withDateEncodingStrategy.encode(products) else { return }
        defaults.set(data, forKey: key)
    }

    @discardableResult
    func add(url: String, title: String, itemID: String?, shopID: String?) -> TPIOSWatchedSale {
        var products = load()
        if let index = products.firstIndex(where: { normalizedURL($0.url) == normalizedURL(url) }) {
            return products[index]
        }
        let product = TPIOSWatchedSale(id: UUID(), url: url, title: title, itemID: itemID, shopID: shopID, variantID: nil, variantName: nil, createdAt: Date(), lastCheckedAt: nil, bestFinalPrice: nil, snapshots: [])
        products.insert(product, at: 0)
        save(products)
        return product
    }

    func analyze(productID: UUID, snapshot: TPIOSSaleSnapshot) {
        var products = load()
        guard let index = products.firstIndex(where: { $0.id == productID }) else { return }
        products[index].lastCheckedAt = snapshot.timestamp
        products[index].snapshots.append(snapshot)
        if let finalPrice = snapshot.finalPrice {
            products[index].bestFinalPrice = products[index].bestFinalPrice.map { min($0, finalPrice) } ?? finalPrice
        }
        save(products)
    }

    private func normalizedURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension JSONEncoder {
    var withDateEncodingStrategy: JSONEncoder { dateEncodingStrategy = .iso8601; return self }
}

private extension JSONDecoder {
    var withDateDecodingStrategy: JSONDecoder { dateDecodingStrategy = .iso8601; return self }
}

private struct TPIOSSaleLinkInfo {
    let url: String
    let itemID: String?
    let shopID: String?
}

private enum TPIOSSaleLinkParser {
    static func makeURL(_ rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let value: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            value = trimmed
        } else {
            value = "https://\(trimmed)"
        }

        guard let url = URL(string: value),
              let host = url.host?.lowercased(),
              host == "vn.shp.ee" || host.hasSuffix(".shopee.vn") || host == "shopee.vn"
        else {
            return nil
        }

        return url
    }

    static func resolve(_ url: URL, completion: @escaping (URL?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { _, response, _ in
            completion((response as? HTTPURLResponse)?.url ?? url)
        }.resume()
    }

    static func parse(_ url: URL) -> TPIOSSaleLinkInfo? {
        guard let host = url.host?.lowercased(),
              host == "vn.shp.ee" || host.hasSuffix(".shopee.vn") || host == "shopee.vn"
        else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        var itemID: String?
        var shopID: String?

        if let index = components.firstIndex(where: { $0.lowercased() == "product" }),
           index + 2 < components.count {
            shopID = components[index + 1]
            itemID = components[index + 2]
        }

        if itemID == nil {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            itemID = queryItems.first(where: {
                ["itemid", "item_id", "item"].contains($0.name.lowercased())
            })?.value
            shopID = queryItems.first(where: {
                ["shopid", "shop_id", "shop"].contains($0.name.lowercased())
            })?.value
        }

        return TPIOSSaleLinkInfo(url: url.absoluteString, itemID: itemID, shopID: shopID)
    }
}


// MARK: - Scanner (gộp từ TPIOSSaleScanner.swift, thêm toạ độ màn hình để
// lọc theo vùng chạm)

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

    // near/radius != nil: chỉ lấy giá trị có khung hình cách điểm chạm
    // trong bán kính đó, sắp theo khoảng cách gần nhất trước. nil: quét
    // toàn bộ, sắp theo số tiền giảm dần (hành vi quét toàn màn hình cũ).
    static func scanVisibleApp(
        in root: UIView,
        near point: CGPoint? = nil,
        radius: CGFloat = 140
    ) -> [TPIOSSaleScanValue] {

        var raw: [(text: String, frame: CGRect)] = []
        collectText(from: root, into: &raw)

        var values: [TPIOSSaleScanValue] = []
        var seen = Set<String>()

        for item in raw {
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

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func collectText(
        from view: UIView,
        into items: inout [(text: String, frame: CGRect)]
    ) {
        guard view.isHidden == false, view.alpha > 0.01 else { return }

        func add(_ text: String?) {
            guard let text, text.isEmpty == false else { return }
            items.append((text, view.convert(view.bounds, to: nil)))
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
            collectText(from: child, into: &items)
        }
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
