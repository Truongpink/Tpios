import Foundation

extension Notification.Name {
    static let tpiosServerTimeChanged =
        Notification.Name("tpiosServerTimeChanged")
}

// Đồng bộ giờ với server Shopee và đo độ trễ mạng.
//
// Header HTTP "Date" chỉ có độ phân giải 1 giây, nên 1 lần đọc đơn lẻ sai
// tới ±0.5s. Cách làm ở đây: đo nhiều lần, mỗi lần cách nhau 0.31s (lệch
// pha với nhịp 1s). Mỗi mẫu cho biết "giờ server thật nằm trong khoảng
// [Date, Date+1)", quy ra độ lệch so với giờ máy là 1 khoảng; giao các
// khoảng của nhiều mẫu lại sẽ thu hẹp còn vài chục ms.
//
// Chỉ chạy khi người dùng mở đồng hồ hoặc chạm để đồng bộ lại — không có
// timer/quét nền liên tục.
//
// Mọi thuộc tính chỉ được đọc/ghi trên main thread.
final class TPIOSServerTime {

    static let shared = TPIOSServerTime()

    enum State {
        case idle
        case syncing
        case synced
        case failed
    }

    private(set) var state: State = .idle

    // giờ server ≈ Date() + offset (giây)
    private(set) var offset: TimeInterval = 0

    // Sai số ước lượng của offset (giây).
    private(set) var uncertainty: TimeInterval = 0

    // Ping trung vị tới server (giây).
    private(set) var latency: TimeInterval = 0

    // Chỉ cần bất kỳ phản hồi HTTP nào có header Date (kể cả 403/404).
    // Nếu mẫu warm-up của địa chỉ đầu không nhận được phản hồi thì chuyển
    // sang địa chỉ kế tiếp cho các mẫu còn lại.
    private let endpoints = [
        URL(string: "https://shopee.vn/")!,
        URL(string: "https://mall.shopee.vn/")!
    ]

    // Mẫu đầu tiên là warm-up (tốn thời gian bắt tay TLS) nên bị bỏ.
    private let sampleCount = 10
    private let sampleSpacing: TimeInterval = 0.31

    private struct Sample {
        // Giờ máy (epoch) tại thời điểm server sinh header, ước lượng
        // bằng điểm giữa lúc gửi và lúc nhận.
        let localMid: TimeInterval
        // Giá trị header Date (epoch, đã làm tròn xuống giây).
        let serverSecond: TimeInterval
        let rtt: TimeInterval
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private init() {}

    var statusText: String {

        switch state {

        case .idle:
            return "Giờ máy • chạm để đồng bộ server"

        case .syncing:
            return "Đang đồng bộ giờ server…"

        case .failed:
            return "Đồng bộ lỗi • chạm để thử lại"

        case .synced:
            let uncertaintyMs = Int((uncertainty * 1000).rounded())
            let pingMs = Int((latency * 1000).rounded())

            // offset = giờ server - giờ máy → máy nhanh khi offset < 0
            let deviceAhead = -offset
            let direction = deviceAhead >= 0 ? "máy nhanh" : "máy chậm"
            let deviceText = direction + " " + String(format: "%.2fs", abs(deviceAhead))

            return "Server ±\(uncertaintyMs)ms • ping \(pingMs)ms • \(deviceText)"
        }
    }

    func syncIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.syncIfNeeded()
            }
            return
        }

        if state == .idle {
            sync()
        }
    }

    func sync() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.sync()
            }
            return
        }

        guard state != .syncing else {
            return
        }

        state = .syncing
        notifyChanged()

        // 1 session duy nhất cho mọi mẫu để tái dùng kết nối (keep-alive),
        // nhờ đó rtt các mẫu sau phản ánh đúng 1 vòng đi-về.
        let session = URLSession(configuration: .ephemeral)

        step(index: 0, samples: [], session: session, endpointIndex: 0)
    }

    private func step(
        index: Int,
        samples: [Sample],
        session: URLSession,
        endpointIndex: Int
    ) {

        guard index < sampleCount else {
            finish(samples: samples, session: session)
            return
        }

        var request = URLRequest(url: endpoints[endpointIndex])
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 6

        let wallSend = Date().timeIntervalSince1970
        let uptimeSend = ProcessInfo.processInfo.systemUptime

        session.dataTask(with: request) { [weak self] _, response, _ in

            let rtt = ProcessInfo.processInfo.systemUptime - uptimeSend
            let dateHeader = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Date")

            DispatchQueue.main.async {

                guard let self else {
                    return
                }

                var collected = samples
                var nextEndpoint = endpointIndex

                // Warm-up không có phản hồi → thử địa chỉ dự phòng.
                if index == 0, dateHeader == nil {
                    nextEndpoint = (endpointIndex + 1) % self.endpoints.count
                }

                if index > 0,
                   let text = dateHeader,
                   let serverDate = TPIOSServerTime.httpDateFormatter.date(from: text) {

                    collected.append(
                        Sample(
                            localMid: wallSend + rtt / 2,
                            serverSecond: serverDate.timeIntervalSince1970,
                            rtt: rtt
                        )
                    )
                }

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + self.sampleSpacing
                ) {
                    self.step(
                        index: index + 1,
                        samples: collected,
                        session: session,
                        endpointIndex: nextEndpoint
                    )
                }
            }
        }.resume()
    }

    private func finish(
        samples: [Sample],
        session: URLSession
    ) {

        session.finishTasksAndInvalidate()

        let intervals = samples.map {
            (
                lo: $0.serverSecond - $0.localMid,
                hi: $0.serverSecond + 1 - $0.localMid
            )
        }

        guard let best = TPIOSServerTime.bestIntersection(of: intervals),
              best.count >= max(3, samples.count / 2) else {

            state = .failed
            TPIOSLog.shared.log(
                "ServerTime: đồng bộ thất bại, mẫu hợp lệ=\(samples.count)"
            )
            notifyChanged()
            return
        }

        let sortedRTT = samples.map { $0.rtt }.sorted()
        let minRTT = sortedRTT.first ?? 0

        offset = (best.lo + best.hi) / 2

        // Sai số = nửa độ rộng khoảng giao + nửa RTT nhỏ nhất (giả định
        // đường đi và về đối xứng).
        uncertainty = (best.hi - best.lo) / 2 + minRTT / 2

        latency = sortedRTT[sortedRTT.count / 2]

        state = .synced

        TPIOSLog.shared.log(
            String(
                format: "ServerTime: offset=%+.3fs ±%.0fms ping=%.0fms",
                offset,
                uncertainty * 1000,
                latency * 1000
            ) + " mẫu=\(samples.count) dùng=\(best.count)"
        )

        notifyChanged()
    }

    // Tìm điểm được nhiều khoảng phủ nhất (chịu được vài mẫu nhiễu do
    // jitter mạng), rồi trả về phần giao của các khoảng đó.
    private static func bestIntersection(
        of intervals: [(lo: Double, hi: Double)]
    ) -> (lo: Double, hi: Double, count: Int)? {

        var best: (lo: Double, hi: Double, count: Int)?

        for candidate in intervals.map({ $0.lo }) {

            let covering = intervals.filter {
                $0.lo <= candidate && candidate < $0.hi
            }

            guard covering.isEmpty == false else {
                continue
            }

            let lo = covering.map { $0.lo }.max() ?? candidate
            let hi = covering.map { $0.hi }.min() ?? candidate

            if let current = best {
                let better =
                    covering.count > current.count ||
                    (covering.count == current.count &&
                     (hi - lo) < (current.hi - current.lo))

                if better == false {
                    continue
                }
            }

            best = (lo: lo, hi: hi, count: covering.count)
        }

        return best
    }

    private func notifyChanged() {
        NotificationCenter.default.post(
            name: .tpiosServerTimeChanged,
            object: nil
        )
    }
}
