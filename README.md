# TPIOS

TPIOS là **iOS dynamic library (dylib)** dành cho môi trường iOS đã được inject/tweak. Repo chứa mã Swift và Objective-C để hiển thị bộ công cụ nổi trong ứng dụng đang chạy, đọc một số dữ liệu runtime/network và cung cấp các tiện ích tương tác.

> Tài liệu này được đối chiếu với source trên `main` tại commit `d4fe164e22d865918df058dbc10ec83a0905f6c4` (2026-11-13). Mục “đã xác nhận” chỉ dùng cho chức năng đã có kết quả chạy thực tế do người dùng xác nhận; có source trong repo không đồng nghĩa mọi chức năng đã được kiểm thử trên mọi ứng dụng/iOS.

---

## 1. TPIOS build ra cái gì?

- **Đầu ra:** `TPIOS.dylib`, đóng gói artifact với tên dạng `tpiosNN.dylib`.
- **Kiến trúc:** `arm64`.
- **Deployment target khi biên dịch:** iOS 15.0.
- **Build runner:** macOS + Xcode 26.6 (workflow chọn `/Applications/Xcode_26.6.app`).
- **Cách build:** compile các file Objective-C thành object, sau đó dùng `swiftc` liên kết toàn bộ `*.swift` cùng các object thành dylib.
- **Không phải:** ứng dụng Xcode độc lập hoặc IPA. Repo hiện build một dylib để nạp vào tiến trình ứng dụng mục tiêu.

### Workflow

| File | Công việc |
|---|---|
| `.github/workflows/build.yml` | Build dylib, đóng gói và upload artifact `TPIOS-NN`; cuối workflow có bước backup source sang nhánh auto trên GitLab (nếu secret được cấu hình). |
| `.github/workflows/backup-release.yml` | Workflow backup thủ công: kiểm tra commit đã có build thành công, tạo ZIP toàn repo, tạo GitHub Release và đẩy bản backup đã xác minh sang GitLab. |

**Cả hai workflow hiện chỉ có trigger `workflow_dispatch`.** Push/commit lên `main` không tự chạy build workflow. Không tự ý dispatch workflow khi chỉnh sửa tài liệu hoặc code.

---

## 2. Cách TPIOS khởi động

Luồng khởi động trong source:

1. `TPIOSBootstrap.m` dùng constructor của dylib để đưa tác vụ khởi tạo lên main queue.
2. Cài hook chặn một số màn hình quảng cáo Google Mobile Ads qua `TPIOSGADPresentationBlocker.m`.
3. Cài chẩn đoán WKWebView qua `TPIOSWebDiagnostics.swift`.
4. Gọi symbol `TPIOSStart()` trong `TPIOSEntry.swift`.
5. `TPIOSStart()` cài bộ thu dữ liệu response giỏ hàng `TPIOSCartBody`, sau đó gọi `TPIOSController.start()`.
6. Controller tạo `TPIOSPassThroughWindow`, đặt nút nổi và mở menu khi người dùng chạm nút.

`TPIOSStop()` là điểm dừng được export để đóng overlay và dọn trạng thái controller.

### Overlay và nút nổi

- `FloatingButton.swift`: nút nổi hình tròn, kéo được.
- `TPIOSController.swift`: quản lý vòng đời overlay window, menu, retry khi app chưa có foreground scene, kéo nút và giảm độ mờ sau thời gian không thao tác.
- `TPIOSPassThroughWindow.hitTest`: chỉ giữ touch nếu touch trúng UI của TPIOS; vùng trống xuyên xuống ứng dụng bên dưới.
- `TPIOSMenu.swift`: menu chính, kéo bằng header, resize ở góc dưới và giới hạn trong vùng màn hình.
- `TPIOSPanelStyle.swift`: nền kính, gradient và đồng bộ frame cho các panel.

---

## 3. Menu và chức năng đang có

Menu hiện có **9 nút**:

| Nút | Chức năng trong source | File chính |
|---|---|---|
| **Vị trí** | Giao diện bản đồ/tìm địa điểm, nhập tọa độ và địa chỉ, lưu vị trí, bật/tắt giả lập vị trí | `TPIOSLocation.swift`, `TPIOSLocationSpoofHook.swift` |
| **Sale** | Theo dõi sản phẩm Shopee, lưu các lần quét, đọc tên/giá/voucher đang hiển thị và tính giá sau mã | `TPIOSSale.swift`, `TPIOSSaleScanner.swift`, `TPIOSSaleData.swift` |
| **Xem log** | Xem, lọc, xóa và lưu log; có thao tác bắt request mạng | `TPIOSLog.swift`, `TPIOSNetworkLog.swift` |
| **Tắt QC** | Quét và lưu profile nhận diện cơ chế quảng cáo; áp dụng các nhánh xử lý native/WebView/model filter | `TPIOSAdBlock.swift`, `TPIOSModelFilter.m` |
| **Đồng hồ** | Đồng hồ nổi HH:MM:SS và phần mười giây; có thể đồng bộ giờ server Shopee | `TPIOSSaleClock.swift`, `TPIOSServerTime.swift` |
| **Tải lại** | Tìm các refresh candidate trong view/controller/WebView/scroll view rồi thử kích hoạt cơ chế refresh phù hợp | `TPIOSReload.swift` |
| **Mua all** | Màn hình chẩn đoán IAP/StoreKit: quét thành phần app, đọc receipt và trạng thái giao dịch/entitlement | `TPIOSMenu.swift`, `TPIOSAppScanner.swift`, `TPIOSPaymentScanner.swift` |
| **Chạm** | Chọn nhiều điểm trên màn hình và tự động gửi chuỗi touch DOWN/UP theo thứ tự | `TPIOSAutoClickPanel.swift`, `TPIOSTapTest.swift`, `CHMTouchBackend.m/.h` |
| **Cào xu** | Panel nổi có thể kéo ẩn vào mép màn hình/kéo ra, lưu trạng thái phiên và log riêng; chưa có bộ đọc nhiệm vụ hay kịch bản tự động Lazada | `TPIOSCaoXu.swift` |

**Lưu ý về “Mua all”:** các mục hiện tại là công cụ chẩn đoán StoreKit/receipt. Source chưa thể hiện một luồng tự động mua sản phẩm hay tự xác nhận giao dịch.

---

## 4. CHẠM — kiến trúc và cách hoạt động chi tiết

Đây là luồng auto-click hiện có trong source. Phần giao diện/lập lịch viết bằng Swift; phần phát touch cấp thấp viết bằng Objective-C.

### 4.1. Các thành phần

| File | Vai trò |
|---|---|
| `TPIOSMenu.swift` | Nút **Chạm**, mở màn hình auto-click. |
| `TPIOSTapTest.swift` | Tìm cửa sổ app thật phía dưới overlay, tạo panel và quản lý lúc mở/đóng. |
| `TPIOSAutoClickPanel.swift` | Chọn/lưu/sửa điểm, marker đánh số, tốc độ, timer, trạng thái chạy/dừng và thứ tự điểm. |
| `CHMTouchBackend.h` | Khai báo API backend: phase DOWN/UP, callback dispatch và trạng thái sẵn sàng. |
| `CHMTouchBackend.m` | Tạo và gửi sự kiện HID, đồng thời dựng UIEvent/UITouch để UIKit chuyển sự kiện tới view đích. |

### 4.2. Chọn và lưu nhiều điểm

1. Người dùng mở **Chạm**. `TPIOSTapTest` lấy app window đang foreground, loại trừ `TPIOSPassThroughWindow` của TPIOS.
2. Panel được gắn trực tiếp lên app window. Khi nhấn **Điểm**, panel tạo một overlay trong suốt phủ màn hình và tạm ẩn panel.
3. Mỗi lần chạm màn hình, `pickerTap` lấy tọa độ local của vùng chọn rồi convert sang tọa độ của app window.
4. Tọa độ được thêm vào mảng `points`. Thứ tự thêm chính là thứ tự chạy.
5. Dữ liệu gồm danh sách tọa độ `x/y` và tốc độ được JSON encode, lưu trong `UserDefaults` với key `TPIOSAutoClickSettings`.
6. Khi mở lại panel/app, `loadSettings()` khôi phục các điểm và tốc độ; `didMoveToWindow()` dựng lại marker từ mảng điểm đã lưu.

Không có giới hạn số điểm cố định trong logic mảng hiện tại; số điểm thực tế phụ thuộc không gian màn hình và khả năng thao tác của người dùng.

### 4.3. Marker và thứ tự chạy

- Mỗi điểm hiển thị thành marker tròn màu xanh, đường kính **30 pt**.
- Marker có số thứ tự màu trắng, bắt đầu từ **1**.
- Số được gán theo vị trí trong mảng `markers/points`; khi khôi phục, marker được dựng theo đúng thứ tự đã lưu.
- Kéo marker sẽ cập nhật tọa độ của đúng phần tử tại index tương ứng; việc kéo không đổi thứ tự.
- Khi kết thúc thao tác kéo, tọa độ mới được lưu lại.
- **Xóa** dừng vòng chạy, xóa toàn bộ điểm/marker, cập nhật bộ đếm và lưu danh sách rỗng.

Vì vậy số 1, 2, 3… là thứ tự chạm, không phải ID ngẫu nhiên.

### 4.4. Tốc độ và chu kỳ click

Các thông số đang được đặt trong `TPIOSAutoClickPanel.swift`:

| Thông số | Giá trị |
|---|---:|
| Tốc độ mặc định | 0.15 giây |
| Khoảng tốc độ cho phép | 0.05–5.00 giây |
| Thời gian giữ một lần chạm (`pressDuration`) | 0.06 giây |
| Timer | `DispatchSourceTimer` trên main queue |
| Timer leeway | 1 ms |

Cách hiểu chính xác: **0.06 giây là thời gian giữ DOWN trước khi gửi UP; giá trị speed là thời gian nghỉ sau UP trước DOWN kế tiếp.** Do đó chu kỳ danh nghĩa giữa hai lần DOWN liên tiếp xấp xỉ `0.06 + speed` giây, chưa tính thời gian xử lý hệ thống. Slider không phải tham số thời gian giữ ngón tay.

### 4.5. Bộ lập lịch DOWN/UP

Khi nhấn **Bắt đầu**:

1. Từ chối chạy nếu chưa có điểm.
2. Nếu một touch cũ chưa được xác nhận UP, không cho bắt đầu chu kỳ mới.
3. Kiểm tra `TPIOSAutoClickEngine.backendAvailable()`; backend không sẵn sàng thì báo trạng thái và không chạy.
4. Đặt `running = true`, reset index về 0 và đưa lần DOWN đầu tiên sang main queue async để tránh gửi touch lồng ngay trong lúc UIKit đang xử lý nút Start.
5. `performDown()` lấy `points[currentPointIndex % points.count]`, gửi DOWN tại điểm đó.
6. Nếu DOWN thành công, lưu `activePoint`, đánh dấu `touchIsDown = true`, rồi hẹn `performUp()` sau 0.06 giây.
7. `performUp()` gửi UP tại **chính activePoint vừa DOWN**, không lấy tọa độ khác.
8. Chỉ khi UP thành công mới tăng TAP counter và chuyển index sang điểm kế tiếp: `(currentPointIndex + 1) % points.count`.
9. Nếu vẫn đang chạy, đợi khoảng speed rồi thực hiện DOWN tiếp theo.

Ví dụ 3 điểm: **1 → 2 → 3 → 1 → 2 → 3…**. Với một điểm, vòng lặp tiếp tục ở điểm đó.

Chỉ có **một ngón tay/contact đang hoạt động tại một thời điểm**. Đây là click tuần tự nhiều tọa độ, không phải multi-touch đồng thời.

### 4.6. Backend phát touch cấp thấp

`TPIOSTapTest.swift` là cầu nối Swift sang hai C symbol:

- `TPIOSCHMTouchAvailable()`: kiểm tra backend HID có sẵn.
- `TPIOSCHMTouchDispatch(x, y, phase)`: gửi sự kiện; phase `0` là DOWN và phase `3` là UP.

Trong `CHMTouchBackend.m`:

1. Dùng `dlopen/dlsym` để nạp và tìm các entry point IOKit HID cần thiết. Các hàm cốt lõi gồm tạo digitizer event, tạo finger event, tạo HID event client, đặt sender ID, set field, append event và dispatch event. BackBoardServices được nạp riêng; `BKSHIDEventSetDigitizerInfo` là phần bổ sung tùy khả năng có mặt.
2. Khi DOWN, backend tìm foreground app window thật, loại trừ overlay window TPIOS và lấy context ID nếu selector private `_contextId` có sẵn.
3. Tọa độ scheduler lưu theo hệ tọa độ window. Backend convert tọa độ này sang hệ tọa độ màn hình cho HID event.
4. Tạo digitizer parent event và finger child event, gắn metadata/finger index, force/radius và append finger vào parent.
5. Để UIKit định tuyến tới đúng control/view, backend tạm ẩn các overlay root có tag `0x5450494F`, hit-test tại tọa độ DOWN trên app window, sau đó hiện lại overlay.
6. Backend tạo/cập nhật `UITouch` và `UIEvent` bằng các selector UIKit private, đặt window/view/phase/timestamp/location/HID event, rồi gọi `UIApplication.sendEvent`.
7. Nếu có selector tương ứng, backend còn gọi `_enqueueHIDEvent:`; cuối cùng dispatch parent event qua `IOHIDEventSystemClientDispatchEvent`.
8. Backend giữ lại `UITouch`, window, view, context ID và tọa độ của DOWN. Khi UP, nó dùng lại đúng contact/window/view/context/point đó để đóng contact ban đầu, không hit-test lại sang view khác.

Việc kết hợp đường UIKit event với đường HID là chủ ý của backend hiện tại: UIKit có target view để xử lý control, còn HID event được đưa xuống event system.

### 4.7. Cơ chế dừng và chống touch bị kẹt

- Nhấn **Dừng** sẽ hủy timer và nếu đang DOWN thì cố gửi UP cho active point.
- Đóng panel gọi `cleanup()`: dừng scheduler, xóa picker/marker và hủy timer.
- DOWN lỗi: dừng chu kỳ và báo `DOWN LỖI`.
- UP lỗi: dừng, giữ cờ touch chưa nhả và báo `UP LỖI - ĐÃ KHÓA`; không cho bắt đầu DOWN mới khi contact cũ chưa được xác nhận đóng.
- Backend cũng từ chối DOWN thứ hai nếu vẫn còn active UITouch; UP phải dùng contact gốc.
- Backend kiểm tra main thread, tọa độ hữu hạn, phase hợp lệ và sự tồn tại của các API/selector cần thiết. Lỗi được ghi vào TPIOS log.

Những guard này nhằm tránh chồng hai contact hoặc tiếp tục bắn DOWN khi lần UP trước chưa thành công.

### 4.8. Trạng thái xác nhận và giới hạn tương thích

- **Đã xác nhận thực tế:** người dùng đã báo bản build có marker nhỏ/đánh số và luồng Chạm hiện tại chạy OK (2026-11-13).
- Tài liệu này không chạy build hay GitHub Actions; đây là mô tả source tại commit nêu đầu README.
- Backend phụ thuộc các API/selector private/undocumented của iOS (IOKit HID, BackBoardServices và UIKit private selectors). Việc compile được không đảm bảo API private luôn tồn tại hoặc giữ ABI trên mọi bản iOS.
- Workflow target arm64/iOS 15.0 là thông số biên dịch, **không phải cam kết** backend tương thích mọi phiên bản iOS hay mọi ứng dụng.
- Cần kiểm thử lại trên thiết bị/môi trường inject mục tiêu sau khi đổi iOS hoặc thay đổi backend.

---

## 5. Các module còn lại

### Vị trí và giả lập GPS

- Giao diện có tìm địa điểm, bản đồ, chọn tọa độ, nhập/sửa vĩ độ–kinh độ–độ cao/địa chỉ và danh sách vị trí lưu.
- `TPIOSLocationSpoofHook.swift` swizzle các entry point của `CLLocationManager` như start update, request location và location; khi spoof bật thì trả vị trí giả, khi tắt thì gọi implementation gốc.
- **Cảnh báo nguồn:** đầu file `TPIOSLocation.swift` ghi rõ source này được dựng lại từ symbol table của binary cũ; chữ ký đã xác nhận nhưng một số thân hàm là suy luận theo tên và phong cách các panel khác. Vì vậy không được coi toàn bộ logic file này là source gốc đã được xác minh từng dòng.

### Sale Shopee

- `TPIOSSale.swift`: giao diện theo dõi sản phẩm, tạo lần quét (snapshot), xem lịch sử, xóa sản phẩm/lần quét, chỉnh tên/giá và nhập voucher.
- `TPIOSSaleScanner.swift`: đọc text từ view đang hiển thị trong app, gom text cùng frame, tìm tên sản phẩm/giá/voucher và đọc thông tin gần vị trí chọn. Đây là đọc cây view/text runtime, không phải OCR ảnh màn hình.
- `TPIOSSaleData.swift`: model, lưu trữ, chuẩn hóa tên, tính mức giảm và chọn tổ hợp voucher phù hợp điều kiện/min spend/max discount.
- `TPIOSCartBody.swift`: hook URLSession delegate để gom response của các request cart/voucher/checkout vào log; parser hiện tạo snapshot giỏ từ response `cart/get` và `cart/update`.
- Dữ liệu sản phẩm theo dõi được lưu bằng UserDefaults. Việc đọc cart response hỗ trợ so sánh dữ liệu giỏ với dữ liệu đang theo dõi.

### Log và network evidence

- `TPIOSLog.swift`: log có giới hạn 2.000 dòng, xem/lọc/xóa, di chuyển/resize cửa sổ và lưu log ra file.
- Trong cửa sổ log có thao tác bắt request mạng. Khi người dùng bật, `TPIOSNetworkLog` hook `URLSessionTask.resume`, ghi lại một tập URL Shopee liên quan đến item/product/voucher/discount/shipping/flash; giữ tối đa 120 request evidence gần nhất.
- `TPIOSCartBody` được cài lúc TPIOS khởi động; network URL evidence được bật từ thao tác trong giao diện log.

### Cào xu Lazada — trạng thái triển khai

- `TPIOSCaoXu.swift` có panel Bắt đầu/Tạm dừng, tiến độ nhiệm vụ được nhận diện, log riêng, sao chép và xóa log.
- Khi Bắt đầu, panel quan sát định kỳ (2 giây/lần) chữ đang hiển thị trong cây UIKit và các phần tử nhìn thấy trong `WKWebView`; không tự chạm, không hook/bắt request mạng.
- Các dòng có từ khóa nhiệm vụ Lazada được ghi nhận tự động. Chỉ đánh dấu hoàn thành khi cùng dòng nhiệm vụ có tín hiệu hoàn thành rõ ràng; các trường hợp không rõ vẫn để chờ.
- Bộ nhận diện dựa trên từ khóa giao diện tổng quát, chưa được xác nhận với mọi biến thể/ngôn ngữ/trạng thái trang Lazada. Cần kiểm tra trên thiết bị sau build được người dùng cho phép; không coi nhận diện là đã được kiểm thử thực tế.
- Tên nhiệm vụ và trạng thái được lưu riêng trong UserDefaults; log Cào xu lưu tối đa 500 dòng và không dùng chung log chính. Tạm dừng dừng observer nhưng giữ tiến độ.
- Panel resize tối thiểu 220 × 300 pt; nút Bắt đầu/Tạm dừng dùng biểu tượng tròn gradient. Có thể thu gọn sát mép màn hình thành tay nắm 56 × 56 pt, chỉ lộ khoảng 24 pt.
- Cào xu không gọi `startLazadaCapture`, không sử dụng `TPIOSNetworkLog`, `TPIOSCartBody` hoặc logic Sale Shopee.

- Bộ lọc ứng viên loại tiêu đề chung (ví dụ “Nhiệm vụ hôm nay”), nhãn CTA đơn lẻ (“Tìm kiếm”, “Đánh giá”, “Thêm vào giỏ”, “Check-in ngay”) và dòng đếm đánh giá/người theo dõi.
- Chuẩn hóa khoảng trắng, gộp tiêu đề bị lặp liền nhau và bỏ trùng trong cùng một lượt quan sát.
- Chỉ ghi UserDefaults khi danh sách nhiệm vụ/trạng thái thực sự thay đổi, thay vì ghi lại mỗi chu kỳ 2 giây.
- Các dòng nhiệm vụ cần đủ mô tả và chứa từ khóa hành động; đây vẫn là heuristic theo text, chưa phải nhận diện chính xác cấu trúc từng card trên mọi phiên bản Lazada.

### Đồng hồ và giờ server

- `TPIOSSaleClock.swift`: đồng hồ nổi có thể kéo/resize, hiển thị giờ đến phần mười giây.
- `TPIOSServerTime.swift`: khi người dùng mở/chạm đồng bộ, gửi 10 HTTP HEAD samples tới endpoint Shopee, cách nhau 0.31 giây; dùng header HTTP Date và RTT để ước lượng offset, sai số và ping. Không có vòng quét giờ nền liên tục.

### Chặn quảng cáo và chẩn đoán WebView

- `TPIOSAdBlock.swift`: quan sát runtime/view/controller, tìm dấu hiệu quảng cáo, lưu profile class/selector và áp dụng chiến lược tương ứng; có nhánh fallback WebView/view. Profile được lưu để lần sau có thể áp dụng mà không phải quét lại nếu tương thích.
- `TPIOSModelFilter.m`: hỗ trợ hook các initializer đã chỉ định của class mục tiêu, gọi predicate BOOL và từ chối object nếu predicate xác định là model cần lọc.
- `TPIOSGADPresentationBlocker.m`: hook `presentViewController` và chặn một số class controller fullscreen Google Mobile Ads được nhận diện theo tên class cụ thể.
- `TPIOSWebDiagnostics.swift`: hook `WKWebView.didMoveToWindow`, ghi URL/frame/cây view và truy vấn DOM/resource liên quan quảng cáo để hỗ trợ chẩn đoán. Đây là diagnostics, không phải tự nó đảm bảo chặn được mọi quảng cáo.

### Tải lại trang

`TPIOSReload.swift` tìm các đối tượng có thể refresh trong cây view/controller, gồm refresh control, scroll view, WebView và một số component React Native; sau đó thử callback/selector hoặc fallback phù hợp. Vì app mục tiêu có thể dùng cấu trúc khác nhau, log có thể báo không tìm thấy candidate hoặc không xác định được callback thật.

### Chẩn đoán IAP/StoreKit

- `TPIOSAppScanner.swift`: đọc bundle/version và liệt kê class runtime liên quan StoreKit/Product/Transaction/Receipt.
- `TPIOSPaymentScanner.swift`: đọc trạng thái receipt, số transaction StoreKit 1 và số current entitlement StoreKit 2 (API có sẵn từ iOS 15).
- Chỉ đọc để chẩn đoán; source có comment rõ không sửa receipt, entitlement hoặc kết quả giao dịch.

---

## 6. Bản đồ source code

| File | Trách nhiệm |
|---|---|
| `TPIOSBootstrap.m` | Constructor của dylib, cài hook ban đầu và gọi entry point. |
| `TPIOSEntry.swift` | Export `TPIOSStart` / `TPIOSStop`; cài cart response hook và start/stop controller. |
| `TPIOSController.swift` | Overlay window pass-through, floating button, menu lifecycle và gesture nút nổi. |
| `FloatingButton.swift` | Giao diện nút nổi. |
| `TPIOSMenu.swift` | Menu 9 nút và màn hình con Mua all (đang nằm chung file). |
| `TPIOSCaoXu.swift` | Panel Cào xu thử nghiệm, lưu tiến độ phiên và log riêng bằng UserDefaults. |
| `TPIOSPanelStyle.swift` | Style nền kính/gradient dùng chung. |
| `TPIOSLog.swift` | Hệ thống log và cửa sổ log. |
| `TPIOSAutoClickPanel.swift` | UI, điểm chạm, lưu cài đặt và scheduler auto-click. |
| `TPIOSTapTest.swift` | Quản lý panel Chạm và cầu nối Swift tới backend C. |
| `CHMTouchBackend.h` / `CHMTouchBackend.m` | API và implementation phát touch UIKit/HID. |
| `TPIOSLocation.swift` | UI bản đồ, tọa độ, địa chỉ và vị trí đã lưu. |
| `TPIOSLocationSpoofHook.swift` | Hook CLLocationManager cho giả lập vị trí. |
| `TPIOSSale.swift` | UI và luồng theo dõi/quét sản phẩm Sale. |
| `TPIOSSaleScanner.swift` | Đọc text/view runtime và trích tên/giá/voucher. |
| `TPIOSSaleData.swift` | Model, voucher math, matcher và persistence Sale. |
| `TPIOSSaleClock.swift` | Đồng hồ nổi. |
| `TPIOSServerTime.swift` | Đồng bộ/ước lượng giờ server Shopee. |
| `TPIOSCartBody.swift` | Thu response cart và parse snapshot giỏ hàng. |
| `TPIOSNetworkLog.swift` | Thu thập URL request Shopee theo thao tác bật bắt mạng. |
| `TPIOSAdBlock.swift` | Quét, lưu profile và áp dụng logic AdBlock. |
| `TPIOSModelFilter.m` | Hook initializer để lọc model theo predicate. |
| `TPIOSGADPresentationBlocker.m` | Chặn một số controller quảng cáo GAD khi present. |
| `TPIOSWebDiagnostics.swift` | Chẩn đoán WKWebView/DOM/resource quảng cáo. |
| `TPIOSReload.swift` | Tìm và kích hoạt cơ chế refresh. |
| `TPIOSAppScanner.swift` | Quét class/bundle liên quan StoreKit. |
| `TPIOSPaymentScanner.swift` | Đọc receipt và trạng thái StoreKit. |

---

## 7. Quy tắc làm việc trên repo

Các quy tắc sau áp dụng cho AI/người tiếp tục phát triển TPIOS:

1. Chỉ làm việc trong đúng repo được yêu cầu; không tự lấy code từ repo khác.
2. Chỉ làm việc trên nhánh `main`; không tạo nhánh mới.
3. Trước khi sửa, kiểm tra trạng thái repo, đọc file và hàm thực tế liên quan; không đoán cấu trúc hoặc API.
4. Ưu tiên diff nhỏ; giữ nguyên chức năng đang chạy tốt; không refactor hoặc thêm dependency không cần thiết.
5. Mặc định một chức năng có một file chính; chỉ tách file khi có lý do dùng chung/kỹ thuật rõ ràng.
6. Menu chính là chuẩn UI tham chiếu: khung thiết kế 240×350 pt, tối thiểu 240×330 pt, radius 24 pt, header 66 pt, resize handle 44 pt, grid 3 cột, padding ngang 14 pt, icon tối đa 58 pt.
7. Không tạo scanner/timer/observer chạy liên tục nếu không cần; tác vụ nặng chỉ chạy khi người dùng yêu cầu hoặc mở chức năng.
8. Log phải có mục đích, có giới hạn; không spam trong vòng lặp.
9. Không tự chạy GitHub Actions/build workflow. Chỉ đọc log hoặc kiểm tra workflow khi được yêu cầu.
10. Khi sửa lỗi build, dựa trên log thực tế; nếu cùng lỗi đã thử 3 lần vẫn chưa giải quyết thì dừng và báo nguyên nhân còn nghi ngờ.
11. Không tuyên bố build/test OK nếu chưa có kết quả xác nhận.
12. Khi chỉnh sửa UI/interaction, kiểm tra touch, kéo, resize, đóng/quay lại và regression liên quan khi có build được người dùng cho phép.

### Chuẩn UI cho panel

- Menu con dùng cùng logic scale, corner radius, header, padding, grid, spacing và resize với menu chính.
- Nút chức năng phải có icon đúng nghĩa, label ngắn và rõ.
- Resize phải scale đồng bộ icon/chữ/layout; không tràn hoặc chồng nội dung.
- Panel kéo bằng header, clamp trong màn hình; có Back/Close khi phù hợp.
- Ô nhập liệu cần co giãn theo khung và có nút xóa nhanh khi thích hợp.

---

## 8. Quy tắc backup

Backup chỉ đại diện cho trạng thái đã được xác nhận build/test OK.

- Tên file backup theo ngày: `BACKUP_YYYY-MM-DD.md`; nếu nhiều bản cùng ngày dùng hậu tố `_v2`, `_v3`…
- Không ghi đè backup cũ.
- Backup mới phải giữ lịch sử cũ và chỉ thêm trạng thái mới đã xác nhận OK.
- Không đưa tính năng đang thử nghiệm/chưa xác nhận vào danh sách hoàn thành.
- Khi khôi phục, đọc backup mới nhất trước và không làm lại phần đã có trong backup.

### Kiểm tra trước khi xác nhận thay đổi

Khi có build được người dùng cho phép, kiểm tra compile/linker, selector conflict, timer/observer, regression chức năng cũ và tương tác UI liên quan. Việc cập nhật tài liệu không phải lý do để tự chạy workflow.

---

## 9. Nguyên tắc cốt lõi

> **Giữ nguyên cái đang chạy OK. Sửa đúng nguyên nhân. Thay đổi ít nhất có thể. Phân biệt rõ code đã có với chức năng đã được kiểm thử. Không tự chạy build/Actions. Ghi lại trạng thái đủ rõ để người khác có thể tiếp tục mà không phải làm lại từ đầu.**
