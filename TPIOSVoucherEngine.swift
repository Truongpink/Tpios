import Foundation

enum TPIOSVoucherKind: String {
    case shop
    case platform
    case vip
    case freeship
}

enum TPIOSVoucherDiscount {
    case fixed(Double)
    case percentage(Double)
}

struct TPIOSVoucher {
    let id: String
    let title: String
    let kind: TPIOSVoucherKind
    let discount: TPIOSVoucherDiscount
    let minimumSpend: Double
    let maximumDiscount: Double?
    let shopID: String?
    let productID: String?
    let isVIPOnly: Bool
    let isStackable: Bool

    init(
        id: String,
        title: String,
        kind: TPIOSVoucherKind,
        discount: TPIOSVoucherDiscount,
        minimumSpend: Double = 0,
        maximumDiscount: Double? = nil,
        shopID: String? = nil,
        productID: String? = nil,
        isVIPOnly: Bool = false,
        isStackable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.discount = discount
        self.minimumSpend = max(0, minimumSpend)
        self.maximumDiscount = maximumDiscount
        self.shopID = shopID
        self.productID = productID
        self.isVIPOnly = isVIPOnly
        self.isStackable = isStackable
    }
}

struct TPIOSProductContext {
    let productID: String?
    let shopID: String?
    let merchandiseAmount: Double
    let shippingAmount: Double
    let isVIP: Bool
}

struct TPIOSVoucherSelection {
    let vouchers: [TPIOSVoucher]
    let merchandiseDiscount: Double
    let shippingDiscount: Double

    var totalDiscount: Double {
        merchandiseDiscount + shippingDiscount
    }
}

struct TPIOSVoucherCalculation {
    let merchandiseBefore: Double
    let shippingBefore: Double
    let merchandiseAfter: Double
    let shippingAfter: Double
    let selection: TPIOSVoucherSelection

    var totalBefore: Double {
        merchandiseBefore + shippingBefore
    }

    var totalAfter: Double {
        merchandiseAfter + shippingAfter
    }

    var totalSaved: Double {
        max(0, totalBefore - totalAfter)
    }
}

enum TPIOSVoucherEngine {

    static func calculateBest(
        product: TPIOSProductContext,
        vouchers: [TPIOSVoucher]
    ) -> TPIOSVoucherCalculation {
        let eligible = vouchers.filter {
            isEligible($0, for: product)
        }

        let candidates = buildCandidates(
            product: product,
            vouchers: eligible
        )

        let best = candidates.max {
            score($0) < score($1)
        } ?? TPIOSVoucherSelection(
            vouchers: [],
            merchandiseDiscount: 0,
            shippingDiscount: 0
        )

        let merchandiseAfter = max(
            0,
            product.merchandiseAmount - best.merchandiseDiscount
        )

        let shippingAfter = max(
            0,
            product.shippingAmount - best.shippingDiscount
        )

        return TPIOSVoucherCalculation(
            merchandiseBefore: product.merchandiseAmount,
            shippingBefore: product.shippingAmount,
            merchandiseAfter: merchandiseAfter,
            shippingAfter: shippingAfter,
            selection: best
        )
    }

    static func isEligible(
        _ voucher: TPIOSVoucher,
        for product: TPIOSProductContext
    ) -> Bool {
        guard product.merchandiseAmount >= voucher.minimumSpend else {
            return false
        }

        if voucher.isVIPOnly && !product.isVIP {
            return false
        }

        if let shopID = voucher.shopID,
           shopID != product.shopID {
            return false
        }

        if let productID = voucher.productID,
           productID != product.productID {
            return false
        }

        return true
    }

    private static func buildCandidates(
        product: TPIOSProductContext,
        vouchers: [TPIOSVoucher]
    ) -> [TPIOSVoucherSelection] {
        let merchandiseVouchers = vouchers.filter {
            $0.kind != .freeship
        }

        let shippingVouchers = vouchers.filter {
            $0.kind == .freeship
        }

        var merchandiseGroups: [[TPIOSVoucher]] = [[]]

        for kind in [TPIOSVoucherKind.shop, .platform, .vip] {
            let group = merchandiseVouchers.filter {
                $0.kind == kind
            }

            guard !group.isEmpty else {
                continue
            }

            let allowed = group.filter { $0.isStackable }

            if allowed.isEmpty {
                continue
            }

            var next = merchandiseGroups

            for current in merchandiseGroups {
                for voucher in allowed {
                    if current.contains(where: { $0.kind == voucher.kind }) {
                        continue
                    }

                    next.append(current + [voucher])
                }
            }

            merchandiseGroups = next
        }

        var selections: [TPIOSVoucherSelection] = []

        for merchandiseGroup in merchandiseGroups {
            let shippingOptions = [[]] + shippingVouchers.map { [$0] }

            for shippingGroup in shippingOptions {
                let selected = merchandiseGroup + shippingGroup

                let merchandiseDiscount = calculateMerchandiseDiscount(
                    product: product,
                    vouchers: merchandiseGroup
                )

                let shippingDiscount = calculateShippingDiscount(
                    product: product,
                    vouchers: shippingGroup
                )

                selections.append(
                    TPIOSVoucherSelection(
                        vouchers: selected,
                        merchandiseDiscount: merchandiseDiscount,
                        shippingDiscount: shippingDiscount
                    )
                )
            }
        }

        return selections
    }

    private static func calculateMerchandiseDiscount(
        product: TPIOSProductContext,
        vouchers: [TPIOSVoucher]
    ) -> Double {
        var subtotal = product.merchandiseAmount
        var totalDiscount = 0.0

        let ordered = vouchers.sorted {
            voucherPriority($0.kind) < voucherPriority($1.kind)
        }

        for voucher in ordered {
            guard subtotal >= voucher.minimumSpend else {
                continue
            }

            let discount = discountAmount(
                voucher.discount,
                base: subtotal,
                maximum: voucher.maximumDiscount
            )

            let applied = min(
                max(0, discount),
                subtotal
            )

            subtotal -= applied
            totalDiscount += applied
        }

        return totalDiscount
    }

    private static func calculateShippingDiscount(
        product: TPIOSProductContext,
        vouchers: [TPIOSVoucher]
    ) -> Double {
        guard let voucher = vouchers.first else {
            return 0
        }

        let discount = discountAmount(
            voucher.discount,
            base: product.shippingAmount,
            maximum: voucher.maximumDiscount
        )

        return min(
            max(0, discount),
            max(0, product.shippingAmount)
        )
    }

    private static func discountAmount(
        _ discount: TPIOSVoucherDiscount,
        base: Double,
        maximum: Double?
    ) -> Double {
        let raw: Double

        switch discount {
        case .fixed(let amount):
            raw = amount

        case .percentage(let percentage):
            raw = base * max(0, percentage) / 100
        }

        if let maximum {
            return min(raw, max(0, maximum))
        }

        return max(0, raw)
    }

    private static func voucherPriority(
        _ kind: TPIOSVoucherKind
    ) -> Int {
        switch kind {
        case .shop:
            return 0
        case .platform:
            return 1
        case .vip:
            return 2
        case .freeship:
            return 3
        }
    }

    private static func score(
        _ selection: TPIOSVoucherSelection
    ) -> Double {
        selection.totalDiscount
    }
}
