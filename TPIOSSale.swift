import UIKit

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
    private let resultLabel = UILabel()
    private let historyLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let resizeHandle = UILabel()

    private var resizeStartFrame = CGRect.zero
    private var resizeStartPoint = CGPoint.zero
    private var selectedProductID: UUID?

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
        contentView.addSubview(linkField)

        configureButton(addButton, title: "Thêm sản phẩm", action: #selector(addProductTapped))
        contentView.addSubview(addButton)

        configureButton(analyzeButton, title: "Kiểm tra ngay", action: #selector(analyzeTapped))
        contentView.addSubview(analyzeButton)

        resultLabel.textColor = .white
        resultLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        resultLabel.numberOfLines = 0
        contentView.addSubview(resultLabel)

        historyLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        historyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        historyLabel.numberOfLines = 0
        contentView.addSubview(historyLabel)

        let note = makeLabel(
            "Mỗi lần kiểm tra tạo một snapshot mới. TPIOS dùng link đã lưu và dữ liệu request Shopee làm nền để xây phân tích; chưa giả lập giá/voucher khi API response chưa được thu thập."
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

    private func configureButton(
        _ button: UIButton,
        title: String,
        action: Selector
    ) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(
            red: 0.12,
            green: 0.55,
            blue: 0.95,
            alpha: 1
        )
        button.layer.cornerRadius = 12
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.addTarget(self, action: action, for: .touchUpInside)
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

        addButton.frame = CGRect(x: x, y: y, width: width, height: 42)
        y += 50

        analyzeButton.frame = CGRect(x: x, y: y, width: width, height: 42)
        y += 54

        resultLabel.frame = CGRect(x: x, y: y, width: width, height: 170)
        y += 180

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
            historyLabel.text = "Hãy dán link Shopee và bấm “Thêm sản phẩm”."
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
        (product.title)

        Item ID: (product.itemID ?? "chưa xác định")
        Shop ID: (product.shopID ?? "chưa xác định")
        Giá cuối hiện tại: (last?.finalPrice.map(formatMoney) ?? "chưa có dữ liệu API")
        Giá thấp nhất: (best)
        Lần kiểm tra: (formatDate(product.lastCheckedAt))
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

    @objc private func addProductTapped() {
        viewEndEditing()

        guard let info = TPIOSSaleLinkParser.parse(linkField.text ?? "") else {
            resultLabel.text = "Link không hợp lệ. Hãy dán link sản phẩm Shopee."
            return
        }

        let title = "Shopee item \(info.itemID ?? "chưa xác định")"
        let product = TPIOSSaleStore.shared.add(
            url: info.url,
            title: title,
            itemID: info.itemID,
            shopID: info.shopID
        )

        selectedProductID = product.id
        resultLabel.text = "Đã lưu sản phẩm. Bấm “Kiểm tra ngay” để tạo snapshot."
        refreshList()

        TPIOSLog.shared.log(
            "Sale: đã lưu product URL itemID=\(info.itemID ?? "-") shopID=\(info.shopID ?? "-")"
        )
    }

    @objc private func analyzeTapped() {
        viewEndEditing()

        guard let selectedProductID else {
            resultLabel.text = "Chưa có sản phẩm để phân tích."
            return
        }

        let products = TPIOSSaleStore.shared.load()
        guard let product = products.first(where: { $0.id == selectedProductID }) else {
            resultLabel.text = "Không tìm thấy sản phẩm đã lưu."
            return
        }

        let evidence = TPIOSNetworkLog.shared.recentSaleRequestURLs()
        let snapshot = TPIOSSaleSnapshot(
            timestamp: Date(),
            productName: product.title,
            itemID: product.itemID,
            shopID: product.shopID,
            price: nil,
            finalPrice: nil,
            analysisNote: evidence.isEmpty
                ? "Chưa có request Shopee phù hợp được NetLog ghi nhận."
                : "Đã ghi nhận request Shopee liên quan; chưa có response payload để tính giá/voucher thật.",
            requestEvidence: Array(evidence.suffix(20))
        )

        TPIOSSaleStore.shared.analyze(
            productID: selectedProductID,
            snapshot: snapshot
        )

        showProduct(
            TPIOSSaleStore.shared.load().first(where: { $0.id == selectedProductID }) ?? product
        )

        resultLabel.text = (resultLabel.text ?? "") + "\n\n" + snapshot.analysisNote

        TPIOSLog.shared.log(
            "Sale: snapshot \(formatDate(snapshot.timestamp)) — requestEvidence=\(evidence.count)"
        )
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
           touch.view === linkField {
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
    let price: Double?
    let finalPrice: Double?
    let analysisNote: String
    let requestEvidence: [String]
}

struct TPIOSWatchedSale: Codable {
    let id: UUID
    var url: String
    var title: String
    var itemID: String?
    var shopID: String?
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
        let product = TPIOSWatchedSale(id: UUID(), url: url, title: title, itemID: itemID, shopID: shopID, createdAt: Date(), lastCheckedAt: nil, bestFinalPrice: nil, snapshots: [])
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
    static func parse(_ rawURL: String) -> TPIOSSaleLinkInfo? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let value = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\\(trimmed)"
        guard let url = URL(string: value), let host = url.host?.lowercased(), host.contains("shopee") else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        var itemID: String?
        var shopID: String?
        if let index = components.firstIndex(where: { $0.lowercased() == "product" }), index + 2 < components.count {
            shopID = components[index + 1]
            itemID = components[index + 2]
        }
        if itemID == nil {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            itemID = queryItems.first(where: { ["itemid", "item_id", "item"].contains($0.name.lowercased()) })?.value
            shopID = queryItems.first(where: { ["shopid", "shop_id", "shop"].contains($0.name.lowercased()) })?.value
        }
        return TPIOSSaleLinkInfo(url: url.absoluteString, itemID: itemID, shopID: shopID)
    }
}
