# Kế hoạch & Checkpoint — Chạm Cào xu Lazada

Cập nhật: 2026-11-17  
Repo: `Truongpink/Tpios` · Nhánh duy nhất được phép: `main`  
File automation chính: `TPIOSCaoXu.swift`

## 1. Mục đích và nguyên tắc bảo toàn

Tài liệu này là sổ tiến độ chuẩn của tính năng Cào xu. Mọi phiên làm việc tiếp theo phải đọc tài liệu này trước khi sửa code và cập nhật trạng thái sau mỗi lần kiểm thử.

**Không làm mất chức năng đã chạy được:**
- Không viết lại toàn bộ luồng automation chỉ để sửa một lỗi cuộn.
- Không sửa Chạm thủ công, Sale hoặc module ngoài phạm vi Cào xu.
- Trước mỗi lần sửa: fetch phiên bản mới nhất từ `main`, đọc đúng hàm liên quan, kiểm tra SHA; không dựa vào code hoặc SHA cũ trong hội thoại.
- Mỗi thay đổi phải có phạm vi nhỏ, ghi rõ chức năng nào bị tác động và kiểm tra hồi quy các mục đã xác nhận hoạt động.
- Không xóa selector, log chẩn đoán, cơ chế HID, nhận diện nhiệm vụ hoặc retry đang có nếu chưa chứng minh được chúng là nguyên nhân lỗi.
- Chỉ dùng nhánh `main`; không tạo nhánh.
- Không chạy GitHub Actions/Codemagic/build nếu chưa được anh cho phép rõ ràng.

## 2. Checkpoint hiện tại

**Mốc mã nguồn:** commit `2b356fe56c3d2b87de47f41cc0b1e60712f37fd5`  
**Blob `TPIOSCaoXu.swift`:** `61b48bbca154c511ef3b62a53a24d11af3ea334c`  
**Trạng thái:** đã fetch xác minh file trên `main`; chưa chạy build và chưa có xác nhận runtime cho các thay đổi mới.

Checkpoint này giữ nguyên selector/HID Nhận xu đã được người dùng xác nhận hoạt động; bổ sung nhận diện hộp thoại có tiêu đề chứa số xu và nút `OK`, chạm OK bằng HID rồi mới xác minh trạng thái nhận. Tìm nút `Kiếm thêm` bằng nhãn hiển thị chính xác trên toàn DOM và không còn phụ thuộc card Điểm danh phải đang hiển thị nếu URL Điểm danh đã được xác nhận. Các thay đổi này mới ở mức code, cần runtime test. Phần cuộn danh sách vẫn đang lỗi và **không đánh dấu hoàn thành**.

### Trạng thái chức năng

| Hạng mục | Trạng thái | Bằng chứng / ghi chú |
|---|---|---|
| Chạm tay nút Điểm danh và ghi DOM | 🟢 Đã ghi nhận | Log thực tế có selector `#lazcoins-check-in-button` và DOM chain |
| Chạm tay nút Nhận và ghi DOM | 🟢 Đã ghi nhận | Log thực tế có selector `.mission-item-btn-claim` |
| Tự chạm nút Nhận xu | 🟢 Người dùng xác nhận hoạt động | Xác nhận mới nhất: “Chạm nhận xu được rồi” |
| Nhận diện nút Nhận bằng `.mission-item-btn-claim` | 🟢 Có trong mã | Được bổ sung vào các bước quét/xác minh claim |
| Nhận diện nút Điểm danh | 🟡 Có selector trong mã | Đã thêm nhận diện và HID tap; cần xác nhận runtime sau build |
| Tự mở Kiếm thêm từ trang Điểm danh | 🟡 Đã nới nhận diện | Tìm nhãn chính xác trên toàn DOM, bỏ điều kiện card Điểm danh còn hiện; cần xác nhận runtime |
| Nhận diện danh sách nhiệm vụ `.mission-item-center` | 🟡 Có trong mã | Đã dùng để xác định trang và đồng bộ tên nhiệm vụ; cần kiểm tra khi trang tải động |
| Đồng bộ tên nhiệm vụ vào danh sách nội bộ | 🟡 Có trong mã | Đã từng ghi nhận đồng bộ số nhiệm vụ; cần kiểm thử lại với danh sách đầy đủ |
| Cuộn đúng vùng danh sách nhiệm vụ | 🔴 Chưa hoạt động đúng | Người dùng xác nhận vẫn cuộn ra trang Điểm danh, không thực hiện nhiệm vụ |
| Tìm và mở từng nhiệm vụ | 🔴 Chưa xác nhận hoàn chỉnh | Cần kiểm tra từ thẻ nhiệm vụ thật đến trang chi tiết |
| Xử lý hộp thoại OK sau khi nhận xu | 🟡 Đã có code | Tìm nút OK trong hộp thoại có nội dung số xu, chạm HID rồi xác minh lại; chưa runtime test |\n| Theo dõi hoàn thành nhiệm vụ | 🔴 Chưa xác nhận | Chỉ đánh dấu hoàn thành sau khi hộp thoại OK đóng và trạng thái nút Nhận đổi; cần kiểm thử |
| Quay lại trang Kiếm thêm sau mỗi nhiệm vụ | 🔴 Chưa ổn định | Lazada có thể đưa về trang Điểm danh; cần xác nhận tự mở lại Kiếm thêm và trở lại danh sách |
| Chọn nhiệm vụ chưa hoàn thành tiếp theo | 🔴 Chưa xác nhận | Không lặp nhiệm vụ đã hoàn tất/đã xử lý |
| Tổng kết khi hết nhiệm vụ | 🔴 Chưa xác nhận | Chỉ kết thúc khi đã quét hết danh sách và không còn nhiệm vụ mới |

Quy ước: 🟢 = người dùng xác nhận chạy được hoặc có bằng chứng runtime rõ; 🟡 = đã có code nhưng chưa xác nhận đủ; 🔴 = đang lỗi/chưa hoàn thành. Không nâng trạng thái chỉ vì code đã được thêm.

## 3. Lộ trình triển khai theo checkpoint

### CP-01 — Giữ nguyên các thao tác đã chạy được
- [x] Nút Nhận xu được nhận diện bằng selector thực tế.
- [x] Người dùng xác nhận chạm Nhận xu hoạt động.
- [ ] Kiểm tra hồi quy: claim vẫn chạm đúng thẻ, không chạm nhầm nhiệm vụ khác.
- Tiêu chí đạt: chạy thử trên danh sách thật và xác nhận xu được Lazada nhận.

### CP-02 — Vào đúng trang Kiếm thêm
- [ ] Bắt đầu automation không làm mất trang Lazada hiện tại.
- [ ] Nhận diện đúng trang Điểm danh bằng selector thực tế.
- [ ] Chạm đúng nút mở Kiếm thêm.
- [ ] Xác nhận URL/trạng thái DOM đã chuyển sang trang có danh sách nhiệm vụ.
- Tiêu chí đạt: log xác nhận `.mission-item-center` xuất hiện trước khi bất kỳ thao tác cuộn/quét nhiệm vụ nào chạy.

### CP-03 — Khóa đúng vùng cuộn của danh sách
- [ ] Chụp chẩn đoán cấu trúc DOM của thẻ nhiệm vụ, ancestor, `overflow-y`, `scrollHeight`, `clientHeight`, `scrollTop`.
- [ ] Xác định đúng scroll container thực tế; không đoán theo `document.scrollingElement`.
- [ ] Chỉ cuộn container đã xác minh chứa danh sách nhiệm vụ.
- [ ] Sau mỗi lần cuộn, xác nhận URL vẫn là trang nhiệm vụ và các thẻ nhiệm vụ vẫn tồn tại.
- [ ] Nếu mất trang hoặc không còn thẻ nhiệm vụ: dừng cuộn, ghi log nguyên nhân; không tự cuộn tiếp trang Điểm danh.
- Tiêu chí đạt: cuộn qua nhiều màn hình, danh sách nhiệm vụ vẫn hiện và các thẻ mới được phát hiện.

### CP-04 — Quét và lập hàng đợi nhiệm vụ
- [ ] Quét toàn bộ thẻ nhiệm vụ, kể cả thẻ tải thêm khi cuộn.
- [ ] Chuẩn hóa tên và loại bỏ trùng lặp.
- [ ] Giữ trạng thái đã hoàn thành/đã thử khi danh sách được đồng bộ lại.
- [ ] Không coi việc nhìn thấy nút hoặc chạm nút là hoàn thành nhiệm vụ.
- Tiêu chí đạt: số lượng và tên nhiệm vụ trong log khớp danh sách Lazada thực tế.

### CP-05 — Mở và thực hiện nhiệm vụ
- [ ] Chọn nhiệm vụ chưa hoàn thành đầu tiên.
- [ ] Xác minh đã rời danh sách và vào đúng trang chi tiết nhiệm vụ.
- [ ] Thực hiện theo loại nhiệm vụ đã nhận diện (tìm kiếm, xem sản phẩm, video, trò chơi, ghé thăm/thử thách…); mỗi loại phải có điều kiện hoàn thành riêng.
- [ ] Không đánh dấu hoàn thành nếu chỉ mới gửi HID.
- Tiêu chí đạt: một nhiệm vụ cụ thể được Lazada xác nhận hoàn thành.

### CP-06 — Quay lại và xử lý tuần tự
- [ ] Sau khi hoàn thành, quay về trang danh sách Kiếm thêm bằng luồng điều hướng đã xác minh.
- [ ] Cập nhật trạng thái nhiệm vụ hoàn thành.
- [ ] Bắt đầu lại từ nhiệm vụ chưa hoàn thành đầu tiên; bỏ qua nhiệm vụ đã hoàn thành.
- [ ] Nếu Lazada yêu cầu bấm Nhận, dùng luồng claim đã hoạt động; nếu trạng thái đã xác nhận hoàn thành và không cần claim thì không bấm thừa.
- Tiêu chí đạt: hoàn thành liên tiếp ít nhất 2 nhiệm vụ khác nhau, quay lại đúng danh sách sau từng nhiệm vụ, không lặp nhiệm vụ.

### CP-07 — Quét hết danh sách và kết thúc an toàn
- [ ] Cuộn đến cuối danh sách bằng đúng container.
- [ ] Chờ nội dung tải thêm rồi quét lại trước khi kết luận hết nhiệm vụ.
- [ ] Chỉ dừng khi không còn thẻ mới và không còn nhiệm vụ chưa hoàn thành.
- [ ] Báo cáo số nhiệm vụ hoàn thành, nhiệm vụ bỏ qua và lý do dừng.
- Tiêu chí đạt: một phiên chạy hoàn chỉnh, không lặp vô hạn, không rời nhầm trang.

## 4. Quy trình kiểm thử và cập nhật tiến độ

Mỗi lần test ghi một mục mới ở phần 5:
1. Commit/blob đang test.
2. Build có thành công hay không (chỉ ghi khi có kết quả thật).
3. Hành động đã thử và kết quả Lazada thực tế.
4. Log quan trọng (đặc biệt URL, số thẻ nhiệm vụ, scroll container, scrollTop/scrollHeight, tên nhiệm vụ, trạng thái điều hướng).
5. Mục nào chuyển 🟡/🔴 sang 🟢; mục nào bị hồi quy.
6. Quyết định checkpoint tiếp theo.

**Quy tắc bảo vệ:** nếu một thay đổi làm hỏng mục 🟢, dừng phát triển tính năng mới; sửa hồi quy trước. Không xóa checkpoint cũ. Mỗi lần cập nhật tài liệu phải giữ lại lịch sử bên dưới.

## 5. Nhật ký checkpoint

### 2026-11-17 — CP-08: Bổ sung xác nhận nhận xu và mở lại Kiếm thêm\n- Commit: `2b356fe56c3d2b87de47f41cc0b1e60712f37fd5`\n- Blob `TPIOSCaoXu.swift`: `61b48bbca154c511ef3b62a53a24d11af3ea334c`\n- Giữ nguyên thao tác chạm `.mission-item-btn-claim` đã được người dùng xác nhận.\n- Bổ sung tìm nút `OK` trong hộp thoại có nội dung số xu; gửi HID DOWN/UP; chờ hộp thoại đóng rồi mới xác minh trạng thái claim.\n- Nới tìm nút `Kiếm thêm` theo nhãn chính xác trên toàn DOM; không bắt buộc card Điểm danh vẫn đang hiển thị nếu URL và lần chạm Điểm danh đã được xác nhận.\n- Trạng thái: đã cập nhật và fetch xác minh source; chưa build/runtime test.\n- Hạng mục cuộn danh sách vẫn 🔴, chưa sửa trong checkpoint này.\n\n### 2026-11-17 — CP-00: Baseline hiện tại
- Commit: `3806a6e8e5d85dd08b1e72c53ebaeb8573b72dfc`
- File: `TPIOSCaoXu.swift`
- Blob: `c8c969c857f555f361b1638ab51dd025b8399e94`
- Đã có: selector nhận xu thực tế, HID claim, nhận diện thẻ nhiệm vụ, logic thử xác định vùng cuộn và chặn cuộn trang khi nút Điểm danh còn hiện.
- Người dùng xác nhận: thao tác Nhận xu hoạt động.
- Lỗi còn lại: cuộn vẫn thoát về trang Điểm danh, không thực hiện nhiệm vụ.
- Build/runtime của commit này: chưa xác nhận trong checkpoint.
- Việc tiếp theo: CP-03 — chẩn đoán DOM và xác định chính xác scroll container trên trang danh sách; không sửa phần claim đang chạy.

## 6. Phạm vi không được tự ý thay đổi
- Chỉ tập trung `TPIOSCaoXu.swift` trừ khi có bằng chứng bắt buộc phải sửa file khác.
- Không thay đổi luồng Chạm thủ công hoặc Sale.
- Không thay đổi selector claim đã được xác nhận hoạt động nếu không có bằng chứng lỗi.
- Không chạy Actions/build khi chưa có sự cho phép rõ ràng.


### 2026-11-17 — CP-09: Sửa lỗi biên dịch Swift từ Actions
- Actions run: `44020154119` · job `133827451603` · bước `Compile Swift sources`.
- Lỗi gốc: ba regex JavaScript dùng `\s` trong Swift multiline string tại dòng 635, 642 và 664 gây `invalid escape sequence in literal`.
- Sửa đúng ba chỗ bằng cách escape thành `\\s` trong source Swift để JavaScript nhận lại `\s` khi chạy.
- Không thay đổi logic nhận diện/chạm Điểm danh, Nhận xu, nút OK, Kiếm thêm hoặc cuộn nhiệm vụ.
- Source đã được cập nhật và fetch xác minh trên `main`; blob mới: `a7f33d2968ee5ed843526bb69c1504a973878931`.
- Commit sửa source: `ff00562402440b6db5c3fc7163e25b7c57389a29`.
- Trạng thái: đã sửa nguyên nhân compile được log chỉ ra; **chưa chạy lại Actions**, chưa xác nhận build pass.


### 2026-11-17 — CP-10: Thu nhỏ khung và tiếp tục từ trang Điểm danh
- Thu nhỏ kích thước mở mặc định của khung Cào xu từ 320 × 520 pt xuống 220 × 300 pt; giữ nguyên khả năng kéo/resize và giới hạn resize hiện tại.
- Sửa điều kiện mở Kiếm thêm: khi automation đang chạy và URL hiện tại trùng URL trang Điểm danh đã lưu, cho phép tìm/chạm nút Kiếm thêm mà không bắt buộc phải có thao tác Điểm danh trong chính phiên hiện tại. Điều này hỗ trợ nút Tiếp tục khi người dùng đã đứng sẵn ở trang xu.
- Không đổi selector .mission-item-btn-claim, luồng nhận xu/OK, thao tác Điểm danh, Chạm thủ công hoặc Sale.
- Source cập nhật trên main; chưa chạy Actions/build và chưa có xác nhận runtime.


### 2026-11-17 — CP-11: Khôi phục luồng chạm Kiếm thêm đã chạy tốt
- Đối chiếu source cũ tại ref 28a67d1: nút Kiếm thêm được tìm trực tiếp bằng selector `.lazcoins-check-in-date`, lấy tâm phần tử và gửi HID DOWN/UP.
- Khôi phục selector DOM cụ thể thay cho quét toàn bộ `body *` theo nhãn chữ và gom ứng viên duy nhất.
- Yêu cầu trang Điểm danh và thẻ Điểm danh hiện diện; giữ nhận diện URL đã lưu, chờ 2 giây sau khi bắt đầu và cơ chế retry 20 giây tối đa 3 lần.
- Bỏ điều kiện so sánh `appWindow()` với `webView.window` vì luồng cũ đã gửi HID trực tiếp theo tọa độ chuyển đổi trong WebView window và không có điều kiện này.
- Không đổi nhận xu, OK, xử lý nhiệm vụ, cuộn danh sách hoặc khung menu.
- Chưa chạy Actions/build; cần kiểm tra runtime sau khi người dùng build.
