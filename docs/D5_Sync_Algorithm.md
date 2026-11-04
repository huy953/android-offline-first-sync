# 📘 D5: THUẬT TOÁN ĐỒNG BỘ HAI CHIỀU & PHÂN GIẢI XUNG ĐỘT (LWW)
**Đề tài:** Ứng dụng Android Offline-First với Two-Way Sync Engine  
**Môn học:** Phát triển Ứng dụng Di động (Mobile Programming)  
**Tài liệu chi tiết tương ứng trong Báo cáo:** Chương 3 — Đồng bộ Hai chiều và Xử lý Xung đột Dữ liệu (Xem file `CHUONG_3_DONG_BO_HAI_CHIEU_VA_XU_LY_XUNG_DOT.md`)

---

## 1. NGUYÊN LÝ THUẬT TOÁN LAST-WRITE-WINS (LWW)

Trong mô hình **Offline-First**, thiết bị Client có thể chỉnh sửa dữ liệu khi không có mạng trong nhiều giờ hoặc nhiều ngày. Khi kết nối Internet được thiết lập lại:
1. Nhiều thiết bị có thể cùng chỉnh sửa một bản ghi Task $T$.
2. Để thống nhất trạng thái cuối cùng mà không cần tương tác thủ công từ người dùng, hệ thống sử dụng trường `updated_at` (Unix epoch tính bằng milliseconds kết hợp cơ chế Monotonic Clock: `maxOf(System.currentTimeMillis(), previous + 1)`).
3. **Quy tắc phán quyết:** Bản ghi nào có mốc thời gian `updated_at` lớn hơn (được chỉnh sửa sau cùng) sẽ **chiến thắng** và trở thành dữ liệu chuẩn.
4. **Idempotency (Tính lặp an toàn):** Nếu `incoming.updated_at == existing.updated_at`, hệ thống ghi nhận thành công và đưa vào `applied_ids` mà không ghi đè hay tạo bản ghi trùng lặp.

---

## 2. LƯU ĐỒ THUẬT TOÁN ĐỒNG BỘ PHÍA SERVER (PUSH & PULL)

Khi Client gọi `POST /api/v1/tasks/sync`:

```mermaid
flowchart TD
    Start([Bắt đầu Sync Request]) --> ReadClient[Đọc mảng tasks từ Client]
    ReadClient --> LoopTasks{Lặp qua từng task}
    
    LoopTasks -->|Còn task| CheckExists{Task đã có trong Server DB?}
    CheckExists -->|Chưa có| InsertNew[Thêm mới vào DB\nThêm vào applied_ids]
    CheckExists -->|Đã có| CompareTime{client.updated_at vs server.updated_at}
    
    CompareTime -->|client > server| UpdateServer[Ghi đè bản ghi Server\nThêm vào applied_ids]
    CompareTime -->|client == server| IdempotentKeep[Không ghi đè - Lặp an toàn\nThêm vào applied_ids]
    CompareTime -->|client < server| RejectServer[Từ chối cập nhật - Server mới hơn\nThêm vào ignored_ids]
    
    InsertNew --> LoopTasks
    UpdateServer --> LoopTasks
    IdempotentKeep --> LoopTasks
    RejectServer --> LoopTasks
    
    LoopTasks -->|Hết task| CommitDB[Commit Transaction vào Database]
    CommitDB --> BuildResponse[Đóng gói SyncResult: applied_ids, ignored_ids, server_time]
    BuildResponse --> End([Trả về HTTP 200 OK])
```

---

## 3. CÁC TÌNH HUỐNG KIỂM THỬ THỰC TẾ

1. **Client tạo mới khi Offline:** Server nhận ID UUID v4, thêm mới vào cơ sở dữ liệu.
2. **Client cập nhật task khi Offline:** `client.updated_at` > `server.updated_at` -> Server cập nhật dữ liệu mới.
3. **Hai Client cùng sửa 1 task khi Offline (Xung đột LWW):**
   - Thiết bị A sửa lúc $t_1$, thiết bị B sửa lúc $t_2$ ($t_2 > t_1$).
   - Thiết bị A đồng bộ trước -> Server nhận bản ghi ở $t_1$.
   - Thiết bị B đồng bộ sau -> Do $t_2 > t_1$, Server cập nhật theo bản ghi của Thiết bị B.
   - Khi Thiết bị A đồng bộ lần kế tiếp -> Server gửi bản ghi $t_2$ về cho Thiết bị A cập nhật lại Room DB.
4. **Xóa mềm (Soft Delete / Tombstone):** Task bị xóa có `is_deleted = true`. Thuật toán LWW xử lý cờ này như một bản cập nhật thông thường, lan truyền trạng thái xóa sang các Client khác mà không gây mất dấu lịch sử hay bị tải ngược lại khi đồng bộ.
5. **Chống đua dữ liệu (Race Condition):** Cơ chế CAS `markSyncedIfUnchanged(id, sentUpdatedAt)` ngăn chặn việc người dùng vừa chỉnh sửa vừa nhấn đồng bộ làm mất thay đổi mới.
