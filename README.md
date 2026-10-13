# TPIOS

TPIOS là iOS dylib dùng để thử nghiệm các chức năng UI/runtime injection trên iPhone.

---

## QUY TẮC LÀM VIỆC TRÊN REPO

> Phần này là quy tắc bắt buộc cho bất kỳ AI/người nào đọc và chỉnh sửa repo này. Khi làm việc trong repo, phải đọc phần này trước và làm đúng theo nó.
> Đọc và sửa trực tiếp trên repo đã liên kết những phần cần chỉnh sửa

### 1. Chỉ làm việc trong đúng repo được yêu cầu

- Chỉ chỉnh sửa repo hiện tại khi task yêu cầu.
- Không tự ý kiểm tra, sửa hoặc lấy code từ repo khác nếu chưa được yêu cầu rõ ràng.
- Không tự ý thay đổi các file không liên quan.

### 2. Trước khi sửa phải đọc đúng phần liên quan

- Chỉ đọc các file thực sự liên quan đến lỗi/tính năng đang xử lý.
- Không đọc toàn bộ repo nếu không cần map kiến trúc.
- Xác định đúng file + đúng class/hàm trước khi sửa.

### 3. Khi sửa lỗi từ GitHub Actions

- Đọc log của job bị lỗi.
- Chỉ trích phần `error`, `warning` liên quan trực tiếp và stack trace cần thiết.
- Bỏ qua log build thành công dài dòng.
- Không sửa theo kiểu đoán.

Quy trình:

1. Xác định lỗi.
2. Xác định file/class/hàm gây lỗi.
3. Sửa đúng nguyên nhân.
4. Build lại.
5. Kiểm tra regression.

### 4. Khi chỉnh sửa code

- Ưu tiên diff/patch và thay đổi ít nhất có thể.
- Không viết lại toàn bộ file nếu chỉ cần sửa vài dòng.
- Giữ nguyên code đang chạy tốt.
- Không refactor lớn chỉ để sửa một lỗi nhỏ.
- Không đổi tên class/method/API nếu không cần thiết.

### 5. Mỗi chức năng nên độc lập

### 5.1. Quy tắc số lượng file cho một chức năng

- Không tách một chức năng thành nhiều file chỉ để chia model/parser/store/UI nếu các phần đó chỉ phục vụ duy nhất chức năng đó.
- Mặc định: **một chức năng = một file chính**.
- Chỉ tạo file phụ khi thành phần đó thực sự dùng chung cho nhiều chức năng hoặc có lý do kỹ thuật rõ ràng.
- Khi đã có nhiều file phụ nhưng không còn cần thiết, phải gom về file chính và xóa file thừa.

### 5.2. UI RULE — chuẩn chung từ Menu chính

Menu chính là **UI reference duy nhất**. Mọi menu con và nút bên trong phải dùng đúng thông số/style của Menu chính, không tự tạo chuẩn riêng.

**Thông số hiện tại của Menu chính:**
- Khung thiết kế: `240 × 350 pt`; tối thiểu `240 × 330 pt`.
- Corner radius: `24 pt`.
- Header: `66 pt` theo tỷ lệ khung.
- Resize handle: `44 pt`.
- Grid: `3 cột`.
- Padding ngang: `14 pt`.
- Khoảng cách ngang: `10 pt`; dọc: `8 pt`.
- Icon tối đa: `58 pt`; bo góc icon theo tỷ lệ `28%` kích thước icon.
- Icon → label: `3 pt`.
- Label: `15 pt` theo tỷ lệ; font `13 pt`, semibold theo tỷ lệ.

**Quy tắc:**
- Menu con mở lên phải dùng cùng kích thước/logic scale, corner radius, header, padding, grid, spacing, resize và cách căn của Menu chính.
- Nút dùng dạng icon vuông bo góc như Menu chính; giữ cùng hệ gradient/style, không tự đổi kiểu.
- **Mọi nút chức năng phải có một icon bên trong nút phù hợp, dễ nhận biết và thể hiện đúng chức năng; không tạo nút chức năng chỉ có chữ hoặc icon không liên quan.**
- Icon, font, label và khoảng cách phải theo chuẩn trên; tên đặt ngoài icon, ngắn gọn nhưng dễ hiểu.
- Resize phải scale đồng bộ icon, chữ, spacing và layout; không tràn, cắt hoặc chồng nội dung; giữ minimum size hợp lý.
- Menu phải kéo bằng header và clamp trong màn hình; có Back và X/Close khi phù hợp.
- Ô nhập liệu phải co giãn theo khung và có X xóa nhanh.
- Không tự đặt size, màu, font, spacing hoặc layout khác cho từng menu. Muốn đổi chuẩn chung phải sửa UI RULE trước.

### 6. Không chạy tác vụ nặng liên tục

Đặc biệt tránh:

- Scanner chạy nền liên tục.
- View traversal liên tục.
- Observer/timer không cần thiết.
- Quét lại mỗi lần mở app nếu không cần.

Tác vụ nặng chỉ chạy khi cần hoặc khi người dùng chủ động yêu cầu.

### 7. Log phải có mục đích

- Log quan trọng dùng `TPIOSLog`.
- Không spam log trong timer/vòng lặp.
- Khi debug phải ghi đủ thông tin để xác định nguyên nhân nhưng không ghi vô hạn.

### 8. Task đơn giản thì xử lý trực tiếp

Các việc như:

- Fix typo.
- Đổi tên biến/file/class theo yêu cầu.
- Sửa path.
- Cập nhật README.

Không cần phân tích dài hoặc thay đổi kiến trúc.

### 9. Giới hạn vòng lặp sửa lỗi

Nếu cùng một lỗi đã sửa và build vẫn fail sau **3 lần thử**:

- Dừng sửa tiếp.
- Tóm tắt lỗi hiện tại.
- Nêu nguyên nhân nghi ngờ dựa trên log.
- Không tiếp tục đoán mò.

### 10. Commit và giải thích

- Commit message ngắn gọn.
- Chỉ mô tả thay đổi mới.
- Không nhắc lại toàn bộ lịch sử project.
- Không tuyên bố "đã hoàn thành/chạy OK" nếu chưa có kết quả build/test xác nhận.

### 11. Không tạo file thừa

- Chỉ tạo file mới khi thực sự cần.
- Không tạo test/log/debug file dư thừa chỉ để thử tạm thời.
- Không để lại file thử nghiệm không dùng.

### 12. Build

Project hiện được build bằng GitHub Actions với:

- Xcode 26.x
- iPhoneOS SDK
- arm64
- iOS 15.0+

Không tự ý thay đổi workflow/build system nếu không liên quan trực tiếp đến task.

### 13. Trước khi xác nhận một thay đổi là OK

Kiểm tra tối thiểu:

- Compile/build.
- Không có lỗi linker.
- Không có selector/method conflict.
- Không có timer/observer chạy vô hạn ngoài ý muốn.
- Không làm thay đổi hành vi của chức năng đang ổn định.
- Nếu có UI/interaction thì kiểm tra cả touch, move, resize và close/back nếu chức năng đó có hỗ trợ.

---

## QUY TẮC BACKUP — RẤT QUAN TRỌNG

Backup dùng để **không bao giờ phải làm lại project từ đầu** nếu repo bị mất, bị khóa hoặc code bị thay đổi ngoài ý muốn.

### Khi người dùng nói: "backup hiện tại"

Phải hiểu là:

> Backup đúng trạng thái mới nhất **đang chạy OK/đã được xác nhận OK tại thời điểm backup**.

Không backup code đang thử nghiệm hoặc chưa build/test thành công.

### Cách đặt backup

Mỗi backup phải có ngày tháng năm:

`BACKUP_YYYY-MM-DD.md`

Ví dụ:

`BACKUP_2026-09-27.md`

Nếu cần nhiều backup trong cùng ngày thì dùng:

`BACKUP_2026-09-27_v2.md`

Không ghi đè backup cũ.

### Nguyên tắc giữ lịch sử backup

- Backup mới phải giữ nguyên toàn bộ nội dung backup trước đó.
- Chỉ **thêm phần trạng thái hiện tại mới đã chạy OK**.
- Không xóa phần lịch sử cũ.
- Không sửa lại lịch sử cũ chỉ vì code hiện tại đã thay đổi.
- Không đưa chức năng đang thử/nghiên cứu nhưng chưa chạy OK vào phần "đã hoàn thành".
- Mỗi backup phải ghi rõ ngày và trạng thái để nhìn vào là biết project đã đi tới đâu.

### Khi khôi phục

Nếu repo bị mất hoặc bị khóa:

1. Đọc backup mới nhất.
2. Xác định trạng thái cuối cùng đã xác nhận OK.
3. Khôi phục theo backup đó.
4. Không quay lại làm lại các chức năng đã có trong backup.
5. Các chức năng mới sau backup được xử lý như phần phát triển tiếp theo.

---

## TRẠNG THÁI HIỆN TẠI

Trạng thái này mô tả **code hiện có trong repo tại thời điểm cập nhật README**.

### UI chính

- Floating Button kiểu AssistiveTouch.
- Có thể kéo nút.
- Chạm nút để mở/đóng menu.
- Menu chính có thể kéo bằng header.
- Menu chính có thể resize bằng góc dưới bên phải.
- Menu được giới hạn trong vùng hiển thị.
- Overlay window cho phép vùng không thuộc UI của TPIOS tiếp tục nhận touch từ app bên dưới.
- Floating Button tự giảm alpha khi không thao tác.

### Menu hiện tại

Menu chính gồm 6 chức năng:

| Nút | Chức năng | File chính |
|---|---|---|
| **Vị trí** | Mở giao diện quản lý vị trí, bản đồ, tọa độ và dữ liệu vị trí đã lưu | `TPIOSLocation.swift` |
| **Sale** | Module săn sale Shopee: theo dõi sản phẩm, voucher và giá thực trả | `TPIOSSale.swift` |
| **Xem log** | Mở cửa sổ log TPIOS | `TPIOSLog.swift` |
| **Tắt QC** | Mở giao diện AdBlock/profile và cơ chế chặn quảng cáo đã lưu | `TPIOSAdBlock.swift` |
| **Đồng hồ** | Hiển thị đồng hồ HH:MM:SS và phần mười giây; có thể kéo/resize | `TPIOSSaleClock.swift` |
| **Tải lại trang** | Tìm và kích hoạt cơ chế refresh của trang/app hiện tại | `TPIOSReload.swift` |

Menu còn hiển thị:

- Tên **TPIOS**.
- **Design By TRUONGPHONG**.
- Trạng thái bằng chấm xanh.
- Ngày dương và ngày âm tham khảo.
- Resize handle ở góc dưới phải.

---

## FILE HIỆN TẠI VÀ CHỨC NĂNG





## NGUYÊN TẮC BẢO TOÀN CHỨC NĂNG

Khi thêm chức năng mới:

1. Không sửa chức năng cũ nếu không liên quan.
2. Không thay đổi UI cũ chỉ để thêm chức năng mới.
3. Ưu tiên tạo module/file riêng **chỉ khi thực sự cần**; nếu các thành phần chỉ thuộc một chức năng thì gom vào file chính.
4. Nếu phải sửa `TPIOSMenu.swift`, chỉ thêm điểm kết nối cần thiết.
5. Nếu phải sửa `TPIOSController.swift`, chỉ sửa phần lifecycle/overlay thật sự liên quan.
6. Sau khi build phải kiểm tra chức năng vừa sửa và các chức năng menu đã hoạt động trước đó.

---

## LỊCH SỬ PHÁT TRIỂN / BACKUP

Phần này dùng để ghi các mốc **đã chạy OK**.

Mỗi lần người dùng yêu cầu **"backup hiện tại"**, thêm một mục mới theo mẫu:

### YYYY-MM-DD — Backup hiện tại

**Trạng thái:** Đã build/test OK.


## NGUYÊN TẮC QUAN TRỌNG NHẤT

> **Giữ nguyên cái đang chạy OK. Sửa đúng nguyên nhân. Thay đổi ít nhất có thể. Chức năng mới phải độc lập. Backup phải có ngày tháng và luôn giữ lại lịch sử cũ. Không để việc repo bị khóa/mất làm project phải bắt đầu lại từ đầu.**
