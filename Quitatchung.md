QUY TẮC TỐI ƯU TOKEN KHI SỬA CODE TRÊN REPO

1. Trước khi sửa, chỉ đọc các file thực sự liên quan đến lỗi/tính năng đang xử lý.
   Không đọc toàn bộ repo trừ khi cần map lại kiến trúc.

2. Khi sửa lỗi từ log GitHub Actions:
   - Chỉ trích phần log liên quan đến lỗi (dòng error/stack trace), 
     bỏ qua log build thành công dài dòng.
   - Xác định đúng file + đúng hàm gây lỗi trước khi sửa, 
     không sửa lan sang các phần không liên quan.

3. Khi chỉnh sửa code:
   - Dùng diff/patch, không viết lại toàn bộ file nếu chỉ sửa vài dòng.
   - Giữ nguyên phần code không liên quan đến lỗi.

4. Giới hạn vòng lặp:
   - Nếu sửa 1 lỗi mà build vẫn fail sau 3 lần thử, dừng lại 
     và tóm tắt nguyên nhân nghi ngờ thay vì tiếp tục đoán mò sửa.

5. Commit message và giải thích:
   - Ngắn gọn, không diễn giải dài dòng lý thuyết Theos/Logos đã biết rồi.
   - Chỉ giải thích phần thay đổi mới, không nhắc lại toàn bộ context cũ.

6. Khi task đơn giản (fix typo, đổi tên biến, sửa path):
   - Xử lý trực tiếp, không cần phân tích sâu hay hỏi lại nhiều bước.

7. Chỉ tạo file mới khi thực sự cần, tránh sinh thêm file test/log dư thừa 
   làm tăng context cho các lần chạy sau.