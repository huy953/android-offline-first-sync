# 📘 D4: TÀI LIỆU ĐẶC TẢ RESTFUL API & HƯỚNG DẪN BACKEND
**Đề tài:** Ứng dụng Android Offline-First với Two-Way Sync Engine  
**Người phụ trách:** Trần Gia Huy - 524H0092 (Backend & Sync Engine Lead)  
**Công nghệ:** Python 3.12, FastAPI, SQLAlchemy 2.0, SQLite (tasks.db), Pydantic v2

---

## 1. TỔNG QUAN HỆ THỐNG API

FastAPI đóng vai trò là máy chủ trung tâm lưu trữ dữ liệu dùng chung và giải quyết xung đột khi các máy Android gửi dữ liệu đồng bộ lên.
- **Base URL:** `http://<server-ip>:8000`
  - Trên máy tính host: `http://localhost:8000`
  - Trên Android Emulator: `http://10.0.2.2:8000`
  - Trên điện thoại thật kết nối cáp USB (đã cấu hình `adb reverse`): `http://localhost:8000`
- **Swagger UI Tài liệu tương tác:** `http://localhost:8000/docs`
- **ReDoc:** `http://localhost:8000/redoc`

---

## 2. QUY ƯỚC DỮ LIỆU (DATA CONTRACT)

Bảng `tasks` (Database tập trung trên FastAPI Server):

| Tên trường | Kiểu dữ liệu | Bắt buộc | Mô tả |
| :--- | :--- | :---: | :--- |
| `id` | `VARCHAR(36)` | Có | Khóa chính dạng chuỗi UUID v4 do Android Client sinh ngẫu nhiên khi tạo ngoại tuyến. |
| `title` | `VARCHAR(255)` | Có | Tiêu đề công việc (không được rỗng). |
| `is_completed` | `BOOLEAN` | Có | `true`: Đã hoàn thành, `false`: Chưa hoàn thành (Mặc định `false`). |
| `is_deleted` | `BOOLEAN` | Có | Cờ xóa logic (**Soft Delete / Tombstone**). Server không xóa vật lý để đồng bộ trạng thái xóa tới các thiết bị khác. |
| `created_at` | `BIGINT` | Có | Mốc thời gian tạo bản ghi ban đầu (Unix epoch milliseconds). |
| `updated_at` | `BIGINT` | Có | Mốc thời gian chỉnh sửa gần nhất (Unix epoch milliseconds) phục vụ giải thuật **Last-Write-Wins (LWW)**. |

> 📌 **Lưu ý:** Các thuộc tính trạng thái đồng bộ cục bộ như `sync_status` (`PENDING`, `SYNCING`, `SYNCED`, `FAILED`) và `last_error` chỉ tồn tại trong Room Database trên thiết bị di động, không lưu trữ trên Server.

---

## 3. DANH SÁCH RESTFUL ENDPOINTS

### 3.1. Nhóm Kiểm tra Trạng thái (Health Check)
- **`GET /health`**
  - Kiểm tra tình trạng hoạt động và tính sẵn sàng của máy chủ.
  - Phản hồi: `{"status": "healthy", "service": "Offline-First Todo Sync Backend"}`

### 3.2. Nhóm CRUD Đơn lẻ
- **`GET /tasks`**
  - Lấy danh sách công việc.
  - *Query Param:* `since` (mặc định = `0`).
    - Khi `since = 0`: Trả về toàn bộ danh sách.
    - Khi `since > 0`: Trả về các bản ghi có `updated_at > since` (phục vụ **Incremental Pull** kéo dữ liệu tăng dần).
- **`POST /tasks`**
  - Tạo mới một công việc đơn lẻ.
  - Trả về mã HTTP `201 Created` cùng chi tiết bản ghi.
- **`GET /tasks/{task_id}`**
  - Truy vấn chi tiết một công việc theo định danh UUID.
- **`PUT /tasks/{task_id}`**
  - Cập nhật thông tin công việc, server tự động nâng mốc `updated_at`.
- **`DELETE /tasks/{task_id}`**
  - Xóa mềm: Chuyển cờ `is_deleted = true`, cập nhật `updated_at`.

### 3.3. Nhóm Đồng bộ Lô & Xử lý Xung đột (Batch Sync & LWW)
- **`POST /tasks/sync`**
  - Tiếp nhận danh sách các bản ghi thay đổi từ Android Client (đẩy theo lô).
  - Áp dụng giải thuật **Last-Write-Wins (LWW)** dựa trên mốc thời gian `updated_at`:
    - `client.updated_at > server.updated_at`: Chấp thuận ghi đè, thêm `id` vào danh sách `applied_ids`.
    - `client.updated_at == server.updated_at`: Idempotency (gửi lặp), giữ nguyên và phản hồi vào `applied_ids`.
    - `client.updated_at < server.updated_at`: Từ chối ghi đè, thêm `id` vào danh sách `ignored_ids`.
  - Phản hồi HTTP 200:
    ```json
    {
      "applied_ids": ["uuid-1", "uuid-2"],
      "ignored_ids": ["uuid-3"],
      "server_time": 1700000050000
    }
    ```

---

## 4. DỮ LIỆU MẪU KHỞI TẠO (SAMPLE SEED DATA)

Để phục vụ việc kiểm thử, đối soát và đánh giá bài nộp độc lập mà không bị phụ thuộc vào trạng thái cơ sở dữ liệu hiện tại, dự án cung cấp bộ dữ liệu mẫu tiêu chuẩn tại:
📁 **`backend/sample_data.json`**

### 4.1. Nội dung dữ liệu mẫu tiêu chuẩn
```json
[
  {
    "id": "11111111-1111-4111-8111-111111111111",
    "title": "Nghiên cứu kiến trúc Offline-First cho Android",
    "is_completed": true,
    "is_deleted": false,
    "created_at": 1700000000000,
    "updated_at": 1700000000000
  },
  {
    "id": "22222222-2222-4222-8222-222222222222",
    "title": "Thiết kế cơ sở dữ liệu Room và SQLite",
    "is_completed": true,
    "is_deleted": false,
    "created_at": 1700000010000,
    "updated_at": 1700000010000
  },
  {
    "id": "33333333-3333-4333-8333-333333333333",
    "title": "Cài đặt thuật toán Last-Write-Wins (LWW) giải quyết xung đột",
    "is_completed": false,
    "is_deleted": false,
    "created_at": 1700000020000,
    "updated_at": 1700000020000
  },
  {
    "id": "44444444-4444-4444-8444-444444444444",
    "title": "Kiểm thử kịch bản mạng chập chờn và rớt gói tin (TC05)",
    "is_completed": false,
    "is_deleted": false,
    "created_at": 1700000030000,
    "updated_at": 1700000030000
  },
  {
    "id": "55555555-5555-4555-8555-555555555555",
    "title": "Đánh giá hiệu năng đồng bộ lô (Batching 100 items)",
    "is_completed": false,
    "is_deleted": false,
    "created_at": 1700000040000,
    "updated_at": 1700000040000
  }
]
```

### 4.2. Hướng dẫn nạp / tái lập dữ liệu mẫu
Khi cần nạp mới hoặc khôi phục lại dữ liệu mẫu ban đầu:
1. Mở cửa sổ dòng lệnh tại thư mục `backend/`.
2. Kích hoạt môi trường ảo: `.\venv\Scripts\Activate.ps1`
3. Thực thi script nạp:
   ```bash
   python seed.py
   ```
4. Hệ thống sẽ tự động tạo bảng (nếu chưa có) và đồng bộ toàn bộ dữ liệu mẫu vào file `tasks.db`. Ngoài ra, script `CHAY_DEMO.bat` tại thư mục gốc cũng đã được cấu hình tự động kiểm tra và nạp dữ liệu mẫu trước khi khởi động server.
